class_name Inventory
extends RefCounted
## What the player is carrying: item ids and how many of each.
##
## Pure, so "taking two when you have one takes nothing" is a test that reads a result rather
## than one that walks a player into a chest. The world holds one of these; every other layer
## sees a plain Dictionary snapshot, because that is what crosses a save file, a hook boundary
## and a JSON map file without any of them learning this class.
##
## The rules that matter are both about NOT half-doing things. A remove that is short takes
## nothing at all rather than as much as it can - a "consume one oil" that silently consumed
## zero and reported success would light a lantern with an empty flask. And an item taken down
## to nothing is forgotten rather than kept at zero, so "carrying" and "have ever carried" are
## not quietly the same question.

## id -> count. Dictionaries keep insertion order in GDScript, so this is also pickup order,
## which is the order the item list draws in - nothing has to store a second sequence.
var _counts: Dictionary = {}


## Rebuilt from a snapshot, dropping anything add() would have refused. A save file is bytes
## on a player's disk that may have been edited, so this is a boundary, not a formality.
static func from_dict(d: Dictionary) -> Inventory:
	var out := Inventory.new()
	for key: Variant in d.keys():
		# JSON has no integers: every count arrives as a float and must be cast, or the whole
		# inventory silently becomes a dictionary of floats that compare oddly.
		out.add(StringName(str(key)), int(d[key]))
	return out


## "Does this snapshot have at least n?", written once. Four layers ask it - hooks, objects,
## warps and dialog choices - and four copies of `int(d.get(id, 0)) >= n` is four places for
## the >= to become a >.
static func has_in(d: Dictionary, id: StringName, n: int = 1) -> bool:
	return int(d.get(id, 0)) >= n


func count(id: StringName) -> int:
	return int(_counts.get(id, 0))


func has(id: StringName, n: int = 1) -> bool:
	return count(id) >= n


## Refuses a non-positive count and an empty id rather than recording nonsense: "gave zero
## keys" is a caller's bug, and an item with no id can never be looked up again.
func add(id: StringName, n: int = 1) -> bool:
	if n <= 0 or String(id).is_empty():
		return false
	_counts[id] = count(id) + n
	return true


## All or nothing. A partial take is the bug this exists to make impossible.
func remove(id: StringName, n: int = 1) -> bool:
	if n <= 0 or count(id) < n:
		return false
	var left := count(id) - n
	if left == 0:
		# Forgotten, not kept at zero: an item list drawn from ids() would otherwise show
		# things the player no longer has, and has() would need a second rule to disagree.
		_counts.erase(id)
	else:
		_counts[id] = left
	return true


## Carried ids, in the order they were first picked up.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _counts.keys():
		out.append(key)
	return out


func is_empty() -> bool:
	return _counts.is_empty()


## A snapshot for a save, a hook or a lock check.
func to_dict() -> Dictionary:
	return _counts.duplicate()


## An independent copy. Named copy() rather than duplicate() so it cannot be read as
## Resource.duplicate(), which this is not.
func copy() -> Inventory:
	return Inventory.from_dict(to_dict())
