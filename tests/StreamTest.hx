package;

import haxe.unit.TestCase;
import tink.streams.Accumulator;
import tink.streams.Stream;
import tink.streams.StreamStep;

using tink.CoreApi;

class StreamTest extends TestCase {

  function testIterator() 
    forEach(function (forEach) {
      var a = [for (i in 0...10) i];
      
      var i = a.iterator();
      forEach(a.iterator(), function (v) { 
        assertEquals(i.next(), v);
        return true;
      });
      
      var i = a.iterator();
      forEach(a.iterator(), function (v) { 
        assertEquals(i.next(), v);
        return v < 6; 
      });
      assertEquals(7, i.next());      
    });
    
  function lift<In, Out>(f:In->Out):In->Future<Out>   
    return function (i) return Future.sync(f(i));
  
  function testFilter() 
    forEach(function (forEach) filter(function (filter) {
      var a = [for (i in 0...10) i];
      
      var oddBig = filter(filter(a.iterator(), function (x) return x & 1 == 1), function (x) return x > 4);
      var out = [];
      
      forEach(oddBig, function (x) return out.push(x) > 0);
      
      assertEquals('5,7,9', out.join(','));
    }));
  
  function testMap() 
    forEach(function (forEach) map(function (map) {
      var a = [for (i in 0...10) i];
      
      var inc = new IteratorStream(a.iterator()).map(function (x) return x - 1).map(function (x) return x + 2);
      var out = [];
      
      forEach(inc, function (x) return out.push(x) > 0);
      
      assertEquals('1,2,3,4,5,6,7,8,9,10', out.join(','));
    }));

  function fold<A,R>(test:(Stream<A>->R->(R->A->R)->Surprise<R, Error>)->Void) {
    test(function (s:Stream<A>, start:R, cb:R->A->R) return s.fold(start, cb));
    test(function (s:Stream<A>, start:R, cb:R->A->R) return s.foldAsync(start, function (a, r) return Future.sync(cb(a, r))));        
  }    
    
  function forEach<A>(test:(Stream<A>->(A->Bool)->Surprise<Bool, Error>)->Void) {
    test(function (s:Stream<A>, cb:A->Bool) return s.forEach(cb));
    test(function (s:Stream<A>, cb:A->Bool) return s.forEachAsync(lift(cb)));        
  }

  function filter<A>(test:(Stream<A>->(A->Bool)->Stream<A>)->Void) {
    test(function (s:Stream<A>, cb:A->Bool) return s.filter(cb));
    test(function (s:Stream<A>, cb:A->Bool) return s.filterAsync(lift(cb)));        
  }  
  
  function map<A, R>(test:(Stream<A>->(A->R)->Stream<R>)->Void) {
    test(function (s:Stream<A>, cb:A->R) return s.map(cb));
    test(function (s:Stream<A>, cb:A->R) return s.mapAsync(lift(cb)));        
  }
  
  function testAccumulator() 
    forEach(function (forEach) {
      var g = new Accumulator();
      var out = [];
          
      forEach(g, function (x:Int) { 
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
    });
    
  
  
  function testFold() 
    fold(function (fold) {    
      var count = 1000;
      var a = [for (i in 0...count<<1) i & 3];
      var forEach:Stream<Int> = new IteratorStream(a.iterator());
      
      fold(forEach, 0, function (x, y) return x + y).handle(function (x) {
        assertEquals(count * 3, x.sure());
      });
      
      var forEach = new IteratorStream(a.iterator()).filter(function (x) return x == 1);
      
      fold(forEach, 0, function (x, y) return x + y).handle(function (x) {
        assertEquals(count>>1, x.sure());     
      });
    });
  
  function testConcat()
    fold(function (fold) {
      var s = ConcatStream.make([for (i in 0...3) [for (i in i...3+i) i].iterator()]);
      fold(s, '', function (ret, x) return '$ret,$x').handle(function (x) {
        assertEquals(',0,1,2,1,2,3,2,3,4', x.sure());
      });
    });
  
  #if (php && haxe_ver < 3.3)
  
  #else
  function testGenerator() 
    fold(function (fold) {
      var i = 0;
      var g = Stream.generate(
        function () 
          return Future.sync(
            if (i == 10) End
            else Data(i * i++)
          )
      );
      fold(g, [], function (ret, x) return ret.concat([x])).handle(function (x) {
        assertEquals('0,1,4,9,16,25,36,49,64,81', x.sure().join(','));
      });
    });
  #end
}