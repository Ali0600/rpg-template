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
	var logic := BattleHelpers.solo(combat, _enemy(), combat.max_hp(level), 0, level, items,
		0, 0, mp, spells)
	screen.setup(logic, load("res://data/styles/dusk16.tres") as SpriteStyle, VIEWPORT,
		FileSpriteSource.create(&"dusk16"))
	_screens.append(screen)
	return screen


## A screen with a FULL party on it - as many members as the view says it can draw. The
## capacity is the content contract, so the audit is run at it rather than at the size the demo
## happens to ship: a layout that holds two and not three is a layout that fails the day a game
## declares what the manifest already lets it declare.
func _full_party_screen(spells: Array = []) -> BattleScreen:
	var screen := BattleScreen.new()
	add_child(screen)
	var combat := _combat(true)
	var members: Array = []
	for i in BattleScreen.MAX_PARTY:
		# Long names on purpose: a caption is as wide as the words in it, and a party page that
		# only fits short ones is one that breaks on the first game that writes real ones.
		members.append(BattleLogic.Fighter.of(&"" if i == 0 else StringName("m%d" % i),
			"You" if i == 0 else "Companion%d" % i, &"quest_wanderer", combat,
			combat.max_hp(1), 0, 1, combat.max_mp(1), 0, 0, spells))
	var logic := BattleLogic.of(combat, [_enemy()], members, [], "map/foe", 7)
	screen.setup(logic, load("res://data/styles/dusk16.tres") as SpriteStyle, VIEWPORT,
		FileSpriteSource.create(&"dusk16"))
	_screens.append(screen)
	return screen


## A screen with a full party AND a full formation - every block this view can be asked to draw,
## at once. The capacity on both sides is the content contract, so this is the audit that
## matters: a layout that holds three of one and three of the other only when they are not both
## there is one that fails on the first map that ships a crowd.
func _full_field_screen() -> BattleScreen:
	var screen := BattleScreen.new()
	add_child(screen)
	var combat := _combat(true)
	var members: Array = []
	for i in BattleScreen.MAX_PARTY:
		members.append(BattleLogic.Fighter.of(&"" if i == 0 else StringName("m%d" % i),
			"You" if i == 0 else "Companion%d" % i, &"quest_wanderer", combat,
			combat.max_hp(1), 0, 1, combat.max_mp(1), 0, 0, []))
	var foes: Array = []
	for at in BattleScreen.MAX_FOES:
		# Long names here too, and DIFFERENT ones: a formation that repeats a name gets lettered,
		# which makes every caption a little wider than the file it came from.
		var foe := _enemy()
		foe.id = StringName("foe%d" % at)
		foe.name = "Deepdweller%d" % at
		foes.append(foe)
	var logic := BattleLogic.of(combat, foes, members, [], "map/foe", 7)
	screen.setup(logic, load("res://data/styles/dusk16.tres") as SpriteStyle, VIEWPORT,
		FileSpriteSource.create(&"dusk16"))
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
	var fills: Array[ColorRect] = []
	fills.append_array(screen._foe_fills)
	fills.append_array(screen._member_fills)
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


func test_a_full_party_is_drawn_without_anything_overlapping() -> void:
	# The audit at the capacity the view declares, which is the number a game is allowed to
	# ship. Every member's bar and caption, the command list, the message, the help line and
	# both fighters, all at once.
	_assert_nothing_overlaps(_full_party_screen(), "full party command")


func test_a_full_party_choosing_a_spell_is_drawn_without_anything_overlapping() -> void:
	# The longest page a party can be looking at: six spells scrolling in a four-slot window
	# while three members' blocks are drawn beside it.
	var screen := _full_party_screen([
		_spell("Ember", 3), _spell("Mend", 4), _spell("Lull", 5),
		_spell("Cinder", 6), _spell("Balm", 7), _spell("Hush", 8),
	])
	# Straight down to Magic and in. No opening press to hand the menu along any more: a press
	# is a swing now, and the page being audited belongs to whoever is being asked.
	assert_int(screen.logic().phase()).is_equal(BattleLogic.Phase.MENU)
	screen.logic().move(1)
	screen.logic().press()
	screen._paint()
	assert_int(screen.logic().phase()).is_equal(BattleLogic.Phase.SPELLS)
	_assert_nothing_overlaps(screen, "full party spell")


