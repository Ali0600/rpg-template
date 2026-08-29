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
##
## A PARTY IS A LIST EVEN WHEN IT IS ONE. A game that declares no party is handed a single
## synthesized member, so there is exactly one code path through a fight rather than a solo one
## and a party one, of which the solo one is the tested one and the party one is where the bugs
## live. The proof that the list of one behaves like the scalar it replaced is that every
## scripted play session written before parties existed passes untouched.
##
## The round is COMMAND-ALL-THEN-RESOLVE, which is the NES norm: Final Fantasy I's manual has
## the player enter commands for all four characters before the round executes, and Dragon
## Quest gives orders only at the start of a turn. Resolution runs in PARTY ORDER rather than
## by a stat, and FF1 is the precedent for that too - its own order is a random shuffle that
## ignores everyone's numbers. A declared order is also the only one a replayed fight can have.

## Where the fight is. MENU, SPELLS, ITEMS and ALLY are waiting for the player; PLAYER_ACT and
## ENEMY_ACT are a cue counting down toward an impact; MESSAGE is a line being read; OVER is
## the result.
##
## ALLY is the targeting cursor, and it exists ONLY when more than one member is standing. A
## heal with one possible recipient is a mode with one option in it, which is the same argument
## that kept an enemy cursor out when fights went 1v1 - and it is what makes a solo fight's
## key presses identical to the ones every session before M27 recorded. There is still no ENEMY
## cursor: fights here are one foe, so an offense spell hits the foe.
enum Phase { MENU, SPELLS, ITEMS, ALLY, PLAYER_ACT, ENEMY_ACT, MESSAGE, OVER }

## The command menu's rows, in the order they are drawn. The view indexes its labels by this,
## so the order lives in one place rather than in a list beside a list.
##
## MAGIC is INSERTED rather than appended, and that is the genre's order rather than a
## preference: Final Fantasy's Fight/Magic/Drink/Item, Dragon Quest's Fight/Run/Spell/Item and
## Chrono Trigger's Att/Tech/Item all put casting immediately after attacking, and a player
## reaches for the second row by muscle memory. The cost is that every counting test and every
## play session pressing its way down this menu moves, which is paid deliberately - the
## Equipment and Status rows in PauseMenu were inserted for the same reason and at the same price.
enum Row { ATTACK, MAGIC, ITEM, FLEE }

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


## One spell the player can cast, already resolved - and "already resolved" includes WHICH
## SPELLS THESE ARE. The world filters the registered spells by the player's level before
## handing them over, because knowing a spell is derived from level and this class may not ask
## a Registry what exists. A spell the player has not reached is not a dimmed row here; it is
## simply not in the list, the way an item they are not carrying is not.
class SpellRow:
	var id: StringName = &""
	var name: String = ""
	var cost: int = 0
	var kind: int = SpellDef.Kind.ATTACK
	var power: int = 0
	var status_turns: int = 0

	static func of(spell_id: StringName, spell_name: String, mp_cost: int, spell_kind: int,
			spell_power: int, turns: int) -> SpellRow:
		var out := SpellRow.new()
		out.id = spell_id
		out.name = spell_name
		out.cost = mp_cost
		out.kind = spell_kind
		out.power = spell_power
		out.status_turns = turns
		return out


## One fighter on the player's side, fully resolved before the fight is built.
##
## Everything per-person lives here: their own numbers, their own curve, their own gear total
## and their own spell list - all four are per-member in every reference game, and Dragon Quest
## II's hero famously has no magic at all while the sorceress who joins him holds the attack
## spells. The world resolves all of it, because this class may not reach a Registry.
##
## An EMPTY id is the leader's, and it is what the world's effect sink routes on: the leader is
## four fields on GameState where a companion is a record in a map, and the difference has to
## survive the trip out of the fight.
class Fighter:
	var id: StringName = &""
	var name: String = ""
	var character: StringName = &""
	var combat: CombatDef = null
	var hp: int = 0
	var xp: int = 0
	var level: int = 1
	var mp: int = 0
	var attack_mod: int = 0
	var defense_mod: int = 0
	## SpellRows, already narrowed to what THIS member can cast at THIS level.
	var spells: Array = []

	static func of(member_id: StringName, member_name: String, art: StringName,
			curve: CombatDef, member_hp: int, member_xp: int, member_level: int, member_mp: int,
			attack: int, defense: int, known: Array) -> Fighter:
		var out := Fighter.new()
		out.id = member_id
		out.name = member_name
		out.character = art
		out.combat = curve
		out.level = maxi(member_level, 1)
		# Clamped to the curve for the reason a save is: a member carrying more than their
		# level allows describes somebody the game cannot produce, and a fight is not the place
		# to argue with it. The floor is nought rather than one, because a member who FELL in
		# an earlier fight arrives at nought and stays down until somebody heals them.
		out.hp = clampi(member_hp, 0, curve.max_hp(out.level))
		out.xp = maxi(member_xp, 0)
		out.mp = clampi(member_mp, 0, curve.max_mp(out.level))
		out.attack_mod = maxi(attack, 0)
		out.defense_mod = maxi(defense, 0)
		out.spells = known.duplicate()
		return out

	func down() -> bool:
		return hp <= 0

	func max_hp() -> int:
		return combat.max_hp(level)

	func max_mp() -> int:
		return combat.max_mp(level)


