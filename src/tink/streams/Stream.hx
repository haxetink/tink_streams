package tink.streams;

import haxe.ds.Option;
import tink.streams.StreamStep;

using tink.CoreApi;

@:forward
abstract Stream<T>(StreamObject<T>) from StreamObject<T> to StreamObject<T> {
  
  @:from static public inline function ofIterator<T>(i:Iterator<T>):Stream<T>
    return new IteratorStream(i);
    
  @:from static public function generate<T>(step:Void->Future<StreamStep<T>>):Stream<T>
    return new Generator(step);
  
  public function fold<R>(start:R, reduce:T->R->R):Surprise<R, Error>
    return Future.async(function (cb) {
      this.forEach(function (x) {
        start = reduce(x, start);
        return true;
      }).handle(function (o) cb(switch o {
        case Failure(e):
          Failure(e);
        default:
          Success(start);
      }));
    });  
  
  public function foldAsync<R>(start:R, reduce:T->R->Future<R>):Surprise<R, Error>
    return Future.async(function (cb) {
      this.forEachAsync(function (x) {
        return reduce(x, start).map(function (v) { start = v; return true; });
      }).handle(function (o) cb(switch o {
        case Failure(e):
          Failure(e);
        default:
          Success(start);
      }));
    });  
}

class CompoundStream<T> extends StreamBase<T> {
  var parts:Array<Stream<T>>;
  public function new(parts)
    this.parts = parts;
    
  override public function next():Future<StreamStep<T>>
    return 
      switch parts {
        case []: Future.sync(End);
        default:
          parts[0].next().flatMap(function (step) return switch step {
            case Data(_) | Fail(_): Future.sync(step);
            case End: 
              parts.shift();
              next();
          });
      }
      
  function transform<X>(f:Stream<T>->Stream<X>):Stream<X>
    return new CompoundStream(parts.map(f));
      
  override public function map<R>(item:T->R):Stream<R>
    return transform(function (s) return s.map(item));
    
  override public function mapAsync<R>(item:T->Future<R>):Stream<R>
    return transform(function (s) return s.mapAsync(item));
    
  override public function filter(item:T->Bool):Stream<T>
    return transform(function (s) return s.filter(item));
    
  override public function filterAsync(item:T->Future<Bool>):Stream<T>
    return transform(function (s) return s.filterAsync(item));
}

class Generator<T> extends StreamBase<T> {
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

interface StreamObject<T> {
  
  function next():Future<StreamStep<T>>;
  
  function forEach(item:T->Bool):Surprise<Noise, Error>;
  function forEachAsync(item:T->Future<Bool>):Surprise<Noise, Error>;
  
  function map<R>(item:T->R):Stream<R>;
  function mapAsync<R>(item:T->Future<R>):Stream<R>;
  
  function filter(item:T->Bool):Stream<T>;
  function filterAsync(item:T->Future<Bool>):Stream<T>;
  
}

class StreamBase<T> implements StreamObject<T> {
  public function next():Future<StreamStep<T>>
    return Future.sync(End);
    
