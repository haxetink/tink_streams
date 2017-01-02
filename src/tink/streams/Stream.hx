package tink.streams;

import tink.streams.IdealStream;

using tink.CoreApi;

@:forward
abstract Stream<Item, Quality>(StreamObject<Item, Quality>) from StreamObject<Item, Quality> to StreamObject<Item, Quality> {
  
  public var depleted(get, never):Bool;
    inline function get_depleted() 
      return this.depleted;
  
  @:to function dirty():Stream<Item, Error>
    return cast this;
    
  static public function single<Item, Quality>(i:Item):Stream<Item, Quality>
    return new Single(i);
    
  static function generateSync<Item, Quality>(f:Void->Option<Item>)
    return new GeneratorStream(function poll() {
      return switch f() {
        case None: null;
        case Some(v): new Pair<Item, Generator<Item>>(v, poll);
      }
    });
      
  @:from static public function ofIterator<Item, Quality>(i:Iterator<Item>):Stream<Item, Quality> 
    return new GeneratorStream(function poll():Null<Pair<Item, Generator<Item>>> {
      return 
        if (i.hasNext()) new Pair<Item, Generator<Item>>(i.next(), poll);
        else null;
    });
    
  @:from static public function flatten<Item, Quality>(f:Future<Stream<Item, Quality>>):Stream<Item, Quality>
    return new FutureStream(f);
  
  @:from static public function promise<Item, Quality>(f:Promise<Stream<Item, Quality>>):Stream<Item, Error>
    return flatten(f.map(function (o) return switch o {
      case Success(s): s.dirty();
      case Failure(e): ofError(e);
    }));
    
  @:from static public function ofError<Item>(e:Error):Stream<Item, Error>
    return new ErrorStream(e);
    
}

private enum MapFilterResult<T, Quality> {
  Ok(item:T):MapFilterResult<T, Quality>;
  Err(e:Error):MapFilterResult<T, Error>;
  Skip;
}

private typedef MapFilter<In, Out, Quality> = {
  function apply(input:In):Future<MapFilterResult<Out, Quality>>;
}


private class MapFilterStream<In, Out, Quality> extends StreamBase<Out, Quality> {
  
  var source:Stream<In, Quality>;
  var f:MapFilter<In, Out, Quality>;
  
  public function new(source, f) {
    this.source = source;
    this.f = f;
  }
  
  override public function forEach<Safety>(handler:Handler<Out, Safety>):Future<Conclusion<Out, Safety, Quality>> {
    var error:Error = null;
    return source.forEach(function (item) {
      return f.apply(item).flatMap(function (o):Future<Handled<Safety>> return switch o {
        case Ok(v): handler.apply(v);
        case Skip: Future.sync(Resume);
        case Err(e): 
          error = e;
          Future.sync(Finish);
      });
    }).map(function (c):Conclusion<Out, Safety, Quality> return switch c {
      case Depleted:
        if (error == null) Depleted;
        else cast Failed(error);
      case Failed(e): Failed(e);
      case Clogged(e, at): Clogged(e, new MapFilterStream(at, f));
      case Halted(rest): Halted(new MapFilterStream(rest, f));
    });
  }
}

enum Handled<Safety> {
  BackOff:Handled<Safety>;
  Finish:Handled<Safety>;
  Resume:Handled<Safety>;
  Fail(e:Error):Handled<Error>;
}

enum Conclusion<Item, Safety, Quality> {
  Halted(rest:Stream<Item, Quality>):Conclusion<Item, Safety, Quality>;
  Clogged(error:Error, at:Stream<Item, Quality>):Conclusion<Item, Error, Quality>;
  Failed(error:Error):Conclusion<Item, Safety, Error>;
  Depleted:Conclusion<Item, Safety, Quality>;
}

private class ErrorStream<Item> extends StreamBase<Item, Error> {
  
  var error:Error;
  
  public function new(error)
    this.error = error;
    
