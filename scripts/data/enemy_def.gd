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

## What it does on its turn, as `{"name": String, "power": int}`. Damage is
## attack + power - the player's defense, so power is the move's own contribution and a
## zero-power move is this enemy's plain hit.
##
## Inline rather than a MoveDef resource: a handful of enemies with two moves each does not
## need a fourth registered type, and a move that is only ever named by one enemy has nothing
## to share. The day moves are reused across enemies, this becomes an Array[MoveDef] and the
## data files gain one indirection - nothing else here changes.
@export var moves: Array[Dictionary] = []


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
	for i in moves.size():
		var move: Dictionary = moves[i]
		if str(move.get("name", "")).is_empty():
			out.append("enemy '%s' move %d has no name" % [id, i])
		if int(move.get("power", 0)) < 0:
			out.append("enemy '%s' move %d has negative power" % [id, i])
	return out
