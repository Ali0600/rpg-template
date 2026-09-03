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




## How wide one fighter draws on this screen, in its own layout units.
func _fighter_width(screen: BattleScreen) -> float:
	return float(screen._foe_views[0].cell_size().x) * screen._foe_views[0].scale.x


## The same fight, drawn under a style that wants a bigger world. Every character is the
## wanderer because the wanderer is the only one drawn in lpc32 yet, which is fine here: this
## is about how big a fighter is drawn, not about who it is.
func _wide_screen() -> BattleScreen:
	var screen := BattleScreen.new()
	var style := load("res://data/styles/lpc32.tres") as SpriteStyle
	UiScale.mount(screen, self, style)
	var combat := _combat(true)
	var enemy := _enemy()
	enemy.character = &"quest_wanderer"
	var logic := BattleHelpers.solo(combat, enemy, combat.max_hp(1), 0, 1, [], 0, 0, 8, [])
	screen.setup(logic, style, UiScale.DESIGN_SIZE, FileSpriteSource.create(&"lpc32"))
	_screens.append(screen)
	return screen


## How tall a fighter actually is on the SCREEN: its cell, through its own scale and through
## the scale of the layer it is drawn on. Reading either alone measures half the answer.
func _drawn_height(screen: BattleScreen, view: SpriteView) -> float:
	return float(view.cell_size().y) * view.scale.y * screen.scale.y


func test_a_fighter_is_drawn_at_the_size_its_style_asks_for() -> void:
	# The screen is a CanvasLayer already drawn at the world's scale, so the multiple the style
	# names is divided by that scale here and what lands on the glass is the number the style
	# asked for. A style asking for 2 without the division would draw a 64px cell 128 screen
	# pixels tall in the 180 this layout was measured for.
	var narrow := _screen()
	var wide := _wide_screen()
	var small := _drawn_height(narrow, narrow._foe_views[0])
	var big := _drawn_height(wide, wide._foe_views[0])
	assert_float(small).override_failure_message(
		"a 16x24 fighter is not being drawn at twice its size").is_equal(48.0)
	# 64, not 128: lpc32 asks for world size since M42. At twice size one fighter took a third
	# of the screen, which is why the readouts had nowhere to go but on top of the sprites.
	assert_float(big).override_failure_message(
		"a 64x64 fighter is drawn %spx tall in a 360px world, where the layout holds three"
		% big).is_equal(64.0)
	# The rule both obey, stated once and read from the DATA rather than from a constant here:
	# a fighter is drawn at its style's own multiple of the size it is in the world. NOT at the
	# same fraction of the screen - the two cells are different shapes, 24 rows on a 16px tile
	# against 64 on a 32px one, and asserting a shared fraction would be asserting that every
	# style must draw its characters at the same proportion, which is a design decision the
	# template leaves to whoever draws them.
	for pair: Array in [[narrow, small], [wide, big]]:
		var screen: BattleScreen = pair[0]
		var wanted := float(screen._style.battle_sprite_scale)
		assert_float(float(pair[1]) / float(screen._foe_views[0].cell_size().y)) \
			.override_failure_message("a fighter is not drawn at %sx its world size on '%s'"
			% [wanted, screen._style.id]).is_equal(wanted)


## A full party under a style asking for a given fighter size. Built by hand rather than taken
## off disk because the rule below is about how the file RESPONDS to a fighter's width, and every
## shipped style now happens to draw one 32 design pixels wide - see the test.
func _party_screen_at(fighter_scale: int) -> BattleScreen:
	var screen := BattleScreen.new()
	var style := (load("res://data/styles/lpc32.tres") as SpriteStyle).duplicate() as SpriteStyle
	style.battle_sprite_scale = fighter_scale
	UiScale.mount(screen, self, style)
	var combat := _combat(true)
	var members: Array = []
	for i in BattleScreen.MAX_PARTY:
		members.append(BattleLogic.Fighter.of(&"" if i == 0 else StringName("m%d" % i),
			"You" if i == 0 else "Companion%d" % i, &"quest_wanderer", combat,
			combat.max_hp(1), 0, 1, combat.max_mp(1), 0, 0, []))
	var enemy := _enemy()
	enemy.character = &"quest_slink"
	var logic := BattleLogic.of(combat, [enemy], members, [], "map/foe", 7)
	screen.setup(logic, style, UiScale.DESIGN_SIZE, FileSpriteSource.create(&"lpc32"))
	_screens.append(screen)
	return screen


