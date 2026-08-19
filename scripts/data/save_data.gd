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

const VERSION := 3

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
	return out
