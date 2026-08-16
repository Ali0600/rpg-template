extends Node
## Writes and reads save slots as JSON.
##
## The rule that matters most here is what happens to a save that will not parse. A player's
## save file is their progress; a loader that falls back to a fresh game and then lets the
## next autosave write over the bad bytes has destroyed both the progress AND the only
## evidence of what went wrong. So the raw bytes are parked under `.corrupt` BEFORE anything
## else is touched, and the failure is reported rather than swallowed.

const SLOT_FORMAT := "%s/slot_%d.json"
const DEFAULT_DIR := "user://saves"

## Overridable so tests never touch a real player's slots.
var base_dir: String = DEFAULT_DIR


func _ready() -> void:
	EventBus.system_ready.emit({"system": &"SaveManager"})


func slot_path(slot: int) -> String:
	return SLOT_FORMAT % [base_dir, slot]


func corrupt_path(slot: int) -> String:
	return slot_path(slot) + ".corrupt"


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save(slot: int, data: SaveData) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not write slot %d (error %d)" % [slot, FileAccess.get_open_error()])
		EventBus.save_changed.emit({"slot": slot, "action": &"save", "ok": false})
		return false
	file.store_string(JSON.stringify(data.to_dict(), "\t") + "\n")
	file.close()
	EventBus.save_changed.emit({"slot": slot, "action": &"save", "ok": true})
	return true


## Returns null when the slot cannot be read, having preserved whatever was there. The caller
## decides what to do about it - starting a new game is a decision, not a fallback this
## should make silently.
func load_slot(slot: int) -> SaveData:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_park_corrupt(slot, text)
		EventBus.save_changed.emit({"slot": slot, "action": &"load", "ok": false})
		return null

	var migrated := Migrations.apply(parsed as Dictionary)
	var data := SaveData.from_dict(migrated)
	var problems := data.problems()
	if not problems.is_empty():
		# Structurally wrong but readable: keep the bytes too, because "the save loaded and
		# the player was somewhere impossible" is a bug report that needs the original file.
		_park_corrupt(slot, text)
		for p in problems:
			push_error("SaveManager: slot %d: %s" % [slot, p])
		EventBus.save_changed.emit({"slot": slot, "action": &"load", "ok": false})
		return null

	EventBus.save_changed.emit({"slot": slot, "action": &"load", "ok": true})
	return data


func delete_slot(slot: int) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


## Copies the unreadable bytes aside before anything can overwrite them. Done first, and
## reported loudly: a fallback that leaves no trace is how a data-loss bug survives for months.
func _park_corrupt(slot: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	var backup := FileAccess.open(corrupt_path(slot), FileAccess.WRITE)
	if backup == null:
		push_error("SaveManager: slot %d is unreadable AND its bytes could not be preserved" % slot)
		return
	backup.store_string(text)
	backup.close()
	push_error("SaveManager: slot %d is unreadable; the original bytes are at %s"
		% [slot, corrupt_path(slot)])
