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

## The verbs the template owns, and the line it does not cross:
##
##   dialog                     a sign, or a conversation
##   set_flag                   a lever
##   once                       a chest, remembered in GameState.seen across saves
##   give_item / give_count     a chest with something in it
##   take_item / take_count     a lantern that drinks the oil
##   requires_item / _count     a lock, with locked_dialog for what it says when it refuses
##
## Items were a game's own business until M12 and are now the template's, because "a count
## rather than a boolean" turned out to be the one noun every game re-invents: a key, a coin,
## a potion and a quest token are one mechanism wearing four names.
##
## HIT POINTS AND TURN ORDER CROSSED THE SAME LINE IN M13, on the same argument one level up -
## every game here would otherwise rewrite "a number that ticks down, a number that ticks up,
## and whose turn it is", each with its own save-migration bug. They live in BattleLogic and
## EnemyDef rather than in these verbs, and a map places a fight the way it places a chest.
##
## What is still over the line: PRICES and ECONOMY, and BATTLE SCRIPTING - what a particular
## boss does on turn three is a game's own business, and GameHooks is where it goes.
##
## Two rules here are invisible at the point they matter:
##
## A TAKE IMPLIES A REQUIRES. A record that takes what the player does not have refuses
## outright rather than emitting a take that fails later - otherwise `once` lands, the chest
## remembers being opened, and the thing inside is gone with nothing on screen having said so.
##
## `once` ON AN NPC MUTES THEM. decide() returns false for a record it has already seen, so a
## person who hands something over needs a dialog choice with `set_flag` + `hidden_if_flag`,
## not `once` - which would leave them standing there with nothing to say ever again.
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
	var gives := str(record.get("give_item", ""))
	var takes := str(record.get("take_item", ""))
	if dialog_id.is_empty() and flag.is_empty() and gives.is_empty() and takes.is_empty():
		return false

	# Both refusals happen BEFORE anything is appended, so the effect list is all or nothing.
	# A lock that emitted half its effects and then refused would set the flag on a door it
	# did not open.
	var needs := str(record.get("requires_item", ""))
	if not needs.is_empty() and not ctx.has_item(StringName(needs), int(record.get("requires_count", 1))):
		return _refuse(record, ctx)
	var take_count := int(record.get("take_count", 1))
	if not takes.is_empty() and not ctx.has_item(StringName(takes), take_count):
		return _refuse(record, ctx)

	# Said first, and that is a contract: a dialog opened by an interaction reads the state as
	# it was BEFORE this interaction's own flag and items land. A conversation that needs to
	# see them is a hook's job, where the order is the game's to choose.
	if not dialog_id.is_empty():
		ctx.say(StringName(dialog_id))
	# Applied on the interaction itself, unlike a flag inside a conversation, which lands
	# when the line is actually reached. You opened the chest; closing the box early does
	# not un-open it.
	if not flag.is_empty():
		ctx.set_flag(StringName(flag))
	if not gives.is_empty():
		# After the two all-or-nothing refusals above, so a take that could not be covered
		# never makes a pickup noise for something the player did not get.
		ctx.play(Sfx.id_of(Sfx.Cue.PICKUP))
		ctx.give_item(StringName(gives), int(record.get("give_count", 1)))
	if not takes.is_empty():
		ctx.take_item(StringName(takes), take_count)
	if once:
		ctx.mark_seen(key)
	return true


## A lock that will not open. HANDLED, not ignored: the player pressed a real thing and it
## answered, so the caller must stop looking for another target - and `once` deliberately does
## not fire, or a chest would remember being opened by someone who could not open it.
static func _refuse(record: Dictionary, ctx: GameContext) -> bool:
	var locked := str(record.get("locked_dialog", ""))
	# Appended BEFORE the line, because the sink applies effects in order and the thud belongs
	# to the door rather than to the sentence about it.
	ctx.play(Sfx.id_of(Sfx.Cue.LOCKED))
	if not locked.is_empty():
		ctx.say(StringName(locked))
	return true


## Map-scoped, so two maps can each have a chest called "chest" without sharing the memory of
## having been opened - the bug being that the second one is already empty when you find it.
static func seen_key(map_id: StringName, object_id: String) -> String:
	return "%s/%s" % [map_id, object_id]
