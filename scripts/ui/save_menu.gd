class_name SaveMenu
extends RefCounted
## Which slot a save point is about to write. No nodes, no autoloads, no files.
##
## A list and nothing else: a save point asks one question, so there is no TOP page and no
## second verb to get to. That is what makes this a separate class from SlotMenu rather than a
## subclass of it - SlotMenu's whole shape is "continue, or start over", and its confirm()
## REFUSES an empty slot, which is exactly backwards here. An empty slot is the best thing a
## save can be pointed at, and a damaged one is fair game too because SaveManager.save() parks
## whatever it is about to overwrite either way.
##
## The rows are worded by the view through PauseMenu.slot_label, the one place a slot has ever
## been put into words. A second wording is how "Slot 2: empty" and "Slot 2: damaged" come to
## disagree about the same file - and "empty" is the one word that invites saving over it.

var _slots: Array[SlotSummary] = []
var _index := 0


static func of(slots: Array[SlotSummary]) -> SaveMenu:
	var menu := SaveMenu.new()
	menu._slots = slots.duplicate()
	return menu


func index() -> int:
	return _index


func size() -> int:
	return _slots.size()


func slot_count() -> int:
	return _slots.size()


## The whole reading for a row, so the view can tell empty from damaged. Out of range is null,
## which the view draws as nothing rather than as a slot called "".
func summary(at: int) -> SlotSummary:
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


## Which slot to write, or -1 for "nothing to write into".
##
## Nothing else is refused. Every other menu here guards against a row with no data behind it,
## and this is the one page where that guard would be the bug: an empty row is precisely what a
## first save is aimed at.
func confirm() -> int:
	if _slots.is_empty():
		return -1
	return _index


## New slot contents, same cursor. Called after a save, so the row the player is looking at
## shows what it now holds - the pause menu's rule, and the reason a save leaves this screen
## open rather than closing it.
func refresh(slots: Array[SlotSummary]) -> void:
	_slots = slots.duplicate()
	if _index >= size():
		_index = maxi(size() - 1, 0)
