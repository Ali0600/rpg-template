class_name TileBank
extends RefCounted
## The terrain a style draws, loaded from data/tiles/<id>.json.
##
## The mirror of Rig, in the same alphabet: '.' is transparent, '1'/'2'/'3' are the shadow,
## base and light tones of this tile's ramp, and 'o' forces the style's outline colour. A
## tile carries no colour of its own, which is what lets one bank dress three styles - the
## same split CLAUDE.md already states for sound, where three voices share one cue bank.
##
## Tiles used to be a const array in TileGen drawn by five hardcoded procedural routines.
## That made terrain the one art noun this template did not treat as data: no kind could
## draw a door, so a game that wanted an interior edited a file under scripts/. The
## procedural output was ported here losslessly - every pixel it drew was one of three tones
## or transparent - so the committed PNGs did not move.
##
## The RUNTIME contract is untouched by any of this: the generator still emits tiles.png and
## tiles.json, TileSetFactory still reads `solid` out of that JSON, and MapBuilder still
## looks a tile up by id. Only the generator's INPUT moved.

## One alphabet, not two: a rig author learns nothing new to author terrain.
const TONE_CHARS := Rig.TONE_CHARS
const TRANSPARENT_CHAR := Rig.TRANSPARENT_CHAR
const OUTLINE_CHAR := Rig.OUTLINE_CHAR

var id: StringName = &""
## Every tile is square and exactly this many pixels on a side. A style whose tile_size
## disagrees is refused rather than scaled - scaling pixel art is how a template starts
## looking like a mistake.
var tile: int = 16
var ok: bool = false
var error: String = ""

## In sheet order. The order is the file's, so a diff that adds a tile appends a column
## rather than reshuffling every index in the generated metadata.
var _tiles: Array = []


static func load_from(path: String) -> TileBank:
	var bank := TileBank.new()
	var file := JsonFile.read(path)
	if not file.ok:
		bank.error = file.error
		return bank

	bank.id = StringName(file.get_string("id", ""))
	bank.tile = int(file.data.get("tile", 0))
	bank._tiles = file.get_array("tiles")
	bank.ok = true
	return bank


func size() -> int:
	return _tiles.size()


## The nth tile's raw record, or an empty Dictionary past the end.
func at(index: int) -> Dictionary:
	if index < 0 or index >= _tiles.size():
		return {}
	return _tiles[index]


func ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in _tiles:
		out.append(str((entry as Dictionary).get("id", "")))
	return out


func solid_ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in _tiles:
		var e: Dictionary = entry
		if bool(e.get("solid", false)):
			out.append(str(e.get("id", "")))
	return out


## Tiles that sit on top of another one and keep their transparency.
func decor_ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in _tiles:
		var e: Dictionary = entry
		if bool(e.get("decor", false)):
			out.append(str(e.get("id", "")))
	return out


func rows_of(index: int) -> Array[String]:
	return JsonFile.to_string_array(at(index).get("rows", []))


## The ramp this tile is drawn in: the style's override if it names one, otherwise the
## bank's own default. The default is what stops a new tile from being a mandatory edit to
## every style - the rig solves the same problem with slot_defaults.
func ramp_for(index: int, style: SpriteStyle) -> String:
	var entry := at(index)
	var tile_id := str(entry.get("id", ""))
	var override := str(style.tile_ramps.get(tile_id, "")) if style != null else ""
	if not override.is_empty():
		return override
	return str(entry.get("ramp", ""))


## Everything structurally wrong with this bank, all of it, named. Authored pixel art fails
## by drawing something plausible rather than by erroring, so every fault here is one that
## would otherwise reach the player as art nobody meant.
func problems() -> Array[String]:
	var out: Array[String] = []
	if not ok:
		out.append("tile bank did not load: " + error)
		return out
	if String(id).is_empty():
		out.append("tile bank has no id")
	if tile <= 0:
		out.append("tile bank size must be positive, got %d" % tile)
	if _tiles.is_empty():
		out.append("tile bank has no tiles")

	var known_chars := TONE_CHARS + TRANSPARENT_CHAR + OUTLINE_CHAR
	var seen: Array[String] = []
	for index in _tiles.size():
		var entry := at(index)
		var tile_id := str(entry.get("id", ""))
		if tile_id.is_empty():
			out.append("tile %d has no id" % index)
		elif seen.has(tile_id):
			# A map names a tile by id, so a duplicate does not draw twice - it makes one of
			# the two unreachable, and which one loses is a property of the file order.
			out.append("tile '%s' is declared twice" % tile_id)
		else:
			seen.append(tile_id)

		var rows := rows_of(index)
		if rows.is_empty():
			out.append("tile '%s' has no rows" % tile_id)
			continue
		if rows.size() != tile:
			out.append("tile '%s' is %d rows tall, expected %d" % [tile_id, rows.size(), tile])
		var is_decor := bool(entry.get("decor", false))
		for ri in rows.size():
			var row := rows[ri]
			if row.length() != tile:
				out.append("tile '%s' row %d is %d wide, expected %d"
					% [tile_id, ri, row.length(), tile])
			for ci in row.length():
				var ch := row[ci]
				if not known_chars.contains(ch):
					out.append("tile '%s' row %d has unknown pixel '%s'" % [tile_id, ri, ch])
				elif ch == TRANSPARENT_CHAR and not is_decor:
					# A hole in the ground shows the window's background through the world.
					# It is invisible while authoring, because the tile looks right on its own.
					out.append("tile '%s' row %d column %d is transparent, but only a decor tile may be"
						% [tile_id, ri, ci])
	return out
