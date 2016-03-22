package tink.streams;

import tink.streams.StreamStep;
using tink.CoreApi;

@:forward
abstract Stream<T>(StreamObject<T>) from StreamObject<T> to StreamObject<T> {
  
  @:from static public function later<T>(f:Surprise<Stream<T>, Error>):Stream<T>
    return new FutureStream(f);
  
  @:from static public function ofIterator<T>(i:Iterator<T>):Stream<T>
    return new IteratorStream(i);
    
  @:from static public function failure<T>(e:Error):Stream<T>
    return generate(function () return Future.sync(Fail(e)));
    
  @:from static public function generate<T>(step:Void->Future<StreamStep<T>>):Stream<T>
    return new Generator(step);
  
  public function fold<R>(start:R, reduce:R->T->R):Surprise<R, Error>
    return Future.async(function (cb) {
      this.forEach(function (x) {
        start = reduce(start, x);
        return true;
      }).handle(function (o) cb(switch o {
        case Failure(e):
          Failure(e);
        default:
          Success(start);
      }));
    });  
  
  public function foldAsync<R>(start:R, reduce:R->T->Future<R>):Surprise<R, Error>
    return Future.async(function (cb) {
      this.forEachAsync(function (x) {
        return reduce(start, x).map(function (v) { start = v; return true; });
      }).handle(function (o) cb(switch o {
        case Failure(e):
          Failure(e);
        default:
          Success(start);
      }));
    }); 
    
  @:op(a...b) static public function concat<A>(a:Stream<A>, b:Stream<A>):Stream<A> 
    return ConcatStream.make([a, b]);
}

private class FutureStream<T> extends StreamBase<T> {
  
  var target:Surprise<Stream<T>, Error>;
  
  public function new(target)
    this.target = target;
    
  function later<Out>(f:Stream<T>->Surprise<Out, Error>):Surprise<Out, Error>
    return 
      Future.async(function (cb) 
        target.handle(function (o) switch o {
          case Failure(e): cb(Failure(e));
          case Success(s): f(s).handle(cb);
        })
      );
      
  override public function forEach(item:T->Bool):Surprise<Bool, Error> 
    return later(function (s) return s.forEach(item));
  
  override public function forEachAsync(item:T->Future<Bool>):Surprise<Bool, Error> 
    return later(function (s) return s.forEachAsync(item));
}

interface StreamObject<T> {
    
  function next():Future<StreamStep<T>>;
  function forEach(item:T->Bool):Surprise<Bool, Error>;
  function forEachAsync(item:T->Future<Bool>):Surprise<Bool, Error>;
  
  function map<R>(item:T->R):Stream<R>;
  function mapAsync<R>(item:T->Future<R>):Stream<R>;
  
  function filter(item:T->Bool):Stream<T>;
  function filterAsync(item:T->Future<Bool>):Stream<T>;
  
}

class Generator<T> extends StepWise<T> {
  var step:Void->Future<StreamStep<T>>;
  var waiting:Array<FutureTrigger<StreamStep<T>>>;
  
  public function new(step) {
    this.step = step;
    this.waiting = new Array<FutureTrigger<StreamStep<T>>>();
  }
  
  override public function next():Future<StreamStep<T>> {
    var ret = Future.trigger();
    
    if (waiting.push(ret) == 1)
      step().handle(ret.trigger);
    else
      waiting[waiting.length - 2].asFuture().handle(function () step().handle(ret.trigger));
      
    return ret;
  }
}

#if cs
private abstract Maybe<T>(Ref<T>) {
  inline function new(o) this = o;
  
  @:to public inline function isSet():Bool
    return this != null;
  
  public inline function get():T
    return this;
    
  public inline function map<R>(f:T->R):Maybe<R>
    return 
      if (isSet()) Maybe.Some(f(this));
      else Maybe.None();
    
  public inline function flatMap<R>(f:T->Maybe<R>):Maybe<R>
    return
      if (isSet()) f(this);
      else Maybe.None();
  
  static public inline function Some<T>(v:T):Maybe<T> return new Maybe(v);
  static public inline function None<T>():Maybe<T> return null;
}
#else
private abstract Maybe<T>(Null<T>) {
  inline function new(o) this = o;
  
  @:to public inline function isSet():Bool
    return this != null;
  
  public inline function get():T
    return this;
    
  public inline function map<R>(f:T->R):Maybe<R>
    return 
      if (isSet()) Maybe.Some(f(this));
      else Maybe.None();
    
  public inline function flatMap<R>(f:T->Maybe<R>):Maybe<R>
    return
      if (isSet()) f(this);
      else Maybe.None();
  
  static public inline function Some<T>(v:T):Maybe<T> return new Maybe(v);
  static public inline function None<T>():Maybe<T> return null;
}
#end


class ConcatStream<T> extends StreamBase<T> {
  var parts:Array<Stream<T>>;

  function new(parts) 
    this.parts = parts;  
    
