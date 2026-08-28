class_name ShopMenu
extends RefCounted
## What a customer is pointing at, and what the keeper says about it. No nodes, no autoloads,
## no files.
##
## Split from ShopScreen for the reason PauseMenu is split from PauseScreen: "you cannot buy
## what you cannot afford", "a quest item is not for sale" and "how many can you carry at
## this price" are RULES, and a rule tested through a scene is a rule tested through three
## other things at once.
##
## The shape follows the classic counter (Dragon Quest through Pokemon): pick a row, be asked
## HOW MANY, watch the running total, confirm - with the keeper talking the whole way. The
## keeper's words are data on the ShopDef with template defaults here, so a game re-voices
## its merchants without touching a script.

## The pages. TOP is the counter itself; the other two are lists entered from its rows.
enum Page { TOP, BUY, SELL }

## The TOP page's rows, in the order they are drawn.
enum Row { BUY, SELL, LEAVE }

## What a press asked the world for. NONE covers "that moved the cursor", "that opened a
## page" and "that was refused" alike: none of them is something the world must act on.
enum Kind { NONE, BUY, SELL, LEAVE }

## What the keeper's window should be saying right now.
enum Saying { GREETING, BROWSING, HOW_MANY, POOR, THANKS, EMPTY }

## The template's own keeper, for shops that bring no voice of their own.
const DEFAULT_GREETING := "What'll it be?"
const DEFAULT_THANKS := "Anything else?"
const DEFAULT_POOR := "You don't have the coin for that."
const DEFAULT_EMPTY := "Nothing there."


## One answer, carried as a value the way PauseMenu.Pick is. `count` and `total` are both
## explicit: the world must never re-multiply a price, because the menu already showed the
## player a number and a different one arriving at the purse is the bug this prevents.
class Deal:
	var kind: Kind = Kind.NONE
	var item: StringName = &""
	var count: int = 0
	var total: int = 0

	static func of(kind_value: Kind, item_id: StringName = &"", n: int = 0, amount: int = 0) -> Deal:
		var out := Deal.new()
		out.kind = kind_value
		out.item = item_id
		out.count = n
		out.total = amount
		return out


## One line of a counter, already resolved. Handed in rather than looked up: resolving a name,
## a price or a description means asking the Registry, and this class may not.
class ShopRow:
	var id: StringName = &""
	var name: String = ""
	## What the shop charges. SELL rows carry the sell price already, so this class never
	## does the halving twice or forgets it once.
	var price: int = 0
	var owned: int = 0
	var description: String = ""

	static func of(item_id: StringName, item_name: String, amount: int, held: int = 0,
			about: String = "") -> ShopRow:
		var out := ShopRow.new()
		out.id = item_id
		out.name = item_name
		out.price = amount
		out.owned = held
		out.description = about
		return out


## Whether a thing may be traded at all. ZERO PRICE MEANS NO, which is what keeps a quest
## item off both counters: a key that can be sold is a door that can be locked for the rest of
## the run, and the failure lands hours later. One predicate rather than a copy per page,
## because the buy side and the sell side disagreeing about what is for sale is the bug this
## exists to make impossible.
static func tradable(price: int) -> bool:
	return price > 0


## What a shop pays for a thing it is about to resell. Half, never below one, so a cheap item
## is still worth something and nothing is ever bought for nothing.
static func sell_price(buy_price: int) -> int:
	return maxi(buy_price / 2, 1)


var _stock: Array = []
var _sellable: Array = []
var _gold := 0
var _page := Page.TOP
var _index := 0
## The "How many?" step. Zero means not asking; the classic counter asks AFTER a row is
## picked, so a purchase is always row -> count -> confirm and never a surprise total.
var _count := 0
var _saying := Saying.GREETING
## The keeper's voice, from the ShopDef, falling back to the template's own lines.
var _greeting := ""
var _thanks := ""
var _poor := ""


static func of(stock: Array = [], sellable: Array = [], gold: int = 0,
		greeting: String = "", thanks: String = "", poor: String = "") -> ShopMenu:
	var menu := ShopMenu.new()
	menu._stock = stock.duplicate()
	menu._sellable = sellable.duplicate()
	menu._gold = gold
	menu._greeting = greeting
	menu._thanks = thanks
	menu._poor = poor
	return menu


func page() -> Page:
	return _page


func index() -> int:
	return _index


func gold() -> int:
	return _gold


func gold_label() -> String:
	return "Gold: %d" % _gold


func asking() -> bool:
	return _count > 0


func count() -> int:
	return _count


## The running total of the deal being sized up, shown while asking so the number the player
## confirms is the number the purse will move by.
func total() -> int:
	var r := row(_index)
	return 0 if r == null or _count <= 0 else r.price * _count


## The most a "How many?" may answer. On the BUY page the purse is the ceiling; on the SELL
## page the bag is. Never below one: the question is only asked about a row that was already
## affordable and held.
func limit() -> int:
	var r := row(_index)
	if r == null:
		return 1
	if _page == Page.BUY:
		return maxi(_gold / maxi(r.price, 1), 1)
	return maxi(r.owned, 1)


