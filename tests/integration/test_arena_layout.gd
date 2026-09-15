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
	# The widest readout the panel is laid out for, so every audit below measures it beside the help.
	out.base_hp = ArenaScreen.READOUT_CAPACITY
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


## The grass cut from a style's own generated atlas: the ground a fight on grass is laid with.
func _grass(style_id: String) -> Texture2D:
	var meta := JsonFile.read("res://assets/generated/%s/tiles.json" % style_id)
	var cut := AtlasTexture.new()
	cut.atlas = load("res://assets/generated/%s/tiles.png" % style_id) as Texture2D
	cut.region = Rect2(TileSetFactory.walkable_region(meta.data, "grass"))
	return cut


## An arena at capacity - the widest floor this screen declares and a full formation, the longest
## name first, on grass unless told otherwise - in `style_id`'s art, mounted the way the world mounts
## it. `source` hands every fighter a fixture sheet instead of the style's committed art.
func _screen(style_id: String, grounded := true, source: SpriteSource = null) -> ArenaScreen:
	var style := load("res://data/styles/%s.tres" % style_id) as SpriteStyle
	var screen := ArenaScreen.new()
	UiScale.mount(screen, self, style)
	var combat := _combat()
	var foes := [_enemy("The Keeper", &"quest_keeper"), _enemy("Slink", &"quest_slink"),
		_enemy("Slink", &"quest_slink")]
	assert_int(foes.size()).is_equal(FightScreen.MAX_FOES)
	var sim := ArenaSim.of(combat, foes, [BattleHelpers.leader(combat, ArenaScreen.READOUT_CAPACITY)],
		"map/foe", 7, GameConfig.new())
	var art := source if source != null else FileSpriteSource.create(StringName(style_id))
	screen.setup(sim, style, UiScale.DESIGN_SIZE, art, _grass(style_id) if grounded else null)
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


## On the floor, a body or one of the floor's own layers - the drawn slash, the ground - which the
## screen tags as such: things whose overlapping is the fight rather than a fault.
func _is_field(child: Node) -> bool:
	return child is SpriteView or child.has_meta(ArenaScreen.FIELD)


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
			if screen._player_view.frames_in(FightScreen.SLASH) > 0:
				# Art that draws its own swing: the hero is caught mid-slash, measured as the body he
				# is, and nothing is drawn over him.
				assert_str(String(screen._player_view.clip())).override_failure_message(
					"%s, %s: the hero is not swinging the blade his art draws" % [style_id, wall[0]]
					).is_equal("slash")
				assert_bool(screen._blade.visible).is_false()
			else:
				assert_bool(screen._blade.visible).override_failure_message(
					"%s, %s: the drawn slash is not shown, so the audit says nothing about it"
					% [style_id, wall[0]]).is_true()
			_assert_laid_out(screen, "%s, %s" % [style_id, wall[0]])

func test_a_hero_whose_swing_outgrows_his_walk_stays_inside_the_floor_at_every_wall() -> void:
	# The floor's margins were read from a sheet's one cell. A swing drawn on a grid of its own, wider and
	# taller than the walk, then went out through the window's frame at every wall - and the audit above
	# still passed, because it measured the hero as his walk. In lpc32's shape only: dusk16 draws a
	# fighter at twice size, and a 64px fixture would not fit its screen at all.
	var built := ArtFixtures.two_grid_sheet(Vector2i(104, 96), Vector2i(52, 84))
	for entry: Variant in _walls():
		var wall: Array = entry
		var screen := _screen("lpc32", true, FixedSpriteSource.new(built))
		_stage(screen, wall[1], wall[2], wall[3])
		assert_str(String(screen._player_view.clip())).is_equal("slash")
		assert_vector(Vector2(screen._player_view.cell_size())).override_failure_message(
			"%s: the hero is measured as his walk, not his swing" % wall[0]).is_equal(Vector2(104, 96))
		_assert_laid_out(screen, "a swing wider than the walk, %s" % wall[0])


