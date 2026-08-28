extends GdUnitTestSuite
## What the player carries: the rules, the data files, and the gate that keeps them agreeing.
##
## Two rules here are the whole reason Inventory is a class rather than a Dictionary. A take
## that cannot be covered takes NOTHING - a partial consume would light a lantern on an empty
## flask and report success. And an item taken down to zero is forgotten rather than kept, so
## "carrying" and "have ever carried" cannot quietly become the same question.

const ITEM_DIR := "res://data/items"

func before_test() -> void:
	GameState.reset()

func after_test() -> void:
	GameState.reset()

func _known_item_ids() -> Dictionary:
	var out: Dictionary = {}
	for res in ContentScan.resources(ITEM_DIR):
		var item := res as ItemDef
		if item != null:
			out[item.id] = true
	return out

func test_adding_counts_up() -> void:
	var bag := Inventory.new()
	assert_bool(bag.add(&"coin")).is_true()
	assert_bool(bag.add(&"coin", 4)).is_true()
	assert_int(bag.count(&"coin")).is_equal(5)
	assert_bool(bag.has(&"coin", 5)).is_true()
	assert_bool(bag.has(&"coin", 6)).is_false()

func test_taking_more_than_is_carried_takes_nothing() -> void:
	# The rule that matters. A partial take reports success and leaves the player short.
	var bag := Inventory.new()
	bag.add(&"oil", 1)
	assert_bool(bag.remove(&"oil", 2)).override_failure_message(
		"a take that could not be covered reported success").is_false()
	assert_int(bag.count(&"oil")).override_failure_message(
		"a refused take still took something").is_equal(1)

func test_taking_the_last_one_forgets_the_item() -> void:
	var bag := Inventory.new()
	bag.add(&"oil", 1)
	assert_bool(bag.remove(&"oil")).is_true()
	assert_int(bag.count(&"oil")).is_equal(0)
	assert_array(bag.ids()).override_failure_message(
		"an item taken down to nothing is still listed as carried").is_empty()
	assert_bool(bag.is_empty()).is_true()

func test_items_are_listed_in_the_order_they_were_picked_up() -> void:
	# The item list draws in this order, so it is the order the player collected things in
	# rather than whatever the dictionary felt like.
	var bag := Inventory.new()
	bag.add(&"key")
	bag.add(&"oil")
	bag.add(&"key", 2)
	assert_array(bag.ids()).is_equal([&"key", &"oil"])

func test_giving_nothing_is_refused() -> void:
	var bag := Inventory.new()
	assert_bool(bag.add(&"coin", 0)).is_false()
	assert_bool(bag.add(&"coin", -3)).is_false()
	assert_bool(bag.add(&"", 1)).override_failure_message(
		"an item with no id was recorded, and can never be looked up again").is_false()
	assert_bool(bag.is_empty()).is_true()

func test_a_snapshot_round_trips_and_drops_what_add_would_refuse() -> void:
	# A save file is bytes on a disk that may have been edited. JSON has no integers either,
	# so every count arrives as a float and must survive the trip as one.
	var bag := Inventory.from_dict({"key": 1.0, "ghost": 0, "": 2, "oil": 3.0})
	assert_int(bag.count(&"key")).is_equal(1)
	assert_int(bag.count(&"oil")).is_equal(3)
	assert_bool(bag.ids().has(&"ghost")).override_failure_message(
		"an item with a count of zero was carried in from a file").is_false()
	assert_int(bag.ids().size()).is_equal(2)
	assert_dict(bag.to_dict()).is_equal({&"key": 1, &"oil": 3})

func test_a_copy_is_not_the_original() -> void:
	var bag := Inventory.new()
	bag.add(&"key")
	var other := bag.copy()
	other.add(&"key", 5)
	assert_int(bag.count(&"key")).is_equal(1)

func test_has_in_reads_a_snapshot_the_same_way() -> void:
	# Four layers ask "at least n" of a plain dictionary; they all ask through this.
	assert_bool(Inventory.has_in({&"key": 2}, &"key", 2)).is_true()
	assert_bool(Inventory.has_in({&"key": 2}, &"key", 3)).is_false()
	assert_bool(Inventory.has_in({}, &"key")).is_false()

