class_name TiledMap
extends RefCounted
## Translating between this template's map format and Tiled's `.tmj`, both ways.
##
## PURE DICTIONARY TO DICTIONARY. Nothing here opens a file, and that is what lets the round-trip
## be a unit test over the six maps the game already ships rather than over a fixture somebody
## invented: write a real map out, read it back, and require what comes back to equal what went
## in, field for field.
##
## BUILD-TIME, NOT RUNTIME. `tools/map_io.gd` converts, and the committed artifact stays the
## native JSON - so a map authored in Tiled arrives as the same legend-and-ASCII file every other
## map is, and still diffs as a picture in a pull request. That is the sprite generator's shape
## exactly: author in the tool, run the generator, commit the output, and a drift gate proves the
## committed output is what the tool now produces. The alternative - parsing `.tmj` at runtime -
## would put a second shipped format behind `MapData.load_from` and give up the readable diff for
## nothing, since the editor never reads the committed file anyway.
##
## THE TILESET IS THE COUPLING, and it is checked rather than trusted. Tiled stores a tile as a
## GID: a number indexing the tileset image, so a map painted against one bank of tiles and loaded
## against another points every cell at the wrong thing and says nothing. `problems()` refuses a
## map whose tileset does not match the one being translated against - by NAME and by COUNT - so
## reordering `data/tiles/*.json` is a loud failure rather than a silently redecorated map.

## What a GID of zero means in Tiled: nothing painted here. The template's own spelling for that
## is a space in the ASCII row, which `MapData.tile_at` already reads as "".
const EMPTY_GID := 0

## The marker on a property whose value is not a scalar.
##
## Tiled's property types are string, int, float, bool, colour, file, object and class - there is
## no array among them, and a map record can hold one (`group: ["gloom"]`, a patrol `path` of
## tile pairs). Rather than flatten those into something lossy, they travel as JSON behind this
## prefix: unambiguous, still editable by hand in Tiled's panel, and exact on the way back.
##
## Scalars deliberately do NOT get it. They become real typed Tiled properties, which is the
## entire point of the exercise - a designer editing `speed` or `dialog` in the side panel is
## what the editor is for.
const JSON_PREFIX := "@json:"

## The object layers, and the map key each one carries. Named here once because both directions
## walk it: the exporter builds a layer per entry, the importer reads one.
const RECORD_LAYERS := ["spawns", "npcs", "warps", "objects", "enemies"]


## Everything wrong with `raw` as a Tiled map for `tile_ids`, in the idiom of every other
## problems() here: all of them, not the first.
##
## The tileset checks are the ones that matter. A GID is an index, so a map that was painted
## against a different bank is not a broken file - it is a map full of the wrong tiles, and every
## other gate in this project would pass it.
## `tile_size` is what the CALLER will read the file at, and zero means "do not check" - the
## default is for a caller that has no table to hand. It matters because every coordinate in a
## Tiled file is in PIXELS: an object is placed at `tile * tile_size` and read back by dividing,
## so a file painted at one size and read at another puts every record at a fraction of its tile,
## silently, on a map that still parses. It is the tileset coupling exactly, in another unit.
static func problems(raw: Dictionary, style: StringName, tile_ids: PackedStringArray,
		tile_size: int = 0) -> Array[String]:
	var out: Array[String] = []
	if str(raw.get("type", "")) != "map":
		out.append("not a Tiled map: type is '%s'" % raw.get("type", ""))
	if bool(raw.get("infinite", false)):
		out.append("map is infinite, and a template map has a fixed size")
	if str(raw.get("orientation", "orthogonal")) != "orthogonal":
		out.append("map is '%s', and this template draws orthogonal maps"
			% raw.get("orientation", ""))
	var grid := int(raw.get("tilewidth", 0))
	if tile_size > 0 and grid != tile_size:
		out.append("map was painted on a %dpx grid and is being read at %dpx - every record on it "
			% [grid, tile_size] + "would land at a fraction of its own tile")
	var sets: Array = raw.get("tilesets", [])
	if sets.size() != 1:
		out.append("map uses %d tilesets; a template map is painted from exactly one" % sets.size())
		return out
	var set_one: Dictionary = sets[0]
	var named := str(set_one.get("name", ""))
	if named != String(style):
		out.append("map was painted against tileset '%s' and is being read as '%s' - every tile "
			% [named, style] + "on it would come out as a different tile")
	var count := int(set_one.get("tilecount", 0))
	if count != tile_ids.size():
		out.append("map was painted against %d tiles and '%s' now has %d - the bank has changed "
			% [count, style, tile_ids.size()] + "under it and every id past the change is wrong")
	if int(set_one.get("firstgid", 0)) <= 0:
		out.append("tileset has no firstgid, so no tile on the map can be resolved")
	return out


## What the tileset image is called beside an exported map. One name per style, so a directory
## of maps drawn from different banks does not collide on one file.
static func atlas_name(style: String) -> String:
	return _atlas_name(style)


