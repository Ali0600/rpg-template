class_name ShopScreen
extends CanvasLayer
## The shop, drawn as a counter. ShopMenu decides; this paints and reports.
##
## The layout is the one every classic counter converges on, and M18 shipped without it:
## a LIST window with prices right-aligned and the owned count beside them, a PURSE window
## that becomes the running total while the keeper is asking how many, a DESCRIPTION bar in
## the item's own words, and the KEEPER's window along the bottom in the dialog box's shape -
## because a shop is a conversation with a till in it.
##
## Windows over the LIVE WORLD rather than a full-screen dim: the town stays visible between
## the panels, which is what makes a shop feel like a place you walked into rather than a
## screen the game changed to. Built in code from the SpriteStyle, like every view here.

## A sound this view wants played. Emitted rather than played directly: signals up, calls
## down, and the world owns the speaker. Practically too - check.sh's per-file parse gate
## skips any file whose TEXT names an autoload, so reaching the audio singleton here would
## quietly drop this file, and every suite that depends on it, out of that gate. Do not name
## it in prose either.
signal sound_wanted(id: StringName)

## A deal the player struck. The world is the only thing that may move money or items, so this
## reports and waits to be told what the counter looks like afterwards. `total` travels with
## it: the player was shown a number, and a different one arriving at the purse is the bug
## that carrying it prevents.
signal bought(item: StringName, count: int, total: int)
signal sold(item: StringName, count: int, total: int)
signal left

const LAYER := 13
const MARGIN := 6
const PADDING := 4
const TITLE_SIZE := UiChrome.FONT_SIZE
const ROW_SIZE := UiChrome.FONT_SIZE
const HELP_SIZE := UiChrome.FONT_SIZE
const ROW_PITCH := 10
## Wide enough for the longest row plus its price column, and narrow enough that the world
## still shows down the right-hand side.
const LIST_WIDTH := 150
const PURSE_WIDTH := 92
## Where the price column starts inside the list, as a fraction of its width. The name gets the
## left of the row and the price the right, and they no longer share the whole of it.
const PRICE_COLUMN := 0.62

## Indexed by ShopMenu.Row, so the order is the enum's rather than a second list's.
const TOP_LABELS: Array[String] = ["Buy", "Sell", "Leave"]

## Which shop this is. Parked here by the world so a refresh can rebuild the same counter
## without a second variable tracking it there.
var stock: ShopDef = null

var _menu: ShopMenu = null
var _style: SpriteStyle = null
var _list: UiChrome.Frame = null
var _purse_frame: UiChrome.Frame = null
var _desc_frame: UiChrome.Frame = null
var _keeper_frame: UiChrome.Frame = null
var _purse: Label = null
var _desc: Label = null
var _keeper: Label = null
var _help: Label = null
var _select: ColorRect = null
var _rows: Array[Label] = []
var _prices: Array[Label] = []

var _gate := InputGate.new()
## Set once leaving is on its way to the world. A deal deliberately does NOT set it: buying
## leaves the counter open and the world calls refresh(), which is the save-row rule
## PauseScreen already follows.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: ShopMenu, style: SpriteStyle, viewport_size: Vector2i, title: String = "") -> void:
	_menu = menu
	_style = style
	_build(viewport_size, title)
	_paint()


func refresh(stock_rows: Array = [], sellable: Array = [], gold: int = 0) -> void:
	if _menu == null:
		return
	_menu.refresh(stock_rows, sellable, gold)
	_paint()


func menu() -> ShopMenu:
	return _menu


