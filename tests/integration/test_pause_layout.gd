extends GdUnitTestSuite
## Where the pause menu PUTS things — its commands, its readouts, and the party beside them.
##
## test_slot_layout measures this screen's SAVE page and has since M39, because that page had a
## capacity somebody had to prove. Every other page had nothing: the commands, the bag, the
## equipment pages and the status readout were as unmeasured as the shop counter was, and the
## party panel M42 adds is new surface entirely.
##
## The rules are the battle screen's, for its reasons: a window is not a peer of what is inside
## it, a cursor covers a whole row or none of one, and nothing unrelated shares pixels.

const VIEWPORT := Vector2i(320, 180)

var _screens: Array[PauseScreen] = []


func after_test() -> void:
	for screen in _screens:
		if screen != null and is_instance_valid(screen):
			screen.free()
	_screens.clear()


func _style() -> SpriteStyle:
	return load("res://data/styles/lpc32.tres") as SpriteStyle


func _slots(count: int) -> Array[SlotSummary]:
	var out: Array[SlotSummary] = []
	for i in count:
		out.append(SlotSummary.empty())
	return out


## A member row in the shape the world builds one - long name, full numbers, a real character so
## a face is actually cut. Measured at names longer than the demo's, which is the capacity rule:
## a panel that holds "You" and not "Companion2" is one that fails the day somebody is recruited.
func _member(id: String, name: String, character: String) -> Dictionary:
	return {"id": id, "name": name, "character": character, "level": 12,
		"hp": 188, "max_hp": 188, "mp": 144, "max_mp": 144}


func _screen(members := 3) -> PauseScreen:
	var rows: Array = []
	var names := ["Wanderer", "Companion2", "Companion3"]
	var art := ["quest_wanderer", "quest_scrapper", "quest_hermit"]
	for i in members:
		rows.append(_member("m%d" % i, names[i], art[i]))
	var screen := PauseScreen.new()
	add_child(screen)
	screen.setup(PauseMenu.of(_slots(GameConfig.MAX_SAVE_SLOTS), [],
		"Gold: 9999", [], "Atk 18+4   Def 12+3", ["Level 12", "HP 188/188"], rows, true),
		_style(), VIEWPORT, FileSpriteSource.create(&"lpc32"))
	_screens.append(screen)
	return screen


func _rects(screen: PauseScreen) -> Array:
	var out: Array = []
	for node in SceneHelpers.find_all_by_class(screen, "Panel"):
		var frame := node as Panel
		if frame.visible:
			out.append([_name_of(screen, frame), Rect2(frame.global_position, frame.size), frame])
	for node in SceneHelpers.find_all_by_class(screen, "TextureRect"):
		var face := node as TextureRect
		if face.visible:
			out.append([_name_of(screen, face), Rect2(face.global_position, face.size), face])
	for node in SceneHelpers.find_all_by_class(screen, "Label"):
		var label := node as Label
		if not label.visible or label.text.strip_edges().is_empty():
			continue
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
		if label.clip_text and label.size.x > 0.0:
			measured.x = minf(measured.x, label.size.x)
		out.append([_name_of(screen, label) + " '" + label.text + "'",
			Rect2(label.global_position, Vector2(measured.x, float(size))), label])
	return out


func _name_of(screen: PauseScreen, node: Node) -> String:
	var parts: Array[String] = []
	var at := node
	while at != null and at != screen:
		var parent := at.get_parent()
		if parent == null:
			break
		parts.push_front("child %d (%s)" % [at.get_index(), at.get_class()])
		at = parent
	return " > ".join(parts) if not parts.is_empty() else node.get_class()


func _assert_inside(screen: PauseScreen, page: String) -> void:
	var rects := _rects(screen)
	assert_int(rects.size()).override_failure_message(
		"the %s page drew nothing measurable, so this proves nothing" % page).is_greater(4)
	for entry: Variant in rects:
		var named: Array = entry
		var rect: Rect2 = named[1]
		assert_float(rect.end.x).override_failure_message(
			"on the %s page, %s runs to x=%.0f in a %dpx window"
			% [page, named[0], rect.end.x, VIEWPORT.x]).is_less_equal(float(VIEWPORT.x))
		assert_float(rect.end.y).override_failure_message(
			"on the %s page, %s runs to y=%.0f in a %dpx window"
			% [page, named[0], rect.end.y, VIEWPORT.y]).is_less_equal(float(VIEWPORT.y))
		assert_float(rect.position.x).is_greater_equal(0.0)
		assert_float(rect.position.y).is_greater_equal(0.0)


## Everything a window holds stays inside that window's CONTENT rect - not its outer one, which
## includes the border and the header band and would pass a row hanging over the bottom edge.
func _assert_contained(screen: PauseScreen, page: String) -> void:
	for entry: Variant in _rects(screen):
		var named: Array = entry
		var node: Node = named[2]
		var parent := node.get_parent()
		if parent == null or UiChrome.kind_of(parent) != UiChrome.FRAME:
			continue
		if UiChrome.kind_of(node) == UiChrome.HEADER or UiChrome.kind_of(node) == UiChrome.SELECT:
			continue
		var inner := UiChrome.inner_of(parent)
		var room := Rect2((parent as Control).global_position + inner.position, inner.size)
		assert_bool(room.encloses(named[1])).override_failure_message(
			"on the %s page, %s %s sticks out of its window %s"
			% [page, named[0], named[1], room]).is_true()


