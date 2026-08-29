extends GdUnitTestSuite
## Saves, migrations, and what happens to a file that will not parse.
##
## The last one is the reason this suite exists. A player's save file IS their progress, so a
## loader that quietly falls back to a fresh game - and then lets the next autosave write over
## the bad bytes - has destroyed the progress AND the only evidence of what went wrong. The
## bytes are parked first, and the failure is reported.
##
## Slots are per game, so every call names one. The pair that matters is a file whose OWN game
## disagrees with the directory it sits in: that is a save copied, moved or hand-edited into
## the wrong place, and loading it would present as the game you meant to play being broken.

const TEST_DIR := "user://test_saves"
const FIXTURES := "res://tests/fixtures/saves/"

func before_test() -> void:
	GameState.reset()
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)

func after_test() -> void:
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.DEFAULT_DIR
	GameState.reset()

## A save belonging to whichever game, built without going through GameState - the suite needs
## to write files that the live state could not produce.
func _save_for(game: StringName, map: StringName) -> SaveData:
	var data := SaveData.new()
	data.game = game
	data.map = map
	data.position = Vector2(16.0, 32.0)
	data.facing = Dir.D.DOWN
	return data

func test_a_save_round_trips_through_disk() -> void:
	GameState.new_game(&"quest", &"quest_village", Vector2(120.5, 88.25), Dir.D.LEFT)
	GameState.set_flag(&"promised_elder", true)
	GameState.mark_seen(&"intro")
	GameState.give_item(&"gate_key")
	GameState.give_item(&"lamp_oil", 2)
	GameState.set_party(13, 22, 3, 7)
	GameState.play_seconds = 42.5

	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	GameState.reset()
	var loaded := SaveManager.load_slot(&"quest", 0)
	assert_object(loaded).is_not_null()
	GameState.from_save(loaded)

	assert_str(String(GameState.game)).is_equal("quest")
	assert_str(String(GameState.current_map)).is_equal("quest_village")
	assert_vector(GameState.player_position).is_equal(Vector2(120.5, 88.25))
	assert_int(GameState.player_facing).is_equal(Dir.D.LEFT)
	assert_bool(GameState.has_flag(&"promised_elder")).is_true()
	assert_bool(GameState.was_seen(&"intro")).is_true()
	assert_float(GameState.play_seconds).is_equal_approx(42.5, 0.001)
	# What the player carries survives with its COUNTS: an inventory that round-tripped as a
	# set of booleans would reload two flasks of oil as one.
	assert_int(GameState.item_count(&"gate_key")).is_equal(1)
	assert_int(GameState.item_count(&"lamp_oil")).is_equal(2)
	# And what the player is worth in a fight. A save that forgot this reloads a level-3
	# player as a fresh one, which reads as lost progress rather than as a save bug.
	assert_int(GameState.player_hp).is_equal(13)
	assert_int(GameState.player_xp).is_equal(22)
	assert_int(GameState.player_level).is_equal(3)
	# Magic rides inside the party dict, so a save that dropped it would reload a caster with
	# nothing to cast - and the player would blame the spell, not the file.
	assert_int(GameState.player_mp).is_equal(7)

func test_a_game_that_never_fought_saves_no_party() -> void:
	# Zero health means UNSET, and that has to survive the round trip as absence rather than as
	# a party at nought hp - which the file format refuses outright.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	var data := GameState.to_save()
	assert_dict(data.party).is_empty()
	assert_array(data.problems()).is_empty()

func test_a_new_game_does_not_inherit_the_last_one_s_level() -> void:
	# An autoload outlives a session. Without the reset, starting over hands the new player
	# every level the old one earned - which reads as a save bug rather than as a missing line.
	GameState.set_party(31, 99, 3, 12)
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	assert_int(GameState.player_level).is_equal(1)
	assert_int(GameState.player_xp).is_equal(0)
	assert_int(GameState.player_hp).is_equal(0)
	assert_int(GameState.player_mp).is_equal(0)