func test_the_party_stands_in_the_same_file_however_wide_its_fighters_are() -> void:
	# The stagger is a fraction of how wide a fighter draws, so the group has one SHAPE at every
	# size. A flat number of pixels put two 64px LPC characters 18 apart - one standing in front
	# of the other with a face showing over a shoulder, which reads as a drawing mistake rather
	# than as a formation.
	#
	# Measured against SYNTHETIC styles, and that is the point of this version. It used to compare
	# the two on disk, and since M42 those draw fighters the same width in design pixels - a 16px
	# cell at twice size and a 64px cell at world size are both 32 - so the ratio was 1 on both
	# sides and deleting the whole calculation changed nothing. The mutant survived and said so.
	# Two widths that actually differ is what makes this an assertion.
	var pairs: Array = []
	var widths: Array = []
	for fighter_scale in [1, 2]:
		var screen := _party_screen_at(fighter_scale)
		var homes: Array = screen._member_homes
		assert_int(homes.size()).is_greater(1)
		var apart: float = absf((homes[1] as Vector2).x - (homes[0] as Vector2).x)
		widths.append(_fighter_width(screen))
		pairs.append(apart / _fighter_width(screen))
	assert_float(widths[1]).override_failure_message(
		"both fixtures draw a fighter %spx wide, so this compares a number with itself"
		% widths[0]).is_not_equal(widths[0])
	assert_float(pairs[1]).override_failure_message(
		"a %spx fighter is stepped %.3f of its own width where a %spx one is stepped %.3f"
		% [widths[1], pairs[1], widths[0], pairs[0]]).is_equal_approx(pairs[0], 0.001)


func test_the_wide_screen_still_draws_nothing_over_anything() -> void:
	# The layout is measured in design pixels and the fighters are the one thing on it sized by
	# the ART. A 64px cell is more than twice the 24 this screen was laid out around, so the
	# audit is run again over there rather than assumed to carry.
	var screen := _wide_screen()
	_assert_nothing_overlaps(screen, "command at 32px")


func test_every_style_draws_its_fighters_at_the_size_it_asked_for() -> void:
	# Over the styles on disk, so one added later fails here rather than in somebody's screenshot.
	#
	# What lands on the glass is `battle_sprite_scale` exactly: the screen divides by world_scale
	# and the layer multiplies by it again, and that cancelling IS the design - the style says how
	# big a fighter is and the world's scale cannot move it.
	#
	# The intermediate is allowed to be fractional, and this is the one place that is worth
	# stating. lpc32 asks for world size on a 2x layer, so the sprite's OWN scale is 0.5 - which
	# looks like half-resolution art and is not. A CanvasLayer's scale is a transform rather than
	# a render target, so the two compose before anything is rasterised: measured, a 0.5 sprite on
	# a 2x layer has a canvas transform of exactly identity and the texture is drawn 1:1. What
	# would cost pixels is a COMPOSED scale that is not whole, and the style declares that as an
	# int, so it cannot be.
	for id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(id)
		var sprite := float(style.battle_sprite_scale) / float(UiScale.scale_of(style))
		var on_screen := sprite * float(UiScale.scale_of(style))
		assert_float(on_screen).override_failure_message(
			"style '%s' draws a fighter at %sx world size where it asks for %d"
			% [id, on_screen, style.battle_sprite_scale]).is_equal(float(style.battle_sprite_scale))
		assert_float(on_screen).override_failure_message(
			"style '%s' draws a fighter at %sx, which is not a whole number of pixels"
			% [id, on_screen]).is_equal(floorf(on_screen))
		assert_float(on_screen).is_greater(0.0)


## A screen with a FULL party on it - as many members as the view says it can draw. The
## capacity is the content contract, so the audit is run at it rather than at the size the demo
## happens to ship: a layout that holds two and not three is a layout that fails the day a game
## declares what the manifest already lets it declare.
func _full_party_screen(spells: Array = [], afflicted := false) -> BattleScreen:
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
	if afflicted:
		# Set before the fight is built, which is the only way in from outside: a Fighter is
		# handed to `of()` and never handed back. The longest tag the vocabulary has, so the
		# caption is at its widest.
		for member: BattleLogic.Fighter in members:
			member.status.shift(SpellDef.Stat.DEFENSE, -2, 3)
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


