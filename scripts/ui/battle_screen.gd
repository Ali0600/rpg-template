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
const TITLE_SIZE := UiChrome.FONT_SIZE
const ROW_SIZE := UiChrome.FONT_SIZE

## How many lines the caption may take, and a DECLARED capacity in `MAX_PARTY`'s sense: the
## layout audit measures against it, so it is a promise the view has to keep rather than a note.
##
## THREE, and it was two until M37 measured the caption that milestone produces. Sequencing a
## sweep made the caption a FRAME LINE plus a target line, and the target line can wrap on its
## own - so at the capacity this view declares, with names as long as the layout audit
## deliberately uses, two was not enough. Three is EarthBound's own in-battle box and well inside
## the room between here and the foe bars.
##
## Every reference battle message area holds more than one line (Pokemon 2, EarthBound 3, Dragon
## Warrior 8) and Dragon Warrior word-wraps into them automatically; a one-line caption was this
## screen's divergence, and M36 closed it. `DialogBox` still draws two, which is a different
## surface with a different budget rather than a number these two must share.
const MESSAGE_LINES := 3
const HELP_SIZE := UiChrome.FONT_SIZE
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
## THE BANDS, top to bottom, in design pixels. Every one of these was a loose number before M42
## and they are written together now because they are one budget: 180 pixels, shared out.
##
##   4..26    the foes' banner - who is in front of you, and how the one you are aiming at is
##   28..52   the caption, MESSAGE_LINES lines of it
##   ..102    the field: fighters stand with their FEET on FLOOR_Y
##   106..164 the two windows - commands on the left, the party on the right
##   168..    the help line
##
## The tightest of them is the field. A dusk16 fighter draws 48 design pixels tall where an lpc32
## one draws 32, so the taller one is what decides where the caption may end and where the windows
## may start - and the audit measures every band at the capacity this view declares.
const BANNER_Y := 4.0
## Two lines of the font inside the border and padding: the names, then the bar and its figures.
const BANNER_HEIGHT := 24.0
const CAPTION_Y := 30.0
## Where a fighter's FEET are. Everything above it is the caption's, everything below the two
## windows' - and the tallest fighter any style draws is 48 design pixels, which is what decides
## both edges: 104 - 48 clears the caption by two, and 104 clears the windows by two.
const FLOOR_Y := 104.0
const PANELS_Y := 106.0
const PANELS_HEIGHT := 60.0
## The command window and the party window split the bottom band, left and right. Sea of Stars'
## own arrangement: the list of what you can do sits beside the people who can do it.
const COMMANDS_WIDTH := 140.0
const PARTY_X := 150.0

const VISIBLE_ROWS := 4

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
## How tall one member's block is inside the party window, and how far apart they sit. A block is
## two lines of the font - a name, then the bars and their figures - and the pitch is one more, so
## there is a pixel of air between one member and the next rather than a wall of numbers.
const BLOCK_HEIGHT := 16.0
const BLOCK_PITCH := 17.0

## The same contract on the other side: how many foes this screen can draw, and therefore how
## large a formation a map record may name. Three for the same reason as MAX_PARTY - it is what
## the banner names on one line at the widest names the layout audit uses, and it is the size the
## genre's own small fights come in.
const MAX_FOES := 3

## The same contract on the other side: how many foes this screen can draw, and therefore how
## large a formation a map record may name. Three for the same reason - it is what the band
## above the cue line holds, and it is the size the genre's own small fights come in.
##

## How far a fighter leans in as its blow lands. Pixels, at the sprite's own scale.
const LUNGE := 10.0
## The drawn width the file's 18/14 stagger was chosen against - a 16px cell at twice size.
## Everything about the group's shape is stated as a fraction of this, so a style with wider
## fighters keeps the file rather than stacking them on top of one another. A historical fact
## about these numbers rather than a multiple anything is drawn at, which is why it stayed here
## when the multiple itself moved into the style.
const STAGGER_WIDTH := 32.0
## How wide a member's bars are inside their block, and how wide the banner's one foe bar is.
## The foe's is wider because it is the only one up there and it is what the player is aiming at.
## How much of a fallen member's face is left. Faded rather than hidden: they are still in the
## party and still what an inn will put back up, and a face that vanished would read as somebody
## having left the fight.
const DOWN_FADE := 0.4
const BAR_WIDTH := 26.0
const FOE_BAR_WIDTH := 80.0

