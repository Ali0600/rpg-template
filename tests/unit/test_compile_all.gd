extends GdUnitTestSuite
## Which files the whole-project compile gate decides to skip.
##
## It skips scripts that USE an autoload, because a standalone run cannot resolve one. A skip
## is an uncompiled file, so the cost of getting this wrong is silent: the gate keeps reporting
## success over a shrinking set.
##
## Tested as a pure function over TEXT, which is what it is - no file has to exist for the rule
## to be provable, and no fixture can drift away from it.

const TOOL := "res://tools/compile_all.gd"


func _uses(code: String, name: String) -> bool:
	return bool(load(TOOL).call(&"_uses", code, name))


func test_a_singleton_actually_used_is_found() -> void:
	assert_bool(_uses("var x := GameState.player_level\n", "GameState")).is_true()
	assert_bool(_uses("\tAudioBus.play_sfx(id)\n", "AudioBus")).is_true()


func test_a_name_that_merely_ends_another_identifier_is_not_a_use() -> void:
	# The bug this was written for: a singleton called Settings made every file calling
	# ProjectSettings look like it used it, and nine files dropped out of the compile gate at
	# once - reported only as a count going up, which nobody reads as a failure.
	assert_bool(_uses("ProjectSettings.globalize_path(p)\n", "Settings")).is_false()
	assert_bool(_uses("var a := MyRouter.go()\n", "Router")).is_false()


func test_a_name_at_the_very_start_of_a_file_still_counts() -> void:
	# The boundary check has to cope with there being no preceding character at all.
	assert_bool(_uses("Settings.sound_gain()", "Settings")).is_true()


func test_both_forms_in_one_file_are_still_a_use() -> void:
	# The real shape of the file that broke it: a genuine use AND a lookalike. Stopping at the
	# first lookalike would answer "not used" about a file that plainly does.
	assert_bool(_uses("ProjectSettings.globalize_path(p)\nSettings.sound_gain()\n",
		"Settings")).is_true()


func test_a_bare_mention_is_not_a_use() -> void:
	# A trailing dot is required, so prose naming a singleton does not cost a file its place in
	# the gate. The per-file PARSE gate in check.sh is the one that cannot make this
	# distinction - which is why views emit a signal instead of playing a sound.
	assert_bool(_uses("var settings_are_nice := 1\n", "Settings")).is_false()
	assert_bool(_uses("var x := Settings\n", "Settings")).is_false()
