class_name GridWalker
extends RefCounted
## One actor's grid step: which cell it is walking to, and whether it got there.
##
## Pure, like Locomotion, and for the same reason: everything that decides whether stepping
## feels right - what a diagonal against a wall does, where an interrupted step leaves you,
## whether a tap buys a whole tile - is decided here, and can be pinned with no scene tree.
## The node contributes move_and_slide and the answer to one question, "would moving by this
## hit anything", and nothing else.
##
## There is no clock in here and no delta, deliberately. move_and_slide multiplies velocity by
## a delta this class cannot see - the engine picks the physics one or the idle one depending
## on where the call came from, which tests/unit/test_engine_assumptions.gd pins - so a step
## that tried to land by predicting that number would overshoot in exactly the hand-driven
## loop the integration tests use. A step ends when its target stops being AHEAD, which is a
## fact about position and needs no clock at all.
##
## The cost of that is honest: a step's duration quantises to whole frames, so a cell takes up
## to one frame longer than the speed implies. That is invisible and consistent. A mispredicted
## landing would be neither.

## How much closer a frame must get before it counts as progress, in pixels. An engineering
## tolerance rather than a feel number - there is nothing here to tune.
const PROGRESS_EPSILON := 0.01

var _config: GameConfig
var _stepping := false
var _origin := Vector2.ZERO
var _target := Vector2.ZERO
var _heading := Vector2.ZERO
## How far the target was at the START of this frame, so settle() can tell whether the frame
## got anywhere.
var _planned := 0.0


func _init(config_value: GameConfig) -> void:
	_config = config_value


func stepping() -> bool:
	return _stepping


## Throws a step away without moving anything. For a teleport, where resolving it would
## resolve it against a cell in the map being left.
func cancel() -> void:
	_stepping = false


## This frame's velocity, facing and pose, in the shape free movement returns, so whatever
## applies it cannot tell the two modes apart.
##
## `is_free` is handed a motion vector and answers whether the actor could move by it. It is
## called at most three times, and only when a new step is being latched.
func plan(input: Vector2, at: Vector2, facing_now: int, is_free: Callable) -> Locomotion.Step:
	# The direction comes from Locomotion rather than being worked out again here, so
	# allow_diagonal and the tie rule have exactly one implementation between the two modes.
	var free := Locomotion.step(input, facing_now, _config)
	if not _stepping:
		_latch(free.velocity, at, is_free)
	if not _stepping:
		# Either nothing is pressed, or everything the press asked for is blocked. Both look
		# the same from outside: the actor turns to look, and does not leave its cell.
		return Locomotion.Step.new(Vector2.ZERO, free.facing, &"idle")

	var residual := _target - at
	_planned = residual.length()
	var pace := _heading.normalized() * _speed()
	var velocity := Vector2.ZERO
	# Each axis runs at its own share of the speed and stops the moment IT arrives. A single
	# velocity re-aimed at the corner every frame would be wrong for a diagonal whose x is
	# walled: as the x residual stopped shrinking, the y component would shrink with it and
	# approach its centre without ever reaching it.
	if residual.x * pace.x > 0.0:
		velocity.x = pace.x
	if residual.y * pace.y > 0.0:
		velocity.y = pace.y
	# The pose is "a step is in flight", not a velocity magnitude. That makes the standing
	# animation during a slide impossible by construction rather than by staying above a
	# threshold - and the facing follows the step rather than the keys, so a direction pressed
	# halfway through is a request for the NEXT step. Turning early would let the player talk
	# to something they are walking away from.
	return Locomotion.Step.new(velocity, Dir.facing_from_vector(residual, facing_now), &"walk")


## Where the actor should be, given where move_and_slide actually left it. Returns `at`
## unchanged for every frame of a step but its last.
func settle(at: Vector2) -> Vector2:
	if not _stepping:
		return at
	var residual := _target - at
	if residual.dot(_heading) <= 0.0:
		# The target is no longer ahead: this frame reached it, or went a fraction of a pixel
		# past. Landing gives that fraction back, backwards, along ground walked a millisecond
		# ago - it is not a way of moving, it is a way of stopping.
		_stepping = false
		return _target
	if residual.length() > _planned - PROGRESS_EPSILON:
		# A whole frame that got no closer: something is in the way that was not there when
		# the step was latched, or was not built yet.
		return abandon(at)
	return at


## Gives up on the step in flight and says where that leaves the actor.
##
## Each axis is settled on its own. An axis that reached its destination keeps it - that is
## the diagonal whose x was walled and whose y went through, landing on the centre of the cell
## it slid into. An axis that did not goes back where it started, which is the one position on
## that axis known to be free: the actor stood on it a fifth of a second ago. Nothing is ever
## settled FORWARD, into whatever it was that stopped us.
##
## Every combination of those is a cell centre, because both _origin and _target are - so the
## actor is on a centre whenever no step is in flight. That is the invariant the mode rests on.
func abandon(at: Vector2) -> Vector2:
	if not _stepping:
		return at
	_stepping = false
	var out := _origin
	# "Reached" means at or past, not within a hair of: an axis is stopped by a frame boundary,
	# which lands it a fraction beyond the centre as readily as on it.
	if (_target.x - at.x) * _heading.x <= 0.0:
		out.x = _target.x
	if (_target.y - at.y) * _heading.y <= 0.0:
		out.y = _target.y
	return out


func _latch(free_velocity: Vector2, at: Vector2, is_free: Callable) -> void:
	var want := Vector2i(_axis_of(free_velocity.x), _axis_of(free_velocity.y))
	if want == Vector2i.ZERO:
		return
	var origin := _centre_of(at)
	var tries: Array[Vector2i] = [want]
	if want.x != 0 and want.y != 0:
		# The whole press first, then each axis alone. A diagonal whose x is walled still takes
		# its y - which is what move_and_slide does for free movement, and a grid mode that
		# stopped dead beside a wall would read as broken rather than as a style. Horizontal is
		# tried first because a keyboard diagonal is a perfect tie, and every tie here goes
		# horizontal, the same way Dir breaks one.
		tries.append(Vector2i(want.x, 0))
		tries.append(Vector2i(0, want.y))
	for cell: Vector2i in tries:
		var to := origin + Vector2(cell) * float(_config.grid_step_px())
		if not bool(is_free.call(to - at)):
			continue
		_origin = origin
		_target = to
		_heading = to - at
		_stepping = true
		return


## A grid step is all or nothing: any deflection buys a whole cell, so a gamepad held gently
## walks a tile rather than a tenth of one. What stops a stick resting a degree off north from
## asking for a diagonal is the input map's own deadzone, where every other deadzone lives.
static func _axis_of(v: float) -> int:
	if is_zero_approx(v):
		return 0
	return 1 if v > 0.0 else -1


## The centre of the cell a position stands in, asked of MapData rather than recomputed, so the
## walker and world_to_tile can never disagree about which cell that is.
func _centre_of(at: Vector2) -> Vector2:
	var g := _config.grid_step_px()
	return MapData.tile_to_world(MapData.world_to_tile(at, g), g)


## Pixels per second while a step is in progress. A DIAGONAL keeps this speed and so takes
## 1.41x as long, covering 22.6px instead of 16 - the same trade free movement makes, and the
## alternative is the 41%-faster diagonal Locomotion exists to prevent.
func _speed() -> float:
	if _config.grid_step_seconds > 0.0:
		return float(_config.grid_step_px()) / _config.grid_step_seconds
	return _config.walk_speed_px()
