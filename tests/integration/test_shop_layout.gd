extends GdUnitTestSuite
## Where the shop counter actually PUTS things, measured off the nodes it built.
##
## Written BEFORE the counter was rebuilt on the chrome, and against the version that shipped, so
## it is proven to measure something before the screen moves underneath it. That order matters
## more here than anywhere else in this milestone: the counter is the one screen in the game that
## had NO layout gate at all - eighteen milestones of prices, quantities and a keeper's window,
## and nothing had ever asserted where any of it lands.
##
## The rules are the battle screen's, because a window is a window: nothing unrelated shares
## pixels, everything inside a window stays inside its CONTENT rect, and the cursor covers a whole
## row or none of it. A shop adds one of its own - the price column is right-aligned, which is
## most of what makes a list of numbers readable, and nothing measured it.

const VIEWPORT := Vector2i(320, 180)

var _screens: Array[ShopScreen] = []


func after_test() -> void:
	for screen in _screens:
		if screen != null and is_instance_valid(screen):
			screen.free()
	_screens.clear()


func _style() -> SpriteStyle:
	return load("res://data/styles/dusk16.tres") as SpriteStyle


func _row(id: StringName, price: int, owned := 0) -> ShopMenu.ShopRow:
	return ShopMenu.ShopRow.of(id, String(id).capitalize(), price, owned,
		"About the %s." % id)


## A counter with a long list and long names - the capacity a shop can actually reach, rather
## than the two rows the demo's smith happens to sell.
func _screen(gold := 100) -> ShopScreen:
	var stock: Array[ShopMenu.ShopRow] = []
	for i in 6:
		stock.append(_row(StringName("longish_name_%d" % i), 1000 + i, i))
	var screen := ShopScreen.new()
	add_child(screen)
	screen.setup(ShopMenu.of(stock, [_row(&"tonic", 5, 2)], gold,
		"Wares, traveller!", "Anything else?", "No coin, no cure."),
		_style(), VIEWPORT, "The smith")
	_screens.append(screen)
	return screen


## Every rectangle the player can see. The battle audit's shape - see its own notes for why
## containers are not peers and why a Label is measured through its font rather than its size.
func _rects(screen: ShopScreen) -> Array:
	var out: Array = []
	for node in SceneHelpers.find_all_by_class(screen, "Panel"):
		var frame := node as Panel
		if frame.visible:
			out.append([_name_of(screen, frame), Rect2(frame.global_position, frame.size), frame])
	for node in SceneHelpers.find_all_by_class(screen, "ColorRect"):
		var rect := node as ColorRect
		if rect.visible and rect.size < Vector2(VIEWPORT):
			out.append([_name_of(screen, rect), Rect2(rect.global_position, rect.size), rect])
	for node in SceneHelpers.find_all_by_class(screen, "Label"):
		var label := node as Label
		if not label.visible or label.text.strip_edges().is_empty():
			continue
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
		# A label that CLIPS draws no wider than its own box, whatever its string would measure.
		# Without this the audit reports the width a name would have had if it had been allowed
		# to run - which is the number the clipping exists to prevent, so the gate would go on
		# failing after the fix and read as though nothing had changed.
		if label.clip_text and label.size.x > 0.0:
			measured.x = minf(measured.x, label.size.x)
		var lines := 1
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.size.x > 0.0:
			var wrapped := font.get_multiline_string_size(label.text,
				HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size)
			lines = maxi(1, int(round(wrapped.y / maxf(font.get_height(size), 1.0))))
			measured.x = minf(measured.x, label.size.x)
		var at := label.global_position
		# A right-aligned label draws its text at the END of its box, which for the price column
		# is the whole point - measured where it is DRAWN, not where its box starts.
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and label.size.x > 0.0:
			at.x += label.size.x - measured.x
		out.append([_name_of(screen, label) + " '" + label.text + "'",
			Rect2(at, Vector2(measured.x, float(size * lines))), label])
	return out


func _name_of(screen: ShopScreen, node: Node) -> String:
	var parts: Array[String] = []
	var at := node
	while at != null and at != screen:
		var parent := at.get_parent()
		if parent == null:
			break
		parts.push_front("child %d (%s)" % [at.get_index(), at.get_class()])
		at = parent
	return " > ".join(parts) if not parts.is_empty() else node.get_class()


