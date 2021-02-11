package;

import tink.streams.IdealStream;
import tink.streams.RealStream;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

@:asserts
class StreamTest {
  public function new() {}
  public function testIterator() {
    var s = Stream.ofIterator(0...100);
    var sum = 0;
    s.forEach(v -> {
      sum += v;
      None;
    }).handle(function (x) {
      asserts.assert(Done == x);
      asserts.assert(4950 == sum);
      asserts.done();
    });
    return asserts;
  }

  public function testMapFilter() {

    var s = Stream.ofIterator(0...100);

    s = s.filter(i -> i % 2 == 0);
    s = s.filter(i -> Success(i % 3 == 0));
    s = s.map(i -> i * 3);
    s = s.filter(i -> Future.sync(i % 5 == 0));
    s = s.filter(i -> Promise.lift(i > 100));
    s = s.map(i -> Success(i << 1));
    s = s.map(i -> Promise.lift(i + 13));
    s = s.map(i -> Future.sync(i - 3));
    s = s.map(i -> i * 2);

    var sum = 0;

    s.forEach(v -> None).handle(function (c) switch c {
      case Failed(_):
      default:
    });

    s.idealize(null).forEach(v -> {
      sum += v;
      return None;
    }).handle(x -> switch x {
      case Done:
        asserts.assert(1840 == sum);
        asserts.done();
      case Stopped(_):
        asserts.fail('Expected "Depleted');
    });
    return asserts;
  }

  public function testMapError() {
    var s = Stream.ofIterator(0...100);
    var mapped = s.map(function(v) return v % 5 == 4 ? Failure(new Error('Fail $v')) : Success(v));
    var sum = 0;

    mapped.forEach(v -> {
      sum += v;
      return None;
    }).handle(function(o) switch o {
      case Failed(_, e):
        asserts.assert(e.message == 'Fail 4');
        asserts.assert(sum == 6);
        asserts.done();
      default:
        asserts.fail('Expected "Failed');
    });

    return asserts;
  }

  // public function testRegroup() {

  //   var s = Stream.ofIterator(0...100);

  //   var sum = 0;
  //   s.regroup(function (i:Array<Int>) return i.length == 5 ? Converted(Stream.single(i[0] + i[4])) : Untouched)
  //     .idealize(null).forEach(function (v) {
  //       sum += v;
  //       return Resume;
  //     })
  //     .handle(function (x) switch x {
  //       case Depleted:
  //         asserts.assert(1980 == sum);
  //       case Halted(_):
  //         asserts.fail('Expected "Depleted"');
  //     });

  //   var sum = 0;
  //   s.regroup(function (i:Array<Int>, s) {
  //     return if(s == Flowing)
  //       i.length == 3 ? Converted(Stream.single(i[0] + i[2])) : Untouched
  //     else
  //       Converted(Stream.single(i[0])); // TODO: test backoff / clog at last step
  //   })
  //     .idealize(null).forEach(function (v) {
  //       sum += v;
  //       return Resume;
  //     })
  //     .handle(function (x) switch x {
  //       case Depleted:
  //         asserts.assert(3333 == sum);
  //       case Halted(_):
  //         asserts.fail('Expected "Depleted"');
  //     });

  //   var sum = 0;
  //   s.regroup(function (i:Array<Int>) return Converted([i[0], i[0]].iterator()))
  //     .idealize(null).forEach(function (v) {
  //       sum += v;
  //       return Resume;
  //     })
  //     .handle(function (x) switch x {
  //       case Depleted:
  //         asserts.assert(9900 == sum);
  //       case Halted(_):
  //         asserts.fail('Expected "Depleted"');
  //     });

  //   var sum = 0;
  //   s.regroup(function (i:Array<Int>, status:RegroupStatus<Noise>) {
  //     var batch = null;

  //     if(status == Ended)
  //       batch = i;
  //     else if(i.length > 3)
  //       batch = i.splice(0, 3); // leave one item in the buf

  //     return if(batch != null)
  //       Converted(batch.iterator(), i)
  //     else
  //       Untouched;
  //   })
  //     .idealize(null).forEach(function (v) {
  //       sum += v;
  //       return Resume;
  //     })
  //     .handle(function (x) switch x {
  //       case Depleted:
  //         asserts.assert(4950 == sum);
  //       case Halted(_):
  //         asserts.fail('Expected "Depleted"');
  //     });

  //   return asserts.done();
  // }

  public function testNested() {
    var n = Stream.ofIterator([Stream.ofIterator(0...3), Stream.ofIterator(3...6)].iterator());
    var s = Stream.flatten(n);
    var sum = 0;

    s.forEach(function (v) {
      sum += v;
      return None;
    }).handle(function (x) {
      asserts.assert(Done == x);
      asserts.assert(15 == sum);
      asserts.done();
    });

    return asserts;
  }

