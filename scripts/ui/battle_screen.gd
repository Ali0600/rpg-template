class_name BattleScreen
extends CanvasLayer
## A fight, drawn. BattleLogic decides; this paints, times it, and reports the result.
##
## Built in code from a SpriteStyle like every other view here: a .tscn would hold a colour,
## and a colour outside the style is how a game's chrome stops re-skinning with the rest of it.
##
## It sits above the dialog box and below the pause menu. Neither can be open during a fight -
## a battle takes the input and Router.accepts_world_input() is false throughout - so the
## ordering is a statement of intent rather than a live constraint.
##
## The screen has NO timing code of its own. Every moving thing on it is derived from
## logic.count(), the same number the rules are judging the player's press against, so what the
## player sees and what the fight scores cannot drift apart.
## A sound this view wants played. Emitted rather than played directly, for two reasons.
##
## Signals up, calls down - the world owns the speaker, and a view asking for a noise is the
## same shape as a view asking for anything else. And practically: check.sh's per-file parse
## gate skips any file whose TEXT names an autoload, so calling the audio singleton here would
## quietly drop this file out of that gate, along with every test that depends on it. That is
## not hypothetical - it is how this signal came to exist. Do not name it in prose either.
signal sound_wanted(id: StringName)

signal finished(outcome: int, effects: Array)

const LAYER := 12
const MARGIN := 8
const TITLE_SIZE := 9
const ROW_SIZE := 8
const HELP_SIZE := 7
const ROW_PITCH := 11

## How far a fighter leans in as its blow lands. Pixels, at the sprite's own scale.
const LUNGE := 10.0
const SPRITE_SCALE := 2.0
const BAR_WIDTH := 64.0
const BAR_HEIGHT := 4.0

## Indexed by BattleLogic.Row, so the order is the enum's rather than a second list's.
const COMMANDS: Array[String] = ["Attack", "Item", "Flee"]

var _logic: BattleLogic = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _title := Label.new()
var _help := Label.new()
var _cue := Label.new()
var _message := Label.new()
var _rows: Array[Label] = []

var _hero_view: SpriteView = null
var _foe_view: SpriteView = null
var _hero_home := Vector2.ZERO
var _foe_home := Vector2.ZERO
var _hero_bar := ColorRect.new()
var _hero_fill := ColorRect.new()
var _foe_bar := ColorRect.new()
var _foe_fill := ColorRect.new()
var _hero_label := Label.new()
var _foe_label := Label.new()

var _gate := InputGate.new()

## Set the frame the result goes out, and never cleared. Without it _physics_process emits
## again on every later frame - the fight is still finished() - and the world applies the same
## xp, the same seen key and the same item take once per frame until something notices.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(logic: BattleLogic, style: SpriteStyle, viewport_size: Vector2i,
		source: SpriteSource, hero_character: StringName, foe_character: StringName) -> void:
	_logic = logic
	_style = style
	_build(viewport_size, source, hero_character, foe_character)
	_paint()


func logic() -> BattleLogic:
	return _logic


