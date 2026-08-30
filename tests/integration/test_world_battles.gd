extends GdUnitTestSuite
## Fighting, losing, and getting back on the road, in a running world.
##
## What can only be answered here is the wiring. BattleLogic already proves the rules; this
## proves that a fight takes control, that its result reaches the ONE sink exactly once, that
## losing ends the run rather than dropping the player back into the world, and that both ways
## out of a game-over screen actually rebuild a world.
##
## The fights are driven through REAL KEYPRESSES rather than by emitting the screen's signal.
## The difference is not cosmetic: the screen latches itself the frame it reports a result, and
## a test that emits `finished` directly never sets that latch - so it would prove the world
## behaves, and nothing at all about the screen that has to ask it to.

const GAME := "res://data/games/quest.tres"
const TEST_DIR := "user://test_saves"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)

func after_test() -> void:
	Input.action_release(&"move_right")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.DEFAULT_DIR
	GameState.reset()
	Router.reset()

## The player's side of a fight, built in code. The shipped game grows its own CombatDef with
## the content; this suite is about the WIRING, and pinning it to the designer's numbers would
## make every rebalance a test failure in a file about screens and signals.
func _combat() -> CombatDef:
	var out := CombatDef.new()
	out.id = &"test_combat"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 50  # ends a test fight in one swing, so the wiring is what is measured
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	out.base_mp = 6
	out.mp_per_level = 3
	out.xp_curve = [10, 12]
	out.attack_cue_frames = 4
	out.defend_cue_frames = 4
	out.timed_window_frames = 2
	out.message_frames = 2
	return out

## The shipped game with a combat definition attached. A duplicate rather than an edit: the
## manifest is a loaded resource, and Godot hands every caller the same instance - assigning to
## it here would leave `combat` set for every other suite in the run.
func _manifest() -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.combat = _combat()
	return manifest

## The shipped game, but opening in the map that actually places enemies. A duplicate for the
## same reason _manifest() duplicates: a loaded resource is shared with every other suite.
func _hollow_manifest() -> GameManifest:
	var manifest := _manifest()
	manifest.start_map = &"quest_hollow"
	manifest.start_spawn = &"from_village"
	return manifest

func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_manifest())).override_failure_message(
		"the world would not start the game").is_true()
	# The game opens with the warden's conversation on screen now. Every test below is about
	# something else, so getting past it belongs here rather than in each of them.
	await _dismiss_opening()
	return _world

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

## An enemy built in code rather than loaded, so the wiring tests do not move every time a
## designer retunes the shipped ones - and so a fight can be made trivially winnable or
## unwinnable without a map that places it.
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
	return out

## Runs the fight forward until it hands control back, pressing confirm whenever a menu is up.
## BOUNDED, and it asserts it actually got out: a "drive until it finishes" loop over a machine
## that can stall is how a suite hangs the whole run instead of failing.
func _fight_it_out(bound := 60) -> void:
	for i in bound:
		if Router.state_name() != "battle":
			return
		await _press(&"interact")
	fail("the fight never ended within %d presses" % bound)

func _good_save() -> SaveData:
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_town"
	data.position = MapData.tile_to_world(Vector2i(4, 6), 16)
	data.facing = Dir.D.DOWN
	data.party = {"hp": 7, "xp": 30, "level": 2}
	return data


# -- taking control ------------------------------------------------------------------------

func test_a_fight_takes_control_and_gives_it_back() -> void:
	await _boot()
	var player: ActorBody = _world.player()
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).is_true()
	assert_str(Router.state_name()).is_equal("battle")
	assert_bool(_world.open_battle_with([_enemy()], "quest_village/foe")).override_failure_message(
		"a second fight opened over the first").is_false()

	var held := player.global_position
	Input.action_press(&"move_right")
	await _steps(6)
	assert_vector(player.global_position).override_failure_message(
		"the player kept walking while a fight was on").is_equal(held)
	Input.action_release(&"move_right")

	await _fight_it_out()
	assert_str(Router.state_name()).override_failure_message(
		"the world did not come back after the fight").is_equal("world")