func test_loading_a_save_from_before_battles_leaves_the_party_unset() -> void:
	# The signal world_scene reads to derive a fresh player from the game's curve. If this
	# came back as "level 1 at zero hp" instead, that derivation would never fire and the
	# first fight would open with a player who is already dead.
	GameState.set_party(9, 4, 2, 5)
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_village"
	GameState.from_save(data)
	assert_int(GameState.player_hp).is_equal(0)
	assert_int(GameState.player_level).is_equal(1)

func test_a_save_is_filed_under_its_game() -> void:
	# The game comes from the SAVE, not from an argument: one source for the fact means a file
	# and its directory cannot be made to disagree by a caller passing the wrong thing.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	assert_bool(FileAccess.file_exists(SaveManager.slot_path(&"quest", 0))).is_true()
	assert_bool(SaveManager.has_slot(&"other", 0)).override_failure_message(
		"one game's save answered another game's slot").is_false()
	var written := JsonFile.read(SaveManager.slot_path(&"quest", 0))
	assert_str(str(written.data.get("game", ""))).is_equal("quest")

func test_a_save_that_names_no_game_is_refused() -> void:
	# Nowhere to put it, and nothing to check it against later. Writing it anyway would create
	# the one file that can never be validated.
	var data := _save_for(&"", &"quest_village")
	assert_str(", ".join(data.problems())).contains("game")
	assert_bool(SaveManager.save(0, data)).is_false()
	assert_bool(SaveManager.has_slot(&"", 0)).is_false()

func test_a_save_from_another_game_is_refused_and_preserved() -> void:
	# The failure this whole layout exists to catch. The bytes are a real save belonging to
	# another game; they are sitting in this one's first slot, which is what a file copied,
	# moved or hand-edited into the wrong directory looks like.
	var stranger := _save_for(&"other", &"other_hall")
	assert_bool(SaveManager.save(0, stranger)).is_true()
	var bytes := FileAccess.get_file_as_string(SaveManager.slot_path(&"other", 0))
	SaveDirs.write_raw(&"quest", 0, bytes)

	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	assert_object(SaveManager.load_slot(&"quest", 0)).override_failure_message(
		"a save from another game loaded into this one").is_null()
	EventBus.save_changed.disconnect(handler)

	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 0))).override_failure_message(
		"the misfiled save was discarded instead of preserved").is_true()
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_false()
	assert_str(String(seen[0]["game"])).is_equal("quest")

func test_the_same_save_loads_under_its_own_game() -> void:
	# The control. Without it, a loader that refused everything would pass the test above.
	assert_bool(SaveManager.save(0, _save_for(&"other", &"other_hall"))).is_true()
	var loaded := SaveManager.load_slot(&"other", 0)
	assert_object(loaded).is_not_null()
	assert_str(String(loaded.map)).is_equal("other_hall")

func test_peeking_at_a_slot_is_silent() -> void:
	# A menu draws its rows by reading every slot. If that read parked files and announced
	# loads, merely LOOKING at the pause screen would produce .corrupt files nobody asked for.
	SaveDirs.write_raw(&"quest", 0, "{ not json at all ")
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	assert_object(SaveManager.peek(&"quest", 0)).is_null()
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).override_failure_message("peeking announced a load").is_equal(0)
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 0))).override_failure_message(
		"peeking parked a file").is_false()

func test_peeking_reads_a_real_save() -> void:
	# The control for the silence above: a peek that returned null for everything would be
	# equally quiet and completely useless.
	SaveManager.save(1, _save_for(&"quest", &"quest_village"))
	var seen := SaveManager.peek(&"quest", 1)
	assert_object(seen).is_not_null()
	assert_str(String(seen.map)).is_equal("quest_village")

func test_saving_over_unreadable_bytes_parks_them_first() -> void:
	# The menu offers Load only for slots that read back, so an unreadable slot looks EMPTY -
	# which makes saving into it the one path that could destroy a damaged file silently.
	SaveDirs.write_raw(&"quest", 0, "{ ruined ")
	assert_bool(SaveManager.save(0, _save_for(&"quest", &"quest_village"))).is_true()
	assert_str(FileAccess.get_file_as_string(SaveManager.corrupt_path(&"quest", 0))).override_failure_message(
		"the unreadable bytes were overwritten instead of parked").is_equal("{ ruined ")
	assert_object(SaveManager.load_slot(&"quest", 0)).is_not_null()

