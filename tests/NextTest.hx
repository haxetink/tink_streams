package;

import haxe.unit.TestCase;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

class NextTest extends TestCase {
  function testMap() {
    var a = Stream.ofIterator(0...3);
    var b = a.map(function(v) return v + 1);
    check(b, [1,2,3]);
  }
  
  function testFilter() {
    var a = Stream.ofIterator(0...6);
    var b = a.filter(function(v) return v % 2 == 1);
    check(b, [1,3,5]);
  }
  
  function testCompound() {
    var a = Signal.trigger();
    var b = Signal.trigger();
    var compound = new SignalStream(a).append(new SignalStream(b));
    a.trigger(Data(1));
    b.trigger(Data(3));
    a.trigger(Data(2));
    a.trigger(End);
    check(compound, [1,2,3]);
    
    var a = Stream.ofIterator(0...3);
    var b = Stream.ofIterator(0...3);
    var compound = a.append(b);
    check(compound, [0,1,2,0,1,2]);
  }
  
  function testBlend() {
    var a = Signal.trigger();
    var b = Signal.trigger();
    var compound = new SignalStream(a).blend(new SignalStream(b));
    a.trigger(Data(1));
    b.trigger(Data(2));
    a.trigger(Data(3));
    a.trigger(End);
    b.trigger(End);
    check(compound, [1,2,3]);
  }
  
  function check<T>(stream:Stream<T, Noise>, values:Array<T>, ?pos) {
    var current = stream;
    for(i in 0...values.length) {
      current.next().handle(function(v) switch v {
        case Link(v, rest): assertEquals(values[i], v, pos); current = rest;
        default: assertTrue(false, pos);
      });
    }
    current.next().handle(function(v) assertTrue(v.match(End), pos));
  }
}