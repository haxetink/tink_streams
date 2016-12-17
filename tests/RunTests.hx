package;

import haxe.unit.TestRunner;
//import tink.streams.StreamOf;
import tink.streams.Stream;
//import tink.streams.IdealStream;

using tink.CoreApi;

#if flash
private typedef Sys = flash.system.System;
#end

class RunTests {

  static function main() {
    //var s:Stream<Int> = null;
    //s.forEach(function (x) return x < 10).handle(function (end) switch end {
      //case Ended(e): $type(e);
    //});
    
    var p:Promise<Int> = Future.sync(Failure(new TypedError<String>(123, 'foo')));
    //var s:IdealStream<Int> = null;
    //if (false)
      //s.forEach(function (x) {
        //return true;
      //});
    var t = new TestRunner();
    //t.add(new StreamTest());
    //t.add(new StreamableTest());
    if (!t.run())
      Sys.exit(500);
  }
  
}