class_name GameMenu
extends RefCounted
## Which game the player is pointing at. No nodes, no autoloads, no files.
##
## Split from GamePicker for the reason DialogRunner is split from DialogBox: "the cursor
## wraps" and "an out-of-range index is refused" are rules, and a rule tested through a scene
## is a rule tested through three other things at once.
##
## It holds manifests rather than ids because the view needs a title, a start map and a
## character off the selection, and an id would force a lookup that can fail. GameManifest is
## a plain Resource a test can build in memory, so nothing here touches the filesystem.

var _items: Array[GameManifest] = []
var _index := 0

## The game that was already running when this opened, or null at boot. Cancel means "go back
## to this" - one sentence that is true in both places the picker opens, so nothing here has
## to know which situation it is in. See cancel().
var _opened_on: GameManifest = null


static func of(items: Array[GameManifest], running: GameManifest = null) -> GameMenu:
	var menu := GameMenu.new()
	menu._items = items.duplicate()
	menu._opened_on = running
	# Opens pointing at what is already running, which is both what a player expects and where
	# cancelling would land anyway. It falls out of the same field rather than a second one.
	if running != null:
		menu.select(menu.index_of(running.id))
	return menu


func size() -> int:
	return _items.size()


func index() -> int:
	return _index


func items() -> Array[GameManifest]:
	return _items.duplicate()


## Where an id sits, or -1. Never used to guess: a miss leaves the cursor where it was.
func index_of(id: StringName) -> int:
	for i in _items.size():
		if _items[i].id == id:
			return i
	return -1


## Null rather than a fabricated entry: an empty menu is a caller's bug, and a menu that
## invents a game to point at is the guessing GameSelect exists to refuse.
func selected() -> GameManifest:
	if _index < 0 or _index >= _items.size():
		return null
	return _items[_index]


## Moves the cursor by whole steps, WRAPPING. A list this short is navigated by tapping one
## key, and a cursor that stops dead at the end reads as a dropped input rather than as an end.
func move(delta: int) -> bool:
	if _items.size() < 2:
		return false
	_index = posmod(_index + delta, _items.size())
	return true


## Points at the nth entry. Out of range is REFUSED, never clamped - the precedent is
## DialogRunner.choose(): clamping turns a UI bug into a plausible-looking wrong answer that
## nobody notices. Here the plausible-looking wrong answer is booting the wrong game, which is
## the exact failure GameSelect was built to refuse.
func select(at: int) -> bool:
	if at < 0 or at >= _items.size():
		return false
	_index = at
	return true


## What the player picked. The caller boots it; this class never touches a scene.
func confirm() -> GameManifest:
	return selected()


## What cancelling returns to, or null when nothing was running. Null is the entire boot case
## and it needs no branch anywhere: "there is nothing to go back to" and "cancel does nothing"
## are the same sentence.
func cancel() -> GameManifest:
	return _opened_on