func test_the_commands_stay_inside_the_window() -> void:
	_assert_inside(_screen(), "top")
	_assert_contained(_screen(), "top")

func test_the_party_stays_inside_the_window() -> void:
	# The panel M42 adds, at the capacity a party can reach - three members with names longer
	# than the demo's and numbers in the hundreds, which is where a block runs out of room.
	var screen := _screen()
	assert_object(screen._party).override_failure_message(
		"a party of three drew no party panel").is_not_null()
	_assert_contained(screen, "party")

func test_every_member_gets_a_block_with_a_face_and_two_bars() -> void:
	# Containment cannot see a panel that drew nothing. One face, one name and two bars per
	# member, counted.
	var screen := _screen()
	assert_int(screen._member_names.size()).is_equal(3)
	var drawn := 0
	for label: Label in screen._member_names:
		if label.visible and not label.text.strip_edges().is_empty():
			drawn += 1
	assert_int(drawn).override_failure_message(
		"a party of three drew %d names" % drawn).is_equal(3)
	for face: TextureRect in screen._faces:
		assert_bool(face.visible).override_failure_message(
			"a member's face is not drawn").is_true()
	for bar: UiChrome.Bar in screen._hp_bars:
		assert_str(bar.numbers.text).is_equal("188/188")
	for bar: UiChrome.Bar in screen._mp_bars:
		assert_bool(bar.root.visible).is_true()
	# And they go DOWN the panel, one per member. Containment cannot see three blocks stacked on
	# one line - that is comfortably inside any window, and it is what a pitch of zero draws.
	for i in screen._member_names.size() - 1:
		assert_float(screen._member_names[i + 1].global_position.y).override_failure_message(
			"members %d and %d are drawn on the same line" % [i, i + 1]) \
			.is_greater(screen._member_names[i].global_position.y)

func test_a_party_of_one_draws_no_party_panel() -> void:
	# The control. A window listing one person is a question whose answer it already has - and a
	# panel that appeared anyway would take a third of the screen from the commands for nothing.
	var screen := _screen(1)
	assert_object(screen._party).override_failure_message(
		"a game with nobody recruited drew a party panel anyway").is_null()
	_assert_inside(screen, "solo")

func test_the_cursor_covers_the_row_it_is_on_and_moves_with_it() -> void:
	var screen := _screen()
	assert_bool(screen._select.visible).is_true()
	var first := screen.selected_row()
	assert_object(first).is_not_null()
	var bar := Rect2(screen._select.global_position, screen._select.size)
	assert_bool(bar.has_point(first.global_position)).override_failure_message(
		"the cursor is not over the row it reports as chosen").is_true()
	screen._menu.move(1)
	screen._paint()
	var second := screen.selected_row()
	assert_object(second).is_not_equal(first)
	var moved := Rect2(screen._select.global_position, screen._select.size)
	assert_bool(moved.has_point(second.global_position)).override_failure_message(
		"the cursor moved a row and the bar stayed put").is_true()

func test_the_status_page_has_no_cursor_at_all() -> void:
	# A readout, so nothing is "chosen" - a bar on a page with no verb points at something that
	# does not exist. The rule PauseMenu.confirm() already answers NONE for, asserted on screen.
	var screen := _screen()
	while screen._menu.top_row(screen._menu.index()) != PauseMenu.Row.STATUS:
		screen._menu.move(1)
	screen._menu.confirm()
	# With a PARTY, Status asks whose first - which is a page with a verb on it, so the cursor is
	# still real there. One more confirm reaches the readout itself.
	if screen._menu.page() == PauseMenu.Page.MEMBER:
		assert_object(screen.selected_row()).override_failure_message(
			"the page asking WHOSE status has no cursor, and it is a question").is_not_null()
		screen._menu.confirm()
	screen._paint()
	assert_int(screen._menu.page()).is_equal(PauseMenu.Page.STATUS)
	assert_object(screen.selected_row()).override_failure_message(
		"the status page reports a chosen row").is_null()
	assert_bool(screen._select.visible).override_failure_message(
		"a cursor is drawn on a page with nothing to press").is_false()


func test_the_status_readout_is_drawn_as_plainly_as_it_reads() -> void:
	# A page with no verb has no chosen row, so every line on it is lit the SAME - and lit at
	# all. Drawn in the quiet colour an unchosen command uses, a readout would read as a list of
	# things the player has failed to select.
	var screen := _screen()
	while screen._menu.top_row(screen._menu.index()) != PauseMenu.Row.STATUS:
		screen._menu.move(1)
	screen._menu.confirm()
	if screen._menu.page() == PauseMenu.Page.MEMBER:
		screen._menu.confirm()
	screen._paint()
	assert_int(screen._menu.page()).is_equal(PauseMenu.Page.STATUS)
	var text := screen._style.ui_color("text")
	var lines := 0
	for i in screen._rows.size():
		var row := screen._rows[i]
		if not row.visible or row.text.strip_edges().is_empty():
			continue
		lines += 1
		assert_that(row.get_theme_color("font_color")).override_failure_message(
			"status line '%s' is drawn in the colour an unchosen row uses" % row.text) \
			.is_equal(text)
	assert_int(lines).override_failure_message(
		"the status page drew nothing, so this measured no colour at all").is_greater(1)
