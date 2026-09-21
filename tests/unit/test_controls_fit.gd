extends GdUnitTestSuite
## Does every game's walk hint FIT the line that draws it, in both devices' words?
##
## This gate exists because the answer was no and nothing said so: the shipped hint drew 356
## design pixels on a 320 window, with "pause" off the right edge, from the first commit until it
## was measured in M52 - a Label with no width does not clip, wrap or complain, and the hint was in
## no layout audit. test_dialog_fit's shape: the real font, and the screen's own constant for the
## room, never a copy. Here for every manifest on disk, shipped and fixture, because the hint is
## per-game DATA and each game writes its own verbs around the template's words.

const GAME_DIRS := ["res://data/games", "res://tests/fixtures/games"]
const STYLE := "res://data/styles/lpc32.tres"
## What shipped before M52: the control, a line known to be too long.
const RETIRED := "WASD / arrows to walk    E or space to look    Esc to pause"
## What test_game_scaffold hands the planner - a literal here too, so a hint the scaffolder
## writes is measured against the same room as a hint somebody typed.
const KNOWN := {
	"styles": ["gb16", "lpc32"],
	"characters_by_style": {
		"gb16": ["hero", "npc_elder", "npc_kid", "npc_smith"],
		"lpc32": ["inn_keeper", "quest_gloom"],
	},
	"voices": ["dusk16", "gb16", "nes16"],
	"existing_ids": ["quest"],
}


func _font() -> Font:
	return ThemeDB.fallback_font


func _width_of(text: String) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiChrome.FONT_SIZE).x


## The room the hint is BUILT with, at the design size - not the live viewport, which doubles for
## a 32px style while the hint's own constant does not.
func _room() -> float:
	return ControlsHint.text_width(UiScale.DESIGN_SIZE.x)


func test_the_font_is_the_one_the_hint_is_measured_against() -> void:
	var label := Label.new()
	add_child(label)
	assert_object(label.get_theme_font(&"font")).override_failure_message(
		"the hint is drawn in a font this gate does not measure").is_equal(_font())
	assert_str(_font().resource_path).is_equal(UiChrome.FONT_PATH)
	label.free()


func _manifests() -> Array[GameManifest]:
	var out: Array[GameManifest] = []
	for dir: String in GAME_DIRS:
		for path in ContentScan.files(dir, ["tres"]):
			var manifest := load(path) as GameManifest
			if manifest != null:
				out.append(manifest)
	return out


func test_every_manifests_hint_fits_in_both_devices_words() -> void:
	var manifests := _manifests()
	assert_int(manifests.size()).override_failure_message(
		"fewer than two manifests found, so this measured almost nothing").is_greater(1)
	var faults: Array[String] = []
	for manifest in manifests:
		for device: Prompts.Device in Prompts.Device.values():
			var line := Prompts.fill(manifest.controls_hint, device)
			var width := _width_of(line)
			if width > _room():
				faults.append("%s (%s): '%s' draws %.0f px in a room of %.0f" % [
					manifest.id, Prompts.Device.keys()[device], line, width, _room()])
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()


func test_the_scaffolded_hint_fits_in_both_devices_words() -> void:
	var planned := GameScaffold.plan({"id": "proof", "style": "gb16"}, KNOWN)
	var key := "data/games/proof.tres"
	assert_bool(planned.has(key)).override_failure_message(
		"the planner writes no %s; it writes %s" % [key, planned.keys()]).is_true()
	var found := RegEx.create_from_string('controls_hint = "([^"]*)"').search(str(planned[key]))
	assert_object(found).override_failure_message("the scaffolded manifest carries no controls_hint").is_not_null()
	for device: Prompts.Device in Prompts.Device.values():
		var line := Prompts.fill(found.get_string(1), device)
		assert_float(_width_of(line)).override_failure_message(
			"the scaffolder's hint '%s' does not fit" % line).is_less_equal(_room())


func test_a_hint_written_too_long_is_caught() -> void:
	# The control: the measurement can fail, on the line that shipped.
	assert_float(_width_of(RETIRED)).override_failure_message(
		"the retired hint measures as fitting, so this gate cannot see an overflow").is_greater(_room())
	assert_float(_width_of("Short enough.")).is_less(_room())