  override public function forEach<Safety>(handler:Handler<Item,Safety>):Future<Conclusion<Item, Safety, Error>>
    return Future.sync(Failed(error));
  
}

interface StreamObject<Item, Quality> {
  var depleted(get, never):Bool;
  function map<Ret>(f:Mapping<Item, Ret, Quality>):Stream<Ret, Quality>;
  function filter(f:Filter<Item, Quality>):Stream<Item, Quality>;
  function retain():Void->Void;
  function idealize(rescue:Error->Stream<Item, Quality>):IdealStream<Item>;
  function append(other:Stream<Item, Quality>):Stream<Item, Quality>;
  function prepend(other:Stream<Item, Quality>):Stream<Item, Quality>;
  function decompose(into:Array<Stream<Item, Quality>>):Void;
  function forEach<Safety>(handle:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>>;
}

class Empty<Item, Quality> extends StreamBase<Item, Quality> {
  
  function new() {}
  
  override function get_depleted()
    return true;
    
  override public function forEach<Safety>(handler:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>> 
    return Future.sync(Depleted);
    
  static var inst = new Empty<Dynamic, Dynamic>();  
    
  static public inline function make<Item, Quality>():Stream<Item, Quality>
    return (cast inst : Stream<Item, Quality>);
  
}

abstract Mapping<In, Out, Quality>(MapFilter<In, Out, Quality>) to MapFilter<In, Out, Quality> {
  
  inline function new(o)
    this = o;
    
  @:from static function ofNext<In, Out>(n:Next<In, Out>):Mapping<In, Out, Error>
    return new Mapping({
      apply: function (i:In) return n(i).next(Ok).recover(Err),
    });
    
  @:from static function ofAsync<In, Out, Quality>(f:In->Future<Out>):Mapping<In, Out, Quality>
    return new Mapping({
      apply: function (i:In) return f(i).map(Ok),
    });
    
  @:from static function ofSync<In, Out>(f:In->Outcome<Out, Error>):Mapping<In, Out, Error>
    return new Mapping({
      apply: function (i:In) return Future.sync(switch f(i) {
        case Success(v): Ok(v);
        case Failure(e): Err(e);
      }),
    });
    
  @:from static function ofPlain<In, Out, Quality>(f:In->Out):Mapping<In, Out, Quality>
    return new Mapping({
      apply: function (i:In) return Future.sync(Ok(f(i))),
    });
    
}

abstract Filter<T, Quality>(MapFilter<T, T, Quality>) to MapFilter<T, T, Quality> {
  
  inline function new(o)
    this = o;    
  
  @:from static function ofNext<T>(n:Next<T, Bool>):Filter<T, Error>
    return new Filter({
      apply: function (i:T) return n(i).next(function (matched) return if (matched) Ok(i) else Skip).recover(Err),
    });
    
  @:from static function ofAsync<T, Quality>(f:T->Future<Bool>):Filter<T, Quality>
    return new Filter({
      apply: function (i:T) return f(i).map(function (matched) return if (matched) Ok(i) else Skip),
    });
    
  @:from static function ofSync<T>(f:T->Outcome<Bool, Error>):Filter<T, Error>
    return new Filter({
      apply: function (i:T) return Future.sync(switch f(i) {
        case Success(true): Ok(i);
        case Success(false): Skip;
        case Failure(e): Err(e);
      }),
    });
    
  @:from static function ofPlain<T, Quality>(f:T->Bool):Filter<T, Quality>
    return new Filter({
      apply: function (i:T) return Future.sync(if (f(i)) Ok(i) else Skip),
    });
  
}

class StreamBase<Item, Quality> implements StreamObject<Item, Quality> {
  
  public var depleted(get, never):Bool;
    function get_depleted() return false;
  
  var retainCount = 0;
  
  public function retain() {
    retainCount++;
    var retained = true;
    return function () {
      if (retained) {
        retained = false;
        if (--retainCount == 0)
          destroy();
      }
    }
  }
  
