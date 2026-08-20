class_name GameOverScreen
extends CanvasLayer
## The end of a run, drawn. GameOverMenu decides; this paints and reports.
##
## Above everything, because there is nothing left underneath it worth seeing and no state this
## can be opened from that it should not cover.
##
## It is an OVERLAY rather than a scene of its own, and that is a deliberate limit: this game
## boots straight into the world and has no title screen, so "return to title" would mean
## inventing one. Router.State.TITLE stays what it has always been - nothing to drive yet - and
## the day a real title scene exists, this becomes the screen that routes to it.
signal load_requested(slot: int)
signal new_game_requested

const LAYER := 20
const MARGIN := 8
const TITLE_SIZE := 9
const ROW_SIZE := 8
const HELP_SIZE := 7
const ROW_PITCH := 11

var _menu: GameOverMenu = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _title := Label.new()
var _blurb := Label.new()
var _help := Label.new()
var _rows: Array[Label] = []

var _gate := InputGate.new()

## Set once an answer is on its way. Both answers rebuild the tree on a deferred call, so there
## is a window in which this is still on screen and must not answer again. refresh() clears it:
## the world calling back is the world saying it is still here.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: GameOverMenu, style: SpriteStyle, viewport_size: Vector2i) -> void:
	_menu = menu
	_style = style
	_build(viewport_size)
	_paint()


func refresh(slots: Array[SaveData]) -> void:
	if _menu == null:
		return
	_menu.refresh(slots)
	_committed = false
	_paint()


func _build(viewport_size: Vector2i) -> void:
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	_title.position = Vector2(MARGIN, MARGIN)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_title)

	_blurb.position = Vector2(MARGIN, MARGIN + 14)
	_blurb.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_blurb)

	# Enough rows for the widest page, built once, so a page change repaints rather than
	# rebuilding and there is no frame on which the screen is half-built.
	for i in maxi(GameOverMenu.Row.size(), _menu.slot_count()):
		var row := Label.new()
		row.position = Vector2(MARGIN, MARGIN + 32 + i * ROW_PITCH)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		add_child(row)
		_rows.append(row)

	_help.position = Vector2(MARGIN, viewport_size.y - 14)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_help)


func _paint() -> void:
	if _style == null or _menu == null:
		return
	var panel := _style.ui_color("panel")
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")

	_backdrop.color = panel
	_title.add_theme_color_override("font_color", text)
	_blurb.add_theme_color_override("font_color", dim)
	_help.add_theme_color_override("font_color", dim)

	_title.text = "THE ROAD ENDS HERE"
	_blurb.text = "Someone will find the lantern eventually."
	_help.text = "W/S to choose    E to pick" if _menu.page() == GameOverMenu.Page.TOP \
		else "W/S to choose    E to pick    Esc to go back"

	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < _menu.size()
		if not row.visible:
			continue
		var selected := i == _menu.index()
		row.text = ("> " if selected else "  ") + _label_for(i)
		row.add_theme_color_override("font_color", text if selected else dim)


func _label_for(at: int) -> String:
	if _menu.page() == GameOverMenu.Page.TOP:
		return _menu.top_label(at)
	# The same row text the pause menu draws, from the same function: a slot that reads one way
	# when you save it and another when you are staring at it after dying is two menus
	# describing one file.
	return PauseMenu.slot_label(at, _menu.slot(at))


func _unhandled_input(event: InputEvent) -> void:
	if _committed or _menu == null or not event.is_pressed() or event.is_echo():
		return
	if not _gate.accept(event):
		return

	if event.is_action(&"move_down"):
		_menu.move(1)
		_paint()
	elif event.is_action(&"move_up"):
		_menu.move(-1)
		_paint()
	elif event.is_action(&"interact"):
		_act(_menu.confirm())
	elif event.is_action(&"cancel"):
		_act(_menu.cancel())
	else:
		return
	get_viewport().set_input_as_handled()


## Turns one answer into one signal. A refusal repaints and says nothing, which is why the menu
## returns NONE rather than throwing: "that did nothing" is a normal outcome here too.
func _act(pick: GameOverMenu.Pick) -> void:
	match pick.kind:
		GameOverMenu.Kind.LOAD:
			_committed = true
			load_requested.emit(pick.slot)
		GameOverMenu.Kind.NEW_GAME:
			_committed = true
			new_game_requested.emit()
		_:
			_paint()