func test_the_floor_at_capacity_still_fits_the_screen_with_the_swing_the_sword_draws() -> void:
	# The bronze arming sword's swing, cropped to what it draws, measured from the art on 2026-09-15:
	# 97 by 54 with the feet at (48, 49). Uncropped, its 128px cell asks for a floor 328 pixels wide.
	var built := ArtFixtures.two_grid_sheet(Vector2i(97, 54), Vector2i(48, 49))
	var screen := _screen("lpc32", true, FixedSpriteSource.new(built))
	var wall: Array = _walls()[0]
	_stage(screen, wall[1], wall[2], wall[3])
	assert_vector(screen._floor.panel.size).override_failure_message(
		"the floor window is %s" % screen._floor.panel.size).is_equal(Vector2(313, 106))
	_assert_laid_out(screen, "the sword's swing at capacity")


func test_the_shipped_hero_s_swing_sizes_the_floor_the_way_it_was_measured() -> void:
	# The same numbers from the committed art rather than a fixture: the fixture above proves the
	# arithmetic, and this proves the hero the game ships is the one it was done for.
	var screen := _screen("lpc32")
	var wall: Array = _walls()[1]
	_stage(screen, wall[1], wall[2], wall[3])
	assert_str(String(screen._player_view.clip())).is_equal("slash")
	assert_vector(screen._floor.panel.size).override_failure_message(
		"the floor window is %s" % screen._floor.panel.size).is_equal(Vector2(313, 106))


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


## Three foes pressed into far corners, clear of a player swinging up from the middle of the floor.
const FAR := [Vector2i(80, 48), Vector2i(4016, 48), Vector2i(4016, 976)]

func test_the_leader_of_one_art_swings_its_own_blade_and_the_other_gets_a_drawn_one() -> void:
	# The pair the per-wall audit rests on: without it, "the hero's art draws a slash" could quietly
	# become false for both styles and every wall case would take the drawn-slash branch.
	assert_int(_screen("lpc32")._player_view.frames_in(FightScreen.SLASH)).override_failure_message(
		"the lpc32 hero's sheet draws no slash").is_greater(1)
	assert_int(_screen("dusk16")._player_view.frames_in(FightScreen.SLASH)).is_equal(0)

func test_a_hero_whose_art_swings_plays_every_picture_of_it_in_order() -> void:
	var screen := _screen("lpc32")
	_stage(screen, Vector2i(2048, 560), Dir.D.UP, FAR)
	var shown: Array[int] = []
	while screen.sim().swinging() and shown.size() < 40:
		assert_str(String(screen._player_view.clip())).is_equal("slash")
		var frame := screen._player_view.current_frame()
		if shown.is_empty() or shown[shown.size() - 1] != frame:
			shown.append(frame)
		screen.sim().tick(Vector2.ZERO, false)
		screen._paint()
	assert_str(str(shown)).override_failure_message(
		"the swing showed pictures %s" % [shown]).is_equal("[0, 1, 2, 3, 4, 5]")
	assert_str(String(screen._player_view.clip())).override_failure_message(
		"the hero is still holding a slash after the sword went away").is_equal("idle")

func test_a_drawn_slash_sweeps_across_the_reach_and_stays_inside_it() -> void:
	# Art with no swing of its own shows one as a bright edge crossing the sword's reach. It has to
	# move, or it is the flat block it replaced, and it has to stay inside the reach it shows.
	var screen := _screen("dusk16")
	_stage(screen, Vector2i(2048, 560), Dir.D.UP, FAR)
	var edges: Array[float] = []
	while screen.sim().swinging() and edges.size() < 40:
		assert_bool(screen._blade.visible).is_true()
		var reach := Rect2(Vector2.ZERO, screen._blade.size).grow(0.001)
		for part: Control in [screen._blade_trail, screen._blade_edge]:
			assert_bool(reach.encloses(Rect2(part.position, part.size))).override_failure_message(
				"part of the drawn slash at %s is outside the reach %s" % [Rect2(part.position, part.size), reach]
				).is_true()
		edges.append(screen._blade_edge.position.x)
		screen.sim().tick(Vector2.ZERO, false)
		screen._paint()
	assert_int(edges.size()).is_greater(2)
	assert_float(edges[edges.size() - 1]).override_failure_message(
		"facing up, the edge should cross left to right; it went %s" % [edges]).is_greater(edges[0])
	# And it is drawn over the swinger: a rig sprite is 32 design pixels wide around a body box of 10,
	# so beneath the body the reach is almost wholly hidden by the body it comes out of.
	assert_int(screen._blade.get_index()).override_failure_message(
		"the drawn slash is drawn under the hero swinging it").is_greater(screen._player_view.get_index())


