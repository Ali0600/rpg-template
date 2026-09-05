extends GdUnitTestSuite
## The command, run as a command.
##
## GameScaffold is proven without a disk and the boot gate is proven without an engine spawn;
## neither says anything about a path, a flag, an extension or an argument. This spawns the real
## engine the way tests/unit/test_map_io.gd does, and reads what landed.
##
## It asserts the FILES, never the exit code alone. The engine exits 0 when `-s` names a script
## that is not there - two ERROR lines to stderr and a clean status - so a renamed tool would sail
## through a check that only looked at the status. That is Plan G's finding, and this is where it
## bites: the wizard is not a check.sh step, so test_ci_paths.gd's derivation cannot cover it.
##
## No --fixed-fps: the tool quits in its first frame, and tools/_engine.sh says the flag is for
## things driven by frames.

const SCRATCH := "user://new_game_test"

## Derived, and compared against what was there BEFORE rather than against a literal list of the
## games this project happens to ship: the wizard invites scaffolding a game into this repo, and a
## suite that spelled the shipped set in would go red over somebody else's game.
var _id := ""
var _games_before: Array[String] = []


func before_test() -> void:
	_id = GameFixtures.unused_game_id("proof")
	_games_before = GameSelect.ids()


func after_test() -> void:
	_sweep(SCRATCH)
	# The redirect-in-effect assertion, test_settings.gd's pattern. Every run here writes under
	# user://, and the one thing that must never be true is that a game landed in the project.
	assert_array(GameSelect.ids()).override_failure_message(
		"a suite run left a game behind in data/games").contains_exactly_in_any_order(_games_before)


func _sweep(path: String) -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(path))
	if dir == null:
		return
	dir.list_dir_begin()
	var found := dir.get_next()
	while found != "":
		if dir.current_is_dir():
			_sweep("%s/%s" % [path, found])
		else:
			dir.remove(found)
		found = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The exit code and everything the run said, so a refusal can be asserted by its wording rather
## than by the fact that something somewhere went wrong.
func _run(args: Array) -> Array:
	var argv: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tools/new_game.gd"]
	argv.append_array(args)
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), argv, out, true)
	return [code, "\n".join(PackedStringArray(out))]


func test_it_writes_a_game_the_game_itself_accepts() -> void:
	var result := _run(["--out=%s" % SCRATCH, "--id=%s" % _id, "--style=gb16", "--hooks"])
	assert_int(int(result[0])).override_failure_message(str(result[1])).is_equal(0)
	# The files, not the status. A tool that is not there exits 0 and writes nothing.
	for shape: String in ["data/games/%s.tres", "data/maps/%s_start.json",
			"data/dialog/%s_hello.json", "games/%s/%s_hooks.gd",
			"tests/fixtures/qa/%s/boots.json"]:
		var path := shape.replace("%s", _id)
		assert_bool(FileAccess.file_exists("%s/%s" % [SCRATCH, path])).override_failure_message(
			"%s was not written:\n%s" % [path, result[1]]).is_true()
	# It says which arbitrary defaults it picked, because a default chosen by sort order is
	# deterministic and arbitrary, and the honest thing to do with an arbitrary choice is say it.
	assert_str(str(result[1])).contains("greeted by")


func test_a_game_that_varies_nothing_is_not_handed_a_config_of_its_own() -> void:
	_run(["--out=%s" % SCRATCH, "--id=%s" % _id, "--style=gb16"])
	assert_bool(FileAccess.file_exists("%s/data/config/%s.tres" % [SCRATCH, _id])
		).override_failure_message("the tool wrote a config nobody asked for").is_false()
	var stepper := GameFixtures.unused_game_id("stepper")
	var result := _run(["--out=%s" % SCRATCH, "--id=%s" % stepper, "--style=gb16",
		"--movement=grid"])
	assert_int(int(result[0])).override_failure_message(str(result[1])).is_equal(0)
	assert_bool(FileAccess.file_exists("%s/data/config/%s.tres" % [SCRATCH, stepper])
		).override_failure_message("a game that moves an axis has nowhere to say so").is_true()


func test_it_will_not_write_over_a_game_that_is_already_where_it_is_writing() -> void:
	# The id check reads data/games, so it says nothing about a --out that already holds a game of
	# that name. Every path is tested before any file is written, because a refusal half way
	# through leaves a game that is neither there nor absent while its id is taken by the half
	# that landed.
	assert_int(int(_run(["--out=%s" % SCRATCH, "--id=%s" % _id, "--style=gb16"])[0])).is_equal(0)
	var before := FileAccess.get_file_as_string("%s/data/games/%s.tres" % [SCRATCH, _id])
	var again := _run(["--out=%s" % SCRATCH, "--id=%s" % _id, "--style=gb16", "--title=Something Else"])
	assert_int(int(again[0])).override_failure_message(
		"the second run overwrote the first:\n%s" % again[1]).is_equal(1)
	assert_str(str(again[1])).contains("is already there")
	assert_str(FileAccess.get_file_as_string("%s/data/games/%s.tres" % [SCRATCH, _id])
		).override_failure_message("the refused run still changed the game that was there"
		).is_equal(before)


func test_the_space_form_of_a_flag_is_refused_by_name() -> void:
	# A value written after a space lands in a positional slot while the option keeps its default,
	# so the run does something nobody asked for. Refused out loud rather than ignored.
	var result := _run(["--out=%s" % SCRATCH, "--id", _id])
	assert_int(int(result[0])).override_failure_message(
		"--id proof was accepted:\n%s" % result[1]).is_equal(1)
	assert_str(str(result[1])).contains("--id=<value>")
	assert_bool(FileAccess.file_exists("%s/data/games/%s.tres" % [SCRATCH, _id])).is_false()


func test_it_refuses_to_write_a_game_with_no_name() -> void:
	var result := _run(["--out=%s" % SCRATCH])
	assert_int(int(result[0])).is_equal(1)
	assert_str(str(result[1])).contains("a game needs an id")


func test_it_refuses_to_stand_on_a_game_that_is_already_there() -> void:
	# Into the project itself, deliberately: the id it is refusing is the one that ships, and the
	# refusal has to be reached before a single file is written. If it were not, this test would
	# leave a second game in data/games and after_test would say so.
	var taken := _games_before[0]
	var result := _run(["--id=%s" % taken])
	assert_int(int(result[0])).override_failure_message(
		"'%s' was overwritten:\n%s" % [taken, result[1]]).is_equal(1)
	assert_str(str(result[1])).contains("already a game called '%s'" % taken)


func test_a_made_up_game_name_is_never_one_that_is_already_there() -> void:
	# Asserted against a name that IS taken, because for any free name the derivation and a plain
	# constant return the same thing: the shipped set of games equalises them, and a mutant that
	# stopped deriving would survive while the suites quietly collided with a real game.
	var taken := _games_before[0]
	var made := GameFixtures.unused_game_id(taken)
	assert_str(made).override_failure_message(
		"a suite would be handed the name of a game that already exists").is_not_equal(taken)
	assert_bool(_games_before.has(made)).is_false()


func test_it_refuses_art_this_project_does_not_have_before_writing_anything() -> void:
	var result := _run(["--out=%s" % SCRATCH, "--id=%s" % _id, "--style=nope"])
	assert_int(int(result[0])).is_equal(1)
	assert_str(str(result[1])).contains("no art style 'nope'")
	assert_bool(FileAccess.file_exists("%s/data/maps/%s_start.json" % [SCRATCH, _id])
		).override_failure_message("it wrote a room for a game it then refused to make").is_false()
