extends GdUnitTestSuite
## How the game plays, chosen by the player, in a running world (M51).
##
## PlayChoices decides what a game offers and which value is in effect, and test_play_choices proves
## that with no scene. What only a world can answer is the wiring: the Options page draws a row for
## what the game in view offers, a press on it writes the choice and says so, a fight style takes hold
## at the next fight, and movement and saving take hold as the page closes over a running game.

const GAME := "res://data/games/quest.tres"
const SCRATCH := "user://test_world_play_choices.json"
const TEST_DIR := "user://test_saves"

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)
	# The redirect FIRST, and asserted: a press on a play row writes the settings file, and every
	# test here starts from nothing chosen.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.use_path(SCRATCH)
	assert_str(Settings.path()).override_failure_message(
		"the redirect is not in effect - this suite would write a settings file it does not own"
	).is_equal(SCRATCH)


func after_test() -> void:
	Input.action_release(&"move_left")
	Input.action_release(&"move_down")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.use_path(Settings.path_for(GameSelect.args()))
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.dir_for(GameSelect.args())
	GameState.reset()
	Router.reset()


func _manifest() -> GameManifest:
	return load(GAME) as GameManifest


func _instance() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world


## A world with `manifest` on its title, nothing started.
func _title_for(manifest: GameManifest) -> void:
	_instance()
	var games: Array[GameManifest] = [manifest]
	assert_bool(_world.offer_games(games)).is_true()
	assert_int(Router.state()).is_equal(Router.State.TITLE)


## A world with `manifest` running and its opening conversation pressed through.
func _running(manifest: GameManifest) -> void:
	_instance()
	assert_bool(_world.start_game(manifest)).is_true()
	for i in 40:
		if Router.state_name() == "world":
			return
		await _press(&"interact")
	fail("the opening conversation never handed the world back")


## The Options page opened over the running world, one press on the play row for `axis`, and the page
## closed again - which is when movement and saving take hold.
func _choose_over_the_world(axis: StringName) -> void:
	assert_bool(_world.open_options(true)).is_true()
	_world.options_screen().play_requested.emit(axis)
	_world._close_options()
	await _steps(2)
	assert_str(Router.state_name()).is_equal("world")


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)
	await await_idle_frame()
	await _steps(1)


## Runs the world until the player is between steps. Bounded, and it fails rather than hanging.
func _until_standing(player: ActorBody) -> void:
	for i in 120:
		await _steps(1)
		if not player.stepping():
			return
	fail("the player never finished a step")


## Something to open a fight against, built in code so a retune of the shipped enemies moves nothing.
func _enemy() -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_foe"
	out.name = "Test Foe"
	out.character = &"quest_warden"
	out.max_hp = 99
	out.attack = 1
	out.defense = 0
	out.xp = 5
	out.moves = [{"name": "Clout", "power": 0}]
	out.speed_tiles_per_second = 0.0
	return out


# -- the page --------------------------------------------------------------------------------------


func test_the_title_offers_every_play_row_for_the_game_on_offer() -> void:
	# At the title no game is running, so the rows are about the game being OFFERED - the only one
	# that exists there, and the one New game would start.
	_title_for(_manifest())
	assert_bool(_world.open_options()).is_true()
	var menu: OptionsMenu = _world.options_screen().menu()
	assert_int(menu.size()).override_failure_message(
		"the title's options page is missing play rows for a game that offers them").is_equal(5)
	assert_str(menu.label(2)).is_equal("Fights: Turns")
	assert_str(menu.label(3)).is_equal("Movement: Free")
	assert_str(menu.label(4)).is_equal("Saving: Anywhere")


func test_a_game_that_cannot_fight_is_offered_no_fights_row() -> void:
	var peaceful := _manifest().duplicate() as GameManifest
	peaceful.combat = null
	_title_for(peaceful)
	assert_bool(_world.open_options()).is_true()
	var menu: OptionsMenu = _world.options_screen().menu()
	assert_int(menu.size()).override_failure_message(
		"a game with no combat was offered a choice about how to fight").is_equal(4)
	assert_str(menu.label(2)).is_equal("Movement: Free")


