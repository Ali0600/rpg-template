extends GdUnitTestSuite
## The two screens that draw one row per save slot, measured AT the capacity the data allows.
##
## `GameConfig.save_slots` is a designer's number and both of these screens lay a row out per
## slot down a 180px window, so a big enough value walks the last rows off the bottom of it -
## silently, with every other gate green, because nothing headless looks at where a Label ended
## up. Measured before this suite was written: at 16 slots BOTH screens overflow.
##
## So `MAX_SAVE_SLOTS` is the capacity the data DECLARES, `GameConfig.problems()` refuses more,
## and this measures the screens at exactly it - the MAX_PARTY/MAX_FOES shape, which M27.1 found
## had been declared and never enforced. Three things, and any two of them without the third is
## the hole this pattern exists to close.
##
## Containment is not the whole assertion, and that is M36's lesson paid forward: a bounds check
## passes the DEGENERATE cases too, because a screen that drew nothing, or drew every row one
## pixel tall on top of itself, is comfortably inside any window. So every row is required to be
## drawn, to be distinct, and to be in slot order.

const VIEWPORT := Vector2i(320, 180)
const STYLE := "res://data/styles/dusk16.tres"

func _style() -> SpriteStyle:
	return load(STYLE) as SpriteStyle

## `count` slots, all empty - the widest a row's LABEL never is, and irrelevant here: this suite
## measures how far DOWN the rows go, which is a function of how many there are.
func _slots(count: int) -> Array[SlotSummary]:
	var out: Array[SlotSummary] = []
	for i in count:
		out.append(SlotSummary.empty())
	return out

## Every visible Label under a screen, with its rect in screen space.
func _rows_of(screen: CanvasLayer) -> Array:
	var out: Array = []
	_collect(screen, Vector2.ZERO, out)
	return out

func _collect(node: Node, offset: Vector2, out: Array) -> void:
	for child in node.get_children():
		var control := child as Control
		if control == null:
			continue
		var at := offset + control.position
		var label := control as Label
		if label != null and label.visible and not label.text.strip_edges().is_empty():
			out.append([label.text, Rect2(at, label.size)])
		if control.visible:
			_collect(control, at, out)

func _assert_inside_the_window(rows: Array, which: String) -> void:
	assert_int(rows.size()).override_failure_message(
		"%s drew no text at all, so this measured nothing" % which).is_greater(1)
	for entry: Variant in rows:
		var named: Array = entry
		var rect: Rect2 = named[1]
		assert_float(rect.end.y).override_failure_message(
			"on %s, '%s' runs to y=%.0f in a %dpx window - the row is drawn off the bottom"
			% [which, named[0], rect.end.y, VIEWPORT.y]).is_less_equal(float(VIEWPORT.y))
		assert_float(rect.end.x).override_failure_message(
			"on %s, '%s' runs to x=%.0f in a %dpx window"
			% [which, named[0], rect.end.x, VIEWPORT.x]).is_less_equal(float(VIEWPORT.x))
		assert_float(rect.position.y).override_failure_message(
			"on %s, '%s' starts above the window" % [which, named[0]]).is_greater_equal(0.0)

func test_the_declared_capacity_is_what_the_data_allows() -> void:
	# The three-way pin: this suite measures at MAX_SAVE_SLOTS, so if the config let a game ship
	# more than that, the measurement would be of a screen no game runs.
	var config := GameConfig.new()
	config.save_slots = GameConfig.MAX_SAVE_SLOTS
	assert_array(config.problems()).override_failure_message(
		"the config refuses the very capacity this suite measures at").is_empty()
	config.save_slots = GameConfig.MAX_SAVE_SLOTS + 1
	assert_str(", ".join(config.problems())).override_failure_message(
		"a game may ship more slots than either screen can draw").contains("save_slots")

