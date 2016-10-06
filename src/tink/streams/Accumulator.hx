package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

private abstract RemovableFuture<T>(Callback<T>->CallbackLink) from (Callback<T>->CallbackLink) to (Callback<T>->CallbackLink){
  static public function fromFutureWith<T>(ft:Future<T>,with:Void->Void):RemovableFuture<T>{
    return function(cb:Callback<T>):CallbackLink{
      var cb0 = ft.handle(cb);
      return function(){
        cb0.dissolve();
        with();
      }
    }
  }
  @:to public function toFuture():Future<T>{
    return new Future(this);
  }
}
class Accumulator<T> extends StepWise<T> {

  var end:StreamStep<T>;
  var buffered:Array<StreamStep<T>>;
  var waiting:Array<FutureTrigger<StreamStep<T>>>;

  public function new() {
    buffered = [];
    waiting = new Array<FutureTrigger<StreamStep<T>>>();
  }

  @:access(tink) override public function next():Future<StreamStep<T>>
    return
      if (end != null)
        Future.sync(end);
      else
        switch buffered.shift() {
          case null:
            var ret       = Future.trigger();
            var canceller = function(){
              waiting.remove(ret);
            }
            var ft_next = RemovableFuture.fromFutureWith(ret,canceller);
            ret.future = ft_next;
            waiting.push(ret);
            ret;
          case v:
            Future.sync(v);
        }
  #if php
  @:native('accumulate')
  #end
  public function yield(step:StreamStep<T>) {
    if (end != null)
      return;

    if (step.match(End | Fail(_)))
      end = step;

    switch waiting.shift() {
      case null:
        buffered.push(step);
      case v:
        v.trigger(step);
    }
  }
  public function isBuffered(){
    return buffered.length > 0;
  }
  public function isWaiting(){
    return waiting.length  > 0;
  }
}
