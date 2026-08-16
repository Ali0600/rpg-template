extends Node2D
## The playable world: builds a map from data, spawns the player, follows with the camera.
##
## Everything specific to a game lives in `data/` - which map, which characters, which
## tiles. This file only knows how to assemble those, which is what makes it template code
## rather than game code.

const DEFAULT_MAP := &"demo_town"
const DEFAULT_SPAWN := &"start"
const PLAYER_CHARACTER := &"hero"

var _config: GameConfig
var _style: SpriteStyle
var _source: SpriteSource
var _built: MapBuilder.Built
var _player: ActorBody
var _camera := Camera2D.new()
var _dialog := DialogBox.new()
## npc id -> {"body": ActorBody, "dialog": String}
var _npcs: Dictionary = {}
var _gate := InputGate.new()


func _ready() -> void:
	_config = load("res://data/game_config.tres") as GameConfig
	if _config == null:
		push_error("World: data/game_config.tres is missing")
		return
	add_child(_dialog)
	_dialog.closed.connect(_on_dialog_closed)
	enter_map(DEFAULT_MAP, DEFAULT_SPAWN)


## Loads a map and puts the player on a named spawn. The one entry point, so a warp, a load
## and the first boot all take the same path - three ways into a map is three places for the
## camera limits to be forgotten.
func enter_map(map_id: StringName, spawn_id: StringName) -> bool:
	var data := MapData.load_from("res://data/maps/%s.json" % map_id)
	_style = load("res://data/styles/%s.tres" % data.style_id) as SpriteStyle
	if _style == null:
		push_error("World: map '%s' names unknown style '%s'" % [map_id, data.style_id])
		return false

	var tiles_meta := JsonFile.read("res://assets/generated/%s/tiles.json" % _style.id)
	var tiles_texture := load("res://assets/generated/%s/tiles.png" % _style.id) as Texture2D
	if not tiles_meta.ok or tiles_texture == null:
		push_error("World: generated tiles for '%s' are missing (run tools/gen_sprites.gd)" % _style.id)
		return false

	var built := MapBuilder.build(data, _style, tiles_texture, tiles_meta.data)
	if not built.ok():
		for p in built.problems:
			push_error("World: map '%s': %s" % [map_id, p])
		return false

	if _built != null and _built.root != null:
		_built.root.queue_free()
	_built = built
	add_child(built.root)

	_source = FileSpriteSource.create(_style.id)
	# The dialog box takes its colours from the map's style, so a map in a different style
	# arrives with matching chrome rather than the previous map's.
	if _dialog.get_child_count() == 0:
		_dialog.setup(_style, get_viewport_rect().size)
	_spawn_player(data, spawn_id)
	_spawn_npcs(data)
	_configure_camera(data)

	GameState.current_map = map_id
	Router.reset()
	EventBus.map_entered.emit({"map_id": map_id, "spawn_id": spawn_id})
	return true


func _spawn_player(data: MapData, spawn_id: StringName) -> void:
	var at := MapBuilder.spawn_position(data, spawn_id, _built.tile_size)
	if at == Vector2(-1.0, -1.0):
		push_error("World: map '%s' has no spawn '%s'" % [data.id, spawn_id])
		at = MapData.tile_to_world(Vector2i.ONE, _built.tile_size)

	if _player == null:
		_player = ActorBody.new()
		_player.name = "Player"
		_player.setup(_config, _source, PLAYER_CHARACTER)
	elif _player.get_parent() != null:
		_player.get_parent().remove_child(_player)
	# The player joins the y-sorted layer, not the map root: it has to sort against the decor
	# tiles, or it is permanently in front of or behind every bush in the map.
	_built.sorted.add_child(_player)
	_player.global_position = at
	_player.halt(GameState.player_facing)


func _spawn_npcs(data: MapData) -> void:
	_npcs.clear()
	for entry: Variant in data.npcs:
		var npc: Dictionary = entry
		var raw := JsonFile.to_int_array(npc.get("tile", []))
		if raw.size() != 2:
			continue
		var npc_id := StringName(str(npc.get("id", "?")))
		var body := ActorBody.new()
		body.name = "Npc_" + String(npc_id)
		body.setup(_config, _source, StringName(str(npc.get("character", ""))))
		_built.sorted.add_child(body)
		body.global_position = MapData.tile_to_world(Vector2i(raw[0], raw[1]), _built.tile_size)
		# An unreadable or absent facing falls back to front-facing rather than erroring: a
		# map is data, and the worst case here is an NPC looking the wrong way.
		var facing := Dir.from_name(str(npc.get("facing", "")))
		body.halt(facing if facing >= 0 else Dir.D.DOWN)
		_npcs[npc_id] = {"body": body, "dialog": str(npc.get("dialog", ""))}


