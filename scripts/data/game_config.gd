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

## Camera pixels per second toward the player. Zero snaps. Any smoothing at all fights pixel
## snapping, so this is deliberately off by default.
@export var camera_smoothing: float = 0.0


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
	return out
