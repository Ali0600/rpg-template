class_name UiScale
extends RefCounted
## How big the window is, and how big the interface is drawn, for a given style.
##
## Every screen in this project lays out in raw pixels against DESIGN_SIZE - 8px fonts, a
## dialog box 6px from the edge, a slot list of twelve rows down a 180px window. That is the
## whole reason those numbers can be constants and the layout audits can measure them. A 64x64
## style would break all of it by arithmetic alone: at 320x180 a 32px map shows ten tiles
## across and the dialog box covers a third of the world.
##
## So the WORLD grows and the INTERFACE does not. The window becomes DESIGN_SIZE times the
## style's world_scale, and every CanvasLayer is drawn at that scale - which leaves every
## screen measuring against 320x180 exactly as before, every font size unchanged, and every
## layout gate still true. Twenty tiles across at 16px, twenty tiles across at 32px.
##
## Pure and static, and it names no autoload: the world scene and Sprite Lab both call it, and
## a util that reached for a singleton would drop itself out of check.sh's per-file parse gate.

## The size every screen is laid out against, at every scale. This is the project's own
## viewport setting (tools/smoke_boot.gd holds the two together), and it is a CONSTANT rather
## than a reading of the live viewport: after apply() the viewport reports the scaled size, so
## a screen that measured the viewport would lay itself out twice as far apart at lpc32.
const DESIGN_SIZE := Vector2i(320, 180)


## How many world pixels the window holds for this style.
static func window_size(style: SpriteStyle) -> Vector2i:
	return DESIGN_SIZE * scale_of(style)


## The scale a CanvasLayer showing an interface is drawn at.
static func layer_scale(style: SpriteStyle) -> Vector2:
	var s := float(scale_of(style))
	return Vector2(s, s)


## A null style is scale 1 rather than an error: the dialog box and the controls hint are built
## before any map has been entered, so there is a moment where the game is running and no style
## is bound. rescale() below is what brings them up when one is.
static func scale_of(style: SpriteStyle) -> int:
	return maxi(style.world_scale, 1) if style != null else 1


## Points the window at the size this style wants. Setting content_scale_size rather than the
## window's own size is what keeps the stretch integer and the pixels square: the root viewport
## IS this size, so get_viewport_rect() reports it and every world coordinate is a world pixel,
## whatever resolution the player's screen happens to be.
static func apply(window: Window, style: SpriteStyle) -> void:
	if window == null:
		return
	window.content_scale_size = window_size(style)


## Adds an interface layer at the right scale. ONE function rather than a scale assignment
## beside each of the ten add_child calls, because the tenth is the one that gets forgotten -
## and a screen mounted at 1x over a 2x world is a quarter-size menu in the corner, which looks
## like a broken screen rather than a missed line.
static func mount(layer: CanvasLayer, parent: Node, style: SpriteStyle) -> void:
	if layer == null or parent == null:
		return
	layer.scale = layer_scale(style)
	parent.add_child(layer)


## Brings every interface layer already in the tree to this style's scale. The pair to mount():
## a layer built before a style was bound (the dialog box, the controls hint) has no way to
## know its scale at the moment it is created, and a layer built while another style was bound
## would keep that one's.
static func rescale(parent: Node, style: SpriteStyle) -> void:
	if parent == null:
		return
	var wanted := layer_scale(style)
	for child in parent.get_children():
		var layer := child as CanvasLayer
		if layer != null:
			layer.scale = wanted
