class_name TileGen
extends RefCounted
## Draws the terrain strip from an authored TileBank, in a style's colours.
##
## Sharing the palette is the whole point: a cast drawn in one set of colours standing on
## ground drawn in another looks pasted on, and it is the most common way a game made of
## mixed assets betrays itself. Because the tiles take their tones from the style, swapping
## the style re-skins the world and the characters together.
##
## This used to hold the tiles themselves - a const array of six, drawn by five hardcoded
## procedural routines. That was the one place this template kept art in code, and it had a
## cost a reader can see: no routine could draw a door, so the quest's cave was built out of
## grass-world tiles. The pixels now come from data/tiles/<id>.json and this file is only the
## compositor, which is the same division SheetBuilder has with the rig.


## {"image": Image, "meta": Dictionary} - a horizontal strip plus the JSON that describes it.
##
## The meta is the contract every consumer downstream reads: TileSetFactory takes `solid`
## from it and MapBuilder resolves a map's legend against `id`. Neither has ever known where
## the pixels came from, which is why moving them cost nothing outside this file.
static func build(style: SpriteStyle, bank: TileBank) -> Dictionary:
	var size := style.tile_size
	var strip := Image.create_empty(maxi(size * bank.size(), 1), maxi(size, 1), false, Image.FORMAT_RGBA8)
	var entries: Array = []

	for index in bank.size():
		var entry := bank.at(index)
		var tile_id := str(entry.get("id", ""))
		var ramp_name := bank.ramp_for(index, style)
		var tones := style.ramp(ramp_name)
		if tones.size() != 3:
			push_error("TileGen: style '%s' has no ramp for tile '%s'" % [style.id, tile_id])
			continue
		var tile := _draw(bank.rows_of(index), tones, style.outline_color(), size)
		# blit, not blend: blending would mix a decor tile's transparent margin with the
		# strip's own transparency as floats and land off the palette.
		strip.blit_rect(tile, Rect2i(0, 0, size, size), Vector2i(index * size, 0))
		entries.append({
			"id": tile_id,
			"index": index,
			"solid": bool(entry.get("solid", false)),
			"decor": bool(entry.get("decor", false)),
			"ramp": ramp_name,
		})

	return {
		"image": strip,
		"meta": {
			"version": 1,
			"tile_size": size,
			"columns": bank.size(),
			"rows": 1,
			"style": String(style.id),
			"tiles": entries,
		},
	}


## What a bank and a style disagree about. Separate from TileBank.problems() for the reason
## CharacterSpec.problems(rig, style) is separate from Rig.problems(): a bank is wrong on its
## own terms or it is wrong against a particular style, and only the second needs both.
static func problems(bank: TileBank, style: SpriteStyle) -> Array[String]:
	var out: Array[String] = []
	if not bank.ok:
		return out
	if bank.tile != style.tile_size:
		out.append("style '%s' has tile_size %d, but its tile bank is authored at %d"
			% [style.id, style.tile_size, bank.tile])
	for index in bank.size():
		var ramp_name := bank.ramp_for(index, style)
		if style.ramp(ramp_name).size() != 3:
			out.append("style '%s' has no ramp '%s' for tile '%s'"
				% [style.id, ramp_name, bank.at(index).get("id", "")])
	return out


## One tile, from its authored rows. set_pixel only, never blend_rect - blending produces
## colours between the ramp's tones, and the palette gate is there to catch exactly that.
static func _draw(rows: Array[String], tones: PackedColorArray, outline: Color, size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in mini(rows.size(), size):
		var row := rows[y]
		for x in mini(row.length(), size):
			var ch := row[x]
			if ch == TileBank.TRANSPARENT_CHAR:
				continue
			if ch == TileBank.OUTLINE_CHAR:
				img.set_pixel(x, y, outline)
				continue
			var tone := TileBank.TONE_CHARS.find(ch)
			if tone >= 0:
				img.set_pixel(x, y, tones[tone])
	return img
