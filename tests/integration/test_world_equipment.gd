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

func test_a_press_on_a_sword_in_the_bag_puts_it_on() -> void:
	# Driven through the real menu rather than by calling equip(): the rule under test is that
	# a CONFIRM on that row reaches the slot map, and calling the writer directly would prove
	# the writer and nothing about the press.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	assert_bool(world.open_pause()).is_true()
	await _steps(2)
	var pause: PauseScreen = world.pause_screen()
	var rows: Array = world._item_rows()
	pause.refresh([], rows, "", "")
	await _steps(1)
	# Driven by real presses: down to Items, confirm to open the bag, confirm to wear.
	await _press(&"move_down")
	await _press(&"interact")
	await _press(&"interact")
	assert_str(String(GameState.equipped(&"weapon"))).override_failure_message(
		"a confirm on the sword row did not reach the slot map").is_equal("bronze_sword")
	# And it is still carried - equipping marks, it never moves.
	assert_int(GameState.item_count(&"bronze_sword")).is_equal(1)

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

func test_the_bag_offers_to_take_off_what_is_already_on() -> void:
	# The line under the list is the only place the player learns what a press will DO. Offering
	# to "wear" the sword already on your back is a menu lying about its own verb.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	var before: Array = world._item_rows()
	var offer := ""
	for row: PauseMenu.ItemRow in before:
		if row.id == &"bronze_sword":
			offer = row.effect
	assert_str(offer).override_failure_message(
		"an unworn sword did not offer to be worn: '%s'" % offer).contains("Wear")

	GameState.equip(&"weapon", &"bronze_sword")
	var after: Array = world._item_rows()
	var worn_offer := ""
	for row: PauseMenu.ItemRow in after:
		if row.id == &"bronze_sword":
			worn_offer = row.effect
	assert_str(worn_offer).override_failure_message(
		"a worn sword still offered to be worn: '%s'" % worn_offer).contains("Take off")

func test_the_delta_reads_against_what_is_already_worn() -> void:
	# "Atk +3" means little without "now +0" beside it - the compare is the point.
	var world := _boot()
	GameState.give_item(&"bronze_sword", 1)
	GameState.equip(&"weapon", &"bronze_sword")
	var rows: Array = world._item_rows()
	var line := ""
	for row: PauseMenu.ItemRow in rows:
		if row.id == &"bronze_sword":
			line = row.effect
	assert_str(line).contains("Atk +3")
	assert_str(line).override_failure_message(
		"the delta was shown with nothing to read it against: '%s'" % line).contains("now Atk +3")

