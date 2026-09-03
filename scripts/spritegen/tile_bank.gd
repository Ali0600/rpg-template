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
	return cell_in(at(index))


## The same, for any record that carries a `cell` - a tile or one piece of a ring. Shared so a
## ring piece is addressed by exactly the arithmetic a tile is, rather than by a second copy of
## it that could disagree about which number is the column.
static func cell_in(record: Dictionary) -> Vector2i:
	var raw := JsonFile.to_int_array(record.get("cell", []))
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(raw[0], raw[1])


## The transition pieces this tile is drawn with where it MEETS something else, or an empty
## Dictionary for a tile with hard edges. Twelve pieces keyed by TerrainEdges.RING_KEYS, plus
## an optional `c` saying what fills a quarter with no edge in it - which defaults to the tile's
## own plain art, so an interior cell comes out exactly as it did before any of this existed.
func ring_of(index: int) -> Dictionary:
	var raw: Variant = at(index).get("ring", {})
	return raw as Dictionary if raw is Dictionary else {}


func has_ring(index: int) -> bool:
	return not ring_of(index).is_empty()


## One piece of a tile's ring, in whichever shape this bank's arm uses. `from` defaults to the
## tile's own art, because a ring is drawn on the sheet its material came from - naming it
## twelve times per tile would be twelve chances to name it differently once.
func piece_of(index: int, key: String) -> Dictionary:
	# Defaulted to NULL, never to an empty Dictionary. An empty one is still a Dictionary, so it
	# survives the test below and then has `from` stamped on it - and every tile with no ring at
	# all starts answering with a whole ring cut from cell (-1, -1). Measured: it refused all
	# four shipped banks at once, which is the only reason it was cheap to find.
	var raw: Variant = ring_of(index).get(key, null)
	if not (raw is Dictionary):
		return {}
	var piece: Dictionary = (raw as Dictionary).duplicate()
	if imports() and str(piece.get("from", "")).is_empty():
		piece["from"] = source_of(index)
	return piece


## The groups of ground this tile draws an edge against, in the bank's own order. A group is a
## list because grass and its tufted variant are one material to a shoreline; the FIRST id is
## the one whose plain tile the edge is composed over, and the order is what settles a cell
## that touches two of them.
func over_of(index: int) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for group: Variant in at(index).get("over", []) as Array:
		out.append(PackedStringArray(JsonFile.to_string_array(group)))
	return out


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
			_file_problems(entry, "tile '%s'" % tile_id, out)
		else:
			_row_problems(entry, "tile '%s'" % tile_id, out)
		_ring_problems(index, entry, tile_id, out)
	return out


## What a bank that draws its own pixels can get wrong. Unchanged from the day the rows arrived,
## and lifted out whole so the two arms read as a pair rather than as a nest.
func _row_problems(entry: Dictionary, label: String, out: Array[String],
		overlay := false) -> void:
	if entry.has("from"):
		out.append("%s names a file to cut from, but this bank draws its own rows"
			% label)
	var rows := JsonFile.to_string_array(entry.get("rows", []))
	if rows.is_empty():
		out.append("%s has no rows" % label)
		return
	if rows.size() != tile:
		out.append("%s is %d rows tall, expected %d" % [label, rows.size(), tile])
	var known_chars := TONE_CHARS + TRANSPARENT_CHAR + OUTLINE_CHAR
	# An OVERLAY - a piece of a transition ring - is clear outside its material by design; that
	# clear half is the whole reason an edge composes rather than replaces. So it is exempt from
	# the hole rule on the same terms decor is, and the composite it ends up in is checked
	# instead. Spelled into this one variable rather than into the test below it, because that
	# test is the line a mutant is aimed at.
	var is_decor := overlay or bool(entry.get("decor", false))
	for ri in rows.size():
		var row := rows[ri]
		if row.length() != tile:
			out.append("%s row %d is %d wide, expected %d"
				% [label, ri, row.length(), tile])
		for ci in row.length():
			var ch := row[ci]
			if not known_chars.contains(ch):
				out.append("%s row %d has unknown pixel '%s'" % [label, ri, ch])
			elif ch == TRANSPARENT_CHAR and not is_decor:
				# A hole in the ground shows the window's background through the world.
				# It is invisible while authoring, because the tile looks right on its own.
				out.append("%s row %d column %d is transparent, but only a decor tile may be"
					% [label, ri, ci])


