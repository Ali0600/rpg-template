class_name SlotMenu
extends RefCounted
## Continue, or start over. No nodes, no autoloads, no files.
##
## Two screens ask this and they ask it identically: the title, where the player has not
## started yet, and the game over, where they have and it ended. What differs is the WORDING of
## the rows, which is a view's business - so the words live on the subclasses and every rule
## about what a press MEANS lives here, once.
##
## They were one class copied twice for about a day. The rule they have to agree on is
## "nothing saved is nothing to continue from", and two copies of that is one screen that
## eventually offers a list of nothing.

## The pages. TOP is the ways on; LOAD is the slot list.
enum Page { TOP, LOAD }

## The TOP page's rows, in the order they are drawn. The view indexes its labels by this.
## Continue first, always - that is the order every game in the genre uses, and it is a
## different fact from which row the cursor STARTS on. See _open_on_a_pressable_row().
enum Row { CONTINUE, NEW_GAME }

## What a press asked the world for. NONE covers "that moved the cursor" and "that was
## refused" alike: neither is something the world has to act on.
enum Kind { NONE, LOAD, NEW_GAME, TITLE, CREDITS, OPTIONS }


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


var _slots: Array[SlotSummary] = []
var _page := Page.TOP
var _index := 0


func page() -> Page:
	return _page


func index() -> int:
	return _index


func slot_count() -> int:
	return _slots.size()


func size() -> int:
	return row_count() if _page == Page.TOP else _slots.size()


## How many rows the top page has. A subclass with an extra way on says so here rather than
## overriding size(), so the page/slot split stays in one place.
func row_count() -> int:
	return Row.size()


## What is in a slot, or null for one with nothing loadable in it. Kept answering SaveData
## rather than the summary, because every caller of THIS is deciding whether there is something
## to load - and an empty slot and a damaged one are the same answer to that question.
func slot(at: int) -> SaveData:
	var found := summary(at)
	return null if found == null else found.data


## The whole reading, for the one caller that needs to tell empty from damaged: the row's label.
func summary(at: int) -> SlotSummary:
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
		var answer := top_pick(_index)
		if answer != null:
			return answer
		# Nothing saved is nothing to continue from. Refusing here rather than opening an empty
		# list is the honest answer: a page of three "empty" rows invites three more presses
		# that also do nothing.
		if not _has_any_save():
			return Pick.of(Kind.NONE)
		_page = Page.LOAD
		_index = 0
		return Pick.of(Kind.NONE)
	# Loading nothing is REFUSED, never nudged to a neighbouring slot - the PauseMenu rule, and
	# it matters more here: on a game over the player has already lost something, and a load
	# they did not ask for would take the rest.
	if slot(_index) == null:
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.LOAD, _index)


## What a top row other than Continue answers, or null for "that is the Continue row". A
## subclass overrides this to add a way on; the Continue rules below stay in one place.
func top_pick(at: int) -> Pick:
	if at == Row.NEW_GAME:
		return Pick.of(Kind.NEW_GAME)
	return null


## What the cancel button asked for. On the slot list it is "back". On the top page it is
## NOTHING: backing out of a pause resumes, and neither of these screens has anything to
## resume into.
func cancel() -> Pick:
	if _page != Page.TOP:
		_page = Page.TOP
		_index = Row.CONTINUE
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.NONE)


## New slot contents, same cursor. Called after a refused load, so the row the player is
## looking at shows what the slots hold now.
func refresh(slots: Array[SlotSummary]) -> void:
	_slots = slots.duplicate()
	if _index >= size():
		_index = maxi(size() - 1, 0)


## Where the cursor starts. On a row a press will actually DO something: with nothing saved
## Continue is refused, and opening on a refused row makes the player's first press of the
## whole game one that does nothing, explained by a label they have not read yet.
##
## The enum ORDER is the genre's - Continue first, always - and the INDEX is honest about what
## is available. Two different facts.
##
## Only the title calls this. The game over deliberately does not: it arrives at the end of a
## lost fight where the player is already pressing, so opening on "Start again" would turn one
## more press into a restarted run. Where a dud first press is friction, an accidental restart
## is a loss - so the two screens answer this differently on purpose.
func _open_on_a_pressable_row() -> void:
	_index = Row.CONTINUE if _has_any_save() else Row.NEW_GAME


## Whether there is anything here to continue FROM. Through has_save() rather than a null test
## on the entry: since M32 a slot is always a reading, and an empty one is an object like any
## other - so `!= null` went from "there is a save" to "there is a slot", which is true of every
## row and would have offered Continue to a player with nothing saved. The type change is what
## made the old test wrong; the tests are what said so.
func _has_any_save() -> bool:
	for summary: SlotSummary in _slots:
		if summary != null and summary.has_save():
			return true
	return false


## One row of the top page, worded by the subclass. Continue says what it would continue from,
## because "Continue" over three empty slots is a promise the menu cannot keep.
func top_label(_at: int) -> String:
	return ""


## The half of that wording both screens share, so "nothing saved" cannot be said two ways.
func _continue_label() -> String:
	return "Continue" if _has_any_save() else "Continue (nothing saved)"
