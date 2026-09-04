class_name GameConfig
extends Resource
## The numbers a designer tunes, in one file, with nothing else in it.
##
## A literal in a script that a designer would want to change is a bug: it means the answer
## to "is the walk too slow?" lives in code review rather than in a text field. Everything
## here is something you would plausibly want to try three values of.

@export var id: StringName = &"default"

## TILES per second. Three is fast enough not to drag, slow enough that a tile still reads as a
## unit of distance - and stated in tiles it is that speed at ANY art size. As 48 pixels it was
## three tiles a second only at 16px, and a 32px game had to write 96 by hand with nothing to
## say when that had drifted.
@export var walk_tiles_per_second: float = 3.0

## When false, the player moves on one axis at a time (the pure four-direction feel of the
## earliest top-down RPGs). When true, diagonals are allowed and normalised so they are not
## faster than a straight line - the classic bug in every hand-rolled movement system.
@export var allow_diagonal: bool = true

## How far in front of the character an interaction reaches, in TILES. Three quarters of one:
## past the body, so standing next to something is enough and standing near it is not.
@export var interact_reach_tiles: float = 0.75

## The player's collision box, in TILES, centred on the feet rather than the body. A top-down
## character collides with the FLOOR they stand on: a box the size of the sprite would stop the
## head against a wall the feet are nowhere near.
@export var body_tiles: Vector2 = Vector2(0.625, 0.375)

## Speed below which the character is considered standing still, in TILES per second. Without a
## threshold, floating-point drift keeps the walk animation twitching after the keys are
## released - and the threshold has to scale with the art, because at 32px a body covers twice
## the pixels per frame that the same walk covered at 16.
@export var idle_tiles_per_second: float = 0.0625

## False is free movement: the character slides a pixel at a time wherever the keys point. True
## and a press buys exactly ONE TILE - the stiffer, more deterministic feel of the earliest
## top-down RPGs, where a trigger tile is either stood on or it is not.
##
## A flag, which it could not be while this config was in pixels. The argument then was that a
## flag "would still need the tile size from somewhere: an actor holds this config and never the
## map's SpriteStyle" - so the field carried the DISTANCE and GameManifest cross-checked it
## against the map, because a step that is not a tile lands the player between tiles forever.
## A config bound by at() already knows its tile size, so that step is now unrepresentable
## rather than refused, and the cross-check went with it.
@export var grid_step: bool = false

## How long one grid step takes, in seconds. Zero derives it from walk_tiles_per_second, so both
## movement modes cross a tile at the same rate unless you say otherwise - the same "zero means
## off" shape camera_tiles_per_second uses. A diagonal keeps the speed and so takes 1.41x this,
## because it covers 1.41 tiles rather than one.
##
## Seconds rather than tiles because it is a DURATION: it is already independent of the art.
@export var grid_step_seconds: float = 0.0

## Camera TILES per second toward the player. Zero snaps. Any smoothing at all fights pixel
## snapping, so this is deliberately off by default.
##
## Godot's Camera2D.position_smoothing_speed is itself in pixels per second (checked against the
## 4.7 docs, not remembered), so camera_speed_px() is what reaches it - this is the one value
## that converts BACK to pixels to feed an engine property rather than our own arithmetic.
@export var camera_tiles_per_second: float = 0.0

## How far the player walks between footsteps, in TILES. Zero switches them off - a mode rather
## than a magic number, so a game that wants silent feet says so in data instead of in code.
##
## A cadence, not a timer: tying it to distance means it slows when the player slows and stops
## when a wall stops them, which is what a footstep is.
@export var footstep_tiles: float = 0.875

## How many save slots the pause menu offers. One is a perfectly good answer - it makes the
## menu a single "continue" - which is why this is a number a designer sets rather than a
## constant in the view.
##
## Bounded ABOVE as well, and that bound is not decoration: two screens draw one row per slot
## down a 180px window, so a big enough number walks the last rows off the bottom of it. At 16
## both the pause menu's slot page and the save point do exactly that, silently, with every
## other gate green - the MAX_PARTY/MAX_FOES shape, where a view declares a capacity, the
## layout audit measures at it, and this refuses data past it.
@export var save_slots: int = 3

