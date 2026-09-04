extends Node
## What the PLAYER chose, as opposed to what the game is. Global, and outside every save slot.
##
## A save is one run of one game; a setting belongs to the person at the keyboard and must
## survive starting over, switching game and deleting every slot. So it lives in its own file
## and carries no version: there is one field, a value it does not recognise falls back to the
## default, and a migration chain for that would be ceremony.
##
## Redirected under a --qa-script run for the same reason saves are. A suite that writes the
## real file would leave a player's volume wherever the last test left it - and a harness that
## runs the suite with things deliberately broken would do it while they were broken.
##
## It carries a PALETTE id beside the volume now, and still no version: an id this build does not
## know falls back the way an out-of-range volume does. Deliberately just the id - which palettes
## exist is a content question, so the WORLD resolves it and the one place "unknown falls back to
## the style's own" is written is there. This file would otherwise be a second opinion about what
## a palette is, held by the one class that may not ask the Registry.

const DEFAULT_PATH := "user://settings.json"
const QA_PATH := "user://qa_settings.json"

## How loud, as named steps rather than a slider. A slider needs a second input axis the menu
## does not have, and four steps is what a pause menu can say in one word.
enum Level { OFF, QUIET, NORMAL, LOUD }

## Linear gain per step. Not evenly spaced: hearing is roughly logarithmic, so evenly spaced
## numbers sound like three loud settings and one quiet one.
const GAINS: Dictionary = {
	Level.OFF: 0.0,
	Level.QUIET: 0.25,
	Level.NORMAL: 0.6,
	Level.LOUD: 1.0,
}

const NAMES: Dictionary = {
	Level.OFF: "Off",
	Level.QUIET: "Quiet",
	Level.NORMAL: "Normal",
	Level.LOUD: "Loud",
}

const DEFAULT_LEVEL := Level.NORMAL

## No palette chosen: the running style's own chrome, which is what every game shipped on this
## template looked like before there was a choice. Empty rather than a named "default" palette,
## because the style's colours are not a file and cannot be one - a game with no palettes at all
## still has to have an answer here.
const NO_PALETTE := &""

var _path := DEFAULT_PATH
var _level: Level = DEFAULT_LEVEL
var _palette: StringName = NO_PALETTE


func _ready() -> void:
	_path = path_for(GameSelect.args())
	_read()
	_apply()
	EventBus.system_ready.emit({"system": &"Settings"})


## Where settings live for this run, as a pure function of the command line so it can be
## proven without arranging a process - the SaveManager.dir_for shape.
static func path_for(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(GameSelect.QA_ARG):
			return QA_PATH
	return DEFAULT_PATH


func path() -> String:
	return _path


func sound_level() -> Level:
	return _level


func sound_gain() -> float:
	return float(GAINS.get(_level, GAINS[DEFAULT_LEVEL]))


func sound_name() -> String:
	return str(NAMES.get(_level, NAMES[DEFAULT_LEVEL]))


## The next step round, applied and written. One button cycles because the pause menu has one:
## up and down move the cursor, and confirm is the only thing left.
func cycle_sound() -> Level:
	_level = ((_level + 1) % Level.size()) as Level
	_apply()
	_write()
	return _level


func palette() -> StringName:
	return _palette


## The next palette round, applied and written. `ids` is what the world found in the Registry, in
## its own order, and NO_PALETTE is the first stop - so the cycle always offers a way back to the
## style's own chrome, including from a palette this build no longer ships.
##
## A current id that is not in `ids` counts as the default rather than as a member: it is what a
## file naming a deleted palette holds, and treating it as a member would make `find` answer -1
## and the next press land on the second entry.
func cycle_palette(ids: Array[StringName]) -> StringName:
	var ring: Array[StringName] = [NO_PALETTE]
	ring.append_array(ids)
	var at := ring.find(_palette)
	_palette = ring[(maxi(at, 0) + 1) % ring.size()]
	_write()
	return _palette


## Used by tests to put the setting back without going through the file, like set_sound_level.
func set_palette(id: StringName) -> void:
	_palette = id


## Points this at another file and re-reads it.
##
## Exists so a suite can redirect the autoload away from the player's real settings before it
## touches anything. A test that cycled the volume would otherwise write it - and a mutation
## harness runs the suite with the code deliberately broken, so it would write it WRONG. The
## suite asserts the redirect is in effect rather than trusting it, because the day it stops
## being applied is the day the tests quietly start editing somebody's preferences.
func use_path(new_path: String) -> void:
	_path = new_path
	_level = DEFAULT_LEVEL
	_palette = NO_PALETTE
	_read()
	_apply()


## Used by tests to put the setting back without going through the file.
func set_sound_level(level: Level) -> void:
	_level = level
	_apply()


func _apply() -> void:
	AudioBus.set_volume(sound_gain())


func _read() -> void:
	var file := JsonFile.read(_path)
	if not file.ok:
		# Absent is the normal case on a first run, and unreadable is not worth a fuss for one
		# number: either way the default is right and the next write repairs the file.
		return
	# The palette FIRST, so a file with an impossible volume still gives up its chrome. The two
	# fields are independent choices and one being unreadable says nothing about the other.
	_palette = StringName(str(file.data.get("palette", NO_PALETTE)))
	var raw := int(file.data.get("sound_level", DEFAULT_LEVEL))
	if raw < 0 or raw >= Level.size():
		push_warning("Settings: '%s' has an unknown sound level %d" % [_path, raw])
		return
	_level = raw as Level


func _write() -> void:
	var err := JsonFile.write(_path, {"sound_level": int(_level), "palette": String(_palette)})
	if err != OK:
		# Said out loud rather than swallowed: a setting that silently fails to persist looks
		# exactly like one that was never changed, and the player will change it again.
		push_error("Settings: could not write %s (error %d)" % [_path, err])
