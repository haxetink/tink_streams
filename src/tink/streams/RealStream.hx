package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

@:forward @:transitive
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
}

typedef RealStreamObject<Item> = StreamObject<Item, Error>;
