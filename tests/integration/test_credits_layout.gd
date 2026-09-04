extends GdUnitTestSuite
## The credits screen, measured. Three questions, and one of them is not about layout at all.
##
## The layout half is the shape every audit here asks: nothing is drawn outside the 320x180
## window, everything inside a window is enclosed by that window's CONTENT rect rather than its
## outer one, and the rows are actually distinct and in order - because containment is one-sided
## and a screen that drew nothing, or stacked twelve rows on one line, is comfortably inside any
## bound. That is M36's lesson applied before the bug rather than after it.
##
## There is deliberately NO cursor question, unlike every other screen audit. This page has no
## verb on it, so it draws no cursor, for the reason the pause menu's status page draws none.
##
## The third question is the one this screen exists for. Every line it can draw is measured with
## the REAL font, and a name that would be trimmed fails the build - because the rows are
## clip_text + OVERRUN_TRIM_ELLIPSIS, which at runtime silently turns an artist into "William
## Thomps...". A truncated artist is a failed attribution, not a cosmetic loss, and no other gate
## in this project can see it: the pure suite has no font, and a screenshot proves one page.

const VIEWPORT := Vector2i(320, 180)
const STYLE := "res://data/styles/dusk16.tres"
const CREDITS := "res://assets/generated/lpc32/credits.json"

var _built: Array[CanvasLayer] = []


func after_test() -> void:
	# Freed rather than queue_freed, and asserted by the suite's own orphan baseline of zero: a
	# screen built here and left behind is still in the tree for every case after it.
	for screen in _built:
		if is_instance_valid(screen):
			screen.free()
	_built.clear()


func _style() -> SpriteStyle:
	return load(STYLE) as SpriteStyle


func _shipped() -> Dictionary:
	var file := JsonFile.read(CREDITS)
	assert_bool(file.ok).override_failure_message(
		"%s did not parse, so this suite measured nothing" % CREDITS).is_true()
	return file.data


func _open(credits: Dictionary) -> CreditsScreen:
	var screen := CreditsScreen.new()
	add_child(screen)
	_built.append(screen)
	screen.setup(CreditsMenu.of(credits), _style(), VIEWPORT)
	return screen


## Every visible Panel and non-empty Label, with the rect it actually DRAWS in. A label is
## measured at its string, narrowed to its box when it clips - the pause audit's rule, so a
## clipping label is measured at the box rather than at the text it would have been.
func _rects(screen: CreditsScreen) -> Array:
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


func test_no_page_draws_outside_the_window() -> void:
	var screen := _open(_shipped())
	var pages := 0
	for at in screen.menu().page_count():
		var rects := _rects(screen)
		assert_int(rects.size()).override_failure_message(
			"page %d drew nothing but its window, so this measured nothing" % at).is_greater(3)
		for entry: Variant in rects:
			var named: Array = entry
			var rect: Rect2 = named[1]
			assert_bool(Rect2(Vector2.ZERO, Vector2(VIEWPORT)).encloses(rect)) \
				.override_failure_message("on page %d, %s is drawn at %s, outside the %s window"
					% [at, named[0], rect, VIEWPORT]).is_true()
		pages += 1
		screen.menu().move(1)
		screen._paint()
	assert_int(pages).override_failure_message(
		"the shipped credits produced no pages at all").is_greater(3)


func test_nothing_sticks_out_of_the_window_it_is_drawn_in() -> void:
	var screen := _open(_shipped())
	for at in screen.menu().page_count():
		for entry: Variant in _rects(screen):
			var named: Array = entry
			var node: Node = named[2]
			var parent := node.get_parent()
			if parent == null or UiChrome.kind_of(parent) != UiChrome.FRAME:
				continue
			# The header band and the cursor are part of the window rather than of the room in
			# it, so they are measured against its outer rect. This screen has no cursor.
			if UiChrome.kind_of(node) == UiChrome.HEADER:
				continue
			var inner := UiChrome.inner_of(parent)
			var room := Rect2((parent as Control).global_position + inner.position, inner.size)
			assert_bool(room.encloses(named[1])).override_failure_message(
				"on page %d, %s %s sticks out of its window %s"
				% [at, named[0], named[1], room]).is_true()
		screen.menu().move(1)
		screen._paint()


func test_the_rows_are_distinct_and_go_down_the_page_in_order() -> void:
	# Containment is one-sided: twelve rows stacked on one line is inside every bound and
	# unreadable. So the drawn rows are required to be as many as the page has, at distinct
	# heights, in the order the page lists them.
	var screen := _open(_shipped())
	var page := screen.menu().current()
	var rows: Array[Label] = []
	for row: Label in screen._rows:
		if row.visible and not row.text.strip_edges().is_empty():
			rows.append(row)
	assert_int(rows.size()).override_failure_message(
		"the first page lists %d lines and %d were drawn" % [page.lines.size(), rows.size()]
		).is_greater(3)
	for i in rows.size() - 1:
		assert_float(rows[i + 1].global_position.y).override_failure_message(
			"'%s' and '%s' are drawn at the same height or out of order"
			% [rows[i].text, rows[i + 1].text]).is_greater(rows[i].global_position.y)


func test_the_screen_is_measured_at_the_capacity_it_declares() -> void:
	# The MAX_SAVE_SLOTS shape: the view declares ROWS_PER_PAGE, CreditsMenu can never emit more,
	# and this measures a page that is exactly full. A page that overflowed the window would be
	# invisible to every other gate here, because nothing headless looks at where a Label landed.
	var names: Array[String] = []
	for i in CreditsMenu.ROWS_PER_PAGE:
		names.append("Artist Name Number %d" % i)
	var screen := _open({"source": "Synthetic", "authors": names})
	while screen.menu().current().title != CreditsMenu.ARTISTS_TITLE:
		assert_bool(screen.menu().move(1)).is_true()
	screen._paint()
	var full := screen.menu().current()
	assert_int(full.lines.size()).is_equal(CreditsMenu.ROWS_PER_PAGE)
	for entry: Variant in _rects(screen):
		var named: Array = entry
		var rect: Rect2 = named[1]
		assert_bool(Rect2(Vector2.ZERO, Vector2(VIEWPORT)).encloses(rect)) \
			.override_failure_message("at capacity, %s is drawn at %s, outside the %s window"
				% [named[0], rect, VIEWPORT]).is_true()


func test_every_line_the_screen_can_draw_fits_without_being_trimmed() -> void:
	# The one that matters. The rows clip with an ellipsis so a stray line cannot draw out of the
	# window at runtime - but an artist trimmed to "William Thomps..." is a failed attribution,
	# and the licence this screen exists to satisfy asks for the name.
	#
	# Every line the menu can produce is measured, not just the page that happens to be showing:
	# a page nobody thought to look at is exactly where a too-wide name would sit.
	var screen := _open(_shipped())
	var row: Label = screen._rows[0]
	var font := row.get_theme_font("font")
	var size := row.get_theme_font_size("font_size")
	var room := row.size.x
	assert_float(room).override_failure_message(
		"the rows have no width, so measuring against them proves nothing").is_greater(100.0)
	var lines := screen.menu().all_lines()
	assert_int(lines.size()).override_failure_message(
		"the menu produced no lines, so this measured nothing").is_greater(40)
	var over: Array[String] = []
	for line in lines:
		var wide := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		if wide > room:
			over.append("'%s' is %.0fpx in a %.0fpx row" % [line, wide, room])
	assert_array(over).override_failure_message(
		"lines the screen would trim, each of which loses what it was drawn to say:\n  "
		+ "\n  ".join(over)).is_empty()
