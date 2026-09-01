class_name GameConfig
extends Resource
## The numbers a designer tunes, in one file, with nothing else in it.
##
## A literal in a script that a designer would want to change is a bug: it means the answer
## to "is the walk too slow?" lives in code review rather than in a text field. Everything
## here is something you would plausibly want to try three values of.

@export var id: StringName = &"default"

## Pixels per second. At 16px tiles, 48 means three tiles a second - fast enough not to
## drag, slow enough that a tile still reads as a unit of distance.
@export var walk_speed: float = 48.0

## When false, the player moves on one axis at a time (the pure four-direction feel of the
## earliest top-down RPGs). When true, diagonals are allowed and normalised so they are not
## faster than a straight line - the classic bug in every hand-rolled movement system.
@export var allow_diagonal: bool = true

## How far in front of the character an interaction reaches, in pixels. Roughly half a tile
## past the body, so standing next to something is enough and standing near it is not.
@export var interact_reach: float = 12.0

## The player's collision box, in pixels, centred on the feet rather than the body. A
## top-down character collides with the FLOOR they stand on: a box the size of the sprite
## would stop the head against a wall the feet are nowhere near.
@export var body_size: Vector2 = Vector2(10.0, 6.0)

## Speed below which the character is considered standing still, in pixels per second.
## Without a threshold, floating-point drift keeps the walk animation twitching after the
## keys are released.
@export var idle_speed_epsilon: float = 1.0

## The distance one grid step covers, in pixels. Zero is off, and off is free movement: the
## character slides a pixel at a time wherever the keys point. Set it to the map's tile_size
## and a press buys exactly one tile - the stiffer, more deterministic feel of the earliest
## top-down RPGs, where a trigger tile is either stood on or it is not.
##
## It is the step DISTANCE rather than a mode flag because those are the same fact, and a flag
## would still need the tile size from somewhere: an actor holds this config and never the
## map's SpriteStyle. GameManifest.problems() checks the two agree.
@export var grid_step_pixels: int = 0

## How long one grid step takes, in seconds. Zero derives it from walk_speed, so both movement
## modes cross a tile at the same rate unless you say otherwise - the same "zero means off"
## shape camera_smoothing uses. A diagonal keeps the speed and so takes 1.41x this, because it
## covers 22.6px rather than 16.
@export var grid_step_seconds: float = 0.0

## Camera pixels per second toward the player. Zero snaps. Any smoothing at all fights pixel
## snapping, so this is deliberately off by default.
@export var camera_smoothing: float = 0.0

## How far the player walks between footsteps, in pixels. Zero switches them off, the same way
## grid_step_pixels at zero means free movement - a mode rather than a magic number, so a game
## that wants silent feet says so in data instead of in code.
##
## A cadence, not a timer: tying it to distance means it slows when the player slows and stops
## when a wall stops them, which is what a footstep is.
@export var footstep_pixels: float = 14.0

## How many save slots the pause menu offers. One is a perfectly good answer - it makes the
## menu a single "continue" - which is why this is a number a designer sets rather than a
## constant in the view.
@export var save_slots: int = 3

## WHERE the player may write a save, which the genre disagrees about loudly enough that a
## template cannot pick for every game built on it. "anywhere" is the pause menu's Save row
## (Pokemon's shape, and the default because it is what every session recorded before this
## field existed was playing); "at_point" removes that row and leaves the `open_save` dialog
## effect as the only way to write one - Dragon Quest's king, Final Fantasy's inn.
##
## It governs WRITING only. Loading stays a pause-and-title verb under both policies: a game
## that makes saving a journey does not also make quitting one.
##
## A StringName checked against a list rather than an enum, for the reason SpellDef.Kind is an
## enum and this is not: a .tres stores an enum as the bare int it was written as, so a third
## policy later would re-label every shipped config. A typo'd value FAILS THE BUILD here rather
## than falling back to a default - the npc `behavior` rule, and for its reason: a policy that
## silently reads as "anywhere" is a save point nobody can find and a Save row nobody removed.
@export var save_policy: StringName = SAVE_ANYWHERE

## The whole vocabulary, so the check below and anything that has to offer the choice - the
## scaffold wizard, a test - read the same list rather than three copies of it.
const SAVE_ANYWHERE := &"anywhere"
const SAVE_AT_POINT := &"at_point"
const SAVE_POLICIES: Array[StringName] = [SAVE_ANYWHERE, SAVE_AT_POINT]

## How long the night takes, in FRAMES rather than seconds - the clock every timed thing here
## counts on, so a rest lasts the same length on a slow machine as on a fast one. Split into
## the fade and the pause at full black because they are tuned against different things: the
## fade is how abrupt sleep feels, the hold is how long a night reads as.
@export var rest_fade_frames: int = 24
@export var rest_hold_frames: int = 30


func problems() -> Array[String]:
	var out: Array[String] = []
	if walk_speed <= 0.0:
		out.append("walk_speed must be positive, got %f" % walk_speed)
	if interact_reach <= 0.0:
		out.append("interact_reach must be positive, got %f" % interact_reach)
	if body_size.x <= 0.0 or body_size.y <= 0.0:
		out.append("body_size must be positive, got %s" % body_size)
	if idle_speed_epsilon < 0.0:
		out.append("idle_speed_epsilon cannot be negative, got %f" % idle_speed_epsilon)
	if grid_step_pixels < 0:
		out.append("grid_step_pixels cannot be negative, got %d" % grid_step_pixels)
	if footstep_pixels < 0.0:
		out.append("footstep_pixels cannot be negative, got %f" % footstep_pixels)
	if grid_step_seconds < 0.0:
		out.append("grid_step_seconds cannot be negative, got %f" % grid_step_seconds)
	if save_slots < 1:
		out.append("save_slots must be at least 1, got %d" % save_slots)
	if not SAVE_POLICIES.has(save_policy):
		out.append("save_policy must be one of %s, got '%s'" % [SAVE_POLICIES, save_policy])
	if rest_fade_frames < 1:
		out.append("rest_fade_frames must be at least 1, got %d" % rest_fade_frames)
	if rest_hold_frames < 1:
		out.append("rest_hold_frames must be at least 1, got %d" % rest_hold_frames)
	return out
