extends GdUnitTestSuite
## Resolving a sound by name across two roots, and what happens when the answer is ambiguous.
##
## Nothing here asserts that audio was AUDIBLE - headless CI runs on a dummy driver and there
## is no speaker to ask. Every assertion is on the mechanism instead: which stream an id bound
## to, what was requested, what the bus reported. That is deliberate rather than a compromise;
## "it made a noise" is not a claim a gate can check, and pretending otherwise is how a gate
## ends up proving nothing.
##
## The bus is an autoload and outlives a suite, so every test puts it back.

const OVERRIDE_ROOT := "res://tests/fixtures/audio/override"
const DUPLICATE_ROOT := "res://tests/fixtures/audio/duplicate"
const EMPTY_ROOT := "res://tests/fixtures/audio/nothing_here"


func _voice(id: StringName) -> SoundStyle:
	return load("res://data/sounds/%s.tres" % id) as SoundStyle


func before_test() -> void:
	AudioBus.set_enabled(true)
	AudioBus.use_style(null, EMPTY_ROOT)
	AudioBus.clear_requests()


func after_test() -> void:
	AudioBus.use_style(null)
	AudioBus.clear_requests()
	AudioBus.set_enabled(true)


func test_a_voice_can_answer_every_cue_the_template_names() -> void:
	AudioBus.use_style(_voice(&"dusk16"), EMPTY_ROOT)
	for cue: int in Sfx.Cue.values():
		assert_bool(AudioBus.has_sound(Sfx.id_of(cue))).override_failure_message(
			"dusk16 cannot play '%s'" % Sfx.id_of(cue)).is_true()
	assert_array(AudioBus.missing_cues()).is_empty()


func test_with_no_voice_there_is_nothing_to_play() -> void:
	# A silent game is a legal shape, not a broken one. It must not report missing cues either -
	# nothing asked for a voice, so nothing is missing.
	assert_array(AudioBus.ids()).is_empty()
	assert_array(AudioBus.missing_cues()).is_empty()
	assert_bool(AudioBus.play(Sfx.Cue.HIT)).is_false()


func test_a_games_own_file_beats_the_generated_cue() -> void:
	# The seam, asserted by BYTES rather than by the flag the bus sets: a precedence bug sets
	# exactly the same flag and binds exactly the wrong audio.
	AudioBus.use_style(_voice(&"dusk16"), OVERRIDE_ROOT)
	var bound := AudioBus.stream_for(Sfx.id_of(Sfx.Cue.HIT)) as AudioStreamWAV
	assert_object(bound).is_not_null()
	var dropped_in := load("%s/hit.wav" % OVERRIDE_ROOT) as AudioStreamWAV
	var generated := load("res://assets/generated/dusk16/sfx/hit.wav") as AudioStreamWAV
	assert_str(Hashing.sha256_bytes(dropped_in.data)).override_failure_message(
		"the fixture and the generated cue are identical, so this test cannot tell them apart"
	).is_not_equal(Hashing.sha256_bytes(generated.data))
	assert_str(Hashing.sha256_bytes(bound.data)).override_failure_message(
		"the generated cue won over the file the game dropped in").is_equal(
		Hashing.sha256_bytes(dropped_in.data))


func test_an_override_is_reported_rather_than_happening_quietly() -> void:
	AudioBus.use_style(_voice(&"dusk16"), OVERRIDE_ROOT)
	assert_array(AudioBus.overridden()).contains([Sfx.id_of(Sfx.Cue.HIT)])
	# And only the one: reporting every cue as overridden would be the same as reporting none.
	assert_int(AudioBus.overridden().size()).is_equal(1)


func test_two_files_answering_to_one_name_are_reported() -> void:
	# Which one would win depends on directory order, which differs between filesystems - so
	# the loser is invisible AND non-deterministic. Registry refuses to let that pass quietly
	# for content ids; this is the same refusal.
	AudioBus.use_style(null, DUPLICATE_ROOT)
	assert_array(AudioBus.duplicate_ids()).contains([Sfx.id_of(Sfx.Cue.MENU_MOVE)])