func test_a_press_on_the_fights_row_chooses_the_sword_and_the_row_says_so() -> void:
	_title_for(_manifest())
	assert_bool(_world.open_options()).is_true()
	var screen: OptionsScreen = _world.options_screen()
	screen.play_requested.emit(PlayChoices.FIGHTS)
	assert_str(String(Settings.play_choice(PlayChoices.FIGHTS))).override_failure_message(
		"the Fights row was pressed and nothing was chosen").is_equal("arena")
	assert_str(screen.menu().label(2)).is_equal("Fights: Sword")
	screen.play_requested.emit(PlayChoices.FIGHTS)
	assert_str(String(Settings.play_choice(PlayChoices.FIGHTS))).is_equal("turns")
	assert_str(screen.menu().label(2)).is_equal("Fights: Turns")


# -- the fight -------------------------------------------------------------------------------------


func test_a_player_who_never_chose_fights_the_way_the_game_declares() -> void:
	await _running(_manifest())
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_object(_world.battle_screen()).override_failure_message(
		"a turn game with nothing chosen did not open the turn fight").is_not_null()
	assert_object(_world.arena_screen()).is_null()


func test_choosing_the_sword_opens_the_arena_in_a_game_that_declares_turns() -> void:
	assert_bool(Settings.choose_play(PlayChoices.FIGHTS, CombatDef.STYLE_ARENA)).is_true()
	await _running(_manifest())
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_object(_world.arena_screen()).override_failure_message(
		"the player chose the sword and the fight opened with menus").is_not_null()
	assert_object(_world.battle_screen()).is_null()


func test_a_word_the_game_does_not_offer_fights_the_way_the_game_declares() -> void:
	# Left in the file by a build that offered it; this one does not, so it does not apply.
	assert_bool(Settings.choose_play(PlayChoices.FIGHTS, &"realtime")).is_true()
	await _running(_manifest())
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_object(_world.battle_screen()).is_not_null()


func test_a_fight_style_chosen_over_the_world_takes_hold_at_the_next_fight() -> void:
	await _running(_manifest())
	await _choose_over_the_world(PlayChoices.FIGHTS)
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_object(_world.arena_screen()).override_failure_message(
		"the sword was chosen mid-run and the next fight still opened with menus").is_not_null()


# -- movement --------------------------------------------------------------------------------------


func test_choosing_tiles_makes_one_tap_move_exactly_one_tile() -> void:
	assert_bool(Settings.choose_play(PlayChoices.MOVEMENT, PlayChoices.MOVE_GRID)).is_true()
	await _running(_manifest())
	var player: ActorBody = _world.player()
	var from := player.global_position
	# A tap, not a hold: moving freely it would cover a few pixels, moving tile by tile a whole tile.
	Input.action_press(&"move_down")
	await _steps(2)
	Input.action_release(&"move_down")
	await _until_standing(player)
	assert_vector(player.global_position - from).override_failure_message(
		"a tap moved the player %s" % (player.global_position - from)).is_equal(
			Vector2(0.0, float(GameState.tile_size)))


func test_switching_to_tiles_mid_run_rebinds_everyone_and_stands_the_player_on_a_centre() -> void:
	await _running(_manifest())
	var player: ActorBody = _world.player()
	# Off a centre on purpose: moving freely leaves a player wherever the last frame stopped them.
	player.place(player.global_position + Vector2(5.0, 3.0))
	await _steps(1)
	await _choose_over_the_world(PlayChoices.MOVEMENT)
	var tile_size := GameState.tile_size
	var tile := MapData.world_to_tile(player.global_position, tile_size)
	assert_vector(player.global_position).override_failure_message(
		"the player switched to tiles and was left between them, at %s" % player.global_position
		).is_equal(MapData.tile_to_world(tile, tile_size))
	var bodies := 0
	for entry: Variant in _world._npcs.values():
		var body := (entry as Dictionary)["body"] as ActorBody
		assert_bool(body.config.grid_step).override_failure_message(
			"'%s' still walks by the old rule" % body.name).is_true()
		bodies += 1
	assert_int(bodies).is_greater(0)
	# And the player's own next step is a whole tile.
	var from := player.global_position
	Input.action_press(&"move_down")
	await _steps(2)
	Input.action_release(&"move_down")
	await _until_standing(player)
	assert_vector(player.global_position - from).is_equal(Vector2(0.0, float(tile_size)))


