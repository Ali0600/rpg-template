extends GdUnitTestSuite
## A fight fought with a sword, in a running world.
##
## The rules are ArenaSim's and proven in test_arena_sim; what can only be answered here is the
## wiring. A game whose CombatDef says `arena` must open an ArenaScreen and nothing else, the player
## on the map must be stopped while it is up, and a win and a loss must come back through the world's
## one fight sink exactly as a turn fight's do.
##
## The fights are driven through REAL INPUT - the four move actions held and the sword pressed -
## choosing the way ArenaDriver's PERFECT does, so what is proven is the screen's reading of the
## keys as well as the world's reading of the result.

const GAME := "res://data/games/quest.tres"
const DUSK := "res://data/styles/dusk16.tres"
const TEST_DIR := "user://test_saves"

var _world: Node2D
var _tapped := false
## A shipped item given art for one test, and the art it had, put back after it: a loaded resource is
## the Registry's own copy and every suite in the run shares it.
var _lent: ItemDef = null
var _lent_art := {}


func before_test() -> void:
	GameState.reset()
	Router.reset()
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)
	_tapped = false


func after_test() -> void:
	if _lent != null:
		_lent.worn_art = _lent_art
		_lent = null
	_release_moves()
	_tap(false)
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.dir_for(GameSelect.args())
	GameState.reset()
	Router.reset()


## Quick numbers, so the wiring is what is measured: one swing fells anything this suite fights.
func _combat(style: StringName = CombatDef.STYLE_ARENA) -> CombatDef:
	var out := CombatDef.new()
	out.id = &"arena_wiring"
	out.style = style
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 50
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	out.xp_curve = [10, 12]
	out.attack_cue_frames = 4
	out.defend_cue_frames = 4
	out.timed_window_frames = 2
	out.message_frames = 2
	out.swing_frames = 4
	out.hurt_frames = 8
	out.foe_hurt_frames = 4
	out.push_frames = 2
	out.arena_tiles = Vector2i(8, 4)
	return out


## The shipped game with this suite's combat attached. A duplicate, because a loaded resource is
## shared with every other suite in the run.
func _manifest(style: StringName = CombatDef.STYLE_ARENA) -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.combat = _combat(style)
	return manifest


## Something standing still to fight, built in code so a retune of the shipped enemies moves nothing
## here.
func _enemy(hp := 1, attack := 1, xp := 5) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_foe"
	out.name = "Test Foe"
	out.character = &"quest_warden"
	out.max_hp = hp
	out.attack = attack
	out.defense = 0
	out.xp = xp
	out.moves = [{"name": "Clout", "power": 0}]
	out.speed_tiles_per_second = 0.0
	return out


func _boot(style: StringName = CombatDef.STYLE_ARENA) -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_manifest(style))).override_failure_message(
		"the world would not start the game").is_true()
	await _dismiss_opening()
	return _world


## The game opens with the warden's conversation on screen. Every test here is about something
## else, so it is pressed through - bounded, and it says so if it never ends.
func _dismiss_opening() -> void:
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
	# An idle frame too: input is flushed once a process frame, and a headless run can fit several
	# physics frames inside one.
	await await_idle_frame()
	await _steps(1)


## The sword button, down or up, as a real event - the screen reads a press, not a held state.
func _tap(down: bool) -> void:
	if not down and not _tapped:
		return
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = down
	Input.parse_input_event(event)
	_tapped = down


func _hold(move: Vector2) -> void:
	_set_held(Dir.D.LEFT, move.x < 0.0)
	_set_held(Dir.D.RIGHT, move.x > 0.0)
	_set_held(Dir.D.UP, move.y < 0.0)
	_set_held(Dir.D.DOWN, move.y > 0.0)


func _set_held(d: Dir.D, down: bool) -> void:
	var action := Locomotion.action_for(d)
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_moves() -> void:
	for d: Dir.D in Dir.ALL:
		Input.action_release(Locomotion.action_for(d))


## Plays the arena that is up the way PERFECT would, through the keys, until the world has it back.
## BOUNDED, and it fails when the bound runs out rather than hanging the run.
func _play_perfectly(bound := 2000) -> void:
	for i in bound:
		var screen: ArenaScreen = _world.arena_screen()
		if screen == null or Router.state_name() != "battle":
			_release_moves()
			return
		var choice := ArenaDriver.choose(screen.sim(), ArenaDriver.Policy.PERFECT)
		_hold(choice.move)
		if choice.swing:
			_tap(true)
		await _steps(1)
		_tap(false)
	_release_moves()
	fail("the arena never ended within %d frames" % bound)


