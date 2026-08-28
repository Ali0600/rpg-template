class_name BattleLogic
extends RefCounted
## A fight, as rules. No nodes, no autoloads, no files, no clock of its own.
##
## Split from BattleScreen for the reason PauseMenu is split from PauseScreen: "a timed press
## doubles the hit" and "a boss cannot be fled" are rules, and a rule tested through a scene is
## a rule tested through three other things at once. Here they are tested by building a fight
## and reading a number.
##
## TIME IS COUNTED IN FRAMES, handed in one at a time by tick(). The view calls it from
## _physics_process, so the unit is the physics frame - which is why a QA script can press on
## an exact frame and get the same result on every machine. Nothing here reads a delta, a
## clock or an OS time; a battle that took real seconds could not be replayed.
##
## Effects are COLLECTED and applied by the world, exactly as DialogRunner collects a
## conversation's. Winning a fight does not set a flag - it appends one, and world_scene's
## single sink carries it out. That is what makes "a beaten enemy stays beaten" the same
## mechanism as "a chest opened once", persisted and migrated for free.

## Where the fight is. MENU and ITEMS are waiting for the player; PLAYER_ACT and ENEMY_ACT are
## a cue counting down toward an impact; MESSAGE is a line being read; OVER is the result.
enum Phase { MENU, ITEMS, PLAYER_ACT, ENEMY_ACT, MESSAGE, OVER }

## The command menu's rows, in the order they are drawn. The view indexes its labels by this,
## so the order lives in one place rather than in a list beside a list.
enum Row { ATTACK, ITEM, FLEE }

## How it ended. NONE is "still fighting", so a caller never has to ask two questions.
enum Outcome { NONE, VICTORY, DEFEAT, FLED }


## One usable thing in the bag, already resolved. The logic is handed these rather than an
## inventory and a Registry, because looking an item up is a job for the layer that may touch
## autoloads - and this class may not. Only items that heal appear: a gate key in a battle
## menu is a row that can only disappoint.
class ItemRow:
	var id: StringName = &""
	var name: String = ""
	var count: int = 0
	var heal: int = 0

	static func of(item_id: StringName, item_name: String, item_count: int, item_heal: int) -> ItemRow:
		var out := ItemRow.new()
		out.id = item_id
		out.name = item_name
		out.count = item_count
		out.heal = item_heal
		return out


var _combat: CombatDef
var _enemy: EnemyDef
var _hp: int = 0
var _xp: int = 0
var _level: int = 1
var _enemy_hp: int = 0
## Cues asked for and not yet drained by the view.
var _sounds: Array[StringName] = []

## Untyped Array because a typed default for a nested class is not a constant expression -
## the same reason PauseMenu._items is untyped.
var _items: Array = []
var _seen_key: String = ""

var _phase := Phase.MENU
var _index: int = 0
var _count: int = 0
## Frames remaining when the acting side's button was first pressed, or -1 for no press yet.
var _pressed_at: int = -1
var _message: String = ""
## What the current MESSAGE goes back to. A message is always an interruption of something.
var _after_message := Phase.MENU
var _outcome := Outcome.NONE
var _moves_rng: SeededRng
var _effects: Array[Dictionary] = []


## Builds a fight. Everything is passed in already resolved - the player's numbers, the
## enemy's definition, the usable rows - because this class may not look anything up.
##
## `seen_key` is the map-scoped id the world will mark on victory, carried rather than
## rebuilt so the logic never has to know how a seen key is spelled.
static func of(combat: CombatDef, enemy: EnemyDef, hp: int, xp: int, level: int,
		items: Array, seen_key: String, seed_value: int) -> BattleLogic:
	var out := BattleLogic.new()
	out._combat = combat
	out._enemy = enemy
	out._level = maxi(level, 1)
	out._hp = clampi(hp, 1, combat.max_hp(out._level))
	out._xp = maxi(xp, 0)
	out._enemy_hp = enemy.max_hp
	out._items = items.duplicate()
	out._seen_key = seen_key
	# Its own derived stream, so a later randomised feature - a crit, a drop - cannot reshuffle
	# the moves an existing fight already draws.
	out._moves_rng = SeededRng.new(seed_value).derive("moves")
	return out


