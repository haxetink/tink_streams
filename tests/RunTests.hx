package;

import tink.unit.*;
import tink.testrunner.*;

using tink.CoreApi;

class RunTests {

  static function main() {
    Runner.run(TestBatch.make([
      new StreamTest(),
      new BlendTest(),
      new NextTest(),
      new SignalStreamTest(),
    ])).handle(Runner.exit);
  }

}
