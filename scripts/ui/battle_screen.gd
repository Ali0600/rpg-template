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

## The bottom band, as two columns: the list on the LEFT growing DOWN from ROWS_Y in a fixed
## number of slots, and the player's own block on the RIGHT, mirroring the enemy's at the top.
## That is the layout every game this borrows from uses, and here it is also the fix for a
## shipped bug - the list used to grow UPWARD from the bottom by however many rows the page
## had, so inserting the Magic command moved its top row onto the player's status line.
##
## FIXED rather than derived from the page. A stack sized to its contents eventually reaches
## whatever is above it, and no amount of choosing good numbers prevents that - only a bound
## does. A page longer than the window SCROLLS; see _first_visible.
const ROWS_Y := 120.0
const VISIBLE_ROWS := 4
const HERO_BAR_Y := 120.0

## How many fighters this screen can draw on the player's side, and therefore how large a party
## a game on this template may declare. THE CAPACITY IS THE CONTENT CONTRACT, not an
## implementation detail: a view that renders data has a bound, and the failure mode of "too
## many to draw" is silence, so the build enforces this rather than the screen coping. Stated
## once here and read by the gate, because two copies is how the check and the thing checked
## drift apart.
##
## Three is what the band between the fighters' feet and the help line holds at 320x180 with a
## bar and a legible caption each, and it is the genre's own common size - Chrono Trigger's
## active three, Dragon Quest II's full party.
const MAX_PARTY := 3
## Where a party of two or more stacks, and how far apart. A party of ONE keeps HERO_BAR_Y and
## a separate MP line, which is the layout that shipped and the one the layout audit pins.
## Sharing the band is what makes the block compact: at one member there is room for two lines,
## and at three there is not.
const MEMBERS_Y := 112.0
const MEMBER_PITCH := 17.0

## How far a fighter leans in as its blow lands. Pixels, at the sprite's own scale.
const LUNGE := 10.0
const SPRITE_SCALE := 2.0
const BAR_WIDTH := 64.0
const BAR_HEIGHT := 4.0

## Indexed by BattleLogic.Row, so the order is the enum's rather than a second list's.
const COMMANDS: Array[String] = ["Attack", "Magic", "Item", "Flee"]

var _logic: BattleLogic = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _title := Label.new()
var _help := Label.new()
var _cue := Label.new()
var _message := Label.new()
var _rows: Array[Label] = []

## One entry per member, all four lists index-aligned with the logic's own party order.
var _member_views: Array[SpriteView] = []
var _member_homes: Array[Vector2] = []
var _member_bars: Array[ColorRect] = []
var _member_fills: Array[ColorRect] = []
var _member_labels: Array[Label] = []
var _foe_view: SpriteView = null
var _foe_home := Vector2.ZERO
var _foe_bar := ColorRect.new()
var _foe_fill := ColorRect.new()
## The magic line, drawn only for a party of ONE - at two or more it folds into the caption,
## because there is no room for a second line each.
var _hero_mp := Label.new()
var _foe_label := Label.new()

var _gate := InputGate.new()

## Set the frame the result goes out, and never cleared. Without it _physics_process emits
## again on every later frame - the fight is still finished() - and the world applies the same
## xp, the same seen key and the same item take once per frame until something notices.
var _committed := false


func _ready() -> void:
	layer = LAYER


## The party's art is not passed in any more: each member carries their own, so the screen asks
## the fight who it is drawing rather than being told once about a hero.
func setup(logic: BattleLogic, style: SpriteStyle, viewport_size: Vector2i,
		source: SpriteSource, foe_character: StringName) -> void:
	_logic = logic
	_style = style
	_build(viewport_size, source, foe_character)
	_paint()


func logic() -> BattleLogic:
	return _logic


