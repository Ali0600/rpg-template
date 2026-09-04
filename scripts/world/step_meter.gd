class_name StepMeter
extends RefCounted
## Counts distance walked and says when a foot lands. Pure: no nodes, no clock, no autoloads.
##
## ONE accumulator serves both movement modes, deliberately. A second implementation firing on
## grid-step completion would break the invariant everything downstream relies on - that
## nothing can tell which mode is running - and the two would drift the first time either was
## touched. The honest consequence is that a diagonal grid step covers 22.6px rather than 16,
## so its footfall lands part-way through the step. That is what walking sounds like anyway.
##
## The remainder CARRIES. Resetting the count each time would make the cadence depend on frame
## rate: a slow frame covering 1.5 strides would drop the second footfall silently, and the
## cadence would speed up and slow down with the machine.

## Distance between footfalls, in PIXELS - GameConfig states it in tiles and hands this the
## bound answer, because a meter counting distance travelled counts it in the units the body
## moves in. Zero switches footsteps off entirely: a mode, not a magic number.
var _stride := 0.0
var _carried := 0.0


func _init(stride: float) -> void:
	_stride = maxf(stride, 0.0)


## Adds ground covered, and answers whether a foot landed. Handed the distance ACTUALLY moved,
## never the distance a call was expected to move: move_and_slide picks its own delta and a
## wall can eat most of a frame's motion, so a predicted stride would keep a blocked player's
## feet clattering against the wall.
func advance(distance: float) -> bool:
	if _stride <= 0.0 or distance <= 0.0:
		return false
	_carried += distance
	if _carried < _stride:
		return false
	# Subtracted rather than zeroed, so the leftover pays into the next step.
	_carried -= _stride
	return true


## Starts the count over. Called when an actor is teleported: a spawn, a warp or a load is not
## a stride, and the distance across a map is not ground the player walked.
func reset() -> void:
	_carried = 0.0


func carried() -> float:
	return _carried
