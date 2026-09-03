extends GdUnitTestSuite
## The pieces every screen in this game is drawn from, and the font they are drawn in.
##
## UiChrome is pure, so this is a unit suite: it builds a frame, a bar and a cursor and measures
## them. What it cannot prove is that a SCREEN used them, which is what the layout audits next
## door are for.
##
## The role census at the bottom is the load-bearing one. Colours reach a screen by NAME, and a
## name is a string - so `ui_color("boarder")` is a typo that compiles, draws, and answers a
## colour nobody chose. The style declares the list and this proves every ask is on it.

const STYLE := "res://data/styles/dusk16.tres"
const UI_DIR := "res://scripts/ui"


func _style() -> SpriteStyle:
	return load(STYLE) as SpriteStyle


# -- the font ---------------------------------------------------------------------------------

func test_the_game_is_drawn_in_the_font_the_project_names() -> void:
	# The setting is what puts it in ThemeDB, and ThemeDB is what a Label falls back to. Asserted
	# from the Label's end, because that is the one a player looks at.
	var label := Label.new()
	add_child(label)
	assert_str(label.get_theme_font(&"font").resource_path).override_failure_message(
		"a Label drawn today reports a font this project did not choose").is_equal(
		UiChrome.FONT_PATH)
	label.free()

func test_the_font_is_rendered_as_pixels_rather_than_smoothed() -> void:
	# The whole reason to bring a pixel font in. Antialiasing, hinting and subpixel positioning
	# each smear an 8px glyph across two pixels, and NOTHING else in this build can see it: the
	# text still says what it says, at the size it says it, in the place it belongs. The pins
	# live in project.godot's [importer_defaults]; this is the assertion that they took.
	var font := load(UiChrome.FONT_PATH) as FontFile
	assert_object(font).override_failure_message(
		"the project font is not a FontFile - nothing below measured anything").is_not_null()
	assert_int(font.antialiasing).override_failure_message(
		"the font is antialiased, so every glyph is drawn in shades of half a pixel"
	).is_equal(TextServer.FONT_ANTIALIASING_NONE)
	assert_int(font.subpixel_positioning).override_failure_message(
		"the font is subpixel-positioned, so a glyph starts between two pixels"
	).is_equal(TextServer.SUBPIXEL_POSITIONING_DISABLED)
	assert_int(font.hinting).override_failure_message(
		"the font is hinted, which moves the pixels a pixel font already placed"
	).is_equal(TextServer.HINTING_NONE)

func test_the_bold_face_is_there_to_be_asked_for() -> void:
	assert_bool(ResourceLoader.exists(UiChrome.FONT_BOLD_PATH)).override_failure_message(
		"the header band's face is named and not shipped").is_true()


# -- a window ---------------------------------------------------------------------------------

func test_a_frame_is_filled_and_ruled_from_the_style() -> void:
	# The difference between a frame and a rectangle is the rule around it, and both colours are
	# the style's - a chrome colour typed into a script is a game that stops re-skinning.
	var style := _style()
	var frame := UiChrome.frame(style, Rect2(4.0, 4.0, 100.0, 40.0))
	var box := frame.panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_object(box).is_not_null()
	assert_that(box.bg_color).is_equal(style.ui_color("panel"))
	assert_that(box.border_color).is_equal(style.ui_color("border"))
	assert_int(box.border_width_left).is_equal(UiChrome.BORDER)
	assert_int(box.border_width_top).is_equal(UiChrome.BORDER)
	assert_int(box.border_width_right).is_equal(UiChrome.BORDER)
	assert_int(box.border_width_bottom).is_equal(UiChrome.BORDER)
	assert_int(box.corner_radius_top_left).override_failure_message(
		"a rounded corner at this size is two grey pixels and a lie about the resolution"
	).is_equal(0)
	frame.panel.free()

func test_an_untitled_frame_has_no_band_and_uses_the_room() -> void:
	var frame := UiChrome.frame(_style(), Rect2(0.0, 0.0, 100.0, 40.0))
	assert_object(frame.header).is_null()
	assert_object(frame.title).is_null()
	# Without a band the content starts just inside the rule.
	assert_float(frame.inner().position.y).is_equal(float(UiChrome.BORDER + UiChrome.PAD))
	frame.panel.free()

