package tink.streams;

import tink.core.Callback;
using tink.CoreApi;

@:transitive
@:using(tink.streams.RealStream)
abstract Stream<Item, Quality>(StreamObject<Item, Quality>) from StreamObject<Item, Quality> {

  static public function generate<Item, Quality>(generator:()->Future<Yield<Item, Quality>>):Stream<Item, Quality> {
    function rec():AsyncLink<Item, Quality>
      return Future.irreversible(yield -> {
        generator().handle(o -> yield(switch o {
          case Data(data): Cons(data, rec());
          case Fail(e): Fin(cast e);
          case End: Fin(null);
        }));
      });

    return new AsyncLinkStream(rec());
  }

  static public function single<Item, Quality>(item:Item):Stream<Item, Quality>
    return new SingleItem(item);

  public function next():Future<Step<Item, Quality>>
    return this.forEach(i -> Some(i)).map(function (r):Step<Item, Quality> return switch r {
      case Done: End;
      case Stopped(rest, result): Link(result, rest);
      case Failed(_, e): Fail(e);
    });

  public function select<R>(selector):Stream<R, Quality>
    return
      if (Type.getClass(this) == SelectStream)
        SelectStream.chain(cast this, selector);
      else
        new SelectStream(this, selector);

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>
    return new Future(trigger -> {
      this.forEach(f).handle(trigger);
    });

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
    return SyncLinkStream.ofIterator(t);

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

private class FlattenStream<Item, Quality> implements StreamObject<Item, Quality> {
  final source:Stream<Stream<Item, Quality>, Quality>;

  public function new(source)
    this.source = source;

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>
    return
      source.forEach(child -> child.forEach(f).map(r -> switch r {
        case Done: None;
        case Stopped(rest, result): Some(new Pair(rest, Success(result)));
        case Failed(rest, e): Some(new Pair(cast rest, Failure(e)));
      })).map(r -> switch r {
        case Done: Done;
        case Stopped(rest, result):
          var rest = new StreamPair(result.a, new FlattenStream(rest));
          switch result.b {
            case Success(data): Stopped(rest, data);
            case Failure(failure): cast Failed(cast rest, failure);
          }
        case Failed(rest, e):
          cast Failed(new FlattenStream(rest), e);
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

private class SingleItem<Item, Quality> implements StreamObject<Item, Quality> {
  final item:Item;
  public function new(item)
    this.item = item;

  public function forEach<Result>(f:Consumer<Item, Result>)
    return new Future<IterationResult<Item, Result, Quality>>(
      trigger -> Helper.trySync(
        f(item),
        (s, _) -> trigger(switch s {
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

private enum LinkKind<Item, Quality, Tail> {
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

      ret.link = Helper.trySync(l.forEach(f), (res, _) -> switch res {
        case Done:
          ret.link = Helper.trySync(r.forEach(f), (v, _) -> trigger(v));
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

  function continued(source):Stream<Out, Quality>
    return new SelectStream(source, selector);

  public function forEach<Result>(f:Consumer<Out, Result>):Future<IterationResult<Out, Result, Quality>>
    return
      source.forEach(
        item -> new Future(trigger -> {
          return
            Helper.trySync(selector(item).asFuture(), (val, sync) -> switch val {
              case Success(None): trigger(None);
              case Success(Some(v)):
                Helper.trySync(f(v), (val, sync) -> switch val {
                  case Some(v): trigger(Some(Success(v)));
                  case None: trigger(None);
                });
              case Failure(e): trigger(Some(Failure(e)));
            });
        })
      ).map(res -> switch res {
        case Done: Done;
        case Stopped(rest, Success(result)):
          Stopped(continued(rest), result);
        case Failed(rest, e) | Stopped(rest, Failure(e)):
          cast Failed(cast continued(cast rest), e);// GADT bug
      });


  static public function chain<In, Between, Out, Quality>(
    a:SelectStream<In, Between, Quality>,
    b:Selector<Between, Out, Quality>
  )
    return new SelectStream(a.source, chainSelectors(a.selector, b));

  static function chainSelectors<In, Between, Out, Quality>(
    a:Selector<In, Between, Quality>,
    b:Selector<Between, Out, Quality>
  ):Selector<In, Out, Quality>
    return v -> new Future(
      trigger -> {
        final inner = new CallbackLinkRef();

        a(v).handle(o -> switch o {
          case Success(None):
            trigger(Success(None));
          case Success(Some(v)):
            inner.link = b(v).handle(trigger);
          case Failure(e):
            trigger(Failure(e));
        }).join(inner);
      }
    );
}

class Grouped<Item, Quality> implements StreamObject<Item, Quality> {
  final source:Stream<Array<Item>, Quality>;

  public function new(source)
    this.source = source;

  public function forEach<Result>(f:Consumer<Item, Result>):Future<IterationResult<Item, Result, Quality>>
    return
      source.forEach(
        group -> switch group {
          case []: None;
          case [item]:
            f(item).map(o -> switch o {
              case Some(v): Some(new Pair(Stream.empty(), Success(v)));
              case None: None;
            });
          default:
            SyncLinkStream.ofIterator(group.iterator())
              .forEach(f).map(res -> switch res {
                case Done: None;
                case Stopped(rest, result): Some(new Pair(rest, Success(result)));
                case Failed(rest, e): Some(new Pair(rest, Failure(e)));
              });
        }
      ).map(function (o):IterationResult<Item, Result, Quality> return switch o {
        case Done: Done;
        case Failed(rest, e): Failed(new Grouped(rest), e);
        case Stopped(rest, { a: left, b: res }):
          var rest = new StreamPair(left, new Grouped(cast rest));
          switch res {
            case Success(data): Stopped(cast rest, data);
            case Failure(e): cast Failed(rest, e);
          }
      });
}

private class Helper {
  static public function noop(_:Dynamic) {}
  static public inline function trySync<X>(f:Future<X>, cb:(val:X, sync:Bool)->Void) {
    var tmp = f.handle(Helper.noop);
    return
      switch f.status {
        case Ready(result):
          cb(result.get(), true);
          null;
        default:
          swapHandler(f, tmp, cb.bind(_, false));
      }
  }
  static public function swapHandler<X>(f:Future<X>, prev:CallbackLink, cb) {
    var ret = f.handle(cb);
    prev.cancel();
    return ret;
  }
}

private typedef AsyncLink<Item, Quality> = Future<AsyncLinkKind<Item, Quality>>;
private typedef AsyncLinkKind<Item, Quality> = LinkKind<Item, Quality, AsyncLink<Item, Quality>>

private class AsyncLinkStream<Item, Quality> implements StreamObject<Item, Quality> {
  final link:AsyncLink<Item, Quality>;

  public function new(link)
    this.link = link;

  public function forEach<Result>(f:Consumer<Item, Result>)
    return new Future<IterationResult<Item, Result, Quality>>(trigger -> {
      final wait = new CallbackLinkRef();
      var streaming = true;
      function yield(v) {
        streaming = false;
        trigger(v);
      }
      function loop(cur:AsyncLink<Item, Quality>) {
        while (streaming) {
          switch cur.status {
            case Ready(result):
              switch result.get() {
                case Fin(v):
                  yield(switch v {
                    case null: Done;
                    case error:
                      cast Failed(Stream.empty(), cast error);// GADT bug
                  });
                case Cons(item, tail):
                  wait.link = Helper.trySync(f(item), (val, sync) -> switch val {
                    case Some(v):
                      yield(Stopped(new AsyncLinkStream(tail), v));
                    case None:
                      if (sync) cur = tail;
                      else loop(tail);
                  });
                  if (wait.link == null) continue;
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
}

private typedef SyncLink<Item, Quality> = Lazy<LinkKind<Item, Quality, SyncLink<Item, Quality>>>;

private class SyncLinkStream<Item, Quality> implements StreamObject<Item, Quality> {
  final link:SyncLink<Item, Quality>;

  public function new(link)
    this.link = link;

  public function forEach<Result>(f:Consumer<Item, Result>)
    return new Future<IterationResult<Item, Result, Quality>>(trigger -> {
      final wait = new CallbackLinkRef();
      var streaming = true;

      function yield(v) {
        streaming = false;
        trigger(v);
      }

      function loop(cur:SyncLink<Item, Quality>)
        while (streaming)
          switch cur.get() {
            case Fin(error):
              yield(switch error {
                case null: Done;
                case e: cast Failed(Stream.empty(), cast e);
              });
            case Cons(item, tail):
              wait.link = Helper.trySync(f(item), (val, sync) -> switch val {
                case Some(v):
                  yield(Stopped(new SyncLinkStream(tail), v));
                case None:
                  if (sync) cur = tail;
                  else loop(tail);
              });
              if (wait.link == null) continue;
          }

      loop(link);

      return wait;
    });

  static function iteratorLink<Item, Quality>(i:Iterator<Item>):SyncLink<Item, Quality>
    return () -> if (i.hasNext()) Cons(i.next(), iteratorLink(i)) else Fin(null);

  static public function ofIterator<Item, Quality>(i:Iterator<Item>):Stream<Item, Quality>
    return new SyncLinkStream(iteratorLink(i));
}

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