func _configure_camera(data: MapData) -> void:
	if _camera.get_parent() == null:
		_player.add_child(_camera)
	_camera.enabled = true
	# Smoothing fights pixel snapping: the camera lands on fractional positions and the whole
	# world shimmers by a pixel. Off unless a project deliberately turns it on.
	_camera.position_smoothing_enabled = _config.camera_smoothing > 0.0
	_camera.position_smoothing_speed = _config.camera_smoothing

	var limits := MapBuilder.camera_limits(data, _built.tile_size)
	var viewport := get_viewport_rect().size
	# A map narrower than the view cannot be clamped into it - the clamp would shove the map
	# off-centre. That axis is left unlimited so the map sits in the middle instead.
	if limits.size.x >= viewport.x:
		_camera.limit_left = limits.position.x
		_camera.limit_right = limits.end.x
	else:
		_camera.limit_left = -10000000
		_camera.limit_right = 10000000
	if limits.size.y >= viewport.y:
		_camera.limit_top = limits.position.y
		_camera.limit_bottom = limits.end.y
	else:
		_camera.limit_top = -10000000
		_camera.limit_bottom = 10000000


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	if not Router.player_can_move():
		_player.halt()
		return
	var step := _player.apply(Locomotion.read_input())
	GameState.set_player(_player.global_position, step.facing)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# One event, one action - the same guard the rest of the project uses. An interaction
	# handled twice opens a conversation and immediately advances past its first line.
	if not _gate.accept(event):
		return
	if not Router.accepts_world_input() or not event.is_action(&"interact"):
		return
	if try_interact():
		get_viewport().set_input_as_handled()


## Talks to whatever the player is facing. Public because the QA harness drives it and
## because it is the one action worth being able to trigger without an input event.
func try_interact() -> bool:
	if _player == null:
		return false
	var target := Interactor.find(_player.global_position, _player.facing, _config, _targets())
	if target == null:
		return false
	var npc: Dictionary = _npcs.get(target.id, {})
	var dialog_id := str(npc.get("dialog", ""))
	if dialog_id.is_empty():
		return false

	# The NPC turns to face the player. Small, and its absence is the loudest thing about a
	# conversation with someone looking the other way.
	var body: ActorBody = npc["body"]
	body.halt(Dir.facing_from_vector(_player.global_position - body.global_position, body.facing))

	var runner := DialogRunner.load_from("res://data/dialog/%s.json" % dialog_id, GameState.flags)
	if not runner.ok:
		push_error("World: %s" % runner.error)
		return false
	for p in runner.problems():
		push_error("World: " + p)

	_player.halt()
	if not _dialog.open(runner):
		return false
	Router.open_overlay(Router.State.DIALOG)
	EventBus.interacted.emit({"target_id": target.id, "kind": &"dialog"})
	EventBus.dialog_changed.emit({"dialog_id": StringName(dialog_id), "open": true})
	return true


func _on_dialog_closed(flags: Array) -> void:
	# Flags are applied HERE, once the conversation actually reached them - the runner
	# collects them and never writes, so an abandoned dialog leaves no promises behind.
	for flag: Variant in flags:
		GameState.set_flag(StringName(str(flag)), true)
	Router.close_overlay()
	EventBus.dialog_changed.emit({"dialog_id": &"", "open": false})


func _targets() -> Array[Interactor.Target]:
	var out: Array[Interactor.Target] = []
	for npc_id: Variant in _npcs.keys():
		var body: ActorBody = _npcs[npc_id]["body"]
		out.append(Interactor.Target.new(npc_id, body.global_position, _config.body_size, body))
	return out


## Test and QA access. Reaching for the node directly from outside would tie every test to
## the scene's shape; these are the things anything outside actually needs.
func player() -> ActorBody:
	return _player


func map_data() -> MapData:
	return _built.data if _built != null else null


func dialog_box() -> DialogBox:
	return _dialog


func npc_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _npcs.keys():
		out.append(k)
	out.sort()
	return out
