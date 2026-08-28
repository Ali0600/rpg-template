class_name ShopMenu
extends RefCounted
## What a customer is pointing at. No nodes, no autoloads, no files.
##
## Split from ShopScreen for the reason PauseMenu is split from PauseScreen: "you cannot buy
## what you cannot afford" and "a quest item is not for sale" are RULES, and a rule tested
## through a scene is a rule tested through three other things at once.
##
## It holds resolved rows rather than item ids because the view needs a name and a price off
## each one, and an id would force a Registry lookup from a class that is not allowed to make
## it - the same call PauseMenu.ItemRow makes.

## The pages. TOP is the counter itself; the other two are lists entered from its rows.
enum Page { TOP, BUY, SELL }

## The TOP page's rows, in the order they are drawn. The view indexes its labels by this, so
## the order lives in one place rather than in a list beside a list.
enum Row { BUY, SELL, LEAVE }

## What a press asked the world for. NONE covers both "that moved the cursor" and "that was
## refused" on purpose: neither is something the world has to do anything about.
enum Kind { NONE, BUY, SELL, LEAVE }


## One answer, carried as a value the way PauseMenu.Pick is. The item is explicit rather than
## something the caller reads back off index() afterwards, which would be a second reading of
## a cursor that may already have moved.
class Deal:
	var kind: Kind = Kind.NONE
	var item: StringName = &""
	var price: int = 0

	static func of(kind_value: Kind, item_id: StringName = &"", amount: int = 0) -> Deal:
		var out := Deal.new()
		out.kind = kind_value
		out.item = item_id
		out.price = amount
		return out


## One line of a counter, already resolved. Handed in rather than looked up, for the reason
## the class header gives.
class ShopRow:
	var id: StringName = &""
	var name: String = ""
	## What the shop charges. The SELL page is handed rows whose price is already the sell
	## price, so this class never does the halving twice or forgets it once.
	var price: int = 0
	var owned: int = 0

	static func of(item_id: StringName, item_name: String, amount: int, held: int = 0) -> ShopRow:
		var out := ShopRow.new()
		out.id = item_id
		out.name = item_name
		out.price = amount
		out.owned = held
		return out


## Whether a thing may be traded at all. ZERO PRICE MEANS NO, which is what keeps a quest
## item off both counters: a key that can be sold is a door that can be locked for the rest of
## the run, and the failure lands hours later. One predicate rather than a copy per page,
## because the buy side and the sell side disagreeing about what is for sale is the bug this
## exists to make impossible.
static func tradable(price: int) -> bool:
	return price > 0


## What a shop pays for a thing it is about to resell. Half, never below one, so a cheap item
## is still worth something and nothing is ever bought for nothing. Static and here rather
## than in the view because it is the rule, not the drawing of it.
static func sell_price(buy_price: int) -> int:
	return maxi(buy_price / 2, 1)


var _stock: Array = []
var _sellable: Array = []
var _gold := 0
var _page := Page.TOP
var _index := 0


static func of(stock: Array = [], sellable: Array = [], gold: int = 0) -> ShopMenu:
	var menu := ShopMenu.new()
	menu._stock = stock.duplicate()
	menu._sellable = sellable.duplicate()
	menu._gold = gold
	return menu


func page() -> Page:
	return _page


func index() -> int:
	return _index


func gold() -> int:
	return _gold


func gold_label() -> String:
	return "Gold: %d" % _gold


func stock_count() -> int:
	return _stock.size()


func sellable_count() -> int:
	return _sellable.size()


## The nth row of whichever list page is up, or null off the end. The view asks for every row
## it draws, and "nothing" is a drawable answer.
func row(at: int) -> ShopRow:
	var list := _list()
	if at < 0 or at >= list.size():
		return null
	return list[at]


## How many rows the CURRENT page has. The cursor wraps over this, so it is one function
## rather than a branch at every call site.
func size() -> int:
	match _page:
		Page.TOP:
			return Row.size()
		_:
			# An empty counter still has one row - the line that says it is empty. A page with
			# no rows at all is one the cursor cannot stand on and the player cannot leave.
			return maxi(_list().size(), 1)


## Whether the row at `at` can actually be afforded. Only the BUY page can refuse: selling
## something you are holding always works.
func affordable(at: int) -> bool:
	if _page != Page.BUY:
		return true
	var r := row(at)
	return r != null and r.price <= _gold


func move(delta: int) -> bool:
	if size() < 2:
		return false
	_index = posmod(_index + delta, size())
	return true


## What the confirm button asked for.
##
## Opening a list page is deliberately NOT an answer: it changes what is on screen and asks
## the world for nothing, which is the same shape as a cursor move.
func confirm() -> Deal:
	if _page == Page.TOP:
		if _index == Row.LEAVE:
			return Deal.of(Kind.LEAVE)
		_page = Page.BUY if _index == Row.BUY else Page.SELL
		_index = 0
		return Deal.of(Kind.NONE)
	var r := row(_index)
	if r == null:
		return Deal.of(Kind.NONE)
	# Refused, never nudged to something cheaper. The precedent is PauseMenu refusing an empty
	# slot: clamping turns a mistake into a plausible-looking wrong answer, and here the wrong
	# answer would be spending money on a thing the player did not choose.
	if _page == Page.BUY and not affordable(_index):
		return Deal.of(Kind.NONE)
	return Deal.of(Kind.BUY if _page == Page.BUY else Kind.SELL, r.id, r.price)


## What the cancel button asked for. On a list page it is "back", and the cursor returns to
## the row that opened the page rather than to the top of the counter. On the top page there
## is nothing left to back out of, and backing out of a shop IS leaving it.
func cancel() -> Deal:
	if _page != Page.TOP:
		_index = Row.BUY if _page == Page.BUY else Row.SELL
		_page = Page.TOP
		return Deal.of(Kind.NONE)
	return Deal.of(Kind.LEAVE)


## New rows and a new purse, same cursor. Called after a deal so the row the player is looking
## at shows what they just did; rebuilding the menu instead would send them back to the top of
## a page they are still using.
func refresh(stock: Array = [], sellable: Array = [], gold: int = 0) -> void:
	_stock = stock.duplicate()
	_sellable = sellable.duplicate()
	_gold = gold
	if _index >= size():
		_index = maxi(size() - 1, 0)


func _list() -> Array:
	return _stock if _page == Page.BUY else _sellable


## One row of a counter. Null is the empty-page line rather than a blank: a row that says
## nothing reads as a menu that failed to draw.
static func row_label(r: ShopRow) -> String:
	if r == null:
		return "(nothing here)"
	if r.owned > 0:
		return "%s  %dg  (have %d)" % [r.name, r.price, r.owned]
	return "%s  %dg" % [r.name, r.price]
