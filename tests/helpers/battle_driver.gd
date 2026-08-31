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
	## Times every press like PERFECT, and CASTS whenever it can pay for something. Appended
	## rather than inserted, so PERFECT and MASH keep the values every existing assertion was
	## written against.
	##
	## It exists because skill was not the only axis bounding this driver's coverage. PERFECT and
	## MASH differ in how well they press and agree completely on WHAT to choose — both take the
	## Attack row every single turn — so magic was outside anything the balance gate could
	## observe: every spell, every status a spell inflicts and every element pairing had never
	## been played by a gate at all. A fixed choice bounds coverage exactly the way a fixed skill
	## does, and this is the second half of that.
	##
	## It ROTATES through what it can afford rather than casting the best thing, because a driver
	## that always picks the strongest spell exercises exactly one row of the page — which is the
	## same blindness one level down. The rotation is a counter, not a draw: nothing here may
	## reach for randomness the fight has not seeded.
	CASTER,
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
	## Every spell this fight actually cast, by id and in order. COUNTED rather than inferred,
	## for the reason `blows` is: a caster that wins having only ever cast the first row of the
	## page has exercised one spell and reported on all of them.
	var casts: Array[StringName] = []
	## Every distinct line the fight SAID, in order.
	##
	## This is how an element pairing is observed, and it is deliberately the caption rather than
	## the aim: a spell that reaches everything never opens the foe cursor, and neither does one
	## aimed at the last foe standing, so a driver that recorded what it pointed at would miss
	## exactly the casts that need no pointing. The caption is also what the PLAYER gets, which
	## makes it the outcome rather than a proxy for it.
	var said: Array[String] = []

	## How many casts have happened, which is also the rotation's position on the spell page.
	func cast_count() -> int:
		return casts.size()

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
		# Read every iteration rather than in the MESSAGE branch: a line can be set and replaced
		# without the phase changing, and a caption nobody recorded is an outcome nobody can
		# assert. Deduped against the last one only, so a line repeated later still registers.
		var spoken := logic.message()
		if not spoken.is_empty() and (out.said.is_empty() or out.said[-1] != spoken):
			out.said.append(spoken)
		if phase != was:
			if phase == BattleLogic.Phase.PLAYER_ACT:
				out.swings += 1
			elif phase == BattleLogic.Phase.ENEMY_ACT:
				out.blows += 1
			was = phase
		match phase:
			BattleLogic.Phase.MENU:
				# MAGIC only when something on the page can actually be paid for. The menu is the
				# ONLY place that decision can be made: a cancel is refused for everybody since
				# M27.1, so a driver that opened the spell page with nothing affordable would
				# press an unaffordable row forever and hang the gate rather than fail it.
				_aim(logic, BattleLogic.Row.MAGIC if _will_cast(logic, policy)
					else BattleLogic.Row.ATTACK)
				logic.press()
				out.presses += 1
			BattleLogic.Phase.SPELLS when policy == Policy.CASTER:
				var row := _spell_to_cast(logic, out.cast_count())
				# Recorded BEFORE the press, because the press is what spends the turn and the
				# page is gone by the time it returns.
				out.casts.append(row.id)
				_aim(logic, _row_of_spell(logic, row))
				logic.press()
				out.presses += 1
			BattleLogic.Phase.ALLY when policy == Policy.CASTER:
				# A heal or a boost, landing on our side. The most hurt member, which is both the
				# sensible play and the one that makes a heal observable at all.
				_aim(logic, _neediest_row(logic))
				logic.press()
				out.presses += 1
			BattleLogic.Phase.FOE:
				# The two aiming policies point OPPOSITE WAYS, deliberately. PERFECT finishes off
				# whatever is closest to falling, because fewer bodies is fewer blows per round.
				# CASTER spends its scarce magic on whatever will take longest to kill, which is
				# at least as sensible a play - and, being the opposite order, it reaches foes
				# PERFECT only ever arrives at once the fight is already decided.
				#
				# That is not a detail. Aim is a policy axis exactly the way skill is: with both
				# drivers finishing the weakest first, a boss standing behind two mooks is never
				# the target of anything while resources last, so every rule that only shows up
				# when you hit the BIG one is unobserved by a suite that looks exhaustive.
				match policy:
					Policy.PERFECT:
						_aim(logic, _weakest_row(logic))
					Policy.CASTER:
						_aim(logic, _toughest_row(logic))
					_:
						pass
				logic.press()
				out.presses += 1
			BattleLogic.Phase.SPELLS, BattleLogic.Phase.ITEMS, BattleLogic.Phase.ALLY:
				# PERFECT and MASH only ever choose Attack, so nothing should open these. Reaching
				# one means the command rows moved under them, and a driver that quietly pressed
				# through would be casting or drinking while reporting on swinging. ITEMS is here
				# for CASTER too: casting is the one verb it adds.
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


