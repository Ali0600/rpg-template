extends Node
## The game-flow state machine, and the single owner of "can the player move right now?"
##
## Every system that needs to take control away - a dialog box, a pause menu, a map
## transition - asks for a state here instead of setting its own flag. One owner is the
## whole point: two independent `can_move` booleans is how a player ends up frozen after a
## dialog that closed, with each system certain it released control.

## Appended to, never reordered: flow_changed carries these as ints, and a member inserted in
## the middle renames every state after it in anything holding a number.
enum State {
	TITLE,  ## nothing to drive yet
	WORLD,  ## the only state the player moves in
	DIALOG,  ## a conversation is open; movement is suspended
	PAUSED,  ## a menu is open over the world
	BATTLE,  ## a fight has the screen; the world is still there underneath
	GAME_OVER,  ## the run ended; the only ways on are a save or a fresh start
	## A counter is open. An overlay like every other: the world is still there behind it
	## and the player cannot walk, which player_can_move() already answers without an edit.
	SHOP,
	## A night is passing. An overlay with nothing to press: it ends on its own, and the
	## point of it being a state at all is that the player cannot walk out of a fade.
	RESTING,
}

var _state: State = State.TITLE
## States pushed by overlays, so closing one returns to what was underneath rather than
## guessing at WORLD - a menu opened from a dialog must not leave the dialog unreachable.
var _stack: Array[State] = []


func state() -> State:
	return _state


## Derived from the enum rather than from a list beside it: a hand-kept array of names is a
## second source of truth that an inserted member silently shifts, renaming every state after
## it. find_key rather than keys()[_state], so it survives non-sequential values too.
func state_name() -> String:
	return str(State.find_key(_state)).to_lower()


## The one question. Everything that moves the player asks this; nothing keeps its own copy.
func player_can_move() -> bool:
	return _state == State.WORLD


## Whether gameplay input (interacting, opening the menu) is accepted at all.
##
## The same condition as movement today, and deliberately delegated rather than repeated:
## two functions with identical bodies are two things that will drift the first time one of
## them needs to change. It keeps its own name because it answers a different question - a
## game that let you read the map while paused would change this one and not the other.
func accepts_world_input() -> bool:
	return player_can_move()


func set_state(next: State) -> void:
	if next == _state:
		return
	var previous := _state
	_state = next
	EventBus.flow_changed.emit({"from": previous, "to": next})


## Opens an overlay state, remembering what it covered. Symmetric with `close_overlay` -
## every open must have a matching close, or the state that "vanished" is really still on
## the stack holding input hostage.
func open_overlay(overlay: State) -> void:
	_stack.append(_state)
	set_state(overlay)


func close_overlay() -> void:
	if _stack.is_empty():
		# Nothing was open. Falling back to WORLD rather than staying stuck is the safer
		# failure: a stuck overlay state means the game stops responding entirely.
		set_state(State.WORLD)
		return
	set_state(_stack.pop_back())


func overlay_depth() -> int:
	return _stack.size()


## Returns to a clean world state. Used on map entry and by tests, which share an autoload
## and would otherwise inherit whatever the previous case left open.
func reset() -> void:
	_stack.clear()
	_state = State.WORLD
