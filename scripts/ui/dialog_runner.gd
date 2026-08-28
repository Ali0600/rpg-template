class_name DialogRunner
extends RefCounted
## Walks a conversation, from data/dialog/<id>.json. Pure: no nodes, no autoloads.
##
## Keeping the conversation logic out of the view means branching, flags and choices can be
## tested by walking a script and reading the result, instead of by clicking through a box
## and watching. It also means the box can be replaced - a different layout, a comic bubble,
## a text log - without touching a single rule about what happens next.
##
## Effects are COLLECTED rather than written. A pure runner cannot reach GameState, and that
## turns out to be the right shape anyway: the caller applies them once the line has actually
## been shown, so a dialog abandoned mid-sentence does not leave its promises behind. They are
## the same effect dictionaries a hook produces, so a conversation and a chest hand a gift over
## through one sink rather than two.
##
## Items may be given or taken on a CHOICE, never on a node. A node has no condition and no
## memory, so a conversation that loops back through one would hand over a second key every
## time it passed - and there is no `once` here to stop it. The idiom is a choice carrying
## `set_flag` plus `hidden_if_flag` naming that same flag: taken once, offered never again.
## `_visible_choices` counts flags earned earlier in this conversation, which is what makes
## that work before anything has been written to the game state.

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
var _effects: Array[Dictionary] = []
## Flags the player already has, used to filter choices. Read-only to this class.
var _known_flags: Dictionary = {}
## What the player is carrying, used the same way. A choice asking for something they do not
## have is hidden rather than shown-and-refused.
var _known_items: Dictionary = {}


static func load_from(path: String, known_flags: Dictionary = {}, known_items: Dictionary = {}) -> DialogRunner:
	var runner := DialogRunner.new()
	var file := JsonFile.read(path)
	if not file.ok:
		runner.error = file.error
		return runner
	runner.id = StringName(file.get_string("id", path.get_file().get_basename()))
	runner._nodes = file.get_dict("nodes")
	runner._start = file.get_string("start", "")
	runner._known_flags = known_flags
	runner._known_items = known_items
	runner.ok = true
	return runner


static func from_dict(data: Dictionary, known_flags: Dictionary = {}, known_items: Dictionary = {}) -> DialogRunner:
	var runner := DialogRunner.new()
	runner.id = StringName(str(data.get("id", "inline")))
	runner._nodes = data.get("nodes", {})
	runner._start = str(data.get("start", ""))
	runner._known_flags = known_flags
	runner._known_items = known_items
	runner.ok = true
	return runner


## Moves to the opening line. Returns false for a dialog with nowhere to start, which is a
## content bug the caller should report rather than silently showing an empty box.
func begin() -> bool:
	_finished = false
	_effects.clear()
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
	_collect(choice)
	return _go_to(str(choice.get("next", "")))


## Everything the conversation has earned so far, in the same shape a hook produces. The
## caller carries it out; this class never does.
func effects() -> Array[Dictionary]:
	return _effects.duplicate(true)


## The flags among those effects. Derived rather than stored, so there is one list and it
## cannot disagree with itself.
func flags_to_set() -> Array[StringName]:
	var out: Array[StringName] = []
	for effect in _effects:
		if str(effect.get("op", "")) == str(GameContext.OP_FLAG):
			out.append(StringName(str(effect.get("key", ""))))
	return out


func _go_to(next_id: String) -> bool:
	if next_id.is_empty() or not _nodes.has(next_id):
		_finished = true
		_current = ""
		return false
	_current = next_id
	_enter(_current)
	return true


## A node sets its flag on arrival, deduped by value: a conversation that loops back through
## the same node has not promised twice. Items are deliberately not read here - see the class
## comment; a node cannot express "only the first time".
func _enter(node_id: String) -> void:
	var node: Dictionary = _nodes[node_id]
	var flag := str(node.get("set_flag", ""))
	if not flag.is_empty() and not flags_to_set().has(StringName(flag)):
		_effects.append({"op": GameContext.OP_FLAG, "key": StringName(flag), "value": true})