# -- the seam ------------------------------------------------------------------------------------


func test_the_arena_draws_the_sword_the_leader_wears() -> void:
	# Both resolvers take their fighters from the world's one list, so the sword worn is the one swung
	# here too (docs/DECISIONS.md, M50.4) - and it is the art the floor's margins are measured over.
	await _boot()
	_lent = Registry.get_resource(&"ItemDef", &"bronze_sword") as ItemDef
	_lent_art = _lent.worn_art
	_lent.worn_art = {&"quest_wanderer": &"quest_wanderer_longsword"}
	GameState.give_item(&"bronze_sword", 1)
	assert_bool(GameState.equip(&"weapon", &"bronze_sword")).is_true()
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_str(String(_world.arena_screen().sim().member_character(0))).override_failure_message(
		"the arena drew the hero without the sword he wears").is_equal("quest_wanderer_longsword")


func test_an_arena_game_opens_the_arena_and_the_player_on_the_map_stays_put() -> void:
	await _boot()
	var player: ActorBody = _world.player()
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_str(Router.state_name()).is_equal("battle")
	assert_object(_world.arena_screen()).override_failure_message(
		"a game whose combat says arena opened something else").is_not_null()
	assert_object(_world.battle_screen()).is_null()
	assert_object(_world.fight_screen()).is_same(_world.arena_screen())
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).override_failure_message(
		"a second fight opened over the first").is_false()
	var held := player.global_position
	Input.action_press(&"move_right")
	await _steps(6)
	Input.action_release(&"move_right")
	assert_vector(player.global_position).override_failure_message(
		"the player on the map walked while the arena was up").is_equal(held)
	# Mounted like every other screen, so it is drawn at the world's own scale.
	assert_vector(_world.arena_screen().scale).is_equal(UiScale.layer_scale(_world._style))

func test_a_turn_game_still_opens_the_turn_fight_and_both_announce_their_foes_by_id() -> void:
	await _boot(CombatDef.STYLE_TURNS)
	var announced: Array = []
	var record := func(payload: Variant) -> void: announced.append(payload)
	EventBus.battle_changed.connect(record)
	_world.open_battle_with([_enemy()], "quest_village/foe")
	EventBus.battle_changed.disconnect(record)
	assert_object(_world.battle_screen()).is_not_null()
	assert_object(_world.arena_screen()).is_null()
	var opened: Dictionary = announced[0]
	assert_int((opened["enemies"] as Array).size()).is_equal(1)
	assert_str(str((opened["enemies"] as Array)[0])).is_equal("test_foe")

func test_winning_the_arena_pays_out_once_and_gives_the_world_back() -> void:
	await _boot()
	var before := GameState.player_xp
	var announced: Array = []
	var record := func(payload: Variant) -> void: announced.append(payload)
	EventBus.battle_changed.connect(record)
	assert_bool(_world.open_battle_with([_enemy(1, 1, 5)], "quest_village/foe")).is_true()
	await _play_perfectly()
	await _steps(20)
	EventBus.battle_changed.disconnect(record)
	assert_str(Router.state_name()).is_equal("world")
	assert_int(GameState.player_xp).override_failure_message(
		"a won arena paid %d xp rather than 5, once" % (GameState.player_xp - before)).is_equal(
		before + 5)
	assert_bool(GameState.was_seen("quest_village/foe")).is_true()
	assert_int(announced.size()).is_equal(2)
	var opened: Dictionary = announced[0]
	var closed: Dictionary = announced[1]
	assert_str(str((opened["enemies"] as Array)[0])).is_equal("test_foe")
	assert_str(str(closed["outcome"])).is_equal("victory")

func test_losing_the_arena_ends_the_run_and_applies_nothing() -> void:
	await _boot()
	var before := GameState.player_xp
	assert_bool(_world.open_battle_with([_enemy(1, 999)], "quest_village/foe")).is_true()
	var screen: ArenaScreen = _world.arena_screen()
	var sim := screen.sim()
	# Stood on the foe's own spot, so the first frame is the touch.
	var spots: Array[Vector2i] = [sim.foe_pos(0)]
	sim.stage(sim.foe_pos(0), Dir.D.UP, spots)
	await _steps(4)
	assert_str(Router.state_name()).is_equal("game_over")
	assert_int(GameState.player_xp).is_equal(before)
	assert_bool(GameState.was_seen("quest_village/foe")).is_false()

