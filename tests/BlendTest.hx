package;

import haxe.unit.TestCase;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

class BlendTest extends TestCase {
  function testBlend() {
    var done = false;
    var a = Signal.trigger();
    var b = Signal.trigger();
    var blended = new SignalStream(a.asSignal()).blend(new SignalStream(b.asSignal()));
    a.trigger(Data(1));
    b.trigger(Data(2));
    a.trigger(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = blended.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    a.trigger(Data(4));
    a.trigger(End);
    b.trigger(Data(5));
    b.trigger(End);
    b.trigger(Data(6));
    a.trigger(Data(7));
    
    result.handle(function (x) {
      assertEquals(Depleted, x);
      assertEquals(15, sum);
      done = true;
    });
    assertTrue(done);
  }
  
  function testCompound() {
    var done = false;
    var a = Signal.trigger();
    var b = Signal.trigger();
    var c = Signal.trigger();
    var blended = new SignalStream(a).append(new SignalStream(c)).blend(new SignalStream(b));
    a.trigger(Data(1));
    b.trigger(Data(2));
    a.trigger(End);
    c.trigger(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = blended.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    c.trigger(Data(4));
    c.trigger(End);
    b.trigger(Data(5));
    b.trigger(End);
    b.trigger(Data(6));
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
    var a = Signal.trigger();
    var b = Signal.trigger();
    var blended = new SignalStream(a.asSignal()).blend(new SignalStream(b.asSignal()));
    a.trigger(Data(1));
    b.trigger(Data(2));
    a.trigger(Data(3));
    
    var i = 0;
    var sum = 0;
    var result = blended.forEach(function (v) {
      assertEquals(++i, v);
      sum += v;
      return Resume;
    });
    
    a.trigger(Data(4));
    a.trigger(Data(5));
    b.trigger(Fail(new Error('Failed')));
    a.trigger(End);
    
    result.handle(function (x) {
      assertTrue(x.match(Failed(_)));
      assertEquals(15, sum);
    done = true;
    });
    assertTrue(done);
  }
  
  function testReuse() {
    var a = Signal.trigger();
    var b = Signal.trigger();
    var blended = new SignalStream(a.asSignal()).blend(new SignalStream(b.asSignal()));
    a.trigger(Data(1));
    b.trigger(Data(2));
    b.trigger(End);
    a.trigger(Data(3));
    a.trigger(End);
    
    var count = 0;
    function iterate() {
      var i = 0;
      var sum = 0;
      blended.forEach(function (v) {
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