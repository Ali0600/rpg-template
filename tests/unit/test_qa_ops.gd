extends GdUnitTestSuite
## That the play harness's assertions can FAIL.
##
## Every scripted session is green, which is the point of them and also the problem: an op whose
## check never fires reads exactly like an op whose check always passes, and a session built on
## one proves nothing while looking like proof. The sessions cannot test this themselves - a
## broken assertion makes them pass harder.
##
## So each op here is driven twice, through Qa's own dispatcher: once where it must be quiet and
## once where it must complain. Only the pair says the instrument works.

func before_test() -> void:
	AudioBus.stop_music()
	Qa._failures.clear()

func after_test() -> void:
	AudioBus.stop_music()
	Qa._failures.clear()


## Runs one step and answers whether it complained.
func _complains(step: Dictionary) -> bool:
	Qa._failures.clear()
	Qa._run(step)
	return not Qa._failures.is_empty()


func test_asserting_what_is_playing_right_now_can_fail() -> void:
	# The "now" mode reads the live track rather than the request log, and it is the only way a
	# session can say SILENCE - so a session's silence gate is worth exactly what this pair is.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	AudioBus.play_music(&"barred_gate")
	assert_bool(_complains({"op": "assert_music", "id": "barred_gate", "now": true})) \
		.override_failure_message("the right answer was called wrong").is_false()
	assert_bool(_complains({"op": "assert_music", "id": "skirmish", "now": true})) \
		.override_failure_message("a track that is not playing passed as playing").is_true()

func test_asserting_silence_right_now_can_fail() -> void:
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	AudioBus.play_music(&"barred_gate")
	assert_bool(_complains({"op": "assert_music", "id": "", "now": true})) \
		.override_failure_message("music was playing and a silence gate passed").is_true()
	AudioBus.stop_music()
	assert_bool(_complains({"op": "assert_music", "id": "", "now": true})) \
		.override_failure_message("nothing was playing and the silence gate still failed") \
		.is_false()

func test_asserting_what_was_asked_for_still_reads_the_log() -> void:
	# The control for the mode switch: adding "now" must not have taken the old behaviour away.
	# The log remembers a track that has since stopped, which is the whole difference.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	AudioBus.clear_requests()
	AudioBus.play_music(&"barred_gate")
	AudioBus.stop_music()
	assert_bool(_complains({"op": "assert_music", "id": "barred_gate"})).override_failure_message(
		"the log forgot a track that played and ended").is_false()
	assert_bool(_complains({"op": "assert_music", "id": "barred_gate", "now": true})) \
		.override_failure_message("'now' answered from the log instead of from the device") \
		.is_true()