func _build(viewport_size: Vector2i, source: SpriteSource, foe_character: StringName) -> void:
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
	var count := _logic.member_count()
	_foe_home = Vector2(float(viewport_size.x) * 0.74, mid + 8.0)
	# The generated walk and idle sheets, unchanged. A battle-only "attack" clip would mean new
	# rig parts, a new clip in SheetBuilder and a change to the sheet contract - so the lunge
	# is done by moving the NODE, which needs none of it and re-skins with everything else.
	#
	# A party stands in a staggered file rather than a row: back and up, so nobody is hidden
	# behind the member in front and the one who is swinging still has room to lean.
	for i in count:
		var home := Vector2(float(viewport_size.x) * 0.26 - i * 18.0, mid + 8.0 - i * 14.0)
		_member_homes.append(home)
		_member_views.append(_make_fighter(source, _logic.member_character(i), home,
			Dir.D.RIGHT))
	_foe_view = _make_fighter(source, foe_character, _foe_home, Dir.D.LEFT)

	var right := float(viewport_size.x) - MARGIN
	# The party's blocks are the bottom-right corner, mirroring the enemy's top-right one, and
	# every text line is RIGHT-ALIGNED so it ends at the edge instead of starting at it.
	# Left-aligned, a status line that grows simply runs off the screen - the same class of
	# bug as one that grows into its neighbour, and quieter.
	for i in count:
		var bar := ColorRect.new()
		var fill := ColorRect.new()
		var label := Label.new()
		_build_bar(bar, fill, label, Vector2(right - BAR_WIDTH, _member_block_y(i, count)))
		_align_right(label, right)
		_member_bars.append(bar)
		_member_fills.append(fill)
		_member_labels.append(label)
	# The magic line only shows at ONE member - at two or more it folds into the caption,
	# because a second line each is what the band does not have room for. Built and parented
	# either way and hidden by its own caption, because a node created and never added to the
	# tree is a node nothing will ever free.
	_hero_mp.position = Vector2(MARGIN, HERO_BAR_Y + BAR_HEIGHT + 10.0)
	_hero_mp.add_theme_font_size_override("font_size", HELP_SIZE)
	_align_right(_hero_mp, right)
	add_child(_hero_mp)
	_build_bar(_foe_bar, _foe_fill, _foe_label, Vector2(right - BAR_WIDTH, mid - 44.0))

	_cue.position = Vector2(0.0, mid - 30.0)
	_cue.size = Vector2(viewport_size.x, 12.0)
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_cue)

	_message.position = Vector2(MARGIN, MARGIN + 14)
	_message.add_theme_font_size_override("font_size", ROW_SIZE)
	add_child(_message)

	# A FIXED window of slots, at fixed positions. The pool used to be sized to the longest page
	# the fight could show, which fixed a truncation - a row with no label is one the player
	# cannot see and therefore cannot cast - and traded it for an unbounded stack: six spells
	# would have put the top row up among the fighters. A window bounds both, because a page
	# longer than it scrolls instead of growing.
	for i in VISIBLE_ROWS:
		var row := Label.new()
		row.position = Vector2(MARGIN, ROWS_Y + i * ROW_PITCH)
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


## Makes a label's text END at `right` rather than start where it was put. The box spans the
## whole width, which costs nothing - only the text is drawn - and means a line of any length
## stays anchored to the corner it belongs to.
func _align_right(label: Label, right: float) -> void:
	label.position.x = MARGIN
	label.size.x = right - MARGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


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


## Where one member's bar sits. A party of ONE keeps exactly where it shipped, which is what
## makes a solo fight pixel-identical to every screenshot and every layout assertion taken
## before parties existed; two or more share the band from MEMBERS_Y down.
func _member_block_y(at: int, count: int) -> float:
	if count <= 1:
		return HERO_BAR_Y
	return MEMBERS_Y + at * MEMBER_PITCH


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

	for i in _member_labels.size():
		# A fallen member's own numbers, dimmed rather than hidden: they are still in the party
		# and still the thing an inn will put back up, and a row that vanished would read as
		# somebody having left.
		_paint_bar(_member_bars[i], _member_fills[i], _member_labels[i], dim,
			dim if _logic.member_down(i) else text,
			_logic.member_hp(i), _logic.member_max_hp(i), _member_caption(i))
	_hero_mp.text = _hero_mp_caption()
	_hero_mp.visible = not _hero_mp.text.is_empty()
	_hero_mp.add_theme_color_override("font_color", text)
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


## What one member is worth. At ONE member this is exactly the line that shipped - the name is
## "You" because the world synthesizes the solo leader with that name, so there is no branch
## here for it - and the magic half is a second line below. At two or more the magic folds in
## and a marker says whose turn it is to give an order, or who is about to be hit.
##
## The magic half only exists for a game that has magic: a "0 MP" on a game with no spells is
## a stat the player can do nothing about and would spend the whole run wondering at.
func _member_caption(at: int) -> String:
	var line := "%s  Lv%d  %d/%d" % [_logic.member_name(at), _logic.member_level(at),
		_logic.member_hp(at), _logic.member_max_hp(at)]
	if _logic.member_count() > 1:
		if _logic.member_max_mp(at) > 0:
			line += "  MP %d/%d" % [_logic.member_mp(at), _logic.member_max_mp(at)]
		line = ("> " if _marked(at) else "  ") + line
	return line


## Whether this member is the one the screen should point at right now: the one being asked for
## an order, or the one the enemy has aimed at. Never both at once - the fight is either taking
## orders or swinging.
func _marked(at: int) -> bool:
	if _logic.commander() == at:
		return true
	return _logic.phase() == BattleLogic.Phase.ENEMY_ACT and _logic.target_member() == at


