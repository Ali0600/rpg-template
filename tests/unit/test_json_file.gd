extends GdUnitTestSuite
## Proves a bad content file fails loudly instead of arriving as an empty dictionary.
##
## Every map, rig and sheet in this template is JSON. `JSON.parse_string` answers null for
## a missing file, an empty file, malformed text and a literal null alike, so a caller that
## treats null as "no data" turns a typo into an empty map that renders fine and is wrong.

const TMP_DIR := "user://test_json"

func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)

func after_test() -> void:
	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()

func _write(name: String, text: String) -> String:
	var path := TMP_DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path

func test_a_valid_object_round_trips() -> void:
	var path := TMP_DIR.path_join("round.json")
	assert_int(JsonFile.write(path, {"cell": 16, "style": "gb16"})).is_equal(OK)
	var read := JsonFile.read(path)
	assert_bool(read.ok).is_true()
	assert_int(read.get_int("cell", -1)).is_equal(16)
	assert_str(read.get_string("style", "")).is_equal("gb16")

func test_a_missing_file_is_an_error_not_an_empty_dictionary() -> void:
	var read := JsonFile.read(TMP_DIR.path_join("nope.json"))
	assert_bool(read.ok).is_false()
	assert_str(read.error).contains("no such file")

func test_malformed_json_is_an_error() -> void:
	var read := JsonFile.read(_write("bad.json", "{ this is not json "))
	assert_bool(read.ok).is_false()
	assert_str(read.error).contains("not valid JSON")

func test_an_empty_file_is_an_error() -> void:
	var read := JsonFile.read(_write("empty.json", ""))
	assert_bool(read.ok).is_false()
	assert_str(read.error).contains("empty file")

func test_a_json_array_is_rejected_where_an_object_is_required() -> void:
	# Valid JSON, wrong shape. Without this check the caller reads keys off an Array and
	# gets nulls, which look exactly like absent optional fields.
	var read := JsonFile.read(_write("array.json", "[1, 2, 3]"))
	assert_bool(read.ok).is_false()
	assert_str(read.error).contains("expected a JSON object")

func test_numbers_are_cast_to_int_not_left_as_floats() -> void:
	var read := JsonFile.read(_write("nums.json", '{"columns": 4, "rows": 4}'))
	assert_bool(read.ok).is_true()
	assert_bool(is_same(read.get_int("columns", 0), 4)).is_true()
	assert_array(JsonFile.to_int_array([16.0, 32.0])).is_equal([16, 32])

func test_missing_keys_return_the_caller_s_fallback() -> void:
	var read := JsonFile.read(_write("sparse.json", '{"a": 1}'))
	assert_int(read.get_int("missing", 7)).is_equal(7)
	assert_array(read.get_array("missing")).is_empty()
	assert_dict(read.get_dict("missing")).is_empty()
