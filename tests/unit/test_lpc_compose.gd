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

## A beast head: drawn in a colour that is NOT its material's base, and saying so. Every
## non-human head in the catalogue is one of these - the lizard is green, the zombie grey-green,
## the fur heads brown - and they are the whole reason a definition's own base is read.
func _beast(base := "ulpc.bronze") -> Dictionary:
	return {"name": "Beast", "type_name": "head",
		"recolors": {"material": "body", "base": base, "palettes": ["ulpc"]},
		"layer_1": {"zPos": 100, "male": "head/beast/male/"},
		"animations": ["walk"],
		"credits": [{"file": "head/beast", "authors": ["f"], "licenses": ["CC-BY-SA 3.0"], "urls": []}]}

func _defs() -> Dictionary:
	return {"shirt": _shirt(), "tunic": _tunic(), "hair": _hair(), "head": _head(),
		"beast": _beast(), "farm": _beast("lpcr.ivory")}

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

func test_a_layer_drawn_off_its_material_s_base_remaps_from_the_colour_it_was_drawn_in() -> void:
	# The beast head is drawn in bronze and asked for light. Remapping from the material's own
	# base - light - would look for pixels that are not there and change almost nothing: a
	# recolour that silently does not happen, on exactly the layers a monster is made of.
	var planned := _plan([{"def": "beast", "recolor": "light"}])
	assert_array(planned["problems"]).is_empty()
	var remap: Dictionary = ((planned["layers"][0] as Dictionary)["remaps"] as Array)[0]
	assert_str((remap["from"] as Array)[1].to_html(false)).override_failure_message(
		"the remap reads from the material's base rather than the colour this art is drawn in"
		).is_equal("000020")
	assert_str((remap["to"] as Array)[1].to_html(false)).is_equal("200000")


func test_asking_a_beast_head_for_the_colour_it_already_is_remaps_nothing() -> void:
	# The other half of reading the stated base: bronze IS this art, so there is nothing to do.
	# Without the fix this would remap bronze onto bronze the long way round, through light.
	var planned := _plan([{"def": "beast", "recolor": "bronze"}])
	assert_array(planned["problems"]).is_empty()
	assert_array((planned["layers"][0] as Dictionary)["remaps"]).is_empty()


func test_a_layer_in_a_palette_scheme_this_composer_never_fetches_is_refused_by_name() -> void:
	# The farm heads are drawn in lpcr, a different scheme with different files. Silently
	# treating "lpcr.ivory" as the ulpc variant "ivory" would remap from a palette that was
	# never loaded, so it says so instead.
	assert_str("\n".join(_plan([{"def": "farm", "recolor": "light"}])["problems"])).contains(
		"'lpcr' palette scheme")


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


# -- the slash ---------------------------------------------------------------------------------

## A weapon in the manner of the generator's dagger: one file per colour, drawn in walk and slash.
func _dagger() -> Dictionary:
	return {"name": "Dagger", "type_name": "weapon", "variants": ["dagger"],
		"layer_1": {"zPos": 140, "male": "weapon/dagger/"},
		"animations": ["walk", "slash"],
		"credits": [{"file": "weapon/dagger", "authors": ["g"], "licenses": ["OGA-BY 3.0"], "urls": []}]}

func _slash_defs() -> Dictionary:
	var defs := _defs()
	defs["shirt"]["animations"] = ["walk", "slash"]
	defs["dagger"] = _dagger()
	return defs

func _slash_recipe(layers: Array) -> Dictionary:
	var recipe := _recipe(layers)
	recipe["animations"] = ["walk", "slash"]
	return recipe

## A slash file painted one colour: `wide` px of 64px frames, four rows.
func _slash(hex: String, wide := 384) -> Image:
	var img := Image.create_empty(wide, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(hex))
	return img

func _paths(planned: Dictionary) -> String:
	return str((planned["layers"] as Array).map(func(l: Dictionary) -> String: return str(l["path"])))