## Whether this policy is going to open the spell page, asked at the MENU where it still can be.
##
## Both halves matter. A page with no affordable row is a trap rather than a choice - the confirm
## says "Not enough magic" and stays put - and a page with no rows at all has one row that is a
## statement rather than a button, which the confirm refuses in the same way.
static func _will_cast(logic: BattleLogic, policy: Policy) -> bool:
	if policy != Policy.CASTER:
		return false
	for row: BattleLogic.SpellRow in logic.spell_rows():
		if logic.can_afford(row):
			return true
	return false


## Which spell to cast, ROTATED by how many have been cast already.
##
## A driver that always casts the strongest row exercises exactly one spell and reports on the
## whole page, which is the same blindness the CASTER policy exists to fix one level up. The
## rotation walks the affordable rows in page order, so over a fight every spell the member can
## pay for gets used - and it is a counter rather than a draw, because nothing in a replayed
## fight may reach for randomness the fight has not seeded.
static func _spell_to_cast(logic: BattleLogic, cast_count: int) -> BattleLogic.SpellRow:
	var affordable: Array = []
	for row: BattleLogic.SpellRow in logic.spell_rows():
		if logic.can_afford(row):
			affordable.append(row)
	# `_will_cast` is what guarantees this is non-empty, and it is checked at the MENU one press
	# earlier. Asserting it here rather than returning null: a null would be pressed at an
	# unaffordable row forever, which hangs the gate instead of failing it.
	assert(not affordable.is_empty(), "the spell page opened with nothing affordable on it")
	return affordable[cast_count % affordable.size()]


## Where `row` sits on the page the cursor is actually walking - which is every spell the member
## knows, not just the affordable ones. Looked up rather than counted, because the two lists
## differ the moment the pool runs low and an index into the wrong one casts a different spell.
static func _row_of_spell(logic: BattleLogic, row: BattleLogic.SpellRow) -> int:
	var rows := logic.spell_rows()
	for i in rows.size():
		if rows[i] == row:
			return i
	return 0


## The ROW of the standing member furthest from full. A row, not a member index: the ally cursor
## counts over the standing, so the two diverge the moment anybody falls.
static func _neediest_row(logic: BattleLogic) -> int:
	var rows := logic.ally_rows()
	var best := 0
	for i in rows.size():
		var gap := logic.member_max_hp(rows[i]) - logic.member_hp(rows[i])
		if gap > logic.member_max_hp(rows[best]) - logic.member_hp(rows[best]):
			best = i
	return best


## The ROW of the living foe with the least health left. A row, not a foe index: the cursor
## counts over the living, so the two diverge the moment anything falls.
static func _weakest_row(logic: BattleLogic) -> int:
	var rows := logic.foe_rows()
	var best := 0
	for i in rows.size():
		if logic.enemy_hp(rows[i]) < logic.enemy_hp(rows[best]):
			best = i
	return best


## The ROW of the living foe with the MOST health left - `_weakest_row`'s mirror, and the whole
## of the aim axis. Written out rather than folded into one function with a sign, because a
## comparison whose direction is a parameter is one every reader has to decode, which is the
## same argument `SpellDef` makes for BOOST and SAP being two kinds rather than one signed power.
static func _toughest_row(logic: BattleLogic) -> int:
	var rows := logic.foe_rows()
	var best := 0
	for i in rows.size():
		if logic.enemy_hp(rows[i]) > logic.enemy_hp(rows[best]):
			best = i
	return best