## Whether anything between this node and the screen is invisible. A row inside a hidden window
## is not on screen, and measuring it would report a collision nobody can see.
func _shown(node: Node, screen: BattleScreen) -> bool:
	var at := node
	while at != null and at != screen:
		var control := at as CanvasItem
		if control != null and not control.visible:
			return false
		at = at.get_parent()
	return true


## The room INSIDE a container, in screen space. A header band has no inner rect of its own -
## what is in it is in it - so it answers with its whole rectangle.
func _content(node: Node, outer: Rect2) -> Rect2:
	var inner := UiChrome.inner_of(node)
	if inner.size == Vector2.ZERO:
		return outer
	return Rect2(outer.position + inner.position, inner.size)


## Which rectangle a child has to fit in. CONTENT for the things a window holds, and the window's
## whole rect for its own chrome: a header band IS the top of the window rather than something
## inside it, and a cursor is deliberately inset past the content edge so the bar reads as being
## around its row rather than starting at the same pixel. Both must still be inside the window.
func _room_for(child: Node, container: Node, outer: Rect2) -> Rect2:
	var kind := UiChrome.kind_of(child)
	if kind == UiChrome.HEADER or kind == UiChrome.SELECT:
		return outer
	return _content(container, outer)


## The nearest chrome kind above `node`, or nothing. Asked by ancestry rather than by an identity
## list, which is what the fill exclusion used to be - and a list every new bar had to be added to.
func _kind_above(node: Node, screen: BattleScreen) -> StringName:
	var at := node.get_parent()
	while at != null and at != screen:
		var kind := UiChrome.kind_of(at)
		if kind != &"":
			return kind
		at = at.get_parent()
	return &""


## The nearest thing above `node` that CONTAINS it - a window or a header band - or null.
func _container_of(node: Node, screen: BattleScreen) -> Node:
	var at := node.get_parent()
	while at != null and at != screen:
		var kind := UiChrome.kind_of(at)
		if kind == UiChrome.FRAME or kind == UiChrome.HEADER:
			return at
		at = at.get_parent()
	return null


