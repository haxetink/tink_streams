package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

@:forward @:transitive
abstract IdealStream<Item>(Stream<Item, Noise>) from Stream<Item, Noise> to Stream<Item, Noise> {

}

typedef IdealStreamObject<Item> = StreamObject<Item, Noise>;

class IdealStreamBase<Item> extends StreamBase<Item, Noise> {
  override public function idealize(rescue:Error->Stream<Item,Noise>):IdealStream<Item>
    return this;
}