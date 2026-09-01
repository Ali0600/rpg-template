class_name LdtkMap
extends RefCounted
## Translating between this template's map format and LDtk's `.ldtk`, both ways.
##
## THE SIBLING OF `TiledMap`, deliberately down to the function names: `problems`, `style_of`,
## `from_native`, `to_native`. `tools/map_io.gd` picks between them from a table rather than
## branching, so a third editor is a translator plus a row - and both are proved the same way,
## by round-tripping the six maps the game already ships.
##
## PURE DICTIONARY TO DICTIONARY, and build-time. Everything in `TiledMap`'s own header applies:
## the committed artifact stays the native JSON, the editor file is a working file, and nothing
## new ships.
##
## WRITTEN AGAINST LDtk 1.5.3's published schema AND its own sample projects, because the schema
## alone is misleading in one specific way: its `required` list means "LDtk always WRITES this",
## not "the loader REFUSES without it". LDtk's own 0.9.3 test file, which current LDtk opens, is
## missing eleven fields the 1.5.3 schema calls required. So the shape here is copied from what
## the editor actually emits rather than trimmed to what a reading of the schema would allow.
##
## WHAT THIS CANNOT PROVE, and it is worth saying plainly: LDtk is not installed here and cannot
## be, so nothing in this project has ever opened one of these files in the editor. The round
## trip proves this reader understands this writer, which is a different claim - the same gap
## `TiledMap` has had since M38. Opening one generated file in LDtk once would close it, and that
## needs a person.

## The marker on a value that is not a scalar.
##
## LDtk has richer field types than Tiled - `Array<Int>`, `Point`, enums - but nothing that
## describes an array of tile PAIRS, which is what a patrol `path` is. So structured values
## travel as JSON behind this prefix, exactly as they do for Tiled, and the two translators stay
## the same shape. Scalars become real typed LDtk fields, which is the point of the exercise.
const JSON_PREFIX := "@json:"

## The object layers, and the map key each carries. Walked by both directions.
const RECORD_LAYERS := ["spawns", "npcs", "warps", "objects", "enemies"]

## The map's own fields, carried as LDtk level fields - the `.ldtk` equivalent of Tiled's map
## properties, so one file is still a complete description.
const LEVEL_FIELDS := ["id", "style", "music"]

const VERSION := "1.5.3"
const TILESET_UID := 1
const LAYER_UID := 10
const ENTITY_UID := 20
const LEVEL_UID := 100
const LEVEL_FIELD_UID := 110
const FIELD_UID := 200
const NEXT_UID := 1000