func test_a_fractional_position_is_not_truncated() -> void:
	# Reading a position through an int conversion loses the fraction silently, and the
	# player reloads a few pixels from where they stood.
	GameState.new_game(&"quest", &"quest_village", Vector2(120.8, 136.4), Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	var loaded := SaveManager.load_slot(&"quest", 0)
	assert_float(loaded.position.x).is_equal_approx(120.8, 0.001)
	assert_float(loaded.position.y).is_equal_approx(136.4, 0.001)

func test_an_empty_slot_loads_as_nothing_rather_than_as_a_blank_game() -> void:
	# Returning a default SaveData would make "no save here" indistinguishable from "a save
	# of a game that has not started", and the menu would offer to continue nothing.
	assert_object(SaveManager.load_slot(&"quest", 3)).is_null()
	assert_bool(SaveManager.has_slot(&"quest", 3)).is_false()

func test_a_corrupt_save_is_preserved_before_anything_else_happens() -> void:
	# The whole point. The bytes must survive the failure.
	SaveDirs.write_raw(&"quest", 0, "{ this is not json ")
	assert_object(SaveManager.load_slot(&"quest", 0)).is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 0))).override_failure_message(
		"the unreadable save was discarded instead of preserved").is_true()
	assert_str(FileAccess.get_file_as_string(SaveManager.corrupt_path(&"quest", 0))).is_equal("{ this is not json ")

func test_a_structurally_wrong_save_is_also_preserved() -> void:
	# Readable JSON, impossible contents. "The save loaded and the player was nowhere" is a
	# bug report that needs the original file just as much as a parse failure does. Written at
	# the current version with the right game, so the faults under test are the only ones.
	SaveDirs.write_raw(&"quest", 0, '{"version": 4, "game": "quest", "map": "", "facing": 99}')
	assert_object(SaveManager.load_slot(&"quest", 0)).is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 0))).is_true()

func test_a_valid_save_leaves_no_corrupt_file_behind() -> void:
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	assert_object(SaveManager.load_slot(&"quest", 0)).is_not_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 0))).is_false()

func test_a_version_1_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v1.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	assert_int(int(migrated["version"])).is_equal(SaveData.VERSION)
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	# The v1 shape carried no play time. It gets zero rather than a guess: a fabricated value
	# would be indistinguishable from a real one later.
	assert_float(data.play_seconds).is_equal(0.0)
	# And nor did it carry a game - it comes from the slot the file was found in.
	assert_str(String(data.game)).is_equal("quest")
	# Everything v1 DID carry survives intact.
	assert_str(String(data.map)).is_equal("quest_town")
	assert_int(data.facing).is_equal(Dir.D.RIGHT)
	assert_bool(bool(data.flags.get("promised_elder", false))).is_true()

func test_a_version_2_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v2.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	assert_str(String(data.game)).override_failure_message(
		"the migrated save did not adopt the game whose slot it was in").is_equal("quest")
	# v2 already counted play time, so this one is carried rather than zeroed.
	assert_float(data.play_seconds).is_equal_approx(42.5, 0.001)
	assert_str(String(data.map)).is_equal("quest_village")
	assert_int(data.facing).is_equal(Dir.D.LEFT)

func test_a_version_1_save_loads_through_the_manager() -> void:
	SaveDirs.write_raw(&"quest", 0, FileAccess.get_file_as_string(FIXTURES + "v1.json"))
	var loaded := SaveManager.load_slot(&"quest", 0)
	assert_object(loaded).override_failure_message("a v1 save was rejected instead of migrated").is_not_null()
	assert_int(loaded.version).is_equal(SaveData.VERSION)
	assert_str(String(loaded.game)).is_equal("quest")

