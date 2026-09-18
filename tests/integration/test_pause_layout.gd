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
		"hp": PauseScreen.READOUT_CAPACITY, "max_hp": PauseScreen.READOUT_CAPACITY,
		"mp": PauseScreen.READOUT_CAPACITY, "max_mp": PauseScreen.READOUT_CAPACITY}


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


## The same screen with a bag and a gear list, so the Equipment pages can actually be opened. Every
## test here used to hand both empty, which is why the readout that sits in the band beside the purse -
## drawn on those pages and no others - was never once measured.
func _equipping_screen() -> PauseScreen:
	var rows: Array = []
	var names := ["Wanderer", "Companion2", "Companion3"]
	var art := ["quest_wanderer", "quest_scrapper", "quest_hermit"]
	for i in 3:
		rows.append(_member("m%d" % i, names[i], art[i]))
	var items: Array = [
		PauseMenu.ItemRow.of(&"longsword", "Longsword", 1, "Long.", &"weapon", true, "Atk +8"),
		PauseMenu.ItemRow.of(&"saber", "Saber", 1, "Curved.", &"weapon", false, "Atk +5"),
	]
	var gear: Array = [
		PauseMenu.GearRow.of(&"weapon", "Weapon", "Longsword", "Atk -8"),
		PauseMenu.GearRow.of(&"armor", "Armor"),
	]
	var screen := PauseScreen.new()
	add_child(screen)
	screen.setup(PauseMenu.of(_slots(GameConfig.MAX_SAVE_SLOTS), items,
		"Gold: 9999", gear, "Atk 18+4  Def 12+3", ["Level 12", "HP 188/188"], rows, true),
		_style(), VIEWPORT, FileSpriteSource.create(&"lpc32"))
	_screens.append(screen)
	return screen


## Walks the real menu to the candidate page, where the gear readout is drawn: Equipment, then WHO,
## then the slot. Named rather than counted, and it asserts it arrived - a page this never reached is
## how the readout went unmeasured in the first place.
func _to_the_candidates(screen: PauseScreen) -> void:
	while screen._menu.index() != PauseMenu.Row.EQUIP:
		screen._menu.move(1)
	screen._menu.confirm()
	screen._menu.confirm()
	screen._menu.confirm()
	assert_int(screen._menu.page()).override_failure_message(
		"the walk did not end on the candidate page").is_equal(PauseMenu.Page.EQUIP_PICK)
	screen._paint()
	assert_bool(screen._stats.visible).override_failure_message(
		"the gear readout is not drawn, so this measures nothing about it").is_true()


## Whether `outer` is a window `node` is drawn inside - directly, or through the header band.
func _holds(outer: Node, node: Node) -> bool:
	var at := node.get_parent()
	while at != null:
		if at == outer:
			return true
		at = at.get_parent()
	return false


## The room a window gives what it holds: its CONTENT rect, or the header BAND for the readouts that
## sit in it. The band is part of the window and not part of the room below it, so the two are
## different questions and were never asked of the band at all.
func _room_in(outer: Node, node: Node) -> Rect2:
	var band := node.get_parent() as Control
	if band != null and UiChrome.kind_of(band) == UiChrome.HEADER:
		return Rect2(band.global_position, band.size)
	var frame := outer as Control
	var inner := UiChrome.inner_of(frame)
	return Rect2(frame.global_position + inner.position, inner.size)


