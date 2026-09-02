extends Node2D
## Sprite Lab: look at the generator's output without running the game.
##
## Generates live through ProceduralSpriteSource rather than reading the committed PNGs, so
## editing a rig or a palette and reloading shows the change immediately - which is the
## difference between a generator you can tune and one you can only run. An IMPORTED style
## has nothing to generate live, so it is shown from the committed sheets through the same
## FileSpriteSource the game uses - the lab is where the first LPC character is judged.
##
## It is also the answer to the one question no test can settle. The gates prove the rules
## hold; only looking proves the result is worth shipping.

## Laid out for the game's own 320x180 viewport, so the lab is judged at the size the art
## will actually be seen at. Previewing pixel art at some other scale is how a sprite that
## is unreadable in play gets approved.
const VIEW_SCALE := 2
const CAST_SCALE := 1
## The strip of four views has this much of the viewport; a cell too wide to show four of at
## VIEW_SCALE is shown at 1x rather than off the edge.
const STRIP_WIDTH := 280
const DIRECTION_GAP := 2
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
## The committed characters of an imported style, by id.
var _imported: Array[StringName] = []
var _source: SpriteSource
var _views: Array[SpriteView] = []
var _direction_labels: Array[Label] = []
var _contact: Node2D
var _chrome: CanvasLayer
var _strip: Node2D
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
	for res in ContentScan.resources("res://data/styles"):
		var style := res as SpriteStyle
		if style != null:
			out.append(style.id)
	# By TEXT. Array[StringName].sort() orders by the interned pointer, which put nes16 before
	# gb16 here and made W/S walk the styles in an order nobody could predict.
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func _build_chrome() -> void:
	var text_color := _style.ui_color("text")
	var dim_color := _style.ui_color("dim")
	var layer := CanvasLayer.new()
	layer.name = "Chrome"
	_chrome = layer
	UiScale.mount(layer, self, _style)
	_title = _label(layer, Vector2(6, 2), 9, text_color)
	_detail = _label(layer, Vector2(6, 14), 7, dim_color)
	_help = _label(layer, Vector2(6, 168), 7, dim_color)
	_help.text = "A/D character	 W/S style	E walk/idle	 TAB reroll"
	_label(layer, CAST_ORIGIN - Vector2(0, 12), 7, dim_color).text = "the cast"

	# One view per direction, so a change is judged from every angle at once - a part that
	# only looks wrong from behind is exactly what a single front-facing preview misses.
	var strip := Node2D.new()
	strip.name = "Directions"
	strip.position = DIRECTION_ORIGIN
	_strip = strip
	add_child(strip)
	for i in Dir.ALL.size():
		var view := SpriteView.new()
		view.name = "View%d" % i
		strip.add_child(view)
		_views.append(view)
		var label := _label(layer, DIRECTION_ORIGIN, 7, dim_color)
		label.text = String(Dir.name_of(Dir.ALL[i]))
		_direction_labels.append(label)
	_layout_strip()

	_contact = Node2D.new()
	_contact.name = "Contact"
	_contact.position = CAST_ORIGIN
	add_child(_contact)


## Brings the chrome and the two world-space origins to the current style's scale. The labels
## live on a CanvasLayer and are laid out in design pixels, exactly as every screen in the game
## is; the strip and the contact sheet are world nodes, so their origins are multiplied.
func _rescale_chrome() -> void:
	if _chrome == null:
		return
	_chrome.scale = UiScale.layer_scale(_style)
	var world := float(UiScale.scale_of(_style))
	# The backdrop is a world-space rect, so it is sized in world pixels. The .tscn's own
	# numbers are a view of the default style; the size is set here because only a style knows.
	var background := get_node_or_null("Background") as ColorRect
	if background != null:
		background.size = Vector2(UiScale.window_size(_style))
	if _strip != null:
		_strip.position = DIRECTION_ORIGIN * world
	if _contact != null:
		_contact.position = CAST_ORIGIN * world


## Spaces the four views by the CURRENT style's cell, at the largest scale that keeps all four
## inside the strip. Views are positioned by their FEET, which is what the SpriteView origin
## is - so they line up on one baseline however tall the character turns out to be.
func _layout_strip() -> void:
	var world := UiScale.scale_of(_style)
	var room := STRIP_WIDTH * world
	var scale_factor := clampi(room / (Dir.ALL.size() * maxi(_style.cell_size.x, 1)), 1, VIEW_SCALE)
	var spacing := _style.cell_size.x * scale_factor + DIRECTION_GAP * world
	for i in _views.size():
		_views[i].scale = Vector2(scale_factor, scale_factor)
		_views[i].position = Vector2(i * spacing, 0)
		# The labels are chrome, so they are placed in DESIGN pixels: the spacing above is in
		# world pixels and has to come back down through the scale to sit under its view.
		_direction_labels[i].position = DIRECTION_ORIGIN + Vector2(i * spacing / world - 2, 4)


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


