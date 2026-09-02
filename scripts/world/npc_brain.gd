class_name NpcBrain
extends RefCounted
## What an NPC wants to do this frame. No nodes, no clock, no randomness of its own.
##
## The sibling of GridWalker: it is handed one frame at a time and answers with an intent
## vector - the same axis pair a keyboard produces and `Locomotion.step` consumes - so a
## walking NPC goes through exactly the code the player does. That is the whole reason
## `ActorBody` exists as one class: the player and every NPC "differ only in what drives
## them", and this is the other driver.
##
## It has NO delta and no timer. Dwelling counts FRAMES, because the world is stepped at a
## fixed rate by the gate and a wall-clock dwell would make a scripted play session depend
## on how busy the machine is - the class of bug this project keeps out of its tests.
##
## Every draw comes from a SeededRng derived from stable identifiers (game, map, npc id),
## never from a clock. Before this file the world had no per-frame randomness at all; keeping
## it reproducible is what lets a play session assert an NPC's position hundreds of frames in.

## What a map's `behavior` field may say. STATIC is the default and the shipped answer: an
## NPC that stands still is a wall the player can talk to, and several QA sessions lean on
## exactly that.
enum Kind { STATIC, WANDER, PATROL }

const NAMES: Dictionary = {
	"static": Kind.STATIC,
	"wander": Kind.WANDER,
	"patrol": Kind.PATROL,
}

## How close to a target counts as arrived, as a fraction of a tile. Generous on purpose: free
## movement approaches a point asymptotically and a tight epsilon would leave an NPC shuffling
## forever a third of a pixel away. Grid movement snaps, so it never gets near this.
##
## Per TILE rather than in pixels, because what "close" means is set by how far a body travels
## in a frame, and that doubles with the world: at 32px tiles a flat 1.5px is under two frames
## of walking, which is exactly the shuffle this margin exists to prevent. Both numbers are
## exact in binary, so at a 16px tile this is still precisely the 1.5 every shipped session was
## recorded against.
const ARRIVE_EPSILON_PER_TILE := 1.5 / 16.0

## A frame that moved less than this, while walking, means something is in the way - the
## player, another NPC, a wall the map author did not expect. Read the same way GridWalker
## reads a stalled step, rather than by asking the physics engine anything.
const PROGRESS_EPSILON := 0.05

## Frames of not-getting-anywhere before the target is abandoned. Not one frame: a body
## squeezing past another legitimately makes no progress for a moment.
const STUCK_FRAMES := 12


## How close counts as arrived, in this map's pixels.
func _arrive_epsilon() -> float:
	return ARRIVE_EPSILON_PER_TILE * float(_tile_size)


static func kind_from_name(raw: String) -> int:
	return NAMES.get(raw, -1)


static func is_mover(kind: Kind) -> bool:
	return kind != Kind.STATIC


var kind: Kind = Kind.STATIC

var _rng: SeededRng
var _tile_size: int = 16
## Where a wanderer is allowed to stray from, in world coordinates.
var _home: Vector2 = Vector2.ZERO
## Chebyshev radius in TILES. A map author thinks in tiles; only this class converts.
var _range: int = 1
## Authored waypoints in world coordinates, already converted at construction.
var _path: Array[Vector2] = []
var _loop: bool = true
var _dwell_min: int = 0
var _dwell_max: int = 0

var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _dwell_left: int = 0
var _index: int = 0
## Ping-pong direction. Only ever -1 or 1, and only consulted when `_loop` is false.
var _leg: int = 1
var _last_at: Vector2 = Vector2.ZERO
var _stalled: int = 0


## Builds the brain for one npc record. `at` is where the body was placed, which is a
## wanderer's home; `path` waypoints are TILE coordinates and are converted here so nothing
## downstream has to know which unit it is holding.
static func of(record: Dictionary, at: Vector2, tile_size: int, rng: SeededRng) -> NpcBrain:
	var brain := NpcBrain.new()
	brain.kind = kind_from_name(str(record.get("behavior", "static"))) as Kind
	brain._rng = rng
	brain._tile_size = maxi(tile_size, 1)
	brain._home = at
	brain._last_at = at
	brain._range = maxi(int(record.get("range", 2)), 1)
	brain._loop = bool(record.get("loop", true))
	# A dwell of zero is legal and means "never stop", which reads as a pacing guard rather
	# than an idler. The pair is clamped so an author who inverts it gets their own numbers
	# back rather than an empty range that would draw the same value forever.
	var lo := maxi(int(record.get("dwell_min", 30)), 0)
	var hi := maxi(int(record.get("dwell_max", 90)), lo)
	brain._dwell_min = lo
	brain._dwell_max = hi
	for raw: Variant in record.get("path", []):
		var pair := JsonFile.to_int_array(raw)
		if pair.size() == 2:
			brain._path.append(MapData.tile_to_world(Vector2i(pair[0], pair[1]), brain._tile_size))
	brain._dwell_left = brain._roll_dwell()
	return brain


