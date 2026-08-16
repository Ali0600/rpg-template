class_name SceneHelpers
extends RefCounted
## Small utilities for the scene tests.
##
## Scene tests are driven by simulated FRAMES, never by wall-clock waits: a headless run has
## no display to pace it, and a test that sleeps is a test that is slow when it passes and
## flaky when the machine is busy.

## Depth-first search for the first node of a given class. Scene trees here are built in
## code from data, so tests find nodes by TYPE rather than by a hardcoded path - a path is a
## second source of truth for the layout, and it goes stale the first time a wrapper node
## appears.
static func find_by_class(root: Node, class_name_wanted: String) -> Node:
	if root.get_class() == class_name_wanted:
		return root
	var script := root.get_script() as Script
	if script != null and script.get_global_name() == StringName(class_name_wanted):
		return root
	for child in root.get_children():
		var found := find_by_class(child, class_name_wanted)
		if found != null:
			return found
	return null


static func find_all_by_class(root: Node, class_name_wanted: String) -> Array[Node]:
	var out: Array[Node] = []
	_collect(root, class_name_wanted, out)
	return out


static func _collect(node: Node, wanted: String, out: Array[Node]) -> void:
	var script := node.get_script() as Script
	var is_match := node.get_class() == wanted
	if not is_match and script != null and script.get_global_name() == StringName(wanted):
		is_match = true
	if is_match:
		out.append(node)
	for child in node.get_children():
		_collect(child, wanted, out)


## A SpriteView wired to a real generated sheet, ready to add to a tree.
static func view_for(character_id: StringName, style_id: StringName = &"gb16") -> SpriteView:
	var view := SpriteView.new()
	var source := FileSpriteSource.create(style_id)
	var sheet := source.sheet(character_id)
	if sheet.is_empty():
		return view
	view.apply_sheet(sheet["texture"], sheet["meta"])
	return view
