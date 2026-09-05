extends GdUnitTestSuite
## The options page, measured with the real font, over both the things it can be drawn over.
##
## The same three questions every audit here asks - nothing outside the window, everything inside
## a window enclosed by that window's CONTENT rect, and a cursor covering a whole row or none of
## one - plus the credits screen's fourth: every line this page can draw must FIT. That one is not
## decoration here. The Window row carries a palette's own NAME, which is content a game supplies,
## and the rows trim with an ellipsis at runtime: "Window: Parchme..." is a row that has stopped
## telling the player what they are looking at.
##
## Measured over the title AND over the world, because this is the only screen here with two
## bases and they are drawn differently - one opaque, one dimmed over the place the player is
## standing in.

const VIEWPORT := Vector2i(320, 180)
const STYLE := "res://data/styles/lpc32.tres"

var _built: Array[OptionsScreen] = []


func after_test() -> void:
	# Freed rather than queue_freed, and asserted by the suite's own orphan baseline of zero.
	for screen in _built:
		if is_instance_valid(screen):
			screen.free()
	_built.clear()


func _style() -> SpriteStyle:
	return load(STYLE) as SpriteStyle


## Opened at CAPACITY: the longest words this page can be handed, so what is measured is the worst
## case rather than whatever the demo happens to say today.
func _open(over_world: bool, sound := "Normal", window := "Parchment") -> OptionsScreen:
	var screen := OptionsScreen.new()
	add_child(screen)
	_built.append(screen)
	screen.setup(OptionsMenu.of(sound, window), _style(), VIEWPORT, over_world)
	return screen


## Every visible Panel and non-empty Label, with the rect it actually DRAWS in - a label measured
## at its string, narrowed to its box when it clips, which is the pause audit's rule.
func _rects(screen: OptionsScreen) -> Array:
	var out: Array = []
	for node in SceneHelpers.find_all_by_class(screen, "Panel"):
		var frame := node as Panel
		if frame.visible:
			out.append(["window", Rect2(frame.global_position, frame.size), frame])
	for node in SceneHelpers.find_all_by_class(screen, "Label"):
		var label := node as Label
		if not label.visible or label.text.strip_edges().is_empty():
			continue
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
		if label.clip_text and label.size.x > 0.0:
			measured.x = minf(measured.x, label.size.x)
		out.append(["'" + label.text + "'",
			Rect2(label.global_position, Vector2(measured.x, float(size))), label])
	return out


func test_nothing_is_drawn_outside_the_window_over_either_base() -> void:
	for over_world: bool in [false, true]:
		var screen := _open(over_world)
		var rects := _rects(screen)
		assert_int(rects.size()).override_failure_message(
			"the page drew nothing measurable, so this proves nothing").is_greater(3)
		for entry: Variant in rects:
			var named: Array = entry
			var rect: Rect2 = named[1]
			assert_bool(Rect2(Vector2.ZERO, Vector2(VIEWPORT)).encloses(rect)) \
				.override_failure_message("over_world=%s: %s is drawn at %s, outside the %s window"
					% [over_world, named[0], rect, VIEWPORT]).is_true()


func test_nothing_sticks_out_of_the_window_it_is_drawn_in() -> void:
	var screen := _open(true)
	for entry: Variant in _rects(screen):
		var named: Array = entry
		var node: Node = named[2]
		var parent := node.get_parent()
		if parent == null or UiChrome.kind_of(parent) != UiChrome.FRAME:
			continue
		# The header band and the cursor are part of the window rather than of the room in it.
		if UiChrome.kind_of(node) == UiChrome.HEADER or UiChrome.kind_of(node) == UiChrome.SELECT:
			continue
		var inner := UiChrome.inner_of(parent)
		var room := Rect2((parent as Control).global_position + inner.position, inner.size)
		assert_bool(room.encloses(named[1])).override_failure_message(
			"%s %s sticks out of its window %s" % [named[0], named[1], room]).is_true()