## One thing a member has decided to do this round, waiting for the round to resolve.
##
## Declarations are collected before ANY of them happen, which is what "command all, then
## resolve" means - so this holds the choice and the target, and nothing about the outcome.
class Order:
	var member: int = 0
	var row: int = Row.ATTACK
	var spell: SpellRow = null
	var item: ItemRow = null
	## Which member this lands on, for a heal or an item. -1 is "the enemy" or "nobody".
	var target: int = -1


var _combat: CombatDef
var _enemy: EnemyDef
var _enemy_hp: int = 0
## Everyone on the player's side, in the order they were handed over - which is the order they
## act in and the order they are drawn in. Never re-sorted: a fight that reordered its own
## party would replay differently from the one that was played.
var _members: Array = []
## Cues asked for and not yet drained by the view.
var _sounds: Array[StringName] = []

## Untyped Array because a typed default for a nested class is not a constant expression -
## the same reason PauseMenu._items is untyped.
var _items: Array = []
## What has been declared this round, oldest first. Cleared as each round begins.
var _orders: Array = []
## Which member is choosing right now, or -1 when nobody is. The MENU, SPELLS, ITEMS and ALLY
## pages all belong to this member.
var _commander: int = 0
## How far through _orders the resolution has walked, or -1 when it is not walking.
var _order_at: int = -1
## Which member is swinging, so the view knows who to lean forward.
var _acting: int = -1
## Which member the enemy has aimed at. Chosen BEFORE the cue begins rather than at the impact,
## because the cue is the thing being reacted to - a player defending has to know who is being
## hit while there is still time to press.
var _target: int = -1
## The page the ALLY cursor was opened from, so cancelling goes back where it came from.
var _ally_from := Phase.SPELLS
## The choice waiting for a target while the ALLY cursor is up.
var _pending: Order = null
## Enemy turns still owed to a sleep, counted DOWN as each one is skipped. It belongs to the
## fight and nothing else: a sleep does not survive the battle it was cast in, so there is
## nothing here to seal, save or migrate.
var _enemy_asleep_turns: int = 0
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
var _target_rng: SeededRng
var _effects: Array[Dictionary] = []


## Builds a fight. Everything is passed in already resolved - the player's numbers, the
## enemy's definition, the usable rows - because this class may not look anything up.
##
## `seen_key` is the map-scoped id the world will mark on victory, carried rather than
## rebuilt so the logic never has to know how a seen key is spelled.
## `combat` is the GAME's curve, not any one member's. It paces the fight - the cue lengths,
## the press window, how long a line is read for - and those are properties of the screen
## rather than of a fighter: two members with different windows would be one screen asking the
## player to react at two speeds. Each member's own curve, which is what their strength grows
## on, rides on the Fighter.
static func of(combat: CombatDef, enemy: EnemyDef, members: Array, items: Array,
		seen_key: String, seed_value: int) -> BattleLogic:
	var out := BattleLogic.new()
	out._combat = combat
	out._enemy = enemy
	out._enemy_hp = enemy.max_hp
	out._members = members.duplicate()
	out._items = items.duplicate()
	out._seen_key = seen_key
	# Its own derived stream, so a later randomised feature - a crit, a drop - cannot reshuffle
	# the moves an existing fight already draws.
	out._moves_rng = SeededRng.new(seed_value).derive("moves")
	# A SECOND derived stream for who the enemy swings at, and the separation is the whole
	# reason a party did not change a single existing fight: drawing a target from the moves
	# stream would consume a number that fight was going to spend on a move, and every solo
	# replay in the repo would diverge. Deliberately drawn even at one target, because a branch
	# no test can distinguish from its absence is decoration.
	out._target_rng = SeededRng.new(seed_value).derive("target")
	out._begin_round()
	return out


