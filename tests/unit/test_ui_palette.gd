extends GdUnitTestSuite
## A palette is a complete set of chrome, and the check that says so is the style's own.
##
## The load-bearing test here is that the two are the SAME function. A palette missing a role
## would draw that one thing in whatever the style underneath happened to say - a health bar in
## the text colour, say - which looks like a design choice rather than a hole, and no layout gate
## can see it because everything is still the right size and in the right place.

const PALETTE_DIR := "res://data/palettes"


func _shipped() -> Array[UiPalette]:
	var out: Array[UiPalette] = []
	for path in ContentScan.files(PALETTE_DIR, ["tres"]):
		var found := load(path) as UiPalette
		assert_object(found).override_failure_message(
			"%s did not load as a UiPalette" % path).is_not_null()
		out.append(found)
	return out


func _full() -> Dictionary:
	var out: Dictionary = {}
	for role in SpriteStyle.UI_ROLES:
		out[role] = "#123456"
	return out


func test_every_shipped_palette_defines_every_role() -> void:
	var palettes := _shipped()
	assert_int(palettes.size()).override_failure_message(
		"no palettes are shipped, so this suite proved nothing").is_greater(1)
	for palette in palettes:
		assert_array(palette.problems()).override_failure_message(
			"palette '%s': %s" % [palette.id, "\n".join(palette.problems())]).is_empty()


func test_every_shipped_palette_has_a_word_for_its_row_and_its_own_id() -> void:
	var ids: Array[StringName] = []
	var names: Array[String] = []
	for palette in _shipped():
		assert_bool(ids.has(palette.id)).override_failure_message(
			"two palettes both call themselves '%s'" % palette.id).is_false()
		ids.append(palette.id)
		# Distinct WORDS as well as distinct ids: the row shows the word, so two palettes reading
		# "Mint" would be a cycle a player cannot tell they are moving through.
		assert_bool(names.has(palette.name)).override_failure_message(
			"two palettes are both called '%s'" % palette.name).is_false()
		names.append(palette.name)


func test_a_palette_missing_a_role_is_refused_by_name() -> void:
	var palette := UiPalette.new()
	palette.id = &"holed"
	palette.name = "Holed"
	palette.colors = _full()
	palette.colors.erase("hp")
	assert_str("\n".join(palette.problems())).override_failure_message(
		"a palette with no 'hp' was accepted, so every health bar in it draws an unchosen colour"
		).contains("'hp'")


func test_a_colour_that_is_not_a_hex_string_is_refused() -> void:
	# Godot's Color() answers black for an unparseable string rather than failing, so a typo here
	# would ship as a window nobody can read text on.
	var palette := UiPalette.new()
	palette.id = &"vague"
	palette.name = "Vague"
	palette.colors = _full()
	palette.colors["panel"] = "dark blue"
	assert_str("\n".join(palette.problems())).contains("'panel'")


func test_a_palette_with_no_name_is_refused() -> void:
	var palette := UiPalette.new()
	palette.id = &"nameless"
	palette.colors = _full()
	assert_str("\n".join(palette.problems())).contains("name")


func test_a_style_and_a_palette_are_judged_by_one_function() -> void:
	# The whole reason role_problems is static and shared. Two implementations of "a complete set
	# of chrome" drift the day a role is added, and the one that loses lets its side ship a hole.
	# Asserted by feeding ONE broken dictionary to both sides and requiring the same complaint.
	var holed := _full()
	holed.erase("select")

	var palette := UiPalette.new()
	palette.id = &"holed"
	palette.name = "Holed"
	palette.colors = holed

	var style := (load("res://data/styles/dusk16.tres") as SpriteStyle).duplicate() as SpriteStyle
	style.ui_colors = holed

	var from_palette := "\n".join(palette.problems())
	var from_style := "\n".join(style.problems())
	assert_str(from_palette).contains("'select'")
	assert_str(from_style).override_failure_message(
		"the style accepted a set of colours the palette refused, so the two have drifted"
		).contains("'select'")


func test_a_full_set_is_accepted_from_either_side() -> void:
	# The control. Without it every assertion above is satisfied by a check that refuses
	# everything, which is the same as no check at all.
	assert_array(SpriteStyle.role_problems(_full(), "fixture")).is_empty()
	var palette := UiPalette.new()
	palette.id = &"whole"
	palette.name = "Whole"
	palette.colors = _full()
	assert_array(palette.problems()).is_empty()


func test_wearing_a_palette_leaves_the_style_it_was_taken_from_alone() -> void:
	# with_ui_colors returns a DUPLICATE. The styles are authored resources shared by everything
	# that loads them, so recolouring in place would recolour the Sprite Lab, every other suite in
	# the process, and the next game to load that file.
	var style := load("res://data/styles/dusk16.tres") as SpriteStyle
	var before := style.ui_color("panel")
	var worn := style.with_ui_colors(_full())
	assert_that(worn.ui_color("panel")).is_equal(Color("#123456"))
	assert_that(style.ui_color("panel")).override_failure_message(
		"the shared style was recoloured in place").is_equal(before)
	# Everything that is not chrome comes along unchanged: a palette is eight colours, not a
	# different art style.
	assert_int(worn.tile_size).is_equal(style.tile_size)
	assert_str(String(worn.id)).is_equal(String(style.id))


func test_a_worn_palette_does_not_share_its_dictionary_with_the_next_one() -> void:
	# Resource.duplicate() is SHALLOW, so without the dictionary copy two styles worn from one
	# palette would share the same colours - and editing either would edit both.
	var style := load("res://data/styles/dusk16.tres") as SpriteStyle
	var colors := _full()
	var worn := style.with_ui_colors(colors)
	colors["panel"] = "#ffffff"
	assert_that(worn.ui_color("panel")).override_failure_message(
		"the worn style shares its colour dictionary with the caller's").is_equal(
			Color("#123456"))
