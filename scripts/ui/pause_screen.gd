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
## The player asked to take off whatever is in a slot. A signal of its own rather than an
## equip carrying nothing, for the reason the answer it comes from has its own kind: a verb
## spelled as the absence of its opposite is one every listener has to remember to decode.
signal unequip_requested(slot: StringName)
## The player picked whose Equipment or Status page they want. An empty id is the leader. The
## world answers by re-wording the page for that member and calling refresh(), which is the
## _stats and _status shape - the menu asks WHO and never learns what a level is.
signal member_selected(member: StringName)

const LAYER := 15
const MARGIN := 8
const TITLE_SIZE := UiChrome.FONT_SIZE
const ROW_SIZE := UiChrome.FONT_SIZE
const HELP_SIZE := UiChrome.FONT_SIZE
const ROW_PITCH := 11

## The world is still there behind this, and being able to see where you stood is most of what
## makes a pause feel like a pause rather than a screen change.
const BACKDROP_ALPHA := 0.85

## Indexed by PauseMenu.Row, so the order is the enum's rather than a second list's.
## Indexed by PauseMenu.Row. Sound is empty here because its text changes with the setting,
## and the menu carries that - a view cannot ask the settings singleton without dropping this
## file, and every suite that depends on it, out of the per-file parse gate.
const TOP_LABELS: Array[String] = ["Resume", "Items", "Equipment", "Status", "Save", "Load", ""]

## Where the stats readout sits on the title line, to the right of the purse. A constant for
## the reason MARGIN is: it is a layout fact, and a number written into a position call is a
## number nobody can find again.
const STATS_X := 96

var _menu: PauseMenu = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _title := Label.new()
var _help := Label.new()
var _rows: Array[Label] = []
var _purse := Label.new()
var _stats := Label.new()

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
func refresh(slots: Array[SlotSummary], items: Array = [], sound: String = "",
		gold: String = "", gear: Array = [], stats: String = "",
		status: Array[String] = [], members: Array = [], can_save := true) -> void:
	if _menu == null:
		return
	_menu.refresh(slots, items, sound, gold, gear, stats, status, members, can_save)
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
	# The candidate page is the widest a bag can make it - every carried thing plus the row
	# that takes the current one off - so it is what the pool is sized against.
	for i in maxi(TOP_LABELS.size(),
			maxi(_menu.status_count(), maxi(_menu.slot_count(), _menu.item_count() + 1))):
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

	# What the gear is worth, beside the purse and on the same terms: a readout, not a row.
	# It is what makes a preview a preview - a delta needs a number to be a delta of.
	_stats.position = Vector2(MARGIN + STATS_X, MARGIN + 10)
	_stats.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_stats)

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
		# The status page is a readout, so no row is "chosen" - a cursor on a page with
		# nothing to press points at a verb that does not exist.
		if _menu.page() == PauseMenu.Page.STATUS:
			row.text = "  " + label
			row.add_theme_color_override("font_color", text)
			continue
		var selected := i == _menu.index()
		row.text = ("> " if selected else "  ") + label
		row.add_theme_color_override("font_color", text if selected else dim)
	_purse.text = _menu.gold_label()
	_purse.add_theme_color_override("font_color", dim)
	# Only where a delta means something, and only when there is one to show. A game with no
	# fighting in it hands nothing, and a readout saying "Atk 0" would be naming a stat that
	# game does not have.
	var equipping := _menu.page() == PauseMenu.Page.EQUIP \
		or _menu.page() == PauseMenu.Page.EQUIP_PICK
	_stats.text = _menu.stats_label() if equipping else ""
	_stats.visible = equipping and not _menu.stats_label().is_empty()
	_stats.add_theme_color_override("font_color", dim)


## The row's text on whichever page is up. One function, so the three sources cannot drift
## out of step with the three pages.
func _label_for(at: int) -> String:
	match _menu.page():
		PauseMenu.Page.TOP:
			# Through top_row() rather than indexing by the cursor, because a game that saves
			# at a point offers fewer rows than the enum has - and labelling by the raw index
			# there would draw "Save" over the row that now answers Load.
			var row := _menu.top_row(at)
			return _menu.sound_label() if row == PauseMenu.Row.SOUND else TOP_LABELS[row]
		PauseMenu.Page.ITEMS:
			return PauseMenu.item_label(_menu.item(at))
		PauseMenu.Page.STATUS:
			return _menu.status_line(at)
		PauseMenu.Page.MEMBER:
			return _menu.member_label(at)
		PauseMenu.Page.EQUIP:
			return PauseMenu.gear_label(_menu.gear(at))
		PauseMenu.Page.EQUIP_PICK:
			return PauseMenu.pick_label(_menu.pick_row(at))
		_:
			return PauseMenu.slot_label(at, _menu.summary(at))


func _title_for(page: PauseMenu.Page) -> String:
	match page:
		PauseMenu.Page.ITEMS:
			return "CARRYING"
		PauseMenu.Page.STATUS:
			return "STATUS"
		PauseMenu.Page.EQUIP:
			return "EQUIPMENT"
		PauseMenu.Page.EQUIP_PICK:
			# The slot being answered, so the page says which question it is asking rather
			# than making the player remember what they pressed.
			return _menu.pick_slot_label().to_upper()
		PauseMenu.Page.MEMBER:
			# What the answer is FOR, so the page is a question rather than a list of names.
			return "EQUIP WHO" if _menu.member_opens_equipment() else "STATUS OF WHO"
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
		if row != null and not row.description.is_empty():
			return row.description
		return "W/S to choose    Esc to go back"
	if page == PauseMenu.Page.STATUS:
		# No "E to pick": there is nothing on this page to press, and a hint offering a verb
		# the page does not have is the menu lying about itself.
		return "Esc to go back"
	if page == PauseMenu.Page.EQUIP_PICK:
		# What the press would DO, before the press that does it - the compare every equip
		# screen has, and the whole reason a candidate list is worth walking.
		var candidate: PauseMenu.ItemRow = _menu.pick_row(_menu.index())
		if candidate != null:
			return candidate.effect if not candidate.effect.is_empty() else candidate.description
		var takeoff := _menu.pick_takeoff_effect()
		return takeoff if not takeoff.is_empty() else "Nothing worn here"
	if page == PauseMenu.Page.EQUIP and _menu.has_members():
		# Whose gear is on screen. Without it, a party's two equipment pages look identical
		# until you read the item names.
		return "%s    Esc to go back" % _menu.member_name()
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
		PauseMenu.Kind.MEMBER:
			# Not committed, and not a change: the menu has decided whose page comes next and
			# is asking the world to word it for them. The world refreshes, and the page the
			# menu has already opened is filled with the right person's gear and lines.
			member_selected.emit(pick.gear)
		PauseMenu.Kind.UNEQUIP:
			# Not committed, for the reason equipping is not: the page stays up and the world
			# refreshes it, so the slot the player just emptied says so.
			unequip_requested.emit(pick.gear)
		PauseMenu.Kind.SOUND:
			# Not committed: turning the sound down leaves the menu open, and the world calls
			# refresh() so the row shows what it now says - the save-row rule.
			sound_changed.emit()
		_:
			_paint()