func test_a_save_with_no_version_is_treated_as_the_oldest_shape() -> void:
	# A file predating versioning must walk the whole chain. Treating it as current would skip
	# every step and read old fields as new ones.
	var migrated := Migrations.apply({"map": "quest_village", "facing": 0}, &"quest")
	assert_int(int(migrated["version"])).is_equal(SaveData.VERSION)
	assert_bool(migrated.has("play_seconds")).is_true()
	assert_bool(migrated.has("game")).is_true()

func test_the_migration_chain_runs_every_step_not_just_one() -> void:
	# The `while` rather than `if`. With an `if`, a save two versions behind is migrated one
	# step and handed to a system that will not recognise it - and the failure shows up as
	# odd values rather than as an error.
	for from_version in Migrations.supported_versions():
		var migrated := Migrations.apply({"version": from_version, "map": "quest_village", "facing": 0}, &"quest")
		assert_int(int(migrated["version"])).override_failure_message(
			"a v%d save did not reach v%d" % [from_version, SaveData.VERSION]) \
			.is_equal(SaveData.VERSION)

func test_migrating_does_not_mutate_the_file_it_was_given() -> void:
	var original := {"version": 1, "map": "quest_village", "facing": 0}
	Migrations.apply(original, &"quest")
	assert_bool(original.has("play_seconds")).override_failure_message(
		"apply() edited its input; the caller's copy of the file is no longer what was read").is_false()
	assert_bool(original.has("game")).is_false()
	assert_int(int(original["version"])).is_equal(1)

func test_a_save_from_a_future_version_is_refused_rather_than_guessed_at() -> void:
	# Forwards compatibility is not free, and pretending to have it loses data. A save from a
	# newer build is reported, not silently read with fields this build does not understand.
	SaveDirs.write_raw(&"quest", 0, '{"version": 99, "game": "quest", "map": "quest_village", "facing": 0}')
	assert_object(SaveManager.load_slot(&"quest", 0)).is_null()

func test_deleting_a_slot_removes_it() -> void:
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	assert_bool(SaveManager.has_slot(&"quest", 0)).is_true()
	SaveManager.delete_slot(&"quest", 0)
	assert_bool(SaveManager.has_slot(&"quest", 0)).is_false()

func test_saving_announces_itself() -> void:
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_true()
	assert_str(String(seen[0]["game"])).is_equal("quest")

func test_a_failed_load_announces_itself_too() -> void:
	# A resilient path that says nothing is how a broken save survives to release.
	SaveDirs.write_raw(&"quest", 0, "not json")
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	SaveManager.load_slot(&"quest", 0)
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_false()

func test_a_scripted_session_gets_its_own_save_directory() -> void:
	# A play script that read the real directory would pass or fail depending on who ran it,
	# and one that wrote to it would overwrite a player's progress on the same machine.
	assert_str(SaveManager.dir_for(PackedStringArray(["--qa-script=res://x.json", "--game=quest"]))) \
		.is_equal(SaveManager.QA_DIR)
	assert_str(SaveManager.dir_for(PackedStringArray(["--game=quest"]))).is_equal(SaveManager.DEFAULT_DIR)
	assert_str(SaveManager.dir_for(PackedStringArray([]))).is_equal(SaveManager.DEFAULT_DIR)


func test_a_version_3_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v3.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	assert_bool(migrated.has("items")).override_failure_message(
		"a migrated save arrived with no inventory field at all").is_true()
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	# An empty bag rather than a guess: inventing an item the player never found would open a
	# door the game meant to make them earn.
	assert_dict(data.items).is_empty()
	assert_str(String(data.game)).is_equal("quest")
	assert_str(String(data.map)).is_equal("quest_keep")
	assert_bool(bool(data.flags.get("has_gate_key", false))).is_true()

func test_a_version_4_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v4.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	assert_bool(migrated.has("party")).override_failure_message(
		"a migrated save arrived with no party field at all").is_true()
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	# An empty party rather than a guess: this step cannot see the game's CombatDef, so it does
	# not know what full health is - world_scene derives that at the one place that can.
	assert_dict(data.party).is_empty()
	# And the step must not drop what v4 already knew. The fixture carries a bag on purpose:
	# with an empty one, a migration that wiped the inventory would pass this test.
	assert_int(int(data.items.get("gate_key", 0))).override_failure_message(
		"the v4->v5 step lost the bag it was handed").is_equal(1)
	assert_str(String(data.map)).is_equal("quest_keep")
	assert_bool(bool(data.seen.get("quest_hollow/keystash", false))).is_true()

