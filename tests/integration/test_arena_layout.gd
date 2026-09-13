extends GdUnitTestSuite
## The arena's screen, measured at the capacity it declares.
##
## Four questions, the ones every screen audit here asks and one the floor adds: every window is
## inside the screen, no two windows meet, everything a window holds is inside its CONTENT rect, and
## nothing a window holds collides with anything else in it - except on the floor, where bodies and
## the blade overlapping is the fight. Asked in both kinds of art, because an LPC character stands
## on a different row of a different-sized cell, and with the player swinging at each wall, because
## that is where a body or a blade leaves the floor if the margins are wrong.

const VIEWPORT := Vector2i(320, 180)

var _screens: Array[ArenaScreen] = []


func after_test() -> void:
	for screen in _screens:
		if is_instance_valid(screen):
			screen.free()
	_screens.clear()


func _combat() -> CombatDef:
	var out := CombatDef.new()
	out.id = &"arena_layout"
	out.style = CombatDef.STYLE_ARENA
	out.xp_curve = [10]
	out.arena_tiles = ArenaScreen.FLOOR_MAX_TILES
	return out


func _enemy(foe_name: String, character: StringName) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = StringName(foe_name.to_lower().replace(" ", "_"))
	out.name = foe_name
	out.character = character
	out.max_hp = 10
	out.attack = 1
	out.defense = 0
	out.moves = [{"name": "Bump", "power": 0}]
	return out


## An arena at capacity - the widest floor this screen declares and a full formation, the longest
## name first - in `style_id`'s art, mounted the way the world mounts it.
func _screen(style_id: String) -> ArenaScreen:
	var style := load("res://data/styles/%s.tres" % style_id) as SpriteStyle
	var screen := ArenaScreen.new()
	UiScale.mount(screen, self, style)
	var combat := _combat()
	var foes := [_enemy("The Keeper", &"quest_keeper"), _enemy("Slink", &"quest_slink"),
		_enemy("Slink", &"quest_slink")]
	assert_int(foes.size()).is_equal(FightScreen.MAX_FOES)
	var sim := ArenaSim.of(combat, foes, [BattleHelpers.leader(combat)], "map/foe", 7,
		GameConfig.new())
	screen.setup(sim, style, UiScale.DESIGN_SIZE, FileSpriteSource.create(StringName(style_id)))
	_screens.append(screen)
	return screen


## The player a quarter of a tile from each wall, facing it and swinging, so the blade reaches past
## the wall; the three foes pressed into corners away from them. Floor units: 16 by 4 tiles is 4096
## by 1024, and a body's centre can come no nearer a wall than half of it (80 across, 48 down).
func _walls() -> Array:
	return [
		["the left wall", Vector2i(144, 512), Dir.D.LEFT,
			[Vector2i(4016, 48), Vector2i(4016, 976), Vector2i(2048, 48)]],
		["the right wall", Vector2i(3952, 512), Dir.D.RIGHT,
			[Vector2i(80, 48), Vector2i(80, 976), Vector2i(2048, 976)]],
		["the top wall", Vector2i(2048, 112), Dir.D.UP,
			[Vector2i(80, 976), Vector2i(4016, 976), Vector2i(80, 48)]],
		["the bottom wall", Vector2i(2048, 912), Dir.D.DOWN,
			[Vector2i(80, 48), Vector2i(4016, 48), Vector2i(4016, 976)]],
	]


func _stage(screen: ArenaScreen, player_at: Vector2i, facing: Dir.D, foes_at: Array) -> void:
	var spots: Array[Vector2i] = []
	spots.assign(foes_at)
	screen.sim().stage(player_at, facing, spots)
	screen.sim().tick(Vector2.ZERO, true)
	screen._paint()


func _label_rect(label: Label) -> Rect2:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	return Rect2(label.position, Vector2(measured.x, float(size)))


## A bar is one widget: its track, and the figures beside it.
func _bar_rect(root: Control) -> Rect2:
	var rect := Rect2(root.position, root.size)
	for child in root.get_children():
		var figures := child as Label
		if figures != null and not figures.text.is_empty():
			var inner := _label_rect(figures)
			rect = rect.merge(Rect2(root.position + inner.position, inner.size))
	return rect


## Where a child of a window is drawn, in the window's own coordinates, or an empty rect for
## something that draws nothing.
func _rect_in_window(child: Node) -> Rect2:
	if child is SpriteView:
		var view := child as SpriteView
		if view.cell_size() == Vector2i.ZERO:
			return Rect2()
		return Rect2(view.position - Vector2(view.anchor()) * view.scale,
			Vector2(view.cell_size()) * view.scale)
	if child is Label:
		return _label_rect(child as Label)
	if UiChrome.kind_of(child) == UiChrome.BAR:
		return _bar_rect(child as Control)
	if child is Control:
		return Rect2((child as Control).position, (child as Control).size)
	return Rect2()