func test_a_voice_missing_its_cues_says_which_ones() -> void:
	# Pointed at a voice whose art was never generated. The failure this catches is a game that
	# boots perfectly and is silent, which reads as "sound is not built yet".
	var orphan := SoundStyle.new()
	orphan.id = &"never_generated"
	orphan.bank_id = &"gb16"
	orphan.tone = &"square"
	AudioBus.use_style(orphan, EMPTY_ROOT)
	assert_int(AudioBus.missing_cues().size()).is_equal(Sfx.ids().size())


func test_what_was_asked_for_is_remembered_even_when_it_could_not_play() -> void:
	# The log is what every other gate leans on, so it must record the REQUEST rather than the
	# playback: a cue that failed to resolve is exactly the one a test needs to see.
	AudioBus.play_sfx(&"definitely_not_a_sound")
	assert_array(AudioBus.requested()).contains([&"definitely_not_a_sound"])


func test_a_muted_bus_still_records_what_was_asked_for() -> void:
	AudioBus.use_style(_voice(&"dusk16"), EMPTY_ROOT)
	AudioBus.set_enabled(false)
	assert_bool(AudioBus.play(Sfx.Cue.HIT)).is_false()
	assert_array(AudioBus.requested()).contains([Sfx.id_of(Sfx.Cue.HIT)])
	# Muting is not unloading: the sound is still there, it is just not coming out.
	assert_bool(AudioBus.has_sound(Sfx.id_of(Sfx.Cue.HIT))).is_true()


func test_a_name_no_cue_has_is_singled_out() -> void:
	AudioBus.use_style(_voice(&"dusk16"), EMPTY_ROOT)
	AudioBus.play(Sfx.Cue.HIT)
	AudioBus.play_sfx(&"kazoo")
	assert_array(AudioBus.unknown_requests()).is_equal([&"kazoo"] as Array[StringName])


func test_the_log_cannot_grow_without_bound() -> void:
	# An autoload outlives every scene, so a log with no ceiling is a leak that only appears
	# in a session long enough that nobody is watching for it.
	for i in 500:
		AudioBus.play_sfx(&"repeated")
	assert_int(AudioBus.requested().size()).is_less_equal(64)


func test_a_cue_does_not_cut_the_one_before_it() -> void:
	# One player meant every sound interrupted its predecessor, so a footstep silenced the
	# dialog blip it happened to land on. Asserted by counting what is actually sounding.
	AudioBus.use_style(_voice(&"dusk16"), EMPTY_ROOT)
	AudioBus.play(Sfx.Cue.DEFEAT)
	AudioBus.play(Sfx.Cue.VICTORY)
	assert_int(_sounding()).override_failure_message(
		"the second cue replaced the first instead of playing beside it").is_greater(1)


func test_asking_through_the_event_bus_reaches_the_same_place() -> void:
	# Systems ask by emitting, so nothing needs a reference to the audio system - which is what
	# let sound be added long after the callers were written.
	AudioBus.use_style(_voice(&"dusk16"), EMPTY_ROOT)
	EventBus.sound_requested.emit({"id": Sfx.id_of(Sfx.Cue.WARP), "kind": &"sfx"})
	assert_array(AudioBus.requested()).contains([Sfx.id_of(Sfx.Cue.WARP)])


func test_a_missing_sound_reports_failure_every_time_it_is_asked() -> void:
	# Warned once, but ANSWERED honestly every time: a caller that cannot tell whether its
	# sound played has no way to notice that audio broke.
	for i in 50:
		assert_bool(AudioBus.play_sfx(&"noisy_missing_sound")).is_false()


## How many of the bus's players are currently sounding.
func _sounding() -> int:
	var count := 0
	for child in AudioBus.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.playing:
			count += 1
	return count


