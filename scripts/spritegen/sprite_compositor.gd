class_name SpriteCompositor
extends RefCounted
## Draws one character frame: stack the rig's parts in the style's colours, then outline.
##
## Pixels are written with `set_pixel`, never `blit_rect` or `blend_rect`. blit_rect copies
## a source pixel's alpha over the destination, so a transparent pixel in an upper layer
## erases the layer beneath it; blend_rect mixes floats and produces colours that are not in
## the palette at all, which no amount of careful authoring can fix afterwards. A per-pixel
## loop over a 16x24 stamp is fast enough and exactly predictable.
##
## The outline is generated, not drawn. Every part is authored inset by a pixel and the pass
## below hugs whatever silhouette the parts happened to make, which is why swapping
## `outline_mode` on the style restyles the whole cast and cannot leave a seam.

## No ramp painted this pixel.
const NO_TONE := -1

## Neighbours the outline pass looks at, in a fixed order. Bound as a typed constant rather
## than written inline: iterating an untyped array literal makes every derived value a
## Variant, which typed GDScript then refuses to infer.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]


## One frame, ready to place in a sheet. `frame` indexes the walk cycle; idle poses ask for
## frame 0.
static func compose(rig: Rig, style: SpriteStyle, resolved: Dictionary, dir: int, frame: int) -> Image:
	if dir == Dir.D.LEFT and style.mirror_left_from_right:
		# One authored side, two directions. flip_x mutates in place and returns nothing.
		var mirrored := compose(rig, style, resolved, Dir.D.RIGHT, frame)
		mirrored.flip_x()
		return mirrored

	var view := Dir.view_name(Dir.view_of(dir))
	var cell := style.cell_size
	var img := Image.create_empty(cell.x, cell.y, false, Image.FORMAT_RGBA8)

	# Parallel buffers: what the outline pass needs to know about each painted pixel.
	var count := cell.x * cell.y
	var shadow_tone := PackedInt32Array()
	shadow_tone.resize(count)
	shadow_tone.fill(NO_TONE)
	var wants_outline := PackedByteArray()
	wants_outline.resize(count)
	wants_outline.fill(0)

	var chosen_parts: Dictionary = resolved.get("parts", {})
	var chosen_ramps: Dictionary = resolved.get("ramps", {})
	var bob := 0
	if frame >= 0 and frame < style.bob_offsets.size():
		bob = style.bob_offsets[frame]

	for slot in rig.slot_order(view):
		if not chosen_parts.has(slot):
			continue
		var part_id := str(chosen_parts[slot])
		var tones := style.ramp(str(chosen_ramps.get(slot, "")))
		if tones.size() != 3:
			continue
		var stamp := rig.stamp(part_id, view, frame)
		var rows: Array[String] = stamp["rows"]
		if rows.is_empty():
			continue
		var at: Vector2i = stamp["at"]
		var dy: int = at.y + (bob if rig.bobs(part_id) else 0)
		var outline_this := rig.outlined(part_id)

		for ry in rows.size():
			var row := rows[ry]
			var y := dy + ry
			if y < 0 or y >= cell.y:
				continue
			for rx in row.length():
				var ch := row[rx]
				if ch == Rig.TRANSPARENT_CHAR:
					continue
				var x := at.x + rx
				if x < 0 or x >= cell.x:
					continue
				var color := style.outline_color()
				if ch != Rig.OUTLINE_CHAR:
					color = tones[Rig.TONE_CHARS.find(ch)]
				img.set_pixel(x, y, color)
				var i := y * cell.x + x
				shadow_tone[i] = tones[0].to_rgba32()
				wants_outline[i] = 1 if outline_this else 0

	if style.outline_mode != SpriteStyle.Outline.NONE:
		_outline(img, style, shadow_tone, wants_outline)
	return img


## Wraps the silhouette in a one-pixel border. Reads the finished layer stack rather than
## each part, so parts that touch produce one continuous outline instead of internal seams.
## Neighbours are checked in a fixed order so a pixel bordering two differently-coloured
## parts always resolves the same way - a tinted outline that depended on iteration order
## would differ between runs and break the golden hash.
static func _outline(img: Image, style: SpriteStyle, shadow_tone: PackedInt32Array, wants_outline: PackedByteArray) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var solid := style.outline_color()
	var tinted := style.outline_mode == SpriteStyle.Outline.TINTED
	var edges: Array[Vector2i] = []
	var edge_colors: PackedColorArray = PackedColorArray()

	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			var source := NO_TONE
			for step: Vector2i in NEIGHBOURS:
				var nx := x + step.x
				var ny := y + step.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				if wants_outline[ni] == 0 or shadow_tone[ni] == NO_TONE:
					continue
				source = shadow_tone[ni]
				break
			if source == NO_TONE:
				continue
			edges.append(Vector2i(x, y))
			# SpriteStyle owns the tint formula so the palette gate can predict exactly
			# which colours this pass is allowed to produce.
			edge_colors.append(SpriteStyle.tint_outline(Color(source)) if tinted else solid)

	# Collected first, written second: writing during the scan would let a fresh outline
	# pixel seed another one and grow the border outward without limit.
	for i in edges.size():
		img.set_pixel(edges[i].x, edges[i].y, edge_colors[i])


## Colours are compared as packed integers. Two visually identical Colors built by different
## routes are not reliably `==` as four floats, and the palette gate must not have that kind
## of near-miss in it.
static func rgba32_of(img: Image, x: int, y: int) -> int:
	return img.get_pixel(x, y).to_rgba32()


## The lowest row holding any opaque pixel: where this frame's character actually stands.
## Returns -1 for a blank image. The grounding gate compares this across every frame,
## direction and character - a cast that does not share a ground line looks like it is
## floating at different heights, and nothing else in the pipeline would notice.
static func ground_row(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				return y
	return -1
