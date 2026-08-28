extends GdUnitTestSuite
## Gear reaching live state, through the real menu, the real counter and a real fight.
##
## The pure suites prove the ARITHMETIC of a modifier and the ANSWER a menu gives. This proves
## the wiring between them: that a press on a sword in the bag reaches the slot map, that a
## worn sword leaves the sell page, and that the mods actually arrive inside the fight rather
## than being resolved into a number nobody passes on.

const GAME := "res://data/games/quest.tres"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()

func after_test() -> void:
	Input.action_release(&"interact")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()

func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(load(GAME) as GameManifest)).is_true()
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

func test_presses_on_the_equipment_screen_put_the_sword_on() -> void:
	# Driven through the real menu rather than by calling equip(): the rule under test is that
	# a CONFIRM on that row reaches the slot map, and calling the writer directly would prove
	# the writer and nothing about the press.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	assert_bool(world.open_pause()).is_true()
	await _steps(2)
	# Two downs to Equipment, in to the slots, in to the weapon slot's candidates, in to wear
	# the only one there.
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _press(&"interact")
	await _press(&"interact")
	assert_str(String(GameState.equipped(&"weapon"))).override_failure_message(
		"a confirm on the sword row did not reach the slot map").is_equal("bronze_sword")
	# And it is still carried - equipping marks, it never moves.
	assert_int(GameState.item_count(&"bronze_sword")).is_equal(1)

func test_presses_on_the_take_off_row_empty_the_slot() -> void:
	# The other half of the verb, and the half M19 could not have: the toggle it shipped meant
	# taking off was the same press as putting on, which is a control nobody would find.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	GameState.equip(&"weapon", &"bronze_sword")
	assert_bool(world.open_pause()).is_true()
	await _steps(2)
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _press(&"interact")
	# Past the sword, onto the row that takes it off.
	await _press(&"move_down")
	await _press(&"interact")
	assert_str(String(GameState.equipped(&"weapon"))).override_failure_message(
		"the take-off row was pressed and the sword is still on").is_equal("")
	assert_int(GameState.item_count(&"bronze_sword")).override_failure_message(
		"taking gear off threw it away").is_equal(1)

func test_the_slot_list_names_what_is_worn_and_says_when_it_is_bare() -> void:
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	GameState.equip(&"weapon", &"bronze_sword")
	var worn := ""
	var bare := "unset"
	for row: PauseMenu.GearRow in world._gear_rows():
		if row.slot_id == &"weapon":
			worn = row.worn_name
		if row.slot_id == &"armor":
			bare = row.worn_name
	assert_str(worn).override_failure_message(
		"the weapon slot does not name the sword in it").is_equal("Bronze sword")
	assert_str(bare).override_failure_message(
		"the empty slot claims to hold something").is_equal("")

func test_the_readout_shows_the_gear_apart_from_the_level() -> void:
	# Two numbers rather than one total: a player deciding whether to buy a sword needs to see
	# what the sword is worth, not what they add up to.
	var world := _boot()
	assert_str(world._stats_label()).override_failure_message(
		"nothing worn should still read as nothing added").contains("Atk 5+0")
	GameState.give_item(&"bronze_sword", 1)
	GameState.equip(&"weapon", &"bronze_sword")
	assert_str(world._stats_label()).contains("Atk 5+3")

func test_what_you_are_wearing_is_not_on_the_sell_counter() -> void:
	# The classic shop bug: selling the sword off your own back. The refusal lives in the
	# world, because the counter has no business knowing what equipment is.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	GameState.give_gold(50)
	assert_bool(world.open_shop(&"smith_shop")).is_true()
	await _steps(2)
	var sellable: Array = world._sellable_rows()
	var names: Array[String] = []
	for row: ShopMenu.ShopRow in sellable:
		names.append(String(row.id))
	assert_array(names).override_failure_message(
		"a spare sword should be sellable before it is worn").contains([&"bronze_sword"])

	GameState.equip(&"weapon", &"bronze_sword")
	var after: Array[String] = []
	var rows_after: Array = world._sellable_rows()
	for row: ShopMenu.ShopRow in rows_after:
		after.append(String(row.id))
	assert_array(after).override_failure_message(
		"the sword the player is wearing was offered for sale").not_contains([&"bronze_sword"])

func test_a_spare_is_still_sellable_while_one_is_worn() -> void:
	# The near miss for the rule above. Refusing the whole STACK would be the easy wrong fix:
	# a player carrying two swords can sell one and keep wearing the other.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 2)
	GameState.equip(&"weapon", &"bronze_sword")
	assert_bool(world.open_shop(&"smith_shop")).is_true()
	await _steps(2)
	var spare := 0
	var rows_after: Array = world._sellable_rows()
	for row: ShopMenu.ShopRow in rows_after:
		if row.id == &"bronze_sword":
			spare = row.owned
	assert_int(spare).override_failure_message(
		"carrying two swords and wearing one should leave exactly one to sell").is_equal(1)