func test_a_track_is_not_mistaken_for_a_misspelled_cue() -> void:
	# The regression this file exists for most. _play logs every id it is asked for, and
	# unknown_requests() turns anything Sfx does not name into a failed play session - so the
	# first tune would have failed the scripted sessions, and only SOME of them, because a
	# 64-entry ring buffer and every sound_mark can age the id out. Intermittent is worse than
	# broken.
	AudioBus.clear_requests()
	AudioBus.play_music(&"barred_gate")
	assert_array(AudioBus.unknown_requests()).override_failure_message(
		"a track was reported as a cue nobody named: %s" % [AudioBus.unknown_requests()]).is_empty()
	assert_array(AudioBus.music_requested()).contains([&"barred_gate"])
	assert_array(AudioBus.requested()).override_failure_message(
		"a track landed in the cue log, where the strict gate reads").not_contains([&"barred_gate"])


func test_a_misspelled_cue_is_still_singled_out() -> void:
	# The control for the test above: splitting the logs must not have taught the gate to shrug.
	AudioBus.clear_requests()
	AudioBus.play_sfx(&"no_such_cue")
	assert_array(AudioBus.unknown_requests()).contains([&"no_such_cue"])


func test_a_track_already_playing_is_not_started_again() -> void:
	# Walking between two rooms of one town must not restart the theme from the top, which is
	# the single most recognisable bug in this genre.
	AudioBus.stop_music()
	AudioBus.clear_requests()
	var before := AudioBus.music_starts()
	AudioBus.play_music(&"barred_gate")
	AudioBus.play_music(&"barred_gate")
	assert_int(AudioBus.music_requested().size()).override_failure_message(
		"the second ask was not even recorded, so this proves nothing about the first").is_equal(2)
	# Counted starts, not the request log and not the device: the request happens either way,
	# and headless never reports anything as playing.
	assert_int(AudioBus.music_starts() - before).override_failure_message(
		"the theme started again when it was already playing").is_equal(1)


func test_a_different_track_does_start() -> void:
	# The control. Without it the assertion above passes for a bus that never starts anything.
	AudioBus.stop_music()
	var before := AudioBus.music_starts()
	AudioBus.play_music(&"barred_gate")
	AudioBus.play_music(&"some_other_tune")
	assert_int(AudioBus.music_starts() - before).is_equal(2)


func test_stopping_forgets_what_was_playing() -> void:
	# Otherwise the no-restart rule above would refuse to start the same track again after a
	# dungeon, and the town would be silent on the way back.
	AudioBus.play_music(&"barred_gate")
	AudioBus.stop_music()
	assert_str(String(AudioBus.music_id())).is_empty()


func test_a_track_is_bound_to_loop_where_a_cue_is_not() -> void:
	# Set at bind time rather than in the .import sidecar: project.godot pins WAV looping off
	# for the whole project, there is one importer default per importer, and a sidecar is build
	# output the drift gate regenerates.
	var style := load("res://data/sounds/dusk16.tres") as SoundStyle
	AudioBus.use_style(style)
	for track_id in MusicTrack.ids():
		var stream := AudioBus.stream_for(track_id) as AudioStreamWAV
		assert_object(stream).override_failure_message(
			"the voice cannot play track '%s'" % track_id).is_not_null()
		assert_int(stream.loop_mode).override_failure_message(
			"track '%s' plays once and then the game goes quiet" % track_id).is_equal(
			AudioStreamWAV.LOOP_FORWARD)
		assert_int(stream.loop_end).is_equal(stream.data.size() / 2)
	var cue := AudioBus.stream_for(Sfx.id_of(Sfx.Cue.HIT)) as AudioStreamWAV
	assert_int(cue.loop_mode).override_failure_message(
		"a one-shot cue loops forever").is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_a_voice_that_cannot_play_a_track_says_which() -> void:
	# missing_cues() for music. assert_audio_ready and smoke_boot both read it, and its whole
	# point is an artifact that boots, walks, talks and is silent.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	assert_array(AudioBus.missing_tracks()).override_failure_message(
		"the shipped voice cannot play %s" % [AudioBus.missing_tracks()]).is_empty()