  public function map<Ret>(f:Mapping<Item, Ret, Quality>):Stream<Ret, Quality> 
    return new MapFilterStream(this, f);
  
  public function filter(f:Filter<Item, Quality>):Stream<Item, Quality>
    return new MapFilterStream(this, f);
  
  function destroy() {}  
    
  public function append(other:Stream<Item, Quality>):Stream<Item, Quality>
    return 
      if (depleted) other;
      else CompoundStream.of([this, other]);
  
  public function prepend(other:Stream<Item, Quality>):Stream<Item, Quality>
    return 
      if (depleted) other;
      else CompoundStream.of([other, this]);
    
  public function decompose(into:Array<Stream<Item, Quality>>) 
    if (!depleted)
      into.push(this);
      
  public function idealize(rescue:Error->Stream<Item, Quality>):IdealStream<Item> 
    return 
      if (depleted) Empty.make();
      else new IdealizeStream(this, rescue);
          
  public function forEach<Safety>(handler:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>> 
    return throw 'not implemented';
    
}

class IdealizeStream<Item, Quality> extends IdealStreamBase<Item> {
  var target:Stream<Item, Quality>;
  var rescue:Error->Stream<Item, Quality>;
  
  public function new(target, rescue) {
    this.target = target;
    this.rescue = rescue;
  }
  
  override function get_depleted()
    return target.depleted;
  
  override public function forEach<Safety>(handler:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Noise>>
    return 
      Future.async(function (cb:Conclusion<Item, Safety, Noise>->Void)
        target.forEach(handler).handle(function (end) switch end {
          case Depleted: 
            cb(Depleted);
          case Halted(rest): 
            cb(Halted(rest.idealize(rescue)));
          case Clogged(e, at): 
            cb(Clogged(e, at.idealize(rescue)));
          case Failed(e): 
            rescue(e).idealize(rescue).forEach(handler).handle(cb);
        })
      );
  
}

class Single<Item, Quality> extends StreamBase<Item, Quality> {
  var value:Lazy<Item>;
  
  public function new(value) 
    this.value = value;
    
  override public function forEach<Safety>(handle:Handler<Item,Safety>)
    return handle.apply(value).map(function (step):Conclusion<Item, Safety, Quality> return switch step {
      case BackOff:
        Halted(this);
      case Finish | Resume:
        Depleted;
      case Fail(e):
        Clogged(e, this);
    });
}

@:forward
abstract Handler<Item, Safety>({ apply: Item->Future<Handled<Safety>> }) {
  inline function new(f) 
    this = { apply: f };
    
  @:from static function ofSafeSync<Item>(f:Item->Handled<Noise>):Handler<Item, Noise>
    return new Handler(function (i) return Future.sync(f(i)));
    
  @:from static function ofUnsafeSync<Item, Q>(f:Item->Handled<Q>):Handler<Item, Q>
    return new Handler(function (i) return Future.sync(f(i)));
    
  @:from static function ofSafe<Item>(f:Item->Future<Handled<Noise>>):Handler<Item, Noise>
    return new Handler(f);
    
  @:from static function ofUnsafe<Item, Q>(f:Item->Future<Handled<Q>>):Handler<Item, Q>
    return new Handler(f);
    
}

typedef SyncHandler<Item, Safety> = Item->Handled<Safety>;

private class CompoundStream<Item, Quality> extends StreamBase<Item, Quality> {
  
  var parts:Array<Stream<Item, Quality>>;
  
  function new(parts)
    this.parts = parts;
  
  override public function decompose(into:Array<Stream<Item, Quality>>):Void 
    for (p in parts)
      p.decompose(into);
  
