package tink.streams;

using tink.CoreApi;

abstract Stream<T, E>(StreamObject<T, E>) from StreamObject<T, E> to StreamObject<T, E> {
  
  public var depleted(get, never):Bool;
    inline function get_depleted()
      return this.depleted();  
      
  public inline function forEach<C>(consume:Consumer<T, C>):Result<T, C, E>
    return this.forEach(consume);
    
  @:noCompletion public inline function decompose(into)
    this.decompose(into);
    
}

interface StreamObject<T, E> {
  function depleted():Bool;
  function decompose(into:Array<Stream<T, E>>):Void;
  function forEach<C>(consume:Consumer<T, C>):Result<T, C, E>;
}

enum Step<C> {
  Halt:Step<C>;
  Resume:Step<C>;
  Fail(e:Error):Step<Error>;
}

enum End<T, C, S> {
  Halted(rest:Stream<T, S>):End<T, C, S>;
  Clogged(error:Error, at:Stream<T, S>):End<T, Error, S>;
  Failed(error:Error):End<T, C, Error>;
  Depleted:End<T, C, S>;
}

typedef Result<T, C, S> = Future<End<T, C, S>>;

@:callable
abstract Consumer<T, C>(T->Future<Step<C>>) from T->Future<Step<C>> {
  
}

class Empty implements StreamObject<Dynamic, Dynamic> {
  
  function new() {}
  
  public function depleted():Bool
    return true;
        
  public function decompose(into:Array<Stream<Dynamic, Dynamic>>) {}
    
  public function forEach<C>(consume:Consumer<Dynamic, C>):Result<Dynamic, C, Dynamic> 
    return Future.sync(Depleted);
    
  static var inst = new Empty();  
    
  static public inline function make<T, E>():Stream<T, E>
    return cast inst;
  
}

class StreamBase<T, E> implements StreamObject<T, E> {
  
  public function depleted():Bool
    return false;
    
  public function decompose(into:Array<Stream<T, E>>) 
    into.push(this);
    
  public function forEach<C>(consume:Consumer<T, C>):Result<T, C, E> 
    return throw 'not implemented';
    
}

class CompoundStream<T, E> extends StreamBase<T, E> {
  
  var parts:Array<Stream<T, E>>;
  
  function new(parts)
    this.parts = parts;
  
  override public function decompose(into:Array<Stream<T, E>>):Void 
    for (p in parts)
      p.decompose(into);
  
  override public function forEach<C>(consume:Consumer<T, C>):Result<T, C, E> 
    return Future.async(consumeParts.bind(parts, consume, _));
      
  static function consumeParts<T, E, C>(parts:Array<Stream<T, E>>, consume:Consumer<T, C>, cb:End<T, C, E>->Void) 
    if (parts.length == 0)
      cb(Depleted);
    else
      parts[0].forEach(consume).handle(function (o) switch o {
        case Depleted:
          
          consumeParts(parts.slice(1), consume, cb);
          
        case Halted(rest):
          
          parts = parts.copy();
          parts[0] = rest;
          cb(Halted(new CompoundStream(parts)));
          
        case Clogged(e, at):
          
          if (at.depleted)
            parts = parts.slice(1);
          else {
            parts = parts.copy();
            parts[0] = at;
          }
          
          cb(Clogged(e, new CompoundStream(parts)));
          
        case Failed(e):
          
          cb(Failed(e));
                    
      });  
      
  static public function of<T, E>(streams:Array<Stream<T, E>>):Stream<T, E> {
    
    var ret = [];
    
    for (s in streams)
      s.decompose(ret);
      
    return 
      if (ret.length == 0) Empty.make();
      else new CompoundStream(ret);
  }      
  
}