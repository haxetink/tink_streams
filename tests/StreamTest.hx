package;

import haxe.unit.TestCase;
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
    s.forEach(function (v) {
      sum += v;
      return Resume;
    }).handle(function (x) {
      asserts.assert(Depleted == x);
      asserts.assert(4950 == sum);
      asserts.done();
    });
    return asserts;
  }
    
  public function testMapFilter() {
    
    var s = Stream.ofIterator(0...100);
    
    s = s.filter(function (i) return i % 2 == 0);
    s = s.filter(function (i) return Success(i % 3 == 0));
    s = s.map(function (i) return i * 3);
    s = s.filter(function (i) return Future.sync(i % 5 == 0));
    s = s.filter(function (i) return Promise.lift(i > 100));
    s = s.map(function (i) return Success(i << 1));
    s = s.map(function (i) return Promise.lift(i + 13));
    s = s.map(function (i) return Future.sync(i - 3));
    s = s.map(function (i) return i * 2);
    
    var sum = 0;
    
    s.forEach(function (v) return Future.sync(Resume)).handle(function (c) switch c {
      case Failed(_):
      default:
    });
    
    s.idealize(null).forEach(function (v) {
      sum += v;
      return Future.sync(Resume);
    }).handle(function (x) switch x {
      case Depleted:
        asserts.assert(1840 == sum);
        asserts.done();
      case Halted(_):
        asserts.fail('Expected "Depleted');
    });
    return asserts;
  }
    
  public function testRegroup() {
    
    var s = Stream.ofIterator(0...100);
    
    var sum = 0;
    s.regroup(function (i:Array<Int>) return i.length == 5 ? Converted(Stream.single(i[0] + i[4])) : Untouched)
      .idealize(null).forEach(function (v) {
        sum += v;
        return Resume;
      })
      .handle(function (x) switch x {
        case Depleted:
          asserts.assert(1980 == sum);
        case Halted(_):
          asserts.fail('Expected "Depleted"');
      });
      
    var sum = 0;
    s.regroup(function (i:Array<Int>, s) {
      return if(s == Flowing)
        i.length == 3 ? Converted(Stream.single(i[0] + i[2])) : Untouched
      else
        Converted(Stream.single(i[0])); // TODO: test backoff / clog at last step
    })
      .idealize(null).forEach(function (v) {
        sum += v;
        return Resume;
      })
      .handle(function (x) switch x {
        case Depleted:
          asserts.assert(3333 == sum);
        case Halted(_):
          asserts.fail('Expected "Depleted"');
      });
      
    var sum = 0;
    s.regroup(function (i:Array<Int>) return Converted([i[0], i[0]].iterator()))
      .idealize(null).forEach(function (v) {
        sum += v;
        return Resume;
      })
      .handle(function (x) switch x {
        case Depleted:
          asserts.assert(9900 == sum);
        case Halted(_):
          asserts.fail('Expected "Depleted"');
      });
    
    return asserts.done();
  }
}