## What the keeper's window says. One function so the view cannot invent a state the menu
## never entered; the words themselves fall back to the template's defaults.
func line() -> String:
	match _saying:
		Saying.HOW_MANY:
			var r := row(_index)
			var thing := r.name if r != null else "that"
			return "How many %s?  x%d = %dg" % [thing, _count, total()]
		Saying.POOR:
			return _poor if not _poor.is_empty() else DEFAULT_POOR
		Saying.THANKS:
			return _thanks if not _thanks.is_empty() else DEFAULT_THANKS
		Saying.EMPTY:
			return DEFAULT_EMPTY
		_:
			return _greeting if not _greeting.is_empty() else DEFAULT_GREETING


## What the selected row is, in the item's own words - the description the pause menu already
## shows, finally shown here too. Empty off the list pages and on the empty-page line.
func description() -> String:
	if _page == Page.TOP:
		return ""
	var r := row(_index)
	return r.description if r != null else ""


func stock_count() -> int:
	return _stock.size()


func sellable_count() -> int:
	return _sellable.size()


func row(at: int) -> ShopRow:
	var list := _list()
	if at < 0 or at >= list.size():
		return null
	return list[at]


func size() -> int:
	match _page:
		Page.TOP:
			return Row.size()
		_:
			# An empty counter still has one row - the line that says it is empty. A page with
			# no rows at all is one the cursor cannot stand on and the player cannot leave.
			return maxi(_list().size(), 1)


## Whether the row at `at` can be afforded AT ALL (one of it). Only the BUY page can refuse:
## selling something you are holding always works.
func affordable(at: int) -> bool:
	if _page != Page.BUY:
		return true
	var r := row(at)
	return r != null and r.price <= _gold


## Moves the cursor - or, while the keeper is asking "how many?", adjusts the answer. One
## verb for both because they are the same key: the classic counter reuses up/down for the
## count, and a second input pathway would be a second thing to gate and test.
func move(delta: int) -> bool:
	if asking():
		var was := _count
		_count = clampi(_count + delta, 1, limit())
		return _count != was
	if size() < 2:
		return false
	_index = posmod(_index + delta, size())
	_saying = Saying.GREETING if _page == Page.TOP else Saying.BROWSING
	return true


## What the confirm button asked for.
##
## On a list row it does not deal yet - it opens the "How many?" question, which is the step
## M18 shipped without and the one every classic counter has. Only the confirm on that
## question is a Deal the world must carry out.
func confirm() -> Deal:
	if _page == Page.TOP:
		_saying = Saying.GREETING
		if _index == Row.LEAVE:
			return Deal.of(Kind.LEAVE)
		_page = Page.BUY if _index == Row.BUY else Page.SELL
		_index = 0
		_saying = Saying.BROWSING
		return Deal.of(Kind.NONE)

	if asking():
		var r := row(_index)
		var deal := Deal.of(Kind.BUY if _page == Page.BUY else Kind.SELL, r.id, _count, total())
		_count = 0
		_saying = Saying.THANKS
		return deal

	var r := row(_index)
	if r == null:
		_saying = Saying.EMPTY
		return Deal.of(Kind.NONE)
	# Refused, never nudged to something cheaper - and SAID, because a refusal that is only a
	# thud reads as a dead key. The precedent is PauseMenu refusing an empty slot.
	if _page == Page.BUY and not affordable(_index):
		_saying = Saying.POOR
		return Deal.of(Kind.NONE)
	_count = 1
	_saying = Saying.HOW_MANY
	return Deal.of(Kind.NONE)


## What the cancel button asked for. Backing out of "How many?" drops the question with
## nothing moved; backing out of a page returns to the row that opened it; backing out of the
## counter is leaving.
func cancel() -> Deal:
	if asking():
		_count = 0
		_saying = Saying.BROWSING
		return Deal.of(Kind.NONE)
	if _page != Page.TOP:
		_index = Row.BUY if _page == Page.BUY else Row.SELL
		_page = Page.TOP
		_saying = Saying.GREETING
		return Deal.of(Kind.NONE)
	return Deal.of(Kind.LEAVE)


## New rows and a new purse, same cursor, keeper thanking. Called after a deal so the row the
## player is looking at shows what they just did.
func refresh(stock: Array = [], sellable: Array = [], gold: int = 0) -> void:
	_stock = stock.duplicate()
	_sellable = sellable.duplicate()
	_gold = gold
	_count = 0
	if _index >= size():
		_index = maxi(size() - 1, 0)


func _list() -> Array:
	return _stock if _page == Page.BUY else _sellable


## One row of a counter. Null is the empty-page line rather than a blank: a row that says
## nothing reads as a menu that failed to draw.
static func row_label(r: ShopRow) -> String:
	if r == null:
		return "(nothing here)"
	return r.name