func test_a_version_5_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v5.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	assert_bool(migrated.has("gold")).override_failure_message(
		"a migrated save arrived with no gold field at all").is_true()
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	# Broke rather than a gift, the same call every step above makes: handing an old save
	# enough to buy what the game meant it to fight for is the lie this avoids.
	assert_int(data.gold).is_equal(0)
	# And the step must not drop what v5 already knew - the fixture carries both a bag and a
	# party on purpose, because with either missing a step that wiped it would still pass.
	assert_int(int(data.items.get("tonic", 0))).override_failure_message(
		"the v5->v6 step lost the bag it was handed").is_equal(2)
	assert_int(int(data.party.get("level", 0))).override_failure_message(
		"the v5->v6 step lost the party it was handed").is_equal(3)

func test_a_version_6_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v6.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	assert_bool(migrated.has("equipment")).override_failure_message(
		"a migrated save arrived with no equipment field at all").is_true()
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	# Nothing worn rather than a gift, the call every step before it made.
	assert_dict(data.equipment).is_empty()
	# And the step must not drop what v6 already knew - the fixture carries a bag, a party
	# and a purse on purpose, because with any of them missing a step that wiped it would pass.
	assert_int(int(data.items.get("tonic", 0))).override_failure_message(
		"the v6->v7 step lost the bag it was handed").is_equal(2)
	assert_int(int(data.party.get("level", 0))).override_failure_message(
		"the v6->v7 step lost the party it was handed").is_equal(3)
	assert_int(data.gold).override_failure_message(
		"the v6->v7 step lost the purse it was handed").is_equal(41)

func test_a_version_7_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v7.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	var party: Dictionary = migrated.get("party", {})
	assert_bool(party.has("mp")).override_failure_message(
		"a migrated save arrived with no mp at all").is_true()
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	# Spent rather than a gift, the call every step before it made - and here there is a second
	# reason: what "full" is depends on the game's CombatDef, which a migration may not reach.
	assert_int(int(data.party.get("mp", -1))).is_equal(0)
	# And the step must not drop what v7 already knew - the fixture carries a bag, a party, a
	# purse and worn gear on purpose, because with any of them missing a step that wiped it
	# would still pass.
	assert_int(int(data.items.get("tonic", 0))).override_failure_message(
		"the v7->v8 step lost the bag it was handed").is_equal(2)
	assert_int(int(data.party.get("level", 0))).override_failure_message(
		"the v7->v8 step lost the party it was handed").is_equal(3)
	assert_int(data.gold).override_failure_message(
		"the v7->v8 step lost the purse it was handed").is_equal(41)
	assert_str(str(data.equipment.get("weapon", ""))).override_failure_message(
		"the v7->v8 step lost the gear it was handed").is_equal("bronze_sword")

func test_a_version_8_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v8.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"quest")
	assert_bool(migrated.has("companions")).override_failure_message(
		"a migrated save arrived with no companions key at all").is_true()
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	assert_int(data.version).is_equal(SaveData.VERSION)
	# Nobody had joined before v9, and a migration may not reach a roster to ask - so empty is
	# the whole truth rather than a default standing in for one.
	assert_dict(data.companions).override_failure_message(
		"the v8->v9 step invented a companion for a save that predates parties").is_empty()
	# And the step must not drop what v8 already knew - the fixture carries a bag, a party with
	# magic, a purse and worn gear on purpose, because with any of them missing a step that
	# wiped it would still pass.
	assert_int(int(data.items.get("tonic", 0))).override_failure_message(
		"the v8->v9 step lost the bag it was handed").is_equal(2)
	assert_int(int(data.party.get("level", 0))).override_failure_message(
		"the v8->v9 step lost the party it was handed").is_equal(3)
	assert_int(int(data.party.get("mp", -1))).override_failure_message(
		"the v8->v9 step lost the magic it was handed").is_equal(5)
	assert_int(data.gold).override_failure_message(
		"the v8->v9 step lost the purse it was handed").is_equal(41)
	assert_str(str(data.equipment.get("weapon", ""))).override_failure_message(
		"the v8->v9 step lost the gear it was handed").is_equal("bronze_sword")

