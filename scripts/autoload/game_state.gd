extends Node
## The live game state, and the only thing allowed to change it.
##
## Views read from here and emit through EventBus; they never assign fields. One writer per
## piece of state is what keeps "who moved the player" answerable - two systems both setting
## a position produce a bug that reproduces only on the frame they disagree.
##
## Serialization lands in M5 (SaveData + migrations). Until then this holds the same fields
## a save will, so adding persistence is a mapping rather than a redesign.

var current_map: StringName = &""
var player_position: Vector2 = Vector2.ZERO
var player_facing: int = 0  # Dir.D value; DOWN is 0.
var flags: Dictionary = {}
var seen: Dictionary = {}


func _ready() -> void:
	EventBus.system_ready.emit({"system": &"GameState"})


## Returns the state to its just-booted values. Tests call this in before_test: an autoload
## outlives every suite in the run, so state set by one test is present in the next unless
## something resets it.
func reset() -> void:
	current_map = &""
	player_position = Vector2.ZERO
	player_facing = 0
	flags = {}
	seen = {}


func new_game(start_map: StringName, start_position: Vector2, facing: int) -> void:
	reset()
	current_map = start_map
	player_position = start_position
	player_facing = facing


func set_flag(key: StringName, value: bool) -> void:
	flags[key] = value


func has_flag(key: StringName) -> bool:
	return bool(flags.get(key, false))


func mark_seen(key: StringName) -> void:
	seen[key] = true


func was_seen(key: StringName) -> bool:
	return bool(seen.get(key, false))


func set_player(position: Vector2, facing: int) -> void:
	player_position = position
	player_facing = facing
