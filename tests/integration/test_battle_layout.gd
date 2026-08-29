extends GdUnitTestSuite
## Where the battle screen actually PUTS things, measured off the nodes it built.
##
## The sibling of test_dialog_box_layout, and it exists for the same reason: every headless
## gate can pass while two things are drawn on the same pixels, because pressing through a
## fight never looks at it. M25 shipped exactly that - inserting the Magic command grew the
## command stack by one row, the stack grows UPWARD from the bottom, and its new top row
## landed on the hero's status line, which had itself just grown an "MP 8/8" tail. Two
## changes, each fine alone, colliding in a band nothing measured.
##
## So this asserts RECTS between REAL nodes. A test that re-derived the positions from the
## same arithmetic the screen uses would agree with it while both were wrong.
##
## Two rules borrowed from the lessons file, both load-bearing here:
##   * only EFFECTIVELY VISIBLE things are peers - an invisible row occupies its line and the
##     user sees nothing there;
##   * a full-screen COVER is not a peer at all. The backdrop overlaps everything by
##     construction, which is its job.

const VIEWPORT := Vector2i(320, 180)

var _screens: Array[BattleScreen] = []


func after_test() -> void:
	for screen in _screens:
		if screen != null and is_instance_valid(screen):
			screen.free()
	_screens.clear()


## The player's side of a fight, built in code - this suite is about PIXELS, and pinning it to
## the designer's numbers would make every rebalance a failure in a file about layout. The
## magic curve is real, though: an MP line only appears for a game that has one.
func _combat(magic := true) -> CombatDef:
	var out := CombatDef.new()
	out.id = &"test_combat"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 5
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	# Zero base is what a game with no magic ACTUALLY looks like - not a caster who has spent
	# everything, which still draws the line. The control below depends on the difference.
	out.base_mp = 8 if magic else 0
	out.mp_per_level = 3 if magic else 0
	out.xp_curve = [10, 12]
	out.attack_cue_frames = 30
	out.defend_cue_frames = 40
	out.timed_window_frames = 6
	out.message_frames = 30
	return out

func _enemy() -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_foe"
	out.name = "Test Foe"
	out.character = &"quest_warden"
	out.max_hp = 99
	out.attack = 1
	out.defense = 0
	out.xp = 0
	out.moves = [{"name": "Clout", "power": 0}]
	return out


## A screen built directly, so a fight can be staged at any level with any spell list without
## walking a map to one. The world's own wiring is proven next door in test_world_battles;
## what is measured here is the screen, so the screen is what is built.
func _screen(level := 1, mp := 8, spells: Array = [], items: Array = [],
		magic := true) -> BattleScreen:
	var screen := BattleScreen.new()
	add_child(screen)
	var combat := _combat(magic)
	var logic := BattleLogic.of(combat, _enemy(), combat.max_hp(level), 0, level, items,
		"map/foe", 7, 0, 0, mp, spells)
	screen.setup(logic, load("res://data/styles/dusk16.tres") as SpriteStyle, VIEWPORT,
		FileSpriteSource.create(&"dusk16"), &"quest_hero", &"quest_warden")
	_screens.append(screen)
	return screen


func _spell(name: String, cost: int) -> BattleLogic.SpellRow:
	return BattleLogic.SpellRow.of(StringName(name.to_lower()), name, cost,
		SpellDef.Kind.ATTACK, 5, 0)


## Every rectangle the player can actually see, with the name of the node that owns it.
##
## ColorRects and Labels both, because the collision that shipped was text on text and the
## next one could as easily be text on a bar. A Label's `size` is only meaningful once it has
## laid out, so its height comes from the font it was given - what is being asserted is where
## a line of text SITS, and a zero-height rect intersects nothing.
func _visible_rects(screen: BattleScreen) -> Array:
	var out: Array = []
	# A bar's FILL is drawn inside its own track by construction - that is what a bar is - so
	# the two are one widget rather than two peers. Excluded by identity rather than by "one
	# rect contains another", which would also excuse a label genuinely buried under a panel.
	var fills: Array[ColorRect] = [screen._hero_fill, screen._foe_fill]
	for node in SceneHelpers.find_all_by_class(screen, "ColorRect"):
		var rect := node as ColorRect
		# The backdrop is a COVER, not a peer: it is the whole screen by construction, and
		# auditing it against everything drawn on top of it would report the entire screen.
		if not rect.visible or rect.size >= Vector2(VIEWPORT) or fills.has(rect):
			continue
		out.append([_name_of(screen, rect), Rect2(rect.global_position, rect.size)])
	for node in SceneHelpers.find_all_by_class(screen, "Label"):
		var label := node as Label
		if not label.visible or label.text.strip_edges().is_empty():
			continue
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
		# Anchored at the label's own drawn origin rather than at its control rect, which for
		# an unsized Label is the whole viewport and would intersect everything.
		var at := label.global_position
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and label.size.x > 0.0:
			at.x += label.size.x - measured.x
		out.append([_name_of(screen, label) + " '" + label.text + "'",
			Rect2(at, Vector2(measured.x, float(size)))])
	return out


## A readable name for a node, so a failure says WHICH two things collided rather than handing
## back two rectangles to work out.
func _name_of(screen: BattleScreen, node: Node) -> String:
	var index := 0
	for child in screen.get_children():
		if child == node:
			return "child %d (%s)" % [index, node.get_class()]
		index += 1
	return node.get_class()


## The audit itself: no two visible things share pixels. Named separately from the tests so
## every page below is one line and the failure message says which page it was.
func _assert_nothing_overlaps(screen: BattleScreen, page: String) -> void:
	var rects := _visible_rects(screen)
	assert_int(rects.size()).override_failure_message(
		"the %s page drew nothing measurable, so this proves nothing" % page).is_greater(3)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i][1]
			var b: Rect2 = rects[j][1]
			assert_bool(a.intersects(b)).override_failure_message(
				"on the %s page, %s %s is drawn over %s %s"
				% [page, rects[i][0], a, rects[j][0], b]).is_false()


