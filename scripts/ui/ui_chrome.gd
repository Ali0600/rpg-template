class_name UiChrome
extends RefCounted
## What every screen in this game is drawn WITH: one font, at one size, in one place.
##
## The interface used to be nine screens each declaring its own 7, 8 and 9, drawn in whatever
## font the engine happened to fall back to. That is most of why it read as cheap: a vector face
## asked for 7 pixels is a smear, and three sizes of smear is not a hierarchy. A pixel font is
## drawn FOR one size and has no other - so the sizes live here, there are two of them, and the
## difference between a title and a row is a band and capitals rather than a point size.
##
## Pure and static, and it names no autoload - the UiScale rule, and for its reason: a file
## whose TEXT contains an autoload's name drops itself, and every suite that depends on it, out
## of check.sh's per-file parse gate.
##
## M42 opened this file with the font alone. The frames, bars and portraits every screen is
## rebuilt on land next, and they belong beside it: one place that knows what this game's
## interface is made of.

## The font every Control in the game draws in. It is NOT loaded here and handed out: it is
## named by the project setting `gui/theme/custom_font`, which Godot loads into
## ThemeDB.fallback_font and the default theme, so a Label built anywhere already has it.
##
## That is the whole reason to do it this way. A helper that handed the font out would only
## reach the labels that remembered to ask - and the one that forgot would draw in the engine's
## own face, at the right size, in the right place, looking almost right. This constant exists
## so the gate can say WHICH font its measurements are about: tests/unit/test_dialog_fit.gd
## holds what a REAL Label reports to this path.
##
## Deliberately asserted there and nowhere else. A second check on the project setting itself
## would restate the config rather than measure the outcome, and the outcome subsumes it - an
## unset setting and a deleted file both arrive as a Label reporting the wrong font. Two checks
## where one subsumes the other leave a mutant nothing can kill.
const FONT_PATH := "res://assets/fonts/pixel_operator_8.ttf"
## The bold face, for a window's header band. Named rather than loaded for the same reason the
## sizes are named: a second face is a decision, and decisions live in one file.
const FONT_BOLD_PATH := "res://assets/fonts/pixel_operator_8_bold.ttf"

## Body text, rows, captions, help lines - everything. Pixel Operator 8 is drawn for exactly
## this height; asking it for 7 or 9 scales a bitmap and undoes the reason it is here.
const FONT_SIZE := 8
## The one word on the title screen, and nothing else. Two is a whole size, so the glyphs are
## drawn rather than stretched.
const HEADING_SIZE := FONT_SIZE * 2

## How thick the rule around a window is. One pixel, at the design size - a window is a frame,
## and the whole difference between a frame and a rectangle is that a reader can see where it
## ends without being told.
const BORDER := 1
## Room between a window's border and anything drawn in it.
const PAD := 3
## The band across the top of a window, tall enough for one line of the font plus its rule.
const HEADER_HEIGHT := FONT_SIZE + 2
## How far a row's text sits inside the bar that selects it, so the bar is visibly AROUND the
## text rather than starting at the same pixel.
const ROW_INSET := 2
const BAR_HEIGHT := 4

## What kind of thing a node is, for the layout audits. A frame ENCLOSES what is drawn in it and
## a select bar sits UNDER a row, so neither is a peer of the things it contains - and an audit
## that measured them as peers would report every window in the game as covering its own text.
##
## Stated as meta on the node rather than inferred from its class, because "a ColorRect that is
## really a highlight" is exactly the kind of thing that gets inferred wrongly the day somebody
## adds a second ColorRect for another reason.
const KIND := &"ui_kind"
const FRAME := &"frame"
const HEADER := &"header"
const SELECT := &"select"
const BAR := &"bar"
const PORTRAIT := &"portrait"
## The content rect, parked on the panel when it is built. A window's own rect is not what
## "inside the window" means - the border and the header band are part of it - so the audit has
## to be able to ask for the same rectangle the layout placed against, rather than settle for the
## outer one and pass a row hanging over the bottom edge.
const INNER := &"ui_inner"


