class_name JsonFile
extends RefCounted
## Reads and writes the project's JSON content with errors that say what went wrong.
##
## `JSON.parse_string` returns null for a missing file, an empty file, malformed text and
## a literal `null` alike. Every caller that treats null as "no data" turns a typo in a map
## file into an empty map instead of a loud failure, so loading goes through here and
## returns a result that has to be asked whether it is ok.
##
## JSON has no integers: every number parses as float. `get_int` and `get_int_array` do the
## cast in one place so a cell size of 16 never arrives as 16.0 and lands in a Vector2i.

var ok: bool = false
var error: String = ""
var data: Dictionary = {}


static func read(path: String) -> JsonFile:
	var out := JsonFile.new()
	if not FileAccess.file_exists(path):
		out.error = "no such file: " + path
		return out
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		# get_file_as_string returns "" for both an empty file and an unreadable one.
		var code := FileAccess.get_open_error()
		out.error = ("unreadable (error %d): %s" % [code, path]) if code != OK else "empty file: " + path
		return out
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		out.error = "not valid JSON: " + path
		return out
	if not (parsed is Dictionary):
		out.error = "expected a JSON object, got %s: %s" % [type_string(typeof(parsed)), path]
		return out
	out.data = parsed as Dictionary
	out.ok = true
	return out


static func write(path: String, value: Dictionary) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(value, "\t") + "\n")
	f.close()
	return OK


func get_int(key: String, fallback: int) -> int:
	if not data.has(key):
		return fallback
	return int(data[key])


func get_string(key: String, fallback: String) -> String:
	if not data.has(key):
		return fallback
	return str(data[key])


func get_dict(key: String) -> Dictionary:
	if not data.has(key) or not (data[key] is Dictionary):
		return {}
	return data[key] as Dictionary


func get_array(key: String) -> Array:
	if not data.has(key) or not (data[key] is Array):
		return []
	return data[key] as Array


## JSON arrays of numbers arrive as floats; a Vector2i built from them would round
## unexpectedly. Callers wanting pixels ask for ints explicitly.
static func to_int_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if not (raw is Array):
		return out
	for v: Variant in raw as Array:
		out.append(int(v))
	return out


## Floats, for values that are genuinely fractional - a saved position, a tuning weight.
## Reading those through to_int_array would truncate them silently, which for a save means a
## player reloading a few pixels from where they stood.
static func to_float_array(raw: Variant) -> Array[float]:
	var out: Array[float] = []
	if not (raw is Array):
		return out
	for v: Variant in raw as Array:
		out.append(float(v))
	return out


static func to_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (raw is Array):
		return out
	for v: Variant in raw as Array:
		out.append(str(v))
	return out
