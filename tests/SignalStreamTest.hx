package;

import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

@:asserts
class SignalStreamTest {
  public function new() {}
  public function testNormal() {
    var done = false;
    var a = Signal.trigger();
    var stream = new SignalStream(a.asSignal());
    a.trigger(Data(1));
    a.trigger(Data(2));
    a.trigger(Data(3));

    var i = 0;
    var sum = 0;
    var result = stream.forEach(v -> {
      asserts.assert(++i == v);
      sum += v;
      None;
    });

    a.trigger(Data(4));
    a.trigger(Data(5));
    a.trigger(End);
    a.trigger(Data(6));
    a.trigger(Data(7));

    result.handle(function (x) {
      asserts.assert(x == Done);
      asserts.assert(sum == 15);
      done = true;
    });
    asserts.assert(done);
    return asserts.done();
  }

  public function testError() {
    var done = false;
    var a = Signal.trigger();
    var stream = new SignalStream(a.asSignal());
    a.trigger(Data(1));
    a.trigger(Data(2));
    a.trigger(Data(3));

    var i = 0;
    var sum = 0;
    var result = stream.forEach(v -> {
      asserts.assert(++i == v);
      sum += v;
      None;
    });

    a.trigger(Data(4));
    a.trigger(Data(5));
    a.trigger(Fail(new Error('Failed')));

    result.handle(function (x) {
      asserts.assert(x.match(Failed(_)));
      asserts.assert(15 == sum);
      done = true;
    });
    asserts.assert(done);
    return asserts.done();
  }

  public function testReuse() {
    var a = Signal.trigger();
    var stream = new SignalStream(a.asSignal());
    a.trigger(Data(1));
    a.trigger(Data(2));
    a.trigger(Data(3));
    a.trigger(End);

    var count = 0;
    function iterate() {
      var i = 0;
      var sum = 0;
      stream.forEach(v -> {
        asserts.assert(++i == v);
        sum += v;
        None;
      }).handle(function (x) {
        asserts.assert(x == Done);
        asserts.assert(sum == 6);
        count++;
      });
    }

    iterate();
    iterate();
    iterate();
    asserts.assert(3 == count);
    return asserts.done();
  }
}