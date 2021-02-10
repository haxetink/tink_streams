package tink.streams;

import tink.core.Callback;
using tink.CoreApi;

@:forward @:transitive
@:using(tink.streams.RealStream)
abstract Stream<Item, Quality>(StreamObject<Item, Quality>) from StreamObject<Item, Quality> {

  static public function generate<Item, Quality>(generator:()->Surprise<Item, Quality>):Stream<Item, Quality> {
    function rec():AsyncLink<Item, Quality>
      return Future.irreversible(yield -> {
        generator().handle(o -> yield(switch o {
          case Success(data): Cons(data, rec());
          case Failure(failure): Fin(failure);
        }));
      });

    return new AsyncLinkStream(rec());
  }

  public function filter(f:Item->Return<Bool, Quality>):Stream<Item, Quality> {
    return this;
  }

  public function map<R>(f:Item->Return<R, Quality>):Stream<R, Quality> {
    return Stream.empty();
  }

  static public inline function empty<Item, Quality>():Stream<Item, Quality>
    return @:privateAccess
      #if cs
        new Empty();
      #else
        cast Empty.INST;
      #end

  @:op(a...b) static function concat<I, Q>(a:Stream<I, Q>, b:Stream<I, Q>)
    return new StreamPair(a, b);

  @:from static public function ofIterator<T, Quality>(t:Iterator<T>):Stream<T, Quality>
    return AsyncLinkStream.ofIterator(t);

  @:from static public function promise<T>(p:Promise<Stream<T, Error>>):Stream<T, Error>
    return new PromiseStream(p);

  @:from static public function ofError<T>(e:Error):Stream<T, Error>
    return promise(e);
}

private class PromiseStream<Item> implements StreamObject<Item, Error> {
  final stream:Promise<Stream<Item, Error>>;

  public function new(stream)
    this.stream = stream;

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Error>>
    return stream.next(s -> s.forEach(f)).map(o -> switch o {
      case Success(data):
        data;
      case Failure(e):
        Failed(Stream.empty(), e);
    });
}

class SingleItem<Item, Quality> implements StreamObject<Item, Quality> {
  final item:Item;
  public function new(item)
    this.item = item;

  public function forEach<Result>(f:Consumer<Item, Result>)
    return new Future<IterationResult<Item, Result, Quality>>(
      trigger -> Helper.trySync(
        f(item),
        s -> trigger(switch s {
          case Some(v):
            Stopped(Stream.empty(), v);
          case None:
            Done;
        })
      )
    );
}

enum IterationResult<Item, Result, Quality> {
  Done:IterationResult<Item, Result, Quality>;
  Failed(rest:Stream<Item, Error>, e:Error):IterationResult<Item, Result, Error>;
  Stopped(rest:Stream<Item, Quality>, result:Result):IterationResult<Item, Result, Quality>;
}


interface StreamObject<Item, Quality> {
  function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>;
}

typedef AsyncLink<Item, Quality> = Future<AsyncLinkKind<Item, Quality>>;
typedef AsyncLinkKind<Item, Quality> = LinkKind<Item, Quality, AsyncLink<Item, Quality>>

enum LinkKind<Item, Quality, Tail> {
  Fin(error:Null<Quality>);
  Cons(head:Item, tail:Tail);
}

abstract Step<Result>(Null<Result>) from Null<Result> {
  public inline function new(v:Result)
    this = v;

  public inline function unwrap():Result
    return
      #if debug
        switch this {
          case null: throw 'ohno!';
          case v: v;
        }
      #else
        cast this;
      #end
}

private typedef Consume<Item, Result> = (item:Item)->Future<Option<Result>>;

@:callable
abstract Consumer<Item, Result>(Consume<Item, Result>) from Consume<Item, Result> {
  // public inline function apply(item, done):Future<Step<Result>>
  //   return switch this(item, done) {
  //     case null: Future.NOISE;
  //     case v: v;
  //   }
}

private class Empty<Item, Quality> implements StreamObject<Item, Quality> {

  static final INST:StreamObject<Dynamic, Dynamic> = new Empty();

  function new() {}

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>
    return Done;
}

private class StreamPair<Item, Quality> implements StreamObject<Item, Quality> {
  final l:Stream<Item, Quality>;
  final r:Stream<Item, Quality>;

  public function new(l, r) {
    this.l = l;
    this.r = r;
  }

  public function forEach<Result>(f:Consumer<Item, Result>)
    return new Future<IterationResult<Item, Result, Quality>>(trigger -> {
      final ret = new CallbackLinkRef();

      ret.link = Helper.trySync(l.forEach(f), res -> switch res {
        case Done:
          ret.link = Helper.trySync(r.forEach(f), trigger);
        case Failed(rest, e):
          trigger(Failed(new StreamPair(rest, cast r), e));//TODO: this is GADT bug
        case Stopped(rest, result):
          trigger(Stopped(new StreamPair(rest, r), result));
      });

      return ret;
    });
}

// private typedef Selector<In, Out, Quality> = In->Surprise<Option<Out>, Quality>;

// private class SelectStream<In, Out, Quality> implements StreamObject<Out, Quality> {

//   final source:Stream<In, Quality>;
//   final selector:Selector<In, Out, Quality>;

//   public function new(source, selector) {
//     this.source = source;
//     this.selector = selector;
//   }

//   public function forEach<Result>(f:Consumer<Out, Result>):Future<IterationResult<Out, Result, Quality>>
//     return
//       source.forEach(
//         item -> selector(item).flatMap(o -> switch o {
//           case Success(data):
//           case Failure(failure):
//         })
//       );

