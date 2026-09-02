extends GdUnitTestSuite
## The world at 32px, driven through the real scene.
##
## Every screen in this project lays out against 320x180 and is measured there. What this
## suite asks is the other half: that a style wanting a bigger WORLD gets one, that every
## interface layer is drawn at that scale so the screens keep landing where they were
## measured, and that a save carries a place rather than a pixel count across the change.
##
## It boots a fixture map rather than a shipped one. A 32px map under data/maps would be
## content nobody plays that every map gate, both editor round trips and map_io --verify would
## then have to carry - so MapData.root is pointed at tests/fixtures/maps and put back after.

const GAME := "res://data/games/quest.tres"
const FIXTURE_MAPS := "res://tests/fixtures/maps"
const DUSK := "res://data/styles/dusk16.tres"

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()

func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	MapData.root = MapData.MAP_DIR
	# The window is NOT put back here. It outlives a suite, and a run left at 640x360 re-scales
	# every layout audit that comes afterwards - but the world scene restores it as it leaves the
	# tree, and a second writer here would mask a mutant aimed at that one. The test below is
	# what proves it happens.
	GameState.reset()
	Router.reset()


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _instantiate() -> Node2D:
	# The shipped maps, always, for the scene's own _ready: it boots the shipped game, and with
	# the fixture root still in effect from a previous boot that hunt fails and leaves the
	# half-built map it had already made behind. Six orphan nodes, no error, every assertion
	# below still passing. Each boot below moves the root again, AFTER this.
	MapData.root = MapData.MAP_DIR
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world


## The shipped game, opening on the fixture yard. The party is dropped because Rook has no
## lpc32 sheet yet, and the hooks because they are written for the quest's own maps.
func _wide_manifest() -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.start_map = &"lpc32_yard"
	manifest.start_spawn = &"start"
	manifest.party = []
	manifest.hooks = null
	return manifest


## The same game in a 16px yard. A fixture rather than a shipped map because the demo has no
## 16px map left - every one of them draws at lpc32 now, which is exactly the change this suite
## exists to measure.
func _narrow_manifest() -> GameManifest:
	var manifest := _wide_manifest()
	manifest.start_map = &"dusk16_yard"
	return manifest


## The fixture root is moved AFTER the scene is instantiated, never before: _ready boots the
## shipped game, and with the root already moved that boot looks for the quest's own start map
## in tests/fixtures/maps, fails to find it, and leaves the half-built map it had already
## made behind. Six orphan nodes, no error, and every assertion below still passing.
func _boot_wide() -> Node2D:
	var world := _instantiate()
	MapData.root = FIXTURE_MAPS
	assert_bool(world.start_game(_wide_manifest())).is_true()
	await _steps(1)
	return world


func _boot_narrow() -> Node2D:
	var world := _instantiate()
	MapData.root = FIXTURE_MAPS
	assert_bool(world.start_game(_narrow_manifest())).is_true()
	await _steps(1)
	return world