## Indexed by BattleLogic.Row, so the order is the enum's rather than a second list's.
const COMMANDS: Array[String] = ["Attack", "Magic", "Item", "Flee"]

var _logic: BattleLogic = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _help := Label.new()
var _cue := Label.new()
var _message := Label.new()

## The foes' banner: who is in front of you, and one bar for the one you are aiming at.
##
## ONE bar rather than one each, which is what M28 shipped and what put a readout on top of every
## sprite it belonged to. Eight reference games and not one draws a bar per enemy - Sea of Stars
## and Persona 5 draw none at all, Clair Obscur draws exactly this: a single bar for the target,
## with the rest of the formation named and nothing more. See docs/DECISIONS.md.
var _banner: UiChrome.Frame = null
var _foe_names: Array[Label] = []
var _foe_bar: UiChrome.Bar = null

## The command window, headed with whoever's turn it is.
var _commands: UiChrome.Frame = null
var _rows: Array[Label] = []
var _select: ColorRect = null

## The party window: one block per member - a face, a name, and two bars.
var _party: UiChrome.Frame = null
var _party_mark: ColorRect = null
var _faces: Array[TextureRect] = []
var _member_labels: Array[Label] = []
var _hp_bars: Array[UiChrome.Bar] = []
var _mp_bars: Array[UiChrome.Bar] = []

## One entry per fighter, index-aligned with the logic's own order.
var _member_views: Array[SpriteView] = []
var _member_homes: Array[Vector2] = []
var _foe_views: Array[SpriteView] = []
var _foe_homes: Array[Vector2] = []

var _gate := InputGate.new()

## Set the frame the result goes out, and never cleared. Without it _physics_process emits
## again on every later frame - the fight is still finished() - and the world applies the same
## xp, the same seen key and the same item take once per frame until something notices.
var _committed := false


func _ready() -> void:
	layer = LAYER


## Nobody's art is passed in any more. The party's stopped being when members gained their own;
## the foe's stops now for the same reason, because a formation has as many as it has - so the
## screen asks the fight who it is drawing rather than being told once about a hero and a foe.
func setup(logic: BattleLogic, style: SpriteStyle, viewport_size: Vector2i,
		source: SpriteSource) -> void:
	_logic = logic
	_style = style
	_build(viewport_size, source)
	_paint()


func logic() -> BattleLogic:
	return _logic


func _build(viewport_size: Vector2i, source: SpriteSource) -> void:
	# Opaque, unlike the pause menu's 0.85. A pause is a moment inside a place and being able
	# to see where you stood is most of what makes it feel like one; a battle is somewhere
	# else, and showing the road behind it would make the fight look like a menu.
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	var wide := float(viewport_size.x)
	var edge := float(UiChrome.PAD) + float(UiChrome.BORDER)
	_build_banner(wide)

	_message.position = Vector2(MARGIN, CAPTION_Y)
	_message.add_theme_font_size_override("font_size", ROW_SIZE)
	# WRAPS, and a Label does not do that on its own: with no width set it has nothing to wrap
	# against, and with no clip it draws straight past the window edge - where the text is not
	# truncated, it is simply somewhere the player cannot see. Measured at the capacity this view
	# DECLARES (MAX_PARTY members, MAX_FOES foes, a sweep that fells two of them), the caption ran
	# to 451px in a 320px window.
	#
	# Three lines rather than one is also the genre's own shape, and this screen was the outlier:
	# every reference battle message area holds more than one line - Pokemon 2, EarthBound 3,
	# Dragon Warrior 8 - and Dragon Warrior word-wraps into them automatically.
	# See docs/GENRE_CONVENTIONS.md S7c.
	_message.size.x = wide - MARGIN * 2.0
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	_build_field(viewport_size, source)

	# The cue sits BETWEEN the two sides, in the gap the fighters leave down the middle of the
	# field - the one place on this screen nothing else is drawn, which is where the thing a
	# player is reacting to belongs.
	_cue.position = Vector2(0.0, FLOOR_Y - 32.0)
	_cue.size = Vector2(wide, 12.0)
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue.add_theme_font_size_override("font_size", TITLE_SIZE)
	add_child(_cue)

	_build_commands(edge)
	_build_party(wide, edge, source)

	_help.position = Vector2(MARGIN, float(viewport_size.y) - 12.0)
	_help.add_theme_font_size_override("font_size", HELP_SIZE)
	add_child(_help)


