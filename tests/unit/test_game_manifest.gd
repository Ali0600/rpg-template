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