func test_a_companion_survives_a_save_and_a_load() -> void:
	# The round trip the milestone rests on: a companion's four numbers and their gear go out
	# through to_save and come back through from_save as the same person.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.set_party(20, 0, 1, 8)
	GameState.give_item(&"bronze_sword")
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(GameState.equip(&"weapon", &"bronze_sword", &"scrapper")).is_true()
	var reloaded := SaveData.from_dict(GameState.to_save().to_dict())
	assert_array(reloaded.problems()).is_empty()
	GameState.reset()
	GameState.from_save(reloaded)
	var back := GameState.companion(&"scrapper")
	assert_int(int(back.get("hp", 0))).is_equal(11)
	assert_int(int(back.get("xp", 0))).is_equal(14)
	assert_int(int(back.get("level", 0))).is_equal(2)
	assert_int(int(back.get("mp", -1))).override_failure_message(
		"a companion came back from the save with different magic").is_equal(3)
	assert_str(str(GameState.equipped(&"weapon", &"scrapper"))).override_failure_message(
		"a companion came back from the save wearing nothing").is_equal("bronze_sword")

func test_a_save_with_no_companions_writes_none() -> void:
	# The control, and the shape every game without a party writes forever: the key is there
	# and it is empty, rather than absent or full of a leader nobody asked to duplicate.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.set_party(20, 0, 1, 8)
	assert_dict(GameState.to_save().companions).override_failure_message(
		"a solo game wrote a companion into its save").is_empty()

func test_a_fallen_leader_beside_a_companion_is_a_save_the_game_can_write() -> void:
	# The state M27 makes possible and M26 could not: the leader fell, somebody else finished
	# the fight, and the party is walking to an inn. Read as "unset" this would be refused by
	# problems() and refilled from the curve on the way into the next fight - a silent
	# resurrection that deletes the consequence the player is walking to town to undo.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.set_party(0, 30, 2, 4)
	GameState.set_companion(&"scrapper", 6, 30, 2, 1)
	var written := GameState.to_save()
	assert_dict(written.party).override_failure_message(
		"a leader who fell beside a companion was written down as having never fought").is_not_empty()
	assert_array(written.problems()).override_failure_message(
		"a save the game itself just produced was refused").is_empty()

func test_a_fallen_leader_alone_is_still_an_unset_party() -> void:
	# The other half, and the reason party_unset is not simply "hp is zero": with nobody else
	# standing, a fight that reached zero health was a DEFEAT, whose effects are discarded
	# wholesale - so zero here still means "never fought" and must still write no party at all.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.set_party(0, 0, 1, 0)
	assert_dict(GameState.to_save().party).override_failure_message(
		"a solo game with nobody set up wrote a party of nought health").is_empty()

func test_a_save_with_a_companion_and_no_party_is_refused() -> void:
	var data := SaveData.from_dict({
		"version": SaveData.VERSION, "game": "quest", "map": "quest_village", "facing": 0,
		"party": {}, "companions": {"scrapper": {"hp": 6, "xp": 0, "level": 1, "mp": 0}},
	})
	assert_array(data.problems()).override_failure_message(
		"a file describing somebody who joined a player who does not exist was accepted").is_not_empty()

func test_a_save_where_two_people_wear_one_carried_sword_is_refused() -> void:
	# One copy, one back - checked against the FILE, because a hand-edited save can describe a
	# party that no sequence of presses could produce.
	var data := SaveData.from_dict({
		"version": SaveData.VERSION, "game": "quest", "map": "quest_village", "facing": 0,
		"items": {"bronze_sword": 1},
		"party": {"hp": 20, "xp": 0, "level": 1, "mp": 0},
		"equipment": {"weapon": "bronze_sword"},
		"companions": {"scrapper": {"hp": 6, "xp": 0, "level": 1, "mp": 0,
			"equipment": {"weapon": "bronze_sword"}}},
	})
	assert_array(data.problems()).override_failure_message(
		"a file with two people wearing one carried sword was accepted").is_not_empty()