func test_a_new_game_carries_nothing_over() -> void:
	GameState.give_item(&"gate_key")
	GameState.reset()
	assert_int(GameState.item_count(&"gate_key")).override_failure_message(
		"a new game starts holding the last one's items").is_equal(0)

func test_the_state_gives_and_takes_through_one_writer() -> void:
	assert_bool(GameState.give_item(&"lamp_oil")).is_true()
	assert_bool(GameState.has_item(&"lamp_oil")).is_true()
	assert_bool(GameState.take_item(&"lamp_oil", 2)).is_false()
	assert_bool(GameState.take_item(&"lamp_oil")).is_true()
	assert_bool(GameState.has_item(&"lamp_oil")).is_false()

func test_an_item_with_no_id_is_reported() -> void:
	var item := ItemDef.new()
	item.name = "Nameless"
	assert_str(", ".join(item.problems())).contains("id")

func test_an_item_with_no_name_is_reported() -> void:
	# It would draw as a blank row in the item list: the player sees they are carrying
	# something and cannot be told what.
	var item := ItemDef.new()
	item.id = &"mystery"
	assert_str(", ".join(item.problems())).contains("name")

func test_a_valid_item_has_no_problems() -> void:
	# The control: a validator that complained about everything would pass both tests above.
	var item := ItemDef.new()
	item.id = &"coin"
	item.name = "Coin"
	assert_array(item.problems()).is_empty()

func test_every_shipped_item_is_valid_and_named_after_its_file() -> void:
	var files := ContentScan.files_of(ITEM_DIR, "tres")
	assert_bool(files.is_empty()).override_failure_message(
		"no items ship, so every check below passes having read nothing").is_false()
	var seen: Dictionary = {}
	for path in files:
		var item := load(path) as ItemDef
		assert_object(item).override_failure_message("%s is not an ItemDef" % path).is_not_null()
		assert_array(item.problems()).override_failure_message(
			"%s: %s" % [path, item.problems()]).is_empty()
		# The file's name IS the id, so "which file is item X" needs no search.
		assert_str(String(item.id)).is_equal(path.get_file().get_basename())
		assert_bool(seen.has(item.id)).override_failure_message(
			"two files claim item '%s'" % item.id).is_false()
		seen[item.id] = true

func test_every_item_a_map_names_exists() -> void:
	# A misspelt item on a chest hands over nothing and on a door locks it forever. Both read
	# as level-design mistakes rather than as typos, which is why this is scanned, not listed.
	var known := _known_item_ids()
	for path in ContentScan.files_of("res://data/maps", "json"):
		var map := MapData.load_from(path)
		for item_id in map.item_refs():
			assert_bool(known.has(item_id)).override_failure_message(
				"map '%s' names item '%s', which no file in %s describes"
				% [map.id, item_id, ITEM_DIR]).is_true()

func test_every_item_a_conversation_names_exists() -> void:
	var known := _known_item_ids()
	for path in ContentScan.files_of("res://data/dialog", "json"):
		var runner := DialogRunner.load_from(path)
		for item_id in runner.item_refs():
			assert_bool(known.has(item_id)).override_failure_message(
				"dialog '%s' names item '%s', which no file in %s describes"
				% [runner.id, item_id, ITEM_DIR]).is_true()

func test_every_shop_a_conversation_names_exists() -> void:
	# The item_refs precedent: a misspelt shop id opens an empty counter, which reads as a
	# broken conversation rather than as a typo in a data file.
	var known: Array[StringName] = []
	for path in ContentScan.files_of("res://data/shops", "tres"):
		var shop := load(path) as ShopDef
		if shop != null:
			known.append(shop.id)
	for path in ContentScan.files_of("res://data/dialog", "json"):
		var runner := DialogRunner.load_from(path)
		for shop_id in runner.shop_refs():
			assert_bool(known.has(shop_id)).override_failure_message(
				"dialog '%s' names shop '%s', which no file in data/shops describes"
				% [runner.id, shop_id]).is_true()