# -- who is standing -------------------------------------------------------------------------


## The indices of everyone still on their feet, in party order. The party's turn order, the
## enemy's list of things to aim at, and the ally cursor's rows are all this same answer.
func _living() -> Array[int]:
	var out: Array[int] = []
	for i in _members.size():
		if not _fighter(i).down():
			out.append(i)
	return out


func _fighter(at: int) -> Fighter:
	return _members[at] as Fighter


## Starts a fresh round of declarations: nothing decided, the first member on their feet
## choosing, and the cursor home on Attack.
func _begin_round() -> void:
	_orders = []
	_order_at = -1
	_acting = -1
	_target = -1
	_pending = null
	var standing := _living()
	_commander = standing[0] if not standing.is_empty() else -1
	_phase = Phase.MENU
	_index = Row.ATTACK


## What a member's gear is contributing, so the wiring from the world is assertable rather than
## only visible in the damage it happens to produce.
func attack_mod(at: int = 0) -> int:
	return _fighter(at).attack_mod


func defense_mod(at: int = 0) -> int:
	return _fighter(at).defense_mod


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
	if _phase == Phase.SPELLS:
		return maxi(spell_rows().size(), 1)
	if _phase == Phase.ALLY:
		return maxi(_living().size(), 1)
	return Row.size()


func item_rows() -> Array:
	return _items.duplicate()


func item_row(at: int) -> ItemRow:
	if at < 0 or at >= _items.size():
		return null
	return _items[at]


## The spells the member who is CHOOSING can cast. Whose page this is changes as the round is
## declared, which is the whole reason a party has per-member magic to begin with.
func spell_rows() -> Array:
	if _commander < 0:
		return []
	return _fighter(_commander).spells.duplicate()


func spell_row(at: int) -> SpellRow:
	var rows := spell_rows()
	if at < 0 or at >= rows.size():
		return null
	return rows[at]


## Whether the member who is choosing could cast this one right now. Read by the view to dim
## what is out of reach, and by _confirm_spell to refuse it - one function, so what the screen
## shows and what the press does cannot disagree.
func can_afford(row: SpellRow) -> bool:
	if row == null or _commander < 0:
		return false
	return row.cost <= _fighter(_commander).mp


## Enemy turns still owed to a sleep. Zero is "awake", so a caller never has to ask twice.
func enemy_asleep_turns() -> int:
	return _enemy_asleep_turns


## The party, by index. There are no leader shims - a `player_hp()` standing for `member_hp(0)`
## would be a second name for one fact, and the one that gets read in a hurry is the one that
## stops being true the day the leader is not first.
func member_count() -> int:
	return _members.size()


func member_hp(at: int) -> int:
	return _fighter(at).hp


func member_max_hp(at: int) -> int:
	return _fighter(at).max_hp()


func member_mp(at: int) -> int:
	return _fighter(at).mp


func member_max_mp(at: int) -> int:
	return _fighter(at).max_mp()


func member_level(at: int) -> int:
	return _fighter(at).level


func member_xp(at: int) -> int:
	return _fighter(at).xp


func member_name(at: int) -> String:
	return _fighter(at).name


func member_character(at: int) -> StringName:
	return _fighter(at).character


func member_down(at: int) -> bool:
	return _fighter(at).down()


## Which member is choosing, or -1 when nobody is. The view marks them so a player with two
## fighters knows whose turn they are giving orders for.
func commander() -> int:
	return _commander


## Which member is swinging, or -1. Only meaningful during PLAYER_ACT.
func acting_member() -> int:
	return _acting


## Which member the enemy has aimed at, or -1. Set before the defend cue opens, so a player has
## the whole wind-up to see who is about to be hit.
func target_member() -> int:
	return _target


