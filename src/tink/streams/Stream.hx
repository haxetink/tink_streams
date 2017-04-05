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
    
  @:from static public function ofIterator<Item, Quality>(i:Iterator<Item>):Stream<Item, Quality> {
    return Generator.stream(function next(step) step(if(i.hasNext()) Link(i.next(), Generator.stream(next)) else End));
  }
    
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

enum RegroupStatus<Quality> {
  Flowing:RegroupStatus<Quality>;
  Errored(e:Error):RegroupStatus<Error>;
  Ended:RegroupStatus<Quality>;
}

enum RegroupResult<Out, Quality> {
  Converted(data:Out):RegroupResult<Out, Quality>;
  Swallowed:RegroupResult<Out, Quality>;
  Untouched:RegroupResult<Out, Quality>;
  Errored(e:Error):RegroupResult<Out, Error>;
}

@:forward
abstract Regrouper<In, Out, Quality>(RegrouperBase<In, Out, Quality>) from RegrouperBase<In, Out, Quality> to RegrouperBase<In, Out, Quality> {
  @:from
  public static function ofIgnorance<In, Out, Quality>(f:Array<In>->Future<RegroupResult<Out, Quality>>):Regrouper<In, Out, Quality>
    return {apply: function(i, _) return f(i)};
  @:from
  public static function ofIgnoranceSync<In, Out, Quality>(f:Array<In>->RegroupResult<Out, Quality>):Regrouper<In, Out, Quality>
    return {apply: function(i, _) return Future.sync(f(i))};
  @:from
  public static function ofFunc<In, Out, Quality>(f:Array<In>->RegroupStatus<Quality>->Future<RegroupResult<Out, Quality>>):Regrouper<In, Out, Quality>
    return {apply: f};
  @:from
  public static function ofFuncSync<In, Out, Quality>(f:Array<In>->RegroupStatus<Quality>->RegroupResult<Out, Quality>):Regrouper<In, Out, Quality>
    return {apply: function(i, s) return Future.sync(f(i, s))};
}

private typedef RegrouperBase<In, Out, Quality> = {
  function apply(input:Array<In>, status:RegroupStatus<Quality>):Future<RegroupResult<Out, Quality>>;
}

private class RegroupStream<In, Out, Quality> extends StreamBase<Out, Quality> {
  
  var source:Stream<In, Quality>;
  var buf:Array<In>;
  var f:Regrouper<In, Out, Quality>;
  
  public function new(source, f, ?buf) {
    this.source = source;
    this.buf = buf == null ? [] : buf;
    this.f = f;
  }
  
  inline function reset()
    buf = []; // TODO: use fastest way per platform
  
  override public function forEach<Safety>(handler:Handler<Out, Safety>):Future<Conclusion<Out, Safety, Quality>> {
    var error:Error = null;
    return source.forEach(function (item) {
      buf.push(item);
      return f.apply(buf, Flowing).flatMap(function (o):Future<Handled<Safety>> return switch o {
        case Converted(v):
          reset();
          handler.apply(v);
        case Swallowed:
          reset();
          Future.sync(Resume);
        case Untouched:
          Future.sync(Resume);
        case Errored(e):
          error = e;
          Future.sync(Finish);
      });
    }).flatMap(function (c):Future<Conclusion<Out, Safety, Quality>> {
      function handleRemaining(status:RegroupStatus<Quality>, conclusion:Conclusion<Out, Safety, Quality>) {
        return
          if(buf.length > 0)
            f.apply(buf, status).flatMap(function(o) return switch o {
              case Converted(v):
                handler.apply(v).map(function(o):Conclusion<Out, Safety, Quality> return switch o {
                  case Finish | Resume: conclusion;
                  case BackOff: Halted(new RegroupStream(Stream.single(buf.pop()), f, buf));
                  case Clog(e): Clogged(error, new RegroupStream(Stream.single(buf.pop()), f, buf));
                });
              case Swallowed | Untouched:
                Future.sync(conclusion);
              case Errored(e):
                Future.sync(cast Failed(error));
            });
          else
            Future.sync(conclusion);
      }
          
      return switch c {
        case Depleted:
          if (error == null) handleRemaining(Ended, Depleted);
          else handleRemaining(cast RegroupStatus.Errored(error), cast Conclusion.Failed(error));
        case Failed(e): 
          handleRemaining(cast RegroupStatus.Errored(e), cast Conclusion.Failed(e));
        case Clogged(e, at): Future.sync(Clogged(e, new RegroupStream(at, f, buf)));
        case Halted(rest): Future.sync(Halted(new RegroupStream(rest, f, buf)));
      }
    });
  }
}

enum Handled<Safety> {
  BackOff:Handled<Safety>;
  Finish:Handled<Safety>;
  Resume:Handled<Safety>;
  Clog(e:Error):Handled<Error>;
}