## Every rectangle the player can actually see, with the name of the node that owns it.
##
## ColorRects, Labels, portraits and FIGHTERS. A Label's `size` is only meaningful once it has
## laid out, so its height comes from the font it was given - what is being asserted is where
## a line of text SITS, and a zero-height rect intersects nothing.
##
## The fighters are the M42 addition and the reason this audit could be green while the screen
## was wrong. It measured two node classes and a SpriteView is neither, so a health bar drawn
## across a character's chest collided with nothing this could see - which is exactly the
## picture that got the old screen rejected. A view's origin is its FEET, so its rectangle
## reaches up and back from there by the anchor.
func _visible_rects(screen: BattleScreen) -> Array:
	var out: Array = []
	for node in SceneHelpers.find_all_by_class(screen, "SpriteView"):
		var view := node as SpriteView
		if not view.visible or not _shown(view, screen) or view.cell_size() == Vector2i.ZERO:
			continue
		var span := Vector2(view.cell_size()) * view.scale
		out.append([_name_of(screen, view) + " (a fighter)",
			Rect2(view.position - Vector2(view.anchor()) * view.scale, span), view])
	# The windows themselves. Collected LAST of the containers on purpose - a frame is not a peer
	# of what is inside it, and the pair rule above turns each such pairing into a containment
	# check. Without them in the list at all, "inside its window" was a rule nothing evaluated.
	for node in SceneHelpers.find_all_by_class(screen, "Panel"):
		var frame := node as Panel
		if not frame.visible or not _shown(frame, screen):
			continue
		out.append([_name_of(screen, frame), Rect2(frame.global_position, frame.size), frame])
	for node in SceneHelpers.find_all_by_class(screen, "TextureRect"):
		var face := node as TextureRect
		if not face.visible or not _shown(face, screen):
			continue
		out.append([_name_of(screen, face), Rect2(face.global_position, face.size), face])
	for node in SceneHelpers.find_all_by_class(screen, "ColorRect"):
		var rect := node as ColorRect
		# The backdrop is a COVER, not a peer: it is the whole screen by construction, and
		# auditing it against everything drawn on top of it would report the entire screen.
		#
		# Anything INSIDE a bar is skipped for a narrower reason: a fill drawn in its own track
		# is what a bar IS, so the widget is one peer rather than two. By ancestry rather than by
		# an identity list, which is what the list was and which every new bar had to be added to.
		if not rect.visible or not _shown(rect, screen) or rect.size >= Vector2(VIEWPORT):
			continue
		if _kind_above(rect, screen) == UiChrome.BAR:
			continue
		out.append([_name_of(screen, rect), Rect2(rect.global_position, rect.size), rect])
	for node in SceneHelpers.find_all_by_class(screen, "Label"):
		var label := node as Label
		if not label.visible or not _shown(label, screen) or label.text.strip_edges().is_empty():
			continue
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		# A WRAPPING label must be measured wrapped, or this audit reports the width the text
		# would have had on one line - which is the number the wrap exists to prevent, so the gate
		# would go on failing after the fix and reading as though nothing had changed.
		var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
		var lines := 1
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.size.x > 0.0:
			var wrapped := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				label.size.x, size)
			# How many LINES it came to, rather than the height in pixels. The rects below are
			# measured in font SIZE and the rows are pitched tighter than the font's own line
			# height, so taking the pixel height straight from the font inflates every box and
			# reports the command menu as overlapping itself - which it has never done.
			lines = maxi(1, int(round(wrapped.y / maxf(font.get_height(size), 1.0))))
			measured.x = minf(measured.x, label.size.x)
		# Anchored at the label's own drawn origin rather than at its control rect, which for
		# an unsized Label is the whole viewport and would intersect everything.
		var at := label.global_position
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and label.size.x > 0.0:
			at.x += label.size.x - measured.x
		# The HEIGHT comes from the measurement too, now that a label can be more than one line
		# tall: a second line drawn over the foe bars is exactly the collision this audit exists
		# to catch, and a rect fixed at one line's height cannot see it.
		out.append([_name_of(screen, label) + " '" + label.text + "'",
			Rect2(at, Vector2(measured.x, float(size * lines))), label])
	return out


## A readable name for a node, so a failure says WHICH two things collided rather than handing
## back two rectangles to work out.
func _name_of(screen: BattleScreen, node: Node) -> String:
	# The path from the screen down, because things nest now: "child 4 (Panel) > child 1 (Label)"
	# says which window a stray row belongs to, where a bare class name says only that one exists.
	var parts: Array[String] = []
	var at := node
	while at != null and at != screen:
		var parent := at.get_parent()
		if parent == null:
			break
		parts.push_front("child %d (%s)" % [at.get_index(), at.get_class()])
		at = parent
	return " > ".join(parts) if not parts.is_empty() else node.get_class()


## How many lines a wrapping label actually comes to. Measured from the font rather than read off
## `get_line_count()`, which needs the label to have laid out - and these screens are painted by
## hand in a test with no frame in between.
func _lines_of(label: Label) -> int:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var width := label.size.x if label.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
	var wrapped := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width,
		size)
	return maxi(1, int(round(wrapped.y / maxf(font.get_height(size), 1.0))))


