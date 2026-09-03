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
## EQUIP_PICK is the only page entered from another page rather than from TOP: it is the
## candidates for ONE slot, so it needs the slot the player just pointed at.
## MEMBER is the "whose?" step in front of Equipment and Status, and it exists ONLY when there
## is more than one member to ask about - Dragon Warrior II's Equip "brings up a smaller window
## listing your characters", and EarthBound's Goods cycles them the same way. With one member
## both rows open their page directly, which is what leaves every counting session and every
## screenshot taken before there was a party pressing exactly what they pressed.
enum Page { TOP, ITEMS, SAVE, LOAD, EQUIP, EQUIP_PICK, STATUS, MEMBER }

## The TOP page's rows, in the order they are drawn. The view indexes its labels by this, so
## the order lives in one place rather than in a list beside a list.
## SOUND is appended rather than slotted in beside Resume, so every existing test that lands
## on a row by naming it - move(Row.SAVE) - still lands on the same one.
## EQUIP and STATUS are the exceptions, and they are slotted in DELIBERATELY: Item, Equip,
## Status is the order every classic command menu uses, and a row's position is the one thing
## a player navigates by muscle memory. The cost is paid once, in the sessions that count
## presses.
enum Row { RESUME, ITEMS, EQUIP, STATUS, SAVE, LOAD, SOUND }

## What a press asked the world for. NONE covers both "that moved the cursor" and "that was
## refused" on purpose: neither is something the world has to do anything about.
## MEMBER is a request, not a change: the menu has decided WHO the next page is about and is
## asking the world to word it for them. It carries the member's id in `gear`, which is the
## field a slot id already travels in - a second name for "the thing this Pick is about".
enum Kind { NONE, RESUME, SAVE, LOAD, SOUND, EQUIP, UNEQUIP, MEMBER }


## One answer, carried as a value the way Locomotion.Step is. The slot is explicit rather than
## something the caller reads back off index() afterwards, which would be a second reading of
## a cursor that may already have moved.
class Pick:
	var kind: Kind = Kind.NONE
	var slot: int = -1
	## Which item an EQUIP asked about. Explicit for the reason `slot` is: reading it back off
	## index() afterwards would be a second reading of a cursor that may already have moved.
	var item: StringName = &""
	## Which slot an UNEQUIP asked about. A field of its own rather than an EQUIP carrying an
	## empty item: a sentinel that means "the opposite verb" is a reading every call site has
	## to remember to make, and one that forgets equips nothing and reports success.
	var gear: StringName = &""

	static func of(kind_value: Kind, slot_value: int = -1, item_id: StringName = &"",
			gear_slot: StringName = &"") -> Pick:
		var out := Pick.new()
		out.kind = kind_value
		out.slot = slot_value
		out.item = item_id
		out.gear = gear_slot
		return out


## One line of the bag, already resolved. The menu is handed these rather than an inventory
## and a Registry, because looking an item's name up is a job for the layer that may touch
## autoloads - and this class may not.
class ItemRow:
	var id: StringName = &""
	var name: String = ""
	var count: int = 0
	var description: String = ""
	## Which slot this occupies, or empty for a thing that is only carried. Resolved by the
	## world, like the name and the description: asking what an item IS means the Registry.
	var slot: StringName = &""
	var equipped: bool = false
	## What equipping this would do, already worded by the world - "Atk +3 (now +0)". The
	## delta a player is shown BEFORE they confirm, which is the whole point of an equip
	## screen; wording it here would mean this class knowing what a stat is called.
	var effect: String = ""

	static func of(item_id: StringName, item_name: String, item_count: int,
			item_description: String = "", item_slot: StringName = &"",
			is_equipped: bool = false, item_effect: String = "") -> ItemRow:
		var out := ItemRow.new()
		out.id = item_id
		out.name = item_name
		out.count = item_count
		out.description = item_description
		out.slot = item_slot
		out.equipped = is_equipped
		out.effect = item_effect
		return out


## One line of the equipment page: a slot, and what is in it. Resolved by the world for the
## reason ItemRow is - naming the thing worn in a slot means asking the Registry, and this
## class may not. The label is passed in rather than derived from the id, because "armor" ->
## "Armor" is a decision about words and this class does not make those.
class GearRow:
	var slot_id: StringName = &""
	var label: String = ""
	## What is worn there, already named. Empty means the slot is bare - which is a fact worth
	## drawing, not a row to hide.
	var worn_name: String = ""
	## What taking the current one off would do, worded by the world. Empty when nothing is
	## worn, which is also how the page knows a take-off has nothing to take.
	var takeoff_effect: String = ""

	static func of(id: StringName, slot_label: String, worn: String = "",
			takeoff: String = "") -> GearRow:
		var out := GearRow.new()
		out.slot_id = id
		out.label = slot_label
		out.worn_name = worn
		out.takeoff_effect = takeoff
		return out


