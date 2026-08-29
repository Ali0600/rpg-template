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


func test_asserting_a_companions_numbers_can_fail() -> void:
	GameState.reset()
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(_complains({"op": "assert_hp", "member": "scrapper", "value": 11})) \
		.override_failure_message("a correct companion assertion complained").is_false()
	assert_bool(_complains({"op": "assert_hp", "member": "scrapper", "value": 12})) \
		.override_failure_message("a wrong companion assertion passed").is_true()
	GameState.reset()


func test_asserting_a_number_of_somebody_who_has_not_joined_fails() -> void:
	# The default that would have hidden this: reading a missing companion as nought would make
	# "the person is not here" and "the number is nought" the same finding, and a session
	# recruiting nobody would still assert its way to green.
	#
	# Asserted by the WORDING, not merely by "it complained": with the guard gone, a missing
	# companion reads as a record of no numbers and the value comparison below it complains
	# anyway - a masking path that makes a green mutant look like a covered rule.
	GameState.reset()
	assert_bool(_complains({"op": "assert_hp", "member": "scrapper", "value": 0})) \
		.override_failure_message("a companion who never joined answered an assertion").is_true()
	assert_str("\n".join(Qa._failures)).override_failure_message(
		"the harness complained about the NUMBER when the person was the thing missing") \
		.contains("has not joined")
	Qa._failures.clear()


func test_the_leaders_numbers_are_still_what_a_bare_assertion_reads() -> void:
	# The control every session written before M27 depends on: with no member named, nothing
	# about these ops moved.
	GameState.reset()
	GameState.set_party(20, 0, 1, 8)
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(_complains({"op": "assert_hp", "value": 20})) \
		.override_failure_message("a bare hp assertion stopped reading the leader").is_false()
	GameState.reset()


func test_asking_a_member_for_the_purse_fails() -> void:
	# One purse for the whole party, in every reference game and here - so a member on a gold
	# assertion is a question with no answer rather than a different answer, and answering it
	# would be the harness inventing a per-member economy nobody built.
	GameState.reset()
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(_complains({"op": "assert_gold", "member": "scrapper", "value": 0})) \
		.override_failure_message("the harness answered a per-member gold question").is_true()
	GameState.reset()
