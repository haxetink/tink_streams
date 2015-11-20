package tink.streams;

using tink.CoreApi;

enum StreamStep<T> {
  Data(data:T);
  End;
  Fail(e:Error);
}