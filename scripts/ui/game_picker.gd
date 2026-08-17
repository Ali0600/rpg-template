class_name GamePicker
extends CanvasLayer
## The screen that asks which game to play.
##
## It is the view half of GameMenu, the way DialogBox is the view half of DialogRunner: it
## holds no index and decides nothing, it asks the menu every time it repaints. The rules -
## the cursor wrapping, an out-of-range index being refused, what cancel means - are all
## tested without a screen, which is the point of the split.
##
## Moving the cursor repaints everything in the selected game's palette and puts that game's
## own player character on screen. That is not decoration: a picker has no style of its own,
## because style comes from a map and a map comes from a game. Taking the colours from the
## SELECTED game means there is never a moment with no style, and never a colour typed into
## this file - which the linter forbids here anyway.

signal chosen(manifest: GameManifest)
signal cancelled(back_to: GameManifest)

const LAYER := 20
const MARGIN := 8
const TITLE_SIZE := 9
const ROW_SIZE := 8
const HELP_SIZE := 7
const ROW_PITCH := 11
## Big enough to read a 16x24 character across a 320x180 screen without crowding the list.
const PORTRAIT_SCALE := 2


## What one row costs to paint, resolved once. A manifest is two file reads away from a style
## (map -> style_id -> .tres) and doing that on every cursor move is a stutter with no cause
## anyone would go looking for.
class Entry:
	var manifest: GameManifest
	var style: SpriteStyle
	var source: SpriteSource


var _menu: GameMenu
var _entries: Array[Entry] = []
var _backdrop := ColorRect.new()
var _title := Label.new()
var _help := Label.new()
var _rows: Array[Label] = []
var _portrait := SpriteView.new()
var _gate := InputGate.new()
## Set the moment an answer is emitted. The world commits its choice deferred, so this node
## lives for at least one more frame and must not offer a second answer to a settled question.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: GameMenu, viewport_size: Vector2i) -> void:
	_menu = menu
	for manifest in _menu.items():
		_entries.append(_resolve(manifest))
	_build(viewport_size)
	# Painted before the node has ever drawn, so there is no unstyled first frame to see.
	_paint()


## A manifest's look, reached the only way it can be: the game names a start map, the map
## names a style, the style owns every colour on this screen.
func _resolve(manifest: GameManifest) -> Entry:
	var entry := Entry.new()
	entry.manifest = manifest
	var map := MapData.load_from("res://data/maps/%s.json" % manifest.start_map)
	entry.style = load("res://data/styles/%s.tres" % map.style_id) as SpriteStyle
	if entry.style == null:
		# Reported, not fatal. A game whose start map is broken is still a game the player may
		# want to pick, and GameManifest.problems() already names the fault properly.
		push_error("GamePicker: game '%s' reaches no style through map '%s'"
			% [manifest.id, manifest.start_map])
	else:
		entry.source = FileSpriteSource.create(entry.style.id)
	return entry


func _build(viewport_size: Vector2i) -> void:
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	_title.position = Vector2(MARGIN, MARGIN)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.text = "CHOOSE A GAME"
	add_child(_title)

	for i in _entries.size():
		var row := Label.new()
		row.position = Vector2(MARGIN, MARGIN + 22 + i * ROW_PITCH)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		add_child(row)
		_rows.append(row)

	# Positioned by the FEET, which is what a SpriteView's origin is, so characters of
	# different heights stand on the same line.
	_portrait.scale = Vector2(PORTRAIT_SCALE, PORTRAIT_SCALE)
	_portrait.position = Vector2(viewport_size.x - 64, viewport_size.y - 40)
	add_child(_portrait)

	_help.position = Vector2(MARGIN, viewport_size.y - 14)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	_help.text = "W/S or arrows to choose    E or space to play"
	add_child(_help)


## Repaints the whole screen in the selected game's palette. Nothing here remembers an index:
## the menu is asked every time, which is what keeps this a view.
func _paint() -> void:
	var entry := _entries[_menu.index()]
	if entry.style == null:
		return
	var panel := entry.style.ui_color("panel")
	var text := entry.style.ui_color("text")
	var dim := entry.style.ui_color("dim")

	_backdrop.color = panel
	# The backdrop hides a live world when this opens over one; the clear colour paints the
	# letterbox OUTSIDE the 320x180 viewport, which no ColorRect can reach. Both take the same
	# value from the same style, so they cannot disagree.
	RenderingServer.set_default_clear_color(panel)
	_title.add_theme_color_override("font_color", text)
	_help.add_theme_color_override("font_color", dim)

	for i in _rows.size():
		var selected := i == _menu.index()
		# The project's cursor idiom, from the dialog choice list: a two-character prefix and
		# a text/dim swap, so the selection reads without any widget chrome.
		_rows[i].text = ("> " if selected else "  ") + _entries[i].manifest.title
		_rows[i].add_theme_color_override("font_color", text if selected else dim)

	if entry.source != null:
		# A false return leaves the previous sprite standing rather than blanking the node,
		# which is SpriteView's documented behaviour and the right one here: a game with
		# ungenerated art is a content fault its manifest already reports.
		_portrait.apply_source(entry.source, entry.manifest.player_character)
		_portrait.set_pose(&"idle", Dir.D.DOWN)


func _unhandled_input(event: InputEvent) -> void:
	if _committed or not event.is_pressed() or event.is_echo():
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
		var picked := _menu.confirm()
		if picked == null:
			return
		_committed = true
		chosen.emit(picked)
	elif event.is_action(&"cancel") or event.is_action(&"menu"):
		var back := _menu.cancel()
		if back == null:
			# Booting: there is nothing behind this screen. The menu staying up IS the
			# refusal, with a cursor on it. Emitting anyway and letting the world work out
			# that there is nowhere to go would put the same branch in two places.
			return
		_committed = true
		cancelled.emit(back)
	else:
		return
	get_viewport().set_input_as_handled()
