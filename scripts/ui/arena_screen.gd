class_name ArenaScreen
extends FightScreen
## An arena, drawn. ArenaSim decides; this feeds it the player's input, paints it, and reports.
##
## Built in code from a SpriteStyle like every other view here. Three windows over an opaque
## backdrop - a banner naming the formation with ONE bar for the foe the fight is about, the floor,
## and the leader's own health - which is what docs/GENRE_CONVENTIONS.md §7d found an action fight
## shows: the player's health always, a foe's flash as its protection made visible, and no menu,
## because there is nothing to choose.
##
## Nothing here times anything. Every frame is one tick of the rules and every moving thing is
## placed from the rules' own numbers, so what the player sees and what the fight judges cannot
## drift apart.
##
## The input is the map's own. The four move actions are READ each frame through Locomotion, and
## the sword is `interact` - the owner's call (docs/DECISIONS.md, M50) - taken as a PRESS, so
## holding the button is one swing and mashing it is one swing per re-arm.

## Design pixels one tile of floor is drawn across, whatever the style: the world's own rule, the
## same number of tiles across at any art size, because the layer is scaled rather than the layout.
const TILE_PX := 16
## The biggest floor this screen draws, in tiles. A DECLARED capacity: the layout audit measures at
## it and the content gate refuses a game asking for more, because a floor too big for the window
## is drawn off the bottom of the screen in silence.
const FLOOR_MAX_TILES := Vector2i(16, 4)
const MARGIN := 8.0
const BANNER_Y := 4.0
## Two lines: the formation's names, and the bar UNDER them - BattleScreen's banner exactly. On one
## line the bar and its figures take the right third of the window, and a full formation's names
## ran into it by a pixel at the capacity the layout audit measures, which is how that was found.
const BANNER_HEIGHT := 24.0
const FLOOR_Y := 32.0
const PANEL_GAP := 4.0
const FOE_BAR_WIDTH := 80.0
const LEADER_BAR_WIDTH := 60.0
## A protected body is shown this many frames and hidden this many, for as long as it lasts.
const FLICKER_SPAN := 2
const HELP := "E to swing"

var _sim: ArenaSim = null
var _style: SpriteStyle = null
var _backdrop: ColorRect = null
var _banner: UiChrome.Frame = null
var _foe_names: Array[Label] = []
var _foe_bar: UiChrome.Bar = null
var _floor: UiChrome.Frame = null
## Where floor position (0, 0) is drawn, in the floor window's own coordinates.
var _origin := Vector2.ZERO
## How far any fighter in this fight is drawn past its feet: left and up, then right and down.
var _before := Vector2.ZERO
var _after := Vector2.ZERO
## The sword's box while it is out. Made in _build like every other node here, so a screen that is
## never set up owns nothing it has not put in the tree.
var _blade: ColorRect = null
var _player_view: SpriteView = null
var _foe_views: Array[SpriteView] = []
var _panel: UiChrome.Frame = null
var _leader_name: Label = null
var _leader_bar: UiChrome.Bar = null
var _help: Label = null
var _gate := InputGate.new()
## A press of the sword button since the last tick, handed to the rules as one frame's request.
var _swing_pressed := false


func setup(sim: ArenaSim, style: SpriteStyle, viewport_size: Vector2i,
		source: SpriteSource) -> void:
	_sim = sim
	_style = style
	_build(viewport_size, source)
	_paint()


func sim() -> ArenaSim:
	return _sim


func foe_ids() -> Array[StringName]:
	if _sim == null:
		var none: Array[StringName] = []
		return none
	return _sim.foe_ids()


## The clock: one tick of the rules, one repaint, and - once - one result.
func _physics_process(_delta: float) -> void:
	if _sim == null or _committed:
		return
	_sim.tick(Locomotion.read_input(), _swing_pressed)
	_swing_pressed = false
	for cue in _sim.take_sounds():
		sound_wanted.emit(cue)
	_paint()
	if _sim.finished():
		_committed = true
		finished.emit(_sim.outcome(), _sim.effects())