## The foes' banner: their names on one line, and under it a single bar for whichever one the
## player is aiming at. A name per foe rather than one joined string, because each is lit or
## dimmed on its own - which is how the banner says which of them the bar is about.
func _build_banner(wide: float) -> void:
	_banner = UiChrome.frame(_style, Rect2(MARGIN - 2.0, BANNER_Y,
		wide - (MARGIN - 2.0) * 2.0, BANNER_HEIGHT))
	add_child(_banner.panel)
	var inner := _banner.inner()
	var at := inner.position
	for i in _logic.foe_count():
		var name_label := UiChrome.label(_style, "text")
		name_label.position = at
		_banner.panel.add_child(name_label)
		_foe_names.append(name_label)
		at.x += 4.0
	_foe_bar = UiChrome.bar(_style, "hp", FOE_BAR_WIDTH)
	_foe_bar.root.position = Vector2(inner.position.x, inner.position.y + 10.0)
	_banner.panel.add_child(_foe_bar.root)


## The field: two staggered files of fighters, feet on FLOOR_Y.
func _build_field(viewport_size: Vector2i, source: SpriteSource) -> void:
	# The generated walk and idle sheets, unchanged. A battle-only "attack" clip would mean new
	# rig parts, a new clip in SheetBuilder and a change to the sheet contract - so the lunge
	# is done by moving the NODE, which needs none of it and re-skins with everything else.
	#
	# A party stands in a staggered file rather than a row: back and up, so nobody is hidden
	# behind the member in front and the one who is swinging still has room to lean.
	#
	# The step between them is a fraction of how wide a fighter DRAWS, not a flat number of
	# pixels: 18 and 14 were chosen against a 16x24 cell at twice size, and a style whose
	# fighters are twice that wide needs twice the room to keep the same file.
	var step := _drawn_width() / STAGGER_WIDTH
	for i in _logic.member_count():
		var home := Vector2(float(viewport_size.x) * 0.26 - i * 18.0 * step,
			FLOOR_Y - i * 14.0 * step)
		_member_homes.append(home)
		_member_views.append(_make_fighter(source, _logic.member_character(i), home,
			Dir.D.RIGHT))
	# The formation stands in the mirror of that file - back and up the other way, so the first
	# foe is where the only foe always stood and the rest step behind it.
	for at in _logic.foe_count():
		var spot := Vector2(float(viewport_size.x) * 0.74 + at * 18.0 * step,
			FLOOR_Y - at * 14.0 * step)
		_foe_homes.append(spot)
		_foe_views.append(_make_fighter(source, _logic.foe_character(at), spot, Dir.D.LEFT))


## The command window, headed with the name of whoever is choosing. Sea of Stars' own shape, and
## the reason it is headed at all: with a party, the menu is a question addressed to somebody.
##
## A FIXED window of slots, at fixed positions. The pool used to be sized to the longest page
## the fight could show, which fixed a truncation - a row with no label is one the player
## cannot see and therefore cannot cast - and traded it for an unbounded stack: six spells
## would have put the top row up among the fighters. A window bounds both, because a page
## longer than it scrolls instead of growing.
func _build_commands(edge: float) -> void:
	_commands = UiChrome.frame(_style, Rect2(MARGIN - 2.0, PANELS_Y, COMMANDS_WIDTH,
		PANELS_HEIGHT), " ")
	add_child(_commands.panel)
	var inner := _commands.inner()
	# Added BEFORE the rows, so it is drawn behind them: this is a bar the text sits ON.
	_select = UiChrome.select(_style)
	_commands.panel.add_child(_select)
	for i in VISIBLE_ROWS:
		var row := UiChrome.label(_style, "text")
		row.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
			inner.position.y + i * ROW_PITCH)
		_commands.panel.add_child(row)
		_rows.append(row)