## The rows of the ally cursor, as member indices. Only the standing: a fallen ally is not a
## heal target here, because reviving in a fight is a verb this template does not have.
func ally_rows() -> Array[int]:
	return _living()


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
	if _phase != Phase.MENU and _phase != Phase.ITEMS and _phase != Phase.SPELLS \
			and _phase != Phase.ALLY:
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
		Phase.SPELLS:
			_want(Sfx.Cue.MENU_CONFIRM)
			_confirm_spell()
		Phase.ITEMS:
			_want(Sfx.Cue.MENU_CONFIRM)
			_confirm_item()
		Phase.ALLY:
			_want(Sfx.Cue.MENU_CONFIRM)
			_confirm_ally()
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
	if _phase == Phase.ALLY:
		# Back to the page the target was being chosen for, with nothing declared. EarthBound's
		# manual says exactly this: select the target, B to cancel.
		_phase = _ally_from
		_index = _pending_index()
		_pending = null
		_want(Sfx.Cue.MENU_MOVE)
		return true
	if _phase == Phase.SPELLS:
		_phase = Phase.MENU
		_index = Row.MAGIC
		_want(Sfx.Cue.MENU_MOVE)
		return true
	if _phase == Phase.ITEMS:
		_phase = Phase.MENU
		_index = Row.ITEM
		_want(Sfx.Cue.MENU_MOVE)
		return true
	if _phase == Phase.MENU and not _orders.is_empty():
		# Taking back the previous member's order and handing the menu back to them. Both
		# Final Fantasy and Dragon Quest let a party walk its declarations backwards, and
		# without it a mis-press on the first of two members can only be fixed by playing the
		# round out. With ONE member there is never a previous order, so this answers false and
		# a solo cancel is refused exactly as it always was.
		var taken: Order = _orders.pop_back()
		_commander = taken.member
		_index = taken.row
		_want(Sfx.Cue.MENU_MOVE)
		return true
	return false


## Where the cursor sat on the page the ally cursor was opened from, so cancelling puts it back
## on the spell or the item that was being aimed rather than at the top of the list.
func _pending_index() -> int:
	if _pending == null:
		return 0
	if _ally_from == Phase.SPELLS:
		var rows := spell_rows()
		for i in rows.size():
			if rows[i] == _pending.spell:
				return i
	else:
		for i in _items.size():
			if _items[i] == _pending.item:
				return i
	return 0


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
			var order := Order.new()
			order.member = _commander
			order.row = Row.ATTACK
			_declare(order)
		Row.MAGIC:
			_phase = Phase.SPELLS
			_index = 0
		Row.ITEM:
			_phase = Phase.ITEMS
			_index = 0
		Row.FLEE:
			# Running is a PARTY decision, not one member's - so it resolves immediately and
			# takes whatever has already been declared with it. A round where one member flees
			# and the rest keep swinging is not a thing any reference game offers.
			_flee()
		_:
			pass


## Records one member's choice and hands the menu to the next member still standing. When
## nobody is left to ask, the round resolves - which is what "command all, then resolve" is.
func _declare(order: Order) -> void:
	_orders.append(order)
	var standing := _living()
	var next := -1
	for i in standing:
		var already := false
		for placed: Order in _orders:
			if placed.member == i:
				already = true
				break
		if not already:
			next = i
			break
	if next >= 0:
		_commander = next
		_phase = Phase.MENU
		_index = Row.ATTACK
		return
	_commander = -1
	_resolve_next()


## Opens the ally cursor, or skips it when there is only one place the thing could land.
##
## Skipping is what keeps a solo fight's presses identical to every session recorded before
## parties existed, and it is not merely a convenience: a cursor with one row is a screen
## asking a question whose answer it already has.
func _aim_at_ally(order: Order, from: Phase) -> void:
	var standing := _living()
	if standing.size() < 2:
		order.target = _commander
		_declare(order)
		return
	_pending = order
	_ally_from = from
	_phase = Phase.ALLY
	_index = maxi(standing.find(_commander), 0)


func _confirm_ally() -> void:
	var standing := _living()
	if _pending == null or _index < 0 or _index >= standing.size():
		return
	var chosen := _pending
	chosen.target = standing[_index]
	_pending = null
	_declare(chosen)


