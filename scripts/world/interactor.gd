class_name Interactor
extends RefCounted
## Finds what the player is facing, so pressing the button talks to the right thing.
##
## Pure geometry over a list of candidates rather than a physics query, for two reasons:
## it can be tested without a scene, and a physics ray would report whichever collider it
## hit first - which for two NPCs standing shoulder to shoulder is whichever the engine
## happened to insert first, not the one the player is looking at.
##
## The rule is "closest thing whose body contains the point in front of me, and if none
## contains it, the closest one within reach". The second half matters: without it, standing
## a pixel too far away does nothing at all and reads as the button being broken.

## What a candidate looks like to this class. Deliberately not a Node: keeping it plain data
## is what lets the tests describe a situation instead of building one.
class Target:
	var id: StringName
	var position: Vector2
	var size: Vector2
	var payload: Variant

	func _init(id_value: StringName, position_value: Vector2, size_value: Vector2, payload_value: Variant = null) -> void:
		id = id_value
		position = position_value
		size = size_value
		payload = payload_value

	## The body's box in world space. Position is the FEET, so the box sits above it.
	func rect() -> Rect2:
		return Rect2(position - Vector2(size.x / 2.0, size.y), size)


## The target the actor at `origin` facing `facing` would interact with, or null.
static func find(origin: Vector2, facing: int, config: GameConfig, targets: Array[Target]) -> Target:
	var point := Locomotion.interact_point(origin, facing, config)
	var best: Target = null
	var best_distance := INF

	for target in targets:
		if target.rect().has_point(point):
			var d := target.position.distance_to(point)
			if d < best_distance:
				best = target
				best_distance = d
	if best != null:
		return best

	# Nothing under the point. Fall back to the nearest target within reach that is roughly
	# in front - generous by half a tile, because "I am clearly standing here facing you" and
	# "my reach point landed one pixel past your hitbox" look identical to a player.
	var forward := Dir.vector_of(facing)
	for target in targets:
		var to_target := target.position - origin
		if to_target.dot(forward) <= 0.0:
			continue
		var d := to_target.length()
		if d > config.interact_reach + config.body_size.x:
			continue
		if d < best_distance:
			best = target
			best_distance = d
	return best
