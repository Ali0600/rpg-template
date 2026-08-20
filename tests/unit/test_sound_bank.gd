extends GdUnitTestSuite
## The bank and the voice, and what each refuses.
##
## The completeness half is the one that earns its keep: Sfx is the generator's work list, so a
## bank that cannot answer every cue in it must fail the BUILD. The alternative is AudioBus
## warning once at the moment the sound should have played, which is a release with a hole in
## it and a log line nobody was watching for.


func _style() -> SoundStyle:
	var style := SoundStyle.new()
	style.id = &"probe"
	style.bank_id = &"gb16"
	style.tone = &"square"
	return style


func test_every_shipped_style_is_valid() -> void:
	var styles := ContentScan.resources("res://data/sounds", ["tres"] as Array[String])
	assert_int(styles.size()).override_failure_message(
		"no sound styles were checked, so this proved nothing").is_greater(0)
	for res in styles:
		var style := res as SoundStyle
		assert_array(style.problems()).override_failure_message(
			"shipped style '%s': %s" % [style.id, style.problems()]).is_empty()


func test_every_shipped_style_has_a_bank_that_answers_every_cue() -> void:
	var styles := ContentScan.resources("res://data/sounds", ["tres"] as Array[String])
	var checked := 0
	for res in styles:
		var style := res as SoundStyle
		var bank := SoundBank.load_from(style.bank_id)
		assert_array(bank.problems()).override_failure_message(
			"style '%s' bank '%s': %s" % [style.id, style.bank_id, bank.problems()]).is_empty()
		checked += 1
	assert_int(checked).is_greater(0)


func test_a_bank_missing_a_cue_the_template_asks_for_is_a_problem() -> void:
	var bank := SoundBank.load_from(&"gb16")
	assert_array(bank.problems()).is_empty()
	bank.cues.erase(Sfx.id_of(Sfx.Cue.FOOTSTEP))
	var found := false
	for p in bank.problems():
		if p.contains(String(Sfx.id_of(Sfx.Cue.FOOTSTEP))):
			found = true
	assert_bool(found).override_failure_message(
		"a bank with no footstep reported: %s" % [bank.problems()]).is_true()


func test_a_bank_defining_a_cue_nobody_asks_for_is_a_problem() -> void:
	# The mirror of the check above, and not the same test. Validating that every WANTED cue is
	# present says nothing about a cue left behind by a rename, which would keep being
	# generated and committed forever with nothing ever playing it.
	var bank := SoundBank.load_from(&"gb16")
	bank.cues[&"kazoo"] = {"ms": 50.0}
	var found := false
	for p in bank.problems():
		if p.contains("kazoo"):
			found = true
	assert_bool(found).is_true()


func test_a_bank_that_does_not_exist_reports_itself_rather_than_being_empty() -> void:
	# Empty and broken must not look alike: an empty bank silently generates nothing, and a
	# gate comparing nothing to nothing passes.
	var bank := SoundBank.load_from(&"no_such_bank")
	assert_array(bank.problems()).is_not_empty()
	assert_bool(bank.has_cue(Sfx.id_of(Sfx.Cue.HIT))).is_false()


func test_a_missing_shape_is_empty_rather_than_a_default() -> void:
	var bank := SoundBank.load_from(&"gb16")
	assert_dict(bank.shape(&"kazoo")).is_empty()


func test_a_voice_refuses_settings_that_would_not_make_a_sound() -> void:
	var style := _style()
	style.id = &""
	assert_array(style.problems()).is_not_empty()

	style = _style()
	style.tone = &"kazoo"
	assert_array(style.problems()).is_not_empty()

	style = _style()
	style.mix_rate = 100
	assert_array(style.problems()).is_not_empty()

	style = _style()
	style.gain = 0.0
	assert_array(style.problems()).is_not_empty()

	style = _style()
	style.quantise_steps = 2
	assert_array(style.problems()).is_not_empty()

	style = _style()
	style.bank_id = &""
	assert_array(style.problems()).is_not_empty()

	assert_array(_style().problems()).is_empty()
