package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

@:forward
abstract RealStream<Item>(Stream<Item, Error>) from Stream<Item, Error> to Stream<Item, Error> {
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