package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

typedef RealStream<Item> = Stream<Item, Error>;
typedef RealStreamObject<Item> = StreamObject<Item, Error>;
typedef RealStreamBase<Item> = StreamBase<Item, Error>;