func test_a_recipe_that_names_no_animations_plans_the_walk_alone() -> void:
	# Every recipe written before the slash, and every character that never swings: their committed
	# sheets stay byte-identical only while nothing plans a slash for them.
	var planned := LpcCompose.plan(_recipe([{"def": "shirt", "recolor": "navy"}]), _slash_defs(), _palettes(), _style())
	assert_array(planned["problems"]).is_empty()
	assert_str(_paths(planned)).is_equal('["spritesheets/torso/shirt/male/walk.png"]')

func test_a_recipe_asking_for_the_slash_plans_each_layer_s_slash_file_after_its_walk() -> void:
	var planned := LpcCompose.plan(_slash_recipe([{"def": "shirt", "recolor": "navy"}]), _slash_defs(), _palettes(), _style())
	assert_array(planned["problems"]).is_empty()
	assert_str(_paths(planned)).is_equal(
		'["spritesheets/torso/shirt/male/walk.png", "spritesheets/torso/shirt/male/slash.png"]')

func test_a_layer_drawn_only_in_the_slash_is_not_planned_for_the_walk() -> void:
	# The dagger appears in the swing and nowhere else, or the hero walks the village armed and his
	# portrait - cut from a walk frame - holds a blade.
	var planned := LpcCompose.plan(_slash_recipe([{"def": "shirt", "recolor": "navy"},
		{"def": "dagger", "variant": "dagger", "only": ["slash"]}]), _slash_defs(), _palettes(), _style())
	assert_array(planned["problems"]).is_empty()
	var dagger := {"layers": (planned["layers"] as Array).filter(
		func(l: Dictionary) -> bool: return str(l["def"]) == "dagger")}
	assert_str(_paths(dagger)).is_equal('["spritesheets/weapon/dagger/slash/dagger.png"]')

func test_a_layer_without_an_animation_the_recipe_draws_it_in_is_refused_by_name() -> void:
	# The hair covers the walk alone. Planned into a slash it would leave the character bald for the
	# length of every swing, and the browser would say nothing about it.
	var problems: Array = LpcCompose.plan(_slash_recipe([{"def": "hair", "recolor": "white"}]),
		_slash_defs(), _palettes(), _style())["problems"]
	assert_str("\n".join(problems)).contains("'hair' has no slash animation")

func test_a_layer_drawn_only_in_an_animation_the_recipe_does_not_draw_is_refused() -> void:
	var problems: Array = LpcCompose.plan(_recipe([{"def": "dagger", "variant": "dagger", "only": ["slash"]}]),
		_slash_defs(), _palettes(), _style())["problems"]
	assert_str("\n".join(problems)).contains("'dagger' is drawn only in")

func test_an_animation_this_composer_has_no_row_for_is_refused_and_so_is_leaving_out_the_walk() -> void:
	var recipe := _recipe([{"def": "shirt", "recolor": "navy"}])
	recipe["animations"] = ["walk", "thrust"]
	assert_str("\n".join(LpcCompose.plan(recipe, _slash_defs(), _palettes(), _style())["problems"])).contains("'thrust'")
	recipe["animations"] = ["slash"]
	assert_str("\n".join(LpcCompose.plan(recipe, _slash_defs(), _palettes(), _style())["problems"])).contains(
		"leave out the walk")

func test_compose_draws_the_slash_into_rows_12_to_15_and_a_slash_only_layer_stays_out_of_the_walk() -> void:
	var planned := LpcCompose.plan(_slash_recipe([{"def": "shirt", "recolor": "navy"},
		{"def": "dagger", "variant": "dagger", "only": ["slash"]}]), _slash_defs(), _palettes(), _style())
	var images := {
		"spritesheets/torso/shirt/male/walk.png": _walk("#200000"),
		"spritesheets/torso/shirt/male/slash.png": _slash("#300000"),
		"spritesheets/weapon/dagger/slash/dagger.png": _slash("#00ff00"),
	}
	var composed := LpcCompose.compose(planned, images)
	assert_array(composed["problems"]).is_empty()
	var img: Image = composed["image"]
	# Rows are literals from the generator's table: the slash block is LPC rows 12-15, the walk 8-11.
	assert_str(img.get_pixel(5, 12 * 64 + 5).to_html(false)).is_equal("00ff00")	# the dagger, over the shirt
	assert_str(img.get_pixel(5, 15 * 64 + 60).to_html(false)).is_equal("00ff00")
	assert_str(img.get_pixel(5, 8 * 64 + 5).to_html(false)).override_failure_message(
		"the walk does not show the shirt alone").is_equal("000020")
	assert_float(img.get_pixel(6 * 64 + 5, 12 * 64 + 5).a).is_equal(0.0)	# six frames, not nine
	assert_float(img.get_pixel(5, 16 * 64 + 5).a).is_equal(0.0)			# nothing below the block