## The axis pair this NPC wants this frame, in the same shape `Locomotion.read_input()`
## returns. Vector2.ZERO means "stand still", which is what a dwelling or STATIC npc answers.
##
## `at` is the body's CURRENT position, read after the last frame's move - so progress is
## measured from what actually happened rather than from what was asked for. That is the only
## way a blocked NPC can notice it is blocked without asking the physics engine anything.
func intent(at: Vector2) -> Vector2:
	if _dwell_left > 0:
		_dwell_left -= 1
		_last_at = at
		return Vector2.ZERO

	if not _has_target:
		_choose(at)
		_last_at = at
		if not _has_target:
			# Nowhere to go - a patrol with no path, or a wander that drew its own tile.
			# Dwell rather than retry every frame, or a bad record becomes a busy loop.
			_dwell_left = _roll_dwell()
			return Vector2.ZERO

	var to_target := _target - at
	if to_target.length() <= _arrive_epsilon():
		_arrive(at)
		return Vector2.ZERO

	# Blocked: the last frame asked to move and the body did not. Give up on this target and
	# stand for a moment, so two NPCs meeting in a corridor do not shove each other forever.
	if at.distance_to(_last_at) < PROGRESS_EPSILON:
		_stalled += 1
		if _stalled >= STUCK_FRAMES:
			_abandon()
			return Vector2.ZERO
	else:
		_stalled = 0
	_last_at = at

	# Normalised, not the raw delta: Locomotion multiplies by walk_speed and treats the input
	# as a direction. Handing it a 40-pixel vector would ask for 40x the speed.
	return to_target.normalized()


## Where this brain is currently headed, for tests and for anything that wants to draw it.
## Vector2.ZERO with no target is not a position - callers check `has_target()` first.
func target() -> Vector2:
	return _target


func has_target() -> bool:
	return _has_target


func dwelling() -> bool:
	return _dwell_left > 0


func _choose(at: Vector2) -> void:
	match kind:
		Kind.WANDER:
			_choose_wander(at)
		Kind.PATROL:
			_choose_patrol()
		_:
			# STATIC lands here, and this is the ONLY place that decides a static NPC does not
			# move. An early return in intent() used to say it a second time; a mutant proved
			# the duplicate changed nothing, which is exactly how a second source of truth
			# announces itself.
			_has_target = false


## A tile within `_range` of home, Chebyshev - so a range of 2 is the 5x5 block a map author
## can see when they count squares, not a circle they have to imagine.
func _choose_wander(at: Vector2) -> void:
	var home_tile := MapData.world_to_tile(_home, _tile_size)
	var here := MapData.world_to_tile(at, _tile_size)
	var options: Array[Vector2i] = []
	for dx in range(-_range, _range + 1):
		for dy in range(-_range, _range + 1):
			var t := home_tile + Vector2i(dx, dy)
			if t != here:
				options.append(t)
	if options.is_empty():
		_has_target = false
		return
	# shuffled() returns a copy and draws from the seeded stream, so the choice is stable for
	# a given npc across runs - never Array.pick_random, which the linter fails the build on.
	var pick: Vector2i = _rng.shuffled(options)[0]
	_target = MapData.tile_to_world(pick, _tile_size)
	_has_target = true
	_stalled = 0


func _choose_patrol() -> void:
	if _path.is_empty():
		_has_target = false
		return
	_index = clampi(_index, 0, _path.size() - 1)
	_target = _path[_index]
	_has_target = true
	_stalled = 0


## Arrived: stand for a while, then line up whatever comes next.
func _arrive(at: Vector2) -> void:
	_has_target = false
	_stalled = 0
	_last_at = at
	_dwell_left = _roll_dwell()
	if kind != Kind.PATROL or _path.size() < 2:
		return
	if _loop:
		_index = (_index + 1) % _path.size()
		return
	# Ping-pong. The turn happens at the ends, so a two-point path oscillates and a longer one
	# walks back down the way it came rather than teleporting to the far end.
	if _index + _leg < 0 or _index + _leg >= _path.size():
		_leg = -_leg
	_index += _leg


func _abandon() -> void:
	_has_target = false
	_stalled = 0
	_dwell_left = _roll_dwell()


func _roll_dwell() -> int:
	if _dwell_max <= 0:
		return 0
	return _rng.next_int(_dwell_min, _dwell_max)