func test_a_fresh_player_starts_the_first_fight_at_full_health() -> void:
	# The derivation that turns "no party yet" into a real hero. Without it the first fight
	# opens on a player at zero health, who loses before pressing anything.
	await _boot()
	assert_int(GameState.player_hp).override_failure_message(
		"a new game began with a player who has no health").is_greater(0)
	assert_int(GameState.player_hp).is_equal(_combat().max_hp(1))
	assert_int(GameState.player_level).is_equal(1)


# -- winning -------------------------------------------------------------------------------

func test_winning_pays_out_once_and_only_once() -> void:
	# Exactly, not "at least": the screen reports its result from inside a frame callback, and
	# a missing latch pays the same xp again on every frame that follows.
	await _boot()
	var before := GameState.player_xp
	_world.open_battle_with([_enemy(1, 1, 5)], "quest_village/foe")
	await _fight_it_out()
	await _steps(20)
	assert_int(GameState.player_xp).override_failure_message(
		"the fight paid out more than once").is_equal(before + 5)

func test_a_screen_nobody_closes_still_reports_its_result_once() -> void:
	# Driven with NO world, on purpose. In the running game the world frees the screen the
	# instant it answers, so the latch never gets a second frame to matter - which means a test
	# that went through the world would pass with the latch deleted, and did.
	#
	# The latch is not decoration, though: this is a template component, and a game that
	# connects `finished` and leaves the screen up is a game whose every frame re-applies the
	# same xp, the same seen key and the same item take. So it is tested where it is reachable.
	var screen := BattleScreen.new()
	add_child(screen)
	var counted := [0]
	screen.finished.connect(func(_outcome: int, _effects: Array) -> void:
		counted[0] += 1)
	screen.setup(BattleHelpers.solo(_combat(), _enemy(1, 1, 5), 20, 0, 1),
		load("res://data/styles/dusk16.tres") as SpriteStyle, Vector2i(320, 180),
		FileSpriteSource.create(&"dusk16"))

	# Enough frames to end the fight several times over, if it could.
	for i in 12:
		screen.logic().press()
		await _steps(4)
	assert_int(counted[0]).override_failure_message(
		"a screen left on screen reported its result %d times" % counted[0]).is_equal(1)
	screen.free()

func test_a_key_is_not_offered_as_something_to_drink() -> void:
	# Only things that HEAL reach the fight menu. A gate key in there is a row that can only
	# disappoint, and worse, a row that spends the turn it is pressed on.
	# The control - an item that DOES belong there - arrives with the tonic and the content.
	await _boot()
	GameState.give_item(&"gate_key")
	_world.open_battle_with([_enemy(999)], "quest_village/foe")
	assert_array(_world.battle_screen().logic().item_rows()).override_failure_message(
		"the fight offered the player something that cannot be drunk").is_empty()

func test_a_beaten_enemy_is_remembered_as_beaten() -> void:
	await _boot()
	_world.open_battle_with([_enemy()], "quest_village/foe")
	await _fight_it_out()
	assert_bool(GameState.was_seen("quest_village/foe")).override_failure_message(
		"nothing recorded the fight, so the enemy is standing there again").is_true()

func test_a_player_who_has_never_fought_is_filled_in_from_the_curve() -> void:
	# THE one place "no party yet" becomes a real hero, and until now nothing asserted it: a
	# mutant emptying it survived. Zero hp is the unset signal, so a boot that skipped this
	# derivation would open the first fight with a player who is already dead - and a boot that
	# derived the health and not the magic would open it with a caster who cannot cast.
	await _boot()
	var combat := _combat()
	assert_int(GameState.player_hp).override_failure_message(
		"a new game started a player at nought health").is_equal(combat.max_hp(1))
	assert_int(GameState.player_mp).override_failure_message(
		"a new game started a player with no magic at all").is_equal(combat.max_mp(1))
	assert_int(combat.max_mp(1)).override_failure_message(
		"the fixture game has no magic, so this could not tell a fill-in from a no-op") \
		.is_greater(0)