## The most slots either slot-drawing screen can lay out. Twelve rather than the fifteen that
## measurably still fits: every reference game offers one or three (Final Fantasy I and Pokemon
## have a single file; Dragon Quest, EarthBound and Chrono Trigger have three), so the ceiling
## is nowhere near a real game's need and the headroom means a font or padding change cannot
## quietly push the last row off the screen.
const MAX_SAVE_SLOTS := 12

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


## The tile size this config is bound to, in pixels. Zero means UNBOUND - nothing has told it how
## big a tile is yet - and every _px() accessor below says so out loud rather than guessing
## quietly. Not exported, because it is not a designer's number: it belongs to the running map,
## and at() sets it explicitly rather than trusting whatever duplicate() carries.
var _tile_size: int = 0


## This config, bound to a tile size. A DUPLICATE, so the shipped resource stays as authored and
## nothing can bind the same object to two scales.
##
## This is the whole reason the pure classes stay pure. Locomotion, GridWalker, Interactor and
## ActorBody have no tile size and must not acquire one - two of their suites advertise "no scene
## at all" as the point, and reaching for an autoload would end that. Binding the size INTO the
## config an actor already holds changes no signature and costs no purity: the config arrives
## already knowing its own scale.
func at(tile_size: int) -> GameConfig:
	var bound := duplicate() as GameConfig
	bound._tile_size = maxi(tile_size, 1)
	return bound


## How many pixels a tile is, and the complaint when nothing has said. Asking an unbound config
## for a distance is a bug in the CALLER - the world binds on entering every map - so this is
## loud and then answers as if 16, the size the defaults above were written against. A fallback
## that fires is a real fault here, never a mode.
func _tiles() -> float:
	if _tile_size <= 0:
		push_error("GameConfig '%s' was asked for a distance before at() bound it to a tile" % id)
		return 16.0
	return float(_tile_size)


func walk_speed_px() -> float:
	return walk_tiles_per_second * _tiles()


func interact_reach_px() -> float:
	return interact_reach_tiles * _tiles()


func body_size_px() -> Vector2:
	return body_tiles * _tiles()


func idle_epsilon_px() -> float:
	return idle_tiles_per_second * _tiles()


func footstep_px() -> float:
	return footstep_tiles * _tiles()


func camera_speed_px() -> float:
	return camera_tiles_per_second * _tiles()


## Exactly one tile when grid stepping is on, zero when it is off - the same "zero is off" answer
## GridWalker and ActorBody already branch on, which is why neither of them changed shape.
func grid_step_px() -> int:
	return int(_tiles()) if grid_step else 0


func problems() -> Array[String]:
	var out: Array[String] = []
	if walk_tiles_per_second <= 0.0:
		out.append("walk_tiles_per_second must be positive, got %f" % walk_tiles_per_second)
	if interact_reach_tiles <= 0.0:
		out.append("interact_reach_tiles must be positive, got %f" % interact_reach_tiles)
	if body_tiles.x <= 0.0 or body_tiles.y <= 0.0:
		out.append("body_tiles must be positive, got %s" % body_tiles)
	if idle_tiles_per_second < 0.0:
		out.append("idle_tiles_per_second cannot be negative, got %f" % idle_tiles_per_second)
	if footstep_tiles < 0.0:
		out.append("footstep_tiles cannot be negative, got %f" % footstep_tiles)
	if grid_step_seconds < 0.0:
		out.append("grid_step_seconds cannot be negative, got %f" % grid_step_seconds)
	if save_slots < 1:
		out.append("save_slots must be at least 1, got %d" % save_slots)
	if save_slots > MAX_SAVE_SLOTS:
		out.append("save_slots must be at most %d (the rows a slot list can draw), got %d"
			% [MAX_SAVE_SLOTS, save_slots])
	if not SAVE_POLICIES.has(save_policy):
		out.append("save_policy must be one of %s, got '%s'" % [SAVE_POLICIES, save_policy])
	if rest_fade_frames < 1:
		out.append("rest_fade_frames must be at least 1, got %d" % rest_fade_frames)
	if rest_hold_frames < 1:
		out.append("rest_hold_frames must be at least 1, got %d" % rest_hold_frames)
	return out
