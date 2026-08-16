class_name Interaction
extends RefCounted
## What pressing the button does, decided from data, with no nodes and no autoloads.
##
## Split out of world_scene for the reason DialogRunner is split out of DialogBox: "a chest
## opens once" deserves a test that reads a result rather than one that drives a scene.
##
## Game code gets FIRST REFUSAL, then the built-in verbs run. Both halves append to the same
## effect list on the same GameContext, which is the point: a hook cannot acquire a power the
## data lacks, a chest cannot acquire one the hook lacks, and there is one place where any of
## it reaches the autoloads.

## The verbs the template owns, and the line it does not cross. Each one is a composition of
## nouns the template already has - a dialog, a flag, the memory of having done it - so
## extending them from NPCs to any tile finishes a job rather than starting a new one:
##
##   dialog             a sign, or a conversation
##   set_flag           a lever
##   once               a chest, remembered in GameState.seen across saves
##
## Items with names and counts, currency, prices, hit points, turn order: those need nouns
## the template does not have, and they belong in a game's own hooks. The moment a map file
## needs a type system, the template has started designing somebody's game.
static func resolve(hooks: GameHooks, ctx: GameContext, target: Interactor.Target) -> bool:
	if hooks != null and hooks.on_interact(ctx, target):
		return true
	var record: Dictionary = target.payload if target.payload is Dictionary else {}
	return decide(record, ctx)


## The built-in verbs. Returns whether anything happened at all - false means the player
## pressed the button at something with nothing to say, and the caller should keep looking.
static func decide(record: Dictionary, ctx: GameContext) -> bool:
	var once := bool(record.get("once", false))
	var key := seen_key(ctx.map_id, str(record.get("id", "")))
	if once and ctx.was_seen(key):
		return false

	var dialog_id := str(record.get("dialog", ""))
	var flag := str(record.get("set_flag", ""))
	if dialog_id.is_empty() and flag.is_empty():
		return false

	if not dialog_id.is_empty():
		ctx.say(StringName(dialog_id))
	# Applied on the interaction itself, unlike a flag inside a conversation, which lands
	# when the line is actually reached. You opened the chest; closing the box early does
	# not un-open it.
	if not flag.is_empty():
		ctx.set_flag(StringName(flag))
	if once:
		ctx.mark_seen(key)
	return true


## Map-scoped, so two maps can each have a chest called "chest" without sharing the memory of
## having been opened - the bug being that the second one is already empty when you find it.
static func seen_key(map_id: StringName, object_id: String) -> String:
	return "%s/%s" % [map_id, object_id]