## A control's rectangle in SCREEN pixels - through its layer's transform, which is where the
## scale lives. Reading position and size alone measures design pixels and can never see it.
func _on_screen(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func test_a_world_that_goes_away_leaves_the_window_as_it_found_it() -> void:
	# The pair to binding a style. The window belongs to the root, so a world that grew it and
	# then went away has moved furniture that is not its own - and the suites that come next lay
	# themselves out against 320x180 whatever the window says, so their failures read as layout
	# faults rather than as this one leaving the lights on.
	#
	# It is asserted right after free() rather than left to after_test, because after_test is
	# where the old fix lived: eleven suites boot a world and exactly one of them put the window
	# back, so the rule was true where it was written down and nowhere else. THE ORDER OF THE
	# SUITES decided whether the run went green, which is why it passed here and failed on the
	# runner.
	var world := await _boot_wide()
	assert_vector(world.get_viewport_rect().size).override_failure_message(
		"the fixture did not grow the window, so freeing it cannot prove anything"
		).is_equal(Vector2(UiScale.DESIGN_SIZE) * 2.0)
	world.free()
	_world = null
	await _steps(1)
	assert_vector(get_tree().root.get_viewport().get_visible_rect().size) \
		.override_failure_message("the world went away and left the window at another style's "
		+ "size, so every suite after it lays out against a window it did not choose"
		).is_equal(Vector2(UiScale.DESIGN_SIZE))

func test_a_32px_style_is_played_in_a_640x360_world() -> void:
	var world := await _boot_wide()
	assert_vector(world.get_viewport_rect().size).override_failure_message(
		"a 32px map is being drawn into a 320x180 world, which is ten tiles across"
		).is_equal(Vector2(640.0, 360.0))
	# Twenty tiles across, which is what the template shows at every scale. The point of the
	# whole mechanism, stated as the thing a player sees rather than as a window size.
	assert_float(world.get_viewport_rect().size.x / 32.0).override_failure_message(
		"a 32px world is not twenty tiles across").is_equal(20.0)


func test_the_dialog_box_is_drawn_twice_as_big_and_measured_the_same() -> void:
	# The rendered outcome. The box is built from the same constants under both styles - 6px
	# from the edge, two 12px lines - and lands on twice the screen at lpc32. Anything that
	# scaled the layout instead of the layer would move these two apart.
	var narrow := await _boot_narrow()
	narrow._apply_effects([{"op": GameContext.OP_DIALOG, "dialog": "elder"}])
	await _steps(2)
	var small := _on_screen(narrow.dialog_box()._panel)
	narrow.free()
	_world = null

	var wide := await _boot_wide()
	wide._apply_effects([{"op": GameContext.OP_DIALOG, "dialog": "elder"}])
	await _steps(2)
	var big := _on_screen(wide.dialog_box()._panel)

	assert_vector(big.position).override_failure_message(
		"the dialog box sits at %s in a 640x360 world where it sits at %s in a 320x180 one"
		% [big.position, small.position]).is_equal(small.position * 2.0)
	assert_vector(big.size).override_failure_message(
		"the dialog box is %s in a 640x360 world and %s in a 320x180 one"
		% [big.size, small.size]).is_equal(small.size * 2.0)


func test_every_screen_the_world_opens_is_drawn_at_the_world_s_scale() -> void:
	# Membership over whatever is in the tree, rather than a list of screens to check: a
	# screen added around the mounting helper fails here without anybody remembering to add it.
	var world := await _boot_wide()
	var opened := 0
	for opener: Callable in [
		func() -> bool: return world.open_pause(),
		func() -> bool: return world.open_save(),
		func() -> bool: return world.open_rest(),
		func() -> bool: return world.open_shop(&"smith_shop"),
		func() -> bool: return world.open_game_over(),
	]:
		assert_bool(opener.call()).is_true()
		await _steps(1)
		opened += 1
		for child in world.get_children():
			var layer := child as CanvasLayer
			if layer == null:
				continue
			assert_vector(layer.scale).override_failure_message(
				"'%s' is drawn at %s in a world scaled 2x - a quarter-size screen in the corner"
				% [layer.name, layer.scale]).is_equal(Vector2(2.0, 2.0))
	assert_int(opened).override_failure_message(
		"no screen was opened, so this proved nothing").is_greater(4)


func test_the_dialog_box_and_the_hint_are_brought_up_with_the_rest() -> void:
	# Both are built in _build_game, before any map has said which style is running. They are
	# the two layers mounting alone cannot reach.
	var world := await _boot_wide()
	assert_vector(world.dialog_box().scale).override_failure_message(
		"the dialog box kept the scale it was built at, before a style was bound"
		).is_equal(Vector2(2.0, 2.0))
	for child in world.get_children():
		var hint := child as ControlsHint
		if hint != null:
			assert_vector(hint.scale).is_equal(Vector2(2.0, 2.0))


func test_the_state_learns_the_map_s_tile_size() -> void:
	var world := await _boot_wide()
	# The state records where the BODY is, once a physics frame - entering a map places the
	# player, and the frame after is what writes it down.
	await _steps(2)
	assert_int(GameState.tile_size).override_failure_message(
		"the state never learned the map's tile size, so a save here would be written at 16"
		).is_equal(32)
	assert_vector(GameState.to_save().tile).is_equal(
		world.player().global_position / 32.0)


func test_a_save_written_on_one_map_lands_on_the_same_tile_of_a_bigger_one() -> void:
	# The reason a save records tiles. This file was written by a 16px game; loading it into a
	# 32px map must put the player on tile (3.5, 2.5) of THAT map, not 112 pixels into it.
	#
	# The load has to CROSS sizes or it proves nothing: from_save converts with whatever size
	# is bound at the moment it runs, so a load that begins and ends on 32px tiles gets the
	# right answer by luck and every guard below it is unobservable. So the run starts in the
	# 16px town and the save names the yard.
	var world := await _boot_narrow()
	assert_int(GameState.tile_size).is_equal(16)
	MapData.root = FIXTURE_MAPS
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"lpc32_yard"
	data.tile = Vector2(3.5, 2.5)
	data.facing = Dir.D.DOWN
	assert_bool(world.restore(data)).is_true()
	# No frame is awaited here on purpose. The physics tick writes the body's position into the
	# state every frame, so one await would repair the very thing this asserts and the guard
	# would be unobservable - green, and gone the day somebody deleted it.
	assert_vector(world.player().global_position).override_failure_message(
		"a save of tile (3.5, 2.5) put the player at %s on a 32px map"
		% world.player().global_position).is_equal(Vector2(112.0, 80.0))
	# The state agrees on the frame the load lands, not on the next physics tick: from_save
	# converted with the tile size bound BEFORE the load, which at a change of style is a
	# different number.
	assert_vector(GameState.player_position).override_failure_message(
		"the state says the player stands at %s and the body stands at %s"
		% [GameState.player_position, world.player().global_position]
		).is_equal(world.player().global_position)
