extends GdUnitTestSuite
## LpcCompose: a recipe against a synthetic catalogue becomes the sheet the browser would make,
## or is refused by name. The catalogue here is invented - two-colour layers, a three-tone
## palette - so every expectation is a literal the class under test cannot reach.

const SRC := ["#100000", "#200000", "#300000"]	 # a material's base palette
const DST := ["#000010", "#000020", "#000030"]	 # the variant the recipe wants

func _palettes() -> Dictionary:
	return {
		"cloth": {"base": "white", "variants": {"white": SRC, "navy": DST, "short": ["#000010"]}},
		"body": {"base": "light", "variants": {"light": SRC, "bronze": DST}},
		"eye": {"base": "blue", "variants": {"blue": SRC, "brown": DST}},
	}

func _style(licenses: Array = ["CC0", "CC-BY", "OGA-BY", "CC-BY-SA"]) -> SpriteStyle:
	var s := SpriteStyle.new()
	s.id = &"lab"
	s.sheets_from = SpriteStyle.SHEETS_FROM_LPC
	s.cell_size = Vector2i(64, 64)
	s.tile_size = 32
	s.rig_id = &""
	s.licenses = JsonFile.to_string_array(licenses)
	s.ramps = {"x": ["#000000", "#777777", "#ffffff"]}
	return s

func _shirt(licenses: Array = ["OGA-BY 3.0"]) -> Dictionary:
	return {"name": "Shirt", "type_name": "clothes",
		"recolors": {"material": "cloth", "palettes": ["ulpc"]},
		"layer_1": {"zPos": 35, "male": "torso/shirt/male/", "female": "torso/shirt/female/"},
		"animations": ["walk", "hurt"],
		"credits": [{"file": "torso/shirt/male", "authors": ["a"], "licenses": licenses, "urls": ["u"]},
			{"file": "torso/shirt/female", "authors": ["b"], "licenses": licenses, "urls": ["u"]}]}

func _tunic() -> Dictionary:
	return {"name": "Tunic", "type_name": "clothes", "variants": ["navy", "forest green"],
		"layer_1": {"zPos": 35, "female": "torso/tunic/female/"},
		"credits": [{"file": "torso/tunic", "authors": ["c"], "licenses": ["CC-BY-SA 3.0"], "urls": []}]}

func _hair() -> Dictionary:
	return {"name": "Ponytail", "type_name": "hair",
		"recolors": {"material": "cloth", "palettes": ["ulpc"]},
		"layer_1": {"zPos": 120, "male": "hair/pony/fg/"},
		"layer_2": {"zPos": 9, "male": "hair/pony/bg/"},
		"animations": ["walk"],
		"credits": [{"file": "hair/pony", "authors": ["d"], "licenses": ["CC0"], "urls": []}]}

func _head() -> Dictionary:
	return {"name": "Head", "type_name": "head",
		"recolors": {"color_1": {"material": "body", "palettes": ["ulpc"]},
			"color_2": {"type_name": "eyes", "material": "eye", "palettes": ["ulpc"]}},
		"layer_1": {"zPos": 100, "male": "head/human/male/"},
		"animations": ["walk"],
		"credits": [{"file": "head/human", "authors": ["e"], "licenses": ["CC-BY 4.0"], "urls": []}]}

func _defs() -> Dictionary:
	return {"shirt": _shirt(), "tunic": _tunic(), "hair": _hair(), "head": _head()}

func _recipe(layers: Array, body := "male") -> Dictionary:
	return {"id": "who", "body_type": body, "layers": layers}

## A 576x256 walk file painted one colour, with alpha everywhere except a transparent hole at
## (0,0) so blending has something to keep.
func _walk(hex: String) -> Image:
	var img := Image.create_empty(576, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(hex))
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	return img

func _plan(layers: Array, body := "male") -> Dictionary:
	return LpcCompose.plan(_recipe(layers, body), _defs(), _palettes(), _style())

func test_a_palette_item_resolves_to_its_walk_file_and_a_by_index_remap() -> void:
	var planned := _plan([{"def": "shirt", "recolor": "navy"}])
	assert_array(planned["problems"]).is_empty()
	var layer: Dictionary = planned["layers"][0]
	assert_str(str(layer["path"])).is_equal("spritesheets/torso/shirt/male/walk.png")
	assert_int(int(layer["z"])).is_equal(35)
	var remap: Dictionary = (layer["remaps"] as Array)[0]
	assert_str((remap["from"] as Array)[1].to_html(false)).is_equal("200000")
	assert_str((remap["to"] as Array)[1].to_html(false)).is_equal("000020")