static func _atlas_name(style: String) -> String:
	return "tiles_%s.png" % style


## Which tile bank this map was painted against, read from the file itself.
##
## The style travels IN the map rather than on the command line, for the reason a save names its
## game: two sources for one fact is how a map ends up read against a bank it disagrees with, and
## the disagreement is silent - every cell resolves to some tile, just the wrong one.
static func style_of(raw: Dictionary) -> String:
	return str(_read_properties(raw.get("properties", [])).get("style", ""))


## A Tiled map, from one of this template's own.
##
## `tile_ids` is the bank in index order, which is what makes a GID mean anything; the caller
## reads it from the generated `tiles.json` rather than this class reaching for a file.
static func from_native(native: Dictionary, tile_ids: PackedStringArray,
		tile_size: int) -> Dictionary:
	var ground := JsonFile.to_string_array(native.get("ground", []))
	var decor := JsonFile.to_string_array(native.get("decor", []))
	var legend: Dictionary = native.get("legend", {})
	var wide := 0
	for row in ground:
		wide = maxi(wide, row.length())
	var style := str(native.get("style", "gb16"))
	var layers: Array = []
	var layer_id := 1
	for pair: Array in [["ground", ground], ["decor", decor]]:
		layers.append(_tile_layer(str(pair[0]), pair[1], legend, tile_ids, wide, layer_id))
		layer_id += 1
	var object_id := 1
	for key: String in RECORD_LAYERS:
		var made := _object_layer(key, native.get(key, [] if key != "spawns" else {}), tile_size,
			layer_id, object_id)
		layers.append(made["layer"])
		object_id = int(made["next_object_id"])
		layer_id += 1
	return {
		"type": "map",
		"version": "1.10",
		"tiledversion": "1.10.2",
		"orientation": "orthogonal",
		"renderorder": "right-down",
		"infinite": false,
		"width": wide,
		"height": ground.size(),
		"tilewidth": tile_size,
		"tileheight": tile_size,
		"nextlayerid": layer_id,
		"nextobjectid": object_id,
		# The map's own fields ride as map properties, so a `.tmj` is a complete description and
		# the importer needs nothing alongside it but the tile bank.
		"properties": _properties({
			"id": native.get("id", ""),
			"style": style,
			"music": native.get("music", ""),
		}),
		"tilesets": [{
			"firstgid": 1,
			"name": style,
			"tilewidth": tile_size,
			"tileheight": tile_size,
			"tilecount": tile_ids.size(),
			"columns": tile_ids.size(),
			# Named for the STYLE and expected BESIDE the map file. Tiled resolves this relative
			# to the .tmj, so a bare "tiles.png" pointed at a file that is not there and every
			# tile opened blank - found by opening one in Tiled, which is the only place it
			# could be found. map_io.gd copies the atlas in under this name.
			"image": _atlas_name(style),
			"imagewidth": tile_ids.size() * tile_size,
			"imageheight": tile_size,
		}],
		"layers": layers,
	}


## One of this template's maps, from a Tiled one. The inverse of `from_native`, and the round-trip
## test is what keeps the two honest about each other.
##
## THE LEGEND IS REBUILT rather than carried. A `.tmj` has no legend - it has GIDs - so the
## characters are assigned here, in the order tiles are first met. That is why the round-trip
## compares the RESOLVED map rather than the raw text: two legends that map different characters
## to the same tiles describe the same map, and a comparison on the strings would call them
## different.
static func to_native(raw: Dictionary, tile_ids: PackedStringArray, tile_size: int) -> Dictionary:
	var first_gid := 1
	var sets: Array = raw.get("tilesets", [])
	if not sets.is_empty():
		first_gid = int((sets[0] as Dictionary).get("firstgid", 1))
	var props := _read_properties(raw.get("properties", []))
	var out := {
		"id": props.get("id", ""),
		"style": props.get("style", "gb16"),
		"music": props.get("music", ""),
	}
	var legend := {}
	var used := {}
	for entry: Variant in raw.get("layers", []):
		var layer: Dictionary = entry
		var name := str(layer.get("name", ""))
		if str(layer.get("type", "")) == "tilelayer":
			out[name] = _rows_of(layer, tile_ids, first_gid, legend, used)
		elif RECORD_LAYERS.has(name):
			out[name] = _records_of(layer, name, tile_size)
	out["legend"] = legend
	return out


# -- writing ------------------------------------------------------------------------------------

static func _tile_layer(name: String, rows: Array[String], legend: Dictionary,
		tile_ids: PackedStringArray, wide: int, id: int) -> Dictionary:
	var data: Array[int] = []
	for y in rows.size():
		var row: String = rows[y]
		for x in wide:
			# Short rows are padded with nothing rather than refused: the native format lets a
			# row stop early, and a Tiled layer is a rectangle.
			var ch := row[x] if x < row.length() else " "
			var named := str(legend.get(ch, ""))
			var at := tile_ids.find(named)
			data.append(EMPTY_GID if named.is_empty() or at < 0 else at + 1)
	return {
		"type": "tilelayer", "name": name, "id": id, "x": 0, "y": 0,
		"width": wide, "height": rows.size(), "opacity": 1.0, "visible": true,
		"encoding": "csv", "data": data,
	}