func test_the_hint_label_is_bounded_and_trims() -> void:
	# Containment is never the whole assertion, and neither is a measurement of the STRING: the
	# label itself has to be told its width, or it draws the string whatever this suite measured.
	var hint := ControlsHint.new()
	add_child(hint)
	hint.setup(load(STYLE) as SpriteStyle, UiScale.DESIGN_SIZE, RETIRED)
	assert_float(hint._label.size.x).is_equal(ControlsHint.text_width(UiScale.DESIGN_SIZE.x))
	assert_bool(hint._label.clip_text).is_true()
	assert_that(hint._label.text_overrun_behavior).override_failure_message(
		"an over-long hint would draw off the screen again").is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	hint.free()


## Every style on disk, since the band's colour is a role each one answers differently.
func _styles() -> Array[SpriteStyle]:
	var out: Array[SpriteStyle] = []
	for path in ContentScan.files("res://data/styles", ["tres"]):
		var style := load(path) as SpriteStyle
		if style != null:
			out.append(style)
	return out


func _hint_over(style: SpriteStyle) -> ControlsHint:
	var hint := ControlsHint.new()
	add_child(hint)
	hint.setup(style, UiScale.DESIGN_SIZE, "{move} to walk    {confirm} to look    {pause} to pause")
	return hint


func test_the_line_is_drawn_on_a_solid_band_of_window() -> void:
	# Fitting is not reading. The hint is drawn in the style's quiet colour, which was chosen to be
	# read against a WINDOW - and it used to be drawn straight onto the world, so on the village's
	# bottom row it was grey text on grey brick: 1.3:1 measured, everything right of the letterbox
	# unreadable. Now it sits on a strip of the window's own fill, opaque, so what is behind the
	# words is the colour they were chosen for whatever the map draws there.
	var styles := _styles()
	assert_int(styles.size()).override_failure_message(
		"no styles were found, so this proved nothing").is_greater_equal(2)
	for style in styles:
		var hint := _hint_over(style)
		var band: ColorRect = hint._band
		assert_object(band).override_failure_message("%s: the hint has no band" % style.id).is_not_null()
		# Across the whole window and down to its bottom edge, so it joins the letterbox and leaves
		# no sliver of map under the words. Literals: this is the expected shape, not a readback.
		assert_that(band.get_global_rect()).override_failure_message(
			"%s: the band is at %s" % [style.id, band.get_global_rect()]).is_equal(Rect2(0, 166, 320, 14))
		assert_bool(band.get_global_rect().encloses(hint._label.get_global_rect())).override_failure_message(
			"%s: the words at %s are not on the band" % [style.id, hint._label.get_global_rect()]).is_true()
		assert_bool(band.is_ancestor_of(hint._label)).override_failure_message(
			"%s: the words are not drawn over the band" % style.id).is_true()
		assert_that(band.color).override_failure_message(
			"%s: the band is %s, not the window's fill" % [style.id, band.color]).is_equal(style.ui_color("panel"))
		assert_float(band.color.a).override_failure_message(
			"%s: the band lets the map show through" % style.id).is_equal(1.0)
		hint.free()


func test_a_recolour_repaints_the_band() -> void:
	# The options page's recolour test collects Panels, and the band is a ColorRect, so it would
	# not notice a band left in the old palette behind words in the new one.
	var style := load(STYLE) as SpriteStyle
	var parchment := load("res://data/palettes/parchment.tres") as UiPalette
	var hint := _hint_over(style)
	var recoloured := style.with_ui_colors(parchment.colors)
	assert_that(recoloured.ui_color("panel")).is_not_equal(style.ui_color("panel"))
	hint.restyle(recoloured)
	assert_that(hint._band.color).override_failure_message(
		"the band kept the old palette's fill after a recolour").is_equal(recoloured.ui_color("panel"))
	assert_that(hint._label.get_theme_color(&"font_color")).is_equal(recoloured.ui_color("dim"))
	hint.free()


func test_the_band_fades_with_the_words() -> void:
	# The band is there for the words, so it goes when they do. Left behind, it would be a dark bar
	# across the bottom of the screen for the rest of the game.
	var hint := _hint_over(load(STYLE) as SpriteStyle)
	assert_float(hint._band.modulate.a).is_equal(1.0)
	assert_float(ControlsHint.LINGER_SECONDS + ControlsHint.FADE_SECONDS).override_failure_message(
		"the fade outlasts the ten seconds this test waits").is_less(10.0)
	hint.dismiss()
	hint._process(10.0)
	assert_float(hint._band.modulate.a).override_failure_message(
		"the words faded and the band stayed").is_equal(0.0)
	assert_float(hint._label.modulate.a * hint._band.modulate.a).is_equal(0.0)
	hint.free()
