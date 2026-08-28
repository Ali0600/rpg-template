class_name SaveData
extends RefCounted
## The shape of a save file, and the only description of it.
##
## Saves are JSON, not Godot Resources. A `.tres` can carry a script path, so loading one is
## close enough to executing code that a save file - the one file a player might be handed by
## someone else - should never be one. JSON is also readable, diffable, and portable to any
## tool that might want to inspect a save.
##
## VERSION is bumped whenever the shape changes, and Migrations carries an old file forward.
## Anything that persists across a session lives here; anything derived is recomputed.

const VERSION := 6

var version: int = VERSION
## Which game wrote this. Added in v3, and the one fact a save carries that no map can
## supply: two games share this build, this save format and these field names, so without it
## a save from one loads into the other and reads as a corrupt world rather than as a
## mismatched file.
var game: StringName = &""
var map: StringName = &""
var position: Vector2 = Vector2.ZERO
var facing: int = Dir.D.DOWN
var flags: Dictionary = {}
var seen: Dictionary = {}
## Carried items as id -> count. Added in v4. Kept as the raw dictionary rather than an
## Inventory: this class describes the FILE, and a file may say things an Inventory would
## refuse - which is what problems() is for.
var items: Dictionary = {}
## Who the player is in a fight, as `{"hp", "xp", "level"}`. Added in v5. EMPTY IS A REAL
## ANSWER and the common one: a save from before battles existed, or from a game that has no
## combat at all, carries no party - and inventing a level-1 hero for it here would be this
## class deciding a rule that belongs to the game's CombatDef, which it cannot see.
var party: Dictionary = {}
## What the player can spend. Added in v6. A plain integer rather than a dictionary like
## `party`: zero is a real answer here (broke), so there is no "unset" to represent.
var gold: int = 0
## Seconds of play. Added in v2, which is what the v1 migration exists to demonstrate.
var play_seconds: float = 0.0


func to_dict() -> Dictionary:
	return {
		"version": version,
		"game": String(game),
		"map": String(map),
		"position": [position.x, position.y],
		"facing": facing,
		"flags": flags,
		"seen": seen,
		"items": items,
		"party": party,
		"gold": gold,
		"play_seconds": play_seconds,
	}


## Builds a save from a dictionary that has ALREADY been migrated. Reading an old shape here
## instead of in Migrations would mean two places knew about old formats, and the second one
## would be the one nobody updated.
static func from_dict(d: Dictionary) -> SaveData:
	var out := SaveData.new()
	out.version = int(d.get("version", VERSION))
	out.game = StringName(str(d.get("game", "")))
	out.map = StringName(str(d.get("map", "")))
	var raw := JsonFile.to_float_array(d.get("position", []))
	if raw.size() == 2:
		out.position = Vector2(raw[0], raw[1])
	out.facing = int(d.get("facing", Dir.D.DOWN))
	out.flags = d.get("flags", {}) if d.get("flags", {}) is Dictionary else {}
	out.seen = d.get("seen", {}) if d.get("seen", {}) is Dictionary else {}
	# Copied, not sanitised: a count of zero is a FAULT to report, not something to quietly
	# tidy away. Inventory.from_dict does the tidying, once the file has been accepted.
	out.items = d.get("items", {}) if d.get("items", {}) is Dictionary else {}
	out.party = d.get("party", {}) if d.get("party", {}) is Dictionary else {}
	# Copied as written, not clamped - a negative purse is a fault to REPORT, the same call
	# the item counts above make.
	out.gold = int(d.get("gold", 0))
	out.play_seconds = float(d.get("play_seconds", 0.0))
	return out


## Structural faults in a loaded save. A save is a file on a player's disk that may have been
## edited, truncated or written by an older build, so nothing in it is assumed.
func problems() -> Array[String]:
	var out: Array[String] = []
	if version != VERSION:
		out.append("save is version %d, this build reads %d" % [version, VERSION])
	if String(game).is_empty():
		out.append("save names no game")
	if String(map).is_empty():
		out.append("save names no map")
	if facing < 0 or facing >= Dir.ALL.size():
		out.append("save has facing %d, which is not a direction" % facing)
	if play_seconds < 0.0:
		out.append("save has negative play time")
	if gold < 0:
		out.append("save carries %d gold" % gold)
	for key: Variant in items.keys():
		# A zero or negative count is a file that has been edited by hand or written by a
		# broken build. Carrying "minus one key" is not a state the game can be in.
		if int(items[key]) <= 0:
			out.append("save carries %s of item '%s'" % [items[key], key])
	# Only a party that is THERE is checked. Absent is legal and means "no combat here"; what
	# cannot be legal is a party present and impossible. The checks stay structural on purpose
	# - whether 40 hp is too much for level 2 is a question for the game's CombatDef, and this
	# class has no way to reach one.
	if not party.is_empty():
		if int(party.get("hp", 0)) < 1:
			out.append("save carries a party at %s hp" % party.get("hp", 0))
		if int(party.get("xp", 0)) < 0:
			out.append("save carries %s xp" % party.get("xp", 0))
		if int(party.get("level", 0)) < 1:
			out.append("save carries a party at level %s" % party.get("level", 0))
	return out
