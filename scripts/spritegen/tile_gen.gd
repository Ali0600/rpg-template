class_name TileGen
extends RefCounted
## Generates the terrain tiles, from the same ramps as the characters.
##
## Sharing the palette is the whole point: a cast drawn in one set of colours standing on
## ground drawn in another looks pasted on, and it is the most common way a game made of
## mixed assets betrays itself. Because the tiles come from the style, swapping the style
## re-skins the world and the characters together.
##
## Every tile is a flat base with a small amount of seeded texture. The seed is fixed per
## tile id, so regenerating produces identical bytes and the drift gate stays meaningful.

## Tiles this generator knows how to draw, in sheet order. `solid` becomes a collision shape
## in TileSetFactory - the one property the world actually needs from art.
const TILES: Array[Dictionary] = [
	{"id": "grass", "kind": "scatter", "solid": false, "seed": 101},
	{"id": "grass_alt", "kind": "scatter", "solid": false, "seed": 202},
	{"id": "path", "kind": "speckle", "solid": false, "seed": 303},
	{"id": "water", "kind": "ripple", "solid": true, "seed": 404},
	{"id": "wall", "kind": "brick", "solid": true, "seed": 505},
	{"id": "bush", "kind": "blob", "solid": true, "seed": 606},
]


## {"image": Image, "meta": Dictionary} - a horizontal strip plus the JSON that describes it.
static func build(style: SpriteStyle) -> Dictionary:
	var size := style.tile_size
	var strip := Image.create_empty(size * TILES.size(), size, false, Image.FORMAT_RGBA8)
	var entries: Array = []

	for i in TILES.size():
		var def := TILES[i]
		var ramp_name := str(style.tile_ramps.get(def["id"], ""))
		var tones := style.ramp(ramp_name)
		if tones.size() != 3:
			push_error("TileGen: style '%s' has no ramp for tile '%s'" % [style.id, def["id"]])
			continue
		var tile := _draw(def, tones, size)
		strip.blit_rect(tile, Rect2i(0, 0, size, size), Vector2i(i * size, 0))
		entries.append({"id": def["id"], "index": i, "solid": def["solid"], "ramp": ramp_name})

	return {
		"image": strip,
		"meta": {
			"version": 1,
			"tile_size": size,
			"columns": TILES.size(),
			"rows": 1,
			"style": String(style.id),
			"tiles": entries,
		},
	}


static func _draw(def: Dictionary, tones: PackedColorArray, size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(tones[1])
	var rng := SeededRng.new(int(def["seed"]))
	match str(def["kind"]):
		"scatter":
			# Tufts: a light pixel with a shadow one below reads as a blade of grass at 16px.
			for i in 7:
				var x := rng.next_int(1, size - 2)
				var y := rng.next_int(1, size - 3)
				img.set_pixel(x, y, tones[2])
				img.set_pixel(x, y + 1, tones[0])
		"speckle":
			for i in 12:
				var x := rng.next_int(0, size - 1)
				var y := rng.next_int(0, size - 1)
				img.set_pixel(x, y, tones[2] if rng.chance(0.5) else tones[0])
		"ripple":
			# Horizontal dashes at regular rows: the eye reads repetition as water, and a
			# fixed spacing tiles seamlessly where scattered marks would not.
			for y in range(1, size, 3):
				var start := rng.next_int(0, size - 6)
				for x in range(start, mini(start + 5, size)):
					img.set_pixel(x, y, tones[2])
				var trail := rng.next_int(0, size - 4)
				for x in range(trail, mini(trail + 3, size)):
					img.set_pixel(x, mini(y + 1, size - 1), tones[0])
		"brick":
			# Courses of half-offset bricks. Mortar is the shadow tone, and each brick gets a
			# light top edge so the wall reads as lit from above like everything else.
			var course := size / 2
			for y in size:
				var in_mortar_row := y % course == 0
				for x in size:
					var offset := 0 if (y / course) % 2 == 0 else course / 2
					var in_mortar_col := (x + offset) % course == 0
					if in_mortar_row or in_mortar_col:
						img.set_pixel(x, y, tones[0])
					elif y % course == 1:
						img.set_pixel(x, y, tones[2])
		"blob":
			# A rounded mass, rimmed in shadow with a soft highlight up and to the left -
			# the same light direction the character shading uses, which is most of why the
			# cast and the scenery look like they belong to one drawing.
			var c := (size - 1) / 2.0
			var lit := Vector2(c * 0.65, c * 0.6)
			for y in size:
				for x in size:
					var d := Vector2(x - c, y - c).length() / (size / 2.0)
					if d > 0.98:
						img.set_pixel(x, y, tones[0])
					elif Vector2(x - lit.x, y - lit.y).length() < size * 0.22:
						img.set_pixel(x, y, tones[2])
			# A few dark flecks so a field of bushes does not read as a field of buttons.
			for i in 5:
				img.set_pixel(rng.next_int(3, size - 4), rng.next_int(3, size - 4), tones[0])
	return img


static func solid_ids() -> Array[String]:
	var out: Array[String] = []
	for def in TILES:
		if bool(def["solid"]):
			out.append(str(def["id"]))
	return out


static func ids() -> Array[String]:
	var out: Array[String] = []
	for def in TILES:
		out.append(str(def["id"]))
	return out
