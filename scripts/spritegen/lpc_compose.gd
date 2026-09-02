class_name LpcCompose
extends RefCounted
## Composes a Universal LPC character from a RECIPE the way the generator's browser does, so a
## hero can be authored as text and rebuilt without a browser.
##
## The generator (see LpcImport) is a catalogue of layers, each a definition JSON under
## sheet_definitions/ naming one art path PER BODY TYPE and a draw order (zPos), plus a palette
## scheme under palette_definitions/. Everything here is that catalogue's own contract, measured
## from its source (sources/state/path.ts, palettes.ts, PALETTE_RECOLOR_GUIDE.md):
##	 - a PALETTE item has one source file per animation, drawn in its material's BASE colour
##	   (skin "light", hair "orange", cloth "white", eyes "blue"); a colour variant is a remap of
##	   the base palette onto the target palette BY INDEX, matching a source pixel within +/-1
##	   per channel - the generator's own tolerance, not a looser one;
##	 - a FILE-VARIANT item has one file per colour, named after the variant with spaces as
##	   underscores;
##	 - lower zPos draws first; a head carries its skin AND its eyes, each on its own palette;
##	 - a layer with no path for the chosen body type is not drawable - REFUSED here by name,
##	   because the browser silently draws nothing and a headless character with a tunic on
##	   looks like a compositor bug rather than a catalogue fact.
##
## Pure: the plan is a function of the recipe, the definitions and the palettes; compose() is a
## function of the plan and the images. Fetching is the shell wrapper's business, and none of
## this is a gate - the two files it writes are the same two the browser would download, and
## LpcImport checks them exactly as it would those.

const SHEETS := "spritesheets/"
const WALK := "walk"
const FRAME := LpcImport.FRAME
const SHEET_WIDE := LpcImport.SHEET_COLUMNS * FRAME
const SHEET_ROWS := 54
const WALK_WIDE := LpcImport.WALK_FRAMES * FRAME
const WALK_TALL := 4 * FRAME
## Per channel, on 0-255 values: the generator's own matching rule.
const TOLERANCE := 1
## What a definition with no `animations` list covers - the original LPC set.
const CLASSIC_SIX: Array[String] = ["spellcast", "thrust", "walk", "slash", "shoot", "hurt"]
## The palette scheme every shipped material defaults to.
const PALETTE_VERSION := "ulpc"
const MATERIALS: Array[String] = ["body", "hair", "cloth", "eye"]


## Resolves a recipe against the catalogue. Returns {"problems": Array[String], "layers":
## Array (each {"def", "path", "z", "remaps", "credits", "order"}), "selections": Dictionary}.
##	 recipe:   {"id", "body_type", "layers": [{"def", "recolor"?, "variant"?, "eyes"?}, ...]}
##	 defs:	   def key -> the definition Dictionary (sheet_definitions/<key>.json)
##	 palettes: material -> {"base": String, "variants": {name: [hex, ...]}}
static func plan(recipe: Dictionary, defs: Dictionary, palettes: Dictionary, style: SpriteStyle) -> Dictionary:
	var problems: Array[String] = []
	var layers: Array = []
	var selections: Dictionary = {}
	var body_type := str(recipe.get("body_type", ""))
	if body_type.is_empty():
		problems.append("recipe names no body_type")
	var wanted: Variant = recipe.get("layers", [])
	if not wanted is Array or (wanted as Array).is_empty():
		problems.append("recipe has no layers")
		return {"problems": problems, "layers": layers, "selections": selections}

	var order := 0
	for entry: Variant in wanted as Array:
		if not entry is Dictionary:
			problems.append("a recipe layer is not an object")
			continue
		var want: Dictionary = entry
		var key := str(want.get("def", ""))
		if not defs.has(key):
			problems.append("no definition for '%s' (expected sheet_definitions/%s.json)" % [key, key])
			continue
		var d: Dictionary = defs[key]
		if not _covers_walk(d):
			problems.append("'%s' has no walk animation; it covers %s" % [key, d.get("animations")])
			continue

		var variant_file := ""
		var variants := JsonFile.to_string_array(d.get("variants", []))
		if not variants.is_empty():
			var variant := str(want.get("variant", ""))
			if variant.is_empty():
				problems.append("'%s' comes in %d colours and the recipe picks none: %s" % [key, variants.size(), variants])
				continue
			if not variants.has(variant):
				problems.append("'%s' has no variant '%s'; choose from %s" % [key, variant, variants])
				continue
			variant_file = variant.replace(" ", "_")

		var remaps := _remaps_for(key, d, want, palettes, problems)
		var type_name := str(d.get("type_name", key.get_file()))
		selections[type_name] = {
			"itemId": key.get_file(),
			"name": str(d.get("name", key.get_file())),
			"variant": want.get("variant", null),
			"recolor": want.get("recolor", null),
		}

		for layer_key in _layer_keys(d):
			var layer: Dictionary = d[layer_key]
			var base_path := str(layer.get(body_type, ""))
			if base_path.is_empty():
				var drawn: Array = layer.keys().filter(func(k: Variant) -> bool: return str(k) != "zPos")
				problems.append("'%s' (%s) has no art for body type '%s'; it draws %s" % [key, layer_key, body_type, drawn])
				continue
			var path := SHEETS + base_path + WALK
			if not variant_file.is_empty():
				path += "/" + variant_file
			path += ".png"
			var credits := _credits_for(d, path)
			for c: Dictionary in credits:
				var licenses := JsonFile.to_string_array(c["licenses"])
				var allowed := false
				for l in licenses:
					if LpcImport.license_allowed(l, style):
						allowed = true
				if not allowed:
					problems.append("'%s' is licensed %s; style '%s' accepts %s" % [c["file"], licenses, style.id, style.licenses])
			layers.append({
				"def": key,
				"path": path,
				"z": int(layer.get("zPos", 100)),
				"remaps": remaps,
				"credits": credits,
				"order": order,
			})
			order += 1
	return {"problems": problems, "layers": layers, "selections": selections}


