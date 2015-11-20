package tink.streams;

import haxe.ds.Option;
import tink.streams.StreamStep;

using tink.CoreApi;

@:forward
abstract Stream<T>(StreamObject<T>) from StreamObject<T> to StreamObject<T> {
  @:from static public function generate<T>(step:Void->Future<StreamStep<T>>):Stream<T>
    return new Generator2(step);
}

private class Generator2<T> extends StreamBase<T> {
  var step:Void->Future<StreamStep<T>>;
  var waiting:Array<FutureTrigger<StreamStep<T>>>;
  public function new(step) {
    this.step = step;
    this.waiting = [];
  }
  override public function next():Future<StreamStep<T>> {
    var ret = Future.trigger();
    waiting.push(ret);
    if (waiting.length == 1)
      step().handle(ret.trigger);
    else {
      waiting[waiting.length - 2].asFuture().handle(function () step().handle(ret.trigger));
    }
    return ret;
  }
}

interface StreamObject<T> {
  
  function next():Future<StreamStep<T>>;
  
  function forEach(item:T->Bool):Surprise<Noise, Error>;
  function forEachAsync(item:T->Future<Bool>):Surprise<Noise, Error>;
  
  function map<R>(item:T->R):Stream<R>;
  function mapAsync<R>(item:T->Future<R>):Stream<R>;
  
  function filter(item:T->Bool):Stream<T>;
  function filterAsync(item:T->Future<Bool>):Stream<T>;
  
  function fold<R>(start:R, reduce:T->R->R):Surprise<R, Error>;
  function foldAsync<R>(start:R, reduce:T->R->Future<R>):Surprise<R, Error>;
  
}

class StreamBase<T> implements StreamObject<T> {
  public function next():Future<StreamStep<T>>
    return Future.sync(End);
  
  static function lift<A, B>(f:A->B):A->Future<B>
    return function (a) return Future.sync(f(a));
  
  public function forEach(item:T->Bool):Surprise<Noise, Error> 
    return forEachAsync(lift(item));
  
  public function forEachAsync(item:T->Future<Bool>):Surprise<Noise, Error> {
    return Future.async(function (cb) {
      function next() {
        while (true) {
          var touched = false;//TODO: this flag is pure fucking magic. An enum that just gives the different states names would probably be better
          this.next().handle(function (step) switch step {
            case Data(data):
              item(data).handle(function (resume) {
                if (!resume) 
                  cb(Success(Noise));
                else 
                  if (touched) next();
                  else touched = true;
              });
            case Fail(e):
              cb(Failure(e));
            case End:
              cb(Success(Noise));
          });
          
          if (!touched) {
            touched = true;
            break;
          }
        }
      }
      next();
    });
  }
  
  public function map<R>(item:T->R):Stream<R>
    return mapAsync(lift(item));
  
  public function mapAsync<R>(item:T->Future<R>):Stream<R>
    return new MapStream(this, item);
  
  public function filter(item:T->Bool):Stream<T>
    return filterAsync(lift(item));
  
  public function filterAsync(item:T->Future<Bool>):Stream<T>
    return new FilterStream(this, item);
  
  public function fold<R>(start:R, reduce:T->R->R):Surprise<R, Error>
    return foldAsync(start, function (cur, ret) return Future.sync(reduce(cur, ret)));
  
  public function foldAsync<R>(start:R, reduce:T->R->Future<R>):Surprise<R, Error> {
    return Future.async(function (cb) {
      forEachAsync(function (x) {
        return reduce(x, start).map(function (v) { start = v; return true; });
      }).handle(function (o) cb(switch o {
        case Failure(e):
          Failure(e);
        default:
          Success(start);
      }));
    });
  }
  
}

class IteratorStream<T> extends StreamBase<T> {
  var target:Iterator<T>;
  
  public function new(target)
    this.target = target;
    
  override public function next()
    return Future.sync(
      if (target.hasNext()) 
        Data(target.next()) 
      else 
        End
    );
}

class MapStream<T, R> extends StreamBase<R> {
  var mapper:T->Future<R>;
  var data:Stream<T>;
  
  public function new(data, mapper) {
    this.data = data;
    this.mapper = mapper;
  }
  
  override public function next():Future<StreamStep<R>> 
    return 
      Future.async(function (cb) {
        data.next().handle(function (o) switch o {
          case Data(d):
            mapper(d).handle(function (x) {
              cb(Data(x));
            });
          default: o;
        });
      });  
  
}

class FilterStream<T> extends StreamBase<T> {
  var matches:T->Future<Bool>;
  var data:Stream<T>;
  
  public function new(data, matches) {
    this.data = data;
    this.matches = matches;
  }
  
  override public function next():Future<StreamStep<T>>
    return 
      data.next().flatMap(function (x) return switch x {
        case Data(d):
          matches(d).flatMap(function (matches) 
            return
              if (matches)
                Future.sync(Data(d));
              else
                next()
          );
        case v: Future.sync(v);
      });
}