func phase() -> Phase:
	return _phase


func index() -> int:
	return _index


## How many rows the CURRENT page has, so the cursor wraps over one function rather than a
## branch at every call site - the PauseMenu.size() shape.
func size() -> int:
	if _phase == Phase.ITEMS:
		# An empty bag still has one row: the line saying it is empty. A page with no rows is
		# one the cursor cannot stand on and the player cannot read.
		return maxi(_items.size(), 1)
	return Row.size()


func item_rows() -> Array:
	return _items.duplicate()


func item_row(at: int) -> ItemRow:
	if at < 0 or at >= _items.size():
		return null
	return _items[at]


func player_hp() -> int:
	return _hp


func player_max_hp() -> int:
	return _combat.max_hp(_level)


func player_level() -> int:
	return _level


func player_xp() -> int:
	return _xp


func enemy_hp() -> int:
	return _enemy_hp


func enemy_max_hp() -> int:
	return _enemy.max_hp


func enemy_name() -> String:
	return _enemy.name


func message() -> String:
	return _message


## Frames left in whatever is counting down. Zero outside a countdown, so a view can read it
## every frame without asking which phase it is in.
func count() -> int:
	return _count


## Whether the timing window is open RIGHT NOW - the thing the view draws a cue for and the
## player is reacting to. Reading it is how the screen and the rule stay the same fact.
func cue_on() -> bool:
	if _phase != Phase.PLAYER_ACT and _phase != Phase.ENEMY_ACT:
		return false
	return _count <= _combat.timed_window_frames


## How long the current cue runs from end to end, so a view can draw a wind-up as a FRACTION
## of itself rather than against a number it keeps its own copy of.
##
## One is returned outside a cue rather than zero: every caller divides by this, and a phase
## with no wind-up should read as "finished", not crash the frame.
func cue_span() -> int:
	match _phase:
		Phase.PLAYER_ACT:
			return _combat.attack_cue_frames
		Phase.ENEMY_ACT:
			return _combat.defend_cue_frames
		_:
			return 1


func acting_side_is_player() -> bool:
	return _phase == Phase.PLAYER_ACT


## Whether the press already captured for this cue landed inside the window. Read by the view
## to show the result of a press the instant it happens rather than at impact.
func pressed_in_time() -> bool:
	return _pressed_at >= 0 and _pressed_at <= _combat.timed_window_frames


func finished() -> bool:
	return _phase == Phase.OVER


func outcome() -> Outcome:
	return _outcome


## What the world should carry out. A copy: reading the list must not be able to change it.
func effects() -> Array[Dictionary]:
	return _effects.duplicate(true)


## The cues this fight has asked for since the last drain, oldest first.
##
## A separate list from _effects on purpose. Effects are applied ONCE at the end and are
## discarded entirely on defeat - but losing is exactly when the defeat sting has to play, and
## a fight makes noise all the way through rather than at the end. Drained rather than read,
## because two cues can land in one frame: a hit that wins the fight is a hit AND a victory,
## and a victory that levels is two more.
func take_sounds() -> Array[StringName]:
	var out := _sounds.duplicate()
	_sounds.clear()
	return out


## Names a cue for the view to play. This class may not touch an autoload, so it reports.
func _want(cue: Sfx.Cue) -> void:
	_sounds.append(Sfx.id_of(cue))


## Moves the cursor by whole steps, WRAPPING, and only while something is waiting for a
## choice. A press during a cue is a timing press, not a menu one.
func move(delta: int) -> bool:
	if _phase != Phase.MENU and _phase != Phase.ITEMS:
		return false
	if size() < 2:
		return false
	_index = posmod(_index + delta, size())
	_want(Sfx.Cue.MENU_MOVE)
	return true


