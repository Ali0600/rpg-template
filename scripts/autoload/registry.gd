extends Node
## Loads every content Resource under res://data once, indexed by type and id.
##
## Content is data, so nothing in scripts/ preloads a specific .tres path: a game built
## from this template adds files to data/ and they appear here. Duplicate ids are tracked
## rather than silently overwritten - two characters claiming "hero" is a content bug that
## otherwise shows up as the wrong sprite much later.

const DATA_ROOT := "res://data"
const RESOURCE_EXTS: Array[String] = ["tres", "res"]

var _by_type: Dictionary = {}
var _duplicate_ids: Array[String] = []
var _loaded := false


func _ready() -> void:
	reload()
	EventBus.system_ready.emit({"system": &"Registry"})


func reload() -> void:
	_by_type.clear()
	_duplicate_ids.clear()
	for path in _all_resources(DATA_ROOT):
		var res := load(path)
		if res == null:
			push_error("Registry: could not load %s" % path)
			continue
		var type_name := StringName(res.get_class())
		var script := res.get_script() as Script
		if script != null and not script.get_global_name().is_empty():
			type_name = script.get_global_name()
		var id: StringName = res.get(&"id") if _has_id(res) else StringName(path.get_file().get_basename())
		if String(id).is_empty():
			push_error("Registry: %s has an empty id" % path)
			continue
		if not _by_type.has(type_name):
			_by_type[type_name] = {}
		var bucket: Dictionary = _by_type[type_name]
		if bucket.has(id):
			_duplicate_ids.append("%s/%s (%s)" % [type_name, id, path])
			continue
		bucket[id] = res
	_loaded = true


func get_resource(type_name: StringName, id: StringName) -> Resource:
	var bucket: Dictionary = _by_type.get(type_name, {})
	return bucket.get(id, null)


func ids_of(type_name: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var bucket: Dictionary = _by_type.get(type_name, {})
	for k: StringName in bucket.keys():
		out.append(k)
	out.sort()
	return out


func type_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _by_type.keys():
		out.append(k)
	out.sort()
	return out


func total_count() -> int:
	var n := 0
	for bucket: Dictionary in _by_type.values():
		n += bucket.size()
	return n


func duplicate_ids() -> Array[String]:
	return _duplicate_ids.duplicate()


func is_loaded() -> bool:
	return _loaded


func _has_id(res: Resource) -> bool:
	for p: Dictionary in res.get_property_list():
		if p.get("name", "") == "id":
			return true
	return false


func _all_resources(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := root.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_all_resources(full))
		else:
			# Exported projects rename .tres to .remap; strip it before testing the type.
			var check := name.trim_suffix(".remap")
			if RESOURCE_EXTS.has(check.get_extension()):
				out.append(root.path_join(check))
		name = dir.get_next()
	dir.list_dir_end()
	return out