## The party window: one block per member - their face, their name and level, and their two bars
## beside it. ONE shape whatever the party's size, which is what retired the old screen's two:
## a solo hero had a bar and a separate magic line, a party had neither, and the two layouts had
## to be kept true separately.
func _build_party(wide: float, edge: float, source: SpriteSource) -> void:
	_party = UiChrome.frame(_style, Rect2(PARTY_X, PANELS_Y,
		wide - PARTY_X - (MARGIN - 2.0), PANELS_HEIGHT))
	add_child(_party.panel)
	var inner := _party.inner()
	_party_mark = UiChrome.select(_style)
	_party.panel.add_child(_party_mark)
	var face_span := UiChrome.portrait_span(_style)
	var text_x := inner.position.x + face_span + 3.0
	for i in _logic.member_count():
		var top := inner.position.y + i * BLOCK_PITCH
		var face := UiChrome.portrait(_style, source, _logic.member_character(i))
		face.position = Vector2(inner.position.x, top + 2.0)
		_party.panel.add_child(face)
		_faces.append(face)
		var name_label := UiChrome.label(_style, "text")
		name_label.position = Vector2(text_x, top)
		_party.panel.add_child(name_label)
		_member_labels.append(name_label)
		# The bars share the block's SECOND line: their figures are a line of the font and the
		# track is centred in it, so a block is exactly two lines tall and the mark that covers
		# one covers all of it.
		var hp := UiChrome.bar(_style, "hp", BAR_WIDTH)
		hp.root.position = Vector2(text_x, top + 10.0)
		_party.panel.add_child(hp.root)
		_hp_bars.append(hp)
		var mp := UiChrome.bar(_style, "mp", BAR_WIDTH)
		mp.root.position = Vector2(text_x + 64.0, top + 10.0)
		_party.panel.add_child(mp.root)
		_mp_bars.append(mp)


## How wide one fighter draws, in the units this screen lays out in.
func _drawn_width() -> float:
	return float(_style.cell_size.x) * _fighter_scale()


## How many of THIS SCREEN's pixels one of a fighter's own pixels covers. The style says how
## many times world size a fighter is drawn at; the division is because this screen is a
## CanvasLayer already drawn at the world's scale, so a bare 2.0 under a 2x layer would put a
## 64px cell across 128 of the 180 design pixels this layout was measured for.
##
## The numerator moved into the style in M42 and the divisor stayed, which is exactly the hook
## DECISIONS named when it deferred this. lpc32 asks for 1 and gets world size: the size that
## character is when you walk around as them.
func _fighter_scale() -> float:
	return float(_style.battle_sprite_scale) / float(UiScale.scale_of(_style))


func _make_fighter(source: SpriteSource, character: StringName, at: Vector2, facing: int) -> SpriteView:
	var view := SpriteView.new()
	add_child(view)
	view.position = at
	var drawn := _fighter_scale()
	view.scale = Vector2(drawn, drawn)
	# A fighter whose art is missing still gets a view: the fight is playable without it, and a
	# battle that refused to open would turn a missing PNG into an unreachable quest.
	if view.apply_source(source, character):
		view.set_pose(&"idle", facing)
	return view


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
	_help.add_theme_color_override("font_color", dim)
	_message.add_theme_color_override("font_color", text)
	_cue.add_theme_color_override("font_color", text)

	_message.text = _logic.message()
	_help.text = _help_text()

	_paint_banner(text, dim)
	_paint_party(text, dim)

	# The one cue the player is reacting to, showing exactly when the rules say the window is
	# open. Reading it from the logic rather than re-deriving a countdown here is what keeps
	# "it looked open" and "it scored as open" the same fact.
	_cue.visible = _logic.cue_on()
	_cue.text = "!"

	_paint_fighters()
	_paint_rows(text, dim)


## The formation, named, with one bar under it for the foe being aimed at.
##
## A felled foe dims and stays: something that vanished mid-fight would read as having fled, and
## the formation is what the player is counting down.
func _paint_banner(text: Color, dim: Color) -> void:
	var shown := _shown_foe()
	var at := _banner.inner().position
	for i in _foe_names.size():
		var label := _foe_names[i]
		label.text = _logic.enemy_name(i) + _tag_suffix(_logic.foe_tag(i))
		label.position.x = at.x
		# Lit when this is the one the bar is about, dim otherwise - which is how a line of names
		# says which of them the number below belongs to, with no second marker to read.
		label.add_theme_color_override("font_color",
			dim if _logic.foe_down(i) else (text if i == shown else dim))
		at.x += _text_width(label) + 8.0
	UiChrome.fill(_foe_bar, _logic.enemy_hp(shown), _logic.enemy_max_hp(shown))
	_foe_bar.numbers.add_theme_color_override("font_color", text)


