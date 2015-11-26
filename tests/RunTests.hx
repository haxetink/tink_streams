package;

import haxe.unit.TestRunner;

using tink.CoreApi;

class RunTests {

  static function main() {
    var t = new TestRunner();
    t.add(new StreamTest());
    t.add(new StreamableTest());
    t.run();
  }
  
}