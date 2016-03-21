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
    var size = 100000,
        repeat = 3;
    var a = [for (i in 0...size) i];
    var s:Streamable<Int> = new IterableStreamable(a);
    
    var ta = measure(function () {
      for (x in 0...repeat) a = a.map(inc).map(dec);
      Lambda.fold(a, sum, 0);
    });
    
    var ts = measure(function () {
      for (x in 0...repeat) s = s.map(inc).map(dec);
      var called = false;
      s.stream().fold(0, sum).handle(function () {
        called = true;
      });
      assertTrue(called);
    });
    
    var fastEnough = ts < ta * 10;//not needing more than one order of magnitude will have to do for now ... mostly because of PHP
    if (!fastEnough)
      trace([ts, ta]);
    assertTrue(fastEnough);
  }
  
  function measure(f) {
    function stamp()
      return 
        #if sys
          Sys.cpuTime();
        #else
          haxe.Timer.stamp();
        #end
    var start = stamp();
    f();
    return stamp() - start;
  }
  
}