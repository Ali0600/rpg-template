class_name ShopScreen
extends CanvasLayer
## The shop, drawn. ShopMenu decides; this paints and reports.
##
## Built in code from a SpriteStyle rather than from a scene file, like every other view here:
## a .tscn would hold a colour, and a colour outside the style is how a game's chrome stops
## re-skinning with the rest of it.
##
## It sits above the dialog box that opened it and below the pause menu, which is the input
## order too: a shop covers the conversation that led to it, and a pause covers the shop.

## A sound this view wants played. Emitted rather than played directly: signals up, calls
## down, and the world owns the speaker. Practically too - check.sh's per-file parse gate
## skips any file whose TEXT names an autoload, so reaching the audio singleton here would
## quietly drop this file, and every suite that depends on it, out of that gate. Do not name
## it in prose either.
signal sound_wanted(id: StringName)

## A deal the player struck. The world is the only thing that may move money or items, so this
## reports and waits to be told what the counter looks like afterwards.
signal bought(item: StringName, price: int)
signal sold(item: StringName, price: int)
signal left

const LAYER := 13
const MARGIN := 8
const TITLE_SIZE := 9
const ROW_SIZE := 8
const HELP_SIZE := 7
const ROW_PITCH := 11
const BACKDROP_ALPHA := 0.85

## Indexed by ShopMenu.Row, so the order is the enum's rather than a second list's.
const TOP_LABELS: Array[String] = ["Buy", "Sell", "Leave"]

## Which shop this is. Parked here by the world so a refresh can rebuild the same counter
## without a second variable tracking it there - the screen is the thing that outlives the
## call that opened it.
var stock: ShopDef = null

var _menu: ShopMenu = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _title := Label.new()
var _purse := Label.new()
var _help := Label.new()
var _rows: Array[Label] = []

var _gate := InputGate.new()
## Set once leaving is on its way to the world. Buying and selling deliberately do NOT set it:
## a deal leaves the counter open and the world calls refresh(), which is the save-row rule
## PauseScreen already follows.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: ShopMenu, style: SpriteStyle, viewport_size: Vector2i, title: String = "Shop") -> void:
	_menu = menu
	_style = style
	_title.text = title
	_build(viewport_size)
	_paint()


## New rows and a new purse from the world, cursor untouched - so the row the player is looking
## at shows what they just bought.
func refresh(stock: Array = [], sellable: Array = [], gold: int = 0) -> void:
	if _menu == null:
		return
	_menu.refresh(stock, sellable, gold)
	_paint()


func menu() -> ShopMenu:
	return _menu


func _build(viewport_size: Vector2i) -> void:
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	_title.position = Vector2(MARGIN, MARGIN)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_title)

	_purse.position = Vector2(MARGIN, MARGIN + 10)
	_purse.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_purse)

	# Enough rows for the widest page, built once. A page change repaints them rather than
	# rebuilding the tree, so there is no frame on which the screen is half-built.
	var widest := maxi(TOP_LABELS.size(), maxi(_menu.stock_count(), _menu.sellable_count()))
	for i in maxi(widest, 1):
		var row := Label.new()
		row.position = Vector2(MARGIN, MARGIN + 22 + i * ROW_PITCH)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		add_child(row)
		_rows.append(row)

	_help.position = Vector2(MARGIN, viewport_size.y - 14)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	_help.text = "move: arrows   choose: Z   back: X"
	add_child(_help)


func _paint() -> void:
	if _menu == null or _style == null:
		return
	var panel := _style.ui_color("panel")
	panel.a = BACKDROP_ALPHA
	_backdrop.color = panel
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")
	_title.add_theme_color_override("font_color", text)
	_help.add_theme_color_override("font_color", dim)
	_purse.text = _menu.gold_label()
	_purse.add_theme_color_override("font_color", dim)

	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < _menu.size()
		if not row.visible:
			continue
		var selected := i == _menu.index()
		row.text = ("> " if selected else "  ") + _label_for(i)
		# An unaffordable row is drawn dim even when the cursor is on it, so "I cannot buy
		# that" is visible BEFORE the press that refuses rather than only after it.
		var lit := text if selected and _menu.affordable(i) else dim
		row.add_theme_color_override("font_color", lit)


## The row's text on whichever page is up. One function, so the pages cannot drift out of step.
func _label_for(at: int) -> String:
	match _menu.page():
		ShopMenu.Page.TOP:
			return TOP_LABELS[at]
		_:
			return ShopMenu.row_label(_menu.row(at))


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


## Turns one answer into one signal. A refusal repaints and says so with the same cue a locked
## door uses - "that did nothing" is a normal outcome, but a silent one reads as a dead key.
func _act(deal: ShopMenu.Deal) -> void:
	match deal.kind:
		ShopMenu.Kind.BUY:
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.PICKUP))
			bought.emit(deal.item, deal.price)
		ShopMenu.Kind.SELL:
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.PICKUP))
			sold.emit(deal.item, deal.price)
		ShopMenu.Kind.LEAVE:
			_committed = true
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
			left.emit()
		_:
			# A refused BUY is the one NONE that has something to say. Distinguishing it from
			# a page change is what makes the refusal audible rather than merely unhelpful.
			if _menu.page() == ShopMenu.Page.BUY and not _menu.affordable(_menu.index()):
				sound_wanted.emit(Sfx.id_of(Sfx.Cue.LOCKED))
			else:
				sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
			_paint()
