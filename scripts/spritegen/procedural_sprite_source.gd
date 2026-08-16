class_name ProceduralSpriteSource
extends SpriteSource
## Generates a character's sheet in memory, with nothing on disk.
##
## This is what Sprite Lab previews and what the tests check, so a change to a rig or a
## palette can be seen and asserted before any PNG is written. The game itself uses
## FileSpriteSource: generating at startup would be wasted work and would make the art
## depend on code that could change after the art was reviewed.

var style: SpriteStyle
var rig: Rig
var _specs: Dictionary = {}  # StringName -> CharacterSpec


static func create(style_value: SpriteStyle, rig_value: Rig, specs: Array[CharacterSpec]) -> ProceduralSpriteSource:
	var src := ProceduralSpriteSource.new()
	src.style = style_value
	src.rig = rig_value
	for spec in specs:
		src._specs[spec.id] = spec
	return src


func add(spec: CharacterSpec) -> void:
	_specs[spec.id] = spec


func character_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _specs.keys():
		out.append(k)
	out.sort()
	return out


func spec_of(character_id: StringName) -> CharacterSpec:
	return _specs.get(character_id, null)


func sheet(character_id: StringName) -> Dictionary:
	var spec: CharacterSpec = _specs.get(character_id, null)
	if spec == null:
		push_error("ProceduralSpriteSource: no character '%s'" % character_id)
		return {}
	if style == null or rig == null or not rig.ok:
		push_error("ProceduralSpriteSource: style or rig missing for '%s'" % character_id)
		return {}
	var built := SheetBuilder.build(rig, style, spec)
	return {
		"texture": ImageTexture.create_from_image(built["image"]),
		"meta": built["meta"],
		"image": built["image"],
	}