func test_a_titled_frame_carries_its_name_in_a_band() -> void:
	var style := _style()
	var frame := UiChrome.frame(style, Rect2(0.0, 0.0, 100.0, 40.0), "Record your journey")
	assert_object(frame.header).is_not_null()
	assert_that(frame.header.color).is_equal(style.ui_color("header"))
	assert_str(frame.title.text).override_failure_message(
		"a header is upper case rather than a bigger size - the font is drawn for ONE size"
	).is_equal("RECORD YOUR JOURNEY")
	# The band and its label are CHILDREN of the panel, which is what makes an audit that walks
	# ancestry get the containment rule with no case of its own.
	assert_object(frame.header.get_parent()).is_equal(frame.panel)
	assert_object(frame.title.get_parent()).is_equal(frame.header)
	frame.panel.free()

func test_a_band_pushes_what_is_drawn_below_it() -> void:
	# The pair that matters: `inner()` is what the layout places by AND what the audit measures
	# by, so a title that ate its window's content would fail here rather than on screen.
	var style := _style()
	var bare := UiChrome.frame(style, Rect2(0.0, 0.0, 100.0, 40.0))
	var titled := UiChrome.frame(style, Rect2(0.0, 0.0, 100.0, 40.0), "Paused")
	assert_float(titled.inner().position.y).override_failure_message(
		"a titled window starts its content where an untitled one does, so the band covers it"
	).is_greater(bare.inner().position.y)
	assert_float(titled.inner().size.y).is_less(bare.inner().size.y)
	# And it is still INSIDE the window it describes.
	assert_bool(Rect2(Vector2.ZERO, titled.panel.size).encloses(titled.inner())).is_true()
	bare.panel.free()
	titled.panel.free()


# -- the cursor -------------------------------------------------------------------------------

func test_the_cursor_starts_nowhere() -> void:
	# A bar at the origin is a bar drawn over the corner of whatever window owns it.
	var bar := UiChrome.select(_style())
	assert_bool(bar.visible).is_false()
	bar.free()

func test_the_cursor_covers_the_row_it_selects() -> void:
	# What replaced the "> " prefix. The old marker was part of the row's own STRING, which is
	# why every test that wanted to know what was selected had to read text and why the text
	# shifted sideways to hold it.
	var style := _style()
	var bar := UiChrome.select(style)
	var row := UiChrome.label(style, "text")
	row.text = "Attack"
	row.position = Vector2(10.0, 40.0)
	UiChrome.place(bar, row, 60.0, 10.0)
	assert_bool(bar.visible).is_true()
	assert_that(bar.color).is_equal(style.ui_color("select"))
	var covered := Rect2(bar.position, bar.size)
	assert_bool(covered.has_point(row.position)).override_failure_message(
		"the cursor does not reach the row it is meant to be under").is_true()
	assert_float(bar.position.x).override_failure_message(
		"the cursor starts on the same pixel as the text, so it reads as a background not a bar"
	).is_less(row.position.x)
	bar.free()
	row.free()


# -- a readout --------------------------------------------------------------------------------

func test_a_bar_is_coloured_by_what_it_measures() -> void:
	# HP and MP are the only colours on this screen, which is Persona 5's own rule and what makes
	# a bar readable at a glance. Until M42 both were drawn in the same grey as the help text.
	var style := _style()
	var hp := UiChrome.bar(style, "hp", 40.0)
	var mp := UiChrome.bar(style, "mp", 40.0)
	assert_that(hp.fill.color).is_equal(style.ui_color("hp"))
	assert_that(mp.fill.color).is_equal(style.ui_color("mp"))
	assert_that(hp.fill.color).override_failure_message(
		"health and magic are drawn the same colour, so neither says which it is"
	).is_not_equal(mp.fill.color)
	assert_that(hp.track.color).is_equal(style.ui_color("header"))
	hp.root.free()
	mp.root.free()

func test_a_bar_is_as_full_as_the_number_beside_it() -> void:
	var bar := UiChrome.bar(_style(), "hp", 40.0)
	UiChrome.fill(bar, 20, 40)
	assert_float(bar.fill.size.x).is_equal(20.0)
	assert_str(bar.numbers.text).is_equal("20/40")
	UiChrome.fill(bar, 40, 40)
	assert_float(bar.fill.size.x).is_equal(40.0)
	bar.root.free()

func test_a_bar_only_reads_full_when_it_is() -> void:
	# Floored rather than rounded. At 99 of 100 a rounded fill reaches the end of its track, and
	# a bar saying "full" during a fight that is not over is the one lie a bar can tell.
	var bar := UiChrome.bar(_style(), "hp", 40.0)
	UiChrome.fill(bar, 99, 100)
	assert_float(bar.fill.size.x).override_failure_message(
		"a bar at 99/100 is drawn full").is_less(40.0)
	bar.root.free()

