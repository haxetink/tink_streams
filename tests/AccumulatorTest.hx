package;

import haxe.unit.TestCase;
import tink.streams.Accumulator;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

class AccumulatorTest extends TestCase {
  function testNormal() {
    var done = false;
    var a = Accumulator.trigger();
    var stream = a.asStream();
    a.trigger(Data(1));
    a.trigger(Data(2));
    a.trigger(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = stream.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    a.trigger(Data(4));
    a.trigger(Data(5));
    a.trigger(End);
    a.trigger(Data(6));
    a.trigger(Data(7));
    
    result.handle(function (x) {
      assertEquals(Depleted, x);
      assertEquals(15, sum);
      done = true;
    });
    assertTrue(done);
  }
  
  function testError() {
    var done = false;
    var a = Accumulator.trigger();
    var stream = a.asStream();
    a.trigger(Data(1));
    a.trigger(Data(2));
    a.trigger(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = stream.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    a.trigger(Data(4));
    a.trigger(Data(5));
    a.trigger(Fail(new Error('Failed')));
    
    result.handle(function (x) {
      assertTrue(x.match(Failed(_)));
      assertEquals(15, sum);
    done = true;
    });
    assertTrue(done);
  }
  
  function testReuse() {
    var a = Accumulator.trigger();
    var stream = a.asStream();
    a.trigger(Data(1));
    a.trigger(Data(2));
    a.trigger(Data(3));
    a.trigger(End);
    
    var count = 0;
    function iterate() {
      var i = 0;
      var sum = 0;
      stream.forEach(function (v) {
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