func test_every_member_of_a_full_party_has_a_visible_block() -> void:
	# The audit above proves nothing OVERLAPS; it cannot prove anything was drawn. A layout
	# that forgot the third member would pass it perfectly.
	# Counted through the screen's own caption nodes rather than by searching the drawn text
	# for a name: the help line names the member being asked for an order, so a substring
	# search finds four captions for three members and the test measures the wrong thing.
	var screen := _full_party_screen()
	var drawn := 0
	for label: Label in screen._member_labels:
		if label.visible and not label.text.strip_edges().is_empty():
			drawn += 1
	assert_int(drawn).override_failure_message(
		"a party of %d drew %d captions" % [BattleScreen.MAX_PARTY, drawn]) \
		.is_equal(BattleScreen.MAX_PARTY)


func test_the_party_fits_between_the_fighters_and_the_help_line() -> void:
	# The bound the pitch is chosen against, asserted rather than eyeballed: the lowest thing a
	# member's block draws must still sit above the help line.
	var screen := _full_party_screen()
	var lowest := 0.0
	for label: Label in screen._member_labels:
		lowest = maxf(lowest, label.global_position.y + label.get_theme_font_size("font_size"))
	for bar: ColorRect in screen._member_bars:
		lowest = maxf(lowest, bar.global_position.y + bar.size.y)
	assert_float(lowest).override_failure_message(
		"the party's last block reaches y=%f, past the help line" % lowest) \
		.is_less(float(VIEWPORT.y) - 14.0)


func test_only_the_member_who_is_swinging_leans_forward() -> void:
	# The lean is how a player reads WHOSE blow is landing. With everybody leaning it is a
	# party stepping forward together, which says nothing - and no overlap audit can see it,
	# because leaning is a position and the audit measures collisions.
	var screen := _full_party_screen()
	var logic := screen.logic()
	logic.press()
	assert_int(logic.phase()).override_failure_message(
		"choosing Attack did not swing").is_equal(BattleLogic.Phase.PLAYER_ACT)
	# Halfway through the wind-up, where the lean is at its most visible.
	for i in 20:
		if logic.count() <= logic.cue_span() / 2:
			break
		logic.tick()
	screen._paint()
	var swinging := logic.acting_member()
	assert_int(swinging).is_greater_equal(0)
	var moved := 0
	for i in screen._member_views.size():
		if not screen._member_views[i].position.is_equal_approx(screen._member_homes[i]):
			moved += 1
			assert_int(i).override_failure_message(
				"member %d leaned while member %d was swinging" % [i, swinging]).is_equal(swinging)
	assert_int(moved).override_failure_message(
		"nobody leaned at all, so this proves nothing about who did").is_equal(1)


func test_exactly_one_member_is_marked_at_a_time() -> void:
	# The marker is one arrow: it follows a member from being asked through their swing, and
	# once the whole party has gone it moves to whoever the enemy has aimed at. A member left
	# holding the turn after their turn ends puts TWO arrows on screen, and a player reading
	# which one means "you are about to be hit" is reading the wrong one.
	var screen := _full_party_screen()
	var logic := screen.logic()
	for round_step in BattleScreen.MAX_PARTY:
		screen._paint()
		assert_int(_marked_count(screen)).override_failure_message(
			"%d members were marked while member %d had the turn"
			% [_marked_count(screen), logic.commander()]).is_equal(1)
		logic.press()
		_walk(logic, BattleLogic.Phase.PLAYER_ACT)
		_walk(logic, BattleLogic.Phase.MESSAGE)
	assert_int(logic.phase()).override_failure_message(
		"the enemy never took its turn, so the marker was never asked to move").is_equal(
		BattleLogic.Phase.ENEMY_ACT)
	screen._paint()
	assert_int(_marked_count(screen)).override_failure_message(
		"%d members were marked while the enemy took aim" % _marked_count(screen)).is_equal(1)


## How many member captions are currently carrying the marker.
func _marked_count(screen: BattleScreen) -> int:
	var out := 0
	for label: Label in screen._member_labels:
		if label.visible and label.text.begins_with("> "):
			out += 1
	return out


## Ticks the fight out of `from`, bounded, failing rather than hanging if it never leaves.
func _walk(logic: BattleLogic, from: BattleLogic.Phase, bound := 400) -> void:
	for i in bound:
		if logic.phase() != from:
			return
		logic.tick()
	fail("the fight never left phase %d within %d frames" % [from, bound])


func test_a_full_field_is_drawn_without_anything_overlapping() -> void:
	# Both sides at capacity, which is the state no shipped map produces yet and every shipped
	# map is allowed to.
	_assert_nothing_overlaps(_full_field_screen(), "full field")


