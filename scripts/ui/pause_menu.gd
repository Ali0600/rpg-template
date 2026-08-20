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

## The pages. TOP is the menu itself; the rest are lists entered from one of its rows.
enum Page { TOP, ITEMS, SAVE, LOAD }

## The TOP page's rows, in the order they are drawn. The view indexes its labels by this, so
## the order lives in one place rather than in a list beside a list.
## SOUND is appended rather than slotted in beside Resume, so every existing test that lands
## on a row by naming it - move(Row.SAVE) - still lands on the same one.
enum Row { RESUME, ITEMS, SAVE, LOAD, SOUND }

## What a press asked the world for. NONE covers both "that moved the cursor" and "that was
## refused" on purpose: neither is something the world has to do anything about.
enum Kind { NONE, RESUME, SAVE, LOAD, SOUND }


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


## One line of the bag, already resolved. The menu is handed these rather than an inventory
## and a Registry, because looking an item's name up is a job for the layer that may touch
## autoloads - and this class may not.
class ItemRow:
	var id: StringName = &""
	var name: String = ""
	var count: int = 0
	var description: String = ""

	static func of(item_id: StringName, item_name: String, item_count: int,
			item_description: String = "") -> ItemRow:
		var out := ItemRow.new()
		out.id = item_id
		out.name = item_name
		out.count = item_count
		out.description = item_description
		return out


## Indexed by slot id, which is 0-based like SaveManager's. Only the LABEL says "Slot 1" - a
## menu that renumbered would make a bug report and a filename disagree.
var _slots: Array[SaveData] = []
## One ItemRow per thing carried, in pickup order. Untyped Array because a typed default
## for a nested class is not a constant expression.
var _items: Array = []
## What the Sound row currently says. Carried as text for the reason the slots are carried as
## SaveData: reading it means asking the settings singleton, and this class may not - the same
## rule that keeps it off the disk.
var _sound := ""
var _page := Page.TOP
var _index := 0


static func of(slots: Array[SaveData], items: Array = [], sound: String = "") -> PauseMenu:
	var menu := PauseMenu.new()
	menu._slots = slots.duplicate()
	menu._items = items.duplicate()
	menu._sound = sound
	return menu


func sound_label() -> String:
	return "Sound: %s" % _sound if not _sound.is_empty() else "Sound"


func page() -> Page:
	return _page


func index() -> int:
	return _index


func slot_count() -> int:
	return _slots.size()


func item_count() -> int:
	return _items.size()


## The nth thing carried, or null when the bag is empty or the index is past its end.
func item(at: int) -> ItemRow:
	if at < 0 or at >= _items.size():
		return null
	return _items[at]


## How many rows the CURRENT page has. The cursor wraps over this, so it is one function
## rather than a branch at every call site.
func size() -> int:
	match _page:
		Page.TOP:
			return Row.size()
		Page.ITEMS:
			# An empty bag still has one row - the line that says it is empty. A page with no
			# rows at all is one the cursor cannot stand on and the player cannot escape from.
			return maxi(_items.size(), 1)
		_:
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
		# Answered BEFORE the empty-slot guard below, along with the item page. Neither has
		# anything to do with saves, and a game configured with no slots must still be able to
		# turn the sound down.
		if _index == Row.SOUND:
			return Pick.of(Kind.SOUND)
		if _index == Row.ITEMS:
			_page = Page.ITEMS
			_index = 0
			return Pick.of(Kind.NONE)
		# A game configured with no slots has nowhere to go. The two rows above are exempt: an
		# empty bag is a fact worth showing, where an empty slot list is a menu with nothing in
		# it.
		if _slots.is_empty():
			return Pick.of(Kind.NONE)
		_page = Page.SAVE if _index == Row.SAVE else Page.LOAD
		_index = 0
		return Pick.of(Kind.NONE)
	# Looking at a thing is not doing anything with it. There is no "use" yet, and a confirm
	# that silently did nothing would be indistinguishable from one that failed.
	if _page == Page.ITEMS:
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
		_index = _opened_from(_page)
		_page = Page.TOP
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.RESUME)


## New slot contents, same cursor. Called after a save so the row the player is looking at
## shows what they just wrote; rebuilding the menu instead would send them back to the top of
## a page they are still using.
func refresh(slots: Array[SaveData], items: Array = [], sound: String = "") -> void:
	_slots = slots.duplicate()
	_items = items.duplicate()
	_sound = sound
	if _index >= size():
		_index = maxi(size() - 1, 0)


## The row a page was opened from, so backing out lands the cursor where the player left it
## rather than at the top of a menu they were halfway down.
static func _opened_from(page: Page) -> Row:
	match page:
		Page.ITEMS:
			return Row.ITEMS
		Page.SAVE:
			return Row.SAVE
		_:
			return Row.LOAD


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


## One row of the bag. Null is the empty-bag line rather than a blank: a row that says nothing
## reads as a menu that failed to draw.
static func item_label(row: ItemRow) -> String:
	if row == null:
		return "(nothing carried)"
	if row.count <= 1:
		return row.name
	return "%s x%d" % [row.name, row.count]


## One row of the slot list. The slot is displayed one-based because a player counts from one;
## everything else - the filename, the API, a bug report - stays zero-based.
static func slot_label(at: int, data: SaveData) -> String:
	if data == null:
		return "Slot %d: empty" % (at + 1)
	return "Slot %d: %s  %s" % [at + 1, data.map, clock(data.play_seconds)]