func test_compose_refuses_a_slash_file_narrower_than_six_frames() -> void:
	var planned := LpcCompose.plan(_slash_recipe([{"def": "shirt", "recolor": "navy"}]), _slash_defs(), _palettes(), _style())
	var images := {
		"spritesheets/torso/shirt/male/walk.png": _walk("#200000"),
		"spritesheets/torso/shirt/male/slash.png": _slash("#300000", 320),
	}
	assert_str("\n".join(LpcCompose.compose(planned, images)["problems"])).contains("a slash file is 6 frames")

func test_the_export_credits_a_file_once_across_the_animations_it_is_drawn_in() -> void:
	var recipe := _slash_recipe([{"def": "shirt", "recolor": "navy"}])
	var planned := LpcCompose.plan(recipe, _slash_defs(), _palettes(), _style())
	var files: Array = (LpcCompose.export_json(recipe, planned)["credits"] as Array).map(
		func(c: Dictionary) -> String: return str(c["file"]))
	assert_str(str(files)).is_equal('["torso/shirt/male"]')


# -- a swing on bigger frames ----------------------------------------------------------------------

## A sword in the manner of the generator's arming sword at the pinned commit: carried in the walk by
## two standard layers, swung by two layers whose `custom_animation` is drawn on 128px frames, with a
## backswing beside them that nobody asks for. Its animations name no plain slash.
func _arming() -> Dictionary:
	return {"name": "Arming Sword", "type_name": "weapon", "variants": ["bronze", "iron"],
		"layer_1": {"zPos": 140, "male": "weapon/sword/arming/universal/fg/"},
		"layer_2": {"zPos": 9, "male": "weapon/sword/arming/universal/bg/"},
		"layer_3": {"zPos": 8, "custom_animation": "slash_128", "male": "weapon/sword/arming/attack_slash/bg/"},
		"layer_4": {"zPos": 150, "custom_animation": "slash_128", "male": "weapon/sword/arming/attack_slash/fg/"},
		"layer_5": {"zPos": 150, "custom_animation": "backslash_128", "male": "weapon/sword/arming/attack_backslash/fg/"},
		"animations": ["walk", "hurt", "slash_128", "backslash_128"],
		"credits": [{"file": "weapon/sword/arming", "authors": ["h; walk by i"], "licenses": ["OGA-BY 3.0"], "urls": []}]}

## The longsword's shape: one swing layer, on 192px frames.
func _longsword() -> Dictionary:
	return {"name": "Longsword", "type_name": "weapon", "variants": ["longsword"],
		"layer_1": {"zPos": 150, "custom_animation": "slash_oversize", "male": "weapon/sword/longsword/attack_slash/"},
		"animations": ["walk", "slash_oversize"],
		"credits": [{"file": "weapon/sword/longsword", "authors": ["j"], "licenses": ["OGA-BY 3.0"], "urls": []}]}

func _sword_defs() -> Dictionary:
	var defs := _slash_defs()
	defs["arming"] = _arming()
	defs["longsword"] = _longsword()
	return defs

## The shirt, and a sword drawn in the swing alone.
func _swing_recipe(sword: Dictionary) -> Dictionary:
	return _slash_recipe([{"def": "shirt", "recolor": "navy"}, sword])

