package tink.streams;

import tink.streams.Stream;

using tink.CoreApi;

class Accumulator<T> extends StepWise<T> {
  
  var end:StreamStep<T>;
  var buffered:Array<StreamStep<T>>;
  var waiting:Array<FutureTrigger<StreamStep<T>>>;
  
  public function new() {
    buffered = [];
    waiting = new Array<FutureTrigger<StreamStep<T>>>();
  }
  
  override public function next():Future<StreamStep<T>> 
    return
      if (end != null)
        Future.sync(end);
      else
        switch buffered.shift() {
          case null:
            var ret = Future.trigger();
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
  
}