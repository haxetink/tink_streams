# Tinkerbell Streams

[![Build Status](https://travis-ci.org/haxetink/tink_streams.svg?branch=master)](https://travis-ci.org/haxetink/tink_streams)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/haxetink/public)

This library provides immutable streams, which are vaguely similar to iterators but might more accurately be thought of as immutable asynchronous lazy lists. Progressing along a stream yields a new stream instead modifying the original. The data in a stream is generated *as needed*.

Because the world is a harsh place, we must discern "real" streams from "ideal" streams, where the former may yield errors, while the latter will not. To deal with this distinction, `tink_streams` makes relatively strong use of [GADTs](http://code.haxe.org/category/functional-programming/enum-gadt.html), a somewhat arcane feature of Haxe. 

In a nutshell, the distinction is expressed like so:
  
```haxe
typedef RealStream<Item> = Stream<Item, Error>;
typedef IdealStream<Item> = Stream<Item, Noise>;
```

So a "real stream of items" is a "stream of items with errors", while an "ideal stream of items" is a "stream of items with nothing" (in tinkerbell `Noise` is used to express nothingness, because of the limitations `Void` exhibits). So let's have a look at what a stream looks like and how we can operate on it:

```haxe
abstract Stream<Item, Quality> {
  function forEach<Safety>(handle:Handler<Item, Safety>):Future<Conclusion<Item, Safety, Quality>>;
}

typedef Handler<Item, Safety> = Item->Future<Handled<Safety>>;

enum Handled<Safety> {
  BackOff:Handled<Safety>;
  Finish:Handled<Safety>;
  Resume:Handled<Safety>;
  Fail(e:Error):Handled<Error>;
}

enum Conclusion<Item, Safety, Quality> {
  Halted(rest:Stream<Item, Quality>):Conclusion<Item, Safety, Quality>;
  Clogged(error:Error, at:Stream<Item, Quality>):Conclusion<Item, Error, Quality>;
  Failed(error:Error):Conclusion<Item, Safety, Error>;
  Depleted:Conclusion<Item, Safety, Quality>;
}
```

Don't let this zoo of type parameters irritate you. They all have their place and we actually know two of them already: `Item` denotes the type of items that flow through the stream and `Quality` is what we use to draw the line between ideal and real streams.

There are many more functions defined on streams, but `forEach` is by far the most important one. As we see it accepts a handler for `Item` with a certain `Safety`. This is to allow us to differentiate ideal and real handlers (although we don't explicitly define them). A handler is a function that gets an item and then tells us how it has handled it. It can either `BackOff`, thus stopping iteration *before* that item, or `Finish` this stopping iteration *after* that item, it can `Resume` the iteration or - if it is a `Handler<Item, Error>` - it may `Fail`.

Iteration can be concluded for various reasons which are thus expressed in the `Conclusion` enum, which handles four cases:
  
- `Halted`: the handler stopped the iteration. The `rest` then represent the remaining stream. So if the handler returns `BackOff` the first item of the remaining stream will be the last item the handler treated, otherwise it's all the items that would have been passed to the handler, had it not stopped.
- `Clogged`: the handler raised an `error` and `at` is the remaining stream (including the item where the error was raised)
- `Failed`: the stream failed. Note that no remaining stream is given, because when streams fail, they end.
- `Depleted`: the whole stream was used up. Therefore this case also has no remaining stream.

If the stream is ideal (and thus `Quality` is not `Error`), then `Failed` is unexpected, if the handler is ideal (and thus `Safety` is not `Error`), then `Clogged` is unexpected.