func test_every_shipped_shop_is_valid_and_sells_only_priced_things() -> void:
	# A stocked item with no price is dropped by the counter rather than drawn at zero, so
	# without this the shop would simply come up short and nothing would say why.
	var found := 0
	for path in ContentScan.files_of("res://data/shops", "tres"):
		var shop := load(path) as ShopDef
		assert_object(shop).override_failure_message("%s is not a ShopDef" % path).is_not_null()
		assert_array(shop.problems()).override_failure_message(
			"shop '%s': %s" % [shop.id, shop.problems()]).is_empty()
		for item_id in shop.stock:
			var item := Registry.get_resource(&"ItemDef", item_id) as ItemDef
			assert_object(item).override_failure_message(
				"shop '%s' stocks '%s', which no item describes" % [shop.id, item_id]).is_not_null()
			assert_int(item.price).override_failure_message(
				"shop '%s' stocks '%s', which has no price - the counter would drop the row"
				% [shop.id, item_id]).is_greater(0)
		found += 1
	# A gate that scanned nothing reports the same green as a gate that scanned everything.
	assert_int(found).override_failure_message("no shops were scanned at all").is_greater(0)

func test_a_shop_that_stocks_the_same_thing_twice_is_refused() -> void:
	# A duplicate draws one row twice and makes the cursor lie about what it points at.
	var shop := ShopDef.new()
	shop.id = &"double"
	shop.stock = [&"tonic", &"tonic"]
	assert_str(str(shop.problems())).contains("twice")

func test_a_shop_with_nothing_to_sell_is_refused() -> void:
	var shop := ShopDef.new()
	shop.id = &"empty"
	assert_str(str(shop.problems())).contains("stocks nothing")

func test_an_unknown_slot_name_is_refused() -> void:
	# A typo'd slot must fail the build rather than quietly becoming a trinket that never
	# equips - the failure would otherwise be "why is my sword doing nothing", hours later.
	var item := ItemDef.new()
	item.id = &"wonky"
	item.name = "Wonky blade"
	item.slot = &"wepon"
	assert_str(str(item.problems())).contains("unknown slot")

func test_the_two_real_slots_are_accepted() -> void:
	# The near miss for the rule above: a rule that refused everything would pass the test
	# above and refuse the whole vocabulary.
	for slot in [&"weapon", &"armor"]:
		var item := ItemDef.new()
		item.id = &"fine"
		item.name = "Fine thing"
		item.slot = slot
		assert_array(item.problems()).override_failure_message(
			"slot '%s' was refused" % slot).is_empty()

func test_equipment_stats_without_a_slot_are_refused() -> void:
	# They would silently do nothing, which is the worst of both: authored, and inert.
	var item := ItemDef.new()
	item.id = &"odd"
	item.name = "Odd thing"
	item.attack = 3
	assert_str(str(item.problems())).contains("no slot")

func test_an_item_priced_below_zero_is_refused() -> void:
	var item := ItemDef.new()
	item.id = &"cursed"
	item.name = "Cursed thing"
	item.price = -1
	assert_str(str(item.problems())).contains("priced at -1")

func test_an_item_that_heals_a_negative_amount_is_refused() -> void:
	# A weapon wearing a potion's clothes. A game that wants one wants a different verb, not a
	# sign flip on this one - and battle_heal doubles as "does this belong in the fight menu",
	# so a negative value would put it there and then hurt the person who drank it.
	var item := ItemDef.new()
	item.id = &"bad_tonic"
	item.name = "Bad tonic"
	item.battle_heal = -5
	assert_array(item.problems()).is_not_empty()

func test_an_item_that_heals_nothing_is_still_a_valid_item() -> void:
	# The control, and the default every shipped item uses: zero means "not usable in a
	# fight", which is the ordinary case rather than a fault.
	var item := ItemDef.new()
	item.id = &"key"
	item.name = "Key"
	assert_int(item.battle_heal).is_equal(0)
	assert_array(item.problems()).is_empty()
