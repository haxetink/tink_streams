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
    
  #if cs
  // This is to mitigate an error in the c# generator that it generates paramterized calls
  // with type parameters which is not defined in scope
  // similar to https://github.com/HaxeFoundation/haxe/issues/6833
  @:from static public function dirtyFlatten<Item>(f:Future<Stream<Item, Error>>):Stream<Item, Error>
    return new FutureStream(f);
  #end
    
  @:from static public function flatten<Item, Quality>(f:Future<Stream<Item, Quality>>):Stream<Item, Quality>
    return new FutureStream(f);
  
  #if cs
  // This is to mitigate an error in the c# generator that it generates paramterized calls
  // with type parameters which is not defined in scope
  // similar to https://github.com/HaxeFoundation/haxe/issues/6833
  @:from static public function dirtyPromise<Item>(f:Promise<Stream<Item, Error>>):Stream<Item, Error>
    return dirtyFlatten(f.map(function (o) return switch o {
      case Success(s): s;
      case Failure(e): ofError(e);
    }));
  #end
  
  @:from static inline function promiseIdeal<Item>(f:Promise<IdealStream<Item>>):Stream<Item, Error>
    return cast promise(f);
  
  @:from static inline function promiseReal<Item>(f:Promise<RealStream<Item>>):Stream<Item, Error>
    return cast promise(f);
  
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
  Converted(data:Stream<Out, Quality>):RegroupResult<Out, Quality>;
  Terminated(data:Option<Stream<Out, Quality>>):RegroupResult<Out, Quality>;
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

