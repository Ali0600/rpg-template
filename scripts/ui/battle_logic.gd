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
## A MEMBER ACTS THE MOMENT THEY CHOOSE. The turn belongs to one member at a time: they pick,
## it happens, and the next standing member is asked once the blow has landed. Super Mario RPG
## is the shape. M27 shipped Final Fantasy I's instead - every member declares, then the round
## plays out - and the first person to play it rejected it at the controls, because a press
## whose effect is invisible for a whole extra menu reads as a press the game missed. Order is
## PARTY ORDER rather than a stat, and FF1 is the precedent for that too: its own order is a
## random shuffle that ignores everyone's numbers.
##
## AND THE OTHER SIDE IS A LIST TOO. A fight holds up to `BattleScreen.MAX_FOES` of them, named
## by one map record, and every living foe takes a turn after the whole party has gone. "One
## foe" was a scope line rather than a convention - Dragon Quest I is the only reference that
## fights one at a time, and the rest field authored formations. A fight of one is a list of
## one, for the reason the party is: one code path, and the proof is that every session
## recorded before crowds existed passes untouched.

## Where the fight is. MENU, SPELLS, ITEMS, ALLY and FOE are waiting for the player; PLAYER_ACT
## and ENEMY_ACT are a cue counting down toward an impact; MESSAGE is a line being read; OVER is
## the result.
##
## ALLY and FOE are the two targeting cursors, and each exists ONLY when there is more than one
## thing to point at. A heal with one possible recipient - or a swing with one possible target -
## is a mode with one option in it, and skipping it is what makes a fight of one press-for-press
## identical to the ones every session recorded before either cursor existed. Super Mario RPG
## asks which enemy "if there is more than one", so the skip is the genre's answer as well as
## the compatible one.
enum Phase { MENU, SPELLS, ITEMS, ALLY, FOE, PLAYER_ACT, ENEMY_ACT, MESSAGE, OVER }

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
	## ONE asks which foe, ALL skips the question. Defaulted on the factory rather than required,
	## so the three call sites that predate formations still read as they did.
	var target: int = SpellDef.Target.ONE
	## Which number a BOOST or a SAP moves. Defaulted for the same reason `target` is.
	var stat: int = SpellDef.Stat.ATTACK
	## What the spell is made of, looked up in the foe's own resistance map. Empty is elementless
	## and lands at face value, so every call site that predates elements reads as it did.
	var element: StringName = &""

	static func of(spell_id: StringName, spell_name: String, mp_cost: int, spell_kind: int,
			spell_power: int, turns: int, shape: int = SpellDef.Target.ONE,
			moves: int = SpellDef.Stat.ATTACK, made_of: StringName = &"") -> SpellRow:
		var out := SpellRow.new()
		out.id = spell_id
		out.name = spell_name
		out.cost = mp_cost
		out.kind = spell_kind
		out.power = spell_power
		out.status_turns = turns
		out.target = shape
		out.stat = moves
		out.element = made_of
		return out


## What is currently true OF a fighter or a foe that is not one of their numbers.
##
## ONE holder, carried by both sides, which is the whole of "the status system points both ways":
## a party member and an enemy are afflicted by the same fields, ticked by the same function, and
## read by the same fold. A second copy shaped slightly differently is how one side quietly
## stops expiring.
##
## Named fields rather than a list of effects. Every other struct here is written this way, and a
## fixed shape is what makes a replayed fight easy to reason about - a list would need an order,
## and an order is a thing that can differ between two runs that should be identical.
##
## Everything here is BATTLE-ONLY and dies with the fight. Nothing reads it afterwards, nothing
## saves it, and `BattleLogic` still writes nothing - which is why this milestone needed no save
## version. Persistent affliction is a milestone of its own; docs/DECISIONS.md carries it.
class Status:
	## Turns this one still spends asleep. Decremented by whoever is taking the turn, so each
	## sleeper counts its own down - Final Fantasy I's rule, and one a battle-wide flag could not
	## express.
	var asleep_turns: int = 0
	var attack_delta: int = 0
	var attack_turns: int = 0
	var defense_delta: int = 0
	var defense_turns: int = 0

	## What this is contributing RIGHT NOW. Zero once the turns run out, so an expired shift is
	## indistinguishable from one that never happened and no caller has to check both.
	func attack_bonus() -> int:
		return attack_delta if attack_turns > 0 else 0

	func defense_bonus() -> int:
		return defense_delta if defense_turns > 0 else 0

	## Shifts a stat, replacing whatever was there rather than stacking onto it. Re-casting a
	## boost refreshes it; it does not double it. Stacking is how a fight becomes unloseable in
	## four casts, and no reference game in this set stacks either.
	func shift(which: int, delta: int, turns: int) -> void:
		if which == SpellDef.Stat.ATTACK:
			attack_delta = delta
			attack_turns = turns
		else:
			defense_delta = delta
			defense_turns = turns

	## One turn passes for the SHIFTS. Sleep is counted separately by the turn-taker, because
	## sleeping is the thing that consumes the turn rather than something that ran during it.
	func tick() -> void:
		attack_turns = maxi(attack_turns - 1, 0)
		defense_turns = maxi(defense_turns - 1, 0)

	## What the battle screen writes beside the numbers, or "" for nothing worth a tag.
	func tag() -> String:
		if asleep_turns > 0:
			return "ZZZ"
		if attack_turns > 0:
			return "ATK+" if attack_delta > 0 else "ATK-"
		if defense_turns > 0:
			return "DEF+" if defense_delta > 0 else "DEF-"
		return ""


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
	## What is currently true of them beyond their numbers. Its own object rather than loose
	## fields, so the party side and the foe side are afflicted by exactly the same shape.
	var status := Status.new()
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


