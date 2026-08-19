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
	GameState.new_game(&"demo", &"demo_town", Vector2(120.5, 88.25), Dir.D.LEFT)
	GameState.set_flag(&"promised_elder", true)
	GameState.mark_seen(&"intro")
	GameState.play_seconds = 42.5

	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	GameState.reset()
	var loaded := SaveManager.load_slot(&"demo", 0)
	assert_object(loaded).is_not_null()
	GameState.from_save(loaded)

	assert_str(String(GameState.game)).is_equal("demo")
	assert_str(String(GameState.current_map)).is_equal("demo_town")
	assert_vector(GameState.player_position).is_equal(Vector2(120.5, 88.25))
	assert_int(GameState.player_facing).is_equal(Dir.D.LEFT)
	assert_bool(GameState.has_flag(&"promised_elder")).is_true()
	assert_bool(GameState.was_seen(&"intro")).is_true()
	assert_float(GameState.play_seconds).is_equal_approx(42.5, 0.001)

func test_a_save_is_filed_under_its_game() -> void:
	# The game comes from the SAVE, not from an argument: one source for the fact means a file
	# and its directory cannot be made to disagree by a caller passing the wrong thing.
	GameState.new_game(&"demo", &"demo_town", Vector2.ZERO, Dir.D.DOWN)
	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	assert_bool(FileAccess.file_exists(SaveManager.slot_path(&"demo", 0))).is_true()
	assert_bool(SaveManager.has_slot(&"quest", 0)).override_failure_message(
		"one game's save answered another game's slot").is_false()
	var written := JsonFile.read(SaveManager.slot_path(&"demo", 0))
	assert_str(str(written.data.get("game", ""))).is_equal("demo")

func test_a_save_that_names_no_game_is_refused() -> void:
	# Nowhere to put it, and nothing to check it against later. Writing it anyway would create
	# the one file that can never be validated.
	var data := _save_for(&"", &"demo_town")
	assert_str(", ".join(data.problems())).contains("game")
	assert_bool(SaveManager.save(0, data)).is_false()
	assert_bool(SaveManager.has_slot(&"", 0)).is_false()

func test_a_save_from_another_game_is_refused_and_preserved() -> void:
	# The failure this whole layout exists to catch. The bytes are a real quest save; they are
	# sitting in the demo's first slot, which is what a copied or hand-edited file looks like.
	var quest := _save_for(&"quest", &"quest_village")
	assert_bool(SaveManager.save(0, quest)).is_true()
	var bytes := FileAccess.get_file_as_string(SaveManager.slot_path(&"quest", 0))
	SaveDirs.write_raw(&"demo", 0, bytes)

	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	assert_object(SaveManager.load_slot(&"demo", 0)).override_failure_message(
		"a save from another game loaded into this one").is_null()
	EventBus.save_changed.disconnect(handler)

	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"demo", 0))).override_failure_message(
		"the misfiled save was discarded instead of preserved").is_true()
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_false()
	assert_str(String(seen[0]["game"])).is_equal("demo")

func test_the_same_save_loads_under_its_own_game() -> void:
	# The control. Without it, a loader that refused everything would pass the test above.
	assert_bool(SaveManager.save(0, _save_for(&"quest", &"quest_village"))).is_true()
	var loaded := SaveManager.load_slot(&"quest", 0)
	assert_object(loaded).is_not_null()
	assert_str(String(loaded.map)).is_equal("quest_village")

func test_peeking_at_a_slot_is_silent() -> void:
	# A menu draws its rows by reading every slot. If that read parked files and announced
	# loads, merely LOOKING at the pause screen would produce .corrupt files nobody asked for.
	SaveDirs.write_raw(&"demo", 0, "{ not json at all ")
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	assert_object(SaveManager.peek(&"demo", 0)).is_null()
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).override_failure_message("peeking announced a load").is_equal(0)
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"demo", 0))).override_failure_message(
		"peeking parked a file").is_false()

func test_peeking_reads_a_real_save() -> void:
	# The control for the silence above: a peek that returned null for everything would be
	# equally quiet and completely useless.
	SaveManager.save(1, _save_for(&"demo", &"demo_town"))
	var seen := SaveManager.peek(&"demo", 1)
	assert_object(seen).is_not_null()
	assert_str(String(seen.map)).is_equal("demo_town")

func test_saving_over_unreadable_bytes_parks_them_first() -> void:
	# The menu offers Load only for slots that read back, so an unreadable slot looks EMPTY -
	# which makes saving into it the one path that could destroy a damaged file silently.
	SaveDirs.write_raw(&"demo", 0, "{ ruined ")
	assert_bool(SaveManager.save(0, _save_for(&"demo", &"demo_town"))).is_true()
	assert_str(FileAccess.get_file_as_string(SaveManager.corrupt_path(&"demo", 0))).override_failure_message(
		"the unreadable bytes were overwritten instead of parked").is_equal("{ ruined ")
	assert_object(SaveManager.load_slot(&"demo", 0)).is_not_null()

func test_a_fractional_position_is_not_truncated() -> void:
	# Reading a position through an int conversion loses the fraction silently, and the
	# player reloads a few pixels from where they stood.
	GameState.new_game(&"demo", &"demo_town", Vector2(120.8, 136.4), Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	var loaded := SaveManager.load_slot(&"demo", 0)
	assert_float(loaded.position.x).is_equal_approx(120.8, 0.001)
	assert_float(loaded.position.y).is_equal_approx(136.4, 0.001)

func test_an_empty_slot_loads_as_nothing_rather_than_as_a_blank_game() -> void:
	# Returning a default SaveData would make "no save here" indistinguishable from "a save
	# of a game that has not started", and the menu would offer to continue nothing.
	assert_object(SaveManager.load_slot(&"demo", 3)).is_null()
	assert_bool(SaveManager.has_slot(&"demo", 3)).is_false()

func test_a_corrupt_save_is_preserved_before_anything_else_happens() -> void:
	# The whole point. The bytes must survive the failure.
	SaveDirs.write_raw(&"demo", 0, "{ this is not json ")
	assert_object(SaveManager.load_slot(&"demo", 0)).is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"demo", 0))).override_failure_message(
		"the unreadable save was discarded instead of preserved").is_true()
	assert_str(FileAccess.get_file_as_string(SaveManager.corrupt_path(&"demo", 0))).is_equal("{ this is not json ")

