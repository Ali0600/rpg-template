extends Node
## The live game state, and the only thing allowed to change it.
##
## Views read from here and emit through EventBus; they never assign fields. One writer per
## piece of state is what keeps "who moved the player" answerable - two systems both setting
## a position produce a bug that reproduces only on the frame they disagree.
##
## Serialization lands in M5 (SaveData + migrations). Until then this holds the same fields
## a save will, so adding persistence is a mapping rather than a redesign.

## Which game is being played. Written by the world when a game starts and by nothing else;
## a save carries it so that loading one into a different game is a refusal rather than a
## silently wrong world.
var game: StringName = &""
var current_map: StringName = &""
var player_position: Vector2 = Vector2.ZERO
var player_facing: int = 0  # Dir.D value; DOWN is 0.
var flags: Dictionary = {}
var seen: Dictionary = {}
## What the player is carrying. An object rather than a Dictionary because the rules - a take
## is all or nothing, a count of zero forgets the item - belong with the data they govern, and
## every other layer is handed a snapshot rather than this.
var inventory: Inventory = Inventory.new()
var play_seconds: float = 0.0


func _ready() -> void:
	EventBus.system_ready.emit({"system": &"GameState"})


func _process(delta: float) -> void:
	# Only counts while the game is actually being played, so a save's play time means time
	# spent playing rather than time spent with the window open.
	if Router.player_can_move():
		play_seconds += delta


## Returns the state to its just-booted values. Tests call this in before_test: an autoload
## outlives every suite in the run, so state set by one test is present in the next unless
## something resets it.
func reset() -> void:
	game = &""
	current_map = &""
	player_position = Vector2.ZERO
	player_facing = 0
	flags = {}
	seen = {}
	inventory = Inventory.new()
	play_seconds = 0.0


func new_game(game_id: StringName, start_map: StringName, start_position: Vector2, facing: int) -> void:
	reset()
	game = game_id
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


## The inventory, through the one writer. A view or a hook never reaches `inventory` directly:
## these four are the whole vocabulary, and give/take report whether they happened so a caller
## cannot assume a take that could not be covered.
func give_item(id: StringName, n: int = 1) -> bool:
	return inventory.add(id, n)


func take_item(id: StringName, n: int = 1) -> bool:
	return inventory.remove(id, n)


func has_item(id: StringName, n: int = 1) -> bool:
	return inventory.has(id, n)


func item_count(id: StringName) -> int:
	return inventory.count(id)


## The live state as a save. Kept here rather than in SaveManager because this is the object
## that OWNS the state - a writer that reached in and read the fields would be a second place
## that has to learn about every new one.
func to_save() -> SaveData:
	var out := SaveData.new()
	out.game = game
	out.map = current_map
	out.position = player_position
	out.facing = player_facing
	out.flags = flags.duplicate(true)
	out.seen = seen.duplicate(true)
	out.items = inventory.to_dict()
	out.play_seconds = play_seconds
	return out


## Replaces the live state wholesale. Duplicated on the way in, so a loaded save cannot be
## mutated from underneath by whoever still holds the SaveData.
func from_save(data: SaveData) -> void:
	game = data.game
	current_map = data.map
	player_position = data.position
	player_facing = data.facing
	flags = data.flags.duplicate(true)
	seen = data.seen.duplicate(true)
	inventory = Inventory.from_dict(data.items)
	play_seconds = data.play_seconds
