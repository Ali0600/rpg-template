class_name SpriteView
extends Node2D
## Plays a character's animations, with the node's origin at the character's feet.
##
## The only node in the project that knows about SpriteFrames. Everything above it - the
## player, NPCs, Sprite Lab - says "face this way, walk or stand" and never touches an
## animation name, which is what keeps a renaming or a re-timing from rippling outward.
##
## The origin matters more than it sounds: placing a character by its FEET means y-sorting,
## collision shapes and tile coordinates all refer to the same point, and a taller sprite
## (a hat, a mounted rider) drops in without re-tuning any of them. The offset comes from
## the sheet's measured anchor, so it stays correct when the rig changes.

signal animation_finished(clip: StringName)

var _sprite := AnimatedSprite2D.new()
var _meta: SheetMeta
var _facing: int = Dir.D.DOWN
var _clip: StringName = &"idle"
var _play_count := 0


func _ready() -> void:
	if _sprite.get_parent() == null:
		add_child(_sprite)
	_sprite.animation_finished.connect(func() -> void: animation_finished.emit(_clip))


## Hands the view a sheet. Returns false and leaves the view unchanged if the pair is
## unusable, so a missing character shows the previous sprite rather than an invisible node
## that looks like a movement bug.
func apply_sheet(texture: Texture2D, meta: SheetMeta) -> bool:
	var frames := SpriteFramesFactory.build(texture, meta)
	if frames == null:
		return false
	if _sprite.get_parent() == null:
		add_child(_sprite)
	_meta = meta
	_sprite.sprite_frames = frames
	# centered=false makes offset measure from the cell's top-left, so subtracting the
	# anchor puts the character's feet exactly on this node's origin.
	_sprite.centered = false
	_sprite.offset = -Vector2(meta.anchor)
	_play()
	return true


func apply_source(source: SpriteSource, character_id: StringName) -> bool:
	var sheet := source.sheet(character_id)
	if sheet.is_empty():
		return false
	return apply_sheet(sheet["texture"], sheet["meta"])


func facing() -> int:
	return _facing


func clip() -> StringName:
	return _clip


## The one call the rest of the game makes, every frame, from the movement code.
##
## The guard is why it can be called every frame: nothing is re-issued unless the pose
## actually changed. AnimatedSprite2D.play() happens to be forgiving about being handed the
## animation it is already running - it does not restart - but that is ITS behaviour, not a
## contract this class should lean on, and a future `stop(); play()` here would turn a
## per-frame call into a walk cycle frozen on frame 0.
func set_pose(clip_name: StringName, dir: int) -> void:
	if clip_name == _clip and dir == _facing:
		return
	_clip = clip_name
	_facing = dir
	_play()


## How many times an animation has actually been (re)started. The guard above changes HOW the
## work is done, not WHAT is rendered, so no assertion on the frame can see it - only
## counting the calls can. Tests read this; nothing in the game does.
func play_count() -> int:
	return _play_count


func current_animation() -> StringName:
	return _sprite.animation


func current_frame() -> int:
	return _sprite.frame


## Height of one cell, for anything that needs to know how tall a character draws (a name
## label, a speech bubble) without reaching into the sprite.
func cell_size() -> Vector2i:
	return _meta.cell if _meta != null else Vector2i.ZERO


## Where this character's origin sits inside their cell - the point this node's position IS.
## Needed by anything that has to work out the RECTANGLE a character occupies rather than the
## point they stand on: the node is at their feet, so the cell reaches up and back from here.
func anchor() -> Vector2i:
	return _meta.anchor if _meta != null else Vector2i.ZERO


func _play() -> void:
	if _sprite.sprite_frames == null:
		return
	var name := Dir.anim_name(_clip, _facing)
	if not _sprite.sprite_frames.has_animation(name):
		push_error("SpriteView: no animation '%s'" % name)
		return
	_play_count += 1
	_sprite.play(name)


## Advances the animation by an exact amount of time, without waiting for one.
##
## AnimatedSprite2D has no `advance()`; it steps itself during _process from the frame
## delta. That is fine in a running game and useless in a headless test, where there is no
## display pacing the loop - so the step is computed here from the clip's own fps and
## applied with set_frame_and_progress, which is the one setter that does not reset progress
## to zero underneath you.
func advance(delta: float) -> void:
	if _sprite.sprite_frames == null:
		return
	var anim := _sprite.animation
	var total := _sprite.sprite_frames.get_frame_count(anim)
	if total <= 0:
		return
	var fps: float = _sprite.sprite_frames.get_animation_speed(anim)
	var progress := _sprite.frame_progress + delta * fps
	var advanced := _sprite.frame + int(floorf(progress))
	progress = fposmod(progress, 1.0)
	if _sprite.sprite_frames.get_animation_loop(anim):
		advanced = posmod(advanced, total)
	else:
		advanced = mini(advanced, total - 1)
	_sprite.set_frame_and_progress(advanced, progress)
