class_name EnemyDef
extends Resource
## Something that fights back, as data.
##
## The counterpart of ItemDef: a NOUN a map can place, with the numbers a fight needs and
## nothing about how the fight is drawn. BattleLogic reads one of these and never loads it -
## the world resolves it through Registry and hands it over, the way PauseMenu is handed rows.
##
## Registered automatically: Registry buckets every resource under data/ by its class_name, so
## a new file in data/enemies/ is reachable as Registry.get_resource(&"EnemyDef", id) with no
## registration step to forget.

## Matched on by a map's `enemies` records. The content gate requires it to equal the file's
## own name, as items do.
@export var id: StringName = &""

## Shown to the player, on the battle screen.
@export var name: String = ""

## The CharacterSpec whose generated sheet this enemy wears. Art is per STYLE and an enemy
## does not know which map places it, so "the art exists" is checked per placement by the
## content gate rather than here - the same split GameManifest makes for player_character.
@export var character: StringName = &""

@export var max_hp: int = 1
@export var attack: int = 1
@export var defense: int = 0

## Granted on defeat. Zero is legal: a fight can be an obstacle rather than a reward.
@export var xp: int = 0

## Coin dropped on defeat, on the same terms as xp - zero is legal and is what a game with no
## economy leaves it at.
@export var gold: int = 0

## A boss cannot be fled. It is a property of the ENEMY rather than of the encounter because
## a designer thinking "can I run from this" is thinking about the thing, not the tile.
@export var boss: bool = false

## The tune THIS fight plays, outranking the manifest's `battle_music`. A track id under
## data/music, validated by the world that opens the fight - an EnemyDef has no voice to check
## it against, since which SoundStyle renders it is a property of the running game.
##
## On the ENEMY rather than behind the `boss` flag, because the references disagree about which
## fights get one and a template that picked would be picking for every game built on it.
## Dragon Quest I (1986) reserves its second battle theme for the Dragonlord; Final Fantasy I
## has ONE and plays it for every fight including Chaos; Final Fantasy II gave major bosses
## "Battle Theme 2"; by IV it plays for all but two. A field on the enemy sits anywhere on that
## range. See docs/GENRE_CONVENTIONS.md §14.
##
## In a formation the FIRST foe that states one wins, scanned in the order the record names
## them: a formation with a boss anywhere in it is a boss fight, and that needs no second field.
@export var music: StringName = &""

## What it does on its turn, as `{"name": String, "power": int}`. Damage is
## attack + power - the player's defense, so power is the move's own contribution and a
## zero-power move is this enemy's plain hit.
##
## A move may AFFLICT instead of hurting, which is what makes the status system point both ways
## rather than only outward: `{"name": "Lull", "status": "sleep", "turns": 2}` costs the target
## their next two turns, and `{"name": "Wither", "status": "sap", "stat": "defense",
## "power": 2, "turns": 3}` takes two off their armour for three. A status move deals NO damage -
## it spends the enemy's turn on the affliction, exactly as the player's own SLEEP and SAP spend
## theirs - so `problems()` refuses one that also carries power.
##
## A well-timed guard SHRUGS IT OFF. The defend cue is already the player's answer to a blow, and
## giving it nothing to do against an affliction would make the timing mechanic go quiet in
## exactly the fights that need it most. See docs/DECISIONS.md.
##
## Inline rather than a MoveDef resource: a handful of enemies with two moves each does not
## need a fourth registered type, and a move that is only ever named by one enemy has nothing
## to share. The day moves are reused across enemies, this becomes an Array[MoveDef] and the
## data files gain one indirection - nothing else here changes.
@export var moves: Array[Dictionary] = []

## How this thing answers each element, as element -> PERCENT of the damage it takes: 200 is
## burns twice as hot, 50 is shrugs half of it off, 0 is untouched by it entirely. An element
## not named here is 100 and needs no entry, so the default - an empty map - is exactly the
## behaviour every enemy had before this field existed.
##
## PERCENTS IN THE DATA rather than tier words with the multipliers in the script. "weak" and
## "resist" would read better in a file and would put `* 2` in `BattleLogic`, which is precisely
## the literal-a-designer-would-want-to-change this project keeps out of code - and it would cap
## the genre at two tiers when the references run from Pokemon's quarter-damage through immunity
## to outright absorption. A number lets a game sit anywhere on that range without asking for a
## new word. See docs/DECISIONS.md.
##
## A value of exactly 100 is REFUSED rather than allowed as a no-op: it is an entry that reads
## like a decision and changes nothing, so it is either a typo for something else or a note that
## belongs in a comment. Zero is legal and means immune; there is no upper bound, because "this
## thing dies to fire" is a design decision and not a fault.
@export var resistances: Dictionary = {}

