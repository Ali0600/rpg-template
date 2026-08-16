extends GdUnitTestSuite
## Saves, migrations, and what happens to a file that will not parse.
##
## The last one is the reason this suite exists. A player's save file IS their progress, so a
## loader that quietly falls back to a fresh game - and then lets the next autosave write over
## the bad bytes - has destroyed the progress AND the only evidence of what went wrong. The
## bytes are parked first, and the failure is reported.

const TEST_DIR := "user://test_saves"
const FIXTURES := "res://tests/fixtures/saves/"

func before_test() -> void:
	GameState.reset()
	SaveManager.base_dir = TEST_DIR
	_clear()

func after_test() -> void:
	_clear()
	SaveManager.base_dir = SaveManager.DEFAULT_DIR
	GameState.reset()

func _clear() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()

func _write_raw(slot: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var f := FileAccess.open(SaveManager.slot_path(slot), FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_a_save_round_trips_through_disk() -> void:
	GameState.new_game(&"demo_town", Vector2(120.5, 88.25), Dir.D.LEFT)
	GameState.set_flag(&"promised_elder", true)
	GameState.mark_seen(&"intro")
	GameState.play_seconds = 42.5

	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	GameState.reset()
	var loaded := SaveManager.load_slot(0)
	assert_object(loaded).is_not_null()
	GameState.from_save(loaded)

	assert_str(String(GameState.current_map)).is_equal("demo_town")
	assert_vector(GameState.player_position).is_equal(Vector2(120.5, 88.25))
	assert_int(GameState.player_facing).is_equal(Dir.D.LEFT)
	assert_bool(GameState.has_flag(&"promised_elder")).is_true()
	assert_bool(GameState.was_seen(&"intro")).is_true()
	assert_float(GameState.play_seconds).is_equal_approx(42.5, 0.001)

func test_a_fractional_position_is_not_truncated() -> void:
	# Reading a position through an int conversion loses the fraction silently, and the
	# player reloads a few pixels from where they stood.
	GameState.new_game(&"demo_town", Vector2(120.8, 136.4), Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	var loaded := SaveManager.load_slot(0)
	assert_float(loaded.position.x).is_equal_approx(120.8, 0.001)
	assert_float(loaded.position.y).is_equal_approx(136.4, 0.001)

func test_an_empty_slot_loads_as_nothing_rather_than_as_a_blank_game() -> void:
	# Returning a default SaveData would make "no save here" indistinguishable from "a save
	# of a game that has not started", and the menu would offer to continue nothing.
	assert_object(SaveManager.load_slot(3)).is_null()
	assert_bool(SaveManager.has_slot(3)).is_false()

func test_a_corrupt_save_is_preserved_before_anything_else_happens() -> void:
	# The whole point. The bytes must survive the failure.
	_write_raw(0, "{ this is not json ")
	assert_object(SaveManager.load_slot(0)).is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(0))).override_failure_message(
		"the unreadable save was discarded instead of preserved").is_true()
	assert_str(FileAccess.get_file_as_string(SaveManager.corrupt_path(0))).is_equal("{ this is not json ")

func test_a_structurally_wrong_save_is_also_preserved() -> void:
	# Readable JSON, impossible contents. "The save loaded and the player was nowhere" is a
	# bug report that needs the original file just as much as a parse failure does.
	_write_raw(0, '{"version": 2, "map": "", "facing": 99}')
	assert_object(SaveManager.load_slot(0)).is_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(0))).is_true()

func test_a_valid_save_leaves_no_corrupt_file_behind() -> void:
	GameState.new_game(&"demo_town", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	assert_object(SaveManager.load_slot(0)).is_not_null()
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(0))).is_false()

func test_a_version_1_save_is_carried_forward() -> void:
	var file := JsonFile.read(FIXTURES + "v1.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var migrated := Migrations.apply(file.data)
	assert_int(int(migrated["version"])).is_equal(SaveData.VERSION)
	var data := SaveData.from_dict(migrated)
	assert_array(data.problems()).is_empty()
	# The v1 shape carried no play time. It gets zero rather than a guess: a fabricated value
	# would be indistinguishable from a real one later.
	assert_float(data.play_seconds).is_equal(0.0)
	# And everything v1 DID carry survives intact.
	assert_str(String(data.map)).is_equal("demo_town")
	assert_int(data.facing).is_equal(Dir.D.RIGHT)
	assert_bool(bool(data.flags.get("promised_elder", false))).is_true()

func test_a_version_1_save_loads_through_the_manager() -> void:
	_write_raw(0, FileAccess.get_file_as_string(FIXTURES + "v1.json"))
	var loaded := SaveManager.load_slot(0)
	assert_object(loaded).override_failure_message("a v1 save was rejected instead of migrated").is_not_null()
	assert_int(loaded.version).is_equal(SaveData.VERSION)

func test_a_save_with_no_version_is_treated_as_the_oldest_shape() -> void:
	# A file predating versioning must walk the whole chain. Treating it as current would skip
	# every step and read old fields as new ones.
	var migrated := Migrations.apply({"map": "demo_town", "facing": 0})
	assert_int(int(migrated["version"])).is_equal(SaveData.VERSION)
	assert_bool(migrated.has("play_seconds")).is_true()

func test_the_migration_chain_runs_every_step_not_just_one() -> void:
	# The `while` rather than `if`. With an `if`, a save two versions behind is migrated one
	# step and handed to a system that will not recognise it - and the failure shows up as
	# odd values rather than as an error.
	for from_version in Migrations.supported_versions():
		var migrated := Migrations.apply({"version": from_version, "map": "demo_town", "facing": 0})
		assert_int(int(migrated["version"])).override_failure_message(
			"a v%d save did not reach v%d" % [from_version, SaveData.VERSION]) \
			.is_equal(SaveData.VERSION)

func test_migrating_does_not_mutate_the_file_it_was_given() -> void:
	var original := {"version": 1, "map": "demo_town", "facing": 0}
	Migrations.apply(original)
	assert_bool(original.has("play_seconds")).override_failure_message(
		"apply() edited its input; the caller's copy of the file is no longer what was read").is_false()
	assert_int(int(original["version"])).is_equal(1)

func test_a_save_from_a_future_version_is_refused_rather_than_guessed_at() -> void:
	# Forwards compatibility is not free, and pretending to have it loses data. A save from a
	# newer build is reported, not silently read with fields this build does not understand.
	_write_raw(0, '{"version": 99, "map": "demo_town", "facing": 0}')
	assert_object(SaveManager.load_slot(0)).is_null()

func test_deleting_a_slot_removes_it() -> void:
	GameState.new_game(&"demo_town", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	assert_bool(SaveManager.has_slot(0)).is_true()
	SaveManager.delete_slot(0)
	assert_bool(SaveManager.has_slot(0)).is_false()

func test_saving_announces_itself() -> void:
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	GameState.new_game(&"demo_town", Vector2.ZERO, Dir.D.DOWN)
	SaveManager.save(0, GameState.to_save())
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_true()

func test_a_failed_load_announces_itself_too() -> void:
	# A resilient path that says nothing is how a broken save survives to release.
	_write_raw(0, "not json")
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.save_changed.connect(handler)
	SaveManager.load_slot(0)
	EventBus.save_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_bool(bool(seen[0]["ok"])).is_false()