func _build(viewport_size: Vector2i, source: SpriteSource, hero_character: StringName,
		foe_character: StringName) -> void:
	# Opaque, unlike the pause menu's 0.85. A pause is a moment inside a place and being able
	# to see where you stood is most of what makes it feel like one; a battle is somewhere
	# else, and showing the road behind it would make the fight look like a menu.
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	_title.position = Vector2(MARGIN, MARGIN)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_title)

	var mid := float(viewport_size.y) * 0.5
	_hero_home = Vector2(float(viewport_size.x) * 0.26, mid + 8.0)
	_foe_home = Vector2(float(viewport_size.x) * 0.74, mid + 8.0)
	# The generated walk and idle sheets, unchanged. A battle-only "attack" clip would mean new
	# rig parts, a new clip in SheetBuilder and a change to the sheet contract - so the lunge
	# is done by moving the NODE, which needs none of it and re-skins with everything else.
	_hero_view = _make_fighter(source, hero_character, _hero_home, Dir.D.RIGHT)
	_foe_view = _make_fighter(source, foe_character, _foe_home, Dir.D.LEFT)

	_build_bar(_hero_bar, _hero_fill, _hero_label, Vector2(MARGIN, mid + 24.0))
	_build_bar(_foe_bar, _foe_fill, _foe_label,
		Vector2(float(viewport_size.x) - MARGIN - BAR_WIDTH, mid - 44.0))

	_cue.position = Vector2(0.0, mid - 30.0)
	_cue.size = Vector2(viewport_size.x, 12.0)
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_cue)

	_message.position = Vector2(MARGIN, MARGIN + 14)
	_message.add_theme_font_size_override("font_size", ROW_SIZE)
	add_child(_message)

	for i in COMMANDS.size():
		var row := Label.new()
		row.position = Vector2(MARGIN, float(viewport_size.y) - 16.0 - (COMMANDS.size() - i) * ROW_PITCH)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		add_child(row)
		_rows.append(row)

	_help.position = Vector2(MARGIN, viewport_size.y - 14)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_help)


func _make_fighter(source: SpriteSource, character: StringName, at: Vector2, facing: int) -> SpriteView:
	var view := SpriteView.new()
	add_child(view)
	view.position = at
	view.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	# A fighter whose art is missing still gets a view: the fight is playable without it, and a
	# battle that refused to open would turn a missing PNG into an unreachable quest.
	if view.apply_source(source, character):
		view.set_pose(&"idle", facing)
	return view


func _build_bar(back: ColorRect, fill: ColorRect, label: Label, at: Vector2) -> void:
	back.position = at
	back.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	add_child(back)
	fill.position = at
	fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	add_child(fill)
	label.position = at + Vector2(0.0, BAR_HEIGHT + 1.0)
	label.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(label)


## The clock. One tick of the rules, one repaint, and - once - one result.
func _physics_process(_delta: float) -> void:
	if _logic == null or _committed:
		return
	_logic.tick()
	# Drained HERE and nowhere else. Input arrives in _unhandled_input and queues cues there
	# too, but one drain in the loop picks all of them up on the next frame - and one driver
	# that copes with whatever it finds beats a play() call at every site that might queue
	# something, where the newest site is always the one that forgets.
	for cue in _logic.take_sounds():
		sound_wanted.emit(cue)
	_paint()
	if _logic.finished():
		_committed = true
		finished.emit(_logic.outcome(), _logic.effects())


func _paint() -> void:
	if _style == null or _logic == null:
		return
	var panel := _style.ui_color("panel")
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")

	_backdrop.color = panel
	_title.add_theme_color_override("font_color", text)
	_help.add_theme_color_override("font_color", dim)
	_message.add_theme_color_override("font_color", text)
	_cue.add_theme_color_override("font_color", text)

	_title.text = _logic.enemy_name().to_upper()
	_message.text = _logic.message()
	_help.text = _help_text()

	_paint_bar(_hero_bar, _hero_fill, _hero_label, dim, text,
		_logic.player_hp(), _logic.player_max_hp(),
		"You  Lv%d  %d/%d" % [_logic.player_level(), _logic.player_hp(), _logic.player_max_hp()])
	_paint_bar(_foe_bar, _foe_fill, _foe_label, dim, text,
		_logic.enemy_hp(), _logic.enemy_max_hp(),
		"%s  %d/%d" % [_logic.enemy_name(), _logic.enemy_hp(), _logic.enemy_max_hp()])

	# The one cue the player is reacting to, showing exactly when the rules say the window is
	# open. Reading it from the logic rather than re-deriving a countdown here is what keeps
	# "it looked open" and "it scored as open" the same fact.
	_cue.visible = _logic.cue_on()
	_cue.text = "!"

	_paint_fighters()
	_paint_rows(text, dim)