## The files a plan needs, unique and sorted - what the wrapper fetches.
static func files_of(planned: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for layer: Dictionary in planned.get("layers", []) as Array:
		var p := str(layer["path"])
		if not out.has(p):
			out.append(p)
	out.sort()
	return out


## Draws the plan onto a full-size universal sheet: every layer's walk file, remapped, blended
## in zPos order into rows 8-11. images: path -> Image. Returns {"image", "problems"}.
static func compose(planned: Dictionary, images: Dictionary) -> Dictionary:
	var problems: Array[String] = []
	var canvas := Image.create_empty(SHEET_WIDE, SHEET_ROWS * FRAME, false, Image.FORMAT_RGBA8)
	var layers: Array = (planned.get("layers", []) as Array).duplicate()
	# Lower zPos first; ties keep recipe order, because sort_custom is not stable.
	layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["z"]) != int(b["z"]):
			return int(a["z"]) < int(b["z"])
		return int(a["order"]) < int(b["order"]))
	for layer: Dictionary in layers:
		var path := str(layer["path"])
		var img: Image = images.get(path)
		if img == null:
			problems.append("no image for %s" % path)
			continue
		if img.get_height() != WALK_TALL or img.get_width() % FRAME != 0:
			problems.append("%s is %s; a walk file is %d rows of %dpx frames" % [path, img.get_size(), 4, FRAME])
			continue
		var painted := remapped(img, layer["remaps"])
		var wide := mini(painted.get_width(), WALK_WIDE)
		# blend, not blit: a shirt over a body must keep the body where the shirt is transparent.
		canvas.blend_rect(painted, Rect2i(0, 0, wide, WALK_TALL), Vector2i(0, LpcImport.WALK_ROW * FRAME))
	return {"image": canvas, "problems": problems}


## The generator's export document for what was composed: what LpcImport reads (credits), what
## the browser would carry (bodyType, selections, layers), and what nobody else writes - the
## recipe, so the file says how it was made.
static func export_json(recipe: Dictionary, planned: Dictionary) -> Dictionary:
	var by_file: Dictionary = {}
	var layers_out: Array = []
	for layer: Dictionary in planned.get("layers", []) as Array:
		layers_out.append({"def": layer["def"], "path": layer["path"], "zPos": layer["z"]})
		for c: Dictionary in layer["credits"]:
			if not by_file.has(c["file"]):
				by_file[c["file"]] = c
	var files: Array = by_file.keys()
	files.sort()
	var credits: Array = []
	for f: Variant in files:
		credits.append(by_file[f])
	return {
		"version": 2,
		"bodyType": str(recipe.get("body_type", "")),
		"selections": planned.get("selections", {}),
		"layers": layers_out,
		"credits": credits,
		"generatedBy": "tools/lpc_compose.gd",
		"recipe": recipe,
	}


## A copy of `img` with every remap applied: a pixel within TOLERANCE of a source colour takes
## the target colour at the same index, keeping its own alpha. First matching remap wins.
static func remapped(img: Image, remaps: Array) -> Image:
	var out := img.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	if remaps.is_empty():
		return out
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var hit := false
			for remap: Dictionary in remaps:
				var from: Array = remap["from"]
				var to: Array = remap["to"]
				for i in from.size():
					if _near(c, from[i]):
						var t: Color = to[i]
						out.set_pixel(x, y, Color(t.r, t.g, t.b, c.a))
						hit = true
						break
				if hit:
					break
	return out


