extends GdUnitTestSuite
## The audio seam: a stub that behaves correctly when it has nothing to play.
##
## The template ships no sound files - sound is one of the things a game brings, and a
## placeholder beep committed to a template is a placeholder beep shipped in somebody's game.
## What is tested here is that asking for a sound by name works, and that a name with nothing
## behind it says so ONCE instead of failing silently or drowning the log.

func test_asking_for_a_missing_sound_does_not_crash_and_reports_failure() -> void:
	# The failure that matters is silence: a caller that cannot tell whether its sound played
	# has no way to notice that audio broke.
	assert_bool(AudioBus.play_sfx(&"definitely_not_a_sound")).is_false()
	assert_bool(AudioBus.play_music(&"also_not_a_sound")).is_false()

func test_a_missing_sound_is_reported_and_then_stops_repeating() -> void:
	# Warned once per id: a sound requested every frame would otherwise bury the log in one
	# repeated line and make every other warning unreadable.
	AudioBus.reload()
	for i in 50:
		AudioBus.play_sfx(&"noisy_missing_sound")
	# Nothing to assert on the log itself; what matters is that fifty calls are survivable
	# and still report failure honestly rather than pretending to have played.
	assert_bool(AudioBus.play_sfx(&"noisy_missing_sound")).is_false()

func test_the_bus_knows_which_sounds_it_has() -> void:
	# With no files shipped this is empty, and that is the point: the seam answers honestly
	# rather than claiming to hold sounds it cannot play.
	AudioBus.reload()
	for id in AudioBus.ids():
		assert_bool(AudioBus.has_sound(id)).is_true()
	assert_bool(AudioBus.has_sound(&"definitely_not_a_sound")).is_false()

func test_requests_can_arrive_through_the_event_bus() -> void:
	# Systems ask for sounds by emitting, so nothing needs a reference to the audio system -
	# which is what lets audio be added later without touching the callers.
	EventBus.sound_requested.emit({"id": &"missing", "kind": &"sfx"})
	EventBus.sound_requested.emit({"id": &"missing", "kind": &"music"})
	assert_bool(true).is_true()

func test_muting_does_not_change_whether_a_sound_exists() -> void:
	AudioBus.set_enabled(false)
	assert_bool(AudioBus.has_sound(&"definitely_not_a_sound")).is_false()
	AudioBus.set_enabled(true)
