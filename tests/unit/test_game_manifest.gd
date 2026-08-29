extends GdUnitTestSuite
## Every shipped game must start somewhere real, and a manifest that does not must say so.
##
## The failure this prevents is quiet: a misspelt spawn drops the player at tile (1,1) with a
## push_error nobody is watching for, and it reads as a level-design mistake in the map rather
## than as a typo in the manifest. Same for a player character with no generated art - the
## game boots and the player is invisible.

const CONFIG := "res://data/game_config.tres"


func _valid() -> GameManifest:
	var manifest := GameManifest.new()
	manifest.id = &"fixture"
	manifest.start_map = &"quest_village"
	manifest.start_spawn = &"start"
	manifest.player_character = &"quest_wanderer"
	manifest.config = load(CONFIG) as GameConfig
	return manifest


func test_every_shipped_game_starts_somewhere_real() -> void:
	var all := GameSelect.manifests()
	# An instrument that cannot fail is not a check: with no manifests found, the loop below
	# examines nothing and passes.
	assert_bool(all.is_empty()).is_false()
	for manifest in all:
		assert_array(manifest.problems()).is_empty()


func test_a_valid_manifest_has_no_problems() -> void:
	# The control. Without it, every assertion below could be satisfied by a problems() that
	# complains about everything.
	assert_array(_valid().problems()).is_empty()


func test_a_spawn_that_does_not_exist_is_reported() -> void:
	var manifest := _valid()
	manifest.start_spawn = &"nowhere"
	var problems := manifest.problems()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("nowhere")


func test_a_player_character_with_no_generated_art_is_reported() -> void:
	# Art is generated per style and the style comes from the map, so this can only be
	# answered once both are known - which is why it lives here and not on CharacterSpec.
	var manifest := _valid()
	manifest.player_character = &"not_a_character"
	var problems := manifest.problems()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("not_a_character")


func test_a_start_map_that_does_not_load_is_reported_without_chasing_further() -> void:
	var manifest := _valid()
	manifest.start_map = &"no_such_map"
	# One problem, not four: with no map there is no style, so "the character has no art"
	# would be a second complaint about the same missing fact.
	assert_int(manifest.problems().size()).is_equal(1)


func test_a_missing_config_is_reported() -> void:
	var manifest := _valid()
	manifest.config = null
	assert_str("\n".join(manifest.problems())).contains("config")


func test_a_game_without_hooks_is_normal() -> void:
	# Most games are expressible in maps and dialog, with no code at all,
	# and "no hooks" must not read as "broken game".
	var manifest := _valid()
	assert_object(manifest.new_hooks()).is_null()
	assert_array(manifest.problems()).is_empty()


func test_a_hooks_script_is_instantiated_as_game_code() -> void:
	# The seam, against a real Script rather than a mock: this is the whole path from a line
	# in a .tres to an object the world will call.
	var manifest := _valid()
	manifest.hooks = load("res://tests/helpers/stub_hooks.gd") as Script
	assert_object(manifest.new_hooks()).is_not_null()
	assert_array(manifest.problems()).is_empty()


func test_each_call_gets_a_fresh_hooks_instance() -> void:
	# Shared hooks would carry state from one run of a game into the next, which is a save
	# bug that only appears on the second playthrough.
	var manifest := _valid()
	manifest.hooks = load("res://tests/helpers/stub_hooks.gd") as Script
	assert_object(manifest.new_hooks()).is_not_same(manifest.new_hooks())


func test_a_script_that_is_not_a_gamehooks_is_reported() -> void:
	# Named in the manifest, so a typo picks up some other script and the game boots with
	# hooks that are silently never called.
	var manifest := _valid()
	manifest.hooks = load("res://scripts/util/content_scan.gd") as Script
	assert_str("\n".join(manifest.problems())).contains("GameHooks")


func test_a_grid_step_that_is_not_the_maps_tile_size_is_reported() -> void:
	# The one genuinely wrong value this mode can be given, and it is invisible from either
	# side alone: the config knows the step and the map knows the tile, and only a manifest
	# holds both. Left unchecked it lands the player between tiles, increasingly, forever.
	var manifest := _valid()
	var config := (manifest.config as GameConfig).duplicate() as GameConfig
	config.grid_step_pixels = 24
	manifest.config = config
	assert_str("\n".join(manifest.problems())).contains("lands the player between them")

func test_a_grid_step_matching_the_maps_tiles_is_accepted() -> void:
	# The control: without it, a check that complained about every grid step would pass above.
	var manifest := _valid()
	var config := (manifest.config as GameConfig).duplicate() as GameConfig
	config.grid_step_pixels = 16
	manifest.config = config
	assert_array(manifest.problems()).is_empty()


