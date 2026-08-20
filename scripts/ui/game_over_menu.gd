class_name GameOverMenu
extends RefCounted
## What a beaten player is pointing at. No nodes, no autoloads, no files.
##
## The same shape as PauseMenu and split for the same reason, but it answers a different
## question: a pause asks "what do you want to do while you are here", and this asks "how do
## you want to carry on", where staying is not one of the options.
##
## That is the whole difference in the rules. Cancel on the top page RESUMES nothing - there is
## no world left to go back to - so it answers NONE rather than PauseMenu's RESUME.

## The pages. TOP is the two ways on; LOAD is the slot list.
enum Page { TOP, LOAD }

## The TOP page's rows, in the order they are drawn. The view indexes its labels by this.
enum Row { CONTINUE, NEW_GAME }

## What a press asked the world for. NONE covers "that moved the cursor" and "that was
## refused" alike: neither is something the world has to act on.
enum Kind { NONE, LOAD, NEW_GAME }


## One answer, carried as a value. The slot is explicit rather than read back off index()
## afterwards, which would be a second reading of a cursor that may have moved.
class Pick:
	var kind: Kind = Kind.NONE
	var slot: int = -1

	static func of(kind_value: Kind, slot_value: int = -1) -> Pick:
		var out := Pick.new()
		out.kind = kind_value
		out.slot = slot_value
		return out


var _slots: Array[SaveData] = []
var _page := Page.TOP
var _index := 0


static func of(slots: Array[SaveData]) -> GameOverMenu:
	var menu := GameOverMenu.new()
	menu._slots = slots.duplicate()
	return menu


func page() -> Page:
	return _page


func index() -> int:
	return _index


func slot_count() -> int:
	return _slots.size()


func size() -> int:
	return Row.size() if _page == Page.TOP else _slots.size()


func slot(at: int) -> SaveData:
	if at < 0 or at >= _slots.size():
		return null
	return _slots[at]


func move(delta: int) -> bool:
	if size() < 2:
		return false
	_index = posmod(_index + delta, size())
	return true


## What the confirm button asked for.
func confirm() -> Pick:
	if _page == Page.TOP:
		if _index == Row.NEW_GAME:
			return Pick.of(Kind.NEW_GAME)
		# Nothing saved is nothing to continue from. Refusing here rather than opening an empty
		# list is the honest answer: a page of three "empty" rows invites three more presses
		# that also do nothing.
		if _slots.is_empty() or not _has_any_save():
			return Pick.of(Kind.NONE)
		_page = Page.LOAD
		_index = 0
		return Pick.of(Kind.NONE)
	# Loading nothing is REFUSED, never nudged to a neighbouring slot - the PauseMenu rule, and
	# it matters more here: the player has already lost something, and a load they did not ask
	# for would take the rest.
	if slot(_index) == null:
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.LOAD, _index)


## What the cancel button asked for. On the slot list it is "back". On the top page it is
## NOTHING, and that is the one place this differs from a pause menu: backing out of a pause
## resumes, and there is nothing here to resume into.
func cancel() -> Pick:
	if _page != Page.TOP:
		_page = Page.TOP
		_index = Row.CONTINUE
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.NONE)


## New slot contents, same cursor. Called after a refused load, so the row the player is
## looking at shows what the slots hold now - which is one fewer, and that is the honest thing.
func refresh(slots: Array[SaveData]) -> void:
	_slots = slots.duplicate()
	if _index >= size():
		_index = maxi(size() - 1, 0)


func _has_any_save() -> bool:
	for data in _slots:
		if data != null:
			return true
	return false


## One row of the top page. Continue says what it would continue from, because "Continue" over
## three empty slots is a promise the menu cannot keep.
func top_label(at: int) -> String:
	if at == Row.NEW_GAME:
		return "Start again"
	return "Continue" if _has_any_save() else "Continue (nothing saved)"
