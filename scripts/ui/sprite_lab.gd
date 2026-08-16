extends Node2D
## Sprite Lab: look at the generator's output without running the game.
##
## Generates live through ProceduralSpriteSource rather than reading the committed PNGs, so
## editing a rig or a palette and reloading shows the change immediately - which is the
## difference between a generator you can tune and one you can only run.
##
## It is also the answer to the one question no test can settle. The gates prove the rules
## hold; only looking proves the result is worth shipping.

## Laid out for the game's own 320x180 viewport, so the lab is judged at the size the art
## will actually be seen at. Previewing pixel art at some other scale is how a sprite that
## is unreadable in play gets approved.
const VIEW_SCALE := 2
const CAST_SCALE := 1
const DIRECTION_SPACING := 34
const DIRECTION_ORIGIN := Vector2(16, 116)
const CAST_ORIGIN := Vector2(196, 40)

var _style_ids: Array[StringName] = []
var _style_index := 0
var _character_index := 0
var _walking := true
var _seed_offset := 0
var _gate := InputGate.new()

var _style: SpriteStyle
var _rig: Rig
var _specs: Array[CharacterSpec] = []
var _source: ProceduralSpriteSource
var _views: Array[SpriteView] = []
var _contact: Node2D
var _title: Label
var _detail: Label
var _help: Label
var _labels: Array[Label] = []


func _ready() -> void:
	_style_ids = _discover_styles()
	if _style_ids.is_empty():
		push_error("Sprite Lab: no styles found in data/styles")
		return
	# The style is loaded BEFORE the chrome is built, because the chrome's own colours come
	# from it: the lab re-skins along with the art it is previewing, and no colour in this
	# file is typed as a literal. Same rule as the sprites - colours live in data.
	_load_style()
	_build_chrome()
	_reload()


func _discover_styles() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open("res://data/styles")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var check := name.trim_suffix(".remap")
		if not dir.current_is_dir() and check.get_extension() == "tres":
			var style := load("res://data/styles/" + check) as SpriteStyle
			if style != null:
				out.append(style.id)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _build_chrome() -> void:
	var text_color := _style.ui_color("text")
	var dim_color := _style.ui_color("dim")
	var layer := CanvasLayer.new()
	layer.name = "Chrome"
	add_child(layer)
	_title = _label(layer, Vector2(6, 2), 9, text_color)
	_detail = _label(layer, Vector2(6, 14), 7, dim_color)
	_help = _label(layer, Vector2(6, 168), 7, dim_color)
	_help.text = "A/D character  W/S style  E walk/idle  TAB reroll"
	_label(layer, CAST_ORIGIN - Vector2(0, 12), 7, dim_color).text = "the cast"

	# One view per direction, so a change is judged from every angle at once - a part that
	# only looks wrong from behind is exactly what a single front-facing preview misses.
	var strip := Node2D.new()
	strip.name = "Directions"
	strip.position = DIRECTION_ORIGIN
	add_child(strip)
	for i in Dir.ALL.size():
		var view := SpriteView.new()
		view.name = "View%d" % i
		view.scale = Vector2(VIEW_SCALE, VIEW_SCALE)
		# Views are positioned by their FEET, which is what the SpriteView origin is - so
		# they line up on one baseline however tall the character turns out to be.
		view.position = Vector2(i * DIRECTION_SPACING, 0)
		strip.add_child(view)
		_views.append(view)
		_label(layer, DIRECTION_ORIGIN + Vector2(i * DIRECTION_SPACING - 2, 4), 7, dim_color) \
			.text = String(Dir.name_of(Dir.ALL[i]))

	_contact = Node2D.new()
	_contact.name = "Contact"
	_contact.position = CAST_ORIGIN
	add_child(_contact)