func test_two_people_wearing_two_carried_swords_is_fine() -> void:
	# The control the check above needs: the refusal must be about the COUNT, not about two
	# people owning the same kind of thing.
	var data := SaveData.from_dict({
		"version": SaveData.VERSION, "game": "quest", "map": "quest_village", "facing": 0,
		"items": {"bronze_sword": 2},
		"party": {"hp": 20, "xp": 0, "level": 1, "mp": 0},
		"equipment": {"weapon": "bronze_sword"},
		"companions": {"scrapper": {"hp": 6, "xp": 0, "level": 1, "mp": 0,
			"equipment": {"weapon": "bronze_sword"}}},
	})
	assert_array(data.problems()).override_failure_message(
		"two carried swords on two backs was refused").is_empty()

func test_a_save_with_no_party_gains_no_magic() -> void:
	# The pairing to_save() makes: a file with no party is a game with no fighting in it, and
	# handing that an mp key would be the one field claiming it has a fighter after all.
	var migrated := Migrations.apply({
		"version": 7, "game": "quest", "map": "quest_village", "facing": 0, "party": {},
	}, &"quest")
	assert_dict(migrated.get("party", {})).override_failure_message(
		"a game with no party was given magic by the migration").is_empty()

func test_a_save_carrying_negative_magic_is_reported() -> void:
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_village"
	data.party = {"hp": 10, "xp": 0, "level": 1, "mp": -1}
	assert_array(data.problems()).is_not_empty()

func test_a_party_that_has_spent_every_point_is_allowed() -> void:
	# The control that keeps the mp check from being written as "must be positive" the way the
	# hp one is. Zero mp is an ordinary state; zero hp is a player who cannot exist.
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_village"
	data.party = {"hp": 10, "xp": 0, "level": 1, "mp": 0}
	assert_array(data.problems()).is_empty()

func test_equipment_survives_a_round_trip() -> void:
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.give_item(&"tonic", 1)
	assert_bool(GameState.equip(&"weapon", &"tonic")).is_true()
	var reloaded := SaveData.from_dict(GameState.to_save().to_dict())
	assert_array(reloaded.problems()).is_empty()
	GameState.reset()
	GameState.from_save(reloaded)
	assert_str(String(GameState.equipped(&"weapon"))).is_equal("tonic")

func test_a_save_that_equips_what_it_does_not_carry_is_reported() -> void:
	# The file checked against ITSELF. A hand-edited save describing a player wearing a sword
	# they do not own would arm a phantom on load, and nothing downstream could tell.
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_keep"
	data.equipment = {"weapon": "bronze_sword"}
	assert_str(str(data.problems())).contains("carries none")

func test_gold_survives_a_round_trip() -> void:
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	assert_bool(GameState.give_gold(30)).is_true()
	var reloaded := SaveData.from_dict(GameState.to_save().to_dict())
	assert_array(reloaded.problems()).is_empty()
	GameState.reset()
	GameState.from_save(reloaded)
	assert_int(GameState.gold).is_equal(30)

func test_you_cannot_equip_what_you_are_not_carrying() -> void:
	# A slot map pointing at a phantom is the dangling reference every other rule here exists
	# to prevent.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	assert_bool(GameState.equip(&"weapon", &"tonic")).override_failure_message(
		"the player equipped something they do not have").is_false()
	assert_str(String(GameState.equipped(&"weapon"))).is_empty()

func test_equipping_into_a_full_slot_swaps() -> void:
	# The item never left the bag, so there is nothing to put back - the DQ model.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.give_item(&"tonic", 1)
	GameState.give_item(&"waybread", 1)
	GameState.equip(&"weapon", &"tonic")
	GameState.equip(&"weapon", &"waybread")
	assert_str(String(GameState.equipped(&"weapon"))).is_equal("waybread")
	assert_int(GameState.item_count(&"tonic")).override_failure_message(
		"swapping gear consumed the item that came off").is_equal(1)

