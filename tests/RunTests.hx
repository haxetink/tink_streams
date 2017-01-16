package;

import haxe.Timer;
import haxe.unit.TestRunner;

using tink.CoreApi;

class RunTests {

  static function main() {
    
    var t = new TestRunner();
    t.add(new StreamTest());
    
    travix.Logger.exit(
      if (t.run()) 0
      else 500
    );
  }
  
}