func _unhandled_input(event: InputEvent) -> void:
	if _committed or _sim == null or not event.is_pressed() or event.is_echo():
		return
	if not _gate.accept(event):
		return
	if event.is_action(&"interact"):
		# Latched until the next tick hands it over, so holding the button asks once.
		_swing_pressed = true
		get_viewport().set_input_as_handled()


# -- building ------------------------------------------------------------------------------------


func _build(viewport_size: Vector2i, source: SpriteSource) -> void:
	# Opaque, for BattleScreen's reason: a fight is somewhere else.
	_backdrop = ColorRect.new()
	_backdrop.color = _style.ui_color("panel")
	_backdrop.size = viewport_size
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	var wide := float(viewport_size.x)
	var band := float(UiChrome.FONT_SIZE + 2) + float(UiChrome.BORDER + UiChrome.PAD) * 2.0
	_build_banner(wide)
	var drawn := FightScreen.fighter_scale(_style)
	_measure_overhang(source, drawn)
	var floor_bottom := _build_floor(wide, source, drawn)
	_build_panel(wide, band, floor_bottom + PANEL_GAP)


func _build_banner(wide: float) -> void:
	_banner = UiChrome.frame(_style, Rect2(MARGIN, BANNER_Y, wide - MARGIN * 2.0, BANNER_HEIGHT))
	add_child(_banner.panel)
	var inner := _banner.inner()
	for i in _sim.foe_count():
		var name_label := UiChrome.label(_style, "text")
		name_label.position = inner.position
		_banner.panel.add_child(name_label)
		_foe_names.append(name_label)
	_foe_bar = UiChrome.bar(_style, "hp", FOE_BAR_WIDTH)
	_banner.panel.add_child(_foe_bar.root)
	_foe_bar.root.position = Vector2(inner.position.x, inner.position.y + 10.0)


## How far every fighter in this fight is drawn past its feet, read from each sheet's own anchor
## rather than from a cell size: a cell is not a body, and LPC's characters stand two rows above the
## bottom of a 64px cell where the rig's stand on the last of a 24px one. The floor window is given
## exactly that much room on each side, so a body pressed against a wall is still inside it.
func _measure_overhang(source: SpriteSource, drawn: float) -> void:
	var characters: Array[StringName] = [_sim.member_character(0)]
	for i in _sim.foe_count():
		characters.append(_sim.foe_character(i))
	for character in characters:
		var sheet := source.sheet(character)
		if sheet.is_empty():
			continue
		var meta: SheetMeta = sheet["meta"]
		_before.x = maxf(_before.x, ceilf(float(meta.anchor.x) * drawn))
		_before.y = maxf(_before.y, ceilf(float(meta.anchor.y) * drawn))
		_after.x = maxf(_after.x, ceilf(float(meta.cell.x - meta.anchor.x) * drawn))
		_after.y = maxf(_after.y, ceilf(float(meta.cell.y - meta.anchor.y) * drawn))


## The floor window, centred, and everything on it. Answers where the window ends.
func _build_floor(wide: float, source: SpriteSource, drawn: float) -> float:
	var tiles := _sim.floor_rect().size / ArenaSim.UNITS_PER_TILE
	var play := Vector2(tiles * TILE_PX)
	var chrome := float(UiChrome.BORDER + UiChrome.PAD) * 2.0
	var outer := play + _before + _after + Vector2(chrome, chrome)
	_floor = UiChrome.frame(_style, Rect2(Vector2(roundf((wide - outer.x) / 2.0), FLOOR_Y), outer))
	add_child(_floor.panel)
	_origin = _floor.inner().position + _before
	# The blade first, so a body is drawn over the sword rather than under it.
	_blade = ColorRect.new()
	_blade.color = _style.ui_color("select")
	_blade.visible = false
	_blade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor.panel.add_child(_blade)
	_player_view = _make_view(source, _sim.member_character(0), drawn)
	for i in _sim.foe_count():
		_foe_views.append(_make_view(source, _sim.foe_character(i), drawn))
	return FLOOR_Y + outer.y


