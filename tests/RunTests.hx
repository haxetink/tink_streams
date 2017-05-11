package;

import haxe.Timer;
import haxe.unit.TestRunner;

using tink.CoreApi;

class RunTests {

  static function main() {
    
    #if python
    (cast python.lib.Sys).setrecursionlimit(9999);
    #end
    
    var t = new TestRunner();
    t.add(new StreamTest());
    t.add(new SignalStreamTest());
    
    travix.Logger.exit(
      if (t.run()) 0
      else 500
    );
  }
  
}