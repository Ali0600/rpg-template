extends GdUnitTestSuite
## What the player chose, and where it is kept.
##
## Every test here redirects the autoload to a scratch file FIRST, and asserts the redirect
## landed. Without that, cycling the volume in a test writes the real settings of whoever is
## running it - and the mutation harness runs this suite with the code deliberately broken, so
## it would write it wrong. Restoring a source file is not restoring the world.

const SCRATCH := "user://test_settings.json"


func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.use_path(SCRATCH)
	assert_str(Settings.path()).override_failure_message(
		"the redirect is not in effect - this suite would write the real settings file"
	).is_equal(SCRATCH)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.use_path(Settings.path_for(GameSelect.args()))


func test_a_first_run_gets_the_default() -> void:
	assert_int(Settings.sound_level()).is_equal(Settings.DEFAULT_LEVEL)
	assert_str(Settings.sound_name()).is_equal("Normal")


func test_cycling_visits_every_step_and_comes_back() -> void:
	# Where the cycle ENDS is not enough: a cycle that never moves at all also ends on the
	# default. What makes this a test is that every step is visited exactly once on the way.
	var seen: Array[int] = []
	for i in Settings.Level.size():
		var next := Settings.cycle_sound()
		assert_bool(seen.has(next)).override_failure_message(
			"step %d came round twice in one cycle: %s" % [next, seen]).is_false()
		seen.append(next)
	assert_int(seen.size()).is_equal(Settings.Level.size())
	assert_int(Settings.sound_level()).override_failure_message(
		"a full cycle did not return to where it started").is_equal(Settings.DEFAULT_LEVEL)


func test_every_step_has_a_gain_and_a_name() -> void:
	for level: int in Settings.Level.values():
		Settings.set_sound_level(level)
		assert_str(Settings.sound_name()).is_not_empty()
		assert_float(Settings.sound_gain()).is_between(0.0, 1.0)


func test_off_really_means_silent() -> void:
	# The one step whose value is a promise rather than a preference. Anything above zero is
	# quiet, and quiet is not what the player asked for.
	Settings.set_sound_level(Settings.Level.OFF)
	assert_float(Settings.sound_gain()).is_equal(0.0)
	assert_float(AudioBus.volume()).is_equal(0.0)


func test_choosing_a_level_reaches_the_speaker() -> void:
	# Settings owns the value and the bus owns the device. If the push stopped happening the
	# menu would keep saying "Quiet" while nothing got any quieter.
	Settings.set_sound_level(Settings.Level.LOUD)
	assert_float(AudioBus.volume()).is_equal(Settings.sound_gain())
	Settings.set_sound_level(Settings.Level.QUIET)
	assert_float(AudioBus.volume()).is_equal(Settings.sound_gain())


func test_a_choice_survives_a_restart() -> void:
	# Written on change, not on quit: a browser tab closing does not give anyone a chance to
	# flush anything.
	Settings.cycle_sound()
	var chosen := Settings.sound_level()
	Settings.use_path(SCRATCH)
	assert_int(Settings.sound_level()).override_failure_message(
		"the setting did not survive being read back").is_equal(chosen)


func test_a_file_saying_something_impossible_falls_back() -> void:
	# Hand-edited, half-written, or from a future version with more steps. A level outside the
	# enum would index nothing and silence the game with no way to find out why.
	assert_int(JsonFile.write(SCRATCH, {"sound_level": 99})).is_equal(OK)
	Settings.use_path(SCRATCH)
	assert_int(Settings.sound_level()).is_equal(Settings.DEFAULT_LEVEL)


func test_no_palette_is_chosen_to_begin_with() -> void:
	# The default is the running style's own chrome, which is what every game built on this
	# template looked like before there was a choice.
	assert_str(String(Settings.palette())).is_equal(String(Settings.NO_PALETTE))


