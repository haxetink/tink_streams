package tink.streams;

import tink.streams.Stream;
using tink.CoreApi;

class Accumulator<Item, Quality> extends Generator<Item, Quality> {
	
	var buffer:Array<FutureTrigger<Step<Item, Quality>>>;
	var ended = false;
	
	public function new() {
		buffer = [Future.trigger()];
		super(buffer[0]);
	}
	
	#if php
	@:native('accumulate')
	#end
	public function yield(product:Yield<Item, Quality>) {
		if(ended) return;
		buffer[buffer.length - 1].trigger(switch product {
			case Data(data):
				var next = Future.trigger();
				buffer.push(next);
				Link(data, new Generator(next));
			case Fail(e):
				ended = true;
				Fail(e);
			case End:
				ended = true;
				End;
		});
	}
}

enum Yield<Item, Quality> {
	Data(data:Item):Yield<Item, Quality>;
	Fail(e:Error):Yield<Item, Error>;
	End:Yield<Item, Quality>;
}