func _assert_inside_the_window(screen: ShopScreen, page: String) -> void:
	var rects := _rects(screen)
	assert_int(rects.size()).override_failure_message(
		"the %s page drew nothing measurable, so this proves nothing" % page).is_greater(3)
	for entry: Variant in rects:
		var named: Array = entry
		var rect: Rect2 = named[1]
		assert_float(rect.end.x).override_failure_message(
			"on the %s page, %s runs to x=%.0f in a %dpx window"
			% [page, named[0], rect.end.x, VIEWPORT.x]).is_less_equal(float(VIEWPORT.x))
		assert_float(rect.end.y).override_failure_message(
			"on the %s page, %s runs to y=%.0f in a %dpx window"
			% [page, named[0], rect.end.y, VIEWPORT.y]).is_less_equal(float(VIEWPORT.y))
		assert_float(rect.position.x).override_failure_message(
			"on the %s page, %s starts left of the window" % [page, named[0]]) \
			.is_greater_equal(0.0)
		assert_float(rect.position.y).override_failure_message(
			"on the %s page, %s starts above the window" % [page, named[0]]) \
			.is_greater_equal(0.0)


func test_the_counter_stays_inside_the_window() -> void:
	_assert_inside_the_window(_screen(), "top")

func test_the_buy_page_stays_inside_the_window() -> void:
	var screen := _screen()
	while screen.menu().index() != ShopMenu.Row.BUY:
		screen.menu().move(1)
	screen.menu().confirm()
	screen._paint()
	_assert_inside_the_window(screen, "buy")

func test_a_deal_being_sized_stays_inside_the_window() -> void:
	# The purse becomes a running total while the keeper is asking how many, and the keeper's
	# window carries a different sentence - the widest state this screen has.
	# Enough coin to be ASKED how many: the counter refuses an unaffordable row rather than
	# asking, which is its own rule and not the state this measures.
	var screen := _screen(9999)
	# Named, never counted: BUY is a row of an enum, and inserting a row must not re-aim this at
	# whatever now sits where it used to be.
	while screen.menu().index() != ShopMenu.Row.BUY:
		screen.menu().move(1)
	screen.menu().confirm()
	screen.menu().confirm()
	screen._paint()
	assert_bool(screen.menu().asking()).override_failure_message(
		"the counter never asked how many, so this measured the wrong page").is_true()
	_assert_inside_the_window(screen, "asking")

func test_every_row_of_the_list_is_drawn_on_its_own_line() -> void:
	# Containment is one-sided: a counter that stacked every row on one line, or drew none of
	# them, is comfortably inside the window. This is the constraint in the units the design
	# declares - one row per item, going down.
	var screen := _screen()
	while screen.menu().index() != ShopMenu.Row.BUY:
		screen.menu().move(1)
	screen.menu().confirm()
	screen._paint()
	var rows: Array = []
	for entry: Variant in _rects(screen):
		var named: Array = entry
		if str(named[0]).contains("Longish Name"):
			rows.append(named[1])
	assert_int(rows.size()).override_failure_message(
		"a list of six items drew %d rows" % rows.size()).is_equal(6)
	for i in rows.size() - 1:
		var here: Rect2 = rows[i]
		var next: Rect2 = rows[i + 1]
		assert_float(next.position.y).override_failure_message(
			"rows %d and %d are drawn on the same line" % [i, i + 1]) \
			.is_greater(here.position.y)

func test_a_price_is_drawn_right_of_the_name_it_belongs_to() -> void:
	# The column that makes a list of goods readable, and the reason the price is its own
	# right-aligned Label rather than padding inside the row's text: spaces cannot align a font
	# whose digits are not all one width. Nothing had ever measured it.
	var screen := _screen()
	while screen.menu().index() != ShopMenu.Row.BUY:
		screen.menu().move(1)
	screen.menu().confirm()
	screen._paint()
	var names: Array = []
	var prices: Array = []
	for entry: Variant in _rects(screen):
		var named: Array = entry
		if str(named[0]).contains("Longish Name"):
			names.append(named[1])
		elif str(named[0]).contains("g  x") or str(named[0]).contains("000g"):
			prices.append(named[1])
	assert_int(prices.size()).override_failure_message(
		"no price was drawn at all: %s" % [prices]).is_greater(0)
	for price: Rect2 in prices:
		for name_rect: Rect2 in names:
			# On the same line, the price sits entirely to the right of the name.
			if absf(price.position.y - name_rect.position.y) > 2.0:
				continue
			assert_float(price.position.x).override_failure_message(
				"a price at %s is drawn over the name at %s" % [price, name_rect]) \
				.is_greater_equal(name_rect.end.x)

func test_the_help_line_names_keys_the_game_actually_binds() -> void:
	# The counter told the player to press Z, which is bound to nothing: `interact` is Space,
	# Enter and E, and `cancel` is Escape and X. A player at the counter following it exactly
	# would conclude the shop was broken.
	var screen := _screen()
	var help := ""
	for node in SceneHelpers.find_all_by_class(screen, "Label"):
		var text := (node as Label).text
		if text.contains("choose") or text.contains("back"):
			help = text
	assert_str(help).override_failure_message("the counter offers no help line at all") \
		.is_not_empty()
	for key in ["Z", "Y"]:
		assert_bool(help.contains(key)).override_failure_message(
			"the counter tells the player to press %s, which nothing is bound to: '%s'"
			% [key, help]).is_false()
