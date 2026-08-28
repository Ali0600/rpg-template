class_name PauseScreen
extends CanvasLayer
## The pause menu, drawn. PauseMenu decides; this paints and reports.
##
## Built in code from a SpriteStyle rather than from a scene file, like every other view here:
## a .tscn would hold a colour, and a colour outside the style is how a game's chrome stops
## re-skinning with the rest of it.
##
## It sits ABOVE the dialog box, which is the input order too: a dialog cannot open while
## paused, and a pause must cover a conversation rather than appear behind one.
## A sound this view wants played. Emitted rather than played directly, for two reasons.
##
## Signals up, calls down - the world owns the speaker, and a view asking for a noise is the
## same shape as a view asking for anything else. And practically: check.sh's per-file parse
## gate skips any file whose TEXT names an autoload, so calling the audio singleton here would
## quietly drop this file out of that gate, along with every test that depends on it. That is
## not hypothetical - it is how this signal came to exist. Do not name it in prose either.
## The player asked for the next volume step. The world owns the setting - a view that wrote
## it would be a second writer for a value that outlives every scene.
signal sound_changed()

signal sound_wanted(id: StringName)

signal resumed
signal save_requested(slot: int)
signal load_requested(slot: int)
## The player asked to wear or take off the thing they are pointing at. The world owns the
## slot map - a view that wrote it would be a second writer for state that outlives the scene.
signal equip_requested(item: StringName)

const LAYER := 15
const MARGIN := 8
const TITLE_SIZE := 9
const ROW_SIZE := 8
const HELP_SIZE := 7
const ROW_PITCH := 11

## The world is still there behind this, and being able to see where you stood is most of what
## makes a pause feel like a pause rather than a screen change.
const BACKDROP_ALPHA := 0.85

## Indexed by PauseMenu.Row, so the order is the enum's rather than a second list's.
## Indexed by PauseMenu.Row. Sound is empty here because its text changes with the setting,
## and the menu carries that - a view cannot ask the settings singleton without dropping this
## file, and every suite that depends on it, out of the per-file parse gate.
const TOP_LABELS: Array[String] = ["Resume", "Items", "Save", "Load", ""]

var _menu: PauseMenu = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _title := Label.new()
var _help := Label.new()
var _rows: Array[Label] = []
var _purse := Label.new()

## The duplicate-event guard every view here has: this TOGGLES a screen, and acting twice on
## one press puts it back where it started, which reads as a dead key.
var _gate := InputGate.new()

## Set once an answer is on its way to the world. A load rebuilds the map deferred, so there is
## a window in which this is still on screen and must not answer again. refresh() clears it:
## the world calling back is the world saying it is still here.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: PauseMenu, style: SpriteStyle, viewport_size: Vector2i) -> void:
	_menu = menu
	_style = style
	_build(viewport_size)
	_paint()


## New slot contents from the world, cursor untouched. After a save that is what makes the row
## the player is looking at show what they just wrote.
func refresh(slots: Array[SaveData], items: Array = [], sound: String = "",
		gold: String = "") -> void:
	if _menu == null:
		return
	_menu.refresh(slots, items, sound, gold)
	_committed = false
	_paint()


func _build(viewport_size: Vector2i) -> void:
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	_title.position = Vector2(MARGIN, MARGIN)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_title)

	# Enough rows for the widest page, built once. A page change repaints them rather than
	# rebuilding the tree, so there is no frame on which the screen is half-built.
	for i in maxi(TOP_LABELS.size(), maxi(_menu.slot_count(), _menu.item_count())):
		var row := Label.new()
		row.position = Vector2(MARGIN, MARGIN + 22 + i * ROW_PITCH)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		add_child(row)
		_rows.append(row)

	# The purse sits on the title line rather than in the row list, because it is a READOUT:
	# the cursor must not be able to land on it, and every test that names a row by its enum
	# stays aimed at the same row.
	_purse.position = Vector2(MARGIN, MARGIN + 10)
	_purse.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_purse)

	_help.position = Vector2(MARGIN, viewport_size.y - 14)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_help)