## What a member has just chosen to do, on its way to happening.
##
## It exists for the step between the two, which is the ally cursor: a heal or an item is chosen
## before it is aimed, so the choice has to be held somewhere while the player picks who. It
## holds the choice and the target, and nothing about the outcome.
class Order:
	var member: int = 0
	var row: int = Row.ATTACK
	var spell: SpellRow = null
	var item: ItemRow = null
	## Which MEMBER this lands on, for a heal or an item. -1 is "nobody on our side".
	var target: int = -1
	## Which FOE this lands on, for a swing, an attack spell or a sleep. -1 is "nobody over
	## there", which is what a heal leaves it at.
	##
	## Two fields rather than one signed number. A single `target` encoding foes as negatives is
	## a decode every reader has to remember, and the one who forgets aims a heal at member 1.
	var foe: int = -1


## One enemy in the fight, with the state that belongs to IT rather than to the fight.
##
## This exists because `Registry.get_resource` hands back a cached instance: two "slink"
## placements resolve to the SAME `EnemyDef`, so hit points and a sleep counter physically
## cannot live on the def. Per-enemy status is also the genre's rule rather than a convenience -
## Final Fantasy I's sleepers each roll their own wake, which a battle-wide flag cannot express.
class Foe:
	var def: EnemyDef
	## What the messages call it. Lettered "Slink A"/"Slink B" when the formation repeats a name,
	## which is EarthBound's convention; a name that appears once stays bare, so a fight of one
	## reads exactly as it always did.
	var name: String = ""
	var hp: int = 0
	## The same holder the party carries. `asleep_turns` used to be a field right here, and
	## moving it in is what let one tick and one fold serve both sides.
	var status := Status.new()

	static func of(enemy: EnemyDef, display: String) -> Foe:
		var out := Foe.new()
		out.def = enemy
		out.name = display
		out.hp = enemy.max_hp
		return out

	func down() -> bool:
		return hp <= 0


var _combat: CombatDef
## Everyone on the enemy's side, in the order the record named them - which is the order they
## are drawn in, the order they take their turns in, and the order the cursor walks.
var _foes: Array = []
## Everyone on the player's side, in the order they were handed over - which is the order they
## act in and the order they are drawn in. Never re-sorted: a fight that reordered its own
## party would replay differently from the one that was played.
var _members: Array = []
## Cues asked for and not yet drained by the view.
var _sounds: Array[StringName] = []

