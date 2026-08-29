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
## This is the LEADER's map; a companion's is in companion_equipment, keyed by member.
var equipment: Dictionary = {}
## What each companion is worth in a fight, as member id -> {hp, xp, level, mp}. The leader is
## NOT in here - they are the four fields above, which is what keeps set_party, every mutant
## aimed at it and every QA assertion pointing where they already pointed.
##
## Absent means "has not joined, or has joined and has not been filled in yet"; the world fills
## a member from their curve the first time it builds a party with them in it, the way it
## derives the leader's health from an unset one. WHO is in the party is not stored here at all
## - that is derived from flags against the manifest's roster (see PartyMemberDef).
var companions: Dictionary = {}
## What each companion is wearing, as member id -> slot -> item id. A second map rather than a
## member key inside `equipment`, because the leader's map is read by name in a dozen places
## and re-shaping it would be a rename with no gain. Gear is per-member in every reference
## game - Final Fantasy I's shared bag holds consumables only - and the ITEM still never
## leaves the one bag, so this is the same marker `equipment` is, once per member.
var companion_equipment: Dictionary = {}
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
	companions = {}
	companion_equipment = {}
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
	# Copies leaving the bag - by a sale, a dialog take, anything - take markers with them.
	# Without this, a slot map points at an item nobody is carrying, and the phantom re-arms
	# the moment another copy is picked up.
	#
	# With a party this is a COUNT rather than a boolean: selling one of two swords while two
	# people wear one must strip exactly one marker, not both and not neither. Companions are
	# stripped first and the LEADER LAST, so the player keeps what they are wearing and the
	# loss lands where it is least surprising. Reverse insertion order among companions makes
	# which one deterministic, because "whichever the dictionary offered first" is a rule that
	# reproduces differently on a different day.
	_strip_phantom_markers(id)
	return true


## Brings the number of markers on `id` down to the number carried, newest companion first and
## the leader last. Idempotent, and a no-op whenever the bag already covers what is worn.
func _strip_phantom_markers(id: StringName) -> void:
	var carried := inventory.count(id)
	var members: Array = companion_equipment.keys()
	members.reverse()
	for member: Variant in members:
		var worn: Dictionary = companion_equipment[member]
		for slot: Variant in worn.keys():
			if wearers_of(id) <= carried:
				return
			if worn[slot] == id:
				worn.erase(slot)
	for slot: Variant in equipment.keys():
		if wearers_of(id) <= carried:
			return
		if equipment[slot] == id:
			equipment.erase(slot)


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
##
## An empty `member` is the LEADER, everywhere in this file. That default is what keeps every
## existing call site - and every session that presses through the equip screen - meaning
## exactly what it meant before there was anyone else to mean.
##
## ONE COPY, ONE BACK. A second member cannot wear the sword the first is wearing unless the
## bag holds two, because the item never leaves the bag and a marker is a claim on a copy.
## Checked as "what the marker count WOULD be", so re-equipping what is already on is still
## the no-op it always was rather than a refusal.
func equip(slot: StringName, id: StringName, member: StringName = &"") -> bool:
	if String(slot).is_empty() or not inventory.has(id):
		return false
	var worn := _worn_map(member, true)
	var already := 1 if worn.get(slot, &"") == id else 0
	if wearers_of(id) - already + 1 > inventory.count(id):
		return false
	worn[slot] = id
	return true


func unequip(slot: StringName, member: StringName = &"") -> bool:
	return _worn_map(member, false).erase(slot)


func equipped(slot: StringName, member: StringName = &"") -> StringName:
	return StringName(str(_worn_map(member, false).get(slot, "")))


## Whether ANYONE is wearing it. The bag's (E) marker and the shop's refusal to sell what is
## worn both ask this question about the party rather than about the player, which is what
## stops a companion's armour being sold out from under them.
func is_equipped(id: StringName) -> bool:
	return wearers_of(id) > 0


