class_name InputGate
extends RefCounted
## Lets a handler act on each input event exactly once.
##
## The same InputEvent can reach a node more than once in a single frame - a parent
## forwarding it, or a test harness that both parses the event and calls `_unhandled_input`
## directly. For a handler that TOGGLES something, acting twice returns it to where it
## started and the key looks dead, which is a miserable thing to debug.
##
## Identity alone is not enough to spot the duplicate, and getting that wrong is worse than
## not guarding at all: the engine REUSES event instances between frames, so "have I seen
## this object before?" answers yes to every genuine repeated press and swallows the lot.
## The duplicate to reject is the same object in the same FRAME; the same object a frame
## later is a person pressing the button again.

var _last: InputEvent = null
var _frame: int = -1


## True the first time an event is offered in a frame, false for any repeat of it.
func accept(event: InputEvent) -> bool:
	var frame := Engine.get_process_frames()
	if event == _last and frame == _frame:
		return false
	_last = event
	_frame = frame
	return true