## Untyped Array because a typed default for a nested class is not a constant expression -
## the same reason PauseMenu._items is untyped.
var _items: Array = []
## Whose turn it is on the player's side, or -1 when it is the enemy's. The MENU, SPELLS, ITEMS
## and ALLY pages all belong to this member, and so does the act they choose - a member holds
## the turn from being asked until their blow has landed, which is what lets the view mark one
## member throughout rather than losing them mid-swing.
var _commander: int = 0
## Which member is swinging, so the view knows who to lean forward.
var _acting: int = -1
## Which member the enemy has aimed at. Chosen BEFORE the cue begins rather than at the impact,
## because the cue is the thing being reacted to - a player defending has to know who is being
## hit while there is still time to press.
var _target: int = -1
## The page the ALLY cursor was opened from, so cancelling goes back where it came from.
var _ally_from := Phase.SPELLS
## The same, for the FOE cursor. Two fields rather than one shared "where did this come from",
## because the two cursors are opened from overlapping pages and a single field would answer
## whichever question was asked last.
var _foe_from := Phase.MENU
## The choice waiting for a target while either cursor is up. One field, because only one cursor
## can be open at a time - a swing is aimed at a foe or a heal at an ally, never both at once.
var _pending: Order = null
## Which foe is taking its turn, or -1 when the enemy side is not acting. The enemy phase walks
## the living in foe order, and this is how far it has walked.
var _foe_turn: int = -1
## Which foe a swing is aimed at, carried from the moment it was chosen through the cue to the
## impact. The cursor is long gone by the time the blow lands, so the aim cannot be read back
## off `_index`.
var _struck: int = -1
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
## `enemies` is the formation, in the order the map record named them.
static func of(combat: CombatDef, enemies: Array, members: Array, items: Array,
		seen_key: String, seed_value: int) -> BattleLogic:
	var out := BattleLogic.new()
	out._combat = combat
	out._foes = _formation(enemies)
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


## Wraps the defs in Foes and letters the duplicates. A formation of two slinks is "Slink A" and
## "Slink B" - EarthBound's convention - because "the Slink is down" says nothing about which of
## them fell. A name that appears once is left ALONE, which is what keeps every message in a
## fight of one byte-identical to the ones recorded before formations existed.
static func _formation(enemies: Array) -> Array:
	var seen := {}
	for entry: EnemyDef in enemies:
		seen[entry.name] = int(seen.get(entry.name, 0)) + 1
	var used := {}
	var out: Array = []
	for entry: EnemyDef in enemies:
		var display := entry.name
		if int(seen.get(entry.name, 0)) > 1:
			var nth := int(used.get(entry.name, 0))
			used[entry.name] = nth + 1
			display = "%s %s" % [entry.name, char("A".unicode_at(0) + nth)]
		out.append(Foe.of(entry, display))
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


## The same answer for the other side: the foes still up, in formation order. The foe cursor's
## rows, the enemy phase's turn order, and what an ALL spell reaches.
func _living_foes() -> Array[int]:
	var out: Array[int] = []
	for at in _foes.size():
		if not _foe(at).down():
			out.append(at)
	return out


func _fighter(at: int) -> Fighter:
	return _members[at] as Fighter


func _foe(at: int) -> Foe:
	return _foes[at] as Foe


## Starts a fresh round: the first member on their feet choosing, and the cursor home on Attack.
func _begin_round() -> void:
	_acting = -1
	_target = -1
	_pending = null
	_foe_turn = -1
	_struck = -1
	var standing := _living()
	if standing.is_empty():
		_commander = -1
		_phase = Phase.MENU
		_index = Row.ATTACK
		return
	_hand_turn_to(standing[0])


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
	if _phase == Phase.FOE:
		return maxi(_living_foes().size(), 1)
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


## Turns this foe still owes to a sleep. Zero is "awake", so a caller never has to ask twice.
func enemy_asleep_turns(at: int = 0) -> int:
	return _foe(at).status.asleep_turns


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


## The short word for whatever is currently true of them beyond their numbers, or "" for
## nothing. The view writes it beside the health rather than instead of it: Final Fantasy I
## replaces the HP readout because its block holds one number and no more, and this screen has a
## caption line AND a bar. Imitating a constraint this screen does not have would cost the
## player a number to be faithful to a layout.
func member_tag(at: int) -> String:
	return _fighter(at).status.tag()


## Which member has the turn - choosing or swinging - or -1 while the enemy has it. The view
## marks them so a player with two fighters knows who they are pressing for.
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


## The rows of the foe cursor, as foe indices. Only the living, which is what makes a stale
## target impossible: the cursor is built at the moment it opens and the blow lands on the same
## beat, so there is no gap for the thing you aimed at to die in.
func foe_rows() -> Array[int]:
	return _living_foes()


func foe_count() -> int:
	return _foes.size()


func foe_down(at: int) -> bool:
	return _foe(at).down()


## The foe side of `member_tag`, and the same word list. A sleeping enemy has said "sleeps on"
## in a message since M25, which is a thing you have to be watching to catch; the tag is what
## makes it readable at a glance on a formation of three.
func foe_tag(at: int) -> String:
	return _foe(at).status.tag()