func test_nothing_on_the_command_menu_is_drawn_over_anything_else() -> void:
	# The reported bug, as geometry: "You Lv1 20/20 MP 8/8" and "> Attack" on the same pixels.
	var screen := _screen()
	_assert_nothing_overlaps(screen, "command")

func test_nothing_on_the_spell_page_is_drawn_over_anything_else() -> void:
	var screen := _screen(1, 8, [_spell("Ember", 3), _spell("Mend", 4)])
	screen.logic().move(BattleLogic.Row.MAGIC)
	screen.logic().press()
	screen._paint()
	_assert_nothing_overlaps(screen, "spell")

func test_nothing_on_the_item_page_is_drawn_over_anything_else() -> void:
	var screen := _screen(1, 8, [], [BattleLogic.ItemRow.of(&"tonic", "Tonic", 2, 10)])
	screen.logic().move(BattleLogic.Row.ITEM)
	screen.logic().press()
	screen._paint()
	_assert_nothing_overlaps(screen, "item")

func test_nothing_mid_cue_is_drawn_over_anything_else() -> void:
	# The cue and the message are the two things that only exist mid-swing, so a page that is
	# clean at rest can still collide the moment the fight is actually running.
	var screen := _screen()
	screen.logic().press()
	for i in 40:
		screen.logic().tick()
	screen._paint()
	_assert_nothing_overlaps(screen, "mid-cue")

## The visible rows, in order, with their cursor prefix intact.
func _drawn_rows(screen: BattleScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for row in screen._rows:
		if row.visible:
			out.append(row.text)
	return out

func _long_page(screen: BattleScreen) -> void:
	screen.logic().move(BattleLogic.Row.MAGIC)
	screen.logic().press()
	assert_int(screen.logic().phase()).is_equal(BattleLogic.Phase.SPELLS)
	screen._paint()

func _six_spells() -> Array:
	var out: Array = []
	for name in ["Ember", "Mend", "Lull", "Gale", "Frost", "Ward"]:
		out.append(_spell(name, 1))
	return out

func test_a_page_longer_than_the_window_still_fits_in_it() -> void:
	# The bound. Six spells against four slots: the old pool grew a label per row and would
	# have put the top one up among the fighters, so this is the case that could not be
	# written before there was a window at all.
	var screen := _screen(1, 8, _six_spells())
	_long_page(screen)
	assert_int(_drawn_rows(screen).size()).override_failure_message(
		"a six-row page drew more rows than the window has slots").is_equal(4)
	for row in screen._rows:
		assert_float(row.position.y).override_failure_message(
			"a row is drawn above the band the layout reserves for it").is_greater_equal(
			BattleScreen.ROWS_Y)
	_assert_nothing_overlaps(screen, "six-spell")

func test_every_row_of_a_long_page_can_be_reached_by_cursoring_down() -> void:
	# The other half, and the one that matters more: a window that BOUNDS the page is only
	# correct if it also SCROLLS it. A window that clamped instead would pass the test above
	# and quietly make the last two spells uncastable - the exact truncation the pool was
	# widened to fix, returning by another door.
	var screen := _screen(1, 8, _six_spells())
	_long_page(screen)
	var seen := {}
	for step in 6:
		screen._paint()
		for row in _drawn_rows(screen):
			if row.begins_with("> "):
				seen[row.substr(2)] = true
		screen.logic().move(1)
	for spell: BattleLogic.SpellRow in screen.logic().spell_rows():
		var wanted := "%s  %d MP" % [spell.name, spell.cost]
		assert_bool(seen.has(wanted)).override_failure_message(
			"'%s' can never be put under the cursor: reached %s" % [wanted, seen.keys()]) \
			.is_true()

func test_the_window_snaps_home_when_the_cursor_wraps() -> void:
	# Wrapping from the last row to the first is one press, and the window has to come with it.
	var screen := _screen(1, 8, _six_spells())
	_long_page(screen)
	for step in 5:
		screen.logic().move(1)
	screen._paint()
	assert_str(_drawn_rows(screen)[3]).contains("Ward")
	screen.logic().move(1)
	screen._paint()
	assert_int(screen.logic().index()).override_failure_message(
		"the cursor did not wrap, so this proves nothing about the window").is_equal(0)
	assert_str(_drawn_rows(screen)[0]).override_failure_message(
		"the cursor wrapped to the top and the window stayed at the bottom: %s"
		% [_drawn_rows(screen)]).contains("Ember")

func test_a_game_with_no_magic_is_clean_too() -> void:
	# The control. The MP line is the thing that grew, so a fix that only worked when it was
	# absent would pass every test above and ship the bug back.
	var screen := _screen(1, 0, [], [], false)
	_assert_nothing_overlaps(screen, "no-magic")

func test_only_a_game_with_magic_is_told_about_magic() -> void:
	# Asserted in BOTH directions, because each half alone is passed by a screen that always
	# draws the line and by one that never does. A game with no spells being shown "MP 0/0" is
	# a system the player is told about and can never find.
	var without := _screen(1, 0, [], [], false)
	assert_bool(without._hero_mp.visible).override_failure_message(
		"a game with no magic is shown a magic readout: '%s'" % without._hero_mp.text).is_false()

	var with_magic := _screen(1, 5)
	assert_bool(with_magic._hero_mp.visible).override_failure_message(
		"a game with magic does not say how much is left").is_true()
	assert_str(with_magic._hero_mp.text).contains("MP 5/8")
