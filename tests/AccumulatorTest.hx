package;

import haxe.unit.TestCase;
import tink.streams.Accumulator;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

class AccumulatorTest extends TestCase {
  function testNormal() {
    var done = false;
    var a = new Accumulator();
    a.yield(Data(1));
    a.yield(Data(2));
    a.yield(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = a.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    a.yield(Data(4));
    a.yield(Data(5));
    a.yield(End);
    a.yield(Data(6));
    a.yield(Data(7));
    
    result.handle(function (x) {
      assertEquals(Depleted, x);
      assertEquals(15, sum);
      done = true;
    });
    assertTrue(done);
  }
  
  function testError() {
    var done = false;
    var a = new Accumulator();
    a.yield(Data(1));
    a.yield(Data(2));
    a.yield(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = a.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    a.yield(Data(4));
    a.yield(Data(5));
    a.yield(Fail(new Error('Failed')));
    
    result.handle(function (x) {
      assertTrue(x.match(Failed(_)));
      assertEquals(15, sum);
    done = true;
    });
    assertTrue(done);
  }
  
  function testReuse() {
    var a = new Accumulator();
    a.yield(Data(1));
    a.yield(Data(2));
    a.yield(Data(3));
    a.yield(End);
    
    var count = 0;
    function iterate() {
      var i = 0;
      var sum = 0;
      a.forEach(function (v) {
        assertEquals(++i, v);
        sum += v;
        return Resume;
      }).handle(function (x) {
        assertEquals(Depleted, x);
        assertEquals(6, sum);
        count++;
      });
    }
    
    iterate();
    iterate();
    iterate();
    assertEquals(3, count);
  }
}