## The confirm button, whatever it means where the fight currently is.
func press() -> void:
	match _phase:
		Phase.MENU:
			_want(Sfx.Cue.MENU_CONFIRM)
			_confirm_command()
		Phase.ITEMS:
			_want(Sfx.Cue.MENU_CONFIRM)
			_confirm_item()
		Phase.PLAYER_ACT, Phase.ENEMY_ACT:
			# ONLY the first press of a cue is captured. Without this, holding the button down
			# or mashing it would land a press in every window by accident, and the timing
			# mechanic would be "press a lot" - which is not a mechanic.
			if _pressed_at >= 0:
				return
			_pressed_at = _count
		_:
			# A message reads for a fixed time and OVER is over. Letting a press skip either
			# would make a battle's length depend on how fast someone taps, which is exactly
			# what the fixed frame schedule exists to prevent.
			pass


## The cancel button. It backs out of the item list and does nothing anywhere else: a fight is
## left by winning, losing or fleeing, and a cancel that closed one would be an escape hatch
## with no cost. Returns whether it did anything, so a view can stay quiet when it did not.
func cancel() -> bool:
	if _phase != Phase.ITEMS:
		return false
	_phase = Phase.MENU
	_index = Row.ITEM
	_want(Sfx.Cue.MENU_MOVE)
	return true


## One physics frame. The only clock this class has.
func tick() -> void:
	match _phase:
		Phase.PLAYER_ACT:
			_count -= 1
			if _count <= 0:
				_land_player_hit()
		Phase.ENEMY_ACT:
			_count -= 1
			if _count <= 0:
				_land_enemy_hit()
		Phase.MESSAGE:
			_count -= 1
			if _count <= 0:
				_leave_message()
		_:
			pass


# -- commands ------------------------------------------------------------------------------


func _confirm_command() -> void:
	match _index:
		Row.ATTACK:
			_begin_cue(Phase.PLAYER_ACT, _combat.attack_cue_frames)
		Row.ITEM:
			_phase = Phase.ITEMS
			_index = 0
		Row.FLEE:
			_flee()
		_:
			pass


func _confirm_item() -> void:
	var row := item_row(_index)
	# An empty bag's one row is a statement, not a button. Refusing is the PauseMenu rule:
	# a confirm that silently did nothing is indistinguishable from one that failed.
	if row == null:
		return
	var healed := mini(_hp + row.heal, player_max_hp()) - _hp
	if healed > 0:
		_want(Sfx.Cue.HEAL)
	_hp += healed
	# Appended NOW, against the count this fight was handed. The snapshot is what makes the
	# take safe: the world cannot be asked for an item the player did not have when the menu
	# was drawn, so the sink never has to refuse one.
	_effects.append({"op": GameContext.OP_TAKE_ITEM, "id": row.id, "count": 1})
	row.count -= 1
	if row.count <= 0:
		_items.remove_at(_index)
	_index = Row.ITEM
	# Using a thing costs the turn. Otherwise the answer to every fight is to drink first and
	# swing afterwards, for free.
	_say("%s used the %s." % [_hero_name(), row.name] if healed > 0
		else "%s used the %s, and nothing changed." % [_hero_name(), row.name], Phase.ENEMY_ACT)


func _flee() -> void:
	if _enemy.boss:
		# Refused, and it still costs the turn: a free retry would make "can I run" a question
		# with no downside, which is not a decision.
		_say("There is no way past the %s." % _enemy.name, Phase.ENEMY_ACT)
		return
	_outcome = Outcome.FLED
	# No seen effect: something you ran from is still standing there. The party effect still
	# goes out, because the damage taken on the way out is real.
	_seal()
	_say("%s broke away." % _hero_name(), Phase.OVER)


# -- the cues ------------------------------------------------------------------------------


func _begin_cue(next: Phase, frames: int) -> void:
	_phase = next
	_count = maxi(frames, 1)
	_pressed_at = -1


func _land_player_hit() -> void:
	var base := damage(_combat.attack_at(_level), _enemy.defense)
	var timed := pressed_in_time()
	var dealt := base * 2 if timed else base
	# The IMPACT is the feedback, not the press. A click the moment the button went down would
	# tell the player they pressed - which they know - instead of telling them they landed it.
	_want(Sfx.Cue.TIMED_HIT if timed else Sfx.Cue.HIT)
	_enemy_hp = maxi(_enemy_hp - dealt, 0)
	var line := "A clean hit! %d damage." % dealt if timed else "%d damage." % dealt
	if _enemy_hp <= 0:
		_win()
		return
	_say(line, Phase.ENEMY_ACT)