  override public function filter(item:T->Bool):Stream<T> 
    return transform(function (x) return x.filter(item));
    
  override public function filterAsync(item:T->Future<Bool>):Stream<T> 
    return transform(function (x) return x.filterAsync(item));
    
  override public function map<R>(item:T->R):Stream<R> 
    return transform(function (x) return x.map(item));
    
  override public function mapAsync<R>(item:T->Future<R>):Stream<R> 
    return transform(function (x) return x.mapAsync(item));
    
  function transform<Out>(t:Stream<T>->Stream<Out>):Stream<Out>
    return new ConcatStream([for (p in parts) t(p)]);
  
  function withAll(f:Stream<T>->Surprise<Bool, Error>):Surprise<Bool, Error>
    return switch parts {
      case []: 
        Future.sync(Success(true));
      default:
        Future.async(function (cb) {
          f(parts[0]).handle(function (x) switch x {
            case Success(v):
              if (v) {
                parts.shift();
                withAll(f).handle(cb);
              }
              else 
                cb(x);
            case Failure(e):
              cb(x);
          });
        });
    }
    
  override public function forEach(item:T->Bool):Surprise<Bool, Error>
    return withAll(function (s) return s.forEach(item));
  
  override public function forEachAsync(item:T -> Future<Bool>):Surprise<Bool, Error>
    return withAll(function (s) return s.forEachAsync(item));
  
  static public function make<T>(parts:Array<Stream<T>>):Stream<T> {
    var flat = [];
    
    for (p in parts)
      if (Std.is(p, ConcatStream)) {
        for (p in (cast p : ConcatStream<T>).parts)
          flat.push(p);
      }
      else
        flat.push(p);    
        
    return new ConcatStream(flat);
  }
  
}

class IteratorStream<T> extends StepWise<T> {
  var target:Iterator<T>;
  var error:Null<Error>;
  
  public function new(target, ?error) {
    this.target = target;
    this.error = error;
  }
    
  override public function next()
    return Future.sync(
      if (target.hasNext()) 
        Data(target.next()) 
      else 
        if (error == null) End
        else Fail(error)
    );
    
  override public inline function forEach(item:T->Bool):Surprise<Bool, Error> {
    if (error != null)
      return Future.sync(Failure(error));
    
    while (target.hasNext())
      if (!item(target.next())) 
        return Future.sync(Success(false));
        
    return Future.sync(Success(true));
  }
}


class StepWise<T> extends StreamBase<T> {
  override public function next():Future<StreamStep<T>>
    return Future.sync(End);
    
  override public function forEach(item:T->Bool):Surprise<Bool, Error> 
    return Future.async(function (cb) {
      function next() {
        while (true) {
          var touched = false;//TODO: this flag is pure fucking magic. An enum that just gives the different states names would probably be better
          this.next().handle(function (step) switch step {
            case Data(data):
              if (!item(data)) 
                cb(Success(false));
              else 
                if (touched) next();
                else touched = true;
            case Fail(e):
              cb(Failure(e));
            case End:
              cb(Success(true));
          });
          
          if (!touched) {
            touched = true;
            break;
          }
        }
      }
      next();
    });
    
