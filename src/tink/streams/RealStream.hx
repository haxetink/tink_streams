package tink.streams;

import tink.streams.Stream.StreamObject;

using tink.CoreApi;

typedef RealStream<Item> = Stream<Item, tink.core.Error>;

class RealStreamTools {
  // static public function idealize<T>(s:RealStream<Item>)

}

// private class IdealizedStream<Item> implements StreamObject<Item, Noise> {

//   final stream:RealStream<Item>;
//   final rescue:Error->RealStream<Item>;

//   public function new(stream, rescue) {
//     this.stream = stream;
//     this.rescue = rescue;
//   }

  // public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Noise>>
  //   return
  //     stream.forEach()
// }