## Puts every body exactly where a test says and repaints, with no tick: a tick wanders the foes and
## shoves whatever the sword or a touch reaches, which is noise when the question is where feet stand.
func _place_still(screen: ArenaScreen, player_at: Vector2i, foes_at: Array) -> void:
	var spots: Array[Vector2i] = []
	spots.assign(foes_at)
	screen.sim().stage(player_at, Dir.D.UP, spots)
	screen._paint()

## Every pair of bodies on the floor, whatever the screen holds: the one whose feet stand lower is drawn
## after the other. Over all of them rather than the two a test staged side by side, because a sort that
## gets the staged pair right can still leave the rest in any order.
func _assert_front_to_back(screen: ArenaScreen, case_name: String) -> void:
	var bodies: Array = [[screen.sim().player_box().end.y, screen._player_view]]
	for i in screen._foe_views.size():
		bodies.append([screen.sim().foe_box(i).end.y, screen._foe_views[i]])
	for a: Array in bodies:
		for b: Array in bodies:
			if int(a[0]) > int(b[0]):
				assert_int((a[1] as Node).get_index()).override_failure_message(
					"%s: a body standing on row %d is drawn behind one on row %d" % [case_name, a[0], b[0]]
					).is_greater((b[1] as Node).get_index())

func test_a_body_lower_on_the_floor_is_drawn_in_front_of_one_above_it() -> void:
	# Floor units, every body in this fixture 160 by 96: a player centred at y 600 stands on row 648, a
	# foe centred at y 540 on row 588, and the two boxes overlap, which is where the order shows.
	var screen := _screen("lpc32")
	_place_still(screen, Vector2i(2048, 600), [Vector2i(2088, 540), FAR[1], FAR[2]])
	assert_bool(screen.sim().player_box().intersects(screen.sim().foe_box(0))).is_true()
	assert_int(screen.sim().player_box().end.y).is_equal(648)
	assert_int(screen.sim().foe_box(0).end.y).is_equal(588)
	assert_int(screen._player_view.get_index()).override_failure_message(
		"the hero stands below the foe and is drawn behind it").is_greater(screen._foe_views[0].get_index())
	_assert_front_to_back(screen, "the hero in front")
	assert_int(screen._ground.get_index()).override_failure_message(
		"ordering the bodies put one under the ground").is_equal(0)
	assert_int(screen._blade.get_index()).override_failure_message(
		"ordering the bodies put one over the drawn slash").is_equal(screen._floor.panel.get_child_count() - 1)
	# The same two, rows swapped, on a screen of their own.
	var behind := _screen("lpc32")
	_place_still(behind, Vector2i(2048, 540), [Vector2i(2088, 600), FAR[1], FAR[2]])
	assert_int(behind.sim().player_box().end.y).is_equal(588)
	assert_int(behind.sim().foe_box(0).end.y).is_equal(648)
	assert_int(behind._player_view.get_index()).override_failure_message(
		"the hero stands above the foe and is drawn in front of it").is_less(behind._foe_views[0].get_index())
	_assert_front_to_back(behind, "the hero behind")

func test_bodies_standing_level_are_drawn_in_slot_order_frame_after_frame() -> void:
	# Two foes on one row: neither is nearer, so the later slot is drawn in front, and stays in front on
	# every paint - an order that could change between frames would flicker one body over the other.
	var screen := _screen("dusk16")
	_place_still(screen, Vector2i(2048, 900), [Vector2i(800, 500), Vector2i(3000, 500), FAR[0]])
	assert_int(screen.sim().foe_box(0).end.y).is_equal(screen.sim().foe_box(1).end.y)
	for paint in 3:
		assert_int(screen._foe_views[1].get_index()).override_failure_message(
			"paint %d: two foes on one row were drawn out of slot order" % paint
			).is_greater(screen._foe_views[0].get_index())
		_assert_front_to_back(screen, "paint %d" % paint)
		screen._paint()


