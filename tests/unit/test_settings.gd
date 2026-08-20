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


func test_a_qa_run_never_touches_the_real_file() -> void:
	# A pure function of the command line, so it is provable without arranging a process - the
	# SaveManager.dir_for shape, for the same reason.
	var qa := PackedStringArray(["--qa-script=res://tests/fixtures/qa/quest/x.json"])
	assert_str(Settings.path_for(qa)).is_equal(Settings.QA_PATH)
	assert_str(Settings.path_for(PackedStringArray([]))).is_equal(Settings.DEFAULT_PATH)
	assert_str(Settings.QA_PATH).is_not_equal(Settings.DEFAULT_PATH)
