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

const VERSION := 9

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
## Who the player is in a fight, as `{"hp", "xp", "level", "mp"}`. Added in v5, and `mp` in v8.
## EMPTY IS A REAL ANSWER and the common one: a save from before battles existed, or from a
## game that has no combat at all, carries no party - and inventing a level-1 hero for it here
## would be this class deciding a rule that belongs to the game's CombatDef, which it cannot see.
##
## MP is a key in here rather than a field of its own for the same reason: magic is part of
## being a fighter, so a game with no party has no magic to record either.
var party: Dictionary = {}
## Everyone else in the party, as member id -> `{"hp", "xp", "level", "mp", "equipment"}`.
## Added in v9. Keyed by member rather than a positional list, because a roster reordered in a
## game's manifest would then make every existing save describe the wrong person - silently,
## and only for players who already had a party.
##
## The LEADER is not in here; they are `party` above, which is what leaves every v8 reader,
## every mutant and every QA assertion pointing exactly where it already pointed. Empty is the
## normal state and is what a game with no party writes forever.
var companions: Dictionary = {}
## What the player can spend. Added in v6. A plain integer rather than a dictionary like
## `party`: zero is a real answer here (broke), so there is no "unset" to represent.
var gold: int = 0
## What is worn, as slot -> item id. Added in v7. A dictionary rather than two fields because
## the slots are the game's vocabulary, not this class's: a save from a game with three slots
## carries three keys and this file needs no edit to hold them.
var equipment: Dictionary = {}
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
		"companions": companions,
		"gold": gold,
		"equipment": equipment,
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
	out.companions = d.get("companions", {}) if d.get("companions", {}) is Dictionary else {}
	# Copied as written, not clamped - a negative purse is a fault to REPORT, the same call
	# the item counts above make.
	out.gold = int(d.get("gold", 0))
	out.equipment = d.get("equipment", {}) if d.get("equipment", {}) is Dictionary else {}
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
	# The file checked against ITSELF: a save that equips what its own bag does not carry is
	# describing a player who cannot exist, and loading it would arm a phantom. With a party
	# this is a COUNT rather than a presence - two people wearing one carried sword is exactly
	# as impossible as one person wearing a sword nobody carries, and only the tally sees it.
	var claimed: Dictionary = {}
	out.append_array(_worn_problems(equipment, "", claimed))
	for id: Variant in companions.keys():
		var record: Dictionary = companions[id] if companions[id] is Dictionary else {}
		var worn_by_them: Dictionary = record.get("equipment", {}) \
			if record.get("equipment", {}) is Dictionary else {}
		out.append_array(_worn_problems(worn_by_them, str(id), claimed))
	for worn_id: Variant in claimed.keys():
		if int(claimed[worn_id]) > int(items.get(worn_id, 0)):
			out.append("save has %d wearing '%s' but carries %s"
				% [claimed[worn_id], worn_id, items.get(worn_id, 0)])
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
		# Zero health is legal ONLY with a companion in the file. Alone it is the shape the
		# world reads as "never fought" and would refill from the curve; beside somebody who
		# was left standing it is a player who fell and is being walked to an inn, which is a
		# state the game produces and must be able to write down.
		var leader_hp := int(party.get("hp", 0))
		if leader_hp < 0 or (leader_hp < 1 and companions.is_empty()):
			out.append("save carries a party at %s hp" % party.get("hp", 0))
		if int(party.get("xp", 0)) < 0:
			out.append("save carries %s xp" % party.get("xp", 0))
		if int(party.get("level", 0)) < 1:
			out.append("save carries a party at level %s" % party.get("level", 0))
		# Zero is legal here where zero hp is not: a player who has spent every point is in a
		# perfectly ordinary state, and only a negative one describes a player who cannot exist.
		# How much is TOO much is a CombatDef question this class still cannot ask.
		if int(party.get("mp", 0)) < 0:
			out.append("save carries %s mp" % party.get("mp", 0))
	# Companions get the same structural read, and one more: a companion beside NO party at all
	# is a file describing somebody who joined a player who does not exist.
	if not companions.is_empty() and party.is_empty():
		out.append("save carries %d companions and no party" % companions.size())
	for id: Variant in companions.keys():
		if String(str(id)).is_empty():
			out.append("save carries a companion with no id")
		if not companions[id] is Dictionary:
			out.append("save carries companion '%s' as something other than a record" % id)
			continue
		var record: Dictionary = companions[id]
		# Zero health is legal for a companion with no qualification at all - a fallen one is
		# the ordinary outcome of a fight the party won, and the inn is what undoes it.
		if int(record.get("hp", 0)) < 0:
			out.append("save carries companion '%s' at %s hp" % [id, record.get("hp", 0)])
		if int(record.get("xp", 0)) < 0:
			out.append("save carries companion '%s' with %s xp" % [id, record.get("xp", 0)])
		if int(record.get("level", 0)) < 1:
			out.append("save carries companion '%s' at level %s" % [id, record.get("level", 0)])
		if int(record.get("mp", 0)) < 0:
			out.append("save carries companion '%s' with %s mp" % [id, record.get("mp", 0)])
	return out


## One member's slot map, checked and tallied into `claimed`. Shared by the leader and every
## companion so the two cannot drift into disagreeing about what a worn slot must look like.
func _worn_problems(worn: Dictionary, who: String, claimed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var whose := "" if who.is_empty() else " for '%s'" % who
	for slot: Variant in worn.keys():
		var id := str(worn[slot])
		if id.is_empty():
			out.append("save equips nothing in slot '%s'%s" % [slot, whose])
			continue
		if int(items.get(id, 0)) <= 0:
			out.append("save equips '%s' in slot '%s'%s but carries none" % [id, slot, whose])
		claimed[id] = int(claimed.get(id, 0)) + 1
	return out