func test_the_ground_covers_the_play_area_exactly_and_is_drawn_behind_everything() -> void:
	for style_id: String in ["dusk16", "lpc32"]:
		var screen := _screen(style_id)
		var ground := screen._ground
		assert_object(ground).override_failure_message("%s: no ground was laid" % style_id).is_not_null()
		# The floor here is 16 by 4 tiles at 16 design pixels each: 256 by 64, from the floor's origin.
		assert_vector(ground.position).is_equal(screen._origin)
		assert_vector(ground.size).override_failure_message(
			"%s: the ground is %s, not the play area" % [style_id, ground.size]).is_equal(Vector2(256, 64))
		assert_int(ground.get_index()).override_failure_message(
			"%s: the ground is drawn over something on the floor" % style_id).is_equal(0)
		var covered := {}
		for node in ground.get_children():
			var piece := node as TextureRect
			assert_vector(piece.size).is_equal(Vector2(16, 16))
			covered[piece.position] = true
		for y in 4:
			for x in 16:
				assert_bool(covered.has(Vector2(x * 16, y * 16))).override_failure_message(
					"%s: no ground at tile (%d, %d)" % [style_id, x, y]).is_true()

func test_a_fight_with_no_ground_is_drawn_on_the_bare_window() -> void:
	var screen := _screen("dusk16", false)
	assert_object(screen._ground).is_null()
	assert_array(SceneHelpers.find_all_by_class(screen._floor.panel, "TextureRect")).is_empty()

func test_every_style_lays_its_ground_one_texture_pixel_to_a_whole_number_of_window_pixels() -> void:
	# A tile of TILE_PX design pixels, on a layer scaled by the world scale. Anything but a whole number
	# of window pixels per texture pixel resamples the ground, and grass shimmers as the eye tracks it.
	var checked := 0
	for path in ContentScan.files_of("res://data/styles", "tres"):
		var style := load(path) as SpriteStyle
		var per_texel := float(UiScale.scale_of(style) * ArenaScreen.TILE_PX) / float(style.tile_size)
		assert_float(per_texel).override_failure_message(
			"'%s' draws its ground at %s window pixels a texture pixel" % [style.id, per_texel]
			).is_equal(roundf(per_texel))
		assert_float(per_texel).is_greater_equal(1.0)
		checked += 1
	assert_int(checked).is_greater(1)


func _binds(action: StringName, key: int) -> bool:
	for event in InputMap.action_get_events(action):
		var pressed := event as InputEventKey
		if pressed != null and (pressed.physical_keycode == key or pressed.keycode == key):
			return true
	return false

func test_the_help_line_names_moving_and_swinging_on_keys_that_are_bound() -> void:
	var screen := _screen("dusk16")
	assert_str(screen._help.text).is_equal(ArenaScreen.HELP)
	assert_bool(screen._help.visible).is_true()
	assert_str(screen._leader_bar.numbers.text).override_failure_message(
		"the audits are not measuring the widest readout").is_equal("999/999")
	var words := ArenaScreen.HELP.to_lower().split(" ", false)
	for word: String in ["wasd", "move", "e", "swing"]:
		assert_bool(words.has(word)).override_failure_message(
			"the help line '%s' does not say '%s'" % [ArenaScreen.HELP, word]).is_true()
	# Every key it names does what it says: a shop here once told players to press a key nothing binds.
	assert_bool(_binds(&"interact", KEY_E)).override_failure_message("E does not swing").is_true()
	for pair: Array in [[&"move_up", KEY_W], [&"move_left", KEY_A], [&"move_down", KEY_S], [&"move_right", KEY_D]]:
		assert_bool(_binds(pair[0], int(pair[1]))).override_failure_message(
			"%s is not on its WASD key" % pair[0]).is_true()