func test_winning_a_fight_leaves_the_player_where_the_fight_left_them() -> void:
	# The party effect reaching the sink. A fight that reported nothing would hand back a
	# player at full health, and every fight would be free.
	await _boot()
	GameState.set_party(9, 0, 1, 0)
	_world.open_battle_with([_enemy(20, 3, 5)], "quest_village/foe")
	await _fight_it_out()
	assert_int(GameState.player_hp).override_failure_message(
		"the player came out of a fight with more health than they went in with"
	).is_less_equal(9)

func test_a_fight_is_offered_only_the_spells_the_player_has_reached() -> void:
	# Knowing a spell is DERIVED, so this is the whole learning mechanism: the same player, one
	# level apart, gets a different page. Asserted at both ends - a filter written as "all of
	# them" passes the level-2 half, and one written as "none" passes neither.
	await _boot()
	GameState.set_party(9, 0, 1, 8)
	_world.open_battle_with([_enemy(4, 1, 0)], "quest_village/foe")
	var early: Array = _world.battle_screen().logic().spell_rows()
	var early_names := PackedStringArray()
	for row: BattleLogic.SpellRow in early:
		early_names.append(String(row.id))
	assert_array(early).override_failure_message(
		"a level-1 player was offered no spells at all, so nothing here is being filtered") \
		.is_not_empty()
	assert_bool(early_names.has("lull")).override_failure_message(
		"a level-2 spell was offered to a level-1 player").is_false()
	assert_bool(early_names.has("ember")).is_true()

func test_a_spell_arrives_when_its_level_does() -> void:
	await _boot()
	GameState.set_party(9, 0, 2, 11)
	_world.open_battle_with([_enemy(4, 1, 0)], "quest_village/foe")
	var names := PackedStringArray()
	for row: BattleLogic.SpellRow in _world.battle_screen().logic().spell_rows():
		names.append(String(row.id))
	assert_bool(names.has("lull")).override_failure_message(
		"levelling past a spell's own level did not hand it over").is_true()

## Every Label the battle screen is currently drawing, as text. The rows are the screen's own
## nodes, so this is the only way to ask what the PLAYER can see rather than what the rules say.
func _screen_text() -> PackedStringArray:
	var out := PackedStringArray()
	for node in SceneHelpers.find_all_by_class(_world.battle_screen(), "Label"):
		var label := node as Label
		if label.visible:
			out.append(label.text)
	return out

func test_the_battle_screen_draws_the_magic_and_what_each_spell_costs() -> void:
	# The mutation sweep's own lesson from the equipment screen: the world's wording was fully
	# tested and nothing asserted the SCREEN drew it, so hiding the readout left everything
	# green. A cost the player cannot see is a decision they cannot make.
	await _boot()
	GameState.set_party(9, 0, 1, 5)
	_world.open_battle_with([_enemy(4, 1, 0)], "quest_village/foe")
	var caption := "".join(_screen_text())
	assert_str(caption).override_failure_message(
		"the battle screen never says how much magic the player has").contains("MP 5/")

	# Down onto Magic, in, and the page has to name a price ON THE ROW. Asserted as the whole
	# row text: the hero's caption says "MP" too, so a test looking for that substring alone
	# passes with every price stripped off the list - the masking path that makes a check
	# decoration.
	_open_the_spells()
	assert_array(_screen_text()).override_failure_message(
		"the spell page does not price its rows: %s" % [_screen_text()]) \
		.contains(["> Ember  3 MP"])

## Opens the spell page and repaints, so the labels hold what the page would draw.
func _open_the_spells() -> void:
	var screen: BattleScreen = _world.battle_screen()
	screen.logic().move(BattleLogic.Row.MAGIC)
	screen.logic().press()
	assert_int(screen.logic().phase()).is_equal(BattleLogic.Phase.SPELLS)
	screen._paint()