## How many copies of `id` are claimed by somebody, across the whole party. The quantity the
## bag has to cover: two markers on one carried sword is the phantom this counts to prevent.
func wearers_of(id: StringName) -> int:
	var total := equipment.values().count(id)
	for member: Variant in companion_equipment.keys():
		var worn: Dictionary = companion_equipment[member]
		total += worn.values().count(id)
	return total


## The slot map a member writes into. `create` is what keeps a read from conjuring an empty
## record for somebody who has not joined - a menu asking what a stranger is wearing must not
## make them a member by asking.
func _worn_map(member: StringName, create: bool) -> Dictionary:
	if String(member).is_empty():
		return equipment
	if not companion_equipment.has(member):
		if not create:
			return {}
		companion_equipment[member] = {}
	return companion_equipment[member]


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


## What a fight left a COMPANION as - set_party for everyone who is not the leader, and every
## argument required for the same reason: the one you forget is the one that silently empties
## somebody. Four numbers, one writer, one member.
func set_companion(id: StringName, hp: int, xp: int, level: int, mp: int) -> void:
	if String(id).is_empty():
		# The empty id is the leader's, and routing them through here would be a second writer
		# for the four fields set_party owns.
		push_error("set_companion called with no member id - the leader goes through set_party")
		return
	companions[id] = {
		"hp": maxi(hp, 0),
		"xp": maxi(xp, 0),
		"level": maxi(level, 1),
		"mp": maxi(mp, 0),
	}


## A companion's numbers, as a copy. Empty when they have never been filled in, which is the
## signal the world reads to fill them from their curve - has_companion asks it directly.
func companion(id: StringName) -> Dictionary:
	return (companions.get(id, {}) as Dictionary).duplicate()


func has_companion(id: StringName) -> bool:
	return companions.has(id)


## Whether anybody has been made real yet. THE signal for "a game with combat has not derived
## its party from the curve", and the one thing zero health used to mean on its own.
##
## It cannot mean that alone any more, and this is the subtlest change M27 makes. With a party,
## A LEADER AT ZERO HEALTH IS A REAL, SAVEABLE STATE: they fell, a companion finished the
## fight, and the survivors walk on to buy a night at the inn. Read as "unset", that state
## would refill them from the curve on the way into the next fight - a silent resurrection that
## deletes the consequence the player is walking to town to undo, and no test that asks about
## a solo game can see it. A companion record is the proof somebody else was standing.
func party_unset() -> bool:
	return player_hp <= 0 and companions.is_empty()


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
	out.party = {} if party_unset() else {
		"hp": player_hp, "xp": player_xp, "level": player_level, "mp": player_mp,
	}
	# Each companion's numbers and gear together, keyed by member, so a roster reordered in the
	# manifest cannot make a save describe the wrong person - which a positional list would.
	# Empty is the normal state and is what every game without a party writes forever.
	var out_companions: Dictionary = {}
	for id: Variant in companions.keys():
		var record: Dictionary = (companions[id] as Dictionary).duplicate()
		record["equipment"] = (companion_equipment.get(id, {}) as Dictionary).duplicate(true)
		out_companions[id] = record
	out.companions = out_companions
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
	var loaded_companions: Dictionary = {}
	var loaded_worn: Dictionary = {}
	for id: Variant in data.companions.keys():
		var record: Dictionary = data.companions[id]
		loaded_companions[id] = {
			"hp": maxi(int(record.get("hp", 0)), 0),
			"xp": maxi(int(record.get("xp", 0)), 0),
			"level": maxi(int(record.get("level", 1)), 1),
			"mp": maxi(int(record.get("mp", 0)), 0),
		}
		var worn: Dictionary = record.get("equipment", {})
		if not worn.is_empty():
			loaded_worn[id] = worn.duplicate(true)
	companions = loaded_companions
	companion_equipment = loaded_worn
	gold = maxi(data.gold, 0)
	equipment = data.equipment.duplicate(true)
	play_seconds = data.play_seconds
