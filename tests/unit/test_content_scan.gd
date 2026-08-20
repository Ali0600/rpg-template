extends GdUnitTestSuite
## Proves the one content walk sees what the four walks it replaced disagreed about.
##
## The defect it exists to prevent: Registry recursed into subdirectories and the art
## generator did not, so a character spec filed one level down was registered by the game,
## never generated, and the art-drift gate compared nothing and reported green. A walk that
## silently skips half the content turns every gate built on it into a subset of its claim.

const DIR := "res://tests/fixtures/content"
const TOP := "res://tests/fixtures/content/top.json"
const NESTED := "res://tests/fixtures/content/nested/deep.json"


func test_a_file_in_a_subdirectory_is_found() -> void:
	assert_array(ContentScan.files_of(DIR, "json")).contains([NESTED])


func test_the_walk_returns_every_match_and_nothing_else() -> void:
	# The exact array rather than a size: the nested file is present and the .txt beside it
	# is not. The ORDER is pinned separately, below, for a reason worth reading.
	assert_array(ContentScan.files_of(DIR, "json")).is_equal([NESTED, TOP])


func test_paths_come_back_in_sorted_order() -> void:
	# Proven over a list rather than over a directory, because DirAccess order cannot be
	# forced from a test. Aiming at the sort inside the walk killed the mutant on macOS and
	# let it SURVIVE on the Ubuntu runner - ext4 handed back an already-alphabetical listing,
	# so the assertion was decoration on the one machine that gates the merge.
	var jumbled: Array[String] = ["res://data/b.tres", "res://data/a.tres", "res://data/a/z.tres"]
	assert_array(ContentScan.in_order(jumbled)).is_equal([
		"res://data/a.tres", "res://data/a/z.tres", "res://data/b.tres",
	])


func test_ordering_leaves_the_caller_s_list_alone() -> void:
	var given: Array[String] = ["res://data/b.tres", "res://data/a.tres"]
	ContentScan.in_order(given)
	assert_array(given).is_equal(["res://data/b.tres", "res://data/a.tres"])


func test_an_extension_that_matches_nothing_is_empty() -> void:
	assert_array(ContentScan.files_of(DIR, "tscn")).is_empty()


func test_a_missing_directory_is_empty_rather_than_a_crash() -> void:
	# Callers scan optional content roots - a game with no audio is not an error.
	assert_array(ContentScan.files_of("res://tests/fixtures/no_such_dir", "json")).is_empty()


func test_resources_follows_the_same_walk_as_files() -> void:
	# The two entry points must agree, because the generator uses one and the gate the
	# other; when they diverged, the gate checked art the generator had not written.
	var styles := ContentScan.files_of("res://data/styles", "tres")
	assert_int(ContentScan.resources("res://data/styles").size()).is_equal(styles.size())
	assert_bool(styles.is_empty()).is_false()


func test_a_packed_entry_resolves_to_the_source_file_it_stands_for() -> void:
	# An exported build does not contain the files you put in it. A .tres is packed beside a
	# .remap, and every IMPORTED asset - png, wav, ogg - is packed as its .import sidecar plus
	# the engine's cached copy, with the original left out. A walk looking for "ogg" therefore
	# finds nothing in a shipped build while working perfectly here.
	#
	# Tested as a pure function over a NAME rather than with a fixture on disk: an orphan
	# .import with no source confuses the importer, and any new file under the fixture root
	# breaks the walk's own exact-array assertion.
	assert_str(ContentScan.source_name("footstep.ogg.import")).is_equal("footstep.ogg")
	assert_str(ContentScan.source_name("hero.png.import")).is_equal("hero.png")
	assert_str(ContentScan.source_name("quest.tres.remap")).is_equal("quest.tres")


func test_a_name_that_is_already_the_source_is_left_alone() -> void:
	assert_str(ContentScan.source_name("footstep.ogg")).is_equal("footstep.ogg")
	assert_str(ContentScan.source_name("map.json")).is_equal("map.json")
	# Not a suffix, so not stripped - the check is on the end of the name, not on it appearing.
	assert_str(ContentScan.source_name("important.wav")).is_equal("important.wav")


func test_a_source_and_its_sidecar_are_one_file_not_two() -> void:
	# In the editor BOTH exist - hit.wav beside hit.wav.import - so resolving the sidecar to
	# the file it stands for makes the same sound appear twice. In an exported build only the
	# sidecar is packed and it appears once. A walk that counts differently in the two places
	# is worse than one that is wrong in both, because it passes wherever you are looking.
	var packed: Array[String] = ["res://a/hit.wav", "res://a/hit.wav", "res://a/talk.wav"]
	assert_array(ContentScan.once_each(packed)).is_equal(
		["res://a/hit.wav", "res://a/talk.wav"] as Array[String])


func test_generated_audio_is_listed_once_each() -> void:
	# The real directory, because that is where it went wrong: the fixture above proves the
	# function, this proves it is actually wired into the walk.
	var cues := ContentScan.files("res://assets/generated/dusk16/sfx", ["wav"])
	assert_int(cues.size()).override_failure_message(
		"the sfx walk returned %d entries for %d cues" % [cues.size(), Sfx.ids().size()]
	).is_equal(Sfx.ids().size())