static func _object_layer(name: String, records: Variant, tile_size: int, id: int,
		first_object_id: int) -> Dictionary:
	var objects: Array = []
	var next := first_object_id
	# `spawns` is a name -> tile map where the others are lists of records; both become objects,
	# and the shape is recovered on the way back from the layer's own name.
	var listed: Array = []
	if records is Dictionary:
		for key: Variant in records:
			listed.append({"name": str(key), "tile": records[key]})
	else:
		listed = records
	for entry: Variant in listed:
		var record: Dictionary = entry
		var tile := JsonFile.to_int_array(record.get("tile", []))
		var fields := record.duplicate(true)
		fields.erase("tile")
		var label := str(fields.get("name", fields.get("id", "")))
		objects.append({
			"id": next,
			"name": label,
			"type": name,
			"x": float(tile[0] * tile_size) if tile.size() == 2 else 0.0,
			"y": float(tile[1] * tile_size) if tile.size() == 2 else 0.0,
			"width": float(tile_size), "height": float(tile_size),
			"visible": true, "rotation": 0.0,
			"properties": _properties(fields),
		})
		next += 1
	return {
		"layer": {
			"type": "objectgroup", "name": name, "id": id, "x": 0, "y": 0,
			"opacity": 1.0, "visible": true, "draworder": "topdown", "objects": objects,
		},
		"next_object_id": next,
	}


## A record's fields as Tiled properties: scalars typed, everything else JSON behind the marker.
static func _properties(fields: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = fields.keys()
	# SORTED, so the same map always exports the same bytes. A dictionary's order is not a
	# promise, and a drift gate that compares output byte for byte needs one.
	keys.sort()
	for key: Variant in keys:
		var value: Variant = fields[key]
		var kind := "string"
		match typeof(value):
			TYPE_BOOL: kind = "bool"
			TYPE_INT: kind = "int"
			TYPE_FLOAT: kind = "float"
			TYPE_STRING, TYPE_STRING_NAME: kind = "string"
			_:
				value = JSON_PREFIX + JSON.stringify(value)
		out.append({"name": str(key), "type": kind,
			"value": str(value) if kind == "string" else value})
	return out


# -- reading ------------------------------------------------------------------------------------

static func _read_properties(raw: Variant) -> Dictionary:
	var out := {}
	for entry: Variant in (raw if raw is Array else []):
		var prop: Dictionary = entry
		var value: Variant = prop.get("value", "")
		if value is String and (value as String).begins_with(JSON_PREFIX):
			var decoded: Variant = JSON.parse_string((value as String).substr(JSON_PREFIX.length()))
			value = decoded if decoded != null else value
		out[str(prop.get("name", ""))] = value
	return out


static func _rows_of(layer: Dictionary, tile_ids: PackedStringArray, first_gid: int,
		legend: Dictionary, used: Dictionary) -> Array[String]:
	# The characters a legend may use, in the order they are handed out. Chosen to look like the
	# hand-written maps rather than to be dense: a converted map should read like one somebody
	# typed, because that is the artifact that gets committed and reviewed.
	const ALPHABET := ".,-#~*abcdefghijklmnopqrstuvwxyz0123456789"
	var wide := int(layer.get("width", 0))
	var data: Array = layer.get("data", [])
	var out: Array[String] = []
	var row := ""
	for i in data.size():
		var gid := int(data[i])
		var ch := " "
		if gid != EMPTY_GID:
			var at := gid - first_gid
			var named: String = tile_ids[at] if at >= 0 and at < tile_ids.size() else ""
			if not named.is_empty():
				if not used.has(named):
					var next: String = ALPHABET[used.size()] if used.size() < ALPHABET.length() \
						else "?"
					used[named] = next
					legend[next] = named
				ch = str(used[named])
		row += ch
		if (i + 1) % wide == 0:
			# Trailing blanks are dropped, which is what a hand-written map does with a short row -
			# and what keeps a re-export byte-identical to the file it came from.
			out.append(row.rstrip(" "))
			row = ""
	return out


static func _records_of(layer: Dictionary, name: String, tile_size: int) -> Variant:
	var listed: Array = []
	for entry: Variant in layer.get("objects", []):
		var object: Dictionary = entry
		var record := _read_properties(object.get("properties", []))
		record["tile"] = [int(object.get("x", 0)) / tile_size, int(object.get("y", 0)) / tile_size]
		listed.append(record)
	if name != "spawns":
		return listed
	# `spawns` goes back to being a name -> tile map, which is the one record layer whose native
	# shape is not a list.
	var out := {}
	for entry: Variant in listed:
		var record: Dictionary = entry
		out[str(record.get("name", ""))] = record.get("tile", [])
	return out
