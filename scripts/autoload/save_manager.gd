extends Node
## Writes and reads save slots as JSON, one directory per game.
##
## The rule that matters most here is what happens to a save that will not parse. A player's
## save file is their progress; a loader that falls back to a fresh game and then lets the
## next autosave write over the bad bytes has destroyed both the progress AND the only
## evidence of what went wrong. So the raw bytes are parked under `.corrupt` BEFORE anything
## else is touched, and the failure is reported rather than swallowed.
##
## Slots are per game because two games share this build and this file format: `slot_0.json`
## has to mean one thing, and "the demo's first slot" is that thing. A save also NAMES its
## game, so the directory is checked against the file rather than trusted - a file moved,
## copied or hand-edited into the wrong game is refused and preserved, never loaded.

const SLOT_FORMAT := "%s/%s/slot_%d.json"
const DEFAULT_DIR := "user://saves"

## Where a scripted play session saves. A QA script that wrote to the real directory would
## overwrite a player's progress on a machine that has both; one that READ from it would be
## a test whose result depends on who ran it. Wiped at boot so a rerun starts from nothing.
const QA_DIR := "user://qa_saves"

## Overridable so tests never touch a real player's slots.
var base_dir: String = DEFAULT_DIR


## Everything one read of a slot found, with nothing done about it. Kept as a value so the
## quiet read (a menu listing slots) and the loud one (a player pressing Load) can share the
## reading and disagree only about what to do with it.
class Reading:
	var exists := false
	var text := ""
	## The save, or null when anything at all was wrong with it.
	var data: SaveData = null
	var faults: Array[String] = []


func _ready() -> void:
	base_dir = dir_for(GameSelect.args())
	if base_dir == QA_DIR:
		_wipe_qa_dir()
	EventBus.system_ready.emit({"system": &"SaveManager"})


## Where saves live for this run, as a pure function of the command line so it can be proven
## without arranging a process.
static func dir_for(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(GameSelect.QA_ARG):
			return QA_DIR
	return DEFAULT_DIR


func slot_path(game: StringName, slot: int) -> String:
	return SLOT_FORMAT % [base_dir, game, slot]


func corrupt_path(game: StringName, slot: int) -> String:
	return slot_path(game, slot) + ".corrupt"


func has_slot(game: StringName, slot: int) -> bool:
	return FileAccess.file_exists(slot_path(game, slot))


func save(slot: int, data: SaveData) -> bool:
	# The game comes from the save rather than from an argument: two sources for one fact is
	# how a file ends up in a directory that disagrees with it, which is the thing load_slot
	# exists to catch.
	var problems := data.problems()
	if not problems.is_empty():
		for p in problems:
			push_error("SaveManager: refusing to write slot %d: %s" % [slot, p])
		EventBus.save_changed.emit({"game": data.game, "slot": slot, "action": &"save", "ok": false})
		return false

	# Nothing may be written over bytes we could not read. A menu offers Load only for slots
	# that read back, so an unreadable slot looks EMPTY - and saving into it would be the one
	# path that destroys a damaged file without anyone ever being told it existed.
	var held := _read(data.game, slot)
	if held.exists and held.data == null:
		_park_corrupt(data.game, slot, held.text)

	var path := slot_path(data.game, slot)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not write slot %d (error %d)" % [slot, FileAccess.get_open_error()])
		EventBus.save_changed.emit({"game": data.game, "slot": slot, "action": &"save", "ok": false})
		return false
	file.store_string(JSON.stringify(data.to_dict(), "\t") + "\n")
	file.close()
	EventBus.save_changed.emit({"game": data.game, "slot": slot, "action": &"save", "ok": true})
	return true


## Returns null when the slot cannot be read, having preserved whatever was there. The caller
## decides what to do about it - starting a new game is a decision, not a fallback this
## should make silently.
func load_slot(game: StringName, slot: int) -> SaveData:
	var reading := _read(game, slot)
	if not reading.exists:
		return null
	if reading.data == null:
		# Readable but wrong is kept too, because "the save loaded and the player was
		# somewhere impossible" is a bug report that needs the original file.
		_park_corrupt(game, slot, reading.text)
		for f in reading.faults:
			push_error("SaveManager: %s slot %d: %s" % [game, slot, f])
		EventBus.save_changed.emit({"game": game, "slot": slot, "action": &"load", "ok": false})
		return null

	EventBus.save_changed.emit({"game": game, "slot": slot, "action": &"load", "ok": true})
	return reading.data


## The slot list's read: what is in this slot, with NOTHING done about it. A menu drawing three
## rows must not park files, log errors or announce loads it did not perform - an interface that
## acquires side effects by being looked at is a bug that surfaces as mysterious `.corrupt`
## files. That much is unchanged and is the whole reason this is not `load_slot`.
##
## What changed in M32 is that it stops throwing away the distinction it already computed.
## `_read` knows whether a file EXISTS and separately whether it could be read; returning only
## the data collapsed "nothing here" and "here and unreadable" into one null, and a menu drew
## both as empty - offering to save over the very file a player would want back. Which FAULT it
## has is still not carried: the row says one thing either way, and load_slot is where the whole
## list gets pushed as an error.
##
## The local is `glance` and not `reading` deliberately: load_slot's own local is `reading`, and
## two identical lines in one file make the mutant aimed at either of them AMBIGUOUS - sed edits
## whichever comes first and reports a verdict about the other. The aim check says so on every
## run, and the fix is to make the lines differ rather than to loosen the pattern.
func peek(game: StringName, slot: int) -> SlotSummary:
	var glance := _read(game, slot)
	if glance.data != null:
		return SlotSummary.of(glance.data)
	return SlotSummary.broken() if glance.exists else SlotSummary.empty()


func delete_slot(game: StringName, slot: int) -> void:
	if FileAccess.file_exists(slot_path(game, slot)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(game, slot)))


