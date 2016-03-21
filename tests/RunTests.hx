package;

import haxe.unit.TestRunner;

using tink.CoreApi;

#if flash
private typedef Sys = flash.system.System;
#end

class RunTests {

  static function main() {
    var t = new TestRunner();
    t.add(new StreamTest());
    t.add(new StreamableTest());
    if (!t.run())
      Sys.exit(500);
  }
  
}