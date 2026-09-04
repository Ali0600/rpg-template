extends GdUnitTestSuite
## The tuning file's own validation.
##
## Every number here is one a designer edits in a text field, so every one of them has a value
## that breaks the game quietly. `problems()` is where that is said out loud, at load, instead
## of showing up as a character who cannot move.

func test_a_game_with_no_save_slots_is_reported() -> void:
	# Zero slots is a pause menu whose Save and Load pages have nothing on them - a screen
	# that opens onto nothing reads as a broken menu, not as a configuration choice.
	var config := GameConfig.new()
	config.save_slots = 0
	assert_str(", ".join(config.problems())).contains("save_slots")

func test_the_shipped_config_offers_at_least_one_slot() -> void:
	# The control: a validator that complained about everything would pass the test above and
	# fail the game.
	var config := load("res://data/game_config.tres") as GameConfig
	assert_object(config).is_not_null()
	assert_int(config.save_slots).is_greater_equal(1)
	assert_array(config.problems()).is_empty()

func test_a_save_policy_nobody_implements_is_reported() -> void:
	# A typo'd policy FAILS THE BUILD rather than falling back, the npc `behavior` rule and for
	# its reason: silently reading as "anywhere" is a save point nobody can find beside a Save
	# row nobody removed, and both halves look correct on their own.
	var config := GameConfig.new()
	config.save_policy = &"at-point"
	assert_str(", ".join(config.problems())).contains("save_policy")

func test_both_shipped_save_policies_are_accepted() -> void:
	# The control the refusal above needs: a validator that rejected everything would pass that
	# test and fail every game.
	for policy: StringName in GameConfig.SAVE_POLICIES:
		var config := GameConfig.new()
		config.save_policy = policy
		assert_array(config.problems()).override_failure_message(
			"the config refused '%s', which is one of its own legal policies" % policy).is_empty()

func test_a_config_that_says_nothing_saves_anywhere() -> void:
	# The default is what every game recorded before this field existed was playing, so a
	# config written then must still mean the same thing now.
	assert_str(String(GameConfig.new().save_policy)).is_equal(String(GameConfig.SAVE_ANYWHERE))


## The pixel numbers the whole game was tuned against, written as LITERALS. Derived from the
## fields they check, they would be satisfied by construction - the expectation has to come from
## somewhere the code under test cannot reach, and this is the table that shipped.
const AT_16 := {"walk": 48.0, "reach": 12.0, "body": Vector2(10.0, 6.0), "idle": 1.0, "foot": 14.0}
const AT_32 := {"walk": 96.0, "reach": 24.0, "body": Vector2(20.0, 12.0), "idle": 2.0, "foot": 28.0}

## The seven names this milestone removed. A .tres carrying one of them is the trap below.
const GONE: Array[String] = ["walk_speed", "interact_reach", "body_size", "idle_speed_epsilon",
	"grid_step_pixels", "camera_smoothing", "footstep_pixels"]


func _assert_pixels(tile: int, want: Dictionary) -> void:
	var config := GameConfig.new().at(tile)
	assert_float(config.walk_speed_px()).override_failure_message(
		"at %dpx tiles the walk is %f, not %f" % [tile, config.walk_speed_px(), want["walk"]]
		).is_equal_approx(want["walk"], 0.001)
	assert_float(config.interact_reach_px()).is_equal_approx(want["reach"], 0.001)
	assert_vector(config.body_size_px()).is_equal_approx(want["body"], Vector2(0.001, 0.001))
	assert_float(config.idle_epsilon_px()).is_equal_approx(want["idle"], 0.001)
	assert_float(config.footstep_px()).is_equal_approx(want["foot"], 0.001)


func test_the_defaults_are_the_same_distances_they_always_were() -> void:
	# The whole milestone in one assertion. These are the numbers the template shipped in pixels
	# before the fields were stated in tiles; every one of them is a sum of powers of two over 16,
	# so the multiply is exact and the 24 scripted sessions - whose legs are counted in frames -
	# play out identically rather than approximately.
	_assert_pixels(16, AT_16)


func test_the_same_config_at_32px_is_what_the_demo_used_to_write_by_hand() -> void:
	# The demo's file used to carry these five doubled numbers with a header explaining why. It
	# carries none of them now: at 32px tiles the template's own defaults ARE those values, which
	# is the point of stating them in tiles and the reason that file could be emptied.
	_assert_pixels(32, AT_32)


func test_a_config_nobody_bound_says_so_instead_of_guessing() -> void:
	# Asking an unbound config for a distance is a bug in the caller - the world binds on entering
	# every map - so it is loud. A fallback that fires quietly is indistinguishable from a missing
	# feature, which is the whole reason this is not simply defaulted to 16.
	var loose := GameConfig.new()
	assert_float(loose.walk_speed_px()).is_equal_approx(48.0, 0.001)


func test_binding_leaves_the_shipped_resource_alone() -> void:
	# at() duplicates. Two maps drawn at different scales bind the same authored resource, and if
	# it bound in place the second would silently re-scale the first.
	var shipped := load("res://data/game_config.tres") as GameConfig
	var big := shipped.at(32)
	assert_float(big.walk_speed_px()).is_equal_approx(96.0, 0.001)
	assert_float(shipped.at(16).walk_speed_px()).override_failure_message(
		"binding at 32 changed what the shipped resource answers at 16").is_equal_approx(48.0, 0.001)


func test_the_shipped_file_names_no_field_this_milestone_removed() -> void:
	# GODOT SILENTLY DROPS UNKNOWN .tres KEYS - no error, no warning, no failed load. A rename
	# that forgot this file would leave every value at its script default, and here that is
	# INVISIBLE, because the defaults are numerically right. So the gate cannot be "the values are
	# correct" (they are, either way); it has to be that the file no longer names the old fields.
	var text := FileAccess.get_file_as_string("res://data/game_config.tres")
	assert_str(text).is_not_empty()
	var stale: Array[String] = []
	for line in text.split("\n"):
		if line.begins_with(";"):
			continue
		for name in GONE:
			if line.begins_with(name + " ="):
				stale.append(line)
	assert_array(stale).override_failure_message(
		"data/game_config.tres still assigns fields that no longer exist, and Godot drops them "
		+ "in silence:\n  " + "\n  ".join(stale)).is_empty()


func test_grid_stepping_is_a_tile_or_it_is_off() -> void:
	# The step cannot disagree with the map any more: it IS the tile. That is what let the
	# manifest's cross-check go, and what makes "a step that is not a tile" unrepresentable
	# rather than refused.
	var off := GameConfig.new().at(16)
	assert_int(off.grid_step_px()).is_equal(0)
	var on := GameConfig.new().at(32)
	on.grid_step = true
	assert_int(on.grid_step_px()).is_equal(32)
