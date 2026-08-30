class_name BattleDriver
extends RefCounted
## Plays a real fight to its end, so a balance claim is made OF the fight rather than of
## arithmetic about it.
##
## `BattleLogic` is pure and has no clock — `tick()` is one physics frame — so a whole battle
## fits in a loop with no scene tree, no waiting, and no seed left to chance. That is what lets
## a gate say "perfect play wins on every seed" honestly, instead of bounding it with a
## worst-case sum. The sum is what this replaced, and it had hard-coded ONE enemy acting once
## per round against ONE player: true when it was written, and it would have gone on reporting
## green about a duel the game no longer contains.
##
## TWO POLICIES, AND BOTH ARE LOAD-BEARING. An optimal driver only ever walks the branches
## optimal play reaches — a party that times every press is barely hurt, so a win proves the
## fight is winnable and nothing whatever about whether the enemy can hurt anybody. PERFECT and
## MASH are the two halves of the difficulty statement, and a fight that fails either is
## broken: one that PERFECT loses is a wall, one that MASH wins has no timing mechanic.

enum Policy {
	## Presses inside every timing window, and always swings at whichever foe is closest to
	## falling — fewer bodies on the field is fewer blows per round, so it is also the play a
	## person converges on.
	PERFECT,
	## Presses on EVERY frame, which is what mashing actually is. Only the first press of a cue
	## is captured, so the press that counts is the one arriving at the top of the wind-up, and
	## it is never in time. Mashing therefore lands no timed hit and blocks nothing — without
	## this driver having to model "untimed" as a special case, which would be a second opinion
	## about a rule `BattleLogic` already owns.
	MASH,
}

## What a played fight looks like from outside. Everything here is COUNTED rather than inferred,
## because the interesting failures are the ones where a fight ends the right way for the wrong
## reason — a party that wins having never been swung at, a formation whose third member never
## took a turn.
class Report extends RefCounted:
	var outcome: BattleLogic.Outcome = BattleLogic.Outcome.NONE
	var ended := false
	var frames := 0
	var presses := 0
	var timed_presses := 0
	## Times a member's swing began, and times a foe's blow began. A formation of three that
	## reports two blows in a whole fight has a foe that never acted.
	var swings := 0
	var blows := 0
	var party_hp: Array[int] = []
	var foes: Array[String] = []
	## Set when the driver reached a page it has no business on. Empty is the healthy value; a
	## test asserts it rather than trusting a `push_error` nobody reads.
	var fault := ""

	func standing() -> int:
		var out := 0
		for hp in party_hp:
			if hp > 0:
				out += 1
		return out


## Plays `logic` to the end and reports. The cap is on ITERATIONS, not on ticks, because menu
## phases do not tick — and a loop bounded only by "until the thing under test says stop" is a
## test that hangs instead of failing. `ended` says whether the fight really finished, and every
## caller must assert it.
static func play(logic: BattleLogic, policy: Policy, cap := 20000) -> Report:
	var out := Report.new()
	for at in logic.foe_count():
		out.foes.append(logic.enemy_name(at))
	var was := logic.phase()
	var guard := 0
	while not logic.finished() and guard < cap:
		guard += 1
		var phase := logic.phase()
		if phase != was:
			if phase == BattleLogic.Phase.PLAYER_ACT:
				out.swings += 1
			elif phase == BattleLogic.Phase.ENEMY_ACT:
				out.blows += 1
			was = phase
		match phase:
			BattleLogic.Phase.MENU:
				_aim(logic, 0)
				logic.press()
				out.presses += 1
			BattleLogic.Phase.FOE:
				if policy == Policy.PERFECT:
					_aim(logic, _weakest_row(logic))
				logic.press()
				out.presses += 1
			BattleLogic.Phase.SPELLS, BattleLogic.Phase.ITEMS, BattleLogic.Phase.ALLY:
				# This driver only ever chooses Attack, so nothing should open these. Reaching
				# one means the command rows moved under it, and a driver that quietly pressed
				# through would be casting or drinking while reporting on swinging.
				out.fault = "the driver reached page %d, which choosing Attack cannot open" % phase
				break
			_:
				if policy == Policy.MASH or logic.cue_on():
					if logic.cue_on():
						out.timed_presses += 1
					logic.press()
					out.presses += 1
				logic.tick()
				out.frames += 1
	out.ended = logic.finished()
	out.outcome = logic.outcome()
	for at in logic.member_count():
		out.party_hp.append(logic.member_hp(at))
	return out


## Puts the cursor on `row` of the current page. There is no setter, so this is the wrap-around
## `move` used as one — and `move` refuses a page of fewer than two rows, which is exactly the
## case where the cursor is already where it needs to be.
static func _aim(logic: BattleLogic, row: int) -> void:
	var steps := row - logic.index()
	if steps != 0:
		logic.move(steps)


## The ROW of the living foe with the least health left. A row, not a foe index: the cursor
## counts over the living, so the two diverge the moment anything falls.
static func _weakest_row(logic: BattleLogic) -> int:
	var rows := logic.foe_rows()
	var best := 0
	for i in rows.size():
		if logic.enemy_hp(rows[i]) < logic.enemy_hp(rows[best]):
			best = i
	return best