static func _near(a: Color, b: Color) -> bool:
	return absi(a.r8 - b.r8) <= TOLERANCE and absi(a.g8 - b.g8) <= TOLERANCE and absi(a.b8 - b.b8) <= TOLERANCE


static func _covers_walk(d: Dictionary) -> bool:
	var anims: Variant = d.get("animations", null)
	if anims == null:
		return true	 # the classic six, walk among them
	if not anims is Array:
		return false
	return JsonFile.to_string_array(anims).has(WALK)


## "layer_1", "layer_2", ... in numeric order.
static func _layer_keys(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: Variant in d.keys():
		if str(k).begins_with("layer_"):
			out.append(str(k))
	out.sort_custom(func(a: String, b: String) -> bool:
		return int(a.trim_prefix("layer_")) < int(b.trim_prefix("layer_")))
	return out


## One remap per palette the definition declares: a single {"material"} block takes the
## recipe's `recolor`; a multi-colour block (color_1, color_2...) takes `recolor` for the
## material and `eyes` for the eye palette. No wish means the base colour and no remap.
static func _remaps_for(key: String, d: Dictionary, want: Dictionary, palettes: Dictionary,
		problems: Array[String]) -> Array:
	var out: Array = []
	var raw: Variant = d.get("recolors", null)
	if raw == null:
		return out
	var blocks: Array = []
	if raw is Dictionary and (raw as Dictionary).has("material"):
		blocks.append(raw)
	elif raw is Dictionary:
		for k: Variant in (raw as Dictionary).keys():
			if (raw as Dictionary)[k] is Dictionary:
				blocks.append((raw as Dictionary)[k])
	elif raw is Array:
		for b: Variant in raw as Array:
			if b is Dictionary:
				blocks.append(b)
	for block: Dictionary in blocks:
		var material := str(block.get("material", ""))
		var slot := "eyes" if str(block.get("type_name", "")) == "eyes" or material == "eye" else "recolor"
		var wish := str(want.get(slot, ""))
		if wish.is_empty():
			continue
		if not palettes.has(material):
			problems.append("'%s' recolours by the '%s' palette, which was not loaded" % [key, material])
			continue
		var palette: Dictionary = palettes[material]
		var variants: Dictionary = palette.get("variants", {})
		# A definition may be DRAWN in something other than its material's base variant - the
		# lizard head is green, the zombie's is grey-green, the fur heads are brown - and says
		# so with its own `base`. Remapping those from the material's default would take human
		# skin tones as the source, find almost none of them in the art, and change almost
		# nothing: a recolour that silently does not happen rather than one that fails.
		var base := str(palette.get("base", ""))
		var stated := str(block.get("base", ""))
		if not stated.is_empty():
			var parts := stated.split(".", false)
			var scheme := parts[0] if parts.size() > 1 else PALETTE_VERSION
			if scheme != PALETTE_VERSION:
				problems.append("'%s' is drawn in the '%s' palette scheme, which this composer does not fetch" % [key, scheme])
				continue
			base = parts[parts.size() - 1]
		if not variants.has(wish):
			var names: Array = variants.keys()
			names.sort()
			problems.append("'%s' is not a %s colour for '%s'; choose from %s" % [wish, material, key, names])
			continue
		if wish == base:
			continue
		var from := _colors(variants.get(base, []))
		var to := _colors(variants[wish])
		if from.is_empty() or from.size() != to.size():
			problems.append("%s palette '%s' has %d tones where the base '%s' has %d" % [material, wish, to.size(), base, from.size()])
			continue
		out.append({"from": from, "to": to})
	return out


static func _colors(raw: Variant) -> Array:
	var out: Array = []
	for hex in JsonFile.to_string_array(raw):
		out.append(Color(hex))
	return out


## The credits that apply to one used file: the definition's entries whose `file` is a prefix
## of the path (the generator's rule), or every entry when none is - conservative, never fewer.
static func _credits_for(d: Dictionary, path: String) -> Array:
	var rel := path.trim_prefix(SHEETS)
	var all: Array = []
	var matching: Array = []
	for entry: Variant in d.get("credits", []) as Array:
		if not entry is Dictionary:
			continue
		var e: Dictionary = entry
		var c := {
			"file": str(e.get("file", "")),
			"authors": JsonFile.to_string_array(e.get("authors", [])),
			"licenses": JsonFile.to_string_array(e.get("licenses", [])),
			"urls": JsonFile.to_string_array(e.get("urls", [])),
			"notes": str(e.get("notes", "")),
		}
		all.append(c)
		if not str(c["file"]).is_empty() and rel.begins_with(str(c["file"])):
			matching.append(c)
	return matching if not matching.is_empty() else all
