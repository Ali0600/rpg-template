class_name Locomotion
extends RefCounted
## Turns raw input into a velocity, a facing and a pose. Pure: no nodes, no engine state.
##
## Everything that makes four-direction movement feel right or wrong lives here, so it can
## all be tested without a scene: how a diagonal is normalised, which way a tie faces,
## whether releasing the keys spins the character back to front. The node that applies it
## (Player, NPCs) contributes only `move_and_slide`.
##
## Keeping it pure is what let grid stepping be added beside this rather than inside it. Note
## that "a second implementation of step is the whole job" - which this comment used to claim -
## was wrong: this class is static and an actor holds only its facing, so there was nowhere to
## keep how far through a step it is. That state lives in GridWalker, which asks this function
## for the DIRECTION so both modes share one answer about diagonals and about which way a tie
## faces.

## What one step of input decides. Everything downstream reads these three fields and
## nothing else.
class Step:
	var velocity: Vector2
	var facing: int
	var clip: StringName
	## Whether a foot landed on this step. Not decided here or by GridWalker - neither knows
	## how far the body ACTUALLY moved, and only the move itself does. ActorBody.apply sets it
	## after move_and_slide, which is why it has a default rather than a constructor argument.
	var footfall := false

	func _init(velocity_value: Vector2, facing_value: int, clip_value: StringName) -> void:
		velocity = velocity_value
		facing = facing_value
		clip = clip_value


## `input` is the raw axis pair, each component in [-1, 1]. `facing_now` is what the
## character is facing already, which is what a released key falls back to.
static func step(input: Vector2, facing_now: int, config: GameConfig) -> Step:
	var move := input
	if not config.allow_diagonal:
		# One axis at a time. The dominant axis wins, and a tie goes horizontal - the same
		# rule Dir uses for facing, so the character never faces a way it is not moving.
		if absf(move.x) >= absf(move.y):
			move = Vector2(signf(move.x), 0.0)
		else:
			move = Vector2(0.0, signf(move.y))

	if move.length() > 1.0:
		# Normalise, never clamp per-axis: two keys held would otherwise produce a vector of
		# length 1.41 and a character who is 41% faster diagonally. It is the most common bug
		# in hand-rolled movement and it survives playtesting because it feels good.
		move = move.normalized()

	var velocity := move * config.walk_speed
	var facing := Dir.facing_from_vector(move, facing_now)
	var moving := velocity.length() > config.idle_speed_epsilon
	return Step.new(velocity, facing, &"walk" if moving else &"idle")


## Reads the four movement actions into an axis pair. The only place the action names are
## spelled, so a rebind is one edit and a rename cannot half-apply.
static func read_input() -> Vector2:
	return Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_up", &"move_down"))


## Where an interaction lands: in front of the character, at arm's length. Derived from the
## facing rather than from the velocity, so a character standing still still has a front.
static func interact_point(origin: Vector2, facing: int, config: GameConfig) -> Vector2:
	return origin + Dir.vector_of(facing) * config.interact_reach