func _arming_plan() -> Dictionary:
	return LpcCompose.plan(_swing_recipe({"def": "arming", "variant": "bronze", "only": ["slash"]}),
		_sword_defs(), _palettes(), _style())

## A swing file: six frames on four rows of `cell`, painted one colour, or left clear.
func _block(hex: String, cell := 128) -> Image:
	var img := Image.create_empty(6 * cell, 4 * cell, false, Image.FORMAT_RGBA8)
	if not hex.is_empty():
		img.fill(Color(hex))
	return img

## The shirt's two files and the arming sword's two, the sword's under layer painted green.
func _arming_images(body: Image) -> Dictionary:
	return {
		"spritesheets/torso/shirt/male/walk.png": _walk("#200000"),
		"spritesheets/torso/shirt/male/slash.png": body,
		"spritesheets/weapon/sword/arming/attack_slash/bg/bronze.png": _block("#00ff00"),
		"spritesheets/weapon/sword/arming/attack_slash/fg/bronze.png": _block(""),
	}

func test_a_swing_on_bigger_frames_plans_its_two_files_and_nothing_it_does_not_draw() -> void:
	# Not the walk layers' slash files, which do not exist, and not the backswing, which nobody asked for.
	var planned := _arming_plan()
	assert_array(planned["problems"]).is_empty()
	var sword := {"layers": (planned["layers"] as Array).filter(
		func(l: Dictionary) -> bool: return str(l["def"]) == "arming")}
	assert_str(_paths(sword)).is_equal(
		'["spritesheets/weapon/sword/arming/attack_slash/bg/bronze.png", "spritesheets/weapon/sword/arming/attack_slash/fg/bronze.png"]')
	assert_str(JSON.stringify(LpcCompose.block_of(planned))).is_equal(
		'{"clip":"slash","columns":6,"frameSize":128,"name":"slash_128","rows":4,"x":0,"y":3456}')

func test_a_recipe_that_does_not_swing_plans_the_sword_it_carries_and_no_block() -> void:
	var planned := LpcCompose.plan(_recipe([{"def": "arming", "variant": "bronze"}]), _sword_defs(), _palettes(), _style())
	assert_array(planned["problems"]).is_empty()
	assert_str(_paths(planned)).is_equal(
		'["spritesheets/weapon/sword/arming/universal/fg/walk/bronze.png", "spritesheets/weapon/sword/arming/universal/bg/walk/bronze.png"]')
	assert_bool(LpcCompose.block_of(planned).is_empty()).is_true()

func test_two_swing_sizes_in_one_recipe_are_refused_by_name() -> void:
	var recipe := _slash_recipe([{"def": "arming", "variant": "bronze", "only": ["slash"]},
		{"def": "longsword", "variant": "longsword", "only": ["slash"]}])
	assert_str("\n".join(LpcCompose.plan(recipe, _sword_defs(), _palettes(), _style())["problems"])).contains(
		"a sheet holds one size")

func test_a_swing_layer_with_no_colours_to_name_its_file_is_refused_by_name() -> void:
	var defs := _sword_defs()
	(defs["longsword"] as Dictionary).erase("variants")
	var problems: Array = LpcCompose.plan(_swing_recipe({"def": "longsword", "only": ["slash"]}), defs,
		_palettes(), _style())["problems"]
	assert_str("\n".join(problems)).contains("'longsword' (layer_1) draws its slash_oversize as one file per colour")