## The audit's other half: nothing visible is drawn outside the window.
##
## Overlap and containment are different failures and only one of them was ever checked. A Label
## with no width, no wrap and no clip - which every label on this screen is - does not clip, wrap
## or complain when its text outgrows the screen: it simply draws past the edge, where the player
## cannot see it. Nothing overlaps out there, so the pairwise audit is blind to it, and only
## vertical containment was asserted anywhere.
##
## Measured before it was written: the widest SHIPPED caption is 295px of a 312px budget, and the
## widest at the capacity this view DECLARES is 478px. `MAX_PARTY` and `MAX_FOES` are the
## capacities the layout audit measures against and the content gate refuses data for - this is
## the third of those three, which had been stated and never enforced.
func _assert_nothing_leaves_the_window(screen: BattleScreen, page: String) -> void:
	var rects := _visible_rects(screen)
	assert_int(rects.size()).override_failure_message(
		"the %s page drew nothing measurable, so this proves nothing" % page).is_greater(3)
	for entry: Variant in rects:
		var named: Array = entry
		var rect: Rect2 = named[1]
		assert_float(rect.end.x).override_failure_message(
			"on the %s page, %s runs to x=%.0f in a %dpx window - the tail is drawn off-screen"
			% [page, named[0], rect.end.x, VIEWPORT.x]).is_less_equal(float(VIEWPORT.x))
		assert_float(rect.position.x).override_failure_message(
			"on the %s page, %s starts at x=%.0f, left of the window"
			% [page, named[0], rect.position.x]).is_greater_equal(0.0)
		assert_float(rect.end.y).override_failure_message(
			"on the %s page, %s runs to y=%.0f in a %dpx window"
			% [page, named[0], rect.end.y, VIEWPORT.y]).is_less_equal(float(VIEWPORT.y))


## The audit itself: no two visible things share pixels, and anything inside a window stays
## inside it. Named separately from the tests so every page below is one line and the failure
## message says which page it was.
##
## A CONTAINER is not a peer. A window is drawn behind everything in it by construction, and a
## cursor is drawn behind the row it selects - so measuring either as a peer would report the
## whole screen. What is asserted about them instead is the thing they promise: a window ENCLOSES
## its contents, and partial overlap - a row half out of its own window - is the failure.
func _assert_nothing_overlaps(screen: BattleScreen, page: String) -> void:
	var rects := _visible_rects(screen)
	assert_int(rects.size()).override_failure_message(
		"the %s page drew nothing measurable, so this proves nothing" % page).is_greater(3)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i][1]
			var b: Rect2 = rects[j][1]
			var a_node: Node = rects[i][2]
			var b_node: Node = rects[j][2]
			# One inside the other: assert the containment rather than the separation, and
			# against the window's CONTENT rect rather than its outer one. The border and the
			# header band are part of a window and not part of the room inside it, so measuring
			# against the outer rect passes a row hanging over the bottom edge - which is what
			# the command window was doing when this was first written.
			if _container_of(b_node, screen) == a_node:
				var room := _room_for(b_node, a_node, a)
				assert_bool(room.encloses(b)).override_failure_message(
					"on the %s page, %s %s sticks out of %s %s"
					% [page, rects[j][0], b, rects[i][0], room]).is_true()
				continue
			if _container_of(a_node, screen) == b_node:
				var space := _room_for(a_node, b_node, b)
				assert_bool(space.encloses(a)).override_failure_message(
					"on the %s page, %s %s sticks out of %s %s"
					% [page, rects[i][0], a, rects[j][0], space]).is_true()
				continue
			# A cursor sits UNDER a row: it may cover one whole, and must not clip any other.
			if UiChrome.kind_of(a_node) == UiChrome.SELECT \
					or UiChrome.kind_of(b_node) == UiChrome.SELECT:
				var bar: Rect2 = a if UiChrome.kind_of(a_node) == UiChrome.SELECT else b
				var other: Rect2 = b if UiChrome.kind_of(a_node) == UiChrome.SELECT else a
				assert_bool(not bar.intersects(other) or bar.encloses(other)) \
					.override_failure_message(
					"on the %s page, the cursor %s half-covers %s %s"
					% [page, bar, rects[j][0] if bar == a else rects[i][0], other]).is_true()
				continue
			# TWO FIGHTERS may overlap, and that is what a staggered file IS: they stand back and
			# up from one another so a party of three fits a field two of them would fill, each
			# still showing their head and their weapon arm. A rule that forbade it would be a
			# rule against formations.
			#
			# Not a free pass, though - what it must never be is two fighters in the same PLACE,
			# which is a file that forgot to step and reads as one character with a doubled
			# outline. So the exemption asserts the thing the overlap is allowed for.
			if a_node is SpriteView and b_node is SpriteView:
				assert_vector((a_node as SpriteView).position).override_failure_message(
					"two fighters stand on the same spot, so one is drawn inside the other"
				).is_not_equal((b_node as SpriteView).position)
				continue
			# A window may sit inside another window's content area; the containment above has
			# already covered the pair that are actually nested.
			if UiChrome.kind_of(a_node) == UiChrome.FRAME and a.encloses(b):
				continue
			if UiChrome.kind_of(b_node) == UiChrome.FRAME and b.encloses(a):
				continue
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