## Indexed by slot id, which is 0-based like SaveManager's. Only the LABEL says "Slot 1" - a
## menu that renumbered would make a bug report and a filename disagree.
var _slots: Array[SlotSummary] = []
## One ItemRow per thing carried, in pickup order. Untyped Array because a typed default
## for a nested class is not a constant expression.
var _items: Array = []
## What the Sound row currently says. Carried as text for the reason the slots are carried as
## SaveData: reading it means asking the settings singleton, and this class may not - the same
## rule that keeps it off the disk.
var _sound := ""
## What the purse says. Text for the same reason _sound is: reading it means asking an
## autoload, and this class may not. A readout rather than a Row, so every test that lands on
## a row by naming it - move(Row.SAVE) - stays aimed at the same row.
var _gold := ""
## One GearRow per slot the template knows about, in the world's order. Untyped for the
## reason _items is: a typed default for a nested class is not a constant expression.
var _gear: Array = []
## What the equipment page says the player's numbers are - "Atk 5+3  Def 1+2". Text, and a
## readout rather than a row, for the same two reasons _gold is: composing it means asking
## what a stat is called, and a row is something a cursor can land on.
var _stats := ""
## Which slot the candidate page is showing. Set when a slot is confirmed and read by
## everything the page draws, so the page cannot be entered without one.
var _pick_slot: StringName = &""
## What the status page says, one line per row, already worded. Text for the reason _stats is:
## composing "Level 3" means knowing what this game calls a level, and whether it has one.
var _status: Array[String] = []
## Who is in the party, as `{"id", "name"}` per member, resolved by the world. Empty or one
## member means no member step at all. This carries WHO, never their numbers: a member's gear
## page and status lines are still the world's words, handed over one member at a time as the
## selection changes - the _stats and _status shape, which is what keeps this class from ever
## having to know what a level is.
var _members: Array = []
## Which member the Equipment and Status pages are currently about, as an index into _members.
var _member: int = 0
## Which page the member step is standing in front of.
var _member_opens := Page.EQUIP
## Whether this game writes saves from the menu at all. A bool rather than the policy word,
## because the menu's question is "is there a Save row" and the vocabulary of save_policy is
## the world's business - the _stats and _status shape, where the world answers and this class
## draws. True is the default and is every game that has not said otherwise.
var _can_save := true
var _page := Page.TOP
var _index := 0


static func of(slots: Array[SlotSummary], items: Array = [], sound: String = "",
		gold: String = "", gear: Array = [], stats: String = "",
		status: Array[String] = [], members: Array = [], can_save := true) -> PauseMenu:
	var menu := PauseMenu.new()
	menu._slots = slots.duplicate()
	menu._items = items.duplicate()
	menu._sound = sound
	menu._gold = gold
	menu._gear = gear.duplicate()
	menu._stats = stats
	menu._status = status.duplicate()
	menu._members = members.duplicate()
	menu._can_save = can_save
	return menu


## The TOP page's rows as this game actually offers them, in enum order.
##
## Identical to the enum whenever the game saves from the menu, which is the default and every
## game recorded before save_policy existed - so the cursor index and the Row are still the
## same number there, and every test and session that lands on a row by naming it
## (move(Row.SAVE)) lands where it always did. Under a save-at-point policy the Save row is
## absent rather than refused: a row that cannot be pressed is a dead key, and this is a
## capability the game does not have rather than a price the player cannot meet - the
## requires_item rule, which hides, not the spend_gold rule, which quotes and refuses.
func _top_rows() -> Array:
	var out: Array = []
	for row: int in Row.values():
		if row == Row.SAVE and not _can_save:
			continue
		out.append(row)
	return out


## Which Row the TOP cursor is on. The view asks so it can label the row, and confirm() asks so
## it can answer for it - one mapping, so the drawing and the pressing cannot disagree about
## what the third row is.
func top_row(at: int) -> int:
	var rows := _top_rows()
	if at < 0 or at >= rows.size():
		return Row.RESUME
	return rows[at]


## Whether the menu offers saving at all. The view asks so its help line can stay honest.
func can_save() -> bool:
	return _can_save


