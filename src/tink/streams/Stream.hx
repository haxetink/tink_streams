package tink.streams;

import tink.streams.IdealStream;

using tink.CoreApi;

@:forward
abstract Stream<T>(StreamObject<T>) to StreamObject<T> from StreamObject<T> from IdealStream<T> {
  
  public var depleted(get, never):Bool;
    inline function get_depleted()
      return this.depleted();
      
}

class StreamErrorOn<T, S> extends TypedError<{ var cause(default, null):Error; var rest(default, null):S; }> {
  
  public function new(cause:Error, rest:S) {
    super(cause.code, cause.message, cause.pos);
    this.data = {
      cause: cause,
      rest: rest,
    };
  }
  
}

typedef StreamError<T> = StreamErrorOn<T, Stream<T>>;

class Cell<T> extends StreamBase<T> {
  var next:Promise<Pair<T, Stream<T>>>;
  
  public function new(next)
    this.next = next;
  
  override public function forEach(consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>> 
    return progress(this, next, consume);
    
  static public function progress<T>(head:Stream<T>, next:Promise<Pair<T, Stream<T>>>, consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>> 
    return Future.async(function (cb) {
      next.handle(function (step) switch step {
        case Success({ a: item, b: rest }):
          consume(item).handle(function (o) switch o {
            case Success(true):
              rest.forEach(consume).handle(cb);
            case Success(false):
              cb(Success(rest));
            case Failure(e):
              cb(Failure(new StreamError(e, head)));
          });          
        case Failure(e):
          cb(Failure(new StreamError(e, head)));
      });
    });
  
}

interface StreamObject<T> {
  function depleted():Bool;
  function idealize(rescue:StreamError<T>->IdealStream<T>):IdealStream<T>;
  function map<A>(f:Next<T, A>):Stream<A>;
  function filter(f:Next<T, Bool>):Stream<T>;
  function forEach(consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>>;
}

private class FilterStream<T> extends StreamBase<T> {
  var target:Stream<T>;
  var test:Next<T, Bool>;
  
  override public function depleted():Bool 
    return target.depleted;
  
  public function new(target, test) {
    this.target = target;
    this.test = test;
  }
  
  override public function forEach(consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>> 
    return super.forEach(function (item) 
      return test(item).next(function (ok) return if (ok) consume(item) else true)
    );
  
}

private class MapStream<In, Out> extends StreamBase<Out> {
  var target:Stream<In>;
  var transform:Next<In, Out>;
  
  override public function depleted():Bool 
    return target.depleted;
    
  public function new(target, transform) {
    this.target = target;
    this.transform = transform;
  }
  
  override public function forEach(consume:Next<Out, Bool>):Surprise<Stream<Out>, StreamError<Out>> 
    return target.forEach(transform * consume).map(function (o) return switch o {
      case Success(rest): Success(rest.map(transform));
      case Failure(e): Failure(new StreamError(e.data.cause, e.data.rest.map(transform)));
    });
  
}

class StreamBase<T> implements StreamObject<T> {
  
  public function depleted():Bool
    return false;
    
  public function idealize(rescue:StreamError<T>->IdealStream<T>):IdealStream<T>
    return new IdealizeStream(this, rescue);
    
  public function forEach(consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>>
    return throw 'abstract';
    
  public function map<A>(f:Next<T, A>):Stream<A>
    return new MapStream(this, f);
    
  public function filter(f:Next<T, Bool>):Stream<T> 
    return new FilterStream(this, f);
}

private class IdealizeStream<T> extends IdealStreamBase<T> {
  
  var target:Stream<T>;
  var _idealize:StreamError<T>->IdealStream<T>;
  
  public function new(target, idealize) {
    this.target = target;
    this._idealize = idealize;
  }
  
  override public function depleted():Bool
    return target.depleted;  
  
  override public function forEachSafely(consume:T->Future<Bool>):Future<IdealStream<T>>
    return target.forEach(consume).map(function (o) return switch o {
      case Success(stream):
        stream.idealize(_idealize);
      case Failure(e):
        _idealize(e);
    });
}

class CompoundStream<T> extends StreamBase<T> {
  var parts:Array<Stream<T>>;
  
  function new(parts) 
    this.parts = parts;
  
  static function consumeParts<T>(parts:Array<Stream<T>>, consume:Next<T, Bool>, cb:Outcome<Stream<T>, StreamError<T>>->Void) 
    if (parts.length == 0)
      cb(Success((Empty.inst : Stream<T>)));
    else
      parts[0].forEach(consume).handle(function (o) switch o {
        case Success({ depleted: true }):
          
          consumeParts(parts.slice(1), consume, cb);
          
        case Success(rest):
          
          parts = parts.copy();
          parts[0] = rest;
          cb(Success((new CompoundStream(parts) : Stream<T>)));
          
        case Failure(e):
          
          if (e.data.rest.depleted)
            parts = parts.slice(1);
          else {
            parts = parts.copy();
            parts[0] = e.data.rest;
          }
          
          cb(Failure(new StreamError(e.data.cause, new CompoundStream(parts))));
      });
    
  override public function forEach(consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>> 
    return Future.async(consumeParts.bind(parts, consume, _));
  
  static public function of<T>(streams:Array<Stream<T>>):Stream<T> {
    var ret = [];
    for (s in streams)
      switch Std.instance(s, CompoundStream) {
        case null:
          if (!s.depleted)
            ret.push(s);
        case v:
          for (p in v.parts)
            ret.push(p);
      }
    return 
      if (ret.length == 0) Empty.inst;
      else new CompoundStream(ret);
  }
}