  override public function forEachAsync(item:T->Future<Bool>):Surprise<Bool, Error> {
    return Future.async(function (cb) {
      function next() {
        while (true) {
          var touched = false;//TODO: this flag is pure fucking magic. An enum that just gives the different states names would probably be better
          this.next().handle(function (step) switch step {
            case Data(data):
              item(data).handle(function (resume) {
                if (!resume) 
                  cb(Success(false));
                else 
                  if (touched) next();
                  else touched = true;
              });
            case Fail(e):
              cb(Failure(e));
            case End:
              cb(Success(true));
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
}

class StreamBase<T> implements StreamObject<T> {
  
  public function next():Future<StreamStep<T>> 
    return Future.async(function (cb) {
      forEach(function (x) {
        cb(Data(x));
        return false;
      }).handle(function (o) switch o {
        case Success(true): cb(End);
        case Failure(e): cb(Fail(e));
        default:
      });
    });
  
  public function forEach(item:T->Bool):Surprise<Bool, Error>
    return forEachAsync(function (x) return Future.sync(item(x)));
    
  public function forEachAsync(item:T->Future<Bool>):Surprise<Bool, Error> 
    return Future.sync(Success(true));

  public function map<R>(item:T->R):Stream<R>
    return new StreamMap(this, item);
  
  public function mapAsync<R>(item:T->Future<R>):Stream<R>
    return new StreamMapAsync(this, item);
  
  public function filter(item:T->Bool):Stream<T>
    return new StreamFilter(this, item);
  
  public function filterAsync(item:T->Future<Bool>):Stream<T>
    return new StreamFilterAsync(this, item);
    
}


abstract StreamFilter<T>(StreamMapFilter<T, T>) to Stream<T> {
  public inline function new(data, filter:T->Bool)
    this = new StreamMapFilter(data, lift(filter)); 
    
  static public function lift<T>(filter:T->Bool):T->Maybe<T>
    return function (x) return if (filter(x)) Maybe.Some(x) else Maybe.None();
}

abstract StreamMap<In, Out>(StreamMapFilter<In, Out>) to Stream<Out> {
  public inline function new(data, map:In->Out)
    this = new StreamMapFilter(data, lift(map));
    
  static public function lift<In, Out>(map:In->Out)
    return function (x) return Maybe.Some(map(x));
}

class StreamMapFilter<In, Out> extends StreamBase<Out> {
  var transformer:In->Maybe<Out>;
  var data:Stream<In>;
  
  public function new(data, transformer) {
    this.data = data;
    this.transformer = transformer;
  }
  
  function chain<R>(transformer:Out->Maybe<R>):Stream<R> 
    return new StreamMapFilter<In, R>(
      data, 
      function (i:In):Maybe<R>
        return this.transformer(i).flatMap(transformer)
    );
    
  override public function forEach(item:Out->Bool):Surprise<Bool, Error>
    return data.forEach(function (x) {
      return switch transformer(x) {
        case v if (v.isSet()): item(v.get());
        default: true;
      }
    });
  
  override public function forEachAsync(item:Out->Future<Bool>):Surprise<Bool, Error> 
    return data.forEachAsync(function (x) {
      return switch transformer(x) {
        case v if (v.isSet()): item(v.get());
        default: Future.sync(true);
      }
    });
  
  function chainAsync<R>(transformer:Out->Future<Maybe<R>>):Stream<R>
    return new StreamMapFilterAsync<In, R>(
      data, 
      function (i:In):Future<Maybe<R>>
        return switch this.transformer(i) {
          case v if (v.isSet()): transformer(v.get());
          default: Future.sync(Maybe.None());
        }
    );
  
  override public function filterAsync(item:Out->Future<Bool>):Stream<Out>
    return chainAsync(StreamFilterAsync.lift(item));
    
  override public function mapAsync<R>(item:Out->Future<R>):Stream<R>
    return chainAsync(StreamMapAsync.lift(item));
    
  override public function map<R>(item:Out->R):Stream<R>
    return chain(StreamMap.lift(item));
    
  override public function filter(item:Out->Bool):Stream<Out>
    return chain(StreamFilter.lift(item));
}

abstract StreamFilterAsync<T>(StreamMapFilterAsync<T, T>) to Stream<T> {
  public inline function new(data, filter:T->Future<Bool>)
    this = new StreamMapFilterAsync(data, lift(filter)); 
    
  static public function lift<T>(filter:T->Future<Bool>)
    return function (x) return filter(x).map(function (matches) return if (matches) Maybe.Some(x) else Maybe.None());
}

abstract StreamMapAsync<In, Out>(StreamMapFilterAsync<In, Out>) to Stream<Out> {
  public inline function new(data, map:In->Future<Out>)
    this = new StreamMapFilterAsync(data, lift(map));
    
  static public function lift<In, Out>(map:In->Future<Out>)
    return function (x) return map(x).map(Maybe.Some);
}

class StreamMapFilterAsync<In, Out> extends StreamBase<Out> {
  var transformer:In->Future<Maybe<Out>>;
  var data:Stream<In>;
  
  public function new(data, transformer) {
    this.data = data;
    this.transformer = transformer;
  }
  
  function chain<R>(transformer:Out->Maybe<R>):Stream<R> 
    return new StreamMapFilterAsync<In, R>(
      data, 
      function (i:In):Future<Maybe<R>>
        return this.transformer(i).map(function (o) return o.flatMap(transformer))
    );
  
  function chainAsync<R>(transformer:Out->Future<Maybe<R>>):Stream<R>
    return new StreamMapFilterAsync<In, R>(
      data, 
      function (i:In):Future<Maybe<R>>
        return this.transformer(i).flatMap(function (o) return switch o {
          case v if (v.isSet()): transformer(v.get());
          default: Future.sync(Maybe.None());
        })
    );
  
  override public function forEachAsync(item:Out -> Future<Bool>):Surprise<Bool, Error> {
    return data.forEachAsync(function (x) {
      return transformer(x).flatMap(function (x) return switch x {
        case v if (v.isSet()): item(v.get());
        default: Future.sync(true);
      }, false);
    });
  }
    
  override public function filterAsync(item:Out->Future<Bool>):Stream<Out>
    return chainAsync(StreamFilterAsync.lift(item));
    
  override public function mapAsync<R>(item:Out->Future<R>):Stream<R>
    return chainAsync(StreamMapAsync.lift(item));
    
  override public function map<R>(item:Out->R):Stream<R>
    return chain(StreamMap.lift(item));
    
  override public function filter(item:Out->Bool):Stream<Out>
    return chain(StreamFilter.lift(item));     
}