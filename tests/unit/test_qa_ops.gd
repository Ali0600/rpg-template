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
	# The voice is global and outlives this suite, so a test that unbinds it has to put it
	# back - otherwise the next suite in the run inherits a silent bus and fails somewhere
	# that has nothing to do with audio.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
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

func test_asserting_audio_is_ready_fails_when_there_is_no_voice_at_all() -> void:
	# The gate that exists to catch a silent artifact used to pass BECAUSE the artifact was
	# silent. missing_cues() and missing_tracks() are filled by reload() only when a voice is
	# bound, so with none bound both lists are empty and "every cue is playable" came back
	# green having asked about nothing. That is what let a title playing into an unbound bus
	# ship, and it is the shape of every gate that reports on a set it never populated.
	AudioBus.use_style(null)
	assert_bool(_complains({"op": "assert_audio_ready"})).override_failure_message(
		"a bus with no voice bound at all passed the readiness gate").is_true()

	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	assert_bool(_complains({"op": "assert_audio_ready"})).override_failure_message(
		"a fully bound voice failed the readiness gate").is_false()

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
