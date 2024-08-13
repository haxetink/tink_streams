package tink.streams;

import haxe.ds.ReadOnlyArray;
using tink.CoreApi;



private typedef RegroupResultObject<In, Out, Quality> = {
  converted:Stream<Out, Quality>,
  ?leftover:Array<In>, // re-populates the buffer
}

@:forward
abstract RegroupResult<In, Out, Quality>(RegroupResultObject<In, Out, Quality>) from RegroupResultObject<In, Out, Quality> to RegroupResultObject<In, Out, Quality> {
  @:from
  public static inline function ofStream<In, Out, Quality>(stream:Stream<Out, Quality>):RegroupResult<In, Out, Quality> {
    return {converted: stream, leftover: null};
  }
}

enum RegroupStatus {
  Flowing;
  Final;
}

private typedef RegrouperFn<In, Out, Quality> = (items:ReadOnlyArray<In>, status:RegroupStatus)->Return<Option<RegroupResult<In, Out, Quality>>, Quality>;

@:callable
abstract Regrouper<In, Out, Quality>(RegrouperFn<In, Out, Quality>) from RegrouperFn<In, Out, Quality> to RegrouperFn<In, Out, Quality> {
  public inline function new(f) {
    this = f;
  }
  
  @:from
  public static inline function ofSyncOutcome<In, Out, Quality>(f:(items:ReadOnlyArray<In>, status:RegroupStatus)->Outcome<Option<RegroupResult<In, Out, Quality>>, Quality>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> Future.sync(f(items, status)));
  }
  
  @:from
  public static inline function ofSync<In, Out, Quality>(f:(items:ReadOnlyArray<In>, status:RegroupStatus)->Option<RegroupResult<In, Out, Quality>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> Future.sync(f(items, status)));
  }
  
  @:from
  public static inline function ofStatusIgnorance<In, Out, Quality>(f:(items:ReadOnlyArray<In>)->Future<Option<RegroupResult<In, Out, Quality>>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> f(items));
  }
  
  @:from
  public static inline function ofSyncOutcomeStatusIgnorance<In, Out, Quality>(f:(items:ReadOnlyArray<In>)->Outcome<Option<RegroupResult<In, Out, Quality>>, Quality>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> Future.sync(f(items)));
  }
  
  @:from
  public static inline function ofSyncStatusIgnorance<In, Out, Quality>(f:(items:ReadOnlyArray<In>)->Option<RegroupResult<In, Out, Quality>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> Future.sync(f(items)));
  }
  
  @:from
  public static inline function ofStreamOnly<In, Out, Quality>(f:(items:ReadOnlyArray<In>, status:RegroupStatus)->Future<Option<Stream<Out, Quality>>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> f(items, status).map(o -> o.map(RegroupResult.ofStream)));
  }
  
  @:from
  public static inline function ofSyncStreamOnly<In, Out, Quality>(f:(items:ReadOnlyArray<In>, status:RegroupStatus)->Option<Stream<Out, Quality>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> Future.sync(f(items, status).map(RegroupResult.ofStream)));
  }
  
  @:from
  public static inline function ofStatusIgnoranceAndStreamOnly<In, Out, Quality>(f:(items:ReadOnlyArray<In>)->Future<Option<Stream<Out, Quality>>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> f(items).map(o -> o.map(RegroupResult.ofStream)));
  }
  
  @:from
  public static inline function ofSyncStatusIgnoranceAndStreamOnly<In, Out, Quality>(f:(items:ReadOnlyArray<In>)->Option<Stream<Out, Quality>>):Regrouper<In, Out, Quality> {
    return new Regrouper((items, status) -> Future.sync(f(items).map(RegroupResult.ofStream)));
  }
}