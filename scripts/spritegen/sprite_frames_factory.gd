class_name SpriteFramesFactory
extends RefCounted
## Turns the PNG + JSON contract into the SpriteFrames an AnimatedSprite2D plays.
##
## This is the one place that knows how a sheet becomes animations, which is what makes the
## art source swappable: a procedural rig, a hand-drawn sheet or an AI export all arrive
## here as the same pair, and the game downstream never learns which.
##
## Animations are named "<clip>_<direction>" via Dir.anim_name, so a caller asks for
## `walk_down` and cannot accidentally invent `walkDown` or `down_walk`.

## Builds every clip x direction the metadata declares. Returns null and pushes an error if
## the sheet and its description disagree - a silently short SpriteFrames would show up much
## later as a character who cannot face one way.
static func build(texture: Texture2D, meta: SheetMeta) -> SpriteFrames:
	if texture == null:
		push_error("SpriteFramesFactory: no texture")
		return null
	var problems := meta.problems(texture.get_size())
	if not problems.is_empty():
		for p in problems:
			push_error("SpriteFramesFactory: " + p)
		return null

	var frames := SpriteFrames.new()
	# SpriteFrames is created holding a "default" animation nobody asked for; leaving it
	# there makes `has_animation` answer true for a clip that does not exist.
	frames.remove_animation(&"default")

	for clip in meta.clip_names():
		for dir in meta.directions:
			var name := Dir.anim_name(StringName(clip), dir)
			frames.add_animation(name)
			frames.set_animation_speed(name, meta.fps_of(clip))
			frames.set_animation_loop(name, meta.loops(clip))
			var row := meta.row_of(dir)
			for frame_index in meta.frames_of(clip):
				frames.add_frame(name, _atlas(texture, meta, row, frame_index))
	return frames


## One cell of the sheet, as a region of the shared texture. AtlasTexture keeps a single
## image in memory for the whole character rather than slicing it into 16 copies.
static func _atlas(texture: Texture2D, meta: SheetMeta, row: int, column: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = texture
	at.region = Rect2i(Vector2i(column * meta.cell.x, row * meta.cell.y), meta.cell)
	# Without this, neighbouring cells bleed a pixel into each other at some scales - the
	# classic "thin line along the edge of every sprite" artefact.
	at.filter_clip = true
	return at


## The animation names a complete sheet must provide. Used by the contract test: a factory
## that quietly produces seven of eight animations passes every other check.
static func expected_animation_names(meta: SheetMeta) -> Array[StringName]:
	var out: Array[StringName] = []
	for clip in meta.clip_names():
		for dir in meta.directions:
			out.append(Dir.anim_name(StringName(clip), dir))
	return out