## Loads the currently selected style and, for a rig style, its rig. Separate from _reload
## because the chrome needs a style to take its colours from before there is anything to display.
func _load_style() -> void:
	var style_id := _style_ids[_style_index % _style_ids.size()]
	_style = load("res://data/styles/%s.tres" % style_id) as SpriteStyle
	_rig = null if _style.imports() else Rig.load_from("res://data/rigs/%s.json" % _style.rig_id)
	# The lab is judged at the size the art is played at, which is the whole reason it lays
	# itself out for the game's own viewport. A 64px style is played in a 640x360 window, so
	# that is the window it is looked at in - the world scene's rule, through the same call.
	UiScale.apply(get_window(), _style)


func _reload() -> void:
	_load_style()
	_restyle_chrome()
	_rescale_chrome()
	_layout_strip()
	var style_id := _style.id
	if _style.imports():
		_specs = []
		_imported = _imported_ids(style_id)
		if _imported.is_empty():
			_title.text = "%s: no imported characters" % style_id
			return
		_source = FileSpriteSource.create(style_id)
	else:
		_imported = []
		_specs = _characters_of(style_id)
		if _specs.is_empty():
			_title.text = "%s: no characters" % style_id
			return
		_source = ProceduralSpriteSource.create(_style, _rig, _specs)
	_refresh()


func _refresh() -> void:
	if _style.imports():
		_refresh_imported()
		return
	var spec := _specs[_character_index % _specs.size()].duplicate() as CharacterSpec
	# Rerolling only shifts the seed, so the character's explicitly authored choices survive
	# and only what the seed decides changes - which is what makes the reroll legible.
	spec.seed = spec.seed + _seed_offset
	(_source as ProceduralSpriteSource).add(spec)

	for i in _views.size():
		var view := _views[i]
		view.apply_source(_source, spec.id)
		view.set_pose(&"walk" if _walking else &"idle", Dir.ALL[i])

	_title.text = "%s / %s" % [_style.id, spec.id]
	var resolved := spec.resolve(_rig, _style)
	var parts: Dictionary = resolved["parts"]
	var ramps: Dictionary = resolved["ramps"]
	_detail.text = "seed %d	  %s   outline %s	%s" % [
		spec.seed,
		"walk" if _walking else "idle",
		["none", "solid", "tinted"][_style.outline_mode],
		"%s / %s" % [parts.get("hair", "-"), ramps.get("body", "-")],
	]
	_rebuild_contact()


## An imported character has no seed to reroll and no parts to name: what is shown is the
## committed sheet, and the detail line says whose terms it is under.
func _refresh_imported() -> void:
	var id := _imported[_character_index % _imported.size()]
	for i in _views.size():
		var view := _views[i]
		view.apply_source(_source, id)
		view.set_pose(&"walk" if _walking else &"idle", Dir.ALL[i])
	_title.text = "%s / %s" % [_style.id, id]
	_detail.text = "imported   %s	licences %s" % [
		"walk" if _walking else "idle",
		", ".join(_style.licenses),
	]
	_rebuild_contact()


## The whole cast side by side. Consistency is a property OF A GROUP - a single sprite can
## never show whether the cast shares a ground line or a palette. An imported cast has no
## rig to compose a strip from, and its ground line is a gate rather than a picture.
func _rebuild_contact() -> void:
	for child in _contact.get_children():
		child.queue_free()
	if _style.imports():
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2(CAST_SCALE, CAST_SCALE)
	sprite.texture = ImageTexture.create_from_image(
		SheetBuilder.contact_sheet(_rig, _style, _specs))
	_contact.add_child(sprite)


func _characters_of(style_id: StringName) -> Array[CharacterSpec]:
	var out: Array[CharacterSpec] = []
	for res in ContentScan.resources("res://data/characters"):
		var spec := res as CharacterSpec
		if spec != null and spec.style_id == style_id:
			out.append(spec)
	out.sort_custom(func(a: CharacterSpec, b: CharacterSpec) -> bool: return String(a.id) < String(b.id))
	return out


## The committed sheets of an imported style, by the id each .sheet.json is named after.
func _imported_ids(style_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var exts: Array[String] = ["json"]
	for path in ContentScan.files("%s/%s" % [FileSpriteSource.DEFAULT_ROOT, style_id], exts):
		if path.ends_with(".sheet.json"):
			out.append(StringName(path.get_file().trim_suffix(".sheet.json")))
	return out


func _count() -> int:
	return _imported.size() if _style.imports() else _specs.size()


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
		_character_index += maxi(_count() - 1, 0)
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
