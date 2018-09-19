package;

import tink.unit.*;
import tink.streams.Stream;
using StringTools;

using tink.CoreApi;

@:asserts
class NextTest {
  public function new() {}
  public function testMap() {
    var a = Stream.ofIterator(0...3);
    var b = a.map(function(v) return v + 1);
    check(asserts, b, [1,2,3]);
    return asserts.done();
  }
  
  public function testFilter() {
    var a = Stream.ofIterator(0...6);
    var b = a.filter(function(v) return v % 2 == 1);
    check(asserts, b, [1,3,5]);
    return asserts.done();
  }
  
  public function testCompound() {
    var a = Signal.trigger();
    var b = Signal.trigger();
    var compound = new SignalStream(a).append(new SignalStream(b));
    a.trigger(Data(1));
    b.trigger(Data(3));
    a.trigger(Data(2));
    a.trigger(End);
    check(asserts, compound, [1,2,3]);
    
    var a = Stream.ofIterator(0...3);
    var b = Stream.ofIterator(0...3);
    var compound = a.append(b);
    check(asserts, compound, [0,1,2,0,1,2]);
    return asserts.done();
  }
  
  public function testBlend() {
    var a = Signal.trigger();
    var b = Signal.trigger();
    var compound = new SignalStream(a).blend(new SignalStream(b));
    a.trigger(Data(1));
    b.trigger(Data(2));
    a.trigger(Data(3));
    a.trigger(End);
    b.trigger(End);
    check(asserts, compound, [1,2,3]);
    return asserts.done();
  }
  
  function check<T>(asserts:AssertionBuffer, stream:Stream<T, Noise>, values:Array<T>, ?pos:haxe.PosInfos) {
    var current = stream;
    for(i in 0...values.length) {
      current.next().handle(function(v) switch v {
        case Link(v, rest): asserts.assert(values[i] == v, pos); current = rest;
        default: asserts.fail('Expected Link(_)', pos);
      });
    }
    current.next().handle(function(v) asserts.assert(v.match(End), pos));
  }
}