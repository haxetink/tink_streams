package tink.streams;

using tink.CoreApi;

import tink.streams.Stream;

@:forward
abstract IdealStream<T>(IdealStreamObject<T>) to IdealStreamObject<T> from IdealStreamObject<T> {
  
  public var depleted(get, never):Bool;
    inline function get_depleted()
      return this.depleted();
      
  @:from static function ofEmpty<T>(e:Empty):IdealStream<T>
    return cast e;
}

interface IdealStreamObject<T> extends StreamObject<T> {
  function forEachSafely(consume:T->Future<Bool>):Future<IdealStream<T>>;  
}

class IdealStreamBase<T> extends StreamBase<T> implements IdealStreamObject<T> {
  
  override public function idealize(rescue:StreamError<T>->IdealStream<T>):IdealStream<T>
    return this;
    
  override public function forEach(consume:Next<T, Bool>):Surprise<Stream<T>, StreamError<T>> {
    var error:Error = null;
    return forEachSafely(function (item:T):Future<Bool> {
      return consume(item).recover(function (e) {
        error = e;
        return Future.sync(false);
      });
    }).map(function (rest) return switch error {
      case null:
        Success((rest:Stream<T>));
      case v:
        Failure(new StreamError(v, rest));
    });
  }
  
  public function forEachSafely(consume:T->Future<Bool>):Future<IdealStream<T>> 
    return throw 'abstract';
  
}

class SingleStream<T> extends IdealStreamBase<T> {
  
  var item:T;
  
  override public function forEachSafely(consume:T->Future<Bool>):Future<IdealStream<T>> 
    return consume(item).map(function (_) return (Empty.inst : IdealStream<T>));
}

class Empty extends IdealStreamBase<Dynamic> {
  
  function new() { }
  
  override public function depleted() 
    return true;
  
  override public function forEachSafely(consume:Dynamic->Future<Bool>):Future<IdealStream<Dynamic>> 
    return Future.sync((this:IdealStream<Dynamic>));
  
  static public var inst(default, null):Empty = new Empty();
    
}