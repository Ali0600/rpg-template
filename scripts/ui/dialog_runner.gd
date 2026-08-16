class_name DialogRunner
extends RefCounted
## Walks a conversation, from data/dialog/<id>.json. Pure: no nodes, no autoloads.
##
## Keeping the conversation logic out of the view means branching, flags and choices can be
## tested by walking a script and reading the result, instead of by clicking through a box
## and watching. It also means the box can be replaced - a different layout, a comic bubble,
## a text log - without touching a single rule about what happens next.
##
## Flags are COLLECTED rather than written. A pure runner cannot reach GameState, and that
## turns out to be the right shape anyway: the caller applies them once the line has actually
## been shown, so a dialog abandoned mid-sentence does not leave its promises behind.

## What the view needs to draw right now.
class Line:
	var speaker: String
	var text: String
	var choices: Array[String] = []

	func has_choices() -> bool:
		return not choices.is_empty()


var id: StringName = &""
var ok: bool = false
var error: String = ""

var _nodes: Dictionary = {}
var _start: String = ""
var _current: String = ""
var _finished := false
var _flags_to_set: Array[StringName] = []
## Flags the player already has, used to filter choices. Read-only to this class.
var _known_flags: Dictionary = {}


static func load_from(path: String, known_flags: Dictionary = {}) -> DialogRunner:
	var runner := DialogRunner.new()
	var file := JsonFile.read(path)
	if not file.ok:
		runner.error = file.error
		return runner
	runner.id = StringName(file.get_string("id", path.get_file().get_basename()))
	runner._nodes = file.get_dict("nodes")
	runner._start = file.get_string("start", "")
	runner._known_flags = known_flags
	runner.ok = true
	return runner


static func from_dict(data: Dictionary, known_flags: Dictionary = {}) -> DialogRunner:
	var runner := DialogRunner.new()
	runner.id = StringName(str(data.get("id", "inline")))
	runner._nodes = data.get("nodes", {})
	runner._start = str(data.get("start", ""))
	runner._known_flags = known_flags
	runner.ok = true
	return runner


## Moves to the opening line. Returns false for a dialog with nowhere to start, which is a
## content bug the caller should report rather than silently showing an empty box.
func begin() -> bool:
	_finished = false
	_flags_to_set.clear()
	_current = _start
	if not _nodes.has(_current):
		_finished = true
		return false
	_enter(_current)
	return true


func is_finished() -> bool:
	return _finished


func current_id() -> String:
	return _current


## The line to draw, or null when the conversation is over.
func line() -> Line:
	if _finished or not _nodes.has(_current):
		return null
	var node: Dictionary = _nodes[_current]
	var out := Line.new()
	out.speaker = str(node.get("speaker", ""))
	out.text = str(node.get("text", ""))
	for choice in _visible_choices(node):
		out.choices.append(str((choice as Dictionary).get("text", "")))
	return out


## Advances a line with no choices. Returns false when the conversation has ended - which is
## the signal the caller uses to hand control back, so it must be reported, never guessed at
## by checking whether the next line happens to be empty.
func advance() -> bool:
	if _finished or not _nodes.has(_current):
		_finished = true
		return false
	var node: Dictionary = _nodes[_current]
	if not _visible_choices(node).is_empty():
		# A line with choices does not advance; it waits. Advancing past one would pick for
		# the player, and it is exactly what a confirm button held down would do.
		return true
	return _go_to(str(node.get("next", "")))


## Takes the nth VISIBLE choice. Out-of-range is refused rather than clamped: clamping turns
## a UI bug into a plausible-looking wrong answer that nobody notices.
func choose(index: int) -> bool:
	if _finished or not _nodes.has(_current):
		return false
	var choices := _visible_choices(_nodes[_current])
	if index < 0 or index >= choices.size():
		return false
	var choice: Dictionary = choices[index]
	var flag := str(choice.get("set_flag", ""))
	if not flag.is_empty():
		_flags_to_set.append(StringName(flag))
	return _go_to(str(choice.get("next", "")))


## Flags the conversation has earned so far. The caller writes them to the game state; this
## class never does.
func flags_to_set() -> Array[StringName]:
	return _flags_to_set.duplicate()


func _go_to(next_id: String) -> bool:
	if next_id.is_empty() or not _nodes.has(next_id):
		_finished = true
		_current = ""
		return false
	_current = next_id
	_enter(_current)
	return true


func _enter(node_id: String) -> void:
	var node: Dictionary = _nodes[node_id]
	var flag := str(node.get("set_flag", ""))
	if not flag.is_empty() and not _flags_to_set.has(StringName(flag)):
		_flags_to_set.append(StringName(flag))


## Choices whose requirements the player meets. A choice referring to a flag they do not have
## is hidden rather than shown-and-refused, so the menu never offers something it will reject.
func _visible_choices(node: Dictionary) -> Array:
	var out: Array = []
	for entry: Variant in node.get("choices", []) as Array:
		var choice: Dictionary = entry
		var requires := str(choice.get("requires_flag", ""))
		if not requires.is_empty() and not bool(_known_flags.get(requires, false)):
			continue
		var forbids := str(choice.get("hidden_if_flag", ""))
		if not forbids.is_empty() and bool(_known_flags.get(forbids, false)):
			continue
		out.append(choice)
	return out


## Everything wrong with this conversation, all of it. Dialog is hand-authored data, so the
## faults are a `next` pointing at a node that does not exist (the conversation ends early
## and looks like it was written that way) and a start that names nothing.
func problems() -> Array[String]:
	var out: Array[String] = []
	if not ok:
		out.append("dialog did not load: " + error)
		return out
	if _nodes.is_empty():
		out.append("dialog '%s' has no nodes" % id)
		return out
	if _start.is_empty():
		out.append("dialog '%s' does not say where it starts" % id)
	elif not _nodes.has(_start):
		out.append("dialog '%s' starts at '%s', which does not exist" % [id, _start])

	for node_id: Variant in _nodes.keys():
		var node: Dictionary = _nodes[node_id]
		if str(node.get("text", "")).is_empty():
			out.append("dialog '%s' node '%s' has no text" % [id, node_id])
		var next := str(node.get("next", ""))
		if not next.is_empty() and not _nodes.has(next):
			out.append("dialog '%s' node '%s' continues to '%s', which does not exist" % [id, node_id, next])
		for entry: Variant in node.get("choices", []) as Array:
			var choice: Dictionary = entry
			if str(choice.get("text", "")).is_empty():
				out.append("dialog '%s' node '%s' has a choice with no text" % [id, node_id])
			var target := str(choice.get("next", ""))
			if not target.is_empty() and not _nodes.has(target):
				out.append("dialog '%s' node '%s' offers a choice leading to '%s', which does not exist"
					% [id, node_id, target])

	# A node nothing points at is unreachable: it was written, it is in the file, and no
	# player will ever see it.
	var reachable: Array[String] = []
	_collect_reachable(_start, reachable)
	for node_id: Variant in _nodes.keys():
		if not reachable.has(str(node_id)):
			out.append("dialog '%s' node '%s' is unreachable" % [id, node_id])
	return out


func _collect_reachable(node_id: String, seen: Array[String]) -> void:
	if node_id.is_empty() or seen.has(node_id) or not _nodes.has(node_id):
		return
	seen.append(node_id)
	var node: Dictionary = _nodes[node_id]
	_collect_reachable(str(node.get("next", "")), seen)
	for entry: Variant in node.get("choices", []) as Array:
		_collect_reachable(str((entry as Dictionary).get("next", "")), seen)