## Casting, which is three verbs behind one row.
##
## A cast has NO TIMING WINDOW, and that is deliberate rather than unfinished. The timed press
## is this template's own invention for swinging a weapon - a thing you aim - where a spell in
## every game this borrows from resolves because you chose it. Giving magic a window too would
## make the whole fight one reflex test and leave the menu with nothing to decide.
func _confirm_spell() -> void:
	var row := spell_row(_index)
	# An empty page's one row is a statement, not a button - the _confirm_item rule.
	if row == null:
		return
	if not can_afford(row):
		# SAID, and it costs nothing - not the turn either. Money is the precedent: a price is
		# quoted out loud, so a player who reaches for something they cannot pay for hears why
		# not, rather than pressing a key that appears to be broken. Where an item they are not
		# carrying is simply absent, a spell they know and cannot pay for has to stay on the
		# page, or the list would change shape as they spend.
		_want(Sfx.Cue.LOCKED)
		_say("Not enough magic for %s." % row.name, Phase.SPELLS)
		return
	var order := Order.new()
	order.member = _commander
	order.row = Row.MAGIC
	order.spell = row
	if row.kind == SpellDef.Kind.HEAL:
		# The only thing in the fight that has more than one place it could land.
		_aim_at_ally(order, Phase.SPELLS)
		return
	_declare(order)


func _confirm_item() -> void:
	var row := item_row(_index)
	# An empty bag's one row is a statement, not a button. Refusing is the PauseMenu rule:
	# a confirm that silently did nothing is indistinguishable from one that failed.
	if row == null:
		return
	var order := Order.new()
	order.member = _commander
	order.row = Row.ITEM
	order.item = row
	_aim_at_ally(order, Phase.ITEMS)


# -- resolving the round ---------------------------------------------------------------------


## Performs the next declared order, or hands the round to the enemy when there are none left.
##
## There is deliberately NO "skip a member who fell" guard here, and it is worth saying why,
## because it is the first thing a reader expects. Only standing members are ever asked for an
## order, and the enemy acts once the party's whole round has resolved - so nothing on the
## player's side can take damage between choosing and acting, and a member cannot fall mid
## round. A guard for it would be a branch no test could reach, which this repo treats as
## decoration rather than as safety. The day an enemy acts BETWEEN player actions is the day it
## becomes reachable, and the day to write it.
func _resolve_next() -> void:
	_acting = -1
	_order_at += 1
	if _order_at >= _orders.size():
		_begin_enemy_turn()
		return
	_perform(_orders[_order_at])


func _perform(order: Order) -> void:
	match order.row:
		Row.ATTACK:
			_acting = order.member
			_begin_cue(Phase.PLAYER_ACT, _combat.attack_cue_frames)
		Row.MAGIC:
			_cast(order)
		Row.ITEM:
			_use(order)
		_:
			_resolve_next()


func _cast(order: Order) -> void:
	var caster := _fighter(order.member)
	var row := order.spell
	# Checked again at the moment it happens, not only when it was chosen: a member can declare
	# a cast and be hit before their turn comes round, and the mp they were counting on may
	# have gone into something else in between.
	if row == null or row.cost > caster.mp:
		_say("%s cannot manage it." % caster.name, Phase.PLAYER_ACT)
		return
	caster.mp -= row.cost
	_want(Sfx.Cue.CAST)
	match row.kind:
		SpellDef.Kind.HEAL:
			var on := _fighter(order.target if order.target >= 0 else order.member)
			var healed := mini(on.hp + row.power, on.max_hp()) - on.hp
			on.hp += healed
			if healed > 0:
				_want(Sfx.Cue.HEAL)
				_say("%s casts %s. %s: %d healed." % [caster.name, row.name, on.name, healed],
					Phase.PLAYER_ACT)
			else:
				_say("%s casts %s, and %s is already whole." % [caster.name, row.name, on.name],
					Phase.PLAYER_ACT)
		SpellDef.Kind.SLEEP:
			_enemy_asleep_turns = row.status_turns
			_say("%s casts %s. The %s sleeps." % [caster.name, row.name, _enemy.name],
				Phase.PLAYER_ACT)
		_:
			# Damage is FLAT - the enemy's defense does not reduce it - and that is what gives
			# magic a job beside a stronger swing: the answer to something armoured. It is also
			# one fewer number to tune, because SpellDef.power then means damage and nothing else.
			_want(Sfx.Cue.HIT)
			_enemy_hp = maxi(_enemy_hp - row.power, 0)
			var line := "%s casts %s. %d damage." % [caster.name, row.name, row.power]
			if _enemy_hp <= 0:
				_win()
				return
			_say(line, Phase.PLAYER_ACT)


