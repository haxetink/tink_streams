package tink.streams;

import tink.streams.Stream;
using tink.CoreApi;

class Accumulator<Item, Quality> extends Chained<Item, Quality> {
	
	var buffer:Array<FutureTrigger<Chain<Item, Quality>>>;
	
	public function new() {
		buffer = [Future.trigger()];
		super(buffer[0]);
	}
	
	#if php
	@:native('accumulate')
	#end
	public function yield(step:AccumulatorStep<Item, Quality>) {
		var last = buffer[buffer.length - 1];
		last.trigger(switch step {
			case Data(data):
				var next = Future.trigger();
				buffer.push(next);
				ChainLink(data, new Chained(next));
			case Fail(e):
				ChainError(e);
			case End:
				ChainEnd;
		});
	}
}

enum AccumulatorStep<Item, Quality> {
	Data(data:Item):AccumulatorStep<Item, Quality>;
	Fail(e:Error):AccumulatorStep<Item, Error>;
	End:AccumulatorStep<Item, Quality>;
}
