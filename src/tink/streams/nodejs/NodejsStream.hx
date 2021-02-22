package tink.streams.nodejs;

import tink.core.Callback;
import js.node.stream.Readable;
import tink.streams.Stream;

using tink.CoreApi;

class NodejsStream<T> {
  static public function wrap<T>(name:String, native:IReadable) {

    function failure(e:Dynamic)
      return Yield.Fail(tink.core.Error.withData('failed to read from $name', e));

    final ended = new Future(yield -> {
      function end(_)
        yield(Yield.End);

      function fail(e:Dynamic)
        yield(failure(e));

      native.on('end', end);
      native.on('close', end);
      native.on('error', fail);

      () -> {
        native.off('end', end);
        native.off('close', end);
        native.off('error', fail);
      }
    });

    final becameReadable = new Signal<Noise>(fire -> {
      native.on('readable', fire);
      () -> native.off('readable', fire);
    });

    return Stream.generate(() -> ended || new Future<Yield<T, Error>>(
      yield -> {
        if (native.readableEnded) {
          yield(End);
          return null;
        }

        final ret = new CallbackLinkRef();

        function attempt()
          try switch native.read() {
            case null:
              ret.link = becameReadable.nextTime().handle(attempt);
            case v:
              yield(Data(v));
          }
          catch (e:Dynamic) yield(failure(e));

        attempt();

        return ret;
      }
    ));

  }

}