package tink.streams;

import tink.streams.IdealStream;

using tink.CoreApi;

@:forward
abstract Stream<T>(StreamObject<T>) to StreamObject<T> from StreamObject<T> from IdealStream<T> {
  
  public var depleted(get, never):Bool;
    inline function get_depleted()
      return this.depleted();
      
}

class StreamError<T> extends TypedError<{
  var cause(default, null):Error;
  var rest(default, null):Stream<T>;
}> {
  public function new(cause:Error, rest:Stream<T>) {
    super(cause.code, cause.message, cause.pos);
    this.data = {
      cause: cause,
      rest: rest,
    };
  }
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