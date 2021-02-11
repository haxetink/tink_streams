// import js.node.stream.Readable;
import tink.streams.Stream.Yield;
import js.node.stream.Readable;
import js.node.Buffer;
import tink.streams.*;
import js.node.events.EventEmitter;
import js.node.Fs;

using sys.io.File;
using sys.FileSystem;
using tink.CoreApi;

class Iter<T> extends Readable<Iter<T>> {
  final iterator:Iterator<T>;
  public function new(iterator) {
    super({ objectMode: true });
    this.iterator = iterator;
  }
  override function _read(size:Int) {
    for (i in 0...size)
      if (iterator.hasNext()) {
        if (!push(iterator.next())) break;
      }
      else {
        push(null);
        break;
      }
  }
}
class Benchmark {
  static function measure<X>(a:Array<Named<Future<X>>>)
    switch a {
      case []:
      case _[0] => task:
        var start = haxe.Timer.stamp();
        task.value.handle(function (x) {
          if (task.name != null)
            trace('${task.name} took ${haxe.Timer.stamp() - start}s producing ${x}');
          measure(a.slice(1));
        });
    }

  static function main() {
    numbers();
    files();
  }

  static function files() {
    final dummy = 'bin/dummy.txt';
    if (!dummy.exists()) {
      var s = 'a';
      for (i in 0...28)
        s += s;
      dummy.saveContent(s);
    }

    final copy = 'bin/dummy_copy.txt';

    function delete<X>():Future<X>
      return Future.irreversible(yield -> {
        if (copy.exists())
          copy.deleteFile();
        yield(null);
      });

    function tinkRead()
      return new Named('tink', {
        var len = 0;
        readStream(dummy).forEach(item -> {
          len += item.length;
          None;
        }).map(_ -> len);
      });

    function tinkCopy():Named<Promise<Noise>>
      return new Named('tink', {
        writeStream(copy, cast readStream(dummy));
      });

    function nodeRead()
      return new Named('node', Future.irreversible(yield -> {
        var len = 0;
        Fs.createReadStream(dummy)
          .on('data', (b:Buffer) -> len += b.length)
          .on('end', () -> yield(len));
          // .pipe(Fs.createWriteStream(copy), { end: true }).on('close', () -> yield(Noise));
      }));

    function nodeCopy()
      return new Named<Promise<Noise>>('node', Future.irreversible(yield -> {
        Fs.createReadStream(dummy)
          .pipe(Fs.createWriteStream(copy), { end: true }).on('close', () -> yield(Success(Noise)));
      }));
    measure([
      new Named(null, delete()),
      nodeCopy(),
      new Named(null, delete()),
      tinkCopy(),
      new Named(null, delete()),
      nodeCopy(),
      new Named(null, delete()),
      tinkCopy(),
    ]);
  }

  static function writeStream(path:String, s:Stream<Buffer, Noise>)
    return
      open(path, WriteCreate).next(
        fd -> s.forEach(buf -> {
          Future.irreversible(trigger -> {
            function flush(start:Int)
              Fs.write(fd, buf, start, buf.length - start, (error, written, buf) -> {
                if (error != null) trigger(Some(Failure(error)))
                else if (written + start == buf.length) trigger(None);
                else flush(start + written);
              });
            flush(0);
          });
        }).next(res -> switch res {
          case Done: Noise;
          case Stopped(rest, Failure(e)):
            tink.core.Error.withData('failed writing to $path', e);
          case Stopped(_):
            throw 'unreachable';
        }).map(x -> {
          Fs.closeSync(fd);
          x;
        }).eager()
      );

  static function open(path:String, flags)
    return new Promise((resolve, reject) -> {
      Fs.open(path, flags, null, (?error, fd) -> {
        if (error == null) resolve(fd);
        else reject(tink.core.Error.withData('failed to open $path', error));
      });
      return null;
    });

  static function readStream(path:String, chunSize:Int = 0x40000) {
    var file = open(path, Read);

    function read(fd)
      return Future.irreversible(trigger -> {
        Fs.read(fd, Buffer.alloc(chunSize), 0, chunSize, null, (error, bytesRead, buffer) -> trigger(
          if (error != null) Yield.Fail(null)
          else if (bytesRead == 0) {
            Fs.closeSync(fd);
            Yield.End;
          }
          else Yield.Data(buffer.slice(0, bytesRead))
        ));
      });

    return Stream.promise(file.next(fd -> Stream.generate(() -> read(fd))));
  }

  static function numbers() {
    final total = 100000;
    var s = Stream.ofIterator(0...total);

    measure([
      new Named('tink', {
        var x = 0;
        s.forEach(_ -> {
          x += 1;
          None;
        }).map(_ -> x);
      }),
      new Named('node', new Future(yield -> {
        var i = new Iter(0...total);
        var x = 0;
        i.on('data', v -> {
          x += 1;
        });
        i.on('end', () -> yield(x));
        return null;
      })),
      new Named('tink', {
        var s = tink.streams.Stream.ofIterator(0...total);
        var x = 0;
        s.forEach(_ -> {
          x += 1;
          None;
        }).map(_ -> x);
      }),
      new Named('node', Future.irreversible(yield -> {
        var i = new Iter(0...total);
        var x = 0;
        i.on('data', v -> {
          x += 1;
        });
        i.on('end', () -> yield(x));
      })),
      new Named('tink repeat', {
        var x = 0;
        s.forEach(_ -> {
          x += 1;
          None;
        }).map(_ -> x);
      }),
    ]);
  }
}