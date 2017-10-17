package;

import haxe.unit.TestCase;
import tink.streams.IdealStream;
import tink.streams.RealStream;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

class StreamTest extends TestCase {
  function testIterator() {
    var s = Stream.ofIterator(0...100);
    var sum = 0;
    s.forEach(function (v) {
      sum += v;
      return Resume;
    }).handle(function (x) {
      assertEquals(Depleted, x);
      assertEquals(4950, sum);
    });
  }
    
  function testMapFilter() {
    
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
        assertEquals(1840, sum);
      case Halted(_):
        assertTrue(false);
    });
    
  }
    
  function testRegroup() {
    
    var s = Stream.ofIterator(0...100);
    
    var sum = 0;
    s.regroup(function (i:Array<Int>) return i.length == 5 ? Converted(Stream.single(i[0] + i[4])) : Untouched)
      .idealize(null).forEach(function (v) {
        sum += v;
        return Resume;
      })
      .handle(function (x) switch x {
        case Depleted:
          assertEquals(1980, sum);
        case Halted(_):
          assertTrue(false);
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
          assertEquals(3333, sum);
        case Halted(_):
          assertTrue(false);
      });
      
    var sum = 0;
    s.regroup(function (i:Array<Int>) return Converted([i[0], i[0]].iterator()))
      .idealize(null).forEach(function (v) {
        sum += v;
        return Resume;
      })
      .handle(function (x) switch x {
        case Depleted:
          assertEquals(9900, sum);
        case Halted(_):
          assertTrue(false);
      });
    
  }
}