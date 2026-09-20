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


## Which action a stick was last seen holding, per action, so a held stick presses ONCE.
var _stick: Dictionary = {}


## Whether an event is a press worth reading at all - the guard every screen's handler opens with.
## A motion event ALWAYS passes: its own is_pressed() is the engine's toggle point, and the stick
## that let go (0.0) has to reach pressed() so the latch there can be released.
static func is_press(event: InputEvent) -> bool:
	return event is InputEventJoypadMotion or (event.is_pressed() and not event.is_echo())


## Whether this event presses `action`, read the way a cursor needs it.
##
## A key, a pad button or a harness action answers is_action_pressed(). A stick differs in two ways
## the engine's own calls do not say out loud: is_action() matches by AXIS, so a stick pushed UP "is"
## move_down too and only is_action_pressed() carries the sign; and a held stick sends one event per
## value change. So a motion event counts once the engine calls it pressed (its own toggle point) AND
## the action's direction agrees - and then not again until the stick has let go of that action.
func pressed(event: InputEvent, action: StringName) -> bool:
	if not event is InputEventJoypadMotion:
		return event.is_action_pressed(action)
	var down := event.is_pressed() and event.is_action_pressed(action)
	var was: bool = _stick.get(action, false)
	_stick[action] = down
	return down and not was