func test_cycling_visits_every_palette_and_the_default_once_each() -> void:
	# The sound row's shape and for its reason: where a cycle ENDS is also where a cycle that
	# never moved would end. What makes this a test is that each stop is visited exactly once,
	# and that the default is one of the stops - a cycle with no way back to the style's own
	# chrome would strand a player who tried one on.
	var ids: Array[StringName] = [&"a", &"b", &"c"]
	var seen: Array[String] = []
	for i in ids.size() + 1:
		var next := String(Settings.cycle_palette(ids))
		assert_bool(seen.has(next)).override_failure_message(
			"'%s' came round twice in one cycle: %s" % [next, seen]).is_false()
		seen.append(next)
	assert_int(seen.size()).is_equal(ids.size() + 1)
	assert_bool(seen.has(String(Settings.NO_PALETTE))).override_failure_message(
		"the cycle never offers a way back to the style's own chrome").is_true()
	assert_str(String(Settings.palette())).override_failure_message(
		"a full cycle did not return to where it started").is_equal(
			String(Settings.NO_PALETTE))


func test_a_game_that_ships_no_palettes_has_nothing_to_cycle_to() -> void:
	# A legal shape forever: three of the four shipped styles draw their own chrome and a game
	# may ship no palettes at all. The row must not then move to something that does not exist.
	assert_str(String(Settings.cycle_palette([] as Array[StringName]))).is_equal(
		String(Settings.NO_PALETTE))


func test_a_chosen_palette_survives_a_restart() -> void:
	Settings.cycle_palette([&"mint"] as Array[StringName])
	var chosen := Settings.palette()
	assert_str(String(chosen)).is_not_equal(String(Settings.NO_PALETTE))
	Settings.use_path(SCRATCH)
	assert_str(String(Settings.palette())).override_failure_message(
		"the chosen palette did not survive being read back").is_equal(String(chosen))


func test_a_palette_this_build_no_longer_ships_still_cycles_forward() -> void:
	# What a settings file holds after a palette is deleted from a game. Treating the missing id
	# as a member would make find() answer -1 and the next press skip the first entry - so the
	# player presses once, sees nothing they recognise, and the way back is a press further off
	# than it looks.
	assert_int(JsonFile.write(SCRATCH, {"sound_level": 2, "palette": "gone"})).is_equal(OK)
	Settings.use_path(SCRATCH)
	assert_str(String(Settings.palette())).is_equal("gone")
	assert_str(String(Settings.cycle_palette([&"mint", &"charcoal"] as Array[StringName]))
		).override_failure_message(
			"cycling from a deleted palette did not land on the first one offered").is_equal(
				"mint")


func test_the_volume_and_the_palette_are_kept_in_one_file_without_disturbing_each_other() -> void:
	# Two independent choices in one file. Writing either must not drop the other - the failure
	# is silent and only shows up on the next restart, by which time nobody connects the two.
	Settings.cycle_palette([&"mint"] as Array[StringName])
	Settings.cycle_sound()
	var level := Settings.sound_level()
	var palette := Settings.palette()
	Settings.use_path(SCRATCH)
	assert_int(Settings.sound_level()).override_failure_message(
		"choosing a palette lost the volume").is_equal(level)
	assert_str(String(Settings.palette())).override_failure_message(
		"changing the volume lost the palette").is_equal(String(palette))


func test_an_impossible_volume_does_not_take_the_palette_down_with_it() -> void:
	# The read gives up on a bad volume and returns. The palette is taken FIRST for exactly this:
	# one field being unreadable says nothing about the other, and a player whose file was
	# hand-edited should not lose their window colour to it as well.
	assert_int(JsonFile.write(SCRATCH, {"sound_level": 99, "palette": "mint"})).is_equal(OK)
	Settings.use_path(SCRATCH)
	assert_int(Settings.sound_level()).is_equal(Settings.DEFAULT_LEVEL)
	assert_str(String(Settings.palette())).override_failure_message(
		"an unreadable volume threw the palette away too").is_equal("mint")


func test_a_qa_run_never_touches_the_real_file() -> void:
	# A pure function of the command line, so it is provable without arranging a process - the
	# SaveManager.dir_for shape, for the same reason.
	var qa := PackedStringArray(["--qa-script=res://tests/fixtures/qa/quest/x.json"])
	assert_str(Settings.path_for(qa)).is_equal(Settings.QA_PATH)
	assert_str(Settings.path_for(PackedStringArray([]))).is_equal(Settings.DEFAULT_PATH)
	assert_str(Settings.QA_PATH).is_not_equal(Settings.DEFAULT_PATH)
