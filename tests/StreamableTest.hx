package;

import haxe.Timer;
import haxe.unit.TestCase;
import tink.streams.Streamable;

class StreamableTest extends TestCase {

  function testPerformance() {
    var a = [for (i in 0...10000) i];
    var s:Streamable<Int> = new IterableStreamable(a);
    function inc(x) return x + 1;
    function dec(x) return x - 1;
    function sum(a, b) return a + b;
    
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
    trace([ta, ts]);
    assertTrue(ts < ta * Math.sqrt(10));//half an order of magnitude is ok ... for now ... on node, we're actually *faster*
  }
  
  function measure(f) {
    var start = Timer.stamp();
    f();
    return Timer.stamp() - start;
  }
  
}