func test_a_structurally_wrong_save_is_also_preserved() -> void:
	# Readable JSON, impossible contents. "The save loaded and the player was nowhere" is a
	# bug report that needs the original file just as much as a parse failure does. Written at
	# the current version with the right game, so the faults under test are the only ones.
	SaveDirs.write_raw(&"demo", 0, '{"version": 3, "game": "demo", "map": "", "facing": 99}')
	assert_object(SaveManager.load_slot(&"demo", 0)).is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"demo", 0))).is_true()

func test_a_valid_save_leaves_no_corrupt_file_behind() -> void:
	GameState.new_game(&"demo", &"demo_town", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	assert_object(SaveManager.load_slot(&"demo", 0)).is_not_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"demo", 0))).is_false()

func test_a_version_1_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v1.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data, &"demo")
	assert_int(int(migrated["version"])).is_equal(SaveData.VERSION)
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	# The v1 shape carried no play time. It gets zero rather than a guess: a fabricated value
	# would be indistinguishable from a real one later.
	assert_float(data.play_seconds).is_equal(0.0)
	# And nor did it carry a game - it comes from the slot the file was found in.
	assert_str(String(data.game)).is_equal("demo")
	# Everything v1 DID carry survives intact.
	assert_str(String(data.map)).is_equal("demo_town")
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
	SaveDirs.write_raw(&"demo", 0, FileAccess.get_file_as_string(FIXTURES + "v1.json"))
	var loaded := SaveManager.load_slot(&"demo", 0)
	assert_object(loaded).override_failure_message("a v1 save was rejected instead of migrated").is_not_null()
	assert_int(loaded.version).is_equal(SaveData.VERSION)
	assert_str(String(loaded.game)).is_equal("demo")

func test_a_save_with_no_version_is_treated_as_the_oldest_shape() -> void:
	# A file predating versioning must walk the whole chain. Treating it as current would skip
	# every step and read old fields as new ones.
	var migrated := Migrations.apply({"map": "demo_town", "facing": 0}, &"demo")
	assert_int(int(migrated["version"])).is_equal(SaveData.VERSION)
	assert_bool(migrated.has("play_seconds")).is_true()
	assert_bool(migrated.has("game")).is_true()

func test_the_migration_chain_runs_every_step_not_just_one() -> void:
	# The `while` rather than `if`. With an `if`, a save two versions behind is migrated one
	# step and handed to a system that will not recognise it - and the failure shows up as
	# odd values rather than as an error.
	for from_version in Migrations.supported_versions():
		var migrated := Migrations.apply({"version": from_version, "map": "demo_town", "facing": 0}, &"demo")
		assert_int(int(migrated["version"])).override_failure_message(
			"a v%d save did not reach v%d" % [from_version, SaveData.VERSION]) \
			.is_equal(SaveData.VERSION)

func test_migrating_does_not_mutate_the_file_it_was_given() -> void:
	var original := {"version": 1, "map": "demo_town", "facing": 0}
	Migrations.apply(original, &"demo")
	assert_bool(original.has("play_seconds")).override_failure_message(
		"apply() edited its input; the caller's copy of the file is no longer what was read").is_false()
	assert_bool(original.has("game")).is_false()
	assert_int(int(original["version"])).is_equal(1)

func test_a_save_from_a_future_version_is_refused_rather_than_guessed_at() -> void:
	# Forwards compatibility is not free, and pretending to have it loses data. A save from a
	# newer build is reported, not silently read with fields this build does not understand.
	SaveDirs.write_raw(&"demo", 0, '{"version": 99, "game": "demo", "map": "demo_town", "facing": 0}')
	assert_object(SaveManager.load_slot(&"demo", 0)).is_null()

func test_deleting_a_slot_removes_it() -> void:
	GameState.new_game(&"demo", &"demo_town", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	assert_bool(SaveManager.has_slot(&"demo", 0)).is_true()
	SaveManager.delete_slot(&"demo", 0)
	assert_bool(SaveManager.has_slot(&"demo", 0)).is_false()

func test_saving_announces_itself() -> void:
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	GameState.new_game(&"demo", &"demo_town", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_true()
	assert_str(String(seen[0]["game"])).is_equal("demo")

func test_a_failed_load_announces_itself_too() -> void:
	# A resilient path that says nothing is how a broken save survives to release.
	SaveDirs.write_raw(&"demo", 0, "not json")
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	SaveManager.load_slot(&"demo", 0)
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_false()

func test_a_scripted_session_gets_its_own_save_directory() -> void:
	# A play script that read the real directory would pass or fail depending on who ran it,
	# and one that wrote to it would overwrite a player's progress on the same machine.
	assert_str(SaveManager.dir_for(PackedStringArray(["--qa-script=res://x.json", "--game=demo"]))) \
		.is_equal(SaveManager.QA_DIR)
	assert_str(SaveManager.dir_for(PackedStringArray(["--game=demo"]))).is_equal(SaveManager.DEFAULT_DIR)
	assert_str(SaveManager.dir_for(PackedStringArray([]))).is_equal(SaveManager.DEFAULT_DIR)