func _use(order: Order) -> void:
	var user := _fighter(order.member)
	var row := order.item
	var on := _fighter(order.target if order.target >= 0 else order.member)
	if row == null or row.count <= 0:
		# The bag emptied between choosing and acting - two members reaching for the last tonic
		# in one round is exactly the case a queued round makes possible.
		_say("%s reaches for nothing." % user.name, Phase.PLAYER_ACT)
		return
	var healed := mini(on.hp + row.heal, on.max_hp()) - on.hp
	if healed > 0:
		_want(Sfx.Cue.HEAL)
	on.hp += healed
	# Appended NOW, against the count this fight was handed. The snapshot is what makes the
	# take safe: the world cannot be asked for an item the player did not have when the menu
	# was drawn, so the sink never has to refuse one.
	_effects.append({"op": GameContext.OP_TAKE_ITEM, "id": row.id, "count": 1})
	row.count -= 1
	if row.count <= 0:
		_items.erase(row)
	# Using a thing costs the turn. Otherwise the answer to every fight is to drink first and
	# swing afterwards, for free.
	_say("%s used the %s on %s." % [user.name, row.name, on.name] if healed > 0
		else "%s used the %s, and nothing changed." % [user.name, row.name], Phase.PLAYER_ACT)


## Running, which the whole party does together or not at all.
##
## Declared by whichever member is choosing and resolved on the spot, taking any orders already
## declared with it - a round where one member flees and the others keep swinging is not a
## thing any reference game offers, and it would leave the fled member somewhere the fight has
## no way to describe.
func _flee() -> void:
	if _enemy.boss:
		# Refused, and it still costs the turn: a free retry would make "can I run" a question
		# with no downside, which is not a decision. The rest of the round is dropped, because
		# the members who had already declared were declaring for a round that is now over.
		_orders = []
		_order_at = -1
		_commander = -1
		_say("There is no way past the %s." % _enemy.name, Phase.ENEMY_ACT)
		return
	_outcome = Outcome.FLED
	# No seen effect: something you ran from is still standing there. The party effect still
	# goes out, because the damage taken on the way out is real.
	_seal()
	_say("%s broke away." % _party_name(), Phase.OVER)


## What to call the player's side in a line about all of it. One member speaks for themselves;
## more than one and there is no name that fits, so the genre's own word does.
func _party_name() -> String:
	if _members.size() == 1:
		return _fighter(0).name
	return "The party"


# -- the cues ------------------------------------------------------------------------------


## The enemy's turn, which it does not always get.
##
## The sleep is checked HERE rather than at the impact, because a sleeping enemy must not
## telegraph a blow the player then has to defend against - the cue is the thing being reacted
## to, so a skipped turn has to skip the cue and not just the damage. One turn is spent per
## check, so a two-turn sleep is two turns the enemy does not act, counted where they are
## actually taken rather than by a clock.
func _begin_enemy_turn() -> void:
	_acting = -1
	if _enemy_asleep_turns > 0:
		_enemy_asleep_turns -= 1
		_say("The %s sleeps on." % _enemy.name, Phase.MENU)
		return
	# WHO is chosen before the cue opens, not at the impact. The cue is the thing being reacted
	# to, so a player defending has to know who is about to be hit while there is still time to
	# press - and the halving belongs to whoever is actually hit.
	var standing := _living()
	_target = standing[_target_rng.next_int(0, standing.size() - 1)]
	_begin_cue(Phase.ENEMY_ACT, _combat.defend_cue_frames)


func _begin_cue(next: Phase, frames: int) -> void:
	_phase = next
	_count = maxi(frames, 1)
	_pressed_at = -1


func _land_player_hit() -> void:
	var swinger := _fighter(_acting)
	var base := damage(swinger.combat.attack_at(swinger.level) + swinger.attack_mod,
		_enemy.defense)
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
	_say(line, Phase.PLAYER_ACT)


