class_name ArtFixtures
extends RefCounted
## Loads the shipped styles, rigs and characters for the consistency gates.
##
## The gates run against the REAL data, not against a miniature fixture: a palette rule that
## only holds for a two-colour test style says nothing about the art the game ships. Loading
## every style also means adding a style automatically puts it under the same gates - a new
## palette cannot quietly opt out of the rules it is supposed to obey.
##
## These live here rather than inside a suite because gdUnit4's scanner crashes on a suite
## whose function signature names a project class; helpers can be typed normally.

const STYLE_DIR := "res://data/styles"
const RIG_DIR := "res://data/rigs"
const TILE_DIR := "res://data/tiles"
const CHARACTER_DIR := "res://data/characters"
const GENERATED_ROOT := "res://assets/generated"
const IMPORT_ROOT := "res://data/imports"
const IMPORT_SHEET := "sheet.png"


static func style_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for path in _files(STYLE_DIR, "tres"):
		var style := load(path) as SpriteStyle
		if style != null:
			out.append(style.id)
	by_text(out)
	return out


## Array[StringName].sort() orders by the interned POINTER, not the text - "sorted" ids came
## out as dusk16, nes16, lpc32, gb16. Every list of ids here goes through this instead.
static func by_text(ids: Array[StringName]) -> void:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


static func style(style_id: StringName) -> SpriteStyle:
	return load("%s/%s.tres" % [STYLE_DIR, style_id]) as SpriteStyle


## The styles whose sheets the rig composes - the only ones a consistency gate can draw a frame
## of. An imported style has no rig and is gated by test_imported_art.gd instead. The two lists
## are asserted to cover every style between them (test_gates_consistency), so a third kind of
## source cannot quietly opt out of both.
static func rig_style_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for style_id in style_ids():
		if not style(style_id).imports():
			out.append(style_id)
	return out


static func imported_style_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for style_id in style_ids():
		if style(style_id).imports():
			out.append(style_id)
	return out


## Every character an imported style has an input for: one folder per character under
## data/imports/<style>/, named by the character id, holding the generator's sheet.png.
static func imported_characters_of(style_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var exts: Array[String] = ["png"]
	for path in ContentScan.files("%s/%s" % [IMPORT_ROOT, style_id], exts):
		if path.get_file() == IMPORT_SHEET:
			out.append(StringName(path.get_base_dir().get_file()))
	by_text(out)
	return out


static func import_dir(style_id: StringName, character_id: StringName) -> String:
	return "%s/%s/%s" % [IMPORT_ROOT, style_id, character_id]


## Every committed sheet a style has, whichever arm made it - what a contract test over "the
## PNG + JSON pairs the game will load" must iterate, or imported sheets are silently outside it.
static func sheet_ids_of(style_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for spec in characters_of(style_id):
		out.append(spec.id)
	out.append_array(imported_characters_of(style_id))
	by_text(out)
	return out


static func rig_for(style_value: SpriteStyle) -> Rig:
	return Rig.load_from("%s/%s.json" % [RIG_DIR, style_value.rig_id])


static func tile_bank_for(style_value: SpriteStyle) -> TileBank:
	return TileBank.load_from("%s/%s.json" % [TILE_DIR, style_value.tile_bank_id])


## Every character that belongs to a style, in a stable order.
static func characters_of(style_id: StringName) -> Array[CharacterSpec]:
	var out: Array[CharacterSpec] = []
	for path in _files(CHARACTER_DIR, "tres"):
		var spec := load(path) as CharacterSpec
		if spec != null and spec.style_id == style_id:
			out.append(spec)
	out.sort_custom(func(a: CharacterSpec, b: CharacterSpec) -> bool: return String(a.id) < String(b.id))
	return out


## Every frame of every direction for one character, as flat images. The gates want to check
## all of them - a rule that holds for the front idle pose and fails on the fourth walk
## frame facing up is exactly the kind of drift nobody sees by looking.
static func all_frames(rig: Rig, style_value: SpriteStyle, spec: CharacterSpec) -> Array[Image]:
	var out: Array[Image] = []
	var resolved := spec.resolve(rig, style_value)
	for dir: int in Dir.ALL:
		for frame in style_value.walk_frames:
			out.append(SpriteCompositor.compose(rig, style_value, resolved, dir, frame))
	return out


static func generated_texture_path(style_id: StringName, character_id: StringName) -> String:
	return "%s/%s/%s.png" % [GENERATED_ROOT, style_id, character_id]


static func generated_meta_path(style_id: StringName, character_id: StringName) -> String:
	return "%s/%s/%s.sheet.json" % [GENERATED_ROOT, style_id, character_id]


## The gates must see exactly what the generator writes, so both walk through ContentScan.
## When these two disagreed, the gate's "every style, every character" was quietly a subset.
static func _files(dir_path: String, extension: String) -> Array[String]:
	return ContentScan.files_of(dir_path, extension)