func _build_panel(wide: float, band: float, top: float) -> void:
	_panel = UiChrome.frame(_style, Rect2(MARGIN, top, wide - MARGIN * 2.0, band))
	add_child(_panel.panel)
	var room := _panel.inner()
	_leader_name = UiChrome.label(_style, "text")
	_leader_name.text = _sim.member_name(0)
	_leader_name.position = room.position
	_panel.panel.add_child(_leader_name)
	_leader_bar = UiChrome.bar(_style, "hp", LEADER_BAR_WIDTH)
	_panel.panel.add_child(_leader_bar.root)
	_leader_bar.root.position = Vector2(room.position.x + _text_width(_leader_name) + 8.0,
		room.position.y + 3.0)
	_help = UiChrome.label(_style, "dim")
	_help.text = HELP
	_panel.panel.add_child(_help)
	_help.position = Vector2(room.end.x - _text_width(_help), room.position.y)


func _make_view(source: SpriteSource, character: StringName, drawn: float) -> SpriteView:
	var view := SpriteView.new()
	_floor.panel.add_child(view)
	view.scale = Vector2(drawn, drawn)
	# A fighter whose art is missing still gets a view, for BattleScreen's reason: a fight that
	# refused to open would turn a missing PNG into an unreachable quest.
	if view.apply_source(source, character):
		view.set_pose(&"idle", Dir.D.DOWN)
	return view


# -- painting ------------------------------------------------------------------------------------


func _paint() -> void:
	if _sim == null or _style == null:
		return
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")
	var shown := _sim.shown_foe()
	var at := _banner.inner().position.x
	for i in _foe_names.size():
		var label := _foe_names[i]
		label.text = _sim.foe_name(i)
		label.position.x = at
		# Lit when the bar is about this one, which is how a line of names says whose number it is.
		label.add_theme_color_override("font_color",
			dim if _sim.foe_down(i) else (text if i == shown else dim))
		at += _text_width(label) + 8.0
	UiChrome.fill(_foe_bar, _sim.foe_hp(shown), _sim.foe_max_hp(shown))
	_foe_bar.numbers.add_theme_color_override("font_color", text)
	UiChrome.fill(_leader_bar, _sim.leader_hp(), _sim.member_max_hp(0))
	_leader_bar.numbers.add_theme_color_override("font_color", text)
	_place(_player_view, _sim.player_box(), _sim.player_facing(), _sim.player_moved(),
		_sim.player_hurt())
	for i in _foe_views.size():
		if _sim.foe_down(i):
			# A felled foe is gone from the floor, the way a Zelda enemy is; the banner still names it.
			_foe_views[i].visible = false
			continue
		_place(_foe_views[i], _sim.foe_box(i), _sim.foe_facing(i), _sim.foe_moved(i),
			_sim.foe_hurt(i))
	_paint_blade()


func _place(view: SpriteView, box: Rect2i, facing: Dir.D, moved: bool, hurt: int) -> void:
	# Feet on the bottom edge of the footprint, which is where the world's own bodies stand.
	view.position = _origin + _pixels(Vector2i(box.position.x + box.size.x / 2, box.end.y))
	view.set_pose(&"walk" if moved else &"idle", facing)
	# The flicker IS the protection, shown and hidden for exactly as long as it lasts. There is no
	# hurt pose, because no sheet in this template has one.
	view.visible = hurt <= 0 or hurt % (FLICKER_SPAN * 2) < FLICKER_SPAN


## The sword, where it is and for as long as it is out, and never past the floor: a blade reaching
## through a wall is drawn up to the wall.
func _paint_blade() -> void:
	if _blade == null:
		return
	_blade.visible = false
	if not _sim.swinging():
		return
	var box := _sim.sword_box().intersection(_sim.floor_rect())
	if box.size.x <= 0 or box.size.y <= 0:
		return
	_blade.position = _origin + _pixels(box.position)
	_blade.size = _pixels(box.size)
	_blade.visible = true


static func _pixels(units: Vector2i) -> Vector2:
	return Vector2(units) * float(TILE_PX) / float(ArenaSim.UNITS_PER_TILE)


func _text_width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x
