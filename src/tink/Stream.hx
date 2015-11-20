package tink;

using tink.CoreApi;

interface Stream<T> {
  //function fold<T, R>(f:T->R->Future<R>):Surprise<R, Error>;
  //function filter(f:T->Bool):Stream<T>;
  //function map<R>(f:T->R):Stream<T>;
  //function transform<R>(f:T->Callback<R>->Void):Stream<R>;
  function forEach(item:T->Bool):Surprise<Noise, Error>;
  function forEachAsync(item:T->Future<Bool>):Surprise<Noise, Error>;
  function stream():Streamer<T>;
}

interface Streamer<T> {
  function next():Future<StreamerStep<T>>;
}

enum StreamerStep<T> {
  SData(v:T);
  SError(e:Error);
  SEnd;
}

class CompoundStreamer<T> implements Streamer<T> {
  
  var parts:Array<Streamer<T>>;
  
  public function new(parts) 
    this.parts = parts;
    
  public function next()
    return
      Future.async(function (cb) {
        function next() {
          if (parts.length == 0)
            cb(SEnd);
          else
            parts[0].next().handle(function (x) switch x {
              case SEnd:
                parts.shift();
                next();
              case SData(data):
                
              case _:
                cb(x);
            });
        }
      });
}


class StreamerStream<T> extends StreamBase<T> {
  
  var cache:Array<T>;
  var source:Streamer<T>;
  
  public function new(source) {
    this.cache = [];
    this.source = source;
  }
  
  override public function stream():Streamer<T> 
    return source;
    //return new CompoundStreamer([new IteratorStreamer(cache.iterator()), source]);
}

class EmptyStreamer<T> implements Streamer<T> {
  
  public function new() { }
  
  public function next():Future<StreamerStep<T>>
    return Future.sync(SEnd);
}

class StreamBase<T> implements Stream<T> {
  
  public function stream():Streamer<T>
    return new EmptyStreamer();
  
  public function forEach(item:T->Bool):Surprise<Noise, Error> {//TODO: move to streamer
    
    return forEachAsync(function (x) return if (item(x)) resume else abort); // <-- this is the short, yet slooooow
    
    var s = stream();
    
    return Future.async(function (cb) {
      function next() {
        while (true) {
          var touched = false;
          s.next().handle(function (step) switch step {
            case SData(data):
              if (!item(data)) 
                cb(Success(Noise));
              else 
                if (touched) next();
                else touched = true;
            case SError(e):
              cb(Failure(e));
            case SEnd:
              cb(Success(Noise));
          });
          
          if (!touched) 
            break;
        }
      }
      next();
    });
  }
  
  public function forEachAsync(item:T->Future<Bool>):Surprise<Noise, Error> {//TODO: move to streamer
    
    var s = stream();
    
    return Future.async(function (cb) {
      function next() {
        while (true) {
          var touched = false;
          s.next().handle(function (step) switch step {
            case SData(data):
              item(data).handle(function (resume) {
                if (!resume) 
                  cb(Success(Noise));
                else 
                  if (touched) next();
                  else touched = true;
              });
            case SError(e):
              cb(Failure(e));
            case SEnd:
              cb(Success(Noise));
          });
          
          if (!touched) 
            break;
        }
      }
      next();
    });
  }
  
  public function foldAsync<R>(start:R, f:T->R->Future<R>):Surprise<R, Error> {
    return forEachAsync(function (value) {
      return Future.async(function (cb) {
        f(value, start).handle(function (x) {
          start = x;
          cb(true);
        });
      });
    }) >> function (n:Noise) return start;
  }
  
  static var resume = Future.sync(true);
  static var abort = Future.sync(false);
  
  public function fold<R>(start:R, f:T->R->R):Surprise<R, Error> {
    return forEach(function (value) {
      start = f(value, start);
      return true;
    }) >> function (n:Noise) return start;
  }
  
}  

class IteratorStreamer<T> implements Streamer<T> {
  var target:Iterator<T>;
  
  public function new(target)
    this.target = target;
    
  public function next()
    return Future.sync(
      if (target.hasNext()) 
        SData(target.next()) 
      else 
        SEnd
    );
}

class IterableStream<T> extends StreamBase<T> {
  
  var target:Iterable<T>;
  
  public function new(target)
    this.target = target;
  
  override public function stream()
    return new IteratorStreamer(target.iterator());
    
  override public function forEach(item:T->Bool):Surprise<Noise, Error> {
    for (x in target)
      if (!item(x)) break;
      
    return Future.sync(Success(Noise));
  }
  
  override public function forEachAsync(item:T->Future<Bool>):Surprise<Noise, Error> {
    
    var i = target.iterator(),
        f = null;
        
    if (!i.hasNext())
      return super.forEachAsync(item);
      
    while (i.hasNext()) {
      var resume = null;
      
      f = item(i.next());
      var link = f.handle(function (x) resume = x);
      if (resume == null) {
        link.dissolve();//this is ouch
        break;
      }
    }
    
    return Future.async(function (cb) {
      function next(resume)
        if (resume && i.hasNext())
          item(i.next()).handle(next);
        else 
          cb(Success(Noise));
          
      f.handle(next);
    });
  }
}