func test_a_player_switched_to_tiles_against_someone_stands_on_the_nearest_free_centre() -> void:
	# Touching the warden from the south, the player's feet are inside the warden's own cell, so the
	# centre of that cell is the warden. The nearest centre the player can step to is the one below.
	await _running(_manifest())
	var player: ActorBody = _world.player()
	var warden := (_world._npcs[&"warden"] as Dictionary)["body"] as ActorBody
	var tile_size := GameState.tile_size
	var below := warden.global_position + Vector2(0.0, player.config.body_size_px().y + 1.0)
	var warden_tile := MapData.world_to_tile(warden.global_position, tile_size)
	assert_vector(Vector2(MapData.world_to_tile(below, tile_size))).override_failure_message(
		"the player is not inside the warden's cell, so this proves nothing").is_equal(Vector2(warden_tile))
	player.place(below)
	await _steps(1)
	await _choose_over_the_world(PlayChoices.MOVEMENT)
	assert_vector(player.global_position).override_failure_message(
		"the player was stood at %s, the warden is at %s" % [player.global_position,
			warden.global_position]).is_equal(MapData.tile_to_world(warden_tile + Vector2i(0, 1), tile_size))


func test_moving_tile_by_tile_meets_an_enemy_on_the_tile_it_lands_on() -> void:
	# The hollow's slink_gate stands in the gap at [4, 5]; walking west along row 4 meets it on [4, 4].
	# A fight opened half way through that step would halt the player back onto [5, 4].
	assert_bool(Settings.choose_play(PlayChoices.MOVEMENT, PlayChoices.MOVE_GRID)).is_true()
	await _running(_manifest())
	assert_bool(_world.enter_map(&"quest_hollow", &"from_village")).is_true()
	await _steps(2)
	var tile_size := GameState.tile_size
	var player: ActorBody = _world.player()
	player.place(MapData.tile_to_world(Vector2i(6, 4), tile_size))
	await _steps(2)
	assert_str(Router.state_name()).is_equal("world")
	Input.action_press(&"move_left")
	for i in 150:
		await _steps(1)
		if Router.state_name() == "battle":
			break
	Input.action_release(&"move_left")
	assert_str(Router.state_name()).is_equal("battle")
	assert_vector(player.global_position).override_failure_message(
		"the fight opened with the player at %s rather than on the tile they walked onto"
		% player.global_position).is_equal(MapData.tile_to_world(Vector2i(4, 4), tile_size))


func test_a_save_restored_moving_tile_by_tile_stands_on_the_centre_of_its_tile() -> void:
	# A save records where the player stood, and one written while moving freely is between tiles.
	assert_bool(Settings.choose_play(PlayChoices.MOVEMENT, PlayChoices.MOVE_GRID)).is_true()
	await _running(_manifest())
	var data := GameState.to_save()
	data.map = &"quest_village"
	data.tile = Vector2(3.5, 2.8)
	assert_bool(_world.restore(data)).is_true()
	assert_vector(_world.player().global_position).override_failure_message(
		"a restore moving tile by tile left the player at %s" % _world.player().global_position
		).is_equal(MapData.tile_to_world(Vector2i(3, 2), GameState.tile_size))


# -- saving ----------------------------------------------------------------------------------------


func test_choosing_save_points_takes_the_save_row_away_and_the_game_keeps_its_own_config() -> void:
	await _running(_manifest())
	assert_bool(_world.open_pause()).is_true()
	assert_bool(_world.pause_screen()._menu.can_save()).override_failure_message(
		"the control failed: the pause menu offers no Save row before anything was chosen").is_true()
	_world._close_pause()
	await _steps(2)
	await _choose_over_the_world(PlayChoices.SAVING)
	assert_bool(_world.open_pause()).is_true()
	assert_bool(_world.pause_screen()._menu.can_save()).override_failure_message(
		"save points were chosen and the pause menu still offers to save").is_false()
	# Laid over a copy: the manifest's own config, shared with everything that reads it, is untouched.
	var shipped := load(GAME) as GameManifest
	assert_str(String(shipped.config.save_policy)).is_equal(String(GameConfig.SAVE_ANYWHERE))
	assert_bool(shipped.config.grid_step).is_false()