func test_every_foe_of_a_full_formation_has_a_visible_block() -> void:
	# The overlap audit proves nothing COLLIDES; it cannot prove anything was drawn. A layout
	# that forgot the third foe would pass it perfectly.
	var screen := _full_field_screen()
	var drawn := 0
	for label: Label in screen._foe_labels:
		if label.visible and not label.text.strip_edges().is_empty():
			drawn += 1
	assert_int(drawn).override_failure_message(
		"a formation of %d drew %d captions" % [BattleScreen.MAX_FOES, drawn]) \
		.is_equal(BattleScreen.MAX_FOES)


func test_a_lone_foe_keeps_the_block_it_has_always_had() -> void:
	# The parity pin on the other side: a fight against one foe is pixel-identical to every
	# screenshot taken before formations existed, and this is the assertion that says so.
	var screen := _screen()
	assert_int(screen._foe_bars.size()).is_equal(1)
	assert_float(screen._foe_bars[0].global_position.y).override_failure_message(
		"the lone foe's bar moved from where it has always been") \
		.is_equal(BattleScreen.FOE_BAR_Y)


func test_the_formation_fits_above_the_cue_line() -> void:
	# The bound the pitch is chosen against, asserted rather than eyeballed: the lowest thing a
	# foe's block draws must still sit above the band the "!" uses, or the crowd covers the one
	# thing the player is reacting to.
	var screen := _full_field_screen()
	var lowest := 0.0
	for label: Label in screen._foe_labels:
		lowest = maxf(lowest, label.global_position.y + label.get_theme_font_size("font_size"))
	for bar: ColorRect in screen._foe_bars:
		lowest = maxf(lowest, bar.global_position.y + bar.size.y)
	assert_float(lowest).override_failure_message(
		"the formation's last block reaches y=%f, into the cue band" % lowest) \
		.is_less(float(VIEWPORT.y) * 0.5 - 30.0)


func test_only_the_foe_that_is_swinging_leans_forward() -> void:
	# The mirror of the party's rule, and unseeable by the overlap audit for the same reason:
	# leaning is a position, and the audit measures collisions.
	var screen := _full_field_screen()
	var logic := screen.logic()
	# Play the party's whole round out, so the formation's turn begins.
	for i in 400:
		if logic.phase() == BattleLogic.Phase.ENEMY_ACT or logic.finished():
			break
		if logic.phase() == BattleLogic.Phase.MENU or logic.phase() == BattleLogic.Phase.FOE:
			logic.press()
		else:
			logic.tick()
	assert_int(logic.phase()).override_failure_message(
		"the formation never got its turn").is_equal(BattleLogic.Phase.ENEMY_ACT)
	for i in 20:
		if logic.count() <= logic.cue_span() / 2:
			break
		logic.tick()
	screen._paint()
	var swinging := logic.acting_foe()
	assert_int(swinging).is_greater_equal(0)
	var moved := 0
	for at in screen._foe_views.size():
		if not screen._foe_views[at].position.is_equal_approx(screen._foe_homes[at]):
			moved += 1
			assert_int(at).override_failure_message(
				"foe %d leaned while foe %d was swinging" % [at, swinging]).is_equal(swinging)
	assert_int(moved).override_failure_message(
		"no foe leaned at all, so this proves nothing about which one did").is_equal(1)


func test_exactly_one_foe_is_marked_while_the_cursor_is_up() -> void:
	# The marker is one arrow on that side too: it sits on the foe the cursor is over, and stays
	# on the one a swing is already travelling toward.
	var screen := _full_field_screen()
	var logic := screen.logic()
	logic.press()
	assert_int(logic.phase()).override_failure_message(
		"a full formation did not ask which one").is_equal(BattleLogic.Phase.FOE)
	screen._paint()
	assert_int(_marked_foes(screen)).override_failure_message(
		"%d foes were marked while the cursor was on one" % _marked_foes(screen)).is_equal(1)
	logic.move(1)
	screen._paint()
	assert_int(_marked_foes(screen)).override_failure_message(
		"moving the cursor left %d foes marked" % _marked_foes(screen)).is_equal(1)
	logic.press()
	screen._paint()
	assert_int(_marked_foes(screen)).override_failure_message(
		"the mark did not stay on the foe the blow is travelling toward").is_equal(1)


## How many foe captions are currently carrying the marker.
func _marked_foes(screen: BattleScreen) -> int:
	var out := 0
	for label: Label in screen._foe_labels:
		if label.visible and label.text.begins_with("> "):
			out += 1
	return out
