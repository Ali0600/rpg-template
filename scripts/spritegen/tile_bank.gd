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
## A bank says where its PIXELS come from, and that is the whole switch. `pixels_from` is
## `rows` - the authored alphabet above, drawn in the style's own ramps - or `files`, where each
## tile is a CELL cut out of art somebody drew, listed under `files` with its artists and their
## licences. The `sheets_from` shape one layer down: a StringName checked against a list, a typo
## refused by name, and the two arms stated as a pair rather than inferred from an absence.
##
## The bank is the right home for that switch because a bank already IS the recipe - the ordered
## list of ids, with `solid` and `decor` on each. A style stays "which bank", so one game can
## paint hand-drawn ground and another the rig's own, with no third concept.
##
## The RUNTIME contract is untouched by any of this: the generator still emits tiles.png and
## tiles.json, TileSetFactory still reads `solid` out of that JSON, and MapBuilder still
## looks a tile up by id. Neither has ever known where the pixels came from.

## One alphabet, not two: a rig author learns nothing new to author terrain.
const TONE_CHARS := Rig.TONE_CHARS
const TRANSPARENT_CHAR := Rig.TRANSPARENT_CHAR
const OUTLINE_CHAR := Rig.OUTLINE_CHAR

## Authored in the alphabet above, in the style's ramps.
const PIXELS_FROM_ROWS := "rows"
## Cut from art under IMPORT_ROOT, in the artists' own colours.
const PIXELS_FROM_FILES := "files"
const PIXEL_SOURCES: Array[String] = [PIXELS_FROM_ROWS, PIXELS_FROM_FILES]

## The ONE place an imported bank's inputs live. Under `data/imports/`, so the editor never
## imports a 512x1024 tile sheet and the exporter never packs one - and in a directory of its
## own rather than beside a style's characters, because the character arm reports any png there
## that is not a `sheet.png`.
const IMPORT_ROOT := "res://data/imports/tiles"

var id: StringName = &""
var pixels_from: String = PIXELS_FROM_ROWS
## Every tile is square and exactly this many pixels on a side. A style whose tile_size
## disagrees is refused rather than scaled - scaling pixel art is how a template starts
## looking like a mistake.
var tile: int = 16
var ok: bool = false
var error: String = ""

## In sheet order. The order is the file's, so a diff that adds a tile appends a column
## rather than reshuffling every index in the generated metadata.
var _tiles: Array = []
## The credited art an imported bank cuts from: one entry per file, in `character.json`'s own
## credit shape, so `LpcImport` merges terrain and cast credits with no second reader.
var _files: Array = []


static func load_from(path: String) -> TileBank:
	var file := JsonFile.read(path)
	if not file.ok:
		var bad := TileBank.new()
		bad.error = file.error
		return bad
	return from_dictionary(file.data)


## The same bank from a Dictionary, which is what lets the rules below be tested against a bank
## written in three lines rather than against a fixture file per fault - `MapData`'s split, and
## for its reason.
static func from_dictionary(data: Dictionary) -> TileBank:
	var bank := TileBank.new()
	bank.id = StringName(str(data.get("id", "")))
	bank.tile = int(data.get("tile", 0))
	bank.pixels_from = str(data.get("pixels_from", PIXELS_FROM_ROWS))
	bank._tiles = data.get("tiles", [])
	bank._files = data.get("files", [])
	bank.ok = true
	return bank


## Whether this bank's pixels are cut from art rather than drawn from its own rows.
func imports() -> bool:
	return pixels_from == PIXELS_FROM_FILES


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


## The credited files this bank cuts from, in their own order - handed to LpcImport as one more
## recipe so the terrain lands in `credits.json` beside the cast.
func files() -> Array:
	return _files


func file_names() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in _files:
		out.append(str((entry as Dictionary).get("file", "")))
	return out


## Where a named file sits on disk. One place, so a suite and the generator cannot disagree
## about it.
func source_path(file: String) -> String:
	return "%s/%s/%s" % [IMPORT_ROOT, id, file]