// }

// class MapStream<In, Out, Quality> implements StreamObject<Out, Quality> {
//   final source:Stream<In, Quality>;
//   final transform:In->Future<Out>;

//   public function new(source, transform) {
//     this.source = source;
//     this.transform = transform;
//   }

//   public function forEach<Result>(f:Consumer<Out, Result>):Future<IterationResult<Out, Result, Quality>>
//     return source.forEach((item, done) -> transform(item).flatMap(out -> f(out, done)));
// }

// class Grouped<Item, Quality> implements StreamObject<Item, Quality> {
//   final source:Stream<Array<Item>, Quality>;

//   public function new(source)
//     this.source = source;

//   public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>
//     return
//       source.forEach((group, done) ->
//         AsyncLinkStream.ofIterator(group.iterator())
//           .forEach(f).map(res -> switch res {
//             case Done: null;
//             case Stopped(rest, result): done(new Pair(rest, result));
//           })
//       ).map(function (o):IterationResult<Item, Result, Quality> return switch o {
//         case Done: Done;
//         case Stopped(rest, result):
//           var rest = new Grouped(rest);
//           switch result {
//             case Success({ a: left, b: res }):
//               Stopped(new StreamPair(left, rest), res);
//             case Failure(failure):
//               Stopped(rest, Failure(failure));
//           }
//       });
// }

private class Helper {
  static public function noop(_:Dynamic) {}
  static public inline function trySync<X>(f:Future<X>, cb:X->Void) {
    var tmp = f.handle(Helper.noop);
    return
      switch f.status {
        case Ready(result):
          cb(result.get());
          null;
        default:
          swapHandler(f, tmp, cb);
      }
  }
  static public function swapHandler<X>(f:Future<X>, prev:CallbackLink, cb) {
    var ret = f.handle(cb);
    prev.cancel();
    return ret;
  }
}

class AsyncLinkStream<Item, Quality> implements StreamObject<Item, Quality> {
  final link:AsyncLink<Item, Quality>;

  public function new(link)
    this.link = link;

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>
    return new Future(yield -> {
      final wait = new CallbackLinkRef();
      function loop(cur:AsyncLink<Item, Quality>) {
        while (true) {
          switch cur.status {
            case Ready(result):
              switch result.get() {
                case Fin(v):
                  yield(switch v {
                    case null: Done;
                    case error: Stopped(Stream.empty(), Failure(error));
                  });
                case Cons(item, tail):
                  function process(progress:Future<Option<Result>>) {
                    switch progress.status {
                      case Ready(result):
                        switch result.get() {
                          case Some(v):
                            yield(Stopped(new AsyncLinkStream(tail), Success(v)));
                          case None:
                            cur = tail;
                            return true;
                        }
                      default:
                        var tmp = progress.handle(Helper.noop);
                        if (progress.status.match(Ready(_)))
                          return process(progress);
                        else
                          wait.link = Helper.swapHandler(progress, tmp, _ -> process(progress));
                    }
                    return false;
                  }
                  if (process(f(item))) continue;
              }
            default:
              wait.link = cur.handle(Helper.noop);
              if (cur.status.match(Ready(_)))
                continue;
              else
                wait.link = Helper.swapHandler(cur, wait, _ -> loop(cur));// this is very lazy
          }
          break;
        }
      }
      loop(link);
      return wait;
    });

  static function iteratorLink<Item, Quality>(i:Iterator<Item>):Future<AsyncLink<Item, Quality>>
    return Future.lazy(() -> if (i.hasNext()) Cons(i.next(), iteratorLink(i)) else Fin(null));

  static public function ofIterator<Item, Quality>(i:Iterator<Item>):Stream<Item, Quality>
    return new AsyncLinkStream(iteratorLink(i));
}

// typedef SyncLink<Item, Quality> = LinkKind<Item, Quality, Lazy<SyncLink<Item, Quality>>>;

// class SyncLinkStream<Item, Quality> implements StreamObject<Item, Quality> {
//   final link:SyncLink<Item, Quality>;

//   public function new(link)
//     this.link = link;

//   public function forEach<Result>(f:Consumer<Item, Result>)
//     return new Future<IterationResult<Item, Result, Quality>>(trigger -> {
//       final wait = new CallbackLinkRef();
//       var running = true;

//       function yield(v) {
//         running = false;
//         trigger(v);
//       }

//       function process(cur:SyncLink<Item, Quality>)
//         while (running)
//           switch cur {
//             case Fin(error):
//               yield(switch error {
//                 case null: Done;
//                 case e: Stopped(Stream.empty(), Failure(e));
//               });
//             case Cons(head, tail):

//           }

//       process(link);

//       return wait;
//     });
// }

class SignalStream<Item, Quality> extends AsyncLinkStream<Item, Quality> {
  public function new(signal:Signal<Yield<Item, Quality>>)
    super(makeLink(signal));

  static function makeLink<Item, Quality>(signal:Signal<Yield<Item, Quality>>):AsyncLink<Item, Quality>
    return
      signal.nextTime().map(function(o):AsyncLinkKind<Item, Quality> return switch o {
        case Data(data): Cons(data, makeLink(signal));
        case Fail(e): Fin(e);
        case End: Fin(null);
      }).eager(); // this must be eager, otherwise the signal will "run away" if there's no consumer for this stream
}

enum Yield<Item, Quality> {
  Data(data:Item):Yield<Item, Quality>;
  Fail(e:Error):Yield<Item, Error>;
  End:Yield<Item, Quality>;
}