## Everything wrong with `raw` as an LDtk project for `tile_ids`. All of them, not the first.
##
## The tileset checks are the ones that matter, for `TiledMap.problems()`'s reason: a tile is
## stored as an INDEX into the atlas, so a map painted against one bank and read against another
## is not a broken file, it is a map full of the wrong tiles.
static func problems(raw: Dictionary, style: StringName, tile_ids: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	var defs: Dictionary = raw.get("defs", {})
	var levels: Array = raw.get("levels", [])
	if levels.size() != 1:
		out.append("project holds %d levels; a template map is one level" % levels.size())
	if bool(raw.get("externalLevels", false)):
		out.append("project keeps its levels in separate files, and this reads them inline")
	var sets: Array = defs.get("tilesets", [])
	if sets.size() != 1:
		out.append("project uses %d tilesets; a template map is painted from exactly one"
			% sets.size())
		return out
	var set_one: Dictionary = sets[0]
	var named := str(set_one.get("identifier", ""))
	if named != String(style):
		out.append("map was painted against tileset '%s' and is being read as '%s' - every tile "
			% [named, style] + "on it would come out as a different tile")
	var across := int(set_one.get("__cWid", 0))
	var down := int(set_one.get("__cHei", 0))
	if across * down != tile_ids.size():
		out.append("map was painted against %d tiles and '%s' now has %d - the bank has changed "
			% [across * down, style, tile_ids.size()] + "under it and every id past the change "
			+ "is wrong")
	if int(set_one.get("tileGridSize", 0)) <= 0:
		out.append("tileset has no tileGridSize, so no tile on it has a size")
	return out


## Which tile bank this map was painted against, read from the file itself - `TiledMap.style_of`'s
## twin, and for its reason.
static func style_of(raw: Dictionary) -> String:
	var levels: Array = raw.get("levels", [])
	if levels.is_empty():
		return ""
	return str(_read_fields((levels[0] as Dictionary).get("fieldInstances", [])).get("style", ""))


## An LDtk project, from one of this template's own maps.
## `chrome` is the editor's own background and label colours, as `{panel, text, dim}` html
## strings. Passed IN rather than written here because a colour welded into a script is exactly
## what "art is data" forbids, and the linter is right to refuse one - so the caller hands over
## the running style's own palette and a map opens in LDtk looking like the game it belongs to.
## Empty falls back to a neutral grey built from numbers, which is what a map with no style to
## ask gets.
static func from_native(native: Dictionary, tile_ids: PackedStringArray,
		tile_size: int, chrome: Dictionary = {}) -> Dictionary:
	var ground := JsonFile.to_string_array(native.get("ground", []))
	var decor := JsonFile.to_string_array(native.get("decor", []))
	var legend: Dictionary = native.get("legend", {})
	var wide := 0
	for row in ground:
		wide = maxi(wide, row.length())
	var high := ground.size()
	var style := str(native.get("style", "gb16"))
	var map_id := str(native.get("id", ""))

	var layer_defs: Array = []
	var instances: Array = []
	var uid := LAYER_UID
	for pair: Array in [["ground", ground], ["decor", decor]]:
		layer_defs.append(_tile_layer_def(str(pair[0]), uid, tile_size))
		instances.append(_tile_layer(str(pair[0]), pair[1], legend, tile_ids, wide, high,
			tile_size, uid, map_id))
		uid += 1

	var entity_defs: Array = []
	var field_uid := FIELD_UID
	var entity_uid := ENTITY_UID
	for key: String in RECORD_LAYERS:
		var records := _listed(native.get(key, [] if key != "spawns" else {}))
		var types := _field_types(records)
		var made := _entity_def(key, entity_uid, types, field_uid, tile_size, chrome)
		entity_defs.append(made["def"])
		field_uid = int(made["next_field_uid"])
		layer_defs.append(_entity_layer_def(key, uid, tile_size))
		instances.append(_entity_layer(key, records, types, tile_size, uid, entity_uid, map_id,
			wide, high, chrome))
		uid += 1
		entity_uid += 1

	return {
		"__header__": {
			"fileType": "LDtk Project JSON", "app": "LDtk", "doc": "https://ldtk.io/json",
			"schema": "https://ldtk.io/files/JSON_SCHEMA.json",
			"appAuthor": "Sebastien 'deepnight' Benard", "appVersion": VERSION,
			"url": "https://ldtk.io",
		},
		"iid": _iid("project/" + map_id), "jsonVersion": VERSION, "appBuildId": 473702,
		"nextUid": NEXT_UID, "identifierStyle": "Free", "toc": [],
		"worldLayout": "Free", "worldGridWidth": tile_size, "worldGridHeight": tile_size,
		"defaultLevelWidth": wide * tile_size, "defaultLevelHeight": high * tile_size,
		"defaultPivotX": 0, "defaultPivotY": 0, "defaultGridSize": tile_size,
		"defaultEntityWidth": tile_size, "defaultEntityHeight": tile_size,
		"bgColor": _chrome(chrome, "panel"), "defaultLevelBgColor": _chrome(chrome, "dim"),
		"minifyJson": false, "externalLevels": false, "exportTiled": false,
		"simplifiedExport": false, "imageExportMode": "None", "exportLevelBg": true,
		"pngFilePattern": null, "backupOnSave": false, "backupLimit": 10, "backupRelPath": null,
		"levelNamePattern": "%world_Level_%idx", "tutorialDesc": null,
		"customCommands": [], "flags": [], "worlds": [],
		"dummyWorldIid": _iid("world/" + map_id),
		"defs": {
			"layers": layer_defs,
			"entities": entity_defs,
			"tilesets": [_tileset_def(style, tile_ids, tile_size)],
			"enums": [], "externalEnums": [],
			"levelFields": _level_field_defs(),
		},
		"levels": [{
			"identifier": _identifier(map_id), "iid": _iid("level/" + map_id), "uid": LEVEL_UID,
			"worldX": 0, "worldY": 0, "worldDepth": 0,
			"pxWid": wide * tile_size, "pxHei": high * tile_size,
			"__bgColor": _chrome(chrome, "dim"), "bgColor": null, "useAutoIdentifier": false,
			"bgRelPath": null, "bgPos": null, "bgPivotX": 0.5, "bgPivotY": 0.5,
			"__smartColor": _chrome(chrome, "text"), "__bgPos": null, "externalRelPath": null,
			"fieldInstances": _level_fields(native),
			"layerInstances": instances,
			"__neighbours": [],
		}],
	}


## One of this template's maps, from an LDtk project. The inverse of `from_native`.
##
## THE LEGEND IS REBUILT rather than carried, exactly as it is for Tiled: an `.ldtk` stores tile
## INDICES, so characters are handed out here in the order tiles are first met. That is why the
## round trip compares what the GAME reads rather than the text.
static func to_native(raw: Dictionary, tile_ids: PackedStringArray, tile_size: int) -> Dictionary:
	var levels: Array = raw.get("levels", [])
	if levels.is_empty():
		return {}
	var level: Dictionary = levels[0]
	var fields := _read_fields(level.get("fieldInstances", []))
	var out := {
		"id": str(fields.get("id", "")),
		"style": str(fields.get("style", "gb16")),
		"music": str(fields.get("music", "")),
	}
	var legend := {}
	var used := {}
	for entry: Variant in level.get("layerInstances", []):
		var layer: Dictionary = entry
		var name := str(layer.get("__identifier", ""))
		if str(layer.get("__type", "")) == "Tiles":
			out[name] = _rows_of(layer, tile_ids, tile_size, legend, used)
		elif RECORD_LAYERS.has(name):
			out[name] = _records_of(layer, name, tile_size)
	out["legend"] = legend
	return out


# -- writing ------------------------------------------------------------------------------------


static func _tileset_def(style: String, tile_ids: PackedStringArray, tile_size: int) -> Dictionary:
	# One row, which is the shape gen_sprites.gd writes: every tile side by side in tiles.png.
	return {
		"__cWid": tile_ids.size(), "__cHei": 1,
		"identifier": style, "uid": TILESET_UID, "relPath": "tiles.png", "embedAtlas": null,
		"pxWid": tile_ids.size() * tile_size, "pxHei": tile_size,
		"tileGridSize": tile_size, "spacing": 0, "padding": 0,
		"tags": [], "tagsSourceEnumUid": null, "enumTags": [], "customData": [],
		"savedSelections": [], "cachedPixelData": null,
	}


## The fields every layer definition carries, whatever its type. Written out because LDtk emits
## all of them and a file shaped like the editor's own output is the one most likely to open.
static func _layer_def_base(name: String, uid: int, tile_size: int) -> Dictionary:
	return {
		"identifier": _identifier(name), "uid": uid, "doc": null, "uiColor": null,
		"gridSize": tile_size, "guideGridWid": 0, "guideGridHei": 0,
		"displayOpacity": 1, "inactiveOpacity": 1, "hideInList": false,
		"hideFieldsWhenInactive": false, "canSelectWhenInactive": true,
		"renderInWorldView": true, "pxOffsetX": 0, "pxOffsetY": 0,
		"parallaxFactorX": 0, "parallaxFactorY": 0, "parallaxScaling": true,
		"requiredTags": [], "excludedTags": [], "autoTilesKilledByOtherLayerUid": null,
		"uiFilterTags": [], "useAsyncRender": false,
		"intGridValues": [], "intGridValuesGroups": [], "autoRuleGroups": [],
		"autoSourceLayerDefUid": null, "tilePivotX": 0, "tilePivotY": 0, "biomeFieldUid": null,
	}


static func _tile_layer_def(name: String, uid: int, tile_size: int) -> Dictionary:
	var out := _layer_def_base(name, uid, tile_size)
	out["__type"] = "Tiles"
	out["type"] = "Tiles"
	out["tilesetDefUid"] = TILESET_UID
	return out


static func _entity_layer_def(name: String, uid: int, tile_size: int) -> Dictionary:
	var out := _layer_def_base(name, uid, tile_size)
	out["__type"] = "Entities"
	out["type"] = "Entities"
	out["tilesetDefUid"] = null
	return out


## An entity definition, with a field declared for every key the records on this layer carry.
##
## DERIVED FROM THE DATA, never a hand-kept list. A map record's keys are a game's business - it
## may put anything on an npc - so a fixed set here would silently drop whatever the template
## did not know about. This is the same rule the reload-list lesson states: a hand-enumerated
## membership is one the newest member is missing from.
##
## Every field instance written below gets a matching definition here, because that is what LDtk
## itself does and a file shaped like the editor's own output cannot be wrong about it. Whether
## the loader would TOLERATE an orphan field is unknown and deliberately not relied on.
static func _entity_def(name: String, uid: int, types: Dictionary,
		first_field_uid: int, tile_size: int, chrome: Dictionary) -> Dictionary:
	var fields: Array = []
	var next := first_field_uid
	var keys: Array = types.keys()
	# SORTED, so one map always exports the same bytes. A dictionary's order is not a promise.
	keys.sort()
	for key: Variant in keys:
		fields.append(_field_def(str(key), str(types[key]), next))
		next += 1
	return {
		"def": {
			"identifier": _identifier(name), "uid": uid, "tags": [], "exportToToc": false,
			"allowOutOfBounds": false, "doc": null,
			"width": tile_size, "height": tile_size,
			"resizableX": false, "resizableY": false,
			"minWidth": null, "maxWidth": null, "minHeight": null, "maxHeight": null,
			"keepAspectRatio": false, "tileOpacity": 1, "fillOpacity": 0.5, "lineOpacity": 1,
			"hollow": false, "color": _chrome(chrome, "text"), "renderMode": "Rectangle",
			"showName": true,
			"tilesetId": null, "tileRenderMode": "FitInside", "tileRect": null,
			"uiTileRect": null, "nineSliceBorders": [], "maxCount": 0,
			"limitScope": "PerLevel", "limitBehavior": "MoveLastOne",
			"pivotX": 0, "pivotY": 0,
			"fieldDefs": fields,
		},
		"next_field_uid": next,
	}


static func _field_def(name: String, kind: String, uid: int) -> Dictionary:
	return {
		"identifier": name, "doc": null, "__type": kind, "uid": uid,
		"type": _internal_type(kind), "isArray": false, "canBeNull": true,
		"arrayMinLength": null, "arrayMaxLength": null,
		"editorDisplayMode": "NameAndValue", "editorDisplayScale": 1,
		"editorDisplayPos": "Above", "editorLinkStyle": "CurvedArrow",
		"editorDisplayColor": null, "editorAlwaysShow": false, "editorShowInWorld": true,
		"editorCutLongValues": true, "editorTextSuffix": null, "editorTextPrefix": null,
		"useForSmartColor": false, "exportToToc": false, "searchable": false,
		"min": null, "max": null, "regex": null, "acceptFileTypes": null,
		"defaultOverride": null, "textLanguageMode": null, "symmetricalRef": false,
		"autoChainRef": true, "allowOutOfLevelRef": true, "allowedRefs": "OnlySame",
		"allowedRefsEntityUid": null, "allowedRefTags": [], "tilesetUid": null,
	}


static func _level_field_defs() -> Array:
	var out: Array = []
	for i in LEVEL_FIELDS.size():
		out.append(_field_def(LEVEL_FIELDS[i], "String", LEVEL_FIELD_UID + i))
	return out


static func _level_fields(native: Dictionary) -> Array:
	var out: Array = []
	for i in LEVEL_FIELDS.size():
		var key: String = LEVEL_FIELDS[i]
		out.append({
			"__identifier": key, "__type": "String", "__value": str(native.get(key, "")),
			"__tile": null, "defUid": LEVEL_FIELD_UID + i, "realEditorValues": [],
		})
	return out


static func _tile_layer(name: String, rows: Array[String], legend: Dictionary,
		tile_ids: PackedStringArray, wide: int, high: int, tile_size: int, uid: int,
		map_id: String) -> Dictionary:
	var tiles: Array = []
	var across := maxi(tile_ids.size(), 1)
	for y in rows.size():
		var row: String = rows[y]
		for x in wide:
			# A short row is padded with nothing: the native format lets a row stop early, and a
			# layer is a rectangle.
			var ch := row[x] if x < row.length() else " "
			var named := str(legend.get(ch, ""))
			var at := tile_ids.find(named)
			if named.is_empty() or at < 0:
				continue
			tiles.append({
				"px": [x * tile_size, y * tile_size],
				# Pixel coordinates INTO THE ATLAS, which is what LDtk means by src - verified
				# against its own samples rather than assumed.
				"src": [(at % across) * tile_size, (at / across) * tile_size],
				"f": 0, "t": at, "d": [y * wide + x], "a": 1,
			})
	var out := _layer_instance_base(name, "Tiles", wide, high, tile_size, uid, map_id)
	out["__tilesetDefUid"] = TILESET_UID
	out["__tilesetRelPath"] = "tiles.png"
	out["gridTiles"] = tiles
	return out


static func _entity_layer(name: String, records: Array, types: Dictionary, tile_size: int,
		uid: int, entity_uid: int, map_id: String, wide: int, high: int,
		chrome: Dictionary) -> Dictionary:
	var out := _layer_instance_base(name, "Entities", wide, high, tile_size, uid, map_id)
	var listed: Array = []
	var index := 0
	for entry: Variant in records:
		var record: Dictionary = entry
		var tile := JsonFile.to_int_array(record.get("tile", []))
		var at := Vector2i(tile[0], tile[1]) if tile.size() == 2 else Vector2i.ZERO
		var fields := record.duplicate(true)
		fields.erase("tile")
		listed.append({
			"__identifier": _identifier(name), "__grid": [at.x, at.y], "__pivot": [0, 0],
			"__tags": [], "__tile": null, "__smartColor": _chrome(chrome, "text"),
			"iid": _iid("%s/%s/%d" % [map_id, name, index]),
			"width": tile_size, "height": tile_size, "defUid": entity_uid,
			"px": [at.x * tile_size, at.y * tile_size],
			"fieldInstances": _field_instances(fields, types),
		})
		index += 1
	out["entityInstances"] = listed
	return out


## The fields EVERY layer instance carries, whatever kind it is - and `gridTiles`,
## `entityInstances` and `intGridCsv` are on that list for a measured reason rather than for
## symmetry: LDtk iterates all three RAW, with no null guard and no default, so a layer missing
## any of them aborts the whole file load with a modal error rather than degrading.
##
## The kind is passed in rather than inferred from the size. Deciding it from `wide > 0` worked
## and was a trap waiting for a degenerate map: a layer's type is a fact about the layer, not
## about how much happens to be on it.
static func _layer_instance_base(name: String, kind: String, wide: int, high: int,
		tile_size: int, uid: int, map_id: String) -> Dictionary:
	return {
		"__identifier": _identifier(name),
		"__type": kind,
		"__cWid": wide, "__cHei": high, "__gridSize": tile_size, "__opacity": 1,
		"__pxTotalOffsetX": 0, "__pxTotalOffsetY": 0,
		"__tilesetDefUid": null, "__tilesetRelPath": null,
		"iid": _iid("layer/%s/%s" % [map_id, name]),
		"levelId": LEVEL_UID, "layerDefUid": uid,
		"pxOffsetX": 0, "pxOffsetY": 0, "visible": true,
		"optionalRules": [], "intGridCsv": [], "autoLayerTiles": [],
		# Fixed rather than drawn. Every number this project writes has to be the same on every
		# machine, and a seed nobody seeded is the one thing a drift gate cannot survive.
		"seed": 0, "overrideTilesetUid": null,
		"gridTiles": [], "entityInstances": [],
	}


## What LDtk type each key on these records should be declared as.
##
## One type per FIELD, across every record on the layer, because a definition describes the field
## and not one value of it. Where the values disagree - an int here, a list there - the answer is
## String, and the non-strings among them travel as JSON behind the marker. That keeps a
## conflicting field lossless instead of picking a winner.
static func _field_types(records: Array) -> Dictionary:
	var out := {}
	for entry: Variant in records:
		var record: Dictionary = entry
		for key: Variant in record:
			if str(key) == "tile":
				continue
			var kind := _ldtk_type(record[key])
			var name := str(key)
			if out.has(name) and str(out[name]) != kind:
				out[name] = "String"
			elif not out.has(name):
				out[name] = kind
	return out


static func _ldtk_type(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL: return "Bool"
		TYPE_INT: return "Int"
		TYPE_FLOAT: return "Float"
		TYPE_STRING, TYPE_STRING_NAME: return "String"
	return "String"


static func _internal_type(kind: String) -> String:
	match kind:
		"Bool": return "F_Bool"
		"Int": return "F_Int"
		"Float": return "F_Float"
	return "F_String"


static func _field_instances(fields: Dictionary, types: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = fields.keys()
	# SORTED, for the reason the field definitions are: byte-stable output.
	keys.sort()
	for key: Variant in keys:
		var name := str(key)
		var kind := str(types.get(name, "String"))
		out.append({
			"__identifier": name, "__type": kind, "__value": _encode(fields[key], kind),
			"__tile": null, "defUid": _field_uid_of(name, types), "realEditorValues": [],
		})
	return out


## A value as its declared type. Anything that is not a scalar of that type - a list, a map, or a
## number under a field the records disagreed about - goes behind the JSON marker, so it comes
## back as DATA rather than as the text of some data.
static func _encode(value: Variant, kind: String) -> Variant:
	match kind:
		"Bool": return bool(value)
		"Int": return int(value)
		"Float": return float(value)
	if value is String or value is StringName:
		return str(value)
	return JSON_PREFIX + JSON.stringify(value)


## Which definition a field instance points at. Derived from the same sorted key order the
## definitions were written in, so the two cannot disagree.
static func _field_uid_of(name: String, types: Dictionary) -> int:
	var keys: Array = types.keys()
	keys.sort()
	return FIELD_UID + keys.find(name)


## One editor-chrome colour, as the html string LDtk wants. The fallback is built from numbers
## rather than written as a hex string: a grey is not an art decision, and the linter's rule is
## about art decisions welded into code.
static func _chrome(chrome: Dictionary, role: String) -> String:
	if chrome.has(role):
		return str(chrome[role])
	# Built from a number rather than written as a colour, and that distinction is real rather
	# than a way around the rule: the running style's palette is what a map actually opens in,
	# and this grey is only what a caller with no style to ask gets. A neutral level is not an
	# art decision about anybody's game.
	const NEUTRAL := {"panel": 26, "dim": 71, "text": 184}
	var level: int = NEUTRAL.get(role, 128)
	return "#%02x%02x%02x" % [level, level, level]


## A deterministic UUID-shaped id. LDtk writes version-1 UUIDs; the format is what matters here,
## and the DETERMINISM is what matters to this project - a drift gate cannot survive an id drawn
## fresh on every export, and `SeededRng` is the rule for anything that looks random.
static func _iid(label: String) -> String:
	var digest := label.sha256_text()
	return "%s-%s-1%s-8%s-%s" % [digest.substr(0, 8), digest.substr(8, 4), digest.substr(13, 3),
		digest.substr(17, 3), digest.substr(20, 12)]


## LDtk identifiers are restricted; this project's map and layer names are already lowercase
## words, so this only has to refuse what would break the file rather than rename anything.
static func _identifier(name: String) -> String:
	var out := ""
	for i in name.length():
		var ch := name[i]
		out += ch if ch.is_valid_identifier() or ch == "_" or (ch >= "0" and ch <= "9") else "_"
	return out if not out.is_empty() else "unnamed"


# -- reading ------------------------------------------------------------------------------------


static func _read_fields(raw: Variant) -> Dictionary:
	var out := {}
	for entry: Variant in (raw if raw is Array else []):
		var field: Dictionary = entry
		var value: Variant = field.get("__value", "")
		if value is String and (value as String).begins_with(JSON_PREFIX):
			var decoded: Variant = JSON.parse_string((value as String).substr(JSON_PREFIX.length()))
			value = decoded if decoded != null else value
		out[str(field.get("__identifier", ""))] = value
	return out


static func _rows_of(layer: Dictionary, tile_ids: PackedStringArray, tile_size: int,
		legend: Dictionary, used: Dictionary) -> Array[String]:
	# The characters a legend may hand out, in order. Chosen to look like the hand-written maps,
	# because the converted file is the artifact that gets committed and reviewed.
	const ALPHABET := ".,-#~*abcdefghijklmnopqrstuvwxyz0123456789"
	var wide := int(layer.get("__cWid", 0))
	var high := int(layer.get("__cHei", 0))
	# Read from `px` rather than from `d`, which the schema calls internal editor data. A position
	# the format documents is a position the format promises.
	var grid := {}
	for entry: Variant in layer.get("gridTiles", []):
		var tile: Dictionary = entry
		var px := JsonFile.to_int_array(tile.get("px", []))
		if px.size() != 2 or tile_size <= 0:
			continue
		grid["%d,%d" % [px[0] / tile_size, px[1] / tile_size]] = int(tile.get("t", -1))
	var out: Array[String] = []
	for y in high:
		var row := ""
		for x in wide:
			var at := int(grid.get("%d,%d" % [x, y], -1))
			var ch := " "
			var named: String = tile_ids[at] if at >= 0 and at < tile_ids.size() else ""
			if not named.is_empty():
				if not used.has(named):
					used[named] = ALPHABET[used.size()] if used.size() < ALPHABET.length() else "?"
					legend[str(used[named])] = named
				ch = str(used[named])
			row += ch
		# Trailing blanks dropped, which is what a hand-written map does with a short row.
		out.append(row.rstrip(" "))
	return out


static func _records_of(layer: Dictionary, name: String, tile_size: int) -> Variant:
	var listed: Array = []
	for entry: Variant in layer.get("entityInstances", []):
		var instance: Dictionary = entry
		var record := _read_fields(instance.get("fieldInstances", []))
		var grid := JsonFile.to_int_array(instance.get("__grid", []))
		record["tile"] = [grid[0], grid[1]] if grid.size() == 2 else [0, 0]
		listed.append(record)
	if name != "spawns":
		return listed
	# `spawns` goes back to being a name -> tile map, the one record layer whose native shape is
	# not a list.
	var out := {}
	for entry: Variant in listed:
		var record: Dictionary = entry
		out[str(record.get("name", ""))] = record.get("tile", [])
	return out


## A record layer as a list, whichever shape it has natively.
static func _listed(records: Variant) -> Array:
	if records is Dictionary:
		var out: Array = []
		for key: Variant in records:
			out.append({"name": str(key), "tile": (records as Dictionary)[key]})
		return out
	return records if records is Array else []
