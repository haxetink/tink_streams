package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

@:forward
abstract IdealStream<Item>(Stream<Item, Noise>) from Stream<Item, Noise> to Stream<Item, Noise> {
  public function collect():Future<Array<Item>> {
    var buf = [];
    return this.forEach(function(x) {
      buf.push(x);
      return Resume;
    }).map(function(c) return buf);
  }
}

typedef IdealStreamObject<Item> = StreamObject<Item, Noise>;

class IdealStreamBase<Item> extends StreamBase<Item, Noise> {
  override public function idealize(rescue:Error->Stream<Item,Noise>):IdealStream<Item> 
    return this;
}