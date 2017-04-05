package tink.streams;

import tink.streams.Stream;
using tink.CoreApi;

class Accumulator<Item, Quality> extends Generator<Item, Quality> {
	
	var buffer:Array<FutureTrigger<Step<Item, Quality>>>;
	
	public function new() {
		buffer = [Future.trigger()];
		super(buffer[0]);
	}
	
	#if php
	@:native('accumulate')
	#end
	public function yield(product:Yield<Item, Quality>) {
		var last = buffer[buffer.length - 1];
		last.trigger(switch product {
			case Data(data):
				var next = Future.trigger();
				buffer.push(next);
				Link(data, new Generator(next));
			case Fail(e):
				Fail(e);
			case End:
				End;
		});
	}
}

enum Yield<Item, Quality> {
	Data(data:Item):Yield<Item, Quality>;
	Fail(e:Error):Yield<Item, Error>;
	End:Yield<Item, Quality>;
}