func foe_character(at: int) -> StringName:
	return _foe(at).def.character


## Every foe's id, for the world's own announcements. Ids rather than display names, because a
## lettered "Slink B" is a thing to read and not a thing to match on.
func foe_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for at in _foes.size():
		out.append(_foe(at).def.id)
	return out


## Which foe is taking its turn, or -1. Only meaningful during ENEMY_ACT, and it is how the view
## knows which one to lean forward.
func acting_foe() -> int:
	return _foe_turn


## Which foe a swing is aimed at, or -1. Meaningful from the moment the cursor closes until the
## blow lands, which is exactly how long the view marks it.
func struck_foe() -> int:
	return _struck


## The foe accessors default to the first, so a fight of one reads exactly as it always did and
## the twenty-odd assertions written against a single enemy never moved.
func enemy_hp(at: int = 0) -> int:
	return _foe(at).hp


func enemy_max_hp(at: int = 0) -> int:
	return _foe(at).def.max_hp


func enemy_name(at: int = 0) -> String:
	return _foe(at).name


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
			and _phase != Phase.ALLY and _phase != Phase.FOE:
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
		Phase.FOE:
			_want(Sfx.Cue.MENU_CONFIRM)
			_confirm_foe()
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
	if _phase == Phase.FOE:
		# The same, for the other cursor - back to the command row or the spell it came from.
		_phase = _foe_from
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
	# And nowhere else - including a party's menu mid-round. There is no previous choice left to
	# take back once every choice acts on the spot: the member before this one has already swung,
	# and unwinding that would mean giving the enemy its health back.
	return false


## Where the cursor sat on the page a cursor was opened from, so cancelling puts it back on the
## spell, the item or the command row that was being aimed rather than at the top of the list.
func _pending_index() -> int:
	if _pending == null:
		return 0
	var from := _foe_from if _phase == Phase.FOE else _ally_from
	if from == Phase.MENU:
		# A swing, aimed straight off the command menu. Back to the row it was chosen on.
		return _pending.row
	if from == Phase.SPELLS:
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
			_aim_at_foe(order, Phase.MENU)
		Row.MAGIC:
			_phase = Phase.SPELLS
			_index = 0
		Row.ITEM:
			_phase = Phase.ITEMS
			_index = 0
		Row.FLEE:
			# Running is a PARTY decision, not one member's: whoever picks it takes everybody,
			# and the members after them do not get asked. A round where one member flees and
			# the rest keep swinging is not a thing any reference game offers.
			_flee()
		_:
			pass


## Opens the ally cursor, or skips it when there is only one place the thing could land.
##
## Skipping is what keeps a solo fight's presses identical to every session recorded before
## parties existed, and it is not merely a convenience: a cursor with one row is a screen
## asking a question whose answer it already has.
func _aim_at_ally(order: Order, from: Phase) -> void:
	var standing := _living()
	if standing.size() < 2:
		order.target = _commander
		_perform(order)
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
	_perform(chosen)


## Opens the foe cursor, or skips it when there is only one thing left to hit. The ally cursor's
## rule, mirrored - and Super Mario RPG's, which asks which enemy only "if there is more than
## one". Skipping is what keeps every fight against a single foe pressing the keys it always did.
##
## The cursor opens on the FIRST living foe rather than on whoever was aimed at last: there is
## no "last" to remember, because the aim never outlives the blow.
func _aim_at_foe(order: Order, from: Phase) -> void:
	var alive := _living_foes()
	if alive.is_empty():
		return
	if alive.size() < 2:
		order.foe = alive[0]
		_perform(order)
		return
	_pending = order
	_foe_from = from
	_phase = Phase.FOE
	_index = 0


func _confirm_foe() -> void:
	var alive := _living_foes()
	if _pending == null or _index < 0 or _index >= alive.size():
		return
	var picked := _pending
	picked.foe = alive[_index]
	_pending = null
	_perform(picked)


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
	if row.kind == SpellDef.Kind.HEAL or row.kind == SpellDef.Kind.BOOST:
		# Both land on OUR side, so both take the ally cursor - and both skip it at one standing
		# member, which is what keeps a solo fight pressing the keys it always did.
		_aim_at_ally(order, Phase.SPELLS)
		return
	if row.target == SpellDef.Target.ALL:
		# It reaches everything, so there is nothing to ask.
		_perform(order)
		return
	_aim_at_foe(order, Phase.SPELLS)


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


# -- taking the turn ---------------------------------------------------------------------------


