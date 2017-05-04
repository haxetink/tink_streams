package tink.streams;

import tink.streams.Stream;
using tink.CoreApi;

class Accumulator<Item, Quality> extends SignalStream<Item, Quality> {
	
	var trigger:SignalTrigger<Yield<Item, Quality>>;
	
	public function new() {
		trigger = Signal.trigger();
		super(trigger.asSignal());
	}
	
	#if php
	@:native('accumulate')
	#end
	public inline function yield(product:Yield<Item, Quality>)
		trigger.trigger(product);
}

class SignalStream<Item, Quality> extends Generator<Item, Quality> {
	public function new(signal:Signal<Yield<Item, Quality>>) {
		super(signal.next().map(function(o):Step<Item, Quality> return switch o {
			case Data(data): Link(data, new SignalStream(signal));
			case Fail(e): Fail(e);
			case End: End;
		}));
	}
}

enum Yield<Item, Quality> {
	Data(data:Item):Yield<Item, Quality>;
	Fail(e:Error):Yield<Item, Error>;
	End:Yield<Item, Quality>;
}
