package tink.streams;

import haxe.ds.Option;
import tink.streams.Stream;

using tink.CoreApi;

@:forward
abstract Streamable<T>(StreamableObject<T>) from StreamableObject<T> to StreamableObject<T> {
  @:from static public function repeat<A>(stream:Stream<A>):Streamable<A>
    return new StreamRepeatable(stream);
}

interface StreamableObject<T> {
  function stream():Stream<T>;
  function map<R>(transform:T->R):Streamable<R>;
  function mapAsync<R>(transform:T->Future<R>):Streamable<R>;
  function filter(test:T->Bool):Streamable<T>;
  function filterAsync(test:T->Future<Bool>):Streamable<T>;
  function cache():Streamable<T>;
}

class StreamRepeatable<T> extends StreamableBase<T> {
  var buffer:Array<T>;
  var error:Null<Error>;
  var source:Stream<T>;
  
  public function new(source:Stream<T>) {
    super();
    this.buffer = [];
    this.source = new CopyStream(source, function (step) switch step {
      case Data(d): buffer.push(d);
      case End: source = null;
      case Fail(e): source = null; error = e;
    });
  }
  
  override public function cache():Streamable<T>
    return this;
    
  override public function stream():Stream<T>
    return
      if (source != null) new CompoundStream([buffer.iterator(), source]);
      else new IteratorStream(buffer.iterator(), error);
  
}

private class CopyStream<T> extends StreamBase<T> {
  
  var source:Stream<T>;
  var cb:StreamStep<T>->Void;
  
  public function new(source, cb) {
    this.source = source;
    this.cb = cb;
  }
  
  override public function next() {
    var ret = source.next();
    ret.handle(cb);
    return ret;
  }
  
}

class IterableStreamable<T> extends StreamableBase<T> {
  var target:Iterable<T>;
  public function new(target) {
    super();
    this.target = target;
  }
    
  override public function stream():Stream<T>
    return new IteratorStream(target.iterator());
}

class StreamableBase<T> implements StreamableObject<T> {
  
  public function new() { } 
  
  public function cache():Streamable<T>
    return new StreamRepeatable(stream());
  
  public function stream():Stream<T>
    return new IteratorStream([].iterator());
    
  public function map<R>(transform:T->R):Streamable<R>
    return new SimpleStreamable(function () return stream().map(transform));
    
  public function mapAsync<R>(transform:T->Future<R>):Streamable<R>
    return new SimpleStreamable(function () return stream().mapAsync(transform));
    
  public function filter(test:T->Bool):Streamable<T>
    return new SimpleStreamable(function () return stream().filter(test));
    
  public function filterAsync(test:T->Future<Bool>):Streamable<T>
    return new SimpleStreamable(function () return stream().filterAsync(test));
}

private class SimpleStreamable<T> extends StreamableBase<T> {
  
  var getStream:Void->Stream<T>;
  
  public function new(getStream) {
    super();
    this.getStream = getStream;
  }
  
  override public function stream():Stream<T>
    return getStream();
  
}