func test_a_bar_cannot_be_drawn_past_its_own_track() -> void:
	# The degenerate ends, which is where a ratio stops behaving: nothing to measure against, a
	# value below nought, and a value above the maximum are all real states a fight can hand it.
	var bar := UiChrome.bar(_style(), "hp", 40.0)
	for pair: Array in [[5, 0], [-3, 10], [30, 10]]:
		UiChrome.fill(bar, int(pair[0]), int(pair[1]))
		assert_float(bar.fill.size.x).override_failure_message(
			"%d of %d draws a fill of %s in a 40px track" % [pair[0], pair[1], bar.fill.size.x]
		).is_between(0.0, 40.0)
	bar.root.free()


# -- what the audits ask ------------------------------------------------------------------------

func test_the_pieces_say_what_kind_of_thing_they_are() -> void:
	# The audits treat a frame and a cursor as CONTAINERS rather than as peers - a window that
	# was a peer would be reported as covering its own text. Stated as meta rather than inferred
	# from the class, because "a ColorRect that is really a highlight" is exactly what gets
	# inferred wrongly the day a second ColorRect arrives for another reason.
	var style := _style()
	var frame := UiChrome.frame(style, Rect2(0.0, 0.0, 40.0, 20.0), "Paused")
	var cursor := UiChrome.select(style)
	var readout := UiChrome.bar(style, "hp", 20.0)
	assert_str(String(UiChrome.kind_of(frame.panel))).is_equal(String(UiChrome.FRAME))
	assert_str(String(UiChrome.kind_of(frame.header))).is_equal(String(UiChrome.HEADER))
	assert_str(String(UiChrome.kind_of(cursor))).is_equal(String(UiChrome.SELECT))
	assert_str(String(UiChrome.kind_of(readout.root))).is_equal(String(UiChrome.BAR))
	assert_str(String(UiChrome.kind_of(frame.title))).override_failure_message(
		"a plain label claims to be chrome, so the audit would stop measuring it").is_equal("")
	frame.panel.free()
	cursor.free()
	readout.root.free()


# -- the two lists that must not drift ----------------------------------------------------------

func test_every_colour_a_screen_asks_for_is_one_a_style_must_define() -> void:
	# Colours reach a screen by NAME. `ui_color("boarder")` compiles, draws, and answers a colour
	# nobody chose - and the style it came from is perfectly valid, because the role it declares
	# is spelled correctly and nothing was looking at the other end.
	#
	# So the asks are read out of the source and checked against the declaration. Both directions
	# would be nice; only this one is checkable, since a role no screen asks for yet is a role a
	# screen may ask for tomorrow.
	var asked: Dictionary = {}
	var files := ContentScan.files(UI_DIR, ["gd"])
	assert_int(files.size()).override_failure_message(
		"no interface source was scanned, so this proved nothing").is_greater(5)
	var pattern := RegEx.new()
	pattern.compile('ui_color\\("([a-z_]+)"\\)')
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in pattern.search_all(text):
			asked[m.get_string(1)] = path.get_file()
	assert_int(asked.size()).override_failure_message(
		"no screen asked for a colour at all").is_greater(2)
	var strays: Array[String] = []
	for role: Variant in asked.keys():
		if not SpriteStyle.UI_ROLES.has(str(role)):
			strays.append("%s asks for ui_color('%s')" % [asked[role], role])
	assert_array(strays).override_failure_message(
		"colours no style has to define, so each is white on somebody's screen:\n  "
		+ "\n  ".join(strays)).is_empty()

func test_every_shipped_style_defines_every_role() -> void:
	# The other half, over the styles rather than the scripts. A style that shipped without
	# chrome used to be perfectly legal and drew a white screen.
	for id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(id)
		assert_array(style.problems()).override_failure_message(
			"style '%s': %s" % [id, ", ".join(style.problems())]).is_empty()
		for role in SpriteStyle.UI_ROLES:
			assert_bool(style.ui_colors.has(role)).override_failure_message(
				"style '%s' has no '%s'" % [id, role]).is_true()

func test_a_style_missing_a_colour_is_refused_by_name() -> void:
	# Fail-first, per role: the message has to NAME the missing one, or a style with eight roles
	# and one typo is a hunt.
	for role in SpriteStyle.UI_ROLES:
		var style := (load(STYLE) as SpriteStyle).duplicate() as SpriteStyle
		style.ui_colors = style.ui_colors.duplicate()
		style.ui_colors.erase(role)
		assert_str("\n".join(style.problems())).override_failure_message(
			"a style with no '%s' is accepted" % role).contains("'%s'" % role)

func test_a_fighter_scale_below_one_is_refused() -> void:
	var style := (load(STYLE) as SpriteStyle).duplicate() as SpriteStyle
	style.battle_sprite_scale = 0
	assert_str("\n".join(style.problems())).contains("battle_sprite_scale")
