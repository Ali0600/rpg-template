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
## What the player is worth in a fight. ZERO HP MEANS UNSET, not dead: a game with no combat
## never touches these, and a game with combat has world_scene derive full health from its
## CombatDef the first time it needs them. The derivation lives there because the curve is a
## resource this autoload has no business loading.
var player_hp: int = 0
var player_xp: int = 0
var player_level: int = 1
## What is left to spend on spells. Unlike player_hp, ZERO IS A REAL VALUE - it means spent,
## not unset - so there is no "no magic yet" signal here and there does not need to be: hp is
## the one that carries it, and _ensure_party fills both from the curve at the same moment.
## A game with no magic leaves this at zero for the whole run, which is also what it means.
var player_mp: int = 0
## What the player can spend. Unlike player_hp, ZERO IS A REAL VALUE - it means broke, not
## unset - so gold is a plain field with a plain default rather than something derived. A
## game with no economy simply never moves it off zero.
var gold: int = 0
## What is worn, as slot -> item id. The item STAYS in the bag - equipping marks it, never
## moves it - so the bag remains the one list of what the player has, and this map is only
## the answer to "which of them are on". Empty is the normal state and means nothing worn.
var equipment: Dictionary = {}
var play_seconds: float = 0.0


func _ready() -> void:
	EventBus.system_ready.emit({"system": &"GameState"})


func _process(delta: float) -> void:
	# Only counts while the game is actually being played, so a save's play time means time
	# spent playing rather than time spent with the window open. A battle counts too: it is the
	# one state where the player is very much playing and deliberately cannot walk.
	if Router.player_can_move() or Router.state() == Router.State.BATTLE:
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
	player_hp = 0
	player_xp = 0
	player_level = 1
	player_mp = 0
	gold = 0
	equipment = {}
	play_seconds = 0.0


func new_game(game_id: StringName, start_map: StringName, start_position: Vector2, facing: int,
		starting_gold: int = 0) -> void:
	reset()
	game = game_id
	current_map = start_map
	player_position = start_position
	player_facing = facing
	gold = maxi(starting_gold, 0)


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
	if not inventory.remove(id, n):
		return false
	# The last copy leaving the bag - by a sale, a dialog take, anything - takes the marker
	# with it. Without this, the slot map points at an item the player no longer has, and the
	# phantom re-arms the moment they pick another one up.
	if inventory.count(id) == 0:
		for slot: Variant in equipment.keys():
			if equipment[slot] == id:
				equipment.erase(slot)
	return true


func has_item(id: StringName, n: int = 1) -> bool:
	return inventory.has(id, n)


func item_count(id: StringName) -> int:
	return inventory.count(id)


## Money, through the one writer, in the same all-or-nothing shape the bag uses. A spend that
## cannot be covered is REFUSED rather than clamped: clamping turns "the player could not
## afford it" into "the player bought it and now has nothing", which is a different game.
## Gold therefore cannot go negative by construction rather than by a check somewhere later.
func give_gold(n: int) -> bool:
	if n <= 0:
		return false
	gold += n
	return true


func spend_gold(n: int) -> bool:
	if n <= 0 or n > gold:
		return false
	gold -= n
	return true


## What is worn, through the one writer. Equip refuses what the bag does not hold - a slot
## map pointing at a phantom item is the dangling reference every other rule here exists to
## prevent. Equipping into an occupied slot swaps: the old item was never out of the bag, so
## there is nothing to put back.
func equip(slot: StringName, id: StringName) -> bool:
	if String(slot).is_empty() or not inventory.has(id):
		return false
	equipment[slot] = id
	return true


func unequip(slot: StringName) -> bool:
	return equipment.erase(slot)


func equipped(slot: StringName) -> StringName:
	return StringName(str(equipment.get(slot, "")))


func is_equipped(id: StringName) -> bool:
	return equipment.values().has(id)


## What a fight left the player as. All four together, through one writer, because they are
## one fact: a level without its heal, or xp without the level it bought, is a state no rule
## in the game produces and every rule downstream would then have to tolerate.
##
## MP joined them rather than getting the give/spend pair gold has, and the difference between
## the two is worth stating: gold moves on its OWN - a sale, a purchase, a drop - so it needs
## verbs of its own. MP only ever moves as part of something that also moves hp: a fight
## resolving, a night at an inn, a level restoring the player. A separate writer for it would
## be a second place that has to remember to be called, and the one that forgets leaves a
## player wondering why resting did not give their magic back.
##
## Required rather than defaulted for the same reason: a call site that omitted it would silently
## empty the player's magic, and "the argument you forgot" would read in play as a bug in
## whatever spent it.
func set_party(hp: int, xp: int, level: int, mp: int) -> void:
	player_hp = maxi(hp, 0)
	player_xp = maxi(xp, 0)
	player_level = maxi(level, 1)
	player_mp = maxi(mp, 0)


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
	# An unset party writes an EMPTY dictionary rather than zeros. A game with no combat then
	# saves no combat state at all, and a file cannot claim the player has nought health.
	# MP rides INSIDE party rather than beside it like gold, because it shares party's "empty
	# means no combat here" answer exactly - a game with no fighting has no magic either, and a
	# top-level mp key would be the one field claiming otherwise.
	out.party = {} if player_hp <= 0 else {
		"hp": player_hp, "xp": player_xp, "level": player_level, "mp": player_mp,
	}
	out.gold = gold
	out.equipment = equipment.duplicate(true)
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
	# An absent party restores as UNSET, not as a level-1 player at zero health. The
	# difference matters: unset is the signal world_scene reads to derive full health from the
	# game's curve, and a save written before battles existed must produce exactly that.
	player_hp = int(data.party.get("hp", 0))
	player_xp = int(data.party.get("xp", 0))
	player_level = maxi(int(data.party.get("level", 1)), 1)
	player_mp = maxi(int(data.party.get("mp", 0)), 0)
	gold = maxi(data.gold, 0)
	equipment = data.equipment.duplicate(true)
	play_seconds = data.play_seconds