## Opens a page that is ABOUT somebody, putting the member step in front of it when there is
## more than one somebody. One function for both rows, so Equipment and Status cannot end up
## disagreeing about when the step appears.
func _open_about(page: Page) -> Pick:
	_index = 0
	if _members.size() > 1:
		_member_opens = page
		_page = Page.MEMBER
		return Pick.of(Kind.NONE)
	_page = page
	return Pick.of(Kind.NONE)


## Who the Equipment and Status pages are currently about. Empty is the leader, which is the
## id every one-member game uses and the one the world reads as "the player".
func member_id() -> StringName:
	if _member < 0 or _member >= _members.size():
		return &""
	return StringName(str((_members[_member] as Dictionary).get("id", "")))


## One row of the member page.
func member_label(at: int) -> String:
	if at < 0 or at >= _members.size():
		return "(nobody else)"
	return str((_members[at] as Dictionary).get("name", ""))


## Whether the member step is part of the flow at all. The view asks so its title and its help
## line can say so, and the world asks so it knows whether a refresh has a member to re-word.
func has_members() -> bool:
	return _members.size() > 1


## The rows themselves, for a VIEW that wants to draw a party rather than list one. The menu
## keeps them verbatim and reads only `id` and `name` out of them; whatever else the world put
## there travels through untouched, which is what lets the screen draw a face and two bars
## without this class learning what a level is.
func members() -> Array:
	return _members


## Which row put the member step up, so the page can say what it is asking for.
func member_opens_equipment() -> bool:
	return _member_opens == Page.EQUIP


## The name of whoever the pages are currently about.
func member_name() -> String:
	return member_label(_member)


func gold_label() -> String:
	return _gold


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


func gear_count() -> int:
	return _gear.size()


## The nth slot, or null past the end - drawable for the reason item() is.
func gear(at: int) -> GearRow:
	if at < 0 or at >= _gear.size():
		return null
	return _gear[at]


func stats_label() -> String:
	return _stats


func status_count() -> int:
	return _status.size()


## The nth status line, or the line that says there is nothing to report. Null is not an
## option here for the reason the empty bag draws a sentence: a page of blanks reads as a page
## that failed rather than as a page with nothing on it.
func status_line(at: int) -> String:
	if _status.is_empty():
		return "(nothing to report)"
	if at < 0 or at >= _status.size():
		return ""
	return _status[at]


func pick_slot() -> StringName:
	return _pick_slot


## What the candidate page is answering a question about, for its title. Empty when the page
## was never entered, which the view draws as nothing rather than as a slot called "".
func pick_slot_label() -> String:
	for row: GearRow in _gear:
		if row.slot_id == _pick_slot:
			return row.label
	return ""


## What is worn in the slot being picked for, or empty. The take-off row asks this rather than
## the world, because a refusal must be decided by the same data the row was drawn from.
func pick_worn_name() -> String:
	for row: GearRow in _gear:
		if row.slot_id == _pick_slot:
			return row.worn_name
	return ""


## What taking off the current gear in this slot would do, or empty. Read by the take-off
## row's preview, and answered from the same rows the page was drawn from.
func pick_takeoff_effect() -> String:
	for row: GearRow in _gear:
		if row.slot_id == _pick_slot:
			return row.takeoff_effect
	return ""


## The carried things that FIT the slot being picked for. A slotless item is not a candidate,
## which is what stops the page offering a tonic as armour - and it is a filter rather than a
## check at confirm time, so the offer is never made in the first place.
func _candidates() -> Array:
	var out: Array = []
	for row: ItemRow in _items:
		if row.slot == _pick_slot:
			out.append(row)
	return out


## The nth candidate, or null for the take-off row that always sits at the end.
func pick_row(at: int) -> ItemRow:
	var rows := _candidates()
	if at < 0 or at >= rows.size():
		return null
	return rows[at]


## How many rows the CURRENT page has. The cursor wraps over this, so it is one function
## rather than a branch at every call site.
func size() -> int:
	match _page:
		Page.TOP:
			return _top_rows().size()
		Page.ITEMS:
			# An empty bag still has one row - the line that says it is empty. A page with no
			# rows at all is one the cursor cannot stand on and the player cannot escape from.
			return maxi(_items.size(), 1)
		Page.EQUIP:
			return _gear.size()
		Page.STATUS:
			# Read-only, so the cursor is only here to be somewhere. An empty status still has
			# the row that says so - the empty-bag rule.
			return maxi(_status.size(), 1)
		Page.MEMBER:
			return maxi(_members.size(), 1)
		Page.EQUIP_PICK:
			# Candidates plus the take-off row, which is always drawn. It is what makes this
			# page impossible to strand a cursor on: a slot whose gear you are not carrying
			# still has one row, the same rule the empty bag gets.
			return _candidates().size() + 1
		_:
			return _slots.size()