func _hero_mp_caption() -> String:
	if _logic.member_count() != 1 or _logic.member_max_mp(0) <= 0:
		return ""
	return "MP %d/%d" % [_logic.member_mp(0), _logic.member_max_mp(0)]


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
	var player_side := _logic.phase() == BattleLogic.Phase.PLAYER_ACT
	var swinging := _logic.acting_member()
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

	for i in _member_views.size():
		# Only the member actually swinging leans; the rest hold their ground, which is what
		# makes it readable at a glance who the blow belongs to.
		var mine := acting and player_side and swinging == i
		_member_views[i].position = _member_homes[i] + Vector2(reach if mine else 0.0, 0.0)
		_member_views[i].set_pose(&"walk" if mine else &"idle", Dir.D.RIGHT)
	if _foe_view != null:
		_foe_view.position = _foe_home - Vector2(reach if acting and not player_side else 0.0, 0.0)
		_foe_view.set_pose(&"walk" if acting and not player_side else &"idle", Dir.D.LEFT)


func _paint_rows(text: Color, dim: Color) -> void:
	var choosing := _logic.phase() == BattleLogic.Phase.MENU \
		or _logic.phase() == BattleLogic.Phase.ITEMS \
		or _logic.phase() == BattleLogic.Phase.SPELLS \
		or _logic.phase() == BattleLogic.Phase.ALLY
	var first := _first_visible()
	for i in _rows.size():
		var row := _rows[i]
		var at := first + i
		# Rows past the current page's list are hidden rather than blanked: an empty label
		# still occupies its line, and everything below it would drift.
		row.visible = choosing and at < _logic.size()
		if not row.visible:
			continue
		var selected := at == _logic.index()
		row.text = ("> " if selected else "  ") + _label_for(at)
		# A spell out of reach of the purse is drawn dim even under the cursor, so the answer
		# to "can I cast this" is on screen BEFORE the press rather than only in the refusal.
		# Affordability is asked of the logic, never recomputed here, or the screen and the
		# rule could disagree about the same spell.
		var reachable := _logic.phase() != BattleLogic.Phase.SPELLS \
			or _logic.can_afford(_logic.spell_row(at))
		row.add_theme_color_override("font_color", text if selected and reachable else dim)


## Which entry the top slot shows. A pure function of the cursor and the page's length, with
## no scroll offset kept anywhere: state would have to be reset on every page change and on
## every refresh, and the one that forgets leaves the window pointing into the wrong list.
##
## The window follows the cursor at its BOTTOM edge, so moving down through a long page slides
## it one row at a time and wrapping back to the top snaps it home.
func _first_visible() -> int:
	var count := _logic.size()
	if count <= VISIBLE_ROWS:
		return 0
	return clampi(_logic.index() - VISIBLE_ROWS + 1, 0, count - VISIBLE_ROWS)


func _label_for(at: int) -> String:
	if _logic.phase() == BattleLogic.Phase.ITEMS:
		var row: BattleLogic.ItemRow = _logic.item_row(at)
		if row == null:
			return "(nothing useful)"
		return "%s x%d" % [row.name, row.count] if row.count > 1 else row.name
	if _logic.phase() == BattleLogic.Phase.SPELLS:
		var spell: BattleLogic.SpellRow = _logic.spell_row(at)
		# The empty page is worded as "not yet" rather than "none": spells arrive with levels,
		# so a player who has none has not failed to find any, they have not got there.
		if spell == null:
			return "(nothing learned yet)"
		return "%s  %d MP" % [spell.name, spell.cost]
	if _logic.phase() == BattleLogic.Phase.ALLY:
		var rows := _logic.ally_rows()
		if at < 0 or at >= rows.size():
			return ""
		var who := rows[at]
		return "%s  %d/%d" % [_logic.member_name(who), _logic.member_hp(who),
			_logic.member_max_hp(who)]
	return COMMANDS[at]


func _help_text() -> String:
	match _logic.phase():
		BattleLogic.Phase.SPELLS:
			return "W/S to choose    E to cast    Esc to go back"
		BattleLogic.Phase.ITEMS:
			return "W/S to choose    E to use    Esc to go back"
		BattleLogic.Phase.ALLY:
			return "W/S to choose who    E to confirm    Esc to go back"
		BattleLogic.Phase.MENU:
			# Whose orders are being taken, once there is more than one member to ask - without
			# it a player with two fighters has to infer from the marker which menu this is.
			if _logic.member_count() > 1 and _logic.commander() >= 0:
				return "%s: W/S to choose    E to pick" % _logic.member_name(_logic.commander())
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