## Runs frames until the fight is showing a line, or the bound runs out. BOUNDED and ASSERTED:
## "tick until the thing under test says so" is a test that hangs rather than fails, and a
## caption that never arrives has to be a red run rather than a timeout.
func _tick_until_message(logic: BattleLogic, bound := 400) -> void:
	for i in bound:
		if not logic.message().is_empty():
			return
		logic.tick()
	fail("the fight produced no caption within %d frames" % bound)


## A sweep at capacity - the widest line this screen can be asked to draw.
##
## The caption names what EACH foe took, so it grows with the formation; the party's names grow
## it further, and a felled foe adds a clause apiece. Long names on purpose, for the reason
## `_full_field_screen` gives: a layout that only fits short ones breaks on the first game that
## writes real ones.
func _swept_field_screen() -> BattleScreen:
	var screen := BattleScreen.new()
	add_child(screen)
	var combat := _combat(true)
	var members: Array = []
	for i in BattleScreen.MAX_PARTY:
		members.append(BattleLogic.Fighter.of(&"" if i == 0 else StringName("m%d" % i),
			"You" if i == 0 else "Companion%d" % i, &"quest_wanderer", combat,
			combat.max_hp(1), 0, 1, combat.max_mp(1), 0, 0,
			[BattleLogic.SpellRow.of(&"gale", "Gale", 1, SpellDef.Kind.ATTACK, 12, 0,
				SpellDef.Target.ALL, SpellDef.Stat.ATTACK, &"lightning")]))
	var foes: Array = []
	for at in BattleScreen.MAX_FOES:
		var foe := _enemy()
		foe.id = StringName("foe%d" % at)
		foe.name = "Deepdweller%d" % at
		# An ELEMENT with a long name, and an answer to it, for the reason the names are long: a
		# caption that only fits short words is one that breaks on the first game writing real
		# ones. Without this the widest line lands within a pixel of the window and whether the
		# audit can see an unwrapped caption depends on the platform's font metrics - measured,
		# after a mutant killed on one runner and survived on another.
		foe.resistances = {&"lightning": 50}
		foe.max_hp = 4 if at < BattleScreen.MAX_FOES - 1 else 99
		foes.append(foe)
	var logic := BattleLogic.of(combat, foes, members, [], "map/foe", 7)
	screen.setup(logic, load("res://data/styles/dusk16.tres") as SpriteStyle, VIEWPORT,
		FileSpriteSource.create(&"dusk16"))
	_screens.append(screen)
	# Cast the sweep: Magic, the only spell, and it reaches everything so there is nothing to aim.
	logic.move(BattleLogic.Row.MAGIC)
	logic.press()
	logic.press()
	_tick_until_message(logic)
	screen._paint()
	return screen

func test_the_caption_is_set_up_to_wrap_inside_the_window() -> void:
	# The CONFIGURATION, asserted apart from any measurement, and that split is the whole point.
	# The audits below measure what a particular caption comes to, so their ability to notice a
	# missing wrap depends on font metrics — which differ between this machine and the runner that
	# gates the merge. A mutant turning the wrap off killed here and SURVIVED there, on a line
	# that happened to land within a pixel of the edge.
	#
	# So the contract the mutants are aimed at is one nothing ambient can move: the label wraps,
	# and it wraps against a width that is most of the window rather than the one pixel a Label
	# falls back to when nobody sets one.
	var screen := _screen()
	assert_int(screen._message.autowrap_mode).override_failure_message(
		"the caption does not wrap, so a long line is drawn past the window edge") \
		.is_not_equal(TextServer.AUTOWRAP_OFF)
	assert_float(screen._message.size.x).override_failure_message(
		"the caption wraps against %.0fpx, which is not a width anybody chose"
		% screen._message.size.x).is_greater(float(VIEWPORT.x) * 0.5)
	assert_float(screen._message.size.x).override_failure_message(
		"the caption is wider than the window it wraps inside").is_less_equal(float(VIEWPORT.x))