## What is in a slot, or null for one with nothing loadable in it. Out of range is null too
## rather than an error: the view asks for every row it draws and the answer "nothing" is a
## drawable one. SaveData rather than the summary, because every caller here is asking whether
## there is something to load - and an empty slot and a damaged one answer that the same way.
func slot(at: int) -> SaveData:
	var found := summary(at)
	return null if found == null else found.data


## The whole reading, for the one caller that has to tell empty from damaged: the row's label.
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


## What the confirm button asked for.
##
## Opening a slot page is deliberately NOT an answer: it changes what is on screen and asks
## the world for nothing, which is the same shape as a cursor move.
func confirm() -> Pick:
	if _page == Page.TOP:
		# Through top_row() rather than off _index directly, because the two are only the same
		# number while every row is offered. A game that saves at a point has no Save row, and
		# reading the cursor as a Row there would answer with whatever now sits at that index.
		var row := top_row(_index)
		if row == Row.RESUME:
			return Pick.of(Kind.RESUME)
		# Answered BEFORE the empty-slot guard below, along with the item page. Neither has
		# anything to do with saves, and a game configured with no slots must still be able to
		# turn the sound down.
		if row == Row.SOUND:
			return Pick.of(Kind.SOUND)
		if row == Row.ITEMS:
			_page = Page.ITEMS
			_index = 0
			return Pick.of(Kind.NONE)
		if row == Row.EQUIP:
			return _open_about(Page.EQUIP)
		if row == Row.STATUS:
			return _open_about(Page.STATUS)
		# A game configured with no slots has nowhere to go. The four rows above are exempt: an
		# empty bag is a fact worth showing, a player can still dress themselves and still ask
		# how they are, where an empty slot list is a menu with nothing in it.
		if _slots.is_empty():
			return Pick.of(Kind.NONE)
		_page = Page.SAVE if row == Row.SAVE else Page.LOAD
		_index = 0
		return Pick.of(Kind.NONE)
	# The bag is a list of what is carried, and nothing more. Equipment moved to a page of its
	# own because that is where the whole genre keeps it - and a general "use" verb remains a
	# game's own business: a potion heals in every RPG ever written, where "use the rope on the
	# well" is a puzzle. So a confirm here does nothing rather than something arbitrary.
	if _page == Page.ITEMS:
		return Pick.of(Kind.NONE)
	# A readout. There is nothing here to press, which is a fact about the page rather than a
	# thing left to build - a status screen that DID something would be a different screen.
	if _page == Page.STATUS:
		return Pick.of(Kind.NONE)
	if _page == Page.MEMBER:
		# Choosing WHO. The world is asked to re-word the page for them - it owns what a level
		# is called and what a slot holds, and this class may not ask a Registry either.
		if _members.is_empty():
			return Pick.of(Kind.NONE)
		_member = clampi(_index, 0, _members.size() - 1)
		_page = _member_opens
		_index = 0
		return Pick.of(Kind.MEMBER, -1, &"", member_id())
	# A slot opens its own candidates, and asks the world for nothing - the same shape as
	# opening a save page.
	if _page == Page.EQUIP:
		var slot_row := gear(_index)
		if slot_row == null:
			return Pick.of(Kind.NONE)
		_pick_slot = slot_row.slot_id
		_page = Page.EQUIP_PICK
		_index = 0
		return Pick.of(Kind.NONE)
	if _page == Page.EQUIP_PICK:
		var chosen := pick_row(_index)
		# The take-off row. Taking nothing off is REFUSED rather than shrugged at, the same
		# rule an empty save slot gets: a menu that accepts a press and does nothing reads as
		# a menu that broke.
		if chosen == null:
			if pick_worn_name().is_empty():
				return Pick.of(Kind.NONE)
			var answer := Pick.of(Kind.UNEQUIP, -1, &"", _pick_slot)
			_back_to_slots()
			return answer
		if String(chosen.slot).is_empty():
			return Pick.of(Kind.NONE)
		var worn_answer := Pick.of(Kind.EQUIP, -1, chosen.id)
		# Back to the slot list before the world hears a word of it. Every refresh therefore
		# lands on a page whose rows are the template's own vocabulary, rather than on a
		# candidate list that was built from a bag the world is about to change.
		_back_to_slots()
		return worn_answer
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
	if _page == Page.EQUIP_PICK:
		_back_to_slots()
		return Pick.of(Kind.NONE)
	# A page that was reached THROUGH the member step goes back to it rather than all the way
	# out - the player is changing their mind about whose page they wanted, not about wanting
	# one. With one member there was no step to come back to, so this does not fire.
	if has_members() and (_page == Page.EQUIP or _page == Page.STATUS):
		_member_opens = _page
		_page = Page.MEMBER
		_index = _member
		return Pick.of(Kind.NONE)
	if _page != Page.TOP:
		_index = _opened_from(_page)
		_page = Page.TOP
		return Pick.of(Kind.NONE)
	return Pick.of(Kind.RESUME)