func test_a_voice_whose_cues_were_never_generated_is_reported() -> void:
	# The failure this catches is a game that boots perfectly and is silent, which reads as
	# "sound is not built yet" rather than as a missing file - the same reason the manifest
	# already checks the player's generated ART instead of trusting the name.
	var manifest := load("res://data/games/quest.tres") as GameManifest
	assert_array(manifest.problems()).is_empty()

	var orphan := manifest.duplicate() as GameManifest
	var voice := SoundStyle.new()
	voice.id = &"never_generated"
	voice.bank_id = &"gb16"
	voice.tone = &"square"
	orphan.sound_style = voice
	# Matched on the CUE message rather than on the voice's name, which appears in the theme's
	# message too - so the looser match passed while the rule under test was switched off. The
	# condition being tested has to be the only thing that can satisfy the assertion.
	var reported := false
	for p in orphan.problems():
		if p.contains("has no generated cues"):
			reported = true
	assert_bool(reported).override_failure_message(
		"a voice with no generated cues passed validation: %s" % [orphan.problems()]).is_true()


func test_a_game_with_no_voice_at_all_is_still_valid() -> void:
	# Silence is a legal shape, exactly as a null combat is a game that cannot fight.
	var silent := (load("res://data/games/quest.tres") as GameManifest).duplicate() as GameManifest
	silent.sound_style = null
	# The theme goes with the voice. A game keeping one while dropping the other is not silent,
	# it is a title naming a tune that cannot be played - which problems() reports, and the
	# test below is the one that proves it.
	silent.title_music = &""
	silent.battle_music = &""
	silent.victory_music = &""
	assert_array(silent.problems()).is_empty()


## The three tunes a manifest can name, so every check below runs once per field rather than
## once for the one that was written first. A fourth field added without its own row here
## fails nothing, which is why the LOOP in problems() is a loop.
func _music_fields() -> Array[StringName]:
	return [&"title_music", &"battle_music", &"victory_music"]


func test_a_theme_with_no_voice_to_play_it_is_reported() -> void:
	for field in _music_fields():
		var mute := (load("res://data/games/quest.tres") as GameManifest).duplicate() as GameManifest
		mute.sound_style = null
		# Only the field under test keeps its tune, so the report has one possible cause. With
		# all three left set, a check that only ever looked at the first would pass all three.
		for other in _music_fields():
			if other != field:
				mute.set(other, &"")
		assert_array(mute.problems()).override_failure_message(
			"%s names a theme with nothing to play it, and nothing said so" % field).is_not_empty()


func test_a_theme_nobody_generated_is_reported() -> void:
	# The same shape as the missing-cues check beside it: a game naming a tune that was never
	# rendered is a silence, and silence is legal here - so a misspelling is invisible unless
	# somebody looks.
	for field in _music_fields():
		var wrong := (load("res://data/games/quest.tres") as GameManifest).duplicate() as GameManifest
		wrong.set(field, &"no_such_tune")
		assert_array(wrong.problems()).override_failure_message(
			"%s names a tune nobody generated and it passed" % field).is_not_empty()


func _member(id: StringName) -> PartyMemberDef:
	var out := PartyMemberDef.new()
	out.id = id
	out.name = "Rook"
	out.character = &"quest_wanderer"
	return out


func test_a_game_with_no_party_is_the_normal_shape() -> void:
	# The control, and the template's own default: a game with no party is a game with a party
	# of one, which is Dragon Quest I's shape rather than an absence.
	var manifest := _valid()
	assert_array(manifest.party).is_empty()
	assert_array(manifest.problems()).is_empty()


func test_a_party_member_is_checked_the_way_the_leader_is() -> void:
	var manifest := _valid()
	manifest.combat = load("res://data/combat/quest_combat.tres") as CombatDef
	var broken := _member(&"scrapper")
	broken.name = ""
	manifest.party = [broken]
	assert_array(manifest.problems()).is_not_empty()


func test_a_party_member_whose_art_was_never_generated_is_reported() -> void:
	# The player_character check, looped. A member whose sheet does not exist for the START
	# map's style is an invisible fighter, which reads as a broken screen rather than as
	# missing content - and art is per style, so the question is only answerable here.
	var manifest := _valid()
	manifest.combat = load("res://data/combat/quest_combat.tres") as CombatDef
	var ghost := _member(&"scrapper")
	ghost.character = &"nobody_drew_this"
	manifest.party = [ghost]
	var faults := manifest.problems()
	assert_array(faults).is_not_empty()
	assert_str("\n".join(faults)).contains("no generated art")


func test_the_same_member_listed_twice_is_reported() -> void:
	# Two members under one id means one save record for two people, and the second would
	# silently inherit the first's health.
	var manifest := _valid()
	manifest.combat = load("res://data/combat/quest_combat.tres") as CombatDef
	manifest.party = [_member(&"scrapper"), _member(&"scrapper")]
	assert_array(manifest.problems()).is_not_empty()


func test_a_party_with_no_combat_definition_is_reported() -> void:
	# Members grow on a curve, and without a CombatDef there is no curve for them to grow on -
	# so a party here is a manifest that could never build the fight it implies.
	var manifest := _valid()
	manifest.combat = null
	manifest.party = [_member(&"scrapper")]
	assert_array(manifest.problems()).is_not_empty()


func test_a_valid_party_is_accepted() -> void:
	var manifest := _valid()
	manifest.combat = load("res://data/combat/quest_combat.tres") as CombatDef
	manifest.party = [_member(&"scrapper")]
	assert_array(manifest.problems()).is_empty()
