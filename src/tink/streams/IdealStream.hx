package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

typedef IdealStream<Item> = Stream<Item, Noise>;
typedef IdealStreamObject<Item> = StreamObject<Item, Noise>;

class IdealStreamBase<Item> extends StreamBase<Item, Noise> {
  override public function idealize(rescue:Error->Stream<Item,Noise>):IdealStream<Item> 
    return this;
}