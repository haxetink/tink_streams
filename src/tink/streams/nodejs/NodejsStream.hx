package tink.streams.nodejs;

import tink.streams.Stream;

using tink.CoreApi;

class NodejsStream<T> extends Generator<T, Error> {
  
  function new(target:WrappedReadable<T>) {
    super(Future.async(function (cb) {
      target.read().handle(function (o) cb(switch o {
        case Success(null): End;
        case Success(data): Link(data, new NodejsStream(target));
        case Failure(e): Fail(e);
      }));
    } #if !tink_core_2 , true #end));
  }
  static public function wrap(name, native, onEnd)
    return new NodejsStream(new WrappedReadable(name, native, onEnd));
  
}