func _build(viewport_size: Vector2i, title: String) -> void:
	var count := maxi(maxi(TOP_LABELS.size(), _menu.stock_count()),
		maxi(_menu.sellable_count(), 1))
	var chrome := float(UiChrome.HEADER_HEIGHT + UiChrome.BORDER * 2 + UiChrome.PAD * 2)
	var list_height := chrome + count * ROW_PITCH

	# The list, top-left, HEADED with its own columns. Sea of Stars heads its stock list "ITEM
	# NAME / OWNED / PRICE", which is the one thing that makes a list of numbers readable without
	# being told what they are - and this counter has had all three columns since M18.1 with
	# nothing naming them. No full-screen backdrop anywhere in this view: the world behind the
	# windows is the point.
	_list = UiChrome.frame(_style, Rect2(MARGIN, MARGIN, LIST_WIDTH, list_height), " ")
	add_child(_list.panel)
	var inner := _list.inner()

	# The purse, right of the list - the one number a shopper checks most.
	# The chrome PLUS a line, which is what a one-row window is. It was the chrome minus its own
	# band, and the purse was drawn into a single pixel of content - the number was there and
	# clipped in half, which reads as a rendering fault rather than as a wrong constant.
	_purse_frame = UiChrome.frame(_style, Rect2(MARGIN + LIST_WIDTH + MARGIN, MARGIN,
		PURSE_WIDTH, chrome + float(UiChrome.FONT_SIZE)), "purse")
	add_child(_purse_frame.panel)
	_purse = UiChrome.label(_style, "dim")
	_purse.position = _purse_frame.inner().position
	_purse_frame.panel.add_child(_purse)

	# Added BEFORE the rows so it is drawn behind them.
	_select = UiChrome.select(_style)
	_list.panel.add_child(_select)
	for i in count:
		var row := UiChrome.label(_style, "text")
		row.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
			inner.position.y + i * ROW_PITCH)
		# BOUNDED to its own column and trimmed with an ellipsis past it. A Label with no width
		# does not clip, wrap or complain - it draws straight on, and here that meant a long name
		# running underneath its own price. A trimmed name still reads; a name with a number
		# printed through it does not.
		row.size = Vector2(inner.size.x * PRICE_COLUMN - float(UiChrome.ROW_INSET) * 2.0,
			ROW_PITCH)
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_list.panel.add_child(row)
		_rows.append(row)
		# A separate right-aligned label rather than padded text: a price column that lines up is
		# most of what makes a list of goods readable, and spaces cannot align a font whose digits
		# are not all one width.
		#
		# It is given its OWN half of the row since M42. It used to span the whole width at the
		# same position, so a long name ran underneath its own price - measured at x=95 against a
		# name reaching x=110, and invisible because the demo's own wares are short words.
		var price := UiChrome.label(_style, "text")
		price.position = Vector2(inner.position.x + inner.size.x * PRICE_COLUMN,
			inner.position.y + i * ROW_PITCH)
		price.size = Vector2(inner.size.x * (1.0 - PRICE_COLUMN), ROW_PITCH)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_list.panel.add_child(price)
		_prices.append(price)

	# The item's own words, under the list.
	_desc_frame = UiChrome.frame(_style, Rect2(MARGIN, MARGIN + list_height + 2,
		LIST_WIDTH + MARGIN + PURSE_WIDTH,
		float(UiChrome.BORDER * 2 + UiChrome.PAD * 2 + UiChrome.FONT_SIZE)))
	add_child(_desc_frame.panel)
	_desc = UiChrome.label(_style, "dim")
	_desc.position = _desc_frame.inner().position
	_desc_frame.panel.add_child(_desc)

	# The keeper, along the bottom in the DIALOG BOX's shape - same margin, same window, same
	# height, DERIVED rather than copied: "the dialog box's shape" was a hand-typed 34 that had
	# no way of following the box when it changed.
	var keeper_height := float(DialogBox.height_for(0))
	_keeper_frame = UiChrome.frame(_style, Rect2(MARGIN,
		float(viewport_size.y) - keeper_height - MARGIN,
		float(viewport_size.x) - MARGIN * 2.0, keeper_height), title if not title.is_empty() else " ")
	add_child(_keeper_frame.panel)
	var keeper_inner := _keeper_frame.inner()
	_keeper = UiChrome.label(_style, "text")
	_keeper.position = keeper_inner.position
	_keeper.size = Vector2(keeper_inner.size.x, ROW_PITCH * 2.0)
	_keeper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keeper_frame.panel.add_child(_keeper)

	_help = UiChrome.label(_style, "dim")
	_help.position = Vector2(keeper_inner.position.x,
		keeper_inner.position.y + keeper_inner.size.y - float(UiChrome.FONT_SIZE))
	_keeper_frame.panel.add_child(_help)