func test_a_file_variant_item_names_the_colour_file_and_needs_a_variant() -> void:
	var planned := _plan([{"def": "tunic", "variant": "forest green"}], "female")
	assert_array(planned["problems"]).is_empty()
	assert_str(str((planned["layers"][0] as Dictionary)["path"])).is_equal("spritesheets/torso/tunic/female/walk/forest_green.png")
	assert_array((planned["layers"][0] as Dictionary)["remaps"]).is_empty()
	assert_str("\n".join(_plan([{"def": "tunic"}], "female")["problems"])).contains("picks none")
	assert_str("\n".join(_plan([{"def": "tunic", "variant": "puce"}], "female")["problems"])).contains("no variant 'puce'")

func test_a_layer_without_art_for_the_body_type_is_refused_by_name() -> void:
	# The tunic is female-only; the browser would draw nothing and say nothing.
	var problems: Array = _plan([{"def": "tunic", "variant": "navy"}], "male")["problems"]
	assert_str("\n".join(problems)).contains("'tunic' (layer_1) has no art for body type 'male'")

func test_a_definition_that_does_not_cover_walk_is_refused_and_no_list_means_the_classic_six() -> void:
	var defs := _defs()
	defs["shirt"]["animations"] = ["sit", "emote"]
	var refused := LpcCompose.plan(_recipe([{"def": "shirt", "recolor": "navy"}]), defs, _palettes(), _style())
	assert_str("\n".join(refused["problems"])).contains("no walk animation")
	defs["shirt"].erase("animations")
	var classic := LpcCompose.plan(_recipe([{"def": "shirt", "recolor": "navy"}]), defs, _palettes(), _style())
	assert_array(classic["problems"]).is_empty()

func test_two_layers_from_one_definition_and_the_base_colour_needs_no_remap() -> void:
	var planned := _plan([{"def": "hair", "recolor": "white"}])
	assert_array(planned["problems"]).is_empty()
	var layers: Array = planned["layers"]
	assert_int(layers.size()).is_equal(2)
	assert_int(int((layers[0] as Dictionary)["z"])).is_equal(120)
	assert_int(int((layers[1] as Dictionary)["z"])).is_equal(9)
	assert_array((layers[0] as Dictionary)["remaps"]).is_empty()

func test_a_head_remaps_skin_and_eyes_on_their_own_palettes() -> void:
	var planned := _plan([{"def": "head", "recolor": "bronze", "eyes": "brown"}])
	assert_array(planned["problems"]).is_empty()
	assert_int(((planned["layers"][0] as Dictionary)["remaps"] as Array).size()).is_equal(2)
	var eyes_only := _plan([{"def": "head", "eyes": "brown"}])
	assert_int(((eyes_only["layers"][0] as Dictionary)["remaps"] as Array).size()).is_equal(1)

func test_an_unknown_colour_and_a_short_palette_are_refused() -> void:
	assert_str("\n".join(_plan([{"def": "shirt", "recolor": "puce"}])["problems"])).contains("'puce' is not a cloth colour")
	assert_str("\n".join(_plan([{"def": "shirt", "recolor": "short"}])["problems"])).contains("has 1 tones where the base")

func test_a_layer_outside_the_style_licences_is_refused() -> void:
	var defs := _defs()
	defs["shirt"] = _shirt(["GPL 3.0"])
	var planned := LpcCompose.plan(_recipe([{"def": "shirt", "recolor": "navy"}]), defs, _palettes(), _style())
	assert_str("\n".join(planned["problems"])).contains("GPL")
	var strict := LpcCompose.plan(_recipe([{"def": "tunic", "variant": "navy"}], "female"), _defs(), _palettes(), _style(["CC0", "OGA-BY"]))
	assert_str("\n".join(strict["problems"])).contains("CC-BY-SA")

func test_credits_keep_the_entries_for_the_used_file_and_fall_back_to_all() -> void:
	var planned := _plan([{"def": "shirt", "recolor": "navy"}])
	var credits: Array = (planned["layers"][0] as Dictionary)["credits"]
	assert_int(credits.size()).is_equal(1)
	assert_str(str((credits[0] as Dictionary)["file"])).is_equal("torso/shirt/male")
	var defs := _defs()
	defs["shirt"]["credits"] = [{"file": "elsewhere", "authors": ["z"], "licenses": ["CC0"], "urls": []},
		{"file": "also/elsewhere", "authors": ["y"], "licenses": ["CC0"], "urls": []}]
	var fallback := LpcCompose.plan(_recipe([{"def": "shirt", "recolor": "navy"}]), defs, _palettes(), _style())
	assert_int(((fallback["layers"][0] as Dictionary)["credits"] as Array).size()).is_equal(2)

