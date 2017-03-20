package;

import haxe.unit.TestRunner;
import travix.Logger.*;

using tink.CoreApi;

class RunTests {

  static function main() {
    var t = new TestRunner();
    t.add(new StreamTest());
    t.add(new StreamableTest());
    if (!t.run())
      exit(500);
  }
  
}