## The file the nth tile is cut from, or empty for a bank that draws its own rows.
func source_of(index: int) -> String:
	return str(at(index).get("from", ""))


## The nth tile's cell in that file, in CELLS - column then row, the way an atlas is addressed
## everywhere else here.
func cell_of(index: int) -> Vector2i:
	var raw := JsonFile.to_int_array(at(index).get("cell", []))
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(raw[0], raw[1])


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
	if not PIXEL_SOURCES.has(pixels_from):
		# Named rather than defaulted, the npc `behavior` rule: a value that silently reads as
		# `rows` is a bank whose art never arrives, beside a `files` list nobody consumes.
		out.append("pixels_from '%s' is not one of %s" % [pixels_from, PIXEL_SOURCES])
		return out
	if imports():
		_credit_problems(out)

	var seen: Array[String] = []
	for index in _tiles.size():
		var entry := at(index)
		var tile_id := str(entry.get("id", ""))
		if tile_id.is_empty():
			out.append("tile %d has no id" % index)
		elif seen.has(tile_id):
			# A map names a tile by id, so a duplicate does not draw twice - it makes one of the
			# two unreachable, and which one loses is a property of the file order.
			out.append("tile '%s' is declared twice" % tile_id)
		else:
			seen.append(tile_id)
		if imports():
			_file_problems(entry, tile_id, out)
		else:
			_row_problems(entry, tile_id, out)
	return out


## What a bank that draws its own pixels can get wrong. Unchanged from the day the rows arrived,
## and lifted out whole so the two arms read as a pair rather than as a nest.
func _row_problems(entry: Dictionary, tile_id: String, out: Array[String]) -> void:
	if entry.has("from"):
		out.append("tile '%s' names a file to cut from, but this bank draws its own rows"
			% tile_id)
	var rows := JsonFile.to_string_array(entry.get("rows", []))
	if rows.is_empty():
		out.append("tile '%s' has no rows" % tile_id)
		return
	if rows.size() != tile:
		out.append("tile '%s' is %d rows tall, expected %d" % [tile_id, rows.size(), tile])
	var known_chars := TONE_CHARS + TRANSPARENT_CHAR + OUTLINE_CHAR
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


## What a bank that CUTS its pixels can get wrong on its own terms. Whether the cut has a hole
## in it, or lands outside the image, needs the art itself and lives in TileGen.problems() -
## the CharacterSpec split, one noun along.
func _file_problems(entry: Dictionary, tile_id: String, out: Array[String]) -> void:
	if entry.has("rows"):
		out.append("tile '%s' is authored in rows, but this bank cuts its pixels from files"
			% tile_id)
	var from := str(entry.get("from", ""))
	if from.is_empty():
		out.append("tile '%s' names no file to cut from" % tile_id)
	elif not file_names().has(from):
		# The credit list is the licence gate's whole input, so a file cut from and not listed is
		# art shipping with nobody named - the one failure that cannot be fixed after release.
		out.append("tile '%s' is cut from '%s', which this bank does not credit" % [tile_id, from])
	var cell := JsonFile.to_int_array(entry.get("cell", []))
	if cell.size() != 2 or cell[0] < 0 or cell[1] < 0:
		out.append("tile '%s' has cell %s; it wants a column and a row, both at least nought"
			% [tile_id, str(cell)])


## The credit list itself. Every entry names a file and at least one licence; the licence is
## checked against the STYLE in TileGen.problems(), because only the style knows what it accepts.
func _credit_problems(out: Array[String]) -> void:
	if _files.is_empty():
		out.append("this bank cuts its pixels from files and credits none")
	var listed: Array[String] = []
	for entry: Variant in _files:
		var record: Dictionary = entry
		var file := str(record.get("file", ""))
		if file.is_empty():
			out.append("a credited file has no name")
			continue
		if listed.has(file):
			out.append("'%s' is credited twice" % file)
		listed.append(file)
		if JsonFile.to_string_array(record.get("authors", [])).is_empty():
			out.append("'%s' credits no author" % file)
		if JsonFile.to_string_array(record.get("licenses", [])).is_empty():
			out.append("'%s' names no licence" % file)
