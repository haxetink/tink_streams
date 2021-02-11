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

  public function next():Future<Step<Item, Quality>>
    // BUG: this compiles: return this.forEach(function (i) return Some(i));
    return this.forEach(function (i) return Some(i)).map(function (r):Step<Item, Quality> return switch r {
      case Done: End;
      case Stopped(rest, result): Link(result, rest);
      case Failed(_, e): Fail(e);
    });

  public function select<R>(selector):Stream<R, Quality>
    return new SelectStream(this, selector);

  public function filter(f:Item->Return<Bool, Quality>):Stream<Item, Quality>
    return select(i -> f(i).map(o -> switch o {
      case Success(matched): Success(if (matched) Some(i) else None);
      case Failure(failure): Failure(failure);
    }));

  public function map<R>(f:Item->Return<R, Quality>):Stream<R, Quality>
    return select(i -> f(i).map(r -> switch r {
      case Success(data): Success(Some(data));// BUG: Success(data) compiles
      case Failure(failure): Failure(failure);
    }));

  static public inline function empty<Item, Quality>():Stream<Item, Quality>
    return @:privateAccess
      #if cs
        new Empty();
      #else
        cast Empty.INST;
      #end

  @:op(a...b) public function append(b:Stream<Item, Quality>)
    return new StreamPair(this, b);

  @:from static public function ofIterator<T, Quality>(t:Iterator<T>):Stream<T, Quality>
    return AsyncLinkStream.ofIterator(t);

  @:from static public function promise<T>(p:Promise<Stream<T, Error>>):Stream<T, Error>
    return new PromiseStream(p);

  @:from static public function ofError<T>(e:Error):Stream<T, Error>
    return promise(e);

  static public function flatten<T>(s:Stream<Stream<T, Error>, Error>):Stream<T, Error>
    return new FlattenStream(s);

  static public function ofSignal<Item, Quality>(s):Stream<Item, Quality>
    return new SignalStream(s);
}

enum Step<Item, Quality> {
  Link(value:Item, next:Stream<Item, Quality>):Step<Item, Quality>;
  Fail(e:Error):Step<Item, Error>;
  End:Step<Item, Quality>;
}

private class FlattenStream<Item> implements StreamObject<Item, Error> {
  final source:Stream<Stream<Item, Error>, Error>;

  public function new(source)
    this.source = source;

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Error>>
    return
      source.forEach(function (child) return child.forEach(f).map(function (r) return switch r {
        case Done: None;
        case Stopped(rest, result): Some(new Pair(rest, Success(result)));
        case Failed(rest, e): Some(new Pair(rest, Failure(e)));
      })).map(function (r) return switch r {
        case Done: Done;
        case Stopped(rest, result):
          var rest = new StreamPair(result.a, new FlattenStream(rest));
          switch result.b {
            case Success(data): Stopped(rest, data);
            case Failure(failure): Failed(rest, failure);
          }
        case Failed(rest, e):
          Failed(new FlattenStream(rest), e);
      });
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

typedef Consumer<Item, Result> = (item:Item)->Future<Option<Result>>;

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

private typedef Selector<In, Out, Quality> = In->Return<Option<Out>, Quality>;

private class SelectStream<In, Out, Quality> implements StreamObject<Out, Quality> {

  final source:Stream<In, Quality>;
  final selector:Selector<In, Out, Quality>;

  public function new(source, selector) {
    this.source = source;
    this.selector = selector;
  }

  public function forEach<Result>(f:Consumer<Out, Result>):Future<IterationResult<Out, Result, Quality>>
    return
      source.forEach(
        item -> selector(item).flatMap(o -> switch o {
          case Success(None): None;
          case Success(Some(v)):
            f(v).map(o -> o.map(Success));
          case Failure(e):
            Some(Failure(e));
        })
      ).map(res -> switch res {
        case Done: Done;
        case Stopped(rest, Success(result)):
          Stopped(rest, result);
        case Failed(rest, e) | Stopped(rest, Failure(e)): cast Failed(rest, e);// GADT bug
      });
}

// class MapStream<In, Out, Quality> implements StreamObject<Out, Quality> {
//   final source:Stream<In, Quality>;
//   final transform:In->Return<Out, Quality>;

//   public function new(source, transform) {
//     this.source = source;
//     this.transform = transform;
//   }

//   public function forEach<Result>(f:Consumer<Out, Result>):Future<IterationResult<Out, Result, Quality>>
//     return source.forEach(item -> transform(item).flatMap(out -> switch out {
//       case Success(data): f(data).map(o -> switch o {
//         case Some(v): Some(Success(v));
//         case None: None;
//       });
//       case Failure(e): trace(e); Some(Failure(e));
//     })).map(res -> switch res {
//         case Done: Done;
//         case Stopped(rest, Success(result)): Stopped(rest, result);
//         case Failed(rest, e) | Stopped(rest, Failure(e)): cast Failed(rest, e);
//     });
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
    return new Future((yield:(res:IterationResult<Item, Result, Quality>)->Void) -> {
      final wait = new CallbackLinkRef();
      function loop(cur:AsyncLink<Item, Quality>) {
        while (true) {
          switch cur.status {
            case Ready(result):
              switch result.get() {
                case Fin(v):
                  yield(switch v {
                    case null: Done;
                    case error:
                      cast Failed(Stream.empty(), cast error);// GADT bug: what's worse, this compiles: Stopped(Stream.empty(), Failure(error)) compiles
                  });
                case Cons(item, tail):
                  function process(progress:Future<Option<Result>>) {
                    switch progress.status {
                      case Ready(result):
                        switch result.get() {
                          case Some(v):
                            yield(Stopped(new AsyncLinkStream(tail), v));
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