func _land_enemy_hit() -> void:
	var move := _pick_move()
	var base := damage(_enemy.attack + int(move.get("power", 0)), _combat.defense_at(_level))
	var blocked := pressed_in_time()
	var taken := maxi(base / 2, 1) if blocked else base
	_want(Sfx.Cue.BLOCK if blocked else Sfx.Cue.HURT)
	_hp = maxi(_hp - taken, 0)
	var name := str(move.get("name", "attacks"))
	var line := "%s: %s. Blocked - %d damage." % [_enemy.name, name, taken] if blocked \
		else "%s: %s. %d damage." % [_enemy.name, name, taken]
	if _hp <= 0:
		_want(Sfx.Cue.DEFEAT)
		_outcome = Outcome.DEFEAT
		# Deliberately NOT sealed: a defeat's effects are never applied, so there is nothing
		# to collect. The world discards them and opens the game-over screen.
		_say(line + " %s falls." % _hero_name(), Phase.OVER)
		return
	_say(line, Phase.MENU)


func _pick_move() -> Dictionary:
	if _enemy.moves.is_empty():
		return {}
	return _enemy.moves[_moves_rng.next_int(0, _enemy.moves.size() - 1)]


func _win() -> void:
	_outcome = Outcome.VICTORY
	var earned := _enemy.xp
	_xp += earned
	var was := _level
	_level = _combat.level_for(_xp)
	var line := "%s is down. +%d xp." % [_enemy.name, earned]
	_want(Sfx.Cue.VICTORY)
	if _level > was:
		# A level restores the player completely. It is the loop the whole design rests on:
		# ambient fights are what make the boss survivable, and a heal you can feel is what
		# makes fighting one more thing before the door a real decision.
		_hp = player_max_hp()
		_want(Sfx.Cue.LEVEL_UP)
		line += " Level %d!" % _level
	_seal()
	_say(line, Phase.OVER)


## What the fight leaves behind, appended as it ends.
##
## There is deliberately no "already sealed" guard here. _win() and _flee() are the only
## callers, each is terminal, and neither phase they leave behind accepts an input that could
## re-enter them - so a guard would be a branch no test could ever reach, which is the shape
## this repo treats as decoration. The double-award this would otherwise protect against lives
## on the VIEW side, where a screen emitting its result twice is genuinely possible, and it is
## latched and mutant-tested there.
func _seal() -> void:
	if _outcome == Outcome.VICTORY:
		_effects.append({"op": GameContext.OP_SEEN, "key": _seen_key})
	_effects.append({"op": GameContext.OP_PARTY, "hp": _hp, "xp": _xp, "level": _level})
	# Coin is appended only on a WIN, and only when the enemy carries any. It rides the same
	# collected list as everything else, so a defeat - whose effects world_scene discards
	# wholesale - pays nothing, and the rule "a fight never writes" is untouched.
	if _outcome == Outcome.VICTORY and _enemy.gold > 0:
		_effects.append({"op": GameContext.OP_GOLD, "amount": _enemy.gold})


# -- messages ------------------------------------------------------------------------------


func _say(text: String, next: Phase) -> void:
	_message = text
	_after_message = next
	_phase = Phase.MESSAGE
	_count = maxi(_combat.message_frames, 1)


func _leave_message() -> void:
	_message = ""
	match _after_message:
		Phase.ENEMY_ACT:
			_begin_cue(Phase.ENEMY_ACT, _combat.defend_cue_frames)
		Phase.MENU:
			_phase = Phase.MENU
			_index = Row.ATTACK
		_:
			_phase = _after_message
	_count = 0 if _phase == Phase.MENU or _phase == Phase.OVER else _count


func _hero_name() -> String:
	return "You"


# -- the one arithmetic rule ---------------------------------------------------------------


## What a hit takes off. The floor of 1 is the rule that matters: without it, armour that
## matches an attacker exactly makes a fight unwinnable in both directions and the battle
## simply never ends, which reads as a frozen game rather than as a balance problem.
static func damage(attack: int, defense: int) -> int:
	return maxi(1, attack - defense)