## Which foe the banner's bar is about: the one the cursor is over, or the one a blow is on its
## way to, and otherwise the first still standing. Never nothing - a bar with no subject would
## blink out between turns, and the player is aiming at somebody the whole time.
func _shown_foe() -> int:
	if _logic.phase() == BattleLogic.Phase.FOE:
		var rows := _logic.foe_rows()
		var row := _logic.index()
		if row >= 0 and row < rows.size():
			return rows[row]
	var struck := _logic.struck_foe()
	if struck >= 0 and struck < _logic.foe_count():
		return struck
	for i in _logic.foe_count():
		if not _logic.foe_down(i):
			return i
	return 0


## One block per member: their face, their name and level, and their two bars.
##
## A fallen member's own numbers, dimmed rather than hidden: they are still in the party and
## still the thing an inn will put back up, and a row that vanished would read as somebody
## having left.
func _paint_party(text: Color, dim: Color) -> void:
	var marked := marked_member()
	for i in _member_labels.size():
		var down := _logic.member_down(i)
		var lit := dim if down else text
		_member_labels[i].text = "%s  Lv%d" % [_logic.member_name(i), _logic.member_level(i)] \
			+ _tag_suffix(_logic.member_tag(i))
		_member_labels[i].add_theme_color_override("font_color", lit)
		# A face FADES with its owner rather than vanishing, for the caption's reason. Done with
		# the node's own alpha rather than a colour, which keeps this file free of one: a colour
		# typed in scripts/ui/ is a build failure, and rightly - it is how chrome stops re-skinning.
		_faces[i].modulate.a = DOWN_FADE if down else 1.0
		UiChrome.fill(_hp_bars[i], _logic.member_hp(i), _logic.member_max_hp(i))
		_hp_bars[i].numbers.add_theme_color_override("font_color", lit)
		# The magic bar only exists for a game that has magic: an empty one on a game with no
		# spells is a stat the player can do nothing about and would spend the whole run
		# wondering at.
		var casts := _logic.member_max_mp(i) > 0
		_mp_bars[i].root.visible = casts
		if casts:
			UiChrome.fill(_mp_bars[i], _logic.member_mp(i), _logic.member_max_mp(i))
			_mp_bars[i].numbers.add_theme_color_override("font_color", lit)
	# The mark moves once, when the turn does. It covers the whole block rather than a line of
	# it, because what it is marking is a person rather than a row.
	_party_mark.visible = marked >= 0 and marked < _member_labels.size()
	if _party_mark.visible:
		var inner := _party.inner()
		_party_mark.position = Vector2(inner.position.x - float(UiChrome.ROW_INSET),
			inner.position.y + marked * BLOCK_PITCH)
		_party_mark.size = Vector2(inner.size.x + float(UiChrome.ROW_INSET), BLOCK_HEIGHT)


## How wide a label's text actually is, which is what a row of names has to be stepped by.
func _text_width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x


## A status tag as it is written into a caption, or nothing at all. One function for both sides,
## so the party and the formation can never come to spell the same condition differently.
func _tag_suffix(tag: String) -> String:
	return "" if tag.is_empty() else "  " + tag


## Which member the screen is pointing at right now: the one whose turn it is, or the one the
## enemy has aimed at, and -1 for neither. Never both at once, because nobody on the player's
## side holds the turn while the enemy has it.
##
## The mark stays put across a member's whole turn - choosing AND swinging - which is what makes
## it readable: it moves once, when the turn does, rather than blinking off at the press.
##
## Published because it is what the layout audit asks. It used to be readable only by looking for
## a "> " on the front of a caption, which made the marker part of a STRING - so a test that
## wanted to know who was marked had to parse text, and the text moved sideways to hold it.
func marked_member() -> int:
	var commander := _logic.commander()
	if commander >= 0:
		return commander
	if _logic.phase() == BattleLogic.Phase.ENEMY_ACT:
		return _logic.target_member()
	return -1


## And which foe, which is the one the banner's bar is about.
func marked_foe() -> int:
	return _shown_foe()


## The row the cursor is on, or null when the page has nothing to press. What replaced reading
## a "> " off the front of a row's text.
func selected_row() -> Label:
	if not _is_choosing():
		return null
	var at := _logic.index() - _first_visible()
	if at < 0 or at >= _rows.size() or not _rows[at].visible:
		return null
	return _rows[at]


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
	var swinging_foe := _logic.acting_foe()
	for at in _foe_views.size():
		# And only the foe taking its turn, for the same reason. With a formation acting one at a
		# time, a whole side leaning together would say nothing about which of them is hitting you.
		var theirs := acting and not player_side and swinging_foe == at
		_foe_views[at].position = _foe_homes[at] - Vector2(reach if theirs else 0.0, 0.0)
		_foe_views[at].set_pose(&"walk" if theirs else &"idle", Dir.D.LEFT)