## What a move's `status` may say. A closed vocabulary for the reason SpellDef.Kind is an enum:
## a typo in a data file would otherwise be a move that reaches its turn and does nothing.
const STATUSES := ["sleep", "sap"]


## How much of an `element` spell's damage this thing takes, as a percent. The ONE reader of
## `resistances`, so a missing entry means 100 in exactly one place.
##
## An elementless spell is 100 too: a spell that is made of nothing cannot be resisted, and
## checking that here rather than at the call site keeps the fight's arithmetic to one line.
func resistance_to(element: StringName) -> int:
	if String(element).is_empty():
		return 100
	return int(resistances.get(element, 100))


## Everything wrong with this enemy, in the idiom of every other problems() here: all of
## them, not the first, so "what is broken about this enemy" is one read rather than six runs.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("enemy has no id")
	if name.is_empty():
		out.append("enemy '%s' has no name" % id)
	if String(character).is_empty():
		out.append("enemy '%s' names no character" % id)
	if max_hp <= 0:
		out.append("enemy '%s' has %d max_hp - a fight it cannot survive starting" % [id, max_hp])
	if attack <= 0:
		out.append("enemy '%s' has %d attack" % [id, attack])
	if defense < 0:
		out.append("enemy '%s' has %d defense" % [id, defense])
	if xp < 0:
		out.append("enemy '%s' grants %d xp" % [id, xp])
	if gold < 0:
		out.append("enemy '%s' drops %d gold" % [id, gold])
	# An enemy with no moves reaches its turn and has nothing to do, which presents as a
	# battle that stops rather than as a broken file.
	if moves.is_empty():
		out.append("enemy '%s' has no moves" % id)
	out.append_array(_resistance_problems())
	for i in moves.size():
		var move: Dictionary = moves[i]
		if str(move.get("name", "")).is_empty():
			out.append("enemy '%s' move %d has no name" % [id, i])
		if int(move.get("power", 0)) < 0:
			out.append("enemy '%s' move %d has negative power" % [id, i])
		out.append_array(_move_status_problems(i, move))
	return out


## Everything wrong with the resistance map, separately for `_move_status_problems`'s reason: an
## enemy that answers no element has none of this, and every fault here is silent in play - a
## misspelt element is a weakness no spell can ever hit, and a percent stored as a string reads
## back as zero, which is IMMUNITY. Both present as a fight that feels wrong rather than as a
## broken file.
func _resistance_problems() -> Array[String]:
	var out: Array[String] = []
	for element: Variant in resistances:
		var word := str(element)
		if word.is_empty():
			out.append("enemy '%s' answers an element with no name" % id)
		var pct: Variant = resistances[element]
		if typeof(pct) != TYPE_INT and typeof(pct) != TYPE_FLOAT:
			out.append("enemy '%s' answers '%s' with %s, which is not a number"
				% [id, word, pct])
			continue
		if int(pct) < 0:
			out.append("enemy '%s' takes %d%% damage from '%s' - it would be healed by it"
				% [id, int(pct), word])
		elif int(pct) == 100:
			# An entry that reads like a decision and changes nothing. It is a typo for a real
			# number or a note that belongs in a comment, and either way saying so beats letting
			# a designer believe they have written a resistance.
			out.append("enemy '%s' answers '%s' with 100%%, which is what it would do anyway"
				% [id, word])
	return out


## The status half of a move, checked separately because a plain damaging move has none of it and
## a move that carries a misspelt one would simply reach its turn and do nothing.
func _move_status_problems(i: int, move: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var status := str(move.get("status", ""))
	if status.is_empty():
		# Not a status move. `turns` and `stat` on one would be fields nothing reads, which is
		# how a data file comes to describe an effect the fight never applies.
		for stray in ["turns", "stat"]:
			if move.has(stray):
				out.append("enemy '%s' move %d has '%s' but no status" % [id, i, stray])
		return out
	if not STATUSES.has(status):
		out.append("enemy '%s' move %d inflicts '%s', which is not a status" % [id, i, status])
	if int(move.get("power", 0)) != 0:
		# It spends the turn on the affliction. A move that hurt AND afflicted would make one
		# defend cue answer two questions, and a blocked one ambiguous about which it stopped.
		out.append("enemy '%s' move %d both afflicts and deals %d damage"
			% [id, i, int(move.get("power", 0))])
	if int(move.get("turns", 0)) <= 0:
		out.append("enemy '%s' move %d afflicts for %d turns"
			% [id, i, int(move.get("turns", 0))])
	if status == "sap":
		if not ["attack", "defense"].has(str(move.get("stat", ""))):
			out.append("enemy '%s' move %d saps '%s', which is not a stat"
				% [id, i, str(move.get("stat", ""))])
		if int(move.get("amount", 0)) <= 0:
			out.append("enemy '%s' move %d saps by %d" % [id, i, int(move.get("amount", 0))])
	return out