enum Conclusion<Item, Safety, Quality> {
  Halted(rest:Stream<Item, Quality>):Conclusion<Item, Safety, Quality>;
  Clogged(error:Error, at:Stream<Item, Quality>):Conclusion<Item, Error, Quality>;
  Failed(error:Error):Conclusion<Item, Safety, Error>;
  Depleted:Conclusion<Item, Safety, Quality>;
}

enum ReductionStep<Safety, Result> {
  Progress(result:Result):ReductionStep<Safety, Result>;
  Crash(e:Error):ReductionStep<Error, Result>;
}

enum Reduction<Item, Safety, Quality, Result> {
  Crashed(error:Error, at:Stream<Item, Quality>):Reduction<Item, Error, Quality, Result>;
  Failed(error:Error):Reduction<Item, Safety, Error, Result>;  
  Reduced(result:Result):Reduction<Item, Safety, Quality, Result>;
}

private class ErrorStream<Item> extends StreamBase<Item, Error> {
  
  var error:Error;
  
  public function new(error)
    this.error = error;
    
  override public function forEach<Safety>(handler:Handler<Item,Safety>):Future<Conclusion<Item, Safety, Error>>
    return Future.sync(Conclusion.Failed(error));
  
}

interface StreamObject<Item, Quality> {
  var depleted(get, never):Bool;
  function regroup<Ret>(f:Regrouper<Item, Ret, Quality>):Stream<Ret, Quality>;
  function map<Ret>(f:Mapping<Item, Ret, Quality>):Stream<Ret, Quality>;
  function filter(f:Filter<Item, Quality>):Stream<Item, Quality>;
  function retain():Void->Void;
  function idealize(rescue:Error->Stream<Item, Quality>):IdealStream<Item>;
  function append(other:Stream<Item, Quality>):Stream<Item, Quality>;
  function prepend(other:Stream<Item, Quality>):Stream<Item, Quality>;
  function decompose(into:Array<Stream<Item, Quality>>):Void;
  function forEach<Safety>(handle:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>>;
  function reduce<Safety, Result>(initial:Result, reducer:Reducer<Item, Safety, Result>):Future<Reduction<Item, Safety, Quality, Result>>;
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

abstract Mapping<In, Out, Quality>(Regrouper<In, Out, Quality>) to Regrouper<In, Out, Quality> {
  
  inline function new(o)
    this = o;
    
  @:from static function ofNext<In, Out>(n:Next<In, Out>):Mapping<In, Out, Error>
    return new Mapping({
      apply: function (i:Array<In>, _) return n(i[0]).next(Converted).recover(Errored),
    });
    
  @:from static function ofAsync<In, Out, Quality>(f:In->Future<Out>):Mapping<In, Out, Quality>
    return new Mapping({
      apply: function (i:Array<In>, _) return f(i[0]).map(Converted),
    });
    
  @:from static function ofSync<In, Out>(f:In->Outcome<Out, Error>):Mapping<In, Out, Error>
    return new Mapping({
      apply: function (i:Array<In>, _) return Future.sync(switch f(i[0]) {
        case Success(v): Converted(v);
        case Failure(e): Errored(e);
      }),
    });
    
  @:from static function ofPlain<In, Out, Quality>(f:In->Out):Mapping<In, Out, Quality>
    return new Mapping({
      apply: function (i:Array<In>, _) return Future.sync(Converted(f(i[0]))),
    });
    
}

abstract Filter<T, Quality>(Regrouper<T, T, Quality>) to Regrouper<T, T, Quality> {
  
  inline function new(o)
    this = o;    
  
  @:from static function ofNext<T>(n:Next<T, Bool>):Filter<T, Error>
    return new Filter({
      apply: function (i:Array<T>, _) return n(i[0]).next(function (matched) return if (matched) Converted(i[0]) else Swallowed).recover(Errored),
    });
    
  @:from static function ofAsync<T, Quality>(f:T->Future<Bool>):Filter<T, Quality>
    return new Filter({
      apply: function (i:Array<T>, _) return f(i[0]).map(function (matched) return if (matched) Converted(i[0]) else Swallowed),
    });
    
  @:from static function ofSync<T>(f:T->Outcome<Bool, Error>):Filter<T, Error>
    return new Filter({
      apply: function (i:Array<T>, _) return Future.sync(switch f(i[0]) {
        case Success(true): Converted(i[0]);
        case Success(false): Swallowed;
        case Failure(e): Errored(e);
      }),
    });
    
  @:from static function ofPlain<T, Quality>(f:T->Bool):Filter<T, Quality>
    return new Filter({
      apply: function (i:Array<T>, _) return Future.sync(if (f(i[0])) Converted(i[0]) else Swallowed),
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
  
  public function regroup<Ret>(f:Regrouper<Item, Ret, Quality>):Stream<Ret, Quality> 
    return new RegroupStream(this, f);
  
  public function map<Ret>(f:Mapping<Item, Ret, Quality>):Stream<Ret, Quality> 
    return regroup(f);
  
  public function filter(f:Filter<Item, Quality>):Stream<Item, Quality>
    return regroup(f);
  
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

  public function reduce<Safety, Result>(initial:Result, reducer:Reducer<Item, Safety, Result>):Future<Reduction<Item, Safety, Quality, Result>> 
    return Future.async(function (cb:Reduction<Item, Safety, Quality, Result>->Void) {
      forEach(function (item)
        return reducer.apply(initial, item).map(
          function (o):Handled<Safety> return switch o {
            case Progress(v): initial = v; Resume;
            case Crash(e): Clog(e);
          })
      ).handle(function (c) switch c {
        case Failed(e): cb(Failed(e));
        case Depleted: cb(Reduced(initial));
        case Halted(_): throw "assert";
        case Clogged(e, rest): cb(Crashed(e, rest));
      });
    }, true);

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
      case Clog(e):
        Clogged(e, this);
    });
}

abstract Handler<Item, Safety>({ apply: Item->Future<Handled<Safety>> }) {
  inline function new(f) 
    this = { apply: f };

  public inline function apply(item)
    return this.apply(item);
    
  @:from static function ofSafeSync<Item>(f:Item->Handled<Noise>):Handler<Item, Noise>
    return new Handler(function (i) return Future.sync(f(i)));
    
  @:from static function ofUnknownSync<Item, Q>(f:Item->Handled<Q>):Handler<Item, Q>
    return new Handler(function (i) return Future.sync(f(i)));
    
  @:from static function ofSafe<Item>(f:Item->Future<Handled<Noise>>):Handler<Item, Noise>
    return new Handler(f);
    
  @:from static function ofUnknown<Item, Q>(f:Item->Future<Handled<Q>>):Handler<Item, Q>
    return new Handler(f);
}

abstract Reducer<Item, Safety, Result>({ apply: Result->Item->Future<ReductionStep<Safety, Result>> }) {
  inline function new(f) 
    this = { apply: f };

  public inline function apply(res, item)
    return this.apply(res, item);
    
  @:from static function ofSafeSync<Item, Result>(f:Result->Item->ReductionStep<Noise, Result>):Reducer<Item, Noise, Result>
    return new Reducer(function (res, cur) return Future.sync(f(res, cur)));
    
  @:from static function ofUnknownSync<Item, Q, Result>(f:Result->Item->ReductionStep<Q, Result>):Reducer<Item, Q, Result>
    return new Reducer(function (res, cur) return Future.sync(f(res, cur)));
    
  @:from static function ofSafe<Item, Result>(f:Result->Item->Future<ReductionStep<Noise, Result>>):Reducer<Item, Noise, Result>
    return new Reducer(f);

  @:from static function ofPlainSync<Item, Result>(f:Result->Item->Result):Reducer<Item, Noise, Result>
    return new Reducer(function (res, cur) return Future.sync(Progress(f(res, cur))));
    
  @:from static function ofUnknown<Item, Q, Result>(f:Result->Item->Future<ReductionStep<Q, Result>>):Reducer<Item, Q, Result>
    return new Reducer(f);

  @:from static function ofPromiseBased<Item, Result>(f:Result->Item->Promise<Result>)
    return new Reducer(function (res, cur) return f(res, cur).map(function (s) return switch s {
      case Success(r): Progress(r);
      case Failure(e): Crash(e);
    }));
    
}

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

class Generator<Item, Quality> extends StreamBase<Item, Quality> {
  var next:Future<Step<Item, Quality>>;
  
  function new(next) 
    this.next = next;
  
  override public function forEach<Safety>(handler:Handler<Item, Safety>)
    return Future.async(function (cb:Conclusion<Item, Safety, Quality>->Void) 
      next.handle(function (e) switch e {
        case Link(v, then):
          handler.apply(v).handle(function (s) switch s {
            case BackOff:
              cb(Halted(this));
            case Finish:
              cb(Halted(then));
            case Resume:
              then.forEach(handler).handle(cb);
            case Clog(e):
              cb(Clogged(e, this));
          });
        case Fail(e):
          cb(Failed(e));
        case End:
          cb(Depleted);
      }),
  true
    );
  
  static public function stream<I, Q>(step:(Step<I, Q>->Void)->Void) {
    return new Generator(Future.async(step, true));
  }
    
}

enum Step<Item, Quality> {
  Link(value:Item, next:Stream<Item, Quality>):Step<Item, Quality>;
  Fail(e:Error):Step<Item, Error>;
  End:Step<Item, Quality>;
}