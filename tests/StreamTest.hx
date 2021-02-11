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
        trace(Std.string(o));
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


  // maybe useful to be moved to Stream itself
  inline function ofOutcomes<T>(i:Iterator<Outcome<T, Error>>) {
    return Stream.ofIterator(i).map(function(v:Outcome<T, Error>) return v);
  }
}