func _paint() -> void:
	if _menu == null or _style == null:
		return
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")

	# While the keeper is asking how many, the purse shows the DEAL - the number the player is
	# about to agree to, where they are already looking.
	_purse.text = "= %dg" % _menu.total() if _menu.asking() else _menu.gold_label()
	_purse.add_theme_color_override("font_color", text if _menu.asking() else dim)
	_desc.text = _menu.description()
	# An empty window is a box with nothing in it, which reads as something that failed to load.
	# The description only exists while a row is under the cursor that has one.
	_desc_frame.panel.visible = not _desc.text.strip_edges().is_empty()
	# The list is headed by its COLUMNS where there are columns, and by the page's own name where
	# there are not - "ITEM OWNED PRICE" over Buy / Sell / Leave names three things that are not
	# there. Sea of Stars heads its stock list exactly this way; its top menu is not a list.
	_list.title.text = ("item          owned   price" if _menu.page() != ShopMenu.Page.TOP
		else "wares").to_upper()
	_list.title.add_theme_color_override("font_color", text)
	_keeper.text = _menu.line()
	# The keys this game actually binds. It said "Z: take" for eighteen milestones, and nothing
	# is bound to Z - a player following it exactly would conclude the counter was broken.
	_help.text = "W/S to choose    E to take    Esc to go back"

	_select.visible = false
	for i in _rows.size():
		var row := _rows[i]
		var price := _prices[i]
		row.visible = i < _menu.size()
		price.visible = row.visible
		if not row.visible:
			continue
		var selected := i == _menu.index()
		if _menu.page() == ShopMenu.Page.TOP:
			row.text = TOP_LABELS[i]
			price.text = ""
		else:
			var r := _menu.row(i)
			row.text = "" if r == null else ShopMenu.row_label(r)
			# The owned count beside the price, the way a shop that respects its customer shows
			# what they are already carrying.
			price.text = "" if r == null else ("%dg  x%d" % [r.price, r.owned] if r.owned > 0
				else "%dg" % r.price)
		# An unaffordable row is dim even under the cursor, so "I cannot buy that" is visible
		# BEFORE the press that refuses rather than only after it.
		var lit := text if _menu.affordable(i) else dim
		row.add_theme_color_override("font_color", lit)
		price.add_theme_color_override("font_color", lit)
		if selected:
			UiChrome.place(_select, row, _list.inner().size.x, ROW_PITCH)


## The row the cursor is on, or null when the list is empty. What replaced reading a "> " off the
## front of a row's own text.
func selected_row() -> Label:
	var at := _menu.index()
	if at < 0 or at >= _rows.size() or not _rows[at].visible:
		return null
	return _rows[at]


func _unhandled_input(event: InputEvent) -> void:
	if _committed or not event.is_pressed() or event.is_echo():
		return
	if not _gate.accept(event):
		return

	if event.is_action(&"move_down"):
		if _menu.move(1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action(&"move_up"):
		if _menu.move(-1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action(&"interact"):
		_act(_menu.confirm())
	elif event.is_action(&"cancel"):
		_act(_menu.cancel())
	else:
		return
	get_viewport().set_input_as_handled()


## Turns one answer into one signal. A refusal repaints and says so - both in the keeper's
## window and with the cue a locked door uses, because "that did nothing" is a normal outcome
## but a silent one reads as a dead key.
func _act(deal: ShopMenu.Deal) -> void:
	match deal.kind:
		ShopMenu.Kind.BUY:
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.PICKUP))
			bought.emit(deal.item, deal.count, deal.total)
		ShopMenu.Kind.SELL:
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.PICKUP))
			sold.emit(deal.item, deal.count, deal.total)
		ShopMenu.Kind.LEAVE:
			_committed = true
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
			left.emit()
		_:
			if _menu.page() == ShopMenu.Page.BUY and not _menu.affordable(_menu.index()):
				sound_wanted.emit(Sfx.id_of(Sfx.Cue.LOCKED))
			else:
				sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
			_paint()