func test_holding_the_sword_button_is_one_swing_and_the_keys_move_the_player() -> void:
	await _boot()
	assert_bool(_world.open_battle_with([_enemy(99)], "quest_village/foe")).is_true()
	var screen: ArenaScreen = _world.arena_screen()
	var sim := screen.sim()
	_tap(true)
	# Four times the swing's length: a held button that swung again would show it.
	await _steps(16)
	_tap(false)
	assert_int(sim.swings()).override_failure_message(
		"holding the button swung %d times" % sim.swings()).is_equal(1)
	var from := sim.player_pos()
	Input.action_press(&"move_right")
	await _steps(10)
	Input.action_release(&"move_right")
	assert_int(sim.player_pos().x).override_failure_message(
		"holding right did not move the player in the arena").is_greater(from.x)

func test_an_arena_nobody_closes_reports_its_result_once() -> void:
	# Driven with NO world, for test_world_battles' reason: in the running game the world frees the
	# screen the instant it answers, so the latch never gets a second frame to matter there.
	var screen := ArenaScreen.new()
	add_child(screen)
	var counted := [0]
	screen.finished.connect(func(_outcome: int, _effects: Array) -> void: counted[0] += 1)
	var combat := _combat()
	var sim := ArenaSim.of(combat, [_enemy(1)], [BattleHelpers.leader(combat)], "map/foe", 7,
		GameConfig.new())
	screen.setup(sim, load(DUSK) as SpriteStyle, Vector2i(320, 180),
		FileSpriteSource.create(&"dusk16"))
	# Won before the screen has run a frame: the foe stands inside the sword of a player swinging up.
	var spots: Array[Vector2i] = [Vector2i(1024, 700)]
	sim.stage(Vector2i(1024, 800), Dir.D.UP, spots)
	sim.tick(Vector2.ZERO, true)
	assert_bool(sim.finished()).is_true()
	await _steps(12)
	assert_int(counted[0]).override_failure_message(
		"an arena left on screen reported its result %d times" % counted[0]).is_equal(1)
	screen.free()


# -- the ground ------------------------------------------------------------------------------------


## The region a tile id takes in the running style's own atlas: the expectation, read from the
## generated table rather than from anything the screen was handed.
func _region_of(id: String) -> Rect2:
	var meta := JsonFile.read("res://assets/generated/%s/tiles.json" % _world._style.id)
	return Rect2(TileSetFactory.walkable_region(meta.data, id))


## The atlas region the open arena's floor is laid with, or an empty rect when it has none.
func _ground_region() -> Rect2:
	var screen: ArenaScreen = _world.arena_screen()
	if screen == null or screen._ground == null or screen._ground.get_child_count() == 0:
		return Rect2()
	var piece := screen._ground.get_child(0) as TextureRect
	return (piece.texture as AtlasTexture).region


func _fight_record_on(map_id: StringName, spawn: StringName, record_id: String) -> void:
	assert_bool(_world.enter_map(map_id, spawn)).is_true()
	await _steps(2)
	assert_object(_world.fight_screen()).override_failure_message(
		"arriving at '%s' opened a fight by itself, so this staging proves nothing" % map_id).is_null()
	assert_bool(_world.open_battle_with([_enemy()], Interaction.seen_key(map_id, record_id))).is_true()


func test_a_fight_is_fought_on_the_ground_under_the_record_it_came_from() -> void:
	# The hollow's SECOND record rather than its first: slink_gate stands on plain grass and
	# slink_stash on the other grass, so a floor taken from whichever record comes first is caught.
	await _boot()
	await _fight_record_on(&"quest_hollow", &"from_village", "slink_stash")
	var expected := _region_of("grass_alt")
	assert_bool(expected.has_area()).is_true()
	assert_str(str(_ground_region())).override_failure_message(
		"the slink_stash fight was laid with %s, not the grass_alt it stood on" % _ground_region()
		).is_equal(str(expected))


func test_the_cave_s_gloom_is_fought_on_the_cave_path() -> void:
	await _boot()
	await _fight_record_on(&"quest_cave", &"west_gate", "gloom")
	assert_str(str(_ground_region())).is_equal(str(_region_of("path")))


func test_a_fight_no_record_on_the_map_answers_to_keeps_the_plain_window() -> void:
	await _boot()
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	var screen: ArenaScreen = _world.arena_screen()
	assert_object(screen._ground).is_null()
