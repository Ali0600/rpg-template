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


func test_the_walk_returns_every_match_sorted_and_nothing_else() -> void:
	# Asserting the exact array rather than a size covers three things at once: the nested
	# file is present, the .txt beside it is not, and the order is the sorted one rather
	# than whatever the filesystem happened to hand back.
	assert_array(ContentScan.files_of(DIR, "json")).is_equal([NESTED, TOP])


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