## The third question this file's own notes promise and never asked: nothing unrelated shares pixels.
## The battle and arena screens have asked it since M28; here it was written down and never
## implemented, and what it would have caught is the band at the top of the window.
func _assert_nothing_overlaps(screen: PauseScreen, page: String) -> void:
	var rects := _rects(screen)
	assert_int(rects.size()).override_failure_message(
		"the %s page drew nothing measurable, so this proves nothing" % page).is_greater(4)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i][1]
			var b: Rect2 = rects[j][1]
			var a_node: Node = rects[i][2]
			var b_node: Node = rects[j][2]
			if _holds(a_node, b_node):
				var room := _room_in(a_node, b_node)
				assert_bool(room.encloses(b)).override_failure_message(
					"on the %s page, %s %s sticks out of %s %s"
					% [page, rects[j][0], b, rects[i][0], room]).is_true()
				continue
			if _holds(b_node, a_node):
				var space := _room_in(b_node, a_node)
				assert_bool(space.encloses(a)).override_failure_message(
					"on the %s page, %s %s sticks out of %s %s"
					% [page, rects[i][0], a, rects[j][0], space]).is_true()
				continue
			assert_bool(a.intersects(b)).override_failure_message(
				"on the %s page, %s %s is drawn over %s %s"
				% [page, rects[i][0], a, rects[j][0], b]).is_false()


func test_nothing_on_the_equipment_page_is_drawn_over_anything_else() -> void:
	# The page the purse and the gear readout share, with a party beside them. Both readouts sit in
	# the window's band, which every other rule here skips: the purse ran into the readout's first
	# letter, and the readout ran out of the window and under the party panel (docs/DECISIONS.md).
	var screen := _equipping_screen()
	_to_the_candidates(screen)
	_assert_nothing_overlaps(screen, "the candidates")
	_assert_inside(screen, "the candidates")

func test_nothing_on_the_commands_is_drawn_over_anything_else() -> void:
	var screen := _screen()
	_assert_nothing_overlaps(screen, "top")

func test_the_band_draws_one_readout_at_a_time_inside_the_room_it_declares() -> void:
	# The capacity rule, for the band: the screen DECLARES how much room each readout gets, and this
	# measures strings that fill them. The purse steps aside while equipping, because a slot's title,
	# a purse and a gear readout together need more band than a window beside a party has.
	var screen := _equipping_screen()
	_to_the_candidates(screen)
	assert_bool(screen._purse.visible).override_failure_message(
		"the purse and the gear readout are both in the band, which is where they collided") \
		.is_false()
	var font := screen._purse.get_theme_font("font")
	var size := screen._purse.get_theme_font_size("font_size")
	for entry: Variant in [[screen._purse, PauseScreen.PURSE_WIDTH, "the purse"],
			[screen._stats, PauseScreen.STATS_WIDTH, "the gear readout"]]:
		var named: Array = entry
		var label: Label = named[0]
		assert_float(label.size.x).override_failure_message(
			"%s is not bounded to the room the screen declares for it" % named[2]) \
			.is_equal(float(named[1]))
		assert_bool(label.clip_text).override_failure_message(
			"%s would draw straight out of the band" % named[2]).is_true()
		assert_float(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x) \
			.override_failure_message("%s does not fit the room declared for it: '%s'"
			% [named[2], label.text]).is_less_equal(float(named[1]))
	# And a game that writes MORE than the room is trimmed rather than drawn out of the band. Nothing
	# the demo ships reaches this - test_world_equipment measures the real strings - so the trim is
	# proven on a string made for it, the way the shop's description bar is.
	screen.refresh(_slots(GameConfig.MAX_SAVE_SLOTS), [], "Gold: 123456789012", [],
		"Atk 9999+9999  Def 9999+9999", ["Level 12"], [], true)
	_assert_nothing_overlaps(screen, "readouts longer than their room")
	_assert_inside(screen, "readouts longer than their room")

func test_the_purse_is_in_the_band_on_every_page_that_is_not_equipping() -> void:
	# The other half of "one at a time": the purse is a readout of the whole game, and the pages that
	# hide it are the two exceptions rather than the rule.
	var screen := _equipping_screen()
	screen._paint()
	assert_bool(screen._purse.visible).override_failure_message(
		"the purse is not drawn on the command page").is_true()
	assert_bool(screen._stats.visible).is_false()

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
		assert_str(bar.numbers.text).is_equal("%d/%d"
			% [PauseScreen.READOUT_CAPACITY, PauseScreen.READOUT_CAPACITY])
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
