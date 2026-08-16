class_name ActorBody
extends CharacterBody2D
## A character that stands on the floor, collides with walls, and animates accordingly.
##
## Shared by the player and every NPC, because they differ only in what drives them: the
## player reads the keyboard, an NPC reads its own behaviour, and both hand the result to
## the same `apply` below. Two separate implementations of "move and pick an animation" is
## how a fix to one silently misses the other.
##
## The collision box is the FEET, not the sprite. A top-down character occupies the floor it
## stands on: a box the size of the drawing would stop its head against a wall the feet are
## nowhere near, and would make it impossible to walk along the bottom edge of anything.

var view := SpriteView.new()
var config: GameConfig
var facing: int = Dir.D.DOWN

var _shape := CollisionShape2D.new()


func _ready() -> void:
	if view.get_parent() == null:
		add_child(view)
	if _shape.get_parent() == null:
		add_child(_shape)
	_apply_shape()


func setup(config_value: GameConfig, source: SpriteSource, character_id: StringName) -> bool:
	config = config_value
	if view.get_parent() == null:
		add_child(view)
	if _shape.get_parent() == null:
		add_child(_shape)
	_apply_shape()
	return view.apply_source(source, character_id)


func _apply_shape() -> void:
	if config == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = config.body_size
	_shape.shape = rect
	# The box sits just ABOVE the origin, because the origin is the feet: centring it on the
	# origin would put half the collider below the floor line the character stands on.
	_shape.position = Vector2(0.0, -config.body_size.y / 2.0)


## One step of movement from an input vector. Returns the Locomotion step so a caller can
## see what was decided without recomputing it.
func apply(input: Vector2) -> Locomotion.Step:
	var step := Locomotion.step(input, facing, config)
	facing = step.facing
	velocity = step.velocity
	move_and_slide()
	view.set_pose(step.clip, step.facing)
	return step


## Where this actor's interaction reaches, in world coordinates.
func interact_point() -> Vector2:
	return Locomotion.interact_point(global_position, facing, config)


func tile(tile_size: int) -> Vector2i:
	return MapData.world_to_tile(global_position, tile_size)


## Stops dead and faces a direction. Used when control is taken away - a dialog opening, a
## map transition - so the character does not slide on through the frames where nobody is
## driving it.
func halt(new_facing: int = -1) -> void:
	velocity = Vector2.ZERO
	if new_facing >= 0:
		facing = new_facing
	view.set_pose(&"idle", facing)