## Carries out what a member just chose, the moment they chose it.
##
## This is the whole shape of the round: a choice does not wait for anybody. Command-all-then-
## resolve shipped first and a player rejected it at the controls - choosing Attack and watching
## the menu move on to somebody else reads as the game ignoring the press, however faithful to
## Final Fantasy I's manual it is.
func _perform(order: Order) -> void:
	match order.row:
		Row.ATTACK:
			_acting = order.member
			_struck = order.foe
			_begin_cue(Phase.PLAYER_ACT, _combat.attack_cue_frames)
		Row.MAGIC:
			_cast(order)
		Row.ITEM:
			_use(order)
		_:
			_advance()


## Hands the turn to the next member still standing, or to the enemy once the party has all
## gone. Whoever just acted is the mark: everybody before them has been asked, nobody after has.
##
## The fallen are skipped because _living() is re-read here rather than fixed when the round
## began. What still cannot happen is a member falling MID-round: the enemy acts once the whole
## party has gone, so nothing on the player's side takes damage between one act and the next.
## The day an enemy acts between two members is the day that becomes reachable.
func _advance() -> void:
	_acting = -1
	var acted := _commander
	# `who` rather than `i`, deliberately: `for i in _living():` is the line the experience
	# mutant anchors on over in _win, and a second copy of it here would have sed editing
	# whichever comes first in the file and reporting a verdict about the other one.
	for who in _living():
		if who > acted:
			_hand_turn_to(who)
			return
	_begin_enemy_phase()


## Gives the turn to `who` - or spends it sleeping on their behalf.
##
## The player-side mirror of `_begin_foe_turn`, and it exists for the same reason that one does:
## the MESSAGE. A turn that passed a sleeping member in silence would read as a press the game
## dropped, which is precisely the complaint that killed M27's round shape. Saying "X sleeps on."
## and letting `_leave_message` walk on to the next member costs one line and answers it.
##
## Both callers go through here - `_begin_round` for the first member and `_advance` for every
## one after - so a sleeper can never be handed the menu, whichever door the turn arrives by.
func _hand_turn_to(who: int) -> void:
	_commander = who
	# `member` rather than `it`, deliberately: `_begin_foe_turn` calls its foe `it`, and the
	# sleep check below would otherwise be character-identical to that one - so a mutant aimed
	# at either would edit whichever came first and report a verdict about the other side.
	var member := _fighter(who)
	member.status.tick()
	if member.status.asleep_turns > 0:
		member.status.asleep_turns -= 1
		_say("%s sleeps on." % member.name, Phase.PLAYER_ACT)
		return
	_phase = Phase.MENU
	_index = Row.ATTACK


## What a message calls the stat a shift moved. Here rather than on `SpellDef` because it is
## wording, and the enum is the fact.
func _stat_word(which: int) -> String:
	return "attack" if which == SpellDef.Stat.ATTACK else "guard"


## What `row` actually takes off `target`, once that foe's answer to the spell's element is
## applied. The ONE place a resistance is read, called by both arms of the attack branch below.
##
## Two arms doing this arithmetic separately is the `_attack_of`/`_defense_of` shape and the same
## failure: the copy somebody forgets is not a crash, it is a weakness that works when you aim
## and silently not when you sweep, which reads as the spell being broken rather than as a bug.
##
## FLOORED AT 1 wherever the element does not stop the spell outright, so "resisted" and "immune"
## stay different things a player can tell apart. Zero comes back only from a zero percent, which
## is what makes the caller's "no effect" line honest.
func _spell_damage(row: SpellRow, target: Foe) -> int:
	var pct := target.def.resistance_to(row.element)
	if pct == 0:
		return 0
	return maxi(row.power * pct / 100, 1)


