package tink.streams;

import tink.streams.Stream;
using tink.CoreApi;

@:forward(trigger)
abstract AccumulatorTrigger<Item, Quality>(SignalTrigger<Yield<Item, Quality>>) from SignalTrigger<Yield<Item, Quality>> to SignalTrigger<Yield<Item, Quality>> {
	public inline function new()
		this = Signal.trigger();
		
	@:to
	public inline function asStream():Stream<Item, Quality>
		return new SignalStream(this.asSignal());
}

class Accumulator<Item, Quality> extends SignalStream<Item, Quality> {
	
	public static inline function trigger<Item, Quality>():AccumulatorTrigger<Item, Quality>
		return new AccumulatorTrigger();
	
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
