package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

@:forward
abstract RealStream<Item>(Stream<Item, Error>) from Stream<Item, Error> to Stream<Item, Error> {
  @:from
  public static inline function promiseOfIdealStream<Item>(p:Promise<IdealStream<Item>>):RealStream<Item>
    return cast Stream.promise(p);
  
  @:from
  public static inline function promiseOfStreamNoise<Item>(p:Promise<Stream<Item, Noise>>):RealStream<Item>
    return cast Stream.promise(p);
    
  @:from
  public static inline function promiseOfRealStream<Item>(p:Promise<RealStream<Item>>):RealStream<Item>
    return cast Stream.promise(p);
  
  @:from
  public static inline function promiseOfStreamError<Item>(p:Promise<Stream<Item, Error>>):RealStream<Item>
    return cast Stream.promise(p);
  
  public function collect():Promise<Array<Item>> {
    var buf = [];
    return this.forEach(function(x) {
      buf.push(x);
      return Resume;
    }).map(function(c) return switch c {
		case Depleted: Success(buf);
		case Failed(e): Failure(e);
		case Halted(_): throw 'unreachable';
	});
  }
}
typedef RealStreamObject<Item> = StreamObject<Item, Error>;
typedef RealStreamBase<Item> = StreamBase<Item, Error>;