func test_compose_centres_the_body_in_the_swing_block_and_lays_the_sword_whole() -> void:
	# The generator's own rule (draw-frames.ts): a 64px frame is centred in the bigger cell, unscaled, and
	# the sword's file IS the block. Rows 12-15 keep the body alone, which the generator draws too.
	var body := _slash("#300000")
	body.set_pixel(3 * 64 + 10, 1 * 64 + 10, Color("#ff0000"))	# frame 3 of LPC row 1, marked
	var composed := LpcCompose.compose(_arming_plan(), _arming_images(body))
	assert_array(composed["problems"]).is_empty()
	var img: Image = composed["image"]
	assert_vector(Vector2(img.get_size())).is_equal(Vector2(832, 3968))
	# Cell (1, 2) of the block starts at (128, 3712). The shirt covers 32..95 of it; the sword, drawn
	# under the shirt, shows round it.
	var top := 3456 + 2 * 128
	assert_str(img.get_pixel(128 + 31, top + 40).to_html(false)).is_equal("00ff00")
	assert_str(img.get_pixel(128 + 32, top + 40).to_html(false)).is_equal("000030")
	assert_str(img.get_pixel(128 + 95, top + 95).to_html(false)).is_equal("000030")
	assert_str(img.get_pixel(128 + 96, top + 95).to_html(false)).is_equal("00ff00")
	# Frame 3 of LPC row 1 lands in cell (3, 1), still marked, 32 in and 32 down.
	assert_str(img.get_pixel(3 * 128 + 32 + 10, 3456 + 128 + 32 + 10).to_html(false)).is_equal("ff0000")
	# The whole sword, to its last pixel; and the body alone in the universal sheet's slash rows.
	assert_str(img.get_pixel(767, 3967).to_html(false)).is_equal("00ff00")
	assert_str(img.get_pixel(5, 12 * 64 + 5).to_html(false)).is_equal("000030")

func test_a_swing_file_of_the_wrong_size_is_refused_by_name() -> void:
	var images := _arming_images(_slash("#300000"))
	images["spritesheets/weapon/sword/arming/attack_slash/bg/bronze.png"] = _block("#00ff00").get_region(
		Rect2i(0, 0, 768, 256))
	assert_str("\n".join(LpcCompose.compose(_arming_plan(), images)["problems"])).contains(
		"a 128px swing file is 6 frames on 4 rows")

func test_a_swing_on_192px_frames_grows_the_sheet_by_its_own_block() -> void:
	var planned := LpcCompose.plan(_swing_recipe({"def": "longsword", "variant": "longsword", "only": ["slash"]}),
		_sword_defs(), _palettes(), _style())
	assert_array(planned["problems"]).is_empty()
	var images := {
		"spritesheets/torso/shirt/male/walk.png": _walk("#200000"),
		"spritesheets/torso/shirt/male/slash.png": _slash("#300000"),
		"spritesheets/weapon/sword/longsword/attack_slash/longsword.png": _block("", 192),
	}
	var img: Image = LpcCompose.compose(planned, images)["image"]
	assert_vector(Vector2(img.get_size())).is_equal(Vector2(1152, 4224))
	assert_float(img.get_pixel(63, 3456 + 64).a).is_equal(0.0)
	assert_str(img.get_pixel(64, 3456 + 64).to_html(false)).is_equal("000030")

func test_the_export_records_where_the_swing_is_and_the_importer_cuts_it_from_there() -> void:
	var recipe := _swing_recipe({"def": "arming", "variant": "bronze", "only": ["slash"]})
	var planned := LpcCompose.plan(recipe, _sword_defs(), _palettes(), _style())
	var doc := LpcCompose.export_json(recipe, planned)
	assert_str(JSON.stringify(doc.get("customAnimations"))).is_equal(
		'[{"clip":"slash","columns":6,"frameSize":128,"name":"slash_128","rows":4,"x":0,"y":3456}]')
	var sheet: Image = LpcCompose.compose(planned, _arming_images(_slash("#300000")))["image"]
	assert_array(LpcImport.problems(sheet, doc, _style())).is_empty()
	var meta: SheetMeta = LpcImport.build(sheet, doc, _style(), "who")["meta"]
	assert_bool(meta.has_grid("slash")).override_failure_message(
		"the importer did not take the swing from the block the export names").is_true()
	# A recipe with nothing swinging on bigger frames writes the export it always did.
	var dagger := _slash_recipe([{"def": "shirt", "recolor": "navy"}, {"def": "dagger", "variant": "dagger", "only": ["slash"]}])
	var plain := LpcCompose.export_json(dagger, LpcCompose.plan(dagger, _sword_defs(), _palettes(), _style()))
	assert_bool(plain.has("customAnimations")).is_false()