func test_every_row_of_the_longest_page_is_actually_drawn() -> void:
	# The pool is built once, at setup, and _paint_rows hides what it has no label for - so a
	# pool cut short does not error, it silently stops drawing rows. Both pages are asserted:
	# the commands are the longer list at level 1 and the spells at level 2, so a pool sized
	# from either one alone would pass half of this and truncate the other.
	await _boot()
	GameState.set_party(9, 0, 2, 11)
	_world.open_battle_with([_enemy(4, 1, 0)], "quest_village/foe")
	var visible := _screen_text()
	for command in BattleScreen.COMMANDS:
		assert_bool(_is_drawn(visible, command)).override_failure_message(
			"the command '%s' is not on screen: %s" % [command, visible]).is_true()

	_open_the_spells()
	var spells: Array = _world.battle_screen().logic().spell_rows()
	assert_int(spells.size()).override_failure_message(
		"a level-2 player was offered no spells, so the page half of this proves nothing") \
		.is_greater(0)
	var page := _screen_text()
	for row: BattleLogic.SpellRow in spells:
		assert_bool(_is_drawn(page, row.name)).override_failure_message(
			"the spell '%s' is in the fight and not on the screen: %s" % [row.name, page]) \
			.is_true()

## Whether any visible line carries this row's name. A row is drawn with a cursor prefix or
## without one, so matching the whole line would only ever find one of the two.
func _is_drawn(lines: PackedStringArray, name: String) -> bool:
	for line in lines:
		if line.contains(name):
			return true
	return false

func test_a_fight_is_handed_the_players_magic_and_gives_it_back() -> void:
	# Two halves of one wiring, and each is silent on its own: a world that never passed the
	# player's MP in would start every fight empty, and a fight sealing an mp the sink ignored
	# would empty the player on the way out. Asserted at a number that is neither nought nor
	# full, because both bugs agree with the player's own value at those ends.
	await _boot()
	var carried := _combat().max_mp(1) - 2
	assert_int(carried).override_failure_message(
		"the fixture game has no magic, so this test could not see it move").is_greater(0)
	# No xp on the foe, because a level-up refills the magic and would agree with a fight that
	# had quietly handed back full MP all along.
	GameState.set_party(9, 0, 1, carried)
	_world.open_battle_with([_enemy(1, 1, 0)], "quest_village/foe")
	assert_int(_world.battle_screen().logic().member_mp(0)).override_failure_message(
		"the fight opened without the magic the player was carrying").is_equal(carried)
	await _fight_it_out()
	assert_int(GameState.player_mp).override_failure_message(
		"the fight handed back magic the player never had").is_equal(carried)


# -- losing --------------------------------------------------------------------------------

func test_losing_ends_the_run() -> void:
	await _boot()
	GameState.set_party(1, 0, 1, 0)
	_world.open_battle_with([_enemy(999, 99)], "quest_village/foe")
	await _fight_it_out()
	assert_str(Router.state_name()).override_failure_message(
		"a lost fight dropped the player back into the world").is_equal("game_over")
	assert_object(_world.game_over_screen()).is_not_null()

func test_a_lost_fight_earns_nothing() -> void:
	# Above all it must not mark the enemy beaten: the thing that just won is still standing.
	await _boot()
	GameState.set_party(1, 0, 1, 0)
	var before := GameState.player_xp
	_world.open_battle_with([_enemy(999, 99, 25)], "quest_village/foe")
	await _fight_it_out()
	assert_int(GameState.player_xp).is_equal(before)
	assert_bool(GameState.was_seen("quest_village/foe")).override_failure_message(
		"losing to something deleted it from the map").is_false()


# -- getting back on the road ---------------------------------------------------------------

func test_continuing_from_a_save_puts_the_player_back_in_it() -> void:
	await _boot()
	assert_bool(SaveManager.save(0, _good_save())).is_true()
	GameState.set_party(1, 0, 1, 0)
	_world.open_battle_with([_enemy(999, 99)], "quest_village/foe")
	await _fight_it_out()
	assert_str(Router.state_name()).is_equal("game_over")

	# Through the real keys: Continue, then the first slot.
	await _press(&"interact")
	await _press(&"interact")
	await _steps(4)
	assert_str(Router.state_name()).override_failure_message(
		"loading from the game-over screen did not put a world back").is_equal("world")
	assert_str(String(GameState.current_map)).is_equal("quest_town")
	assert_int(GameState.player_hp).override_failure_message(
		"the loaded save's party was not restored").is_equal(7)
	assert_int(GameState.player_level).is_equal(2)