func _paint() -> void:
	if _style == null or _menu == null:
		return
	var panel := _style.ui_color("panel")
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")

	# Translucent, so the world stays visible underneath. The clear colour is left alone on
	# purpose: this is a pause over a place, not a different screen.
	panel.a = BACKDROP_ALPHA
	_backdrop.color = panel
	_title.add_theme_color_override("font_color", text)
	_help.add_theme_color_override("font_color", dim)

	_title.text = _title_for(_menu.page())
	_help.text = _help_for(_menu.page())

	for i in _rows.size():
		var row := _rows[i]
		# Rows past the current page's list are hidden rather than blanked: an empty label
		# still occupies its line, and the help text would drift down the screen.
		row.visible = i < _menu.size()
		if not row.visible:
			continue
		var label := _label_for(i)
		var selected := i == _menu.index()
		row.text = ("> " if selected else "  ") + label
		row.add_theme_color_override("font_color", text if selected else dim)
	_purse.text = _menu.gold_label()
	_purse.add_theme_color_override("font_color", dim)


## The row's text on whichever page is up. One function, so the three sources cannot drift
## out of step with the three pages.
func _label_for(at: int) -> String:
	match _menu.page():
		PauseMenu.Page.TOP:
			return _menu.sound_label() if at == PauseMenu.Row.SOUND else TOP_LABELS[at]
		PauseMenu.Page.ITEMS:
			return PauseMenu.item_label(_menu.item(at))
		_:
			return PauseMenu.slot_label(at, _menu.slot(at))


func _title_for(page: PauseMenu.Page) -> String:
	match page:
		PauseMenu.Page.ITEMS:
			return "CARRYING"
		PauseMenu.Page.SAVE:
			return "SAVE TO"
		PauseMenu.Page.LOAD:
			return "LOAD FROM"
		_:
			return "PAUSED"


func _help_for(page: PauseMenu.Page) -> String:
	if page == PauseMenu.Page.ITEMS:
		# The selected thing describes itself here rather than in the row: a list of names is
		# scannable, and a list of names plus sentences is not.
		var row: PauseMenu.ItemRow = _menu.item(_menu.index())
		if row != null and not row.effect.is_empty():
			# What equipping would DO, shown before the press that does it - the compare every
			# equip screen has, and the reason this line beats the description for gear.
			return row.effect
		if row != null and not row.description.is_empty():
			return row.description
		return "W/S to choose    Esc to go back"
	if page == PauseMenu.Page.TOP:
		return "W/S to choose    E to pick    Esc to resume"
	return "W/S to choose    E to pick    Esc to go back"


func _unhandled_input(event: InputEvent) -> void:
	if _committed or not event.is_pressed() or event.is_echo():
		return
	if not _gate.accept(event):
		return

	if event.is_action(&"move_down"):
		# Only when the cursor actually went somewhere. A list too short to move is a list
		# where a blip would say "that worked" about nothing happening.
		if _menu.move(1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action(&"move_up"):
		if _menu.move(-1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action(&"interact"):
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
		_act(_menu.confirm())
	elif event.is_action(&"cancel"):
		_act(_menu.cancel())
	else:
		return
	get_viewport().set_input_as_handled()


## Turns one answer into one signal. A refusal repaints and says nothing, which is the whole
## reason PauseMenu returns NONE rather than throwing: "that did nothing" is a normal outcome.
func _act(pick: PauseMenu.Pick) -> void:
	match pick.kind:
		PauseMenu.Kind.RESUME:
			_committed = true
			resumed.emit()
		PauseMenu.Kind.SAVE:
			# Not committed: saving leaves the menu open, and the world calls refresh() so the
			# row shows what was just written.
			save_requested.emit(pick.slot)
		PauseMenu.Kind.LOAD:
			_committed = true
			load_requested.emit(pick.slot)
		PauseMenu.Kind.EQUIP:
			# Not committed: equipping leaves the menu open and the world calls refresh(), so
			# the row shows its new marker - the save-row and sound-row rule.
			equip_requested.emit(pick.item)
		PauseMenu.Kind.SOUND:
			# Not committed: turning the sound down leaves the menu open, and the world calls
			# refresh() so the row shows what it now says - the save-row rule.
			sound_changed.emit()
		_:
			_paint()
