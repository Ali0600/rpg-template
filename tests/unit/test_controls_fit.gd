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
