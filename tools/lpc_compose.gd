extends SceneTree
## Composes an LPC character from a recipe, out of layer files already fetched into a cache.
##
##	   Godot --headless --path . -s tools/lpc_compose.gd --recipe=<file> --list
##	   Godot --headless --path . -s tools/lpc_compose.gd --recipe=<file> --out=<dir> [--preview=<png>]
##
## Run it through tools/lpc_compose.sh, which fetches what --list names and then calls this
## again to compose. The thin half of LpcCompose: arguments, files, and the two outputs the
## browser would have downloaded - sheet.png and character.json - plus the recipe beside them.
## --preview writes a 2x strip of the four directions THROUGH LpcImport.build, so what is
## looked at is exactly what the game will load. Every flag is `--flag=value`; the space form
## is refused out loud (the map_io rule).

const CACHE_DEFAULT := "res://build/lpc"
const STYLE_DIR := "res://data/styles"
const DEFS := "sheet_definitions"
const PALETTES := "palette_definitions"
const FLAGS: Array[String] = ["--recipe", "--cache", "--out", "--preview", "--list"]

var _recipe_path := ""
var _cache := CACHE_DEFAULT
var _out := ""
var _preview := ""
var _list := false


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	var recipe_file := JsonFile.read(_recipe_path)
	if not recipe_file.ok:
		_fail(recipe_file.error)
		return
	var recipe: Dictionary = recipe_file.data
	var style_id := str(recipe.get("style", "lpc32"))
	var style := load("%s/%s.tres" % [STYLE_DIR, style_id]) as SpriteStyle
	if style == null:
		_fail("no style '%s' under %s" % [style_id, STYLE_DIR])
		return

	var defs := _load_defs(recipe)
	var palettes := _load_palettes()
	if defs.is_empty() or palettes.is_empty():
		return
	var planned := LpcCompose.plan(recipe, defs, palettes, style)
	var problems: Array[String] = planned["problems"]
	if not problems.is_empty():
		for p in problems:
			printerr("lpc_compose: " + p)
		quit(1)
		return

	if _list:
		for path in LpcCompose.files_of(planned):
			print(path)
		quit(0)
		return

	var images: Dictionary = {}
	for path in LpcCompose.files_of(planned):
		var img := ImageFile.read_png("%s/%s" % [_cache, path])
		if img == null:
			_fail("no %s in the cache; run tools/lpc_compose.sh, which fetches it" % path)
			return
		images[path] = img
	var composed := LpcCompose.compose(planned, images)
	var faults: Array[String] = composed["problems"]
	if not faults.is_empty():
		for p in faults:
			printerr("lpc_compose: " + p)
		quit(1)
		return
	var sheet: Image = composed["image"]
	var doc := LpcCompose.export_json(recipe, planned)
	var check := LpcImport.problems(sheet, doc, style)
	if not check.is_empty():
		for p in check:
			printerr("lpc_compose: the importer refuses what was composed: " + p)
		quit(1)
		return

	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
		var err := sheet.save_png(_out.path_join("sheet.png"))
		if err != OK:
			_fail("could not write sheet.png (error %d)" % err)
			return
		if JsonFile.write(_out.path_join("character.json"), doc) != OK or JsonFile.write(_out.path_join("recipe.json"), recipe) != OK:
			_fail("could not write beside sheet.png")
			return
		print("lpc_compose: wrote %s/{sheet.png, character.json, recipe.json}" % _out)
	if not _preview.is_empty():
		var built := LpcImport.build(sheet, doc, style, str(recipe.get("id", "preview")))
		var strip: Image = built["image"]
		strip.resize(strip.get_width() * 2, strip.get_height() * 2, Image.INTERPOLATE_NEAREST)
		var err := strip.save_png(_preview)
		if err != OK:
			_fail("could not write %s (error %d)" % [_preview, err])
			return
		print("lpc_compose: preview at %s" % _preview)
	quit(0)


func _parse_args() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var name := arg.get_slice("=", 0)
		if not FLAGS.has(name):
			continue
		if name != "--list" and not arg.contains("="):
			printerr("lpc_compose: write %s=<value>; the space form leaves the value in a positional slot" % name)
			return false
		var value := arg.get_slice("=", 1)
		match name:
			"--recipe":
				_recipe_path = _resolve(value)
			"--cache":
				_cache = _resolve(value)
			"--out":
				_out = _resolve(value)
			"--preview":
				_preview = _resolve(value)
			"--list":
				_list = true
	if _recipe_path.is_empty():
		printerr("lpc_compose: --recipe=<file> is required")
		return false
	if not _list and _out.is_empty() and _preview.is_empty():
		printerr("lpc_compose: nothing to do - give --out=<dir>, --preview=<png> or --list")
		return false
	return true


## A relative path is relative to the project, the way map_io reads one.
func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return "res://" + path


func _load_defs(recipe: Dictionary) -> Dictionary:
	var defs: Dictionary = {}
	for entry: Variant in recipe.get("layers", []) as Array:
		if not entry is Dictionary:
			continue
		var key := str((entry as Dictionary).get("def", ""))
		if key.is_empty() or defs.has(key):
			continue
		var file := JsonFile.read("%s/%s/%s.json" % [_cache, DEFS, key])
		if not file.ok:
			_fail("no definition for '%s' in the cache (%s); run tools/lpc_compose.sh" % [key, file.error])
			return {}
		defs[key] = file.data
	if defs.is_empty():
		_fail("the recipe names no layers")
	return defs


## material -> {"base", "variants"} for the four shipped materials, from the ulpc scheme each
## defaults to.
func _load_palettes() -> Dictionary:
	var out: Dictionary = {}
	for material in LpcCompose.MATERIALS:
		var meta := JsonFile.read("%s/%s/%s/meta_%s.json" % [_cache, PALETTES, material, material])
		var variants := JsonFile.read("%s/%s/%s/%s_%s.json" % [_cache, PALETTES, material, material, LpcCompose.PALETTE_VERSION])
		if not meta.ok or not variants.ok:
			_fail("palette '%s' is not in the cache; run tools/lpc_compose.sh" % material)
			return {}
		out[material] = {"base": str(meta.data.get("base", "")), "variants": variants.data}
	return out


func _fail(message: String) -> void:
	printerr("lpc_compose: " + message)
	quit(1)