func _land_enemy_hit() -> void:
	var move := _pick_move()
	var on := _fighter(_target)
	var base := damage(_enemy.attack + int(move.get("power", 0)),
		on.combat.defense_at(on.level) + on.defense_mod)
	var blocked := pressed_in_time()
	var taken := maxi(base / 2, 1) if blocked else base
	_want(Sfx.Cue.BLOCK if blocked else Sfx.Cue.HURT)
	on.hp = maxi(on.hp - taken, 0)
	var name := str(move.get("name", "attacks"))
	var line := "%s: %s. Blocked - %d damage." % [_enemy.name, name, taken] if blocked \
		else "%s: %s. %d damage." % [_enemy.name, name, taken]
	if on.hp <= 0:
		line += " %s falls." % on.name
		# The fight is lost only when EVERYONE is down, which is the rule in every reference
		# game. One member falling is a setback the survivors fight on through, and the fallen
		# stay down until somebody pays to put them back up.
		if _living().is_empty():
			_want(Sfx.Cue.DEFEAT)
			_outcome = Outcome.DEFEAT
			# Deliberately NOT sealed: a defeat's effects are never applied, so there is
			# nothing to collect. The world discards them and opens the game-over screen.
			_say(line, Phase.OVER)
			return
	_say(line, Phase.MENU)


func _pick_move() -> Dictionary:
	if _enemy.moves.is_empty():
		return {}
	return _enemy.moves[_moves_rng.next_int(0, _enemy.moves.size() - 1)]


## Every member still STANDING earns the full award, and nobody who fell earns anything.
##
## Dragon Quest's rule rather than Final Fantasy's, which divides the award among survivors.
## Dividing would punish a small party for being small - and this template's demo party is two,
## which is the size the division hurts most - and it would need a rounding decision that a
## single shared xp curve has nowhere to put. The fallen earning nothing is both series' rule.
func _win() -> void:
	_outcome = Outcome.VICTORY
	var earned := _enemy.xp
	var line := "%s is down. +%d xp." % [_enemy.name, earned]
	_want(Sfx.Cue.VICTORY)
	var levelled := false
	for i in _living():
		var who := _fighter(i)
		who.xp += earned
		var was := who.level
		who.level = who.combat.level_for(who.xp)
		if who.level > was:
			# A level restores that member completely - magic included, which is what
			# "completely" has to mean once there is magic. It is the loop the whole design
			# rests on: ambient fights are what make the boss survivable, and a heal you can
			# feel is what makes fighting one more thing before the door a real decision.
			who.hp = who.max_hp()
			who.mp = who.max_mp()
			if not levelled:
				# One cue however many of them levelled: two chimes in one frame is noise, and
				# the second carries no information the first did not.
				_want(Sfx.Cue.LEVEL_UP)
				levelled = true
			line += " %s: level %d!" % [who.name, who.level] if _members.size() > 1 \
				else " Level %d!" % who.level
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
	# ONE effect carrying everybody, rather than one per member. The sink applies an effect
	# list all-or-nothing, and a party half-written - the leader's new level saved and the
	# companion's fall not - is a state no rule in the game produces.
	var who: Array[Dictionary] = []
	for i in _members.size():
		var member := _fighter(i)
		who.append({"id": String(member.id), "hp": member.hp, "xp": member.xp,
			"level": member.level, "mp": member.mp})
	_effects.append({"op": GameContext.OP_PARTY, "members": who})
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
		Phase.PLAYER_ACT:
			# "Carry on down the round." Every act the party declared ends here, and the walk
			# hands over to the enemy when it runs out of orders.
			_resolve_next()
		Phase.ENEMY_ACT:
			_begin_enemy_turn()
		Phase.MENU:
			_begin_round()
		_:
			# A refused cast lands here, going back to the page it was refused on with the
			# cursor where it was left: the player is choosing again, not starting the turn
			# over. No arm of its own, because "become what you were told to become" is what
			# the default already does - and a second literal `_phase = Phase.SPELLS` in this
			# file is a line no mutant could aim at unambiguously.
			_phase = _after_message
	_count = 0 if _phase == Phase.MENU or _phase == Phase.OVER or _phase == Phase.SPELLS \
		else _count


# -- the one arithmetic rule ---------------------------------------------------------------


## What a hit takes off. The floor of 1 is the rule that matters: without it, armour that
## matches an attacker exactly makes a fight unwinnable in both directions and the battle
## simply never ends, which reads as a frozen game rather than as a balance problem.
static func damage(attack: int, defense: int) -> int:
	return maxi(1, attack - defense)
