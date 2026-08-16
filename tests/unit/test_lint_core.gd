extends GdUnitTestSuite
## Proves each source rule fires on a known-bad input, and stays quiet on a clean one.
##
## A linter that has only ever passed is decoration: it cannot tell "the repo is clean"
## from "the scan is broken". Every rule therefore has a fixture under
## tests/fixtures/lint/ that must produce a hit, plus near-miss code in the same fixture
## that must NOT - a rule that fires on everything gets disabled by the next person.
##
## Fixtures are .txt so the repo's own gates never compile or scan them.

const FIXTURE_DIR := "res://tests/fixtures/lint/"
## A path under scripts/world: subject to every rule, exempt from none.
const SUBJECT := "res://scripts/world/fixture_subject.gd"
## A path under games/: template code plus the one rule that applies only to game code.
const GAME_SUBJECT := "res://games/example/example_hooks.gd"
## Passed explicitly so the rule stays pure. The live list comes from project.godot.
const AUTOLOADS: Array[String] = ["EventBus", "GameState", "Router"]

## Which path each fixture is scanned AS. It is not decoration: the autoload rule fires only
## for game code, so its fixture has to arrive from under games/ or it proves nothing.
func _fixture_subjects() -> Dictionary:
	return {
		"bad_rng.gd.txt": SUBJECT,
		"bad_direction.gd.txt": SUBJECT,
		"bad_color.gd.txt": SUBJECT,
		"bad_autoload.gd.txt": GAME_SUBJECT,
	}

func _autoload_hits(hits: Array[String]) -> Array[String]:
	return hits.filter(func(h: String) -> bool: return h.contains(LintCore.RULE_AUTOLOAD))

func _load(name: String) -> String:
	var text := FileAccess.get_file_as_string(FIXTURE_DIR + name)
	# A fixture that failed to load would make every "no hits" assertion pass.
	assert_bool(text.is_empty()).is_false()
	return text

