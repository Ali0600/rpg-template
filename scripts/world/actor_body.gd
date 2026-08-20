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
## Counts ground covered so something upstairs can put a footstep on it. Null when the config
## asks for no footsteps at all.
var _meter: StepMeter = null

## Built by setup() when the config asks for grid movement, null otherwise. Null IS free
## movement - there is no mode flag to keep in sync with it.
var _walker: GridWalker


func _ready() -> void:
	if view.get_parent() == null:
		add_child(view)
	if _shape.get_parent() == null:
		add_child(_shape)
	_apply_shape()


func setup(config_value: GameConfig, source: SpriteSource, character_id: StringName) -> bool:
	config = config_value
	_walker = GridWalker.new(config) if config.grid_step_pixels > 0 else null
	_meter = StepMeter.new(config.footstep_pixels) if config.footstep_pixels > 0.0 else null
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
	# Both modes produce the same three fields and both move through move_and_slide, so
	# nothing downstream - the camera, y-sorting, the warp check, the QA harness - can tell
	# which one is running.
	var step := _walker.plan(input, global_position, facing, _reachable) if _walker != null \
		else Locomotion.step(input, facing, config)
	facing = step.facing
	velocity = step.velocity
	var was := global_position
	move_and_slide()
	if _walker != null:
		# Where move_and_slide actually left us decides whether the step arrived, and the last
		# fraction of a pixel is given back here rather than predicted before the move.
		global_position = _walker.settle(global_position)
	view.set_pose(step.clip, step.facing)
	# Measured, never predicted: move_and_slide picks its own delta and a wall can eat most of
	# a frame's motion, so a stride computed from speed would keep a blocked player's feet
	# clattering against the wall they are standing still against.
	if _meter != null:
		step.footfall = _meter.advance(was.distance_to(global_position))
	return step


## Whether a grid step is in flight. The invariant a caller can rely on: false means this
## actor is standing on a cell centre.
func stepping() -> bool:
	return _walker != null and _walker.stepping()


## Would this actor survive moving by `motion` from where it stands? Handed to GridWalker as a
## Callable so the walker stays a pure object with no node in it.
##
## test_move rather than a look-up in the map data: what is in front of you is as likely to be
## an NPC as a wall, and an NPC is a body in the physics server and nothing at all in MapData.
## The QA script that walks north into the warden until her body stops it would sail through a
## map look-up and fail the game.
func _reachable(motion: Vector2) -> bool:
	if not is_inside_tree():
		return true
	return not test_move(global_transform, motion)


## Puts the actor down somewhere, with no step in flight and nothing carried over from wherever
## it was. The ONE way an actor is teleported - a spawn, a warp, a load - because the order
## matters: abandoning a grid step AFTER the position has been assigned would resolve it
## against the cell it left, in the map it left, and teleport the actor back there.
func place(at: Vector2, new_facing: int = -1) -> void:
	if _walker != null:
		_walker.cancel()
	if _meter != null:
		# A spawn, a warp or a load is not a stride. Without this, the distance across a map
		# would be counted as ground the player walked and land a footstep on arrival.
		_meter.reset()
	global_position = at
	halt(new_facing)


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
	if _walker != null:
		# A step in flight is abandoned where it stands, back onto a cell centre. halt is what
		# a dialog opening calls EVERY frame it is open: a step that insisted on finishing
		# would walk the player out from under the conversation, and one left in flight would
		# resume the moment the box closed, from input nobody is holding any more.
		global_position = _walker.abandon(global_position)
	if new_facing >= 0:
		facing = new_facing
	view.set_pose(&"idle", facing)