  public function forEach(item:T->Bool):Surprise<Noise, Error> 
    return Future.async(function (cb) {
      function next() {
        while (true) {
          var touched = false;//TODO: this flag is pure fucking magic. An enum that just gives the different states names would probably be better
          this.next().handle(function (step) switch step {
            case Data(data):
              if (!item(data)) 
                cb(Success(Noise));
              else 
                if (touched) next();
                else touched = true;
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
    return new StreamMap(this, item);
  
  public function mapAsync<R>(item:T->Future<R>):Stream<R>
    return new StreamMapAsync(this, item);
  
  public function filter(item:T->Bool):Stream<T>
    return new StreamFilter(this, item);
  
  public function filterAsync(item:T->Future<Bool>):Stream<T>
    return new StreamFilterAsync(this, item);
  
}

class IteratorStream<T> extends StreamBase<T> {
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
    
  override public inline function forEach(item:T->Bool):Surprise<Noise, Error> {
    while (target.hasNext())
      if (!item(target.next())) break;
      
    return Future.sync(Success(Noise));
  }
}

class StreamFilterAsync<T> extends StreamMapFilterAsync<T, T> {
  public function new(data, filter:T->Future<Bool>)
    super(data, lift(filter)); 
    
  static public function lift<T>(filter:T->Future<Bool>)
    return function (x) return filter(x).map(function (matches) return if (matches) Some(x) else None);
}

class StreamMapAsync<In, Out> extends StreamMapFilterAsync<In, Out> {
  public function new(data, map:In->Future<Out>)
    super(data, lift(map));
    
  static public function lift<In, Out>(map:In->Future<Out>)
    return function (x) return map(x).map(Some);
}

//TODO: consider using a faster alternative to option

class StreamMapFilterAsync<In, Out> extends StreamBase<Out> {
  var transformer:In->Future<Option<Out>>;
  var data:Stream<In>;
  
  public function new(data, transformer) {
    this.data = data;
    this.transformer = transformer;
  }
  
  function chain<R>(transformer:Out->Option<R>):Stream<R> 
    return new StreamMapFilterAsync<In, R>(
      data, 
      function (i:In):Future<Option<R>>
        return this.transformer(i).map(function (o) return switch o {
          case Some(o): transformer(o);
          case None: None;
        })
    );
  
  function chainAsync<R>(transformer:Out->Future<Option<R>>):Stream<R>
    return new StreamMapFilterAsync<In, R>(
      data, 
      function (i:In):Future<Option<R>>
        return this.transformer(i).flatMap(function (o) return switch o {
          case Some(o): transformer(o);
          case None: Future.sync(None);
        })
    );
  
  override public function filterAsync(item:Out->Future<Bool>):Stream<Out>
    return chainAsync(StreamFilterAsync.lift(item));
    
  override public function mapAsync<R>(item:Out->Future<R>):Stream<R>
    return chainAsync(StreamMapAsync.lift(item));
    
  override public function map<R>(item:Out->R):Stream<R>
    return chain(StreamMap.lift(item));
    
  override public function filter(item:Out->Bool):Stream<Out>
    return chain(StreamFilter.lift(item));    
  
  override public function next():Future<StreamStep<Out>>
    return 
      data.next().flatMap(function (x) return switch x {
        case Data(d):
          transformer(d).flatMap(function (result) return switch result {
            case Some(d):
              Future.sync(Data(d));
            case None:
              next();
          });
        case End: Future.sync(End);
        case Fail(e): Future.sync(Fail(e));
      });
 
}

class StreamFilter<T> extends StreamMapFilter<T, T> {
  public function new(data, filter:T->Bool)
    super(data, lift(filter)); 
    
  static public function lift<T>(filter:T->Bool)
    return function (x) return if (filter(x)) Some(x) else None;
}

class StreamMap<In, Out> extends StreamMapFilter<In, Out> {
  public function new(data, map:In->Out)
    super(data, lift(map));
    
  static public function lift<In, Out>(map:In->Out)
    return function (x) return Some(map(x));
}

class StreamMapFilter<In, Out> extends StreamBase<Out> {
  var transformer:In->Option<Out>;
  var data:Stream<In>;
  
  public function new(data, transformer) {
    this.data = data;
    this.transformer = transformer;
  }
  
  function chain<R>(transformer:Out->Option<R>):Stream<R> 
    return new StreamMapFilter<In, R>(
      data, 
      function (i:In):Option<R>
        return switch this.transformer(i) {
          case Some(o): transformer(o);
          case None: None;
        }
    );
  
  function chainAsync<R>(transformer:Out->Future<Option<R>>):Stream<R>
    return new StreamMapFilterAsync<In, R>(
      data, 
      function (i:In):Future<Option<R>>
        return switch this.transformer(i) {
          case Some(o): transformer(o);
          case None: Future.sync(None);
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
  
  override public function next():Future<StreamStep<Out>>
    return 
      data.next().flatMap(function (x) return switch x {
        case Data(d):
          switch transformer(d) {
            case Some(d):
              Future.sync(Data(d));
            case None:
              next();
          };
        case End: Future.sync(End);
        case Fail(e): Future.sync(Fail(e));
      });
 
}