func _rules_hit(hits: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for h in hits:
		for rule in LintCore.rule_names():
			if h.contains(": %s: " % rule) and not out.has(rule):
				out.append(rule)
	return out

## Directories in the repo that are not this project's source.
const NOT_OURS: Array[String] = ["addons"]

func _top_level_dirs() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with(".") and not NOT_OURS.has(name):
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

func test_every_top_level_source_directory_is_scanned() -> void:
	# The guard on the list itself. A new top-level directory holding .gd files used to
	# escape the linter, the per-file parse gate and the whole-project compile at once, and
	# nothing said so - the files simply stopped being covered. This turns that into a
	# failure the moment the directory appears.
	var dirs := _top_level_dirs()
	# An instrument that cannot fail is not a check: if res:// listed nothing, every
	# assertion below would pass having examined no directories at all.
	assert_bool(dirs.is_empty()).is_false()
	var missed: Array[String] = []
	for name in dirs:
		var root := "res://" + name
		if not ContentScan.files_of(root, "gd").is_empty() and not LintCore.SOURCE_ROOTS.has(root):
			missed.append(root)
	assert_array(missed).is_empty()

func test_every_source_root_exists() -> void:
	# The mirror failure: a directory renamed out from under the list. The tools would walk
	# nothing there and report success on what remained.
	var missing: Array[String] = []
	for root in LintCore.SOURCE_ROOTS:
		if not DirAccess.dir_exists_absolute(root):
			missing.append(root)
	assert_array(missing).is_empty()

func test_the_suite_is_compiled_but_not_linted() -> void:
	# An asymmetry that is invisible at the point it matters: tests/ must be parsed and
	# compiled like everything else, but cannot be linted, because proving a rule fires
	# means writing the very string the rule bans - this file contains "left" on purpose.
	assert_bool(LintCore.SOURCE_ROOTS.has("res://tests")).is_true()
	assert_bool(LintCore.lint_roots().has("res://tests")).is_false()
	assert_array(LintCore.lint_roots()).contains(["res://scripts", "res://tools"])

func test_every_rule_has_a_fixture_that_proves_it_fires() -> void:
	# The structural guard: adding a rule without a known-bad input leaves it unproven, and
	# this fails the moment rule_names() grows past the fixtures.
	var fired: Array[String] = []
	for fixture: String in _fixture_subjects().keys():
		var subject: String = _fixture_subjects()[fixture]
		for rule in _rules_hit(LintCore.scan_text(subject, _load(fixture), AUTOLOADS)):
			if not fired.has(rule):
				fired.append(rule)
	fired.sort()
	var expected := LintCore.rule_names()
	expected.sort()
	assert_array(fired).is_equal(expected)

func test_clean_source_produces_no_hits() -> void:
	var hits := LintCore.scan_text(SUBJECT, _load("clean.gd.txt"))
	assert_array(hits).is_empty()

func test_global_rng_calls_are_reported_and_seeded_ones_are_not() -> void:
	var hits := LintCore.scan_text(SUBJECT, _load("bad_rng.gd.txt"))
	var rng_hits := hits.filter(func(h: String) -> bool: return h.contains(LintCore.RULE_RNG))
	# randi(), randf_range(), pick_random() - and NOT rng.randi_range()/rng.randf().
	assert_int(rng_hits.size()).is_equal(3)

func test_a_method_on_a_seeded_generator_is_not_a_violation() -> void:
	var hits := LintCore.scan_text(SUBJECT, "var a := rng.randf_range(0.0, 1.0)\n")
	assert_array(hits).is_empty()

func test_direction_words_are_only_reported_inside_string_literals() -> void:
	# The word "left" in a comment or inside a compound name is not a raw direction.
	assert_array(LintCore.scan_text(SUBJECT, "# facing left when idle\n")).is_empty()
	assert_array(LintCore.scan_text(SUBJECT, "var a := \"walk_left\"\n")).is_empty()
	assert_int(LintCore.scan_text(SUBJECT, "var a := \"left\"\n").size()).is_equal(1)

func test_a_hash_inside_a_string_does_not_truncate_the_line() -> void:
	# If '#' were stripped blindly, everything after it would go unscanned - the quiet way
	# a scan stops covering the code it claims to cover.
	var hits := LintCore.scan_text(SUBJECT, "var s := \"# not a comment\"; var d := \"up\"\n")
	assert_int(hits.size()).is_equal(1)
	assert_str(hits[0]).contains(LintCore.RULE_DIRECTION)

func test_colour_literals_are_allowed_where_art_is_generated() -> void:
	var text := _load("bad_color.gd.txt")
	assert_bool(LintCore.scan_text(SUBJECT, text).is_empty()).is_false()
	# spritegen and data are where colour is supposed to be written down.
	assert_array(LintCore.scan_text("res://scripts/spritegen/tile_gen.gd", text)).is_empty()
	assert_array(LintCore.scan_text("res://scripts/data/sprite_style.gd", text)).is_empty()

func test_dir_module_may_name_directions() -> void:
	# The exemption that makes the rule usable: one file owns the vocabulary.
	var text := "var names := {\"down\": 0, \"left\": 1}\n"
	assert_bool(LintCore.scan_text(SUBJECT, text).is_empty()).is_false()
	assert_array(LintCore.scan_text("res://scripts/util/dir.gd", text)).is_empty()

func test_every_violation_is_reported_not_just_the_first() -> void:
	# A scan that stops at the first hit reports one problem and hides four. The fixture
	# has several of each kind on purpose.
	var text := "var a := \"left\"\nvar b := \"right\"\nvar c := \"up\"\n"
	assert_int(LintCore.scan_text(SUBJECT, text).size()).is_equal(3)

func test_hits_name_the_file_and_line() -> void:
	var hits := LintCore.scan_text(SUBJECT, "var ok := 1\nvar bad := \"down\"\n")
	assert_int(hits.size()).is_equal(1)
	assert_str(hits[0]).starts_with(SUBJECT + ":2: ")

func test_game_code_may_not_name_an_autoload() -> void:
	# The fixture has two singletons used as singletons, and four near-misses: a local whose
	# name resembles one, the name inside a string, the name inside a comment, and the
	# sanctioned GameContext call that replaces it.
	var hits := LintCore.scan_text(GAME_SUBJECT, _load("bad_autoload.gd.txt"), AUTOLOADS)
	assert_int(_autoload_hits(hits).size()).is_equal(2)

func test_template_code_may_name_an_autoload() -> void:
	# Not a general ban. world_scene.gd names GameState on purpose: it is the file that owns
	# turning an effect into live state, which is exactly why game code does not have to.
	var hits := LintCore.scan_text(SUBJECT, _load("bad_autoload.gd.txt"), AUTOLOADS)
	assert_array(_autoload_hits(hits)).is_empty()

func test_the_autoload_rule_needs_the_live_list_to_check_anything() -> void:
	# Called with no names the rule cannot fire, which is a fail-open - so tools/lint_rules.gd
	# refuses to run at all when project.godot yields no autoloads, rather than reporting a
	# clean scan of a check that never happened.
	var hits := LintCore.scan_text(GAME_SUBJECT, _load("bad_autoload.gd.txt"))
	assert_array(_autoload_hits(hits)).is_empty()

func test_the_autoload_names_are_read_from_the_project_not_typed() -> void:
	# The one derivation both the linter and compile_all use. A typed copy would go stale the
	# day a singleton is added, and the file naming it would silently stop being compiled.
	var names := LintCore.autoload_names()
	assert_bool(names.is_empty()).is_false()
	assert_array(names).contains(["GameState", "Router", "EventBus"])
