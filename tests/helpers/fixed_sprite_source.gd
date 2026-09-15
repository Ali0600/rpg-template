class_name FixedSpriteSource
extends SpriteSource
## Hands every character the same sheet, built in memory: how a screen suite puts a fixture character
## in front of a screen that asks a SpriteSource for its art, with nothing written to disk.


var _sheet: Dictionary


## `sheet` is {"texture": Texture2D, "meta": SheetMeta}, the shape every source answers with.
func _init(sheet_value: Dictionary) -> void:
	_sheet = sheet_value


func sheet(_character_id: StringName) -> Dictionary:
	return _sheet
