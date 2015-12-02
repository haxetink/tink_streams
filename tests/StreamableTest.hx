package;

import haxe.Timer;
import haxe.unit.TestCase;
import tink.streams.Stream;
import tink.streams.Streamable;

using tink.CoreApi;

class StreamableTest extends TestCase {

  function testRepeat() {
    var s:Stream<Int> = [0, 1, 2, 3, 4].iterator();
    var c:Streamable<Int> = s;
    var calls = 0;
    c.stream().fold(0, sum).handle(function (x) { assertEquals(10, x.sure()); calls++; });
    c.stream().fold(0, sum).handle(function (x) { assertEquals(10, x.sure()); calls++; });
    c.stream().fold(0, sum).handle(function (x) { assertEquals(10, x.sure()); calls++; });
    assertEquals(3, calls);
  }
  
  function inc(x) return x + 1;
  function dec(x) return x - 1;
  function sum(a, b) return a + b;
  
  function testPerformance() {
    var a = [for (i in 0...10000) i];
    var s:Streamable<Int> = new IterableStreamable(a);
    
    var ta = measure(function () {
      for (x in 0...100) a = a.map(inc).map(dec);
      Lambda.fold(a, sum, 0);
    });
    
    var ts = measure(function () {
      for (x in 0...100) s = s.map(inc).map(dec);
      var called = false;
      s.stream().fold(0, sum).handle(function () {
        called = true;
      });
      assertTrue(called);
    });
    
    assertTrue(ts < ta * Math.sqrt(10));//half an order of magnitude is ok ... for now ... on node, we're actually *faster*
  }
  
  function measure(f) {
    var start = Timer.stamp();
    f();
    return Timer.stamp() - start;
  }
  
}