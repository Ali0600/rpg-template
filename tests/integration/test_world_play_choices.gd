extends GdUnitTestSuite
## How the game plays, chosen by the player, in a running world (M51).
##
## PlayChoices decides what a game offers and which value is in effect, and test_play_choices proves
## that with no scene. What only a world can answer is the wiring: the Options page draws a row for
## what the game in view offers, a press on it writes the choice and says so, and the next fight opens
## the screen the choice names.

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


func test_the_title_offers_a_fights_row_for_the_game_on_offer() -> void:
	# At the title no game is running, so the rows are about the game being OFFERED - the only one
	# that exists there, and the one New game would start.
	_title_for(_manifest())
	assert_bool(_world.open_options()).is_true()
	var menu: OptionsMenu = _world.options_screen().menu()
	assert_int(menu.size()).override_failure_message(
		"the title's options page has no Fights row for a game that can fight").is_equal(3)
	assert_str(menu.label(2)).is_equal("Fights: Turns")


func test_a_game_that_cannot_fight_is_offered_no_fights_row() -> void:
	var peaceful := _manifest().duplicate() as GameManifest
	peaceful.combat = null
	_title_for(peaceful)
	assert_bool(_world.open_options()).is_true()
	assert_int(_world.options_screen().menu().size()).override_failure_message(
		"a game with no combat was offered a choice about how to fight").is_equal(2)


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


func test_a_choice_made_over_the_world_takes_hold_at_the_next_fight() -> void:
	# The on-the-spot half: chosen from the pause menu's way in, mid-run, and nothing rebuilt.
	await _running(_manifest())
	assert_bool(_world.open_options(true)).is_true()
	_world.options_screen().play_requested.emit(PlayChoices.FIGHTS)
	_world._close_options()
	await _steps(2)
	assert_str(Router.state_name()).is_equal("world")
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_object(_world.arena_screen()).override_failure_message(
		"the sword was chosen mid-run and the next fight still opened with menus").is_not_null()