## A window: fill, rule, and an optional header band with a name in it.
##
## The header and its label are CHILDREN of the panel, so an audit that walks ancestry gets the
## containment rule for free and there is no third case to remember.
class Frame:
	extends RefCounted
	var panel: Panel
	var header: ColorRect
	var title: Label

	## The rect inside the border and under the header, in the panel's own coordinates. The
	## LAYOUT places by this and the AUDIT measures by it, which is what keeps "inside the
	## window" one fact rather than two arithmetics that agree until they do not.
	func inner() -> Rect2:
		var top := float(BORDER)
		if header != null:
			top += float(HEADER_HEIGHT)
		return Rect2(Vector2(float(BORDER) + PAD, top + PAD),
			Vector2(panel.size.x - (float(BORDER) + PAD) * 2.0,
				panel.size.y - top - float(BORDER) - PAD * 2.0))


## A readout with a number on it: a track, a fill drawn over it, and the figures beside them.
## One widget rather than three peers - a fill inside its own track is what a bar IS.
class Bar:
	extends RefCounted
	var root: Control
	var track: ColorRect
	var fill: ColorRect
	var numbers: Label
	var width: float = 0.0


static func label(style: SpriteStyle, role: String, size := FONT_SIZE) -> Label:
	var out := Label.new()
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", style.ui_color(role))
	return out


## Builds a window at `rect`, titled or not. Nothing is added to a tree here: the caller owns
## where it goes, the way every other builder in this project does.
static func frame(style: SpriteStyle, rect: Rect2, title := "") -> Frame:
	var out := Frame.new()
	out.panel = Panel.new()
	out.panel.position = rect.position
	out.panel.size = rect.size
	out.panel.set_meta(KIND, FRAME)
	var box := StyleBoxFlat.new()
	box.bg_color = style.ui_color("panel")
	box.border_color = style.ui_color("border")
	box.set_border_width_all(BORDER)
	# Square. A rounded corner at this size is two grey pixels and a lie about the resolution.
	box.set_corner_radius_all(0)
	box.anti_aliasing = false
	out.panel.add_theme_stylebox_override("panel", box)
	if title.is_empty():
		out.panel.set_meta(INNER, out.inner())
		return out
	out.header = ColorRect.new()
	out.header.color = style.ui_color("header")
	out.header.position = Vector2(float(BORDER), float(BORDER))
	out.header.size = Vector2(rect.size.x - float(BORDER) * 2.0, float(HEADER_HEIGHT))
	out.header.set_meta(KIND, HEADER)
	out.panel.add_child(out.header)
	# Upper case rather than a larger size: the font is drawn for ONE size, and a heading that
	# scales it is the blur the font was brought in to remove.
	out.title = label(style, "text")
	out.title.text = title.to_upper()
	out.title.position = Vector2(float(PAD), 0.0)
	out.header.add_child(out.title)
	out.panel.set_meta(INNER, out.inner())
	return out


## The cursor. A bar drawn UNDER the row it selects, which is what every reference does that
## does not draw a hand - and what this game did not do: it prefixed the row's own text with a
## `>`, which makes the marker part of the string and shifts the text sideways to hold it.
##
## Hidden until place() puts it somewhere, because a bar at the origin is a bar drawn over the
## corner of whatever window it belongs to.
static func select(style: SpriteStyle) -> ColorRect:
	var out := ColorRect.new()
	out.color = style.ui_color("select")
	out.set_meta(KIND, SELECT)
	out.visible = false
	return out


## Puts the cursor behind `over`, in the coordinates `over` is placed in. `pitch` is the row
## height rather than the font's, so the bar covers the whole line rather than the glyphs.
static func place(bar: ColorRect, over: Label, width: float, pitch: float) -> void:
	bar.position = Vector2(over.position.x - float(ROW_INSET), over.position.y - 1.0)
	bar.size = Vector2(width, pitch)
	bar.visible = true