func test_the_rows_are_distinct_and_go_down_the_page_in_order() -> void:
	# Containment is one-sided: two rows stacked on one line is inside every bound and unreadable.
	var screen := _open(false)
	var rows: Array[Label] = []
	for row: Label in screen._rows:
		if row.visible and not row.text.strip_edges().is_empty():
			rows.append(row)
	assert_int(rows.size()).override_failure_message(
		"the page lists %d rows and %d were drawn" % [screen.menu().size(), rows.size()]
		).is_equal(screen.menu().size())
	for i in rows.size() - 1:
		assert_float(rows[i + 1].global_position.y).override_failure_message(
			"'%s' and '%s' are drawn at the same height or out of order"
			% [rows[i].text, rows[i + 1].text]).is_greater(rows[i].global_position.y)


func test_the_cursor_covers_the_row_it_is_on_and_moves_with_it() -> void:
	var screen := _open(false)
	assert_bool(screen._select.visible).override_failure_message(
		"the page draws no cursor, on a page where every row has a verb").is_true()
	var first := screen.selected_row()
	assert_object(first).is_not_null()
	var bar := Rect2(screen._select.global_position, screen._select.size)
	assert_bool(bar.has_point(first.global_position)).override_failure_message(
		"the cursor is not over the row it reports as chosen").is_true()
	screen.menu().move(1)
	screen._paint()
	var second := screen.selected_row()
	assert_object(second).is_not_equal(first)
	var moved := Rect2(screen._select.global_position, screen._select.size)
	assert_bool(moved.has_point(second.global_position)).override_failure_message(
		"the cursor moved a row and the bar stayed put").is_true()


func test_the_cursor_covers_a_whole_row_and_never_half_of_one() -> void:
	var screen := _open(false)
	var row := screen.selected_row()
	var bar := Rect2(screen._select.global_position, screen._select.size)
	var line := Rect2(row.global_position, Vector2(1.0, float(UiChrome.FONT_SIZE)))
	assert_bool(bar.encloses(line)).override_failure_message(
		"the cursor bar %s does not cover the height of the row it marks %s" % [bar, line]).is_true()


func test_every_word_this_page_can_be_handed_fits_without_being_trimmed() -> void:
	# The one that matters, and the reason it is not decoration: the Window row says a palette's
	# own name, which comes from a game's data, and the rows trim with an ellipsis at runtime.
	# Measured against EVERY shipped palette rather than the one the demo starts on.
	var screen := _open(false)
	var row: Label = screen._rows[0]
	var font := row.get_theme_font("font")
	var size := row.get_theme_font_size("font_size")
	var room := row.size.x
	assert_float(room).override_failure_message(
		"the rows have no width, so measuring against them proves nothing").is_greater(60.0)

	var windows: Array[String] = ["Default"]
	for path in ContentScan.files("res://data/palettes", ["tres"]):
		var palette := load(path) as UiPalette
		windows.append(palette.name)
	assert_int(windows.size()).override_failure_message(
		"no palettes were found, so the widest row was never measured").is_greater(2)

	var over: Array[String] = []
	for level: int in Settings.Level.values():
		for window in windows:
			var menu := OptionsMenu.of(str(Settings.NAMES[level]), window)
			for at in menu.size():
				var line := menu.label(at)
				var wide := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
				if wide > room:
					over.append("'%s' is %.0fpx in a %.0fpx row" % [line, wide, room])
	assert_array(over).override_failure_message(
		"rows the page would trim, each of which stops saying what it is:\n  "
		+ "\n  ".join(over)).is_empty()


func test_a_recolour_repaints_the_page_it_was_chosen_on() -> void:
	# The page is the one screen that has to change its OWN colours while being looked at, which
	# is most of the point of the Window row: a player picking a palette is judging it here.
	var screen := _open(true)
	var palette := load("res://data/palettes/mint.tres") as UiPalette
	var worn := _style().with_ui_colors(palette.colors)
	screen.restyle(worn)
	var box := (screen._frame.panel as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(box.bg_color).override_failure_message(
		"the page kept its old window fill after the palette it is choosing changed").is_equal(
			worn.ui_color("panel"))
	# And it is still a page: a rebuild that dropped the rows would pass the colour assertion.
	assert_int(screen._rows.size()).is_equal(screen.menu().size())
	assert_bool(screen._select.visible).is_true()
