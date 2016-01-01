import haxe.unit.TestCase;

import tink.CoreApi;
import haxe.ds.Option;
import tink.streams.*;
import tink.streams.StreamStep;

class ExtTest extends TestCase{
  public function testScan(){
    var a = [1,2,3,4,5,6,-6,-5,-4,-3,-2,-1];
    var s : Stream<Int> = Stream.ofIterator(a.iterator());
    Scan.scan(s,
      function(a,b){
        trace('a: $a b: $b');
        return a + b;
      }
    ).fold(10,
      function(x0,x1){
        trace('x0: $x0 x1: $x1');
        return x0+x1;
      }
    ).handle(
      function(x){
        trace(x);
        this.assertTrue(Type.enumEq(Success(101),x));
      }
    );
  }
}
class Scan{
  static public function scan<A>(source:Stream<A>,accumulator:A->A->A,?seed:A):Stream<A>{
    var memo    = Data(None);
    if(seed!=null){
      memo = Data(Some(seed));
    }
    return function(){
      return source.next().map(
        function(next){
          //trace('next: $next memo $memo');
          return memo = switch([next,memo]){
            case [Data(v),Data(None)]         : Data(Some(v));
            case [Data(v0),Data(Some(v1))]    : Data(Some(accumulator(v0,v1)));
            case [End,_]                      : End;
            case [Fail(e),_]                  : Fail(e);
            case [_,Fail(e)]                  : Fail(e);
            case [_,End]                      : End;
          }
        }
      ).map(
        function(x){
          return switch(x){
            case Data(Some(v)) : Data(v);
            case Data(None)    : Fail(new Error(501,"null encountered in scan"));
            case Fail(e)       : Fail(e);
            case End           : End;
          }
        }
      );
    }
  }
}