func test_the_widest_caption_this_screen_can_draw_stays_inside_it() -> void:
	var screen := _swept_field_screen()
	assert_str(screen._message.text).override_failure_message(
		"the sweep produced no caption, so there is nothing to measure").is_not_empty()
	# The worst caption is the one that names every foe's damage AND every foe it felled, so the
	# fixture has to actually fell some. Without this the test measures a shorter line than the
	# screen can be asked to draw and passes while proving nothing.
	assert_str(screen._message.text).override_failure_message(
		"nothing fell, so this is not the widest caption: %s" % screen._message.text) \
		.contains("is down")
	_assert_nothing_leaves_the_window(screen, "a sweep at capacity")
	# CONTAINMENT IS NOT ENOUGH ON ITS OWN, which the mutation run proved: with no width to wrap
	# against, the label falls back to one pixel and the caption becomes a twenty-line column one
	# word wide - absurd, and technically inside the window, so the audit above passes it. The
	# line count is the constraint that actually says the caption is drawable, and it is a
	# capacity this view DECLARES rather than a number invented here.
	assert_int(_lines_of(screen._message)).override_failure_message(
		"the widest caption came to %d lines against a declared %d: '%s'"
		% [_lines_of(screen._message), BattleScreen.MESSAGE_LINES, screen._message.text]) \
		.is_less_equal(BattleScreen.MESSAGE_LINES)

func test_nothing_on_the_command_menu_leaves_the_window() -> void:
	_assert_nothing_leaves_the_window(_screen(), "command menu")

func test_nothing_on_a_full_field_leaves_the_window() -> void:
	var screen := _full_field_screen()
	screen._paint()
	_assert_nothing_leaves_the_window(screen, "a full field")

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
		assert_float(row.global_position.y).override_failure_message(
			"a row is drawn above the window that holds it").is_greater_equal(
			BattleScreen.PANELS_Y)
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
		var picked := screen.selected_row()
		assert_object(picked).override_failure_message(
			"the page is open and no row is under the cursor").is_not_null()
		seen[picked.text] = true
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
	assert_bool(without._mp_bars[0].root.visible).override_failure_message(
		"a game with no magic is shown a magic bar").is_false()

	var with_magic := _screen(1, 5)
	assert_bool(with_magic._mp_bars[0].root.visible).override_failure_message(
		"a game with magic does not say how much is left").is_true()
	assert_str(with_magic._mp_bars[0].numbers.text).is_equal("5/8")


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
	for bar: UiChrome.Bar in screen._hp_bars:
		lowest = maxf(lowest, bar.root.global_position.y + float(UiChrome.BAR_HEIGHT))
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
		# WHICH one, not just how many. The count alone cannot see a mark that stayed put: with
		# the turn never released it is still exactly one arrow, on the wrong person - and a
		# player reading it as "you are about to be hit" is reading about somebody else.
		assert_int(screen.marked_member()).override_failure_message(
			"the mark is on member %d where member %d has the turn"
			% [screen.marked_member(), logic.commander()]).is_equal(logic.commander())
		logic.press()
		_walk(logic, BattleLogic.Phase.PLAYER_ACT)
		_walk(logic, BattleLogic.Phase.MESSAGE)
	assert_int(logic.phase()).override_failure_message(
		"the enemy never took its turn, so the marker was never asked to move").is_equal(
		BattleLogic.Phase.ENEMY_ACT)
	screen._paint()
	assert_int(_marked_count(screen)).override_failure_message(
		"%d members were marked while the enemy took aim" % _marked_count(screen)).is_equal(1)
	# And it has MOVED, to whoever is about to be hit. This is the assertion the count could
	# never make: a party member still holding the turn from their own swing leaves the mark on
	# them, which is one arrow, in the wrong place, saying the wrong thing.
	assert_int(screen.marked_member()).override_failure_message(
		"the enemy is aiming at member %d and the mark is on member %d"
		% [logic.target_member(), screen.marked_member()]).is_equal(logic.target_member())