func test_worn_gear_reaches_the_fight() -> void:
	# The WIRE. The pure suite proves a modifier changes damage; this proves the world resolves
	# what is worn and passes it on, which is a different failure and needs its own test.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	GameState.give_item(&"leather_vest", 1)
	GameState.equip(&"weapon", &"bronze_sword")
	GameState.equip(&"armor", &"leather_vest")
	var foe := load("res://data/enemies/slink.tres") as EnemyDef
	assert_bool(world.open_battle_with(foe, "map/foe")).is_true()
	await _steps(2)
	var screen: BattleScreen = world.battle_screen()
	var logic: BattleLogic = screen.logic()
	assert_int(logic.attack_mod()).override_failure_message(
		"the sword was worn and the fight never heard about it").is_equal(3)
	assert_int(logic.defense_mod()).override_failure_message(
		"the vest was worn and the fight never heard about it").is_equal(2)

func test_a_fight_with_nothing_worn_gets_nothing() -> void:
	# The near miss: a wire that always passed 3 would pass the test above.
	var world := _boot()
	var foe := load("res://data/enemies/slink.tres") as EnemyDef
	assert_bool(world.open_battle_with(foe, "map/foe")).is_true()
	await _steps(2)
	var screen: BattleScreen = world.battle_screen()
	var logic: BattleLogic = screen.logic()
	assert_int(logic.attack_mod()).is_equal(0)
	assert_int(logic.defense_mod()).is_equal(0)

func test_the_slot_offers_to_take_off_what_is_in_it() -> void:
	# The line under the list is the only place the player learns what a press will DO, and a
	# take-off is the one row whose effect is a subtraction.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	var bare := ""
	for row: PauseMenu.GearRow in world._gear_rows():
		if row.slot_id == &"weapon":
			bare = row.takeoff_effect
	assert_str(bare).override_failure_message(
		"an empty slot offered to take something off: '%s'" % bare).is_empty()

	GameState.equip(&"weapon", &"bronze_sword")
	var offer := ""
	for row: PauseMenu.GearRow in world._gear_rows():
		if row.slot_id == &"weapon":
			offer = row.takeoff_effect
	assert_str(offer).contains("Take off")
	assert_str(offer).override_failure_message(
		"taking off a +3 sword did not read as losing 3: '%s'" % offer).contains("Atk -3")

func test_a_candidate_reads_as_the_swap_it_would_be() -> void:
	# The delta is against what the slot ALREADY holds, not against nothing. Wearing the sword
	# you are already wearing changes nothing, and the line has to say so - the M19 wording
	# promised "+3" a second time, which is a menu describing a fight the player cannot have.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	var fresh := ""
	for row: PauseMenu.ItemRow in world._item_rows():
		if row.id == &"bronze_sword":
			fresh = row.effect
	assert_str(fresh).contains("Atk +3")
	assert_str(fresh).override_failure_message(
		"the delta was shown with nothing to read it against: '%s'" % fresh).contains("now Atk +0")

	GameState.equip(&"weapon", &"bronze_sword")
	var again := ""
	for row: PauseMenu.ItemRow in world._item_rows():
		if row.id == &"bronze_sword":
			again = row.effect
	assert_str(again).override_failure_message(
		"wearing what is already worn promised its stats twice: '%s'" % again).contains("no change")
	assert_str(again).contains("now Atk +3")


func test_the_status_lines_carry_the_players_real_numbers() -> void:
	# Read from the same CombatDef the fight reads, so the page cannot say one thing while a
	# battle says another - the two-paths-one-answer trap.
	var world := _boot()
	var lines: Array[String] = world._status_lines()
	var joined := "\n".join(lines)
	assert_str(joined).override_failure_message(
		"the status page does not say what level the player is: %s" % [lines]).contains("Level 1")
	assert_str(joined).override_failure_message(
		"nothing says how hurt the player is: %s" % [lines]).contains("HP ")
	assert_str(joined).override_failure_message(
		"the line a player opens this page FOR is missing: %s" % [lines]).contains("next in")

func test_the_status_page_shows_what_is_worn() -> void:
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	GameState.equip(&"weapon", &"bronze_sword")
	var joined := "\n".join(world._status_lines())
	assert_str(joined).override_failure_message(
		"the status page does not name the gear: '%s'" % joined).contains("Weapon: Bronze sword")
	assert_str(joined).override_failure_message(
		"the gear's contribution is not shown apart from the level: '%s'" % joined) \
		.contains("Atk 5+3")
