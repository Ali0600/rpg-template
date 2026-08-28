class_name GameContext
extends RefCounted
## What a game's own code is allowed to see, and how it asks for things to happen.
##
## Game code is handed one of these instead of the autoloads, and that is not a style
## preference. `--check-only` and tools/compile_all.gd both SKIP any script that names a
## singleton, because a singleton does not exist in a standalone run - so game code reaching
## for `GameState.` would quietly leave two of the four gates and could only fail in front of
## a player. Reading a snapshot keeps it inside every gate, and testable with no scene tree.
##
## It also follows the DialogRunner precedent: effects are COLLECTED here and applied once,
## by the one caller that owns the autoloads. A hook cannot half-apply a change, and there is
## exactly one place to look for "what does an interaction actually do".
##
## `set_flag(key, false)` is how a game clears a flag - the dialog format can only ever set
## one true, deliberately, so anything conditional beyond that is three lines of game code
## rather than a new grammar in the dialog files.

const OP_FLAG := &"flag"
const OP_SEEN := &"seen"
const OP_DIALOG := &"dialog"
const OP_WARP := &"warp"
const OP_SOUND := &"sound"
const OP_GIVE_ITEM := &"give_item"
const OP_TAKE_ITEM := &"take_item"
const OP_PARTY := &"party"
const OP_GOLD := &"gold"

## Where the player is, at the moment the hook was called.
var map_id: StringName = &""
var player_tile: Vector2i = Vector2i.ZERO

## The live world node, for a game that has to add scenes of its own - a battle, a shop.
## Typed as Node so nothing here depends on the world's shape.
var world: Node = null

var _flags: Dictionary = {}
var _seen: Dictionary = {}
## What the player is carrying, as a snapshot. A hook asks "do I have the key" and cannot
## reach in and take it: giving and taking are effects like everything else.
var _items: Dictionary = {}
var _effects: Array[Dictionary] = []


static func create(in_map: StringName, at_tile: Vector2i, flags: Dictionary, seen: Dictionary,
		world_node: Node = null, items: Dictionary = {}) -> GameContext:
	var ctx := GameContext.new()
	ctx.map_id = in_map
	ctx.player_tile = at_tile
	# Duplicated, so a hook holding onto a context cannot reach back into live state, and so
	# reads inside one interaction are consistent with each other.
	ctx._flags = flags.duplicate()
	ctx._seen = seen.duplicate()
	ctx._items = items.duplicate()
	ctx.world = world_node
	return ctx


func has_flag(key: StringName) -> bool:
	return bool(_flags.get(key, false))


func was_seen(key: String) -> bool:
	return bool(_seen.get(key, false))


func set_flag(key: StringName, value: bool = true) -> void:
	_effects.append({"op": OP_FLAG, "key": key, "value": value})


func mark_seen(key: String) -> void:
	_effects.append({"op": OP_SEEN, "key": key})


## Opens a dialog file by id, as talking to an NPC does.
func say(dialog_id: StringName) -> void:
	_effects.append({"op": OP_DIALOG, "dialog": dialog_id})


func warp_to(to_map: StringName, to_spawn: StringName) -> void:
	_effects.append({"op": OP_WARP, "map": to_map, "spawn": to_spawn})


## Whether the player is carrying at least n of an item.
func has_item(id: StringName, n: int = 1) -> bool:
	return Inventory.has_in(_items, id, n)


func item_count(id: StringName) -> int:
	return int(_items.get(id, 0))


## Asks for an item to be handed over. Like every other effect it is COLLECTED, so a hook
## cannot half-give a thing and the one sink is still the only place an inventory changes.
func give_item(id: StringName, n: int = 1) -> void:
	_effects.append({"op": OP_GIVE_ITEM, "id": id, "count": n})


## Asks for an item to be consumed. Check has_item() first: the sink logs a take it cannot
## cover rather than going negative, which is a bug report, not a game rule.
func take_item(id: StringName, n: int = 1) -> void:
	_effects.append({"op": OP_TAKE_ITEM, "id": id, "count": n})


func play(sound_id: StringName) -> void:
	_effects.append({"op": OP_SOUND, "id": sound_id})


## How a fight reports what it did to the player. One effect carrying all three numbers rather
## than three carrying one each: hp, xp and level move together and are meaningless apart - a
## level applied without the full heal that came with it is a player the curve says should be
## stronger and the save says is nearly dead.
func set_party(hp: int, xp: int, level: int) -> void:
	_effects.append({"op": OP_PARTY, "hp": hp, "xp": xp, "level": level})


## What the caller should carry out. A copy: reading the list must not be able to change it.
func effects() -> Array[Dictionary]:
	return _effects.duplicate(true)


func has_effects() -> bool:
	return not _effects.is_empty()
