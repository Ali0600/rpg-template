extends GdUnitTestSuite
## Reading a committed WAV as samples, without the import system.
##
## The sibling of test_image_file.gd, and it exists for the same reason that suite does:
## swapping how a gate READS its inputs is exactly the change that can quietly make it read
## nothing, and a reader returning null for everything would leave the drift gate comparing
## absence to absence and reporting green.


func _a_committed_cue() -> String:
	for res in ContentScan.resources("res://data/sounds", ["tres"] as Array[String]):
		var style := res as SoundStyle
		if style != null:
			return "res://assets/generated/%s/sfx/%s.wav" % [style.id, Sfx.id_of(Sfx.Cue.HIT)]
	return ""


func test_a_committed_cue_reads_back_as_the_style_asked_for_it() -> void:
	var path := _a_committed_cue()
	assert_str(path).is_not_empty()
	var wav := SoundFile.read_wav(path)
	assert_object(wav).override_failure_message("%s did not read" % path).is_not_null()
	assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_bool(wav.stereo).is_false()
	assert_int(wav.data.size()).is_greater(0)


func test_the_samples_are_the_bytes_the_reader_found() -> void:
	var path := _a_committed_cue()
	assert_array(SoundFile.samples_of(path)).is_equal(SoundFile.read_wav(path).data)


func test_a_file_that_is_not_there_reads_as_nothing() -> void:
	assert_object(SoundFile.read_wav("res://assets/generated/nope/sfx/nope.wav")).is_null()
	assert_array(SoundFile.samples_of("res://assets/generated/nope/sfx/nope.wav")).is_empty()