func test_losing_the_last_copy_takes_the_marker_with_it() -> void:
	# By a sale, a dialog take, anything: without this the slot map points at an item the
	# player no longer has, and the phantom re-arms the moment they pick another one up.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.give_item(&"tonic", 2)
	GameState.equip(&"weapon", &"tonic")
	GameState.take_item(&"tonic", 1)
	assert_str(String(GameState.equipped(&"weapon"))).override_failure_message(
		"selling a spare unequipped the one still carried").is_equal("tonic")
	GameState.take_item(&"tonic", 1)
	assert_str(String(GameState.equipped(&"weapon"))).override_failure_message(
		"the last copy left the bag and stayed equipped").is_empty()

func test_a_purse_cannot_go_negative() -> void:
	# Refused, never clamped: clamping turns "could not afford it" into "bought it and has
	# nothing", which is a different game.
	GameState.new_game(&"quest", &"quest_village", Vector2.ZERO, Dir.D.DOWN)
	GameState.give_gold(10)
	assert_bool(GameState.spend_gold(11)).override_failure_message(
		"a spend beyond the purse was allowed").is_false()
	assert_int(GameState.gold).is_equal(10)
	assert_bool(GameState.spend_gold(10)).is_true()
	assert_int(GameState.gold).is_equal(0)
	# Nonsense amounts change nothing rather than subtracting.
	assert_bool(GameState.give_gold(0)).is_false()
	assert_bool(GameState.spend_gold(-5)).is_false()
	assert_int(GameState.gold).is_equal(0)

func test_a_negative_purse_in_a_file_is_reported() -> void:
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_keep"
	data.gold = -1
	assert_str(str(data.problems())).contains("carries -1 gold")

func test_a_party_survives_a_round_trip() -> void:
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_keep"
	data.party = {"hp": 14, "xp": 22, "level": 3}
	assert_array(data.problems()).is_empty()
	var back := SaveData.from_dict(data.to_dict())
	assert_int(int(back.party.get("hp", 0))).is_equal(14)
	assert_int(int(back.party.get("xp", 0))).is_equal(22)
	assert_int(int(back.party.get("level", 0))).is_equal(3)

func test_a_save_carrying_a_dead_player_is_refused() -> void:
	# Zero health is what "unset" is spelled as in GameState, so a file that states it as a
	# real party is a file that has been edited or written by a broken build.
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_keep"
	data.party = {"hp": 0, "xp": 5, "level": 1}
	assert_array(data.problems()).is_not_empty()

func test_a_save_with_no_party_at_all_is_accepted() -> void:
	# The control for the refusal above, and the common case: a game with no combat, or a save
	# written before battles existed. Absent must stay legal forever.
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_keep"
	assert_array(data.problems()).is_empty()


func test_a_save_carrying_none_of_something_is_refused_and_preserved() -> void:
	# A file edited by hand, or written by a broken build. "Minus one key" is not a state the
	# game can be in, so it is parked like any other unreadable save rather than tidied away.
	SaveDirs.write_raw(&"quest", 0, '{"version": 4, "game": "quest", "map": "quest_village",'
		+ ' "facing": 0, "items": {"gate_key": 0}}')
	assert_object(SaveManager.load_slot(&"quest", 0)).override_failure_message(
		"a save carrying zero of an item was accepted").is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 0))).is_true()


func test_a_save_carrying_a_real_count_loads() -> void:
	# The control: a validator that refused every inventory would pass the test above.
	SaveDirs.write_raw(&"quest", 1, '{"version": 4, "game": "quest", "map": "quest_village",'
		+ ' "facing": 0, "items": {"gate_key": 2}}')
	var loaded := SaveManager.load_slot(&"quest", 1)
	assert_object(loaded).is_not_null()
	assert_int(int(loaded.items["gate_key"])).is_equal(2)