## Reads one slot and judges it, touching nothing. Every fault is collected rather than
## returned at the first one, so a load reports what is wrong with the file instead of what
## is wrong with it first.
func _read(game: StringName, slot: int) -> Reading:
	var out := Reading.new()
	var path := slot_path(game, slot)
	if not FileAccess.file_exists(path):
		return out
	out.exists = true
	out.text = FileAccess.get_file_as_string(path)

	var parsed: Variant = JSON.parse_string(out.text)
	if parsed == null or not (parsed is Dictionary):
		out.faults.append("file is not JSON")
		return out

	var migrated := Migrations.apply(parsed as Dictionary, game)
	var data := SaveData.from_dict(migrated)
	out.faults.append_array(data.problems())
	# The directory says which game this is; so does the file. They agree or the file does not
	# belong here - and a save that loads into the wrong game does not look like a mismatched
	# file, it looks like the game you meant to play being broken.
	if data.game != game:
		out.faults.append("save belongs to game '%s' but sits in '%s'" % [data.game, game])
	if out.faults.is_empty():
		out.data = data
	return out


## Copies the unreadable bytes aside before anything can overwrite them. Done first, and
## reported loudly: a fallback that leaves no trace is how a data-loss bug survives for months.
func _park_corrupt(game: StringName, slot: int, text: String) -> void:
	var backup_path := corrupt_path(game, slot)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_path.get_base_dir()))
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup == null:
		push_error("SaveManager: %s slot %d is unreadable AND its bytes could not be preserved" % [game, slot])
		return
	backup.store_string(text)
	backup.close()
	push_error("SaveManager: %s slot %d is unreadable; the original bytes are at %s"
		% [game, slot, backup_path])


## Empties the scripted-session directory, one game at a time. Guarded on the directory rather
## than on a caller's promise: this deletes files, and the one thing it must never be pointed
## at is a real player's saves.
func _wipe_qa_dir() -> void:
	if base_dir != QA_DIR:
		return
	var root := DirAccess.open(base_dir)
	if root == null:
		return
	for game in root.get_directories():
		var sub := DirAccess.open(base_dir.path_join(game))
		if sub == null:
			continue
		for file in sub.get_files():
			sub.remove(file)
		root.remove(game)
	for file in root.get_files():
		root.remove(file)
