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
const KEEPER_HEIGHT := 34

## Indexed by ShopMenu.Row, so the order is the enum's rather than a second list's.
const TOP_LABELS: Array[String] = ["Buy", "Sell", "Leave"]

## Which shop this is. Parked here by the world so a refresh can rebuild the same counter
## without a second variable tracking it there.
var stock: ShopDef = null

var _menu: ShopMenu = null
var _style: SpriteStyle = null
var _list_panel := ColorRect.new()
var _purse_panel := ColorRect.new()
var _desc_panel := ColorRect.new()
var _keeper_panel := ColorRect.new()
var _purse := Label.new()
var _desc := Label.new()
var _keeper := Label.new()
var _help := Label.new()
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
	var list_height := MARGIN + PADDING * 2 + ROW_PITCH * maxi(
		maxi(TOP_LABELS.size(), _menu.stock_count()), maxi(_menu.sellable_count(), 1))

	# The list, top-left. No full-screen backdrop anywhere in this view: the world behind the
	# panels is the point.
	_list_panel.position = Vector2(MARGIN, MARGIN)
	_list_panel.size = Vector2(LIST_WIDTH, list_height)
	add_child(_list_panel)

	# The purse, top-right of the list - the one number a shopper checks most.
	_purse_panel.position = Vector2(MARGIN + LIST_WIDTH + MARGIN, MARGIN)
	_purse_panel.size = Vector2(PURSE_WIDTH, PADDING * 2 + ROW_PITCH)
	add_child(_purse_panel)
	_purse.position = Vector2(PADDING, PADDING - 2)
	_purse.add_theme_font_size_override("font_size", ROW_SIZE)
	_purse_panel.add_child(_purse)

	for i in maxi(maxi(TOP_LABELS.size(), _menu.stock_count()), maxi(_menu.sellable_count(), 1)):
		var row := Label.new()
		row.position = Vector2(PADDING, PADDING + i * ROW_PITCH - 2)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		_list_panel.add_child(row)
		_rows.append(row)
		# A separate right-aligned label rather than padded text: a price column that lines up
		# is most of what makes a list of goods readable, and spaces cannot align a font whose
		# digits are not all one width.
		var price := Label.new()
		price.position = Vector2(PADDING, PADDING + i * ROW_PITCH - 2)
		price.size = Vector2(LIST_WIDTH - PADDING * 2, ROW_PITCH)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.add_theme_font_size_override("font_size", ROW_SIZE)
		_list_panel.add_child(price)
		_prices.append(price)

	# The item's own words, under the list. The description field has existed since items did
	# and this is the first screen to show it.
	_desc_panel.position = Vector2(MARGIN, MARGIN + list_height + 2)
	_desc_panel.size = Vector2(LIST_WIDTH + MARGIN + PURSE_WIDTH, PADDING * 2 + ROW_PITCH)
	add_child(_desc_panel)
	_desc.position = Vector2(PADDING, PADDING - 2)
	_desc.add_theme_font_size_override("font_size", HELP_SIZE)
	_desc_panel.add_child(_desc)

	# The keeper, along the bottom in the dialog box's shape - same margin, same panel colour,
	# so the counter reads as the same conversation the player walked in with.
	_keeper_panel.position = Vector2(MARGIN, viewport_size.y - KEEPER_HEIGHT - MARGIN)
	_keeper_panel.size = Vector2(viewport_size.x - MARGIN * 2, KEEPER_HEIGHT)
	add_child(_keeper_panel)
	_keeper.position = Vector2(PADDING, PADDING - 2)
	_keeper.size = Vector2(viewport_size.x - MARGIN * 2 - PADDING * 2, ROW_PITCH * 2)
	_keeper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keeper.add_theme_font_size_override("font_size", ROW_SIZE)
	_keeper_panel.add_child(_keeper)

	_help.position = Vector2(PADDING, KEEPER_HEIGHT - ROW_PITCH - 2)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	_keeper_panel.add_child(_help)
	if not title.is_empty():
		_keeper.text = title


func _paint() -> void:
	if _menu == null or _style == null:
		return
	# No fallback colour is typed here: a style that forgot to define its panel should show
	# that, not be quietly covered for - the DialogBox rule.
	var panel := _style.ui_color("panel")
	for rect in [_list_panel, _purse_panel, _desc_panel, _keeper_panel]:
		rect.color = panel
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")

	# While the keeper is asking how many, the purse shows the DEAL - the number the player is
	# about to agree to, where they are already looking.
	_purse.text = "= %dg" % _menu.total() if _menu.asking() else _menu.gold_label()
	_purse.add_theme_color_override("font_color", text if _menu.asking() else dim)
	_desc.text = _menu.description()
	_desc.add_theme_color_override("font_color", dim)
	_keeper.text = _menu.line()
	_keeper.add_theme_color_override("font_color", text)
	_help.text = "arrows: choose   Z: take   X: back"
	_help.add_theme_color_override("font_color", dim)

	for i in _rows.size():
		var row := _rows[i]
		var price := _prices[i]
		row.visible = i < _menu.size()
		price.visible = row.visible
		if not row.visible:
			continue
		var selected := i == _menu.index()
		if _menu.page() == ShopMenu.Page.TOP:
			row.text = ("> " if selected else "  ") + TOP_LABELS[i]
			price.text = ""
		else:
			var r := _menu.row(i)
			row.text = ("> " if selected else "  ") + ShopMenu.row_label(r)
			# The owned count beside the price, the way a shop that respects its customer
			# shows what they are already carrying.
			price.text = "" if r == null else ("%dg  x%d" % [r.price, r.owned] if r.owned > 0
				else "%dg" % r.price)
		# An unaffordable row is dim even under the cursor, so "I cannot buy that" is visible
		# BEFORE the press that refuses rather than only after it.
		var lit := text if selected and _menu.affordable(i) else dim
		row.add_theme_color_override("font_color", lit)
		price.add_theme_color_override("font_color", lit)


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