func _cast(order: Order) -> void:
	var caster := _fighter(order.member)
	var row := order.spell
	# Not re-checked for affordability here, and that is a consequence of acting on the spot:
	# _confirm_spell refuses what cannot be paid for in the same frame this runs, with nothing
	# in between that could spend the magic. Under the queued round a member could declare a
	# cast and have their mp go elsewhere before their turn came - that gap no longer exists,
	# and a guard for it would be a branch no test could reach.
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
			var sleeper := _foe(order.foe if order.foe >= 0 else 0)
			sleeper.status.asleep_turns = row.status_turns
			_say("%s casts %s. The %s sleeps." % [caster.name, row.name, sleeper.name],
				Phase.PLAYER_ACT)
		SpellDef.Kind.BOOST:
			# At an ALLY, and the target arm is the heal's exactly: -1 means the cursor was
			# skipped because there was only one of us, which is the caster.
			var lifted := _fighter(order.target if order.target >= 0 else order.member)
			lifted.status.shift(row.stat, row.power, row.status_turns)
			_say("%s casts %s. %s's %s rises." % [caster.name, row.name, lifted.name,
				_stat_word(row.stat)], Phase.PLAYER_ACT)
		SpellDef.Kind.SAP:
			# The same verb pointed the other way, at a foe, on the attack spell's target arm.
			# The MINUS lives here rather than in the data: `power` is a size on every kind.
			var drained := _foe(order.foe if order.foe >= 0 else 0)
			drained.status.shift(row.stat, -row.power, row.status_turns)
			_say("%s casts %s. The %s's %s drops." % [caster.name, row.name, drained.name,
				_stat_word(row.stat)], Phase.PLAYER_ACT)
		_ when row.target == SpellDef.Target.ALL:
			# Everything still standing, for the same flat damage. The one place in the fight a
			# single choice reaches more than one thing.
			_want(Sfx.Cue.HIT)
			var reached := _living_foes()
			var felled: Array[String] = []
			# Named PER FOE rather than as one figure "to each". They were the same number until
			# an element could scale them apart, and "7 damage to each" against a formation where
			# one of them burns and one shrugs is a caption that states something false - the
			# exact failure a wrong claim in a comment already cost this project once.
			var struck: Array[String] = []
			for at in reached:
				var each := _foe(at)
				var took := _spell_damage(row, each)
				each.hp = maxi(each.hp - took, 0)
				struck.append("%s %d" % [each.name, took])
				if each.down():
					felled.append(each.name)
			if _living_foes().is_empty():
				_win(" and ".join(felled))
				return
			var swept := "%s casts %s. %s." % [caster.name, row.name, ", ".join(struck)]
			for name in felled:
				swept += " %s is down." % name
			_say(swept, Phase.PLAYER_ACT)
		_:
			# Damage is FLAT - the enemy's defense does not reduce it - and that is what gives
			# magic a job beside a stronger swing: the answer to something armoured. It is also
			# one fewer number to tune, because SpellDef.power then means damage and nothing else.
			_want(Sfx.Cue.HIT)
			var hit := _foe(order.foe if order.foe >= 0 else 0)
			var dealt := _spell_damage(row, hit)
			hit.hp = maxi(hit.hp - dealt, 0)
			var line := "%s casts %s. %d damage." % [caster.name, row.name, dealt]
			if dealt == 0:
				# It spent the magic and the turn and moved no number, so it SAYS so: a cast that
				# changed nothing and reported a damage figure of zero reads as a broken button,
				# which is the argument problems() makes for refusing a powerless spell outright.
				line = "%s casts %s, and it does nothing to %s." % [caster.name, row.name, hit.name]
			if hit.down() and not _living_foes().is_empty():
				line += " %s is down." % hit.name
			if _living_foes().is_empty():
				_win(hit.name)
				return
			_say(line, Phase.PLAYER_ACT)


func _use(order: Order) -> void:
	var user := _fighter(order.member)
	var row := order.item
	var on := _fighter(order.target if order.target >= 0 else order.member)
	# No emptied-bag re-check, for _cast's reason: two members reaching for the last tonic in one
	# round was a case the queued round made possible, and taking the turn on the spot closes it.
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
## Chosen by whichever member has the turn and answered on the spot, for everybody - a round
## where one member flees and the others keep swinging is not a thing any reference game offers,
## and it would leave the fled member somewhere the fight has no way to describe.
func _flee() -> void:
	var barring := _boss()
	if barring >= 0:
		# Refused, and it still costs the turn: a free retry would make "can I run" a question
		# with no downside, which is not a decision. The members who had not gone yet lose their
		# turn with it, because the round the party spent trying to run is over.
		#
		# ANY boss in the formation refuses, because unfleeability is a property of the encounter
		# rather than an average over its members - Super Mario RPG's mandatory fights are
		# mandatory whole. `_foe_turn` is wound back so the enemy phase starts at the first foe.
		_commander = -1
		_foe_turn = -1
		_say("There is no way past the %s." % _foe(barring).name, Phase.ENEMY_ACT)
		return
	_outcome = Outcome.FLED
	# No seen effect: something you ran from is still standing there. The party effect still
	# goes out, because the damage taken on the way out is real.
	_seal()
	_say("%s broke away." % _party_name(), Phase.OVER)