private class RegroupStream<In, Out, Quality> extends CompoundStream<Out, Quality> {
  public function new(source:Stream<In, Quality>, f:Regrouper<In, Out, Quality>, ?prev) {
    if(prev == null) prev = Empty.make();
    
    var ret = null;
    var terminated = false;
    var buf = [];
    var next = Stream.flatten(source.forEach(function(item) {
      buf.push(item);
      return f.apply(buf, Flowing).map(function (o):Handled<Error> return switch o {
        case Converted(v):
          ret = v;
          Finish;
        case Terminated(v):
          ret = v.or(Empty.make);
          terminated = true;
          Finish;
        case Untouched:
          Resume;
        case Errored(e):
          Clog(e);
      });
    }).map(function(o):Stream<Out, Quality> return switch o {
      case Failed(e): Stream.ofError(e);
      case Depleted if(buf.length == 0): Empty.make();
      case Depleted:
        Stream.flatten(f.apply(buf, Ended).map(function(o) return switch o {
          case Converted(v): v;
          case Terminated(v): v.or(Empty.make);
          case Untouched: Empty.make();
          case Errored(e): cast Stream.ofError(e);
        }));
      case Halted(_) if(terminated): ret;
      case Halted(rest): new RegroupStream(rest, f, ret);
      case Clogged(e, rest): cast new CloggedStream(e, cast rest);
    }));
    // TODO: get rid of those casts in this function
    
    super([prev, next]);
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

private class CloggedStream<Item> extends StreamBase<Item, Error> {
  
  var rest:Stream<Item, Error>;
  var error:Error;
  
  public function new(rest, error) {
    this.rest = rest;
    this.error = error;
  }
  
  override function next():Future<Step<Item, Error>>
    return Future.sync(Step.Fail(error));
    
  override public function forEach<Safety>(handler:Handler<Item,Safety>):Future<Conclusion<Item, Safety, Error>>
    return Future.sync(cast Conclusion.Clogged(error, rest));
  
}

private class ErrorStream<Item> extends StreamBase<Item, Error> {
  
  var error:Error;
  
  public function new(error)
    this.error = error;
  
  override function next():Future<Step<Item, Error>>
    return Future.sync(Step.Fail(error));
    
  override public function forEach<Safety>(handler:Handler<Item,Safety>):Future<Conclusion<Item, Safety, Error>>
    return Future.sync(Conclusion.Failed(error));
  
}

interface StreamObject<Item, Quality> {
  /**
   *  `true` if there is no data in this stream
   */
  var depleted(get, never):Bool;
  function next():Future<Step<Item, Quality>>;
  /**
   *  Create a new stream by performing an N-to-M mapping
   */
  function regroup<Ret>(f:Regrouper<Item, Ret, Quality>):Stream<Ret, Quality>;
  /**
   *  Create a new stream by performing an 1-to-1 mapping
   */
  function map<Ret>(f:Mapping<Item, Ret, Quality>):Stream<Ret, Quality>;
  /**
   *  Create a filtered stream
   */
  function filter(f:Filter<Item, Quality>):Stream<Item, Quality>;
  function retain():Void->Void;
  /**
   *  Create an IdealStream.
   *  The stream returned from the `rescue` function will be recursively rescued by the same `rescue` function
   */
  function idealize(rescue:Error->Stream<Item, Quality>):IdealStream<Item>;
  /**
   *  Append another stream after this
   */
  function append(other:Stream<Item, Quality>):Stream<Item, Quality>;
  /**
   *  Prepend another stream before this
   */
  function prepend(other:Stream<Item, Quality>):Stream<Item, Quality>;
  function blend(other:Stream<Item, Quality>):Stream<Item, Quality>;
  function decompose(into:Array<Stream<Item, Quality>>):Void;
  /**
   *  Iterate this stream.
   *  The handler should return one of the following values (or a `Future` of it)
   *  - Backoff: stop the iteration before the current item
   *  - Finish: stop the iteration after the current item
   *  - Resume: continue the iteration
   *  - Clog(error): produce an error
   *  @return A conclusion that indicates how the iteration was ended
   *  - Depleted: there are no more data in the stream
   *  - Failed(err): the stream produced an error
   *  - Halted(rest): the iteration was halted by `Backoff` or `Finish`
   *  - Clogged(err): the iteration was halted by `Clog(err)`
   */
  function forEach<Safety>(handle:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>>;
  /**
   *  Think Lambda.fold()
   */
  function reduce<Safety, Result>(initial:Result, reducer:Reducer<Item, Safety, Result>):Future<Reduction<Item, Safety, Quality, Result>>;
}

class Empty<Item, Quality> extends StreamBase<Item, Quality> {
  
  function new() {}
  
  override function get_depleted()
    return true;
    
  override function next():Future<Step<Item, Quality>>
    return Future.sync(Step.End);
    
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
      apply: function (i:Array<In>, _) return n(i[0]).next(function(o) return Converted(Stream.single(o))).recover(Errored),
    });
    
  @:from static function ofAsync<In, Out, Quality>(f:In->Future<Out>):Mapping<In, Out, Quality>
    return new Mapping({
      apply: function (i:Array<In>, _) return f(i[0]).map(function(o) return Converted(Stream.single(o))),
    });
    
  @:from static function ofSync<In, Out>(f:In->Outcome<Out, Error>):Mapping<In, Out, Error>
    return new Mapping({
      apply: function (i:Array<In>, _) return Future.sync(switch f(i[0]) {
        case Success(v): Converted(Stream.single(v));
        case Failure(e): Errored(e);
      }),
    });
    
  @:from static function ofPlain<In, Out, Quality>(f:In->Out):Mapping<In, Out, Quality>
    return new Mapping({
      apply: function (i:Array<In>, _) return Future.sync(Converted(Stream.single(f(i[0])))),
    });
    
}

abstract Filter<T, Quality>(Regrouper<T, T, Quality>) to Regrouper<T, T, Quality> {
  
  inline function new(o)
    this = o;    
  
  @:from static function ofNext<T>(n:Next<T, Bool>):Filter<T, Error>
    return new Filter({
      apply: function (i:Array<T>, _) return n(i[0]).next(function (matched) return Converted(if (matched) Stream.single(i[0]) else Empty.make())).recover(Errored),
    });
    
  @:from static function ofAsync<T, Quality>(f:T->Future<Bool>):Filter<T, Quality>
    return new Filter({
      apply: function (i:Array<T>, _) return f(i[0]).map(function (matched) return Converted(if (matched) Stream.single(i[0]) else Empty.make())),
    });
    
  @:from static function ofSync<T>(f:T->Outcome<Bool, Error>):Filter<T, Error>
    return new Filter({
      apply: function (i:Array<T>, _) return Future.sync(switch f(i[0]) {
        case Success(v): Converted(if(v)Stream.single(i[0]) else Empty.make());
        case Failure(e): Errored(e);
      }),
    });
    
  @:from static function ofPlain<T, Quality>(f:T->Bool):Filter<T, Quality>
    return new Filter({
      apply: function (i:Array<T>, _) return Future.sync(Converted(if (f(i[0])) Stream.single(i[0]) else Empty.make())),
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
      
  public function next():Future<Step<Item, Quality>> {
    throw 'not implemented';
    // var item = null;
    // return this.forEach(function(i) {
    //   item = i;
    //   return Finish;
    // }).map(function(o):Step<Item, Quality> return switch o {
    //   case Depleted: End;
    //   case Halted(rest): Link(item, rest);
    //   case Failed(e): Fail(e);
    // });
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
  
  public function blend(other:Stream<Item, Quality>):Stream<Item, Quality>
    return 
      if (depleted) other;
      else new BlendStream(this, other);
    
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
  
  override function next():Future<Step<Item, Noise>>
    return target.next().flatMap(function(v) return switch v {
      case Fail(e): rescue(e).idealize(rescue).next();
      default: Future.sync(cast v);
    });
    
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
    
  override function next():Future<Step<Item, Quality>>
    return Future.sync(Link(value.get(), Empty.make()));
    
  override public function forEach<Safety>(handle:Handler<Item,Safety>)
    return handle.apply(value).map(function (step):Conclusion<Item, Safety, Quality> return switch step {
      case BackOff:
        Halted(this);
      case Finish:
        Halted(Empty.make());
      case Resume:
        Depleted;
      case Clog(e):
        Clogged(e, this);
    });
}

abstract Handler<Item, Safety>(Item->Future<Handled<Safety>>) {
  inline function new(f) 
    this = f;

  public inline function apply(item):Future<Handled<Safety>>
    return this(item);
    
  @:from static function ofSafeSync<Item>(f:Item->Handled<Noise>):Handler<Item, Noise>
    return new Handler(function (i) return Future.sync(f(i)));
    
  @:from static function ofUnknownSync<Item, Q>(f:Item->Handled<Q>):Handler<Item, Q>
    return new Handler(function (i) return Future.sync(f(i)));
    
  @:from static function ofSafe<Item>(f:Item->Future<Handled<Noise>>):Handler<Item, Noise>
    return new Handler(f);
    
  @:from static function ofUnknown<Item, Q>(f:Item->Future<Handled<Q>>):Handler<Item, Q>
    return new Handler(f);
}

abstract Reducer<Item, Safety, Result>(Result->Item->Future<ReductionStep<Safety, Result>>) {
  inline function new(f) 
    this = f;

  public inline function apply(res, item):Future<ReductionStep<Safety, Result>>
    return this(res, item);
    
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

#if (java || cs)
private abstract Parts<I, Q>(Array<Dynamic>) {
  public var length(get, never):Int;
    inline function get_length() return this.length;

  public function new(parts:Array<Stream<I, Q>>)
    this = parts;

  @:arrayAccess function get(index:Int):Stream<I, Q>
    return this[index];

  @:arrayAccess function set(index:Int, value:Stream<I, Q>):Stream<I, Q>
    return this[index] = value;

  public function copy():Parts<I, Q>
    return new Parts(cast this.copy());

  public function slice(start:Int, ?end:Int):Parts<I, Q>
    return new Parts(cast this.slice(start, end));
  
  @:from static function ofArray<I, Q>(a:Array<Stream<I, Q>>)
    return new Parts<I, Q>(a);
}
#else
private typedef Parts<I, Q> = Array<Stream<I, Q>>;
#end

private class CompoundStream<Item, Quality> extends StreamBase<Item, Quality> {
  
  var parts:Parts<Item, Quality>;
  
  function new(parts)
    this.parts = parts;
    
  override function get_depleted()
    return switch parts.length {
      case 0: true;
      case 1: parts[0].depleted;
      default: false;
    }
    
  override function next():Future<Step<Item, Quality>> {
    return if(parts.length == 0) Future.sync(Step.End);
    else parts[0].next().flatMap(function(v) return switch v {
      case End if(parts.length > 1): parts[1].next();
      case Link(v, rest):
        var copy = parts.copy();
        copy[0] = rest;
        Future.sync(Link(v, new CompoundStream(copy)));
      default: Future.sync(v);
    });
  }
  
  override public function decompose(into:Array<Stream<Item, Quality>>):Void 
    for (p in parts)
      p.decompose(into);
  
  override public function forEach<Safety>(handler:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>> 
    return Future.async(consumeParts.bind(cast parts, handler, _));
      
  static function consumeParts<Item, Quality, Safety>(parts:Parts<Item, Quality>, handler:Handler<Item, Safety>, cb:Conclusion<Item, Safety, Quality>->Void) 
    if (parts.length == 0)
      cb(Depleted);
    else
      (parts[0]:Stream<Item, Quality>).forEach(handler).handle(function (o) switch o {
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

class FutureStream<Item, Quality> extends StreamBase<Item, Quality> {
  var f:Future<Stream<Item, Quality>>;
  public function new(f)
    this.f = f;
    
  override function next():Future<Step<Item, Quality>>
    return f.flatMap(function(s) return s.next());
    
  override public function forEach<Safety>(handler:Handler<Item, Safety>) {
    return Future.async(function (cb) {
      f.handle(function (s) s.forEach(handler).handle(cb));
    });
  }
}

class BlendStream<Item, Quality> extends Generator<Item, Quality> {
  
  public function new(a:Stream<Item, Quality>, b:Stream<Item, Quality>) {
    var first = null;
    
    function wait(s:Stream<Item, Quality>) {
      return s.next().map(function(o) {
        if(first == null) first = s;
        return o;
      });
    }
    
    var n1 = wait(a);
    var n2 = wait(b);
    
    super(Future.async(function(cb) {
      n1.first(n2).handle(function(o) switch o {
        case Link(item, rest):
          cb(Link(item, new BlendStream(rest, first == a ? b : a)));
        case End:
          (first == a ? n2 : n1).handle(cb);
        case Fail(e):
          cb(Fail(e));
      });
    }));
    
  }
}


class Generator<Item, Quality> extends StreamBase<Item, Quality> {
  var upcoming:Future<Step<Item, Quality>>;
  
  function new(upcoming) 
    this.upcoming = upcoming;
    
  override function next():Future<Step<Item, Quality>>
    return upcoming;
  
  override public function forEach<Safety>(handler:Handler<Item, Safety>)
    return Future.async(function (cb:Conclusion<Item, Safety, Quality>->Void) 
      upcoming.handle(function (e) switch e {
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

class SignalStream<Item, Quality> extends Generator<Item, Quality> {
	public function new(signal:Signal<Yield<Item, Quality>>) {
		super(signal.nextTime().map(function(o):Step<Item, Quality> return switch o {
			case Data(data): Link(data, new SignalStream(signal));
			case Fail(e): Fail(e);
			case End: End;
		}));
	}
}

enum Yield<Item, Quality> {
	Data(data:Item):Yield<Item, Quality>;
	Fail(e:Error):Yield<Item, Error>;
	End:Yield<Item, Quality>;
}
