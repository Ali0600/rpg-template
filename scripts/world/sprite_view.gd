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
## True while a frame is being held by hold_frame rather than played by the clip's own clock.
var _held := false


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
	# anchor puts the character's feet exactly on this node's origin. The offset itself is set
	# by _play(), per clip.
	_sprite.centered = false
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
	if _held:
		_held = false
		_sprite.play()
	if clip_name == _clip and dir == _facing:
		return
	_clip = clip_name
	_facing = dir
	_play()


## Shows one frame of a clip and holds it there, for a caller whose own clock decides which frame
## it is - the arena, whose swing is counted in physics frames rather than played at a speed. An
## index past the clip's end shows its last frame. The next set_pose lets the clip run again.
func hold_frame(clip_name: StringName, dir: int, index: int) -> void:
	if _sprite.sprite_frames == null:
		return
	if clip_name != _clip or dir != _facing:
		_clip = clip_name
		_facing = dir
		_play()
	var total := _sprite.sprite_frames.get_frame_count(Dir.anim_name(_clip, _facing))
	if total <= 0:
		return
	_held = true
	_sprite.pause()
	_sprite.set_frame_and_progress(clampi(index, 0, total - 1), 0.0)


## How many frames a clip of this character's sheet has, and nought for a clip the sheet does not
## draw - which is how a caller asks whether it can be shown at all.
func frames_in(clip_name: StringName) -> int:
	if _meta == null:
		return 0
	return _meta.frames_of(String(clip_name)).size()


## How many times an animation has actually been (re)started. The guard above changes HOW the
## work is done, not WHAT is rendered, so no assertion on the frame can see it - only
## counting the calls can. Tests read this; nothing in the game does.
func play_count() -> int:
	return _play_count


func current_animation() -> StringName:
	return _sprite.animation


func current_frame() -> int:
	return _sprite.frame


## The cell of the clip being shown, for anything that needs to know how big a character draws (a
## name label, a speech bubble, a layout audit) without reaching into the sprite. A swing drawn on a
## grid of its own is bigger than the walk, and it is the swing that has to fit.
func cell_size() -> Vector2i:
	return _meta.cell_of(String(_clip)) if _meta != null else Vector2i.ZERO


## Where this character's origin sits inside the cell of the clip being shown - the point this node's
## position IS. Needed by anything that has to work out the RECTANGLE a character occupies rather than
## the point they stand on: the node is at their feet, so the cell reaches up and back from here.
func anchor() -> Vector2i:
	return _meta.anchor_of(String(_clip)) if _meta != null else Vector2i.ZERO


func _play() -> void:
	if _sprite.sprite_frames == null:
		return
	var name := Dir.anim_name(_clip, _facing)
	if not _sprite.sprite_frames.has_animation(name):
		push_error("SpriteView: no animation '%s'" % name)
		return
	_play_count += 1
	# Per clip, because a clip on a grid of its own stands on a different point of its own cell.
	_sprite.offset = -Vector2(_meta.anchor_of(String(_clip)))
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
