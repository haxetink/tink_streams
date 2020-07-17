package tink.streams.nodejs;

import js.node.Buffer;
import js.node.stream.Readable.IReadable;

using tink.CoreApi;

class WrappedReadable<T> {

  var native:IReadable;
  var name:String;
  var end:Surprise<Null<T>, Error>;
      
  public function new(name, native, onEnd) {
    this.name = name;
    this.native = native;
    
    end = Future.async(function (cb) {
      native.once('end', function () cb(Success(null)));
      native.once('close', function () cb(Success(null)));
      native.once('error', function (e:{ code:String, message:String }) cb(Failure(new Error('${e.code} - Failed reading from $name because ${e.message}'))));      
    })
    .eager(); // async laziness fix for tink_core v2
    if (onEnd != null)
      end.handle(function () 
        js.Node.process.nextTick(onEnd)
      );
  }

  public function read():Promise<Null<T>>{
    return Future.async(function (cb) {
      function attempt() {
        try 
          switch native.read() {
            case null:
              native.once('readable', attempt);
            case object:
              cb(Success((cast object:T)));
          }
        catch (e:Dynamic) {
          trace(e);
          js.Syntax.code('debugger');
          cb(Failure(Error.withData('Error while reading from $name', e)));
        }
      }
                    
      attempt();
      //end.handle(cb);
    }).first(end);
  }
}