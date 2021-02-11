package;

import tink.unit.*;
import tink.testrunner.*;

using tink.CoreApi;

class RunTests {

  static function main() {
    // new StreamTest().laziness(null);
    Runner.run(TestBatch.make([
      new StreamTest(),
    //   // new BlendTest(),
      new NextTest(),
      new SignalStreamTest(),
    ])).handle(Runner.exit);
  }

}