  public function testNestedWithInnerError() {
    var n = Stream.ofIterator([
      Stream.ofIterator(0...3),
      ofOutcomes([Success(3), Failure(new Error('dummy')), Success(5)].iterator()),
      Stream.ofIterator(6...9),
    ].iterator());
    var s = Stream.flatten(n);
    var sum = 0;

    s.forEach(function (v) {
      sum += v;
      return None;
    }).handle(function (x) {
      asserts.assert(x.match(Failed(_)));
      asserts.assert(6 == sum);
      asserts.done();
    });

    return asserts;
  }

  public function depthTest() {
    var s = Stream.single(1);
    for (i in 0...10000)
      s = s.map(f -> f + 1);
    s.forEach(v -> Some(v)).eager().handle(res -> switch res {
      case Stopped(rest, result):
        asserts.assert(result == 10001);
        asserts.done();
      default:
        asserts.fail('Expected `Stopped`');
    });
    return asserts;
  }

  public function testNestedWithOuterError() {
    var n = ofOutcomes([
      Success(Stream.ofIterator(0...3)),
      Failure(new Error('dummy')),
      Success(Stream.ofIterator(6...9)),
    ].iterator());

    var s = Stream.flatten(n);
    var sum = 0;

    s.forEach(function (v) {
      sum += v;
      return None;
    }).handle(function (x) {
      asserts.assert(x.match(Failed(_)));
      asserts.assert(3 == sum);
      asserts.done();
    });

    return asserts;
  }

  // #if !java
  // public function casts() {
  //   var pi1:Promise<IdealStream<Int>> = Promise.NEVER;
  //   var pi2:Promise<Stream<Int, Noise>> = Promise.NEVER;
  //   var pr1:Promise<RealStream<Int>> = Promise.NEVER;
  //   var pr2:Promise<Stream<Int, Error>> = Promise.NEVER;
  //   var r1:RealStream<Int>;
  //   var r2:Stream<Int, Error>;

  //   r1 = pi1;
  //   r2 = pi1;
  //   r1 = pi2;
  //   r2 = pi2;

  //   r1 = pr1;
  //   r2 = pr1;
  //   r1 = pr2;
  //   r2 = pr2;

  //   return asserts.done();
  // }
  // #end

  public function suspend() {

    var triggers = [];
    var s = Stream.generate(() -> {

      var t = new FutureTrigger<Null<Int>>();
      triggers.push(t);
      t.asFuture().map(v -> if (v == null) Yield.End else Data(v));
    });

    var log = [];
    var res = s.forEach(v -> { log.push(v); None; });
    var active = res.handle(function () {});

    function progress()
      triggers[triggers.length - 1].trigger(triggers.length - 1);

    for (i in 0...5)
      progress();

    active.cancel();

    progress();

    res.eager();
    triggers[triggers.length - 1].trigger(null);
    asserts.assert(res.status.match(Ready(_.get() => Done)));

    asserts.assert(log.join(',') == [for (i in 0...triggers.length - 1) i].join(','));

    return asserts.done();
  }

  static public var verbose = false;

  public function laziness() {

    var triggers = [],
        counter = 0;
    var s = Stream.generate(() -> {

      var t = switch triggers[counter] {
        case null: triggers[counter] = new FutureTrigger<Null<Int>>();
        case v: v;
      }

      counter++;

      t.asFuture().map(v -> if (v == null) Yield.End else Data(v));
    });

    var res = s.forEach(t -> if (t < 20) None else Some(t)).eager();

    for (i in 0...21) {
      asserts.assert(triggers.length == i + 1);
      asserts.assert(res.status.match(EagerlyAwaited));
      triggers[i].trigger(i);
    }

    asserts.assert(res.status.match(Ready(_.get() => Stopped(_, 20))));

    var res = s.forEach(t -> if (t < 40) None else Some(t)).eager();

    for (i in 21...41) {
      asserts.assert(triggers.length == i + 1);
      asserts.assert(res.status.match(EagerlyAwaited));
      triggers[i].trigger(i);
    }

    asserts.assert(res.status.match(Ready(_.get() => Stopped(_, 40))));

    var log = [];
    var res = s.forEach(t -> { log.push(t); None; });
    var active:CallbackLink = null;

    active = res.handle(function () {});

    for (i in 0...5) {
      asserts.assert(triggers.length == 42 + i);
      triggers[triggers.length - 1].trigger(triggers.length - 1);
    }

    active.cancel();

    for (i in 0...5) {
      var t = new FutureTrigger();
      t.trigger(triggers.length - 1);
      triggers.push(t);
    }

    var t = new FutureTrigger();
    t.trigger(null);
    triggers.push(t);

    res.eager();

    asserts.assert(res.status.match(Ready(_.get() => Done)));
    asserts.assert(log.join(',') == [for (i in 0...triggers.length - 2) i].join(','));

    return asserts.done();
  }

  // maybe useful to be moved to Stream itself
  inline function ofOutcomes<T>(i:Iterator<Outcome<T, Error>>) {
    return Stream.ofIterator(i).map(function(v:Outcome<T, Error>) return v);
  }
}