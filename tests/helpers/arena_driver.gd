class_name ArenaDriver
extends RefCounted
## Plays an arena to its end, so a claim about a sword fight is made OF the fight - BattleDriver's
## twin, and for its reason: ArenaSim is pure and has no clock, so a whole fight is a loop on every
## seed with no scene.
##
## TWO POLICIES, AND BOTH ARE LOAD-BEARING. PERFECT lines up, swings when the blade will land, waits
## out a foe's flash at arm's length and steps away from anything about to touch it; CHARGE walks
## straight at the nearest foe and swings on every frame it can. A shipped fight PERFECT loses is a
## wall, and one CHARGE wins has no skill in it.
##
## Every choice is read from the sim's own probes. The scripted harness plays PERFECT too and cannot
## name this class - tests/ is not in the exported pack - so the choice is kept small enough to
## state twice, and a suite holds the two to one answer.

enum Policy { PERFECT, CHARGE }

## Units of slack in lining up: inside it, the cross axis counts as lined up.
const ALIGN := 24
## How close CHARGE lets a foe's body get to its own before it swings: a quarter of a tile. Any
## further and it roots itself out of reach - a swing holds the player still - which is not
## charging but standing.
const CHARGE_RANGE := 64


class Choice extends RefCounted:
	var move := Vector2.ZERO
	var swing := false


## What a played arena looks like from outside, COUNTED rather than inferred: a win that never
## swung, or a charge that was never touched, is a fight that ended right for the wrong reason.
class Report extends RefCounted:
	var outcome: BattleLogic.Outcome = BattleLogic.Outcome.NONE
	var ended := false
	var frames := 0
	var swings := 0
	var hits := 0
	var touches := 0
	var leader_hp := 0


## This frame's input for `policy`.
static func choose(sim: ArenaSim, policy: Policy) -> Choice:
	var out := Choice.new()
	var target := sim.nearest_standing()
	if target < 0:
		return out
	var gap := sim.foe_pos(target) - sim.player_pos()
	if policy == Policy.CHARGE:
		# Straight at it, diagonal and all, and swinging whenever it is close - facing it or not,
		# flashing or not.
		out.move = Vector2(signi(gap.x), signi(gap.y))
		out.swing = sim.player_box().grow(CHARGE_RANGE).intersects(sim.foe_box(target))
		return out
	if sim.shoved():
		return out
	if sim.sword_reaches(target):
		if not sim.swinging() and sim.foe_hurt(target) == 0:
			out.swing = true
		return out
	if sim.swinging():
		return out
	var danger := sim.threat()
	if danger >= 0 and sim.player_hurt() == 0:
		out.move = Vector2(_dominant(sim.player_pos() - sim.foe_pos(danger)))
		return out
	out.move = Vector2(_approach(gap))
	return out


## Plays `sim` to the end, or to `cap` frames. A loop bounded only by "until the fight says stop"
## hangs instead of failing, so `ended` says whether it really finished and every caller asserts it.
static func play(sim: ArenaSim, policy: Policy, cap := 20000) -> Report:
	var out := Report.new()
	while out.frames < cap and not sim.finished():
		var choice := choose(sim, policy)
		sim.tick(choice.move, choice.swing)
		out.frames += 1
	out.ended = sim.finished()
	out.outcome = sim.outcome()
	out.swings = sim.swings()
	out.hits = sim.hits()
	out.touches = sim.touches()
	out.leader_hp = sim.leader_hp()
	return out


## Along the larger axis only, ties sideways.
static func _dominant(delta: Vector2i) -> Vector2i:
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## Lines up the cross axis first and closes on the main one last, so the player arrives FACING what
## they walked to.
static func _approach(gap: Vector2i) -> Vector2i:
	if absi(gap.x) >= absi(gap.y):
		if absi(gap.y) > ALIGN:
			return Vector2i(0, signi(gap.y))
		return Vector2i(signi(gap.x), 0)
	if absi(gap.x) > ALIGN:
		return Vector2i(signi(gap.x), 0)
	return Vector2i(0, signi(gap.y))
