class_name PauseMenu
extends RefCounted
## What a paused player is pointing at. No nodes, no autoloads, no files.
##
## Split from PauseScreen for the reason DialogRunner is split from DialogBox: "loading an empty
## slot is refused" and "backing out of the top page resumes" are rules, and a rule tested
## through a scene is a rule tested through three other things at once.
##
## It holds SaveData rather than slot numbers because the view needs a map name and a play
## time off each row, and a number would force a read that can fail - from a class that is not
## allowed to touch the disk. A null entry is an empty slot; whether it is empty, unreadable or
## another game's is deliberately not a question this can ask, and not one a menu should
## answer differently.

## The pages. TOP is the menu itself; the other two are the slot list, entered from a row.
enum Page { TOP, SAVE, LOAD }

## The TOP page's rows, in the order they are drawn. The view indexes its labels by this, so
## the order lives in one place rather than in a list beside a list.
enum Row { RESUME, SAVE, LOAD }

## What a press asked the world for. NONE covers both "that moved the cursor" and "that was
## refused" on purpose: neither is something the world has to do anything about.
enum Kind { NONE, RESUME, SAVE, LOAD }


## One answer, carried as a value the way Locomotion.Step is. The slot is explicit rather than
## something the caller reads back off index() afterwards, which would be a second reading of
## a cursor that may already have moved.
class Pick:
	var kind: Kind = Kind.NONE
	var slot: int = -1

	static func of(kind_value: Kind, slot_value: int = -1) -> Pick:
		var out := Pick.new()
		out.kind = kind_value
		out.slot = slot_value
		return out


## Indexed by slot id, which is 0-based like SaveManager's. Only the LABEL says "Slot 1" - a
## menu that renumbered would make a bug report and a filename disagree.
var _slots: Array[SaveData] = []
var _page := Page.TOP
var _index := 0


static func of(slots: Array[SaveData]) -> PauseMenu:
	var menu := PauseMenu.new()
	menu._slots = slots.duplicate()
	return menu


func page() -> Page:
	return _page


func index() -> int:
	return _index


func slot_count() -> int:
	return _slots.size()


## How many rows the CURRENT page has. The cursor wraps over this, so it is one function
## rather than a branch at every call site.
func size() -> int:
	if _page == Page.TOP:
		return Row.size()
	return _slots.size()


## What is in a slot, or null for an empty one. Out of range is null too rather than an error:
## the view asks for every row it draws and the answer "nothing" is a drawable one.
func slot(at: int) -> SaveData:
	if at < 0 or at >= _slots.size():
		return null
	return _slots[at]


## Moves the cursor by whole steps, WRAPPING, for the reason every cursor here does: a list
## this short is navigated by tapping one key, and a cursor that stops dead reads as a dropped
## input rather than as an end.
func move(delta: int) -> bool:
	if size() < 2:
		return false
	_index = posmod(_index + delta, size())
	return true


## What the confirm button asked for.
##
## Opening a slot page is deliberately NOT an answer: it changes what is on screen and asks
## the world for nothing, which is the same shape as a cursor move.
func confirm() -> Pick:
	if _page == Page.TOP:
		if _index == Row.RESUME:
			return Pick.of(Kind.RESUME)
		# A game configured with no slots has nowhere to go. Opening an empty page would be a
		# screen that answers nothing and has to be backed out of.
		if _slots.is_empty():
			return Pick.of(Kind.NONE)
		_page = Page.SAVE if _index == Row.SAVE else Page.LOAD
		_index = 0
		return Pick.of(Kind.NONE)
	# Loading nothing is REFUSED, never nudged to a neighbouring slot. The precedent is
	# DialogRunner.choose(): clamping turns a UI mistake into a plausible-looking wrong answer,
	# and here the wrong answer would be loading a game the player did not ask for.
	if _page == Page.LOAD and slot(_index) == null:
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.SAVE if _page == Page.SAVE else Kind.LOAD, _index)


## What the cancel button asked for. On a slot page it is "back", and the cursor returns to the
## row that opened the page rather than to the top of the menu - the player is where they were.
## On the top page there is nothing left to back out of, and backing out of a pause IS resuming.
func cancel() -> Pick:
	if _page != Page.TOP:
		_index = Row.SAVE if _page == Page.SAVE else Row.LOAD
		_page = Page.TOP
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.RESUME)


## New slot contents, same cursor. Called after a save so the row the player is looking at
## shows what they just wrote; rebuilding the menu instead would send them back to the top of
## a page they are still using.
func refresh(slots: Array[SaveData]) -> void:
	_slots = slots.duplicate()
	if _index >= size():
		_index = maxi(size() - 1, 0)


## Play time as a clock. Minutes and seconds until an hour, because a two-digit hour on a save
## that is eleven minutes old reads as padding rather than as information.
static func clock(seconds: float) -> String:
	var whole := maxi(floori(seconds), 0)
	var hours := whole / 3600
	var minutes := (whole / 60) % 60
	var rest := whole % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, rest]
	return "%02d:%02d" % [minutes, rest]


## One row of the slot list. The slot is displayed one-based because a player counts from one;
## everything else - the filename, the API, a bug report - stays zero-based.
static func slot_label(at: int, data: SaveData) -> String:
	if data == null:
		return "Slot %d: empty" % (at + 1)
	return "Slot %d: %s  %s" % [at + 1, data.map, clock(data.play_seconds)]
