extends GdUnitTestSuite
## The title against the real world node.
##
## It exists for the branch the scripted session structurally cannot reach: a --qa-script run
## empties its save directory at BOOT, so a session can never start with a save and can never
## drive Continue. This can write a slot and rebuild the title inside one process.

const GAME := "res://data/games/quest.tres"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()

func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()

func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world

func _manifest() -> GameManifest:
	return load(GAME) as GameManifest


func test_the_game_opens_on_a_title_rather_than_in_a_map() -> void:
	# The boot path itself: _ready resolves a game and then STOPS, where for twenty milestones
	# it started one.
	var world := _boot()
	assert_int(Router.state()).override_failure_message(
		"the game booted straight into the world").is_equal(Router.State.TITLE)
	var screen: TitleScreen = world.title_screen()
	assert_object(screen).is_not_null()


func test_the_title_wears_the_games_own_name() -> void:
	# Not a constant in the view: which game this is, and what it is called, is a manifest's
	# business - the same rule that keeps the controls hint out of the screen that draws it.
	var world := _boot()
	var screen: TitleScreen = world.title_screen()
	var found := ""
	for child in screen.get_children():
		if child is Label and (child as Label).text == _manifest().title:
			found = (child as Label).text
	assert_str(found).override_failure_message(
		"nothing on the title says what game this is").is_equal(_manifest().title)


func test_starting_a_new_game_builds_the_map_and_closes_the_title() -> void:
	var world := _boot()
	world._commit_new_game_from_title()
	await get_tree().physics_frame
	var gone: TitleScreen = world.title_screen()
	assert_object(gone).override_failure_message(
		"the title outlived the game it started").is_null()
	# Not asserted as WORLD: what a game does on its first frame is the GAME's business, and
	# this one opens on a conversation. What the title promised is that a run started, which is
	# the map being built and the title being gone.
	assert_bool(Router.state() != Router.State.TITLE).override_failure_message(
		"the title was still up after a run started").is_true()
	assert_str(String(GameState.current_map)).is_equal(String(_manifest().start_map))


func test_a_title_with_a_save_offers_it_and_loads_it() -> void:
	# The branch no scripted session can reach. Start a run, walk it somewhere, save it, then
	# rebuild the title over the top and load through it.
	var world := _boot()
	world._commit_new_game_from_title()
	await get_tree().physics_frame
	GameState.set_party(7, 11, 2, 0)
	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()

	assert_bool(world.open_title()).is_true()
	var screen: TitleScreen = world.title_screen()
	var menu: TitleMenu = screen.menu()
	assert_int(menu.index()).override_failure_message(
		"a title with a save did not open on Continue").is_equal(TitleMenu.Row.CONTINUE)
	menu.confirm()
	assert_int(menu.page()).is_equal(TitleMenu.Page.LOAD)

	world._commit_title_load(0)
	await get_tree().physics_frame
	assert_bool(Router.state() != Router.State.TITLE).is_true()
	assert_int(GameState.player_level).override_failure_message(
		"the run came back as a fresh one").is_equal(2)
	assert_int(GameState.player_hp).is_equal(7)


func test_a_refused_load_leaves_the_title_up() -> void:
	# The empty-slot rule reaching the real screen: refusing must not close the thing that
	# refused, or the player is dropped somewhere with no explanation.
	var world := _boot()
	world._commit_title_load(2)
	await get_tree().physics_frame
	var still: TitleScreen = world.title_screen()
	assert_object(still).is_not_null()
	assert_int(Router.state()).is_equal(Router.State.TITLE)


func test_losing_can_be_walked_back_to_the_title() -> void:
	# The promise the game-over screen's comment made for eight milestones.
	var world := _boot()
	world._commit_new_game_from_title()
	await get_tree().physics_frame
	assert_bool(world.open_game_over()).is_true()
	world._commit_title()
	await get_tree().physics_frame
	assert_int(Router.state()).is_equal(Router.State.TITLE)
	var back: TitleScreen = world.title_screen()
	assert_object(back).is_not_null()
	assert_str(String(GameState.current_map)).override_failure_message(
		"the world survived the run that ended in it").is_empty()


## Physics frames, which is the clock everything here counts on.
func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## One real keypress, the way the QA harness delivers them, with its release.
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


func test_pressing_continue_on_a_real_save_loads_it_through_the_screen() -> void:
	# Driven through the FRONT DOOR - real key events into the real screen - because the rule
	# under test is the screen's, not the world's. A test that called the world's handler
	# directly would prove the load works and nothing at all about the button that asks for it,
	# and a screen whose Continue emits nothing looks identical from there.
	var world := _boot()
	world._commit_new_game_from_title()
	await get_tree().physics_frame
	GameState.set_party(9, 11, 2, 0)
	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	GameState.set_party(3, 0, 1, 0)

	assert_bool(world.open_title()).is_true()
	await _steps(2)
	await _press(&"interact")          # Continue, which the cursor opens on when a save exists
	await _press(&"interact")          # slot 0
	await _steps(4)

	assert_int(GameState.player_level).override_failure_message(
		"pressing Continue at the title loaded nothing").is_equal(2)
	assert_int(GameState.player_hp).is_equal(9)
	var gone: TitleScreen = world.title_screen()
	assert_object(gone).is_null()


func test_continue_resumes_the_run_instead_of_replaying_its_opening() -> void:
	# The bug this pins was found by the user in play: Continue loaded the save UNDER the
	# warden's intro, because the load path passed through the start map with a fresh state on
	# its way to the save's map - and the entry hook, seeing no flags, opened her dialog.
	#
	# The fixture is built to make that impossible to miss where the first version of this
	# suite tolerated it: the save sits in a DIFFERENT map from the start map, with the met
	# flag set - so the right outcome is that map, that position, and NOBODY talking.
	var world := _boot()
	world._commit_new_game_from_title()
	await get_tree().physics_frame
	GameState.set_flag(&"met_the_warden", true)
	GameState.current_map = &"quest_town"
	GameState.player_position = Vector2(72.0, 88.0)
	GameState.set_party(9, 5, 1, 0)
	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()

	assert_bool(world.open_title()).is_true()
	world._commit_title_load(0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_str(String(GameState.current_map)).override_failure_message(
		"Continue went to the start map, not the save's").is_equal("quest_town")
	assert_bool(GameState.has_flag(&"met_the_warden")).override_failure_message(
		"the save's flags did not survive the load").is_true()
	var box: DialogBox = world.dialog_box()
	var talking := box != null and box.visible
	assert_bool(talking).override_failure_message(
		"Continue replayed the game's opening conversation over the loaded save").is_false()


func test_starting_a_run_announces_the_state_change() -> void:
	# The edge that was invisible until M23: enter_map resets the router, and reset used to
	# write the state field directly. So a game started and nothing heard about it - which is
	# how a Continue that passed through the start map went unnoticed for a milestone.
	var world := _boot()
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.flow_changed.connect(handler)
	world._commit_new_game_from_title()
	await get_tree().physics_frame
	EventBus.flow_changed.disconnect(handler)
	var first := ""
	if not seen.is_empty():
		first = "%s->%s" % [Router.State.find_key(int(seen[0]["from"])),
			Router.State.find_key(int(seen[0]["to"]))]
	assert_str(first).override_failure_message(
		"starting a run announced %s" % [seen]).is_equal("TITLE->WORLD")