func _paint_bar(back: ColorRect, fill: ColorRect, label: Label, dim: Color, text: Color,
		value: int, most: int, caption: String) -> void:
	back.color = dim
	fill.color = text
	fill.size = Vector2(BAR_WIDTH * (float(maxi(value, 0)) / float(maxi(most, 1))), BAR_HEIGHT)
	label.add_theme_color_override("font_color", text)
	label.text = caption


## Where the fighters stand this frame, derived entirely from the countdown. No tween, no timer
## and nothing to reset: at any frame the pose is a pure function of the fight's own state, so
## a battle replayed from the same seed draws identically.
func _paint_fighters() -> void:
	var acting := _logic.phase() == BattleLogic.Phase.PLAYER_ACT \
		or _logic.phase() == BattleLogic.Phase.ENEMY_ACT
	var player_side := _logic.acting_side_is_player()
	var cue := maxi(_logic.count(), 0)
	var reach := 0.0
	if acting:
		# Furthest forward at the moment of impact, which is where the window is - and
		# measured against the cue's OWN length, asked of the logic rather than kept here.
		# A hardcoded span makes the lean finish early on a longer cue and never arrive on a
		# shorter one, so a retune of the timing would silently stop the wind-up reading as
		# one. That matters more than it looks: the lean is the anticipation the player is
		# reacting to, and the `!` only lights once the window is already open.
		var span := float(maxi(_logic.cue_span(), 1))
		reach = LUNGE * (1.0 - clampf(float(maxi(cue, 0)) / span, 0.0, 1.0))

	if _hero_view != null:
		_hero_view.position = _hero_home + Vector2(reach if acting and player_side else 0.0, 0.0)
		_hero_view.set_pose(&"walk" if acting and player_side else &"idle", Dir.D.RIGHT)
	if _foe_view != null:
		_foe_view.position = _foe_home - Vector2(reach if acting and not player_side else 0.0, 0.0)
		_foe_view.set_pose(&"walk" if acting and not player_side else &"idle", Dir.D.LEFT)


func _paint_rows(text: Color, dim: Color) -> void:
	var choosing := _logic.phase() == BattleLogic.Phase.MENU \
		or _logic.phase() == BattleLogic.Phase.ITEMS
	for i in _rows.size():
		var row := _rows[i]
		# Rows past the current page's list are hidden rather than blanked: an empty label
		# still occupies its line, and everything below it would drift.
		row.visible = choosing and i < _logic.size()
		if not row.visible:
			continue
		var selected := i == _logic.index()
		row.text = ("> " if selected else "  ") + _label_for(i)
		row.add_theme_color_override("font_color", text if selected else dim)


func _label_for(at: int) -> String:
	if _logic.phase() == BattleLogic.Phase.ITEMS:
		var row: BattleLogic.ItemRow = _logic.item_row(at)
		if row == null:
			return "(nothing useful)"
		return "%s x%d" % [row.name, row.count] if row.count > 1 else row.name
	return COMMANDS[at]


func _help_text() -> String:
	match _logic.phase():
		BattleLogic.Phase.ITEMS:
			return "W/S to choose    E to use    Esc to go back"
		BattleLogic.Phase.MENU:
			return "W/S to choose    E to pick"
		BattleLogic.Phase.PLAYER_ACT, BattleLogic.Phase.ENEMY_ACT:
			return "E on the !"
		_:
			return ""


func _unhandled_input(event: InputEvent) -> void:
	if _committed or _logic == null or not event.is_pressed() or event.is_echo():
		return
	if not _gate.accept(event):
		return

	if event.is_action(&"move_down"):
		_logic.move(1)
	elif event.is_action(&"move_up"):
		_logic.move(-1)
	elif event.is_action(&"interact"):
		_logic.press()
	elif event.is_action(&"cancel"):
		_logic.cancel()
	else:
		return
	_paint()
	get_viewport().set_input_as_handled()
