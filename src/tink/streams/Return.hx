package tink.streams;

using tink.CoreApi;

private enum ReturnKind<T, Quality> {
  Yay(v:T):ReturnKind<T, Quality>;
  Nay(e:Error):ReturnKind<T, Error>;
}

abstract Return<T, Quality>(Future<ReturnKind<T, Quality>>) {

  inline function new(v)
    this = v;

  @:from static function ofError<T>(e:Error):Return<T, Error>
    return new Return(Nay(e));

  @:from static function ofOutcome<T>(o:Outcome<T, Error>):Return<T, Error>
    return new Return(outcome(o));

  static function outcome<T>(o:Outcome<T, Error>)
    return switch o {
      case Success(data): Yay(data);
      case Failure(failure): Nay(failure);
    }

  @:from static function ofPromise<T>(f:Promise<T>):Return<T, Error>
    return new Return(f.map(outcome));

  @:from static function ofFuture<T, Quality>(f:Future<T>):Return<T, Quality>
    return new Return(f.map(Yay));

  @:from static function ofConst<T, Quality>(v:T):Return<T, Quality>
    return ofFuture(v);

}