## New slot contents, same cursor. Called after a save so the row the player is looking at
## shows what they just wrote; rebuilding the menu instead would send them back to the top of
## a page they are still using.
func refresh(slots: Array[SlotSummary], items: Array = [], sound: String = "",
		gold: String = "", gear: Array = [], stats: String = "",
		status: Array[String] = [], members: Array = [], can_save := true) -> void:
	_slots = slots.duplicate()
	_items = items.duplicate()
	_sound = sound
	_gold = gold
	_gear = gear.duplicate()
	_stats = stats
	_status = status.duplicate()
	_members = members.duplicate()
	_can_save = can_save
	if _index >= size():
		_index = maxi(size() - 1, 0)


## Leaves the candidate page for the slot list, cursor on the slot that was being answered.
## One function because three paths need it - equipping, taking off, and backing out - and a
## player who lands somewhere different depending on which is a player who has to look.
func _back_to_slots() -> void:
	_page = Page.EQUIP
	_index = 0
	for at in _gear.size():
		var row: GearRow = _gear[at]
		if row.slot_id == _pick_slot:
			_index = at
			break


## The row a page was opened from, so backing out lands the cursor where the player left it
## rather than at the top of a menu they were halfway down.
func _opened_from(page: Page) -> Row:
	match page:
		Page.ITEMS:
			return Row.ITEMS
		Page.EQUIP:
			return Row.EQUIP
		Page.STATUS:
			return Row.STATUS
		Page.SAVE:
			return Row.SAVE
		Page.MEMBER:
			# Whichever row put the step up. Without this, backing out of the member page
			# always lands on Load, which is two rows from where the player was.
			return Row.STATUS if _member_opens == Page.STATUS else Row.EQUIP
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
	# The marker goes first so a glance down the list finds what is worn without reading every
	# line - the convention every equip screen shares.
	var worn := "(E) " if row.equipped else ""
	if row.count <= 1:
		return worn + row.name
	return "%s%s x%d" % [worn, row.name, row.count]


## One row of the equipment page. A bare slot SAYS it is bare, for the reason the empty bag
## says so: a blank where a value belongs reads as a draw that failed.
static func gear_label(row: GearRow) -> String:
	if row == null:
		return ""
	if row.worn_name.is_empty():
		return "%s: (nothing)" % row.label
	return "%s: %s" % [row.label, row.worn_name]


## One row of the candidate list. Null is the take-off row rather than an emptiness, which is
## why it is worded as a verb: it is the one row on the page that removes something.
static func pick_label(row: ItemRow) -> String:
	if row == null:
		return "(take off)"
	return item_label(row)


## One row of the save slot list. The slot is displayed one-based because a player counts from one;
## everything else - the filename, the API, a bug report - stays zero-based.
##
## THREE ANSWERS, not two. A file that is there and cannot be read used to draw as "empty",
## which is the one wording that invites a player to save over it - and the thing being saved
## over is the file they would want back. The genre states it: Pokémon decides a save is
## unusable by checksum and says "The file data is destroyed!" rather than showing a blank.
## Nothing else changes about a damaged row: the LOAD page already refused anything with no
## data behind it, so only the wording was ever missing.
static func slot_label(at: int, summary: SlotSummary) -> String:
	if summary == null or (summary.data == null and not summary.damaged):
		return "Slot %d: empty" % (at + 1)
	if summary.data == null:
		return "Slot %d: damaged" % (at + 1)
	return "Slot %d: %s  %s" % [at + 1, summary.data.map, clock(summary.data.play_seconds)]
