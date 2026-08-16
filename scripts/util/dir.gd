class_name Dir
extends RefCounted
## The one place a direction is named.
##
## Every sheet row, animation name, facing value and map legend entry in the project
## resolves through here. A generator that writes rows in one order and a game that reads
## them in another produces a character who walks left while facing up, and nothing errors
## - so the order below is the contract, and tests/unit/test_dir.gd pins it.
##
## External sprite sources (an AI generator, a downloaded pack) label directions with
## compass names. `from_name` accepts those aliases so an outside sheet can be described
## in its own vocabulary and still land in canonical rows.

enum D { DOWN, LEFT, RIGHT, UP }

## Canonical row order, top to bottom, in every sheet this project reads or writes.
const ALL: Array[D] = [D.DOWN, D.LEFT, D.RIGHT, D.UP]

const NAMES: Dictionary = {
	D.DOWN: &"down",
	D.LEFT: &"left",
	D.RIGHT: &"right",
	D.UP: &"up",
}

## Compass and shorthand spellings other tools use for the same four directions.
const ALIASES: Dictionary = {
	"down": D.DOWN, "south": D.DOWN, "s": D.DOWN, "front": D.DOWN,
	"left": D.LEFT, "west": D.LEFT, "w": D.LEFT,
	"right": D.RIGHT, "east": D.RIGHT, "e": D.RIGHT,
	"up": D.UP, "north": D.UP, "n": D.UP, "back": D.UP,
}

## The three drawn views. LEFT is RIGHT mirrored when the style allows it, so the rig
## authors one side only.
enum View { FRONT, SIDE, BACK }


static func name_of(d: D) -> StringName:
	return NAMES[d]


## Returns -1 for anything unrecognised. Callers decide whether that is a hard error;
## returning DOWN as a "safe default" would silently file every unknown row as front-facing.
static func from_name(raw: String) -> int:
	var key := raw.strip_edges().to_lower()
	if not ALIASES.has(key):
		return -1
	return ALIASES[key]


static func view_of(d: D) -> View:
	match d:
		D.UP:
			return View.BACK
		D.LEFT, D.RIGHT:
			return View.SIDE
		_:
			return View.FRONT


static func view_name(v: View) -> StringName:
	match v:
		View.BACK:
			return &"back"
		View.SIDE:
			return &"side"
		_:
			return &"front"


## The unit step for a direction in screen space (y grows downward).
static func vector_of(d: D) -> Vector2:
	match d:
		D.DOWN:
			return Vector2(0.0, 1.0)
		D.LEFT:
			return Vector2(-1.0, 0.0)
		D.RIGHT:
			return Vector2(1.0, 0.0)
		_:
			return Vector2(0.0, -1.0)


## Facing from a movement vector. A tie between the axes resolves horizontally: a player
## holding two keys at 45 degrees reads as sideways, which is the pose with the most
## readable silhouette. The rule lives here, not in the movement code, so the locomotion
## test and the animation both quote one source.
static func facing_from_vector(v: Vector2, fallback: D) -> D:
	if is_zero_approx(v.x) and is_zero_approx(v.y):
		return fallback
	if absf(v.x) >= absf(v.y):
		return D.RIGHT if v.x > 0.0 else D.LEFT
	return D.DOWN if v.y > 0.0 else D.UP


## Animation names are "<clip>_<direction>": walk_down, idle_up. SpriteFrames keys and
## AnimatedSprite2D.play() both take these, so building the string in one function keeps a
## typo from becoming a silently missing animation.
static func anim_name(clip: StringName, d: D) -> StringName:
	return StringName("%s_%s" % [clip, NAMES[d]])