## The first foe that will not be run from, or -1 when the whole formation can be.
func _boss() -> int:
	for at in _foes.size():
		if _foe(at).def.boss:
			return at
	return -1


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
func _begin_enemy_phase() -> void:
	_acting = -1
	_struck = -1
	# Nobody on the player's side holds the turn now, which is what keeps the view marking one
	# fighter: the mark is the commander while the party is going and the target once it is not.
	_commander = -1
	_foe_turn = -1
	_next_foe_or_round()


## Hands the enemy's turn to the next living foe, or starts a fresh round once they have all
## gone. Every living enemy acts every round, which is the rule in every reference game - FF1's
## nine are nine of the thirteen entries in its shuffle.
##
## `taken` and `next_up` rather than the party walk's names, deliberately: `_advance` is the same
## shape one side over, and two identical loops in one file is how a mutant aimed at the first
## quietly reports a verdict about the second.
func _next_foe_or_round() -> void:
	var taken := _foe_turn
	for next_up in _living_foes():
		if next_up > taken:
			_begin_foe_turn(next_up)
			return
	_begin_round()


func _begin_foe_turn(at: int) -> void:
	_foe_turn = at
	var it := _foe(at)
	# BEFORE the sleep check, not after it. A sleeping foe returns from this function, so a tick
	# below the branch would let a sap sit on it for as long as it stayed asleep - the affliction
	# outlasting its own duration because the target was too incapacitated to notice.
	it.status.tick()
	if it.status.asleep_turns > 0:
		# Its own counter, so the rest of the formation still swings. FF1's sleepers each roll
		# their own wake, which one flag on the fight could not express.
		it.status.asleep_turns -= 1
		_say("The %s sleeps on." % it.name, Phase.ENEMY_ACT)
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
	var aimed := _foe(_struck if _struck >= 0 else 0)
	var base := damage(_attack_of(swinger), _foe_defense(aimed))
	var timed := pressed_in_time()
	var dealt := base * 2 if timed else base
	# The IMPACT is the feedback, not the press. A click the moment the button went down would
	# tell the player they pressed - which they know - instead of telling them they landed it.
	_want(Sfx.Cue.TIMED_HIT if timed else Sfx.Cue.HIT)
	aimed.hp = maxi(aimed.hp - dealt, 0)
	var line := "A clean hit! %d damage." % dealt if timed else "%d damage." % dealt
	if aimed.down() and not _living_foes().is_empty():
		line += " %s is down." % aimed.name
	if _living_foes().is_empty():
		_win(aimed.name)
		return
	_say(line, Phase.PLAYER_ACT)


func _land_enemy_hit() -> void:
	var move := _pick_move()
	var swinging := _foe(_foe_turn)
	var on := _fighter(_target)
	if not str(move.get("status", "")).is_empty():
		_land_affliction(move, swinging, on)
		return
	var base := damage(_foe_attack(swinging) + int(move.get("power", 0)), _defense_of(on))
	var blocked := pressed_in_time()
	var taken := maxi(base / 2, 1) if blocked else base
	_want(Sfx.Cue.BLOCK if blocked else Sfx.Cue.HURT)
	on.hp = maxi(on.hp - taken, 0)
	var name := str(move.get("name", "attacks"))
	var line := "%s: %s. Blocked - %d damage." % [swinging.name, name, taken] if blocked \
		else "%s: %s. %d damage." % [swinging.name, name, taken]
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
	# ENEMY_ACT rather than MENU: the next foe in the formation may still be owed a turn, and
	# _leave_message asks _next_foe_or_round which it is. At one foe that walk finds nobody left
	# and starts the round in the same tick the MENU arm used to.
	_say(line, Phase.ENEMY_ACT)