## A bar and its figures. `role` is "hp" or "mp" - the two colours in this game - and the track
## is the header's own fill, so an empty bar reads as a groove rather than as a second colour.
static func bar(style: SpriteStyle, role: String, width: float) -> Bar:
	var out := Bar.new()
	out.width = width
	out.root = Control.new()
	out.root.set_meta(KIND, BAR)
	out.track = ColorRect.new()
	out.track.color = style.ui_color("header")
	out.track.size = Vector2(width, float(BAR_HEIGHT))
	out.root.add_child(out.track)
	out.fill = ColorRect.new()
	out.fill.color = style.ui_color(role)
	out.fill.size = Vector2(width, float(BAR_HEIGHT))
	out.root.add_child(out.fill)
	out.numbers = label(style, "text")
	# Two above the track, so the figures and the bar together occupy exactly one line of the
	# font: a block is laid out in whole lines and a readout that hangs a pixel below its own
	# row is one the cursor cannot cover.
	out.numbers.position = Vector2(width + 3.0, -2.0)
	out.root.add_child(out.numbers)
	out.root.size = Vector2(width, float(BAR_HEIGHT))
	return out


## What the bar is worth now. Floored, so a fill only reaches the end of its track at full - a
## rounded 99/100 that draws full is a bar saying the fight is not on.
static func fill(b: Bar, value: int, most: int) -> void:
	var span := float(maxi(value, 0)) / float(maxi(most, 1))
	b.fill.size = Vector2(floorf(b.width * clampf(span, 0.0, 1.0)), float(BAR_HEIGHT))
	b.numbers.text = "%d/%d" % [maxi(value, 0), maxi(most, 0)]


## The content rect of a window, in its own coordinates - what `inside the window` means.
static func inner_of(panel: Node) -> Rect2:
	if panel == null or not panel.has_meta(INNER):
		return Rect2()
	return panel.get_meta(INNER)


## What kind of thing this is, or nothing. The audits ask; nothing in the game does.
static func kind_of(node: Node) -> StringName:
	if node == null or not node.has_meta(KIND):
		return &""
	return StringName(str(node.get_meta(KIND)))


## A character's face, cut from the standing frame of their own sheet.
##
## Drawn at 1 texture pixel per WORLD pixel, which on a layer already scaled to the world comes
## out the size that face is when you walk around as them - and the same number of design pixels
## whatever style is running, because a style with twice the cell declares twice the portrait.
##
## Returns a hidden node when the character has no sheet, rather than nothing: a party block with
## a hole in it still lays out, and a missing PNG should cost a face rather than a screen.
static func portrait(style: SpriteStyle, source: SpriteSource, character: StringName) -> TextureRect:
	var out := TextureRect.new()
	out.set_meta(KIND, PORTRAIT)
	out.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# EXPAND_IGNORE_SIZE or the node takes its TEXTURE's size and the assignment below is a
	# suggestion - which is how a 24px face lands in a block laid out for 12 and the audit
	# reports a cursor half-covering it.
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var span := float(style.portrait_size) / float(UiScale.scale_of(style))
	out.custom_minimum_size = Vector2(span, span)
	out.size = Vector2(span, span)
	var sheet := source.sheet(character)
	if sheet.is_empty():
		out.visible = false
		return out
	var meta: SheetMeta = sheet["meta"]
	var at := AtlasTexture.new()
	at.atlas = sheet["texture"]
	# The face's rect is in CELL coordinates, so the row this character faces the camera on is
	# added here - once, in the one place that turns the measurement into a region.
	at.region = Rect2i(meta.portrait.position
		+ Vector2i(0, maxi(meta.row_of(Dir.D.DOWN), 0) * meta.cell.y), meta.portrait.size)
	# Without this a portrait samples the neighbouring frame's edge pixels at some scales, which
	# is a thin line of somebody else's shoulder down the side of every face.
	at.filter_clip = true
	out.texture = at
	out.stretch_mode = TextureRect.STRETCH_SCALE
	return out


## How big a face is drawn, in the units a screen lays out in.
static func portrait_span(style: SpriteStyle) -> float:
	return float(style.portrait_size) / float(UiScale.scale_of(style))