func _label(parent: Node, at: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	_labels.append(l)
	return l


## Repaints the chrome when the style changes. Without this the interface would keep the
## first style's colours while the art beside it changed - a half-applied swap, which is a
## worse advertisement for "one file re-skins everything" than no swap at all.
func _restyle_chrome() -> void:
	if _labels.is_empty():
		return
	var dim_color := _style.ui_color("dim")
	for label in _labels:
		label.add_theme_color_override("font_color", dim_color)
	if _title != null:
		_title.add_theme_color_override("font_color", _style.ui_color("text"))


## Loads the currently selected style and its rig. Separate from _reload because the chrome
## needs a style to take its colours from before there is anything to display.
func _load_style() -> void:
	var style_id := _style_ids[_style_index % _style_ids.size()]
	_style = load("res://data/styles/%s.tres" % style_id) as SpriteStyle
	_rig = Rig.load_from("res://data/rigs/%s.json" % _style.rig_id)


func _reload() -> void:
	_load_style()
	_restyle_chrome()
	var style_id := _style.id
	_specs = _characters_of(style_id)
	if _specs.is_empty():
		_title.text = "%s: no characters" % style_id
		return
	_source = ProceduralSpriteSource.create(_style, _rig, _specs)
	_refresh()


func _refresh() -> void:
	var spec := _specs[_character_index % _specs.size()].duplicate() as CharacterSpec
	# Rerolling only shifts the seed, so the character's explicitly authored choices survive
	# and only what the seed decides changes - which is what makes the reroll legible.
	spec.seed = spec.seed + _seed_offset
	_source.add(spec)

	for i in _views.size():
		var view := _views[i]
		view.apply_source(_source, spec.id)
		view.set_pose(&"walk" if _walking else &"idle", Dir.ALL[i])

	_title.text = "%s / %s" % [_style.id, spec.id]
	var resolved := spec.resolve(_rig, _style)
	var parts: Dictionary = resolved["parts"]
	var ramps: Dictionary = resolved["ramps"]
	_detail.text = "seed %d   %s   outline %s   %s" % [
		spec.seed,
		"walk" if _walking else "idle",
		["none", "solid", "tinted"][_style.outline_mode],
		"%s / %s" % [parts.get("hair", "-"), ramps.get("body", "-")],
	]
	_rebuild_contact()


## The whole cast side by side. Consistency is a property OF A GROUP - a single sprite can
## never show whether the cast shares a ground line or a palette.
func _rebuild_contact() -> void:
	for child in _contact.get_children():
		child.queue_free()
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2(CAST_SCALE, CAST_SCALE)
	sprite.texture = ImageTexture.create_from_image(
		SheetBuilder.contact_sheet(_rig, _style, _specs))
	_contact.add_child(sprite)


func _characters_of(style_id: StringName) -> Array[CharacterSpec]:
	var out: Array[CharacterSpec] = []
	var dir := DirAccess.open("res://data/characters")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var check := name.trim_suffix(".remap")
		if not dir.current_is_dir() and check.get_extension() == "tres":
			var spec := load("res://data/characters/" + check) as CharacterSpec
			if spec != null and spec.style_id == style_id:
				out.append(spec)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: CharacterSpec, b: CharacterSpec) -> bool: return String(a.id) < String(b.id))
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# One event, one action - see InputGate for why this is not a plain identity check.
	if not _gate.accept(event):
		return

	if event.is_action(&"move_right"):
		_character_index += 1
		_seed_offset = 0
		_refresh()
	elif event.is_action(&"move_left"):
		_character_index += maxi(_specs.size() - 1, 0)
		_seed_offset = 0
		_refresh()
	elif event.is_action(&"move_up") or event.is_action(&"move_down"):
		_style_index += 1
		_character_index = 0
		_seed_offset = 0
		_reload()
	elif event.is_action(&"interact"):
		_walking = not _walking
		_refresh()
	elif event.is_action(&"menu"):
		_seed_offset += 1
		_refresh()
	else:
		return
	get_viewport().set_input_as_handled()