## A move that afflicts rather than hurts, and the defend cue's answer to it.
##
## A WELL-TIMED GUARD SHRUGS IT OFF ENTIRELY, where a timed guard against a blow only halves it.
## All-or-nothing because there is no half of being asleep, and because the alternative - a
## shorter affliction for a good press - would make the cue's reward invisible in the moment it
## was earned. It is also what keeps the timing mechanic meaningful in exactly the fights that
## lean on statuses; a cue with nothing to do would quietly become decoration there.
##
## No defeat check: an affliction deals no damage, so it cannot be the thing that fells anybody.
## `EnemyDef.problems()` refuses a move that tries to do both.
func _land_affliction(move: Dictionary, swinging: Foe, on: Fighter) -> void:
	var move_name := str(move.get("name", "attacks"))
	if pressed_in_time():
		_want(Sfx.Cue.BLOCK)
		_say("%s: %s. Shrugged off." % [swinging.name, move_name], Phase.ENEMY_ACT)
		return
	_want(Sfx.Cue.HURT)
	var turns := int(move.get("turns", 1))
	var line := ""
	if str(move.get("status", "")) == "sleep":
		on.status.asleep_turns = turns
		line = "%s: %s. %s drops asleep." % [swinging.name, move_name, on.name]
	else:
		var which := SpellDef.Stat.ATTACK if str(move.get("stat", "")) == "attack" \
			else SpellDef.Stat.DEFENSE
		on.status.shift(which, -int(move.get("amount", 1)), turns)
		line = "%s: %s. %s's %s drops." % [swinging.name, move_name, on.name, _stat_word(which)]
	_say(line, Phase.ENEMY_ACT)


func _pick_move() -> Dictionary:
	var moves := _foe(_foe_turn).def.moves
	if moves.is_empty():
		return {}
	return moves[_moves_rng.next_int(0, moves.size() - 1)]


## Every member still STANDING earns the full award, and nobody who fell earns anything.
##
## Dragon Quest's rule rather than Final Fantasy's, which divides the award among survivors.
## Dividing would punish a small party for being small - and this template's demo party is two,
## which is the size the division hurts most - and it would need a rounding decision that a
## single shared xp curve has nowhere to put. The fallen earning nothing is both series' rule.
## `felled` names what the last blow put down, so a formation says which one ended it. Empty
## means the first foe, which is the only foe a fight of one has - so the victory line of a solo
## fight is character-for-character the one it always was.
##
## The award SUMS the formation: Final Fantasy I's gold is "the direct sum of the gold values of
## all monsters killed", and a foe felled early in the fight still counts toward it.
func _win(felled: String = "") -> void:
	_outcome = Outcome.VICTORY
	var earned := 0
	for at in _foes.size():
		earned += _foe(at).def.xp
	var line := "%s is down. +%d xp." % [felled if not felled.is_empty() else _foe(0).name, earned]
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
	# Coin is appended only on a WIN, and only when the formation carries any. It is SUMMED over
	# every foe, the way the experience is - a fight pays for what it killed. It rides the same
	# collected list as everything else, so a defeat - whose effects world_scene discards
	# wholesale - pays nothing, and the rule "a fight never writes" is untouched.
	var purse := 0
	for at in _foes.size():
		purse += _foe(at).def.gold
	if _outcome == Outcome.VICTORY and purse > 0:
		_effects.append({"op": GameContext.OP_GOLD, "amount": purse})


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
			# "Carry on round the party." Every member's act ends here, and the turn goes to
			# whoever has not had it - or to the enemy when everybody has.
			_advance()
		Phase.ENEMY_ACT:
			# "Carry on down the formation." Every foe's turn ends here too, and the walk starts
			# the next round once they have all had one.
			_next_foe_or_round()
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


# -- what a fighter's numbers actually are -------------------------------------------------
#
# FOUR contributors now reach two numbers: the level curve, worn equipment, and a status shift -
# and on the foe side the def and a shift. Before M30 there were two, and each hit resolver
# added them up itself. A third contributor is exactly when that stops being safe: the copy
# somebody forgets to update is not a crash, it is a buff that works when you swing and not when
# you are swung at, which reads as the spell being broken.
#
# So these are the ONLY places either number is assembled, and every call site reads them.
# `lessons.md` names this twice - compute a compound value once above the branches, and populate
# a field other systems read even where your own path ignores it.


func _attack_of(who: Fighter) -> int:
	return maxi(0, who.combat.attack_at(who.level) + who.attack_mod + who.status.attack_bonus())


## Floored at nought rather than allowed to go negative: a sap deep enough to invert this would
## make a hit land for MORE than it does on an unarmoured target, which is not what "your guard
## is down" means. `damage()`'s own floor of 1 then keeps the blow real.
func _defense_of(who: Fighter) -> int:
	return maxi(0, who.combat.defense_at(who.level) + who.defense_mod + who.status.defense_bonus())


func _foe_attack(it: Foe) -> int:
	return maxi(0, it.def.attack + it.status.attack_bonus())


func _foe_defense(it: Foe) -> int:
	return maxi(0, it.def.defense + it.status.defense_bonus())
