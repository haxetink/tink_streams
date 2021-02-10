package tink.streams;

using tink.CoreApi;


abstract Return<T, Quality>(Surprise<T, Quality>) {

  inline function new(v)
    this = v;

  @:from static function ofError<T>(e:Error):Return<T, Error>
    return ofPromise(e);

  @:from static function ofOutcome<T, Quality>(o:Outcome<T, Quality>):Return<T, Quality>
    return new Return(Future.sync(o));

  @:from static function ofPromise<T>(f:Promise<T>):Return<T, Error>
    return new Return(f);

  @:from static function ofFuture<T, Quality>(f:Future<T>):Return<T, Quality>
    return new Return(f.map(Success));

  @:from static function ofConst<T, Quality>(v:T):Return<T, Quality>
    return ofFuture(v);

}