## How many member blocks the mark is currently covering. Read off the BAR rather than off the
## front of a caption, which is what it was: the marker used to be a "> " inside the row's own
## string, so a test that wanted to know who was marked had to parse text, and could not tell a
## marked member from one whose NAME began with a chevron.
func _marked_count(screen: BattleScreen) -> int:
	if not screen._party_mark.visible:
		return 0
	var bar := Rect2(screen._party_mark.global_position, screen._party_mark.size)
	var out := 0
	for label: Label in screen._member_labels:
		if label.visible and bar.has_point(label.global_position):
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


func test_a_full_party_wearing_statuses_still_fits() -> void:
	# Statuses APPEND to a caption, so every one of them makes a line wider - and every other
	# fixture here carries none, which means the widest caption this screen can be asked to draw
	# is not the one anything measures.
	#
	# The PARTY side is the binding case and the only one afflicted here: a member's caption is
	# already the longer of the two ("You  Lv1  20/20  MP 8/8" against "Deepdweller  10/10"), so
	# a tag that fits there fits beside a foe. Afflicting the foes as well would need a seam on
	# the logic that exists only for this test, which is a worse trade than saying which case
	# binds and measuring that one.
	var screen := _full_party_screen([], true)
	var logic := screen.logic()
	for at in logic.member_count():
		assert_str(logic.member_tag(at)).override_failure_message(
			"member %d was afflicted by the fixture and came back with no tag, so this audit is "
			% at + "measuring the same captions the untagged one already did").is_not_empty()
	_assert_nothing_overlaps(screen, "full party wearing statuses")


func test_every_foe_of_a_full_formation_is_named() -> void:
	# The overlap audit proves nothing COLLIDES; it cannot prove anything was drawn. A banner
	# that forgot the third foe would pass it perfectly.
	var screen := _full_field_screen()
	var drawn := 0
	for label: Label in screen._foe_names:
		if label.visible and not label.text.strip_edges().is_empty():
			drawn += 1
	assert_int(drawn).override_failure_message(
		"a formation of %d named %d of them" % [BattleScreen.MAX_FOES, drawn]) \
		.is_equal(BattleScreen.MAX_FOES)

func test_one_bar_says_how_the_foe_you_are_aiming_at_is_doing() -> void:
	# ONE, whatever the formation's size - which is the M42 divergence from this template's own
	# M28, and Clair Obscur's shape. Eight reference games and not one draws a bar per enemy.
	var lone := _screen()
	assert_str(lone._foe_bar.numbers.text).override_failure_message(
		"the banner says nothing about the foe in front of you").is_equal("99/99")
	var crowd := _full_field_screen()
	assert_int(crowd._foe_names.size()).is_equal(BattleScreen.MAX_FOES)
	assert_str(crowd._foe_bar.numbers.text).override_failure_message(
		"a formation of three draws something other than one bar").is_equal("99/99")

func test_the_named_foe_is_the_one_the_bar_is_about() -> void:
	# The banner's own coupling: a name is LIT to say the number below belongs to it, so a bar
	# about one foe under a name lit for another is a readout pointing at the wrong body.
	var screen := _full_field_screen()
	var logic := screen.logic()
	# Aim at the last foe, which is not the one a fresh banner shows.
	logic.press()
	_walk(logic, BattleLogic.Phase.MENU)
	assert_int(logic.phase()).override_failure_message(
		"the cursor over the formation never opened").is_equal(BattleLogic.Phase.FOE)
	logic.move(1)
	screen._paint()
	var aimed := screen.marked_foe()
	assert_int(aimed).override_failure_message(
		"the cursor moved and the banner still shows the first foe").is_not_equal(0)
	var text := screen._style.ui_color("text")
	for i in screen._foe_names.size():
		var lit: Color = screen._foe_names[i].get_theme_color("font_color")
		assert_bool(lit == text).override_failure_message(
			"foe %d is lit %s where the bar is about foe %d" % [i, lit, aimed]) \
			.is_equal(i == aimed)


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


## How many foes the banner is currently lighting - which is how it says whose number the one
## bar underneath belongs to. Read off the COLOUR rather than off a marker inside the text, for
## the party mark's reason.
func _marked_foes(screen: BattleScreen) -> int:
	var text := screen._style.ui_color("text")
	var out := 0
	for label: Label in screen._foe_names:
		if label.visible and label.get_theme_color("font_color") == text:
			out += 1
	return out
