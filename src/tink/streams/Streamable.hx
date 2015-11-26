package tink.streams;

import haxe.ds.Option;
import tink.streams.Stream;

using tink.CoreApi;

@:forward
abstract Streamable<T>(StreamableObject<T>) from StreamableObject<T> to StreamableObject<T> {
}

interface StreamableObject<T> {
  function stream():Stream<T>;
  function map<R>(transform:T->R):Streamable<R>;
  function mapAsync<R>(transform:T->Future<R>):Streamable<R>;
  function filter(test:T->Bool):Streamable<T>;
  function filterAsync(test:T->Future<Bool>):Streamable<T>;
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