## A node named by what a reader would recognise it as: a label by its text, anything else by class.
func _described(node: Node) -> String:
	var label := node as Label
	if label != null:
		return "the label '%s'" % label.text
	if UiChrome.kind_of(node) == UiChrome.BAR:
		return "a bar"
	return "a " + node.get_class()


## On the floor, a body or the blade: things whose overlapping is the fight rather than a fault.
func _is_field(child: Node) -> bool:
	return child is SpriteView or (child is ColorRect and UiChrome.kind_of(child) == &"")


func _assert_laid_out(screen: ArenaScreen, case_name: String) -> void:
	var windows: Array[Panel] = []
	for node in SceneHelpers.find_all_by_class(screen, "Panel"):
		windows.append(node as Panel)
	assert_int(windows.size()).override_failure_message(
		"%s: the arena drew %d windows, not 3" % [case_name, windows.size()]).is_equal(3)
	var whole := Rect2(Vector2.ZERO, Vector2(VIEWPORT))
	var measured := 0
	for i in windows.size():
		var outer := Rect2(windows[i].position, windows[i].size)
		assert_bool(whole.encloses(outer)).override_failure_message(
			"%s: window %d at %s leaves the %s screen" % [case_name, i, outer, VIEWPORT]).is_true()
		for j in range(i + 1, windows.size()):
			var other := Rect2(windows[j].position, windows[j].size)
			assert_bool(outer.intersects(other)).override_failure_message(
				"%s: windows %d and %d meet (%s, %s)" % [case_name, i, j, outer, other]).is_false()
		var room := UiChrome.inner_of(windows[i])
		var inside: Array = []
		for child in windows[i].get_children():
			var item := child as CanvasItem
			if item == null or not item.visible or UiChrome.kind_of(child) == UiChrome.HEADER:
				continue
			var rect := _rect_in_window(child)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			measured += 1
			assert_bool(room.encloses(rect)).override_failure_message(
				"%s: %s at %s is outside window %d's room %s"
				% [case_name, child.get_class(), rect, i, room]).is_true()
			inside.append([child, rect])
		for a in inside.size():
			for b in range(a + 1, inside.size()):
				var first: Array = inside[a]
				var second: Array = inside[b]
				if _is_field(first[0]) and _is_field(second[0]):
					continue
				assert_bool((first[1] as Rect2).intersects(second[1] as Rect2)).override_failure_message(
					"%s: %s %s and %s %s collide in window %d at %s"
					% [case_name, _described(first[0] as Node), first[1], _described(second[0] as Node),
						second[1], i, outer]).is_false()
	assert_int(measured).override_failure_message(
		"%s: almost nothing was measured, so this proves nothing" % case_name).is_greater(8)


func test_the_arena_fits_its_window_in_both_kinds_of_art_with_the_player_at_every_wall() -> void:
	for style_id: String in ["dusk16", "lpc32"]:
		for entry: Variant in _walls():
			var wall: Array = entry
			var screen := _screen(style_id)
			_stage(screen, wall[1], wall[2], wall[3])
			assert_bool(screen._blade.visible).override_failure_message(
				"%s, %s: the blade is not drawn, so the audit says nothing about it"
				% [style_id, wall[0]]).is_true()
			_assert_laid_out(screen, "%s, %s" % [style_id, wall[0]])

func test_the_bar_is_the_foe_the_fight_is_about() -> void:
	var screen := _screen("dusk16")
	# The second Slink stands inside the sword of a player swinging up; the other two are far off.
	_stage(screen, Vector2i(2048, 560), Dir.D.UP,
		[Vector2i(80, 48), Vector2i(4016, 48), Vector2i(2048, 400)])
	# Attack 5 at level 1 against defense 0 takes 5 off 10.
	assert_int(screen.sim().shown_foe()).is_equal(2)
	assert_str(screen._foe_bar.numbers.text).is_equal("5/10")

func test_a_struck_foe_flickers_for_as_long_as_it_is_protected() -> void:
	var screen := _screen("dusk16")
	_stage(screen, Vector2i(2048, 560), Dir.D.UP,
		[Vector2i(80, 48), Vector2i(4016, 48), Vector2i(2048, 400)])
	var seen := {}
	for f in 8:
		screen.sim().tick(Vector2.ZERO, false)
		screen._paint()
		seen[screen._foe_views[2].visible] = true
	assert_int(seen.size()).override_failure_message(
		"a struck foe was drawn the same way on eight frames of its protection").is_equal(2)

func test_a_body_that_moved_walks_and_one_that_did_not_stands() -> void:
	var screen := _screen("dusk16")
	screen.sim().tick(Vector2(1.0, 0.0), false)
	screen._paint()
	assert_str(String(screen._player_view.clip())).is_equal("walk")
	screen.sim().tick(Vector2.ZERO, false)
	screen._paint()
	assert_str(String(screen._player_view.clip())).is_equal("idle")