## What a bank that CUTS its pixels can get wrong on its own terms. Whether the cut has a hole
## in it, or lands outside the image, needs the art itself and lives in TileGen.problems() -
## the CharacterSpec split, one noun along.
func _file_problems(entry: Dictionary, label: String, out: Array[String]) -> void:
	if entry.has("rows"):
		out.append("%s is authored in rows, but this bank cuts its pixels from files"
			% label)
	var from := str(entry.get("from", ""))
	if from.is_empty():
		out.append("%s names no file to cut from" % label)
	elif not file_names().has(from):
		# The credit list is the licence gate's whole input, so a file cut from and not listed is
		# art shipping with nobody named - the one failure that cannot be fixed after release.
		out.append("%s is cut from '%s', which this bank does not credit" % [label, from])
	var cell := JsonFile.to_int_array(entry.get("cell", []))
	if cell.size() != 2 or cell[0] < 0 or cell[1] < 0:
		out.append("%s has cell %s; it wants a column and a row, both at least nought"
			% [label, str(cell)])


## What a tile's transition ring can get wrong on its own terms. Whether a piece's cut lands
## inside its sheet needs the art, and lives in TileGen.problems() with the rest of that split.
##
## The two fields are stated as a PAIR in both directions, because either one alone is a tile
## that looks finished and draws nothing: a ring with nothing to draw against is never reached,
## and an `over` with no ring names a neighbour and has no pixels for the boundary.
func _ring_problems(index: int, entry: Dictionary, tile_id: String, out: Array[String]) -> void:
	var ring := ring_of(index)
	var over := over_of(index)
	if ring.is_empty():
		if not over.is_empty():
			out.append("tile '%s' says what it lies over and names no ring to draw there"
				% tile_id)
		return
	if over.is_empty():
		out.append("tile '%s' has a ring and names nothing for it to be an edge against"
			% tile_id)
	if bool(entry.get("decor", false)):
		# Decor stands ON the ground and keeps its own transparency, so it has no boundary with
		# anything - a bush does not need a shoreline.
		out.append("tile '%s' is decor and carries a ring; decor sits on the ground rather than "
			% tile_id + "being it, so it has no edge to draw")
	var known_keys := TerrainEdges.all_keys()
	for key: Variant in ring.keys():
		if not known_keys.has(str(key)):
			# By name, because a typo'd key is a piece that is simply never drawn: the quarter
			# falls back to fill, the cell looks like ground, and nothing else complains.
			out.append("tile '%s' ring names '%s', which is not one of %s"
				% [tile_id, str(key), known_keys])
	for key in known_keys:
		if not ring.has(key):
			if key != TerrainEdges.CENTRE_KEY:
				out.append("tile '%s' ring has no '%s' piece" % [tile_id, key])
			continue
		var label := "tile '%s' ring '%s'" % [tile_id, key]
		if imports():
			_file_problems(piece_of(index, key), label, out)
		else:
			_row_problems(piece_of(index, key), label, out, true)
	_over_problems(index, tile_id, out)


## The ground a ring is drawn against. Every id has to be a tile of this bank's own, because the
## edge is COMPOSED over that tile's plain art at generation time - an id from somewhere else has
## no pixels here to lie on.
func _over_problems(index: int, tile_id: String, out: Array[String]) -> void:
	var known := ids()
	var decor := decor_ids()
	var claimed: Array[String] = []
	for group: PackedStringArray in over_of(index):
		if group.is_empty():
			out.append("tile '%s' has an empty group in its over list" % tile_id)
			continue
		for other in group:
			if other == tile_id:
				# It would ask for an edge against itself, so every interior cell would read as
				# a shoreline and the whole material would come out as fringe.
				out.append("tile '%s' is listed among the tiles it draws an edge against"
					% tile_id)
			elif not known.has(other):
				out.append("tile '%s' draws an edge against '%s', which this bank has no tile for"
					% [tile_id, other])
			elif decor.has(other):
				out.append("tile '%s' draws an edge against '%s', which is decor and has no "
					% [tile_id, other] + "ground of its own to lie on")
			if claimed.has(other):
				out.append("tile '%s' lists '%s' in more than one group, so which edge a cell "
					% [tile_id, other] + "draws would depend on which group was read first")
			claimed.append(other)


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