func test_starting_again_rebuilds_the_game_from_the_beginning() -> void:
	await _boot()
	GameState.set_flag(&"lit_the_lantern", true)
	GameState.set_party(1, 99, 3, 0)
	_world.open_battle_with([_enemy(999, 99)], "quest_village/foe")
	await _fight_it_out()
	assert_str(Router.state_name()).is_equal("game_over")

	# Down to "Start again", then in.
	await _press(&"move_down")
	await _press(&"interact")
	await _steps(4)
	# A fresh run, so the warden says her piece again - which is the point of starting again,
	# and the reason this asserts the opening rather than dismissing it quietly.
	assert_str(Router.state_name()).override_failure_message(
		"starting again did not begin the story again").is_equal("dialog")
	await _dismiss_opening()
	assert_str(Router.state_name()).is_equal("world")
	assert_int(GameState.player_level).override_failure_message(
		"starting again kept the dead run's level").is_equal(1)
	assert_bool(GameState.has_flag(&"lit_the_lantern")).override_failure_message(
		"starting again kept the dead run's progress").is_false()
	assert_int(GameState.player_hp).is_greater(0)

func test_continuing_with_nothing_saved_is_refused_and_the_screen_keeps_answering() -> void:
	# The refusal, and the control for it: the screen must still be listening afterwards, or a
	# player with no saves is stuck on a menu that has stopped responding entirely.
	await _boot()
	GameState.set_party(1, 0, 1, 0)
	_world.open_battle_with([_enemy(999, 99)], "quest_village/foe")
	await _fight_it_out()
	assert_str(Router.state_name()).is_equal("game_over")

	await _press(&"interact")
	await _steps(2)
	assert_str(Router.state_name()).override_failure_message(
		"continuing with no saves at all did something").is_equal("game_over")

	await _press(&"move_down")
	await _press(&"interact")
	await _steps(4)
	await _dismiss_opening()
	assert_str(Router.state_name()).override_failure_message(
		"the game-over screen stopped answering after a refusal").is_equal("world")


# -- enemies on a real map ------------------------------------------------------------------

func test_a_map_puts_bodies_on_the_tiles_its_enemies_stand_on() -> void:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_hollow_manifest())).is_true()
	assert_array(_world.enemy_ids()).override_failure_message(
		"the hollow drew none of the enemies its map file places").contains([&"slink_gate"])

func test_something_already_beaten_is_never_drawn_again() -> void:
	# The rule that makes "defeated enemies stay gone" true across a save and a re-entry. It
	# is checked at SPAWN rather than by hiding the body afterwards, because a hidden body
	# still blocks the tile it stands on - and here that tile is a one-tile gap, so the map
	# would become uncrossable for a reason the player cannot see.
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_hollow_manifest())).is_true()
	assert_array(_world.enemy_ids()).contains([&"slink_gate"])

	GameState.mark_seen("quest_hollow/slink_gate")
	assert_bool(_world.enter_map(&"quest_hollow", &"from_village")).is_true()
	assert_array(_world.enemy_ids()).override_failure_message(
		"a beaten enemy was standing on its tile again after re-entering the map"
	).not_contains([&"slink_gate"])
	# And the control: the one that has NOT been beaten is still there, so this is a test
	# about the seen key rather than about enemies failing to spawn at all.
	assert_array(_world.enemy_ids()).contains([&"slink_stash"])

## The game now opens with the warden's conversation on screen, so every suite that boots it
## has to get past that before it can test anything else. Bounded and asserted rather than a
## fixed number of presses: the box reveals text a character at a time, so how many presses a
## conversation takes depends on how long its lines are - and a "press until it goes away"
## loop with no cap is how a suite hangs instead of failing.
func _dismiss_opening() -> void:
	for i in 12:
		if Router.state_name() != "dialog":
			return
		await _press(&"interact")
	fail("the opening conversation would not close")
