class_name SheetBuilder
extends RefCounted
## Assembles composed frames into one sheet image plus the metadata that describes it.
##
## Rows are directions in Dir.ALL order, columns are walk frames. That layout is not a
## detail: a sheet written in one order and read in another produces a character walking
## east while facing west, with nothing anywhere reporting an error.

## {"image": Image, "meta": SheetMeta}
static func build(rig: Rig, style: SpriteStyle, spec: CharacterSpec) -> Dictionary:
	var resolved := spec.resolve(rig, style)
	var cell := style.cell_size
	var columns := style.walk_frames
	var rows := Dir.ALL.size()
	var sheet := Image.create_empty(cell.x * columns, cell.y * rows, false, Image.FORMAT_RGBA8)

	var ground := -1
	for row in rows:
		var dir: int = Dir.ALL[row]
		for col in columns:
			var frame := SpriteCompositor.compose(rig, style, resolved, dir, col)
			# blit_rect is correct HERE and wrong inside the compositor: the destination is
			# untouched transparent space, so there is no lower layer for the source's
			# alpha to erase, and copying a whole cell in one call is exact.
			sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, row * cell.y))
			ground = maxi(ground, SpriteCompositor.ground_row(frame))

	var meta := SheetMeta.new()
	meta.cell = cell
	meta.columns = columns
	meta.rows = rows
	meta.directions = Dir.ALL.duplicate()
	# Measured, not declared. Every other system reads the anchor to place the sprite's feet
	# on the ground, so deriving it from the pixels keeps it true even if the rig moves.
	meta.anchor = Vector2i(cell.x / 2, ground)
	meta.animations = {
		"idle": {"frames": [0], "fps": style.idle_fps, "loop": true},
		"walk": {"frames": _sequence(columns), "fps": style.walk_fps, "loop": true},
	}
	meta.source = "procedural"
	meta.style = String(style.id)
	meta.character = String(spec.id)
	meta.seed = spec.seed
	return {"image": sheet, "meta": meta}


static func _sequence(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(i)
	return out


## A single strip showing every character side by side, front-facing and idle. This is the
## picture that answers the only question that matters about a generator - "do these look
## like they belong to the same game?" - and it answers it at a glance, which no test can.
static func contact_sheet(rig: Rig, style: SpriteStyle, specs: Array[CharacterSpec]) -> Image:
	var cell := style.cell_size
	var columns := style.walk_frames
	if specs.is_empty():
		return Image.create_empty(cell.x, cell.y, false, Image.FORMAT_RGBA8)
	var out := Image.create_empty(cell.x * columns, cell.y * specs.size(), false, Image.FORMAT_RGBA8)
	for i in specs.size():
		var resolved := specs[i].resolve(rig, style)
		for col in columns:
			# One row per character, walking on the spot: the walk frames are where a
			# mismatched ground line or a stray bob shows up.
			var frame := SpriteCompositor.compose(rig, style, resolved, Dir.D.DOWN, col)
			out.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, i * cell.y))
	return out