  override public function forEach<Safety>(handler:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>> 
    return Future.async(consumeParts.bind(parts, handler, _));
      
  static function consumeParts<Item, Quality, Safety>(parts:Array<Stream<Item, Quality>>, handler:Handler<Item, Safety>, cb:Conclusion<Item, Safety, Quality>->Void) 
    if (parts.length == 0)
      cb(Depleted);
    else
      parts[0].forEach(handler).handle(function (o) switch o {
        case Depleted:
          
          consumeParts(parts.slice(1), handler, cb);
          
        case Halted(rest):
          
          parts = parts.copy();
          parts[0] = rest;
          cb(Halted(new CompoundStream(parts)));
          
        case Clogged(e, at):
          
          if (at.depleted)
            parts = parts.slice(1);
          else {
            parts = parts.copy();
            parts[0] = at;
          }
          
          cb(Clogged(e, new CompoundStream(parts)));
          
        case Failed(e):
          
          cb(Failed(e));
                    
      });  
      
  static public function of<Item, Quality>(streams:Array<Stream<Item, Quality>>):Stream<Item, Quality> {
    
    var ret = [];
    
    for (s in streams)
      s.decompose(ret);
      
    return 
      if (ret.length == 0) Empty.make();
      else new CompoundStream(ret);
  }      
  
}

private class FutureStream<Item, Quality> extends StreamBase<Item, Quality> {
  var f:Future<Stream<Item, Quality>>;
  public function new(f)
    this.f = f;
    
  override public function forEach<Safety>(handler:Handler<Item, Safety>) {
    return Future.async(function (cb) {
      f.handle(function (s) s.forEach(handler).handle(cb));
    });
  }
}

private typedef Generator<T> = Lazy<Null<Pair<T, Generator<T>>>>;

class GeneratorStream<Item, Quality> extends StreamBase<Item, Quality> {
  
  var g:Generator<Item>;
  
  public function new(g)
    this.g = g;
    
  override public function forEach<Safety>(handler:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>> 
    return Future.async(function (cb:Conclusion<Item, Safety, Quality>->Void) {
      function progress(cur:Generator<Item>) {
        var run = true;
        while (run) {
          run = false;
          switch cur.get() {
            case null: cb(Depleted);
            case v: 
              var val = None;
              
              var step = handler.apply(v.a);
              
              step.handle(function (x) val = Some(x)).dissolve();
              
              function next(s:Handled<Safety>) switch s {
                case Resume: progress(v.b);
                case Fail(e): cb(Clogged(e, new GeneratorStream(cur)));
                case Finish: cb(Halted(new GeneratorStream(v.b)));
                case BackOff: cb(Halted(new GeneratorStream(cur)));
              }
              
              switch val {
                case Some(Resume): 
                  cur = v.b;
                  run = true;
                case Some(v): next(v);
                case None: step.handle(next);
              }
          }
        }
      }
      progress(g);
    });
}

class Chained<Item, Quality> extends StreamBase<Item, Quality> {
  var next:Future<Chain<Item, Quality>>;
  
  function new(next) 
    this.next = next;
  
  override public function forEach<Safety>(handler:Handler<Item, Safety>)
    return Future.async(function (cb:Conclusion<Item, Safety, Quality>->Void) 
      next.handle(function (e) switch e {
        case ChainLink(v, then):
          handler.apply(v).handle(function (s) switch s {
            case BackOff:
              cb(Halted(this));
            case Finish:
              cb(Halted(then));
            case Resume:
              then.forEach(handler).handle(cb);
            case Fail(e):
              cb(Clogged(e, this));
          });
        case ChainError(e):
          cb(Failed(e));
        case ChainEnd:
          cb(Depleted);
      }),
  true
    );
  
  static public function stream<I, Q>(step:(Chain<I, Q>->Void)->Void) {
    return new Chained(Future.async(step, true));
  }
    
}

enum Chain<Item, Quality> {
  ChainLink(value:Item, next:Stream<Item, Quality>):Chain<Item, Quality>;
  ChainError(e:Error):Chain<Item, Error>;
  ChainEnd:Chain<Item, Quality>;
}