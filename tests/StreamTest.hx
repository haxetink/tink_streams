package;

import haxe.unit.TestCase;
import tink.streams.Accumulator;
import tink.streams.Stream;

using tink.CoreApi;

class StreamTest extends TestCase {

  function testIterator() {
    
    var a = [for (i in 0...10) i];
    
    var i = a.iterator();
    new IteratorStream(a.iterator()).forEachAsync(function (v) { 
      assertEquals(i.next(), v);
      return Future.sync(true); 
    });
    
    var i = a.iterator();
    new IteratorStream(a.iterator()).forEachAsync(function (v) { 
      assertEquals(i.next(), v);
      return Future.sync(v < 6); 
    });
    assertEquals(7, i.next());
  }
  
  function testFilter() {
    var a = [for (i in 0...10) i];
    
    var oddBig = new IteratorStream(a.iterator()).filter(function (x) return x & 1 == 1).filter(function (x) return x > 4);
    var out = [];
    
    oddBig.forEach(function (x) return out.push(x) > 0);
    
    assertEquals('5,7,9', out.join(','));
  }
  
  function testMap() {
    var a = [for (i in 0...10) i];
    
    var inc = new IteratorStream(a.iterator()).map(function (x) return x + 1);
    var out = [];
    
    inc.forEach(function (x) return out.push(x) > 0);
    
    assertEquals('1,2,3,4,5,6,7,8,9,10', out.join(','));
  }
  
  function testAccumulator() {
    var g = new Accumulator();
    var out = [];
        
    g.forEach(function (x:Int) { 
      out.push(x);
      return true; 
    }).handle(function (x) {
      x.sure();
      out = null;
    });
    
    assertEquals('', out.join(','));
    
    for (i in 0...5)
      g.yield(Data(i));      

    assertEquals('0,1,2,3,4', out.join(','));
    
    for (i in 0...5)
      g.yield(Data(i));      

    assertEquals('0,1,2,3,4,0,1,2,3,4', out.join(','));
    
    g.yield(End);
    assertEquals(null, out);
  }
  
  function testFold() {
    
    var count = 1000;
    var a = [for (i in 0...count<<1) i & 3];
    var iter = new IteratorStream(a.iterator());
    
    iter.fold(0, function (x, y) return x + y).handle(function (x) {
      assertEquals(count * 3, x.sure());
    });
    
    var iter = new IteratorStream(a.iterator()).filter(function (x) return x == 1);
    
    iter.fold(0, function (x, y) return x + y).handle(function (x) {
      assertEquals(count>>1, x.sure());     
    });
  }
  
  function testGenerator() {
    
    function squares()
      return new IteratorStream([for (i in 0...100) i].iterator()).filter(function (i) return Math.floor(Math.sqrt(i)) == Math.sqrt(i));
      
    var g = Stream.generate(squares().next);
    g.fold([], function (x, y) return y.concat([x])).handle(function (x) {
      assertEquals('0,1,4,9,16,25,36,49,64,81', x.sure().join(','));
    });
  }
}