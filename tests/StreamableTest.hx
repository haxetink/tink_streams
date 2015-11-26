package;

import haxe.Timer;
import haxe.unit.TestCase;
import tink.streams.Streamable;

class StreamableTest extends TestCase {

  function testPerformance() {
    var a = [for (i in 0...10) i];
    var s:Streamable<Int> = new IterableStreamable(a);
    function inc(x) return x + 1;
    function sum(a, b) return a + b;
    
    var ta = measure(function () {
      for (x in 0...10000) a = a.map(inc);
      Lambda.fold(a, sum, 0);
    });
    
    var ts = measure(function () {
      for (x in 0...10000) s = s.map(inc);
      var called = false;
      s.stream().fold(0, sum).handle(function () {
        called = true;
      });
      assertTrue(called);
    });
    
    assertTrue(ts < ta * 10);
  }
  
  function measure(f) {
    var start = Timer.stamp();
    f();
    return Timer.stamp() - start;
  }
  
}