func test_the_save_point_draws_every_slot_inside_the_window_at_capacity() -> void:
	var screen := SaveScreen.new()
	add_child(screen)
	screen.setup(SaveMenu.of(_slots(GameConfig.MAX_SAVE_SLOTS)), _style(), VIEWPORT)
	await get_tree().process_frame
	var rows := _rows_of(screen)
	_assert_inside_the_window(rows, "the save point at capacity")

	# Containment alone would pass a screen that drew nothing, or stacked every row on one line.
	# The rows are counted and required to be DISTINCT and in order, which is the constraint in
	# the units the design declares: one row per slot, going down.
	var slot_rows: Array = []
	for entry: Variant in rows:
		var named: Array = entry
		if str(named[0]).contains("Slot "):
			slot_rows.append(named)
	assert_int(slot_rows.size()).override_failure_message(
		"the save point drew %d slot rows for %d slots"
		% [slot_rows.size(), GameConfig.MAX_SAVE_SLOTS]).is_equal(GameConfig.MAX_SAVE_SLOTS)
	for i in slot_rows.size() - 1:
		var here: Rect2 = (slot_rows[i] as Array)[1]
		var next: Rect2 = (slot_rows[i + 1] as Array)[1]
		assert_float(next.position.y).override_failure_message(
			"slot rows %d and %d are drawn on top of each other" % [i, i + 1]).is_greater(
			here.position.y)
	screen.free()

func test_the_pause_menus_slot_page_stays_inside_the_window_at_capacity() -> void:
	# The same measurement on the OLDER screen, which had the same latent hole and no test: this
	# is not a new defect the save point introduced, it is one it made visible.
	var screen := PauseScreen.new()
	add_child(screen)
	var menu := PauseMenu.of(_slots(GameConfig.MAX_SAVE_SLOTS))
	screen.setup(menu, _style(), VIEWPORT)
	# Onto the slot list: Resume, Items, Equipment, Status, Save.
	menu.move(PauseMenu.Row.SAVE)
	menu.confirm()
	screen.refresh(_slots(GameConfig.MAX_SAVE_SLOTS))
	await get_tree().process_frame
	assert_int(menu.page()).override_failure_message(
		"this measured the top page, not the slot list").is_equal(PauseMenu.Page.SAVE)
	_assert_inside_the_window(_rows_of(screen), "the pause menu's slot page at capacity")
	screen.free()

func test_a_single_slot_still_draws() -> void:
	# The other degenerate end. A capacity check that only ever runs at the maximum says nothing
	# about the one-slot game, which is the shape a template with one save is meant to allow.
	var screen := SaveScreen.new()
	add_child(screen)
	screen.setup(SaveMenu.of(_slots(1)), _style(), VIEWPORT)
	await get_tree().process_frame
	var rows := _rows_of(screen)
	_assert_inside_the_window(rows, "the save point with one slot")
	var joined := ""
	for entry: Variant in rows:
		joined += str((entry as Array)[0]) + " | "
	assert_str(joined).override_failure_message(
		"a one-slot save point drew no slot row: %s" % joined).contains("Slot 1")
	screen.free()


func test_the_save_point_marks_the_slot_it_would_write_to() -> void:
	# The rows say what is in each slot; only the cursor says which one a press would overwrite.
	# It used to be a "*" written into the front of the row's own text, which is why this suite
	# could see it by reading Labels - a bar is a different node and needs its own assertion, or
	# a save point that marked nothing would pass every measurement here.
	var screen := SaveScreen.new()
	add_child(screen)
	screen.setup(SaveMenu.of(_slots(3)), _style(), VIEWPORT)
	await get_tree().process_frame
	assert_bool(screen._select.visible).override_failure_message(
		"no slot is marked, so the screen cannot say where it would write").is_true()
	var first := screen.selected_row()
	assert_object(first).is_not_null()
	var bar := Rect2(screen._select.global_position, screen._select.size)
	assert_bool(bar.has_point(first.global_position)).override_failure_message(
		"the cursor is not over the row it reports as chosen").is_true()
	# And it MOVES. A bar parked on row 0 marks something true at the start and wrong after.
	screen.menu().move(1)
	screen._paint()
	var second := screen.selected_row()
	assert_object(second).is_not_equal(first)
	var moved := Rect2(screen._select.global_position, screen._select.size)
	assert_bool(moved.has_point(second.global_position)).override_failure_message(
		"the cursor moved to a different row and the bar stayed put").is_true()
	assert_vector(moved.position).is_not_equal(bar.position)
	screen.free()