func test_remap_matches_within_one_unit_per_channel_and_not_two() -> void:
	var img := Image.create_empty(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(0x20, 0, 0))		  # exact
	img.set_pixel(1, 0, Color8(0x21, 0, 1))		  # within +/-1
	img.set_pixel(2, 0, Color8(0x22, 0, 0))		  # two off: untouched
	var remaps := [{"from": [Color("#100000"), Color("#200000"), Color("#300000")],
		"to": [Color("#000010"), Color("#000020"), Color("#000030")]}]
	var out := LpcCompose.remapped(img, remaps)
	assert_str(out.get_pixel(0, 0).to_html(false)).is_equal("000020")
	assert_str(out.get_pixel(1, 0).to_html(false)).is_equal("000020")
	assert_str(out.get_pixel(2, 0).to_html(false)).is_equal("220000")

func test_compose_draws_lower_z_first_into_the_walk_rows_and_keeps_alpha() -> void:
	# Two layers listed hair-first: the bg hair (z 9) must end up UNDER the shirt (z 35).
	var planned := _plan([{"def": "hair", "recolor": "white"}, {"def": "shirt", "recolor": "navy"}])
	var images := {
		"spritesheets/hair/pony/fg/walk.png": _walk("#00ff00"),
		"spritesheets/hair/pony/bg/walk.png": _walk("#ff0000"),
		"spritesheets/torso/shirt/male/walk.png": _walk("#200000"),
	}
	var composed := LpcCompose.compose(planned, images)
	assert_array(composed["problems"]).is_empty()
	var img: Image = composed["image"]
	assert_int(img.get_width()).is_equal(832)
	assert_int(img.get_height()).is_equal(3456)
	# Row 8 is the top of the walk block; (5,5) is inside every layer's painted area.
	var y := 8 * 64 + 5
	assert_str(img.get_pixel(5, y).to_html(false)).is_equal("00ff00")	# fg hair on top of all
	assert_float(img.get_pixel(0, 8 * 64).a).is_equal(0.0)				# the hole stayed a hole
	assert_float(img.get_pixel(5, 7 * 64).a).is_equal(0.0)				# nothing above the block
	# With the fg hair gone, the shirt's remapped navy is what shows, not the red bg hair.
	var without_fg := _plan([{"def": "hair", "recolor": "white"}, {"def": "shirt", "recolor": "navy"}])
	(without_fg["layers"] as Array).remove_at(0)
	var under: Image = LpcCompose.compose(without_fg, images)["image"]
	assert_str(under.get_pixel(5, y).to_html(false)).is_equal("000020")

func test_compose_refuses_a_missing_or_misshapen_walk_file() -> void:
	var planned := _plan([{"def": "shirt", "recolor": "navy"}])
	assert_str("\n".join(LpcCompose.compose(planned, {})["problems"])).contains("no image for")
	var wrong := Image.create_empty(576, 200, false, Image.FORMAT_RGBA8)
	assert_str("\n".join(LpcCompose.compose(planned, {"spritesheets/torso/shirt/male/walk.png": wrong})["problems"])).contains("a walk file is 4 rows")

func test_the_export_credits_every_used_file_once_and_the_importer_accepts_it() -> void:
	var recipe := _recipe([{"def": "hair", "recolor": "white"}, {"def": "shirt", "recolor": "navy"}])
	var planned := LpcCompose.plan(recipe, _defs(), _palettes(), _style())
	var doc := LpcCompose.export_json(recipe, planned)
	assert_int(int(doc["version"])).is_equal(2)
	assert_str(str(doc["bodyType"])).is_equal("male")
	var files: Array = (doc["credits"] as Array).map(func(c: Dictionary) -> String: return str(c["file"]))
	assert_str(str(files)).is_equal('["hair/pony", "torso/shirt/male"]')
	var images := {
		"spritesheets/hair/pony/fg/walk.png": _walk("#00ff00"),
		"spritesheets/hair/pony/bg/walk.png": _walk("#ff0000"),
		"spritesheets/torso/shirt/male/walk.png": _walk("#200000"),
	}
	var sheet: Image = LpcCompose.compose(planned, images)["image"]
	assert_array(LpcImport.problems(sheet, doc, _style())).is_empty()
	assert_str(str(LpcCompose.files_of(planned))).is_equal('["spritesheets/hair/pony/bg/walk.png", "spritesheets/hair/pony/fg/walk.png", "spritesheets/torso/shirt/male/walk.png"]')