## The effects a chosen choice earns: a flag, and anything it hands over or takes away.
func _collect(choice: Dictionary) -> void:
	var flag := str(choice.get("set_flag", ""))
	if not flag.is_empty():
		_effects.append({"op": GameContext.OP_FLAG, "key": StringName(flag), "value": true})
	var gives := str(choice.get("give_item", ""))
	if not gives.is_empty():
		_effects.append({"op": GameContext.OP_GIVE_ITEM, "id": StringName(gives),
			"count": int(choice.get("give_count", 1))})
	var takes := str(choice.get("take_item", ""))
	if not takes.is_empty():
		_effects.append({"op": GameContext.OP_TAKE_ITEM, "id": StringName(takes),
			"count": int(choice.get("take_count", 1))})
	# A counter, opened AFTER the conversation ends. It rides the effect list rather than
	# opening anything here for the reason nothing else here writes either: the runner decides,
	# the world acts - and _on_dialog_closed applies this list before closing the dialog, so
	# the shop arrives over a conversation that has already finished.
	var shop := str(choice.get("open_shop", ""))
	if not shop.is_empty():
		_effects.append({"op": GameContext.OP_SHOP, "shop": StringName(shop)})


## A flag the player already had, OR one this conversation has just earned. The second half is
## what lets a choice hide behind the flag it sets: without it, the gift is offered again on
## the next pass through the same node, because nothing has been written to the game state yet.
func _flag_known(name: String) -> bool:
	return bool(_known_flags.get(name, false)) or flags_to_set().has(StringName(name))


## Every item id this conversation names. Read by the content gate, like a map's.
## Every ShopDef this conversation names, for the content gate. The item_refs precedent
## exactly: a misspelt shop id opens an empty counter, which reads as a broken menu rather
## than as a typo in a data file.
func shop_refs() -> Array[StringName]:
	var out: Array[StringName] = []
	for node_id: Variant in _nodes.keys():
		var node: Dictionary = _nodes[node_id]
		for entry: Variant in node.get("choices", []) as Array:
			var choice: Dictionary = entry
			_add_ref(out, choice.get("open_shop", ""))
	return out


func item_refs() -> Array[StringName]:
	var out: Array[StringName] = []
	for node_id: Variant in _nodes.keys():
		var node: Dictionary = _nodes[node_id]
		for entry: Variant in node.get("choices", []) as Array:
			var choice: Dictionary = entry
			for key in ["give_item", "take_item", "requires_item"]:
				_add_ref(out, choice.get(key, ""))
	return out


static func _add_ref(out: Array[StringName], raw: Variant) -> void:
	var id := StringName(str(raw))
	if not String(id).is_empty() and not out.has(id):
		out.append(id)


## Choices whose requirements the player meets. A choice referring to a flag they do not have
## is hidden rather than shown-and-refused, so the menu never offers something it will reject.
func _visible_choices(node: Dictionary) -> Array:
	var out: Array = []
	for entry: Variant in node.get("choices", []) as Array:
		var choice: Dictionary = entry
		var requires := str(choice.get("requires_flag", ""))
		if not requires.is_empty() and not _flag_known(requires):
			continue
		var forbids := str(choice.get("hidden_if_flag", ""))
		if not forbids.is_empty() and _flag_known(forbids):
			continue
		var needs := str(choice.get("requires_item", ""))
		if not needs.is_empty() and not Inventory.has_in(_known_items, StringName(needs), int(choice.get("requires_count", 1))):
			continue
		# A take implies a requires, the same rule objects follow: offering to hand over
		# something you are not carrying is a choice that can only go wrong when taken.
		var takes := str(choice.get("take_item", ""))
		if not takes.is_empty() and not Inventory.has_in(_known_items, StringName(takes), int(choice.get("take_count", 1))):
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