## Whether the timing window is open RIGHT NOW, and whether the fight is waiting on a choice.
##
## Two reads the screen already makes of itself - the cue's visibility and the rows' dimming -
## published so a scripted play session can play WELL: press on the cue, confirm through the
## menus. Without them a session has to derive frame offsets from the combat data and chain them
## by hand, which is arithmetic that goes stale the moment a formation changes size, and which
## fails as a fight that mysteriously does not end rather than as a sum that no longer adds up.
func cue_on() -> bool:
	return _logic != null and _logic.cue_on()


func choosing() -> bool:
	return _logic != null and _is_choosing()


func _is_choosing() -> bool:
	return _logic.phase() == BattleLogic.Phase.MENU \
		or _logic.phase() == BattleLogic.Phase.ITEMS \
		or _logic.phase() == BattleLogic.Phase.SPELLS \
		or _logic.phase() == BattleLogic.Phase.ALLY \
		or _logic.phase() == BattleLogic.Phase.FOE


func _paint_rows(text: Color, dim: Color) -> void:
	var choosing := _is_choosing()
	var first := _first_visible()
	# The window is headed with whoever is choosing, so the menu is a question addressed to
	# somebody rather than a list floating beside three people.
	_commands.panel.visible = choosing
	_commands.title.text = _page_title().to_upper()
	_commands.title.add_theme_color_override("font_color", text)
	for i in _rows.size():
		var row := _rows[i]
		var at := first + i
		# Rows past the current page's list are hidden rather than blanked: an empty label
		# still occupies its line, and everything below it would drift.
		row.visible = choosing and at < _logic.size()
		if not row.visible:
			continue
		var selected := at == _logic.index()
		row.text = _label_for(at)
		# A spell out of reach of the purse is drawn dim even under the cursor, so the answer
		# to "can I cast this" is on screen BEFORE the press rather than only in the refusal.
		# Affordability is asked of the logic, never recomputed here, or the screen and the
		# rule could disagree about the same spell.
		var reachable := _logic.phase() != BattleLogic.Phase.SPELLS \
			or _logic.can_afford(_logic.spell_row(at))
		row.add_theme_color_override("font_color", text if reachable else dim)
	# The cursor is a BAR under the selected row, not a ">" on the front of its text. Placed
	# after the rows are laid out, so it covers whichever one the cursor actually reached.
	var picked := selected_row()
	_select.visible = picked != null
	if picked != null:
		UiChrome.place(_select, picked, _commands.inner().size.x, ROW_PITCH)


## What the command window is headed with: whoever is choosing, or what they are choosing FROM.
## With one member the name is still theirs - the world synthesizes a solo leader called "You",
## so there is no branch here for a party of one.
func _page_title() -> String:
	match _logic.phase():
		BattleLogic.Phase.SPELLS:
			return "Magic"
		BattleLogic.Phase.ITEMS:
			return "Items"
		BattleLogic.Phase.ALLY:
			return "Who"
		BattleLogic.Phase.FOE:
			return "Which"
		_:
			var commander := _logic.commander()
			if commander >= 0:
				return _logic.member_name(commander)
			return "Battle"


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
	if _logic.phase() == BattleLogic.Phase.FOE:
		var alive := _logic.foe_rows()
		if at < 0 or at >= alive.size():
			return ""
		var which := alive[at]
		return "%s  %d/%d" % [_logic.enemy_name(which), _logic.enemy_hp(which),
			_logic.enemy_max_hp(which)]
	return COMMANDS[at]


func _help_text() -> String:
	match _logic.phase():
		BattleLogic.Phase.SPELLS:
			return "W/S to choose    E to cast    Esc to go back"
		BattleLogic.Phase.ITEMS:
			return "W/S to choose    E to use    Esc to go back"
		BattleLogic.Phase.ALLY:
			return "W/S to choose who    E to confirm    Esc to go back"
		BattleLogic.Phase.FOE:
			return "W/S to choose a foe    E to strike    Esc to go back"
		BattleLogic.Phase.MENU:
			# Whose turn it is, once there is more than one member to ask - without it a player
			# with two fighters has to infer from the marker which menu this is.
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
