class_name StubHooks
extends GameHooks
## A game's hooks, controllable from a test: it handles exactly the targets it is told to.
##
## It lives here rather than inside a suite because gdUnit4's scanner crashes on a suite whose
## function signature names a project class, and every override here names two.

## Target ids this pretends to be a game's business. Anything else falls through.
var takes: Array[StringName] = []
## Ids it was actually asked about and claimed, in order.
var handled: Array[StringName] = []
## Ids it saw at all, claimed or not - which is how "was game code even consulted?" is asked.
var offered: Array[StringName] = []
## Said when a target is claimed, if set.
var says: StringName = &""
var maps_entered: Array[StringName] = []


func on_interact(ctx: GameContext, target: Interactor.Target) -> bool:
	offered.append(target.id)
	if not takes.has(target.id):
		return false
	handled.append(target.id)
	if not String(says).is_empty():
		ctx.say(says)
	return true


func on_map_entered(ctx: GameContext) -> void:
	maps_entered.append(ctx.map_id)
