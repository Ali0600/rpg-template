class_name FileSpriteSource
extends SpriteSource
## Reads a committed PNG + <name>.sheet.json pair.
##
## What the game uses. It is also the seam an outside art pack plugs into: drop a sheet and
## its JSON into a style directory and the game loads it with no code change - the metadata
## carries the cell size, row order and frame timings, so nothing about the layout is
## assumed here.

const DEFAULT_ROOT := "res://assets/generated"

var root: String = DEFAULT_ROOT
var style_id: StringName = &""


static func create(style_value: StringName, root_value: String = DEFAULT_ROOT) -> FileSpriteSource:
	var src := FileSpriteSource.new()
	src.style_id = style_value
	src.root = root_value
	return src


func texture_path(character_id: StringName) -> String:
	return "%s/%s/%s.png" % [root, style_id, character_id]


func meta_path(character_id: StringName) -> String:
	return "%s/%s/%s.sheet.json" % [root, style_id, character_id]


func sheet(character_id: StringName) -> Dictionary:
	var tex_path := texture_path(character_id)
	var texture := load(tex_path) as Texture2D
	if texture == null:
		push_error("FileSpriteSource: no texture at %s (has tools/gen_sprites.gd been run?)" % tex_path)
		return {}
	var file := JsonFile.read(meta_path(character_id))
	if not file.ok:
		# A PNG with no description is not usable art: nothing knows how many rows it has,
		# which direction each row is, or where the character's feet are.
		push_error("FileSpriteSource: %s" % file.error)
		return {}
	return {"texture": texture, "meta": SheetMeta.from_dict(file.data)}
