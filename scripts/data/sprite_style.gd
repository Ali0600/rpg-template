class_name SpriteStyle
extends Resource
## Every art rule the generator obeys, in one editable file.
##
## This is the swap seam: pointing a character at a different SpriteStyle re-skins it
## completely - palette, outline treatment, shading, frame timing - with no code change.
## Consistency in pixel art comes from rules held everywhere at once, so the rules live
## here rather than being retyped per sprite, and tests/unit/test_gates_*.gd enforce them
## against the generated pixels.
##
## Ramps are hex strings rather than Colors on purpose: a palette is something a person
## edits and reviews in a diff, and "#d9a066" survives that where four floats do not.

enum Outline {
	NONE,  ## no outline pass; the silhouette is carried by the shapes alone
	SOLID,  ## one outline colour everywhere - the classic readable choice
	TINTED,  ## outline takes the shadow tone of whatever it is hugging - softer, warmer
}

@export var id: StringName = &""

## The cell every character frame is drawn into. Width is the sheet column stride.
@export var cell_size: Vector2i = Vector2i(16, 24)

## Terrain grid size. Keeping it a clean divisor of the cell is what makes characters and
## tiles look like they belong to the same world.
@export var tile_size: int = 16

## Which rig (data/rigs/<id>.json) supplies the part shapes.
@export var rig_id: StringName = &"gb16"

## name -> [shadow, base, light] as hex strings. Three tones per material is the cel
## shading budget; a fourth tone is where a limited palette starts to look muddy.
@export var ramps: Dictionary = {}

## Which ramp a slot falls back to when a character does not name one.
@export var default_ramps: Dictionary = {}

## Ramp names a randomised character may draw from, per slot.
@export var ramp_choices: Dictionary = {}

## Part ids a randomised character may draw from, per slot.
@export var part_choices: Dictionary = {}

@export var outline_mode: Outline = Outline.SOLID
@export var outline_color_hex: String = "#1a1c2c"

## Terrain colours, keyed by tile id, as ramp names.
@export var tile_ramps: Dictionary = {}

## Interface colours (text, dim text, panel), as hex strings. Deliberately NOT part of
## `ramps`: chrome re-skins with the style, but a UI colour must never become legal inside a
## sprite, and everything in `ramps` is exactly what the palette gate permits there.
@export var ui_colors: Dictionary = {}

@export var walk_frames: int = 4
@export var walk_fps: int = 8
@export var idle_fps: int = 4

## Per walk frame, how far the upper body lifts. The passing poses rise a pixel, which is
## what makes a four-frame walk read as a walk instead of a shuffle. Parts marked
## "bob": false in the rig (legs, feet) ignore this - they carry the stride, and a foot
## that leaves the ground breaks the grounding gate.
@export var bob_offsets: Array[int] = [0, -1, 0, -1]

## When true the left-facing row is the right-facing row mirrored, so the rig authors one
## side. Set false for a style with side-specific detail (a satchel on one hip).
@export var mirror_left_from_right: bool = true


func outline_color() -> Color:
	return Color(outline_color_hex)


## The three tones of a ramp, darkest first. Returns an empty array for an unknown name so
## the caller can report which slot asked for it - a silent fallback here would produce a
## sprite in the wrong colours that still passes the palette gate.
func ramp(name: String) -> PackedColorArray:
	var out := PackedColorArray()
	if not ramps.has(name):
		return out
	for hex: Variant in ramps[name]:
		out.append(Color(str(hex)))
	return out


## An interface colour by role ("text", "dim", "panel"). Falls back to a legible neutral so
## a style that has not defined chrome still renders readable text rather than black on black.
func ui_color(role: String, fallback: Color = Color(1, 1, 1, 1)) -> Color:
	if not ui_colors.has(role):
		return fallback
	return Color(str(ui_colors[role]))


func ramp_names() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in ramps.keys():
		out.append(str(k))
	out.sort()
	return out


## How much of a tone survives into its tinted outline, in whole percent.
const OUTLINE_TINT_PERCENT := 65

## A tinted outline is the part's own shadow tone pushed one step darker, so it still reads
## as an edge rather than as more shading. Defined here, not in the compositor, because the
## palette gate and the drawing code must agree on it exactly - two definitions of the same
## colour is how a generated pixel ends up outside its own palette.
##
## The arithmetic is done in whole BYTES, not with Color.darkened(). A float-derived colour
## does not survive being stored in an 8-bit image: Color.to_rgba32() rounds while the image
## truncates, so `darkened(0.35)` of #008840 reports itself as #00582a and comes back out of
## the PNG as #005829. One unit, and the palette gate is right to reject it - a palette whose
## members depend on which side of the pipeline you ask is not a palette.
static func tint_outline(c: Color) -> Color:
	return Color8(_tint_byte(c.r), _tint_byte(c.g), _tint_byte(c.b), 255)


static func _tint_byte(channel: float) -> int:
	return int(channel * 255.0 + 0.5) * OUTLINE_TINT_PERCENT / 100


## Every colour the outline pass can produce under this style's settings.
func outline_colors_rgba32() -> Array[int]:
	var out: Array[int] = []
	match outline_mode:
		Outline.SOLID:
			out.append(outline_color().to_rgba32())
		Outline.TINTED:
			for name in ramp_names():
				var tones := ramp(name)
				if tones.size() == 3:
					var v := tint_outline(tones[0]).to_rgba32()
					if not out.has(v):
						out.append(v)
	return out


## Every colour this style can legally put on screen. The palette gate compares generated
## pixels against exactly this set: anything else means a colour entered the pipeline from
## somewhere other than the style, which is the failure this whole design exists to prevent.
func palette_rgba32() -> Array[int]:
	var out: Array[int] = []
	for name in ramp_names():
		for c in ramp(name):
			var v := c.to_rgba32()
			if not out.has(v):
				out.append(v)
	for v in outline_colors_rgba32():
		if not out.has(v):
			out.append(v)
	return out


func default_ramp_for(slot: String) -> String:
	return str(default_ramps.get(slot, ""))


func choices_for_ramp(slot: String) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in ramp_choices.get(slot, []):
		out.append(str(v))
	return out


func choices_for_part(slot: String) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in part_choices.get(slot, []):
		out.append(str(v))
	return out


## Reports what is wrong with this style rather than trusting it. A ramp with two tones or
## a missing outline colour produces sprites that look almost right, which is the hardest
## kind of wrong to notice.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("style has no id")
	if cell_size.x <= 0 or cell_size.y <= 0:
		out.append("cell_size must be positive, got %s" % cell_size)
	if tile_size <= 0:
		out.append("tile_size must be positive, got %d" % tile_size)
	if walk_frames <= 0:
		out.append("walk_frames must be positive, got %d" % walk_frames)
	if bob_offsets.size() != walk_frames:
		out.append("bob_offsets has %d entries for %d walk frames" % [bob_offsets.size(), walk_frames])
	if ramps.is_empty():
		out.append("style has no ramps")
	for name in ramp_names():
		var r := ramp(name)
		if r.size() != 3:
			out.append("ramp '%s' has %d tones, expected 3 (shadow, base, light)" % [name, r.size()])
	for slot: Variant in default_ramps.keys():
		var wanted := str(default_ramps[slot])
		if not ramps.has(wanted):
			out.append("default ramp for slot '%s' names unknown ramp '%s'" % [slot, wanted])
	if outline_mode == Outline.SOLID and not outline_color_hex.begins_with("#"):
		out.append("outline_color_hex is not a hex colour: '%s'" % outline_color_hex)
	return out
