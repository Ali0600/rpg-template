extends Node2D
## The playable world: builds a map from data, spawns the player, follows with the camera.
##
## Everything specific to a game lives in `data/` - which map, which characters, which
## tiles. This file only knows how to assemble those, which is what makes it template code
## rather than game code.

## The game being played, resolved once at boot. Nothing in this file names a map, a spawn,
## a character or a line of on-screen text any more: those were three consts and a string
## literal, and they were the whole reason a second game could not exist without editing the
## generic world. One game ships; that is a fact about `data/`, not about this file.
var _game: GameManifest
## The game's own code, if it has any. Null is normal: a game whose whole design is
## expressible in maps and dialog needs none.
var _hooks: GameHooks
var _config: GameConfig
var _style: SpriteStyle
var _source: SpriteSource
var _built: MapBuilder.Built
var _player: ActorBody
## Created by start_game, freed by _teardown_game. They used to be built at the declaration,
## which is the same as "built once per process" - correct while one game ran forever.
var _camera: Camera2D
var _dialog: DialogBox
## npc id -> {"body": ActorBody, "dialog": String}
var _npcs: Dictionary = {}
var _gate := InputGate.new()
var _hint: ControlsHint
## The pause menu, when it is up. It belongs to the running game - its slot list is that
## game's - so _teardown_game frees it.
var _pause: PauseScreen
## The tile the player was on last frame, so a warp fires on ARRIVING at a tile rather than
## on every frame spent standing there.
var _last_tile := Vector2i(-9999, -9999)

## How many map entries may chain through on_map_entered before it is called a loop.
const MAX_CHAINED_ENTRIES := 8

## "Use the map's spawn." A sentinel rather than an optional Vector2 because every real
## position is a valid one, including the origin - there is no in-band value left to mean
## "unset". Only restore() ever passes something else.
const NO_SPOT := Vector2.INF
var _entry_depth := 0


func _ready() -> void:
	# Resolution happens here and exactly once per process; construction is start_game's job,
	# so booting and re-starting cannot drift into two different ideas of what starting means.
	var game := GameSelect.resolve()
	if game == null:
		# GameSelect has already said which of the three ways it failed. There is no default to
		# fall back to: with one game shipped this cannot happen, and if a second is ever added
		# without saying which boots, a guessed game presents as the game you meant to run
		# behaving strangely - which is a much worse afternoon than an error.
		return
	start_game(game)


## Boots a game from scratch: tears down whatever was running, then builds the new one.
##
## Deliberately NOT enter_map with looser guards. enter_map is idempotent WITHIN a game, and
## the four guards that make it so - the player, the dialog box, the hint, the camera's parent
## - are right for a warp: rebuilding the player on every warp would re-run setup and lose its
## facing for no reason. Loosening them would be fixing the wrong thing. This restores the
## precondition each guard was written against instead, so the warp path is untouched.
func start_game(manifest: GameManifest) -> bool:
	_teardown_game()
	_game = manifest
	# The one fact a save carries that no map can supply. Set here because this is where "a
	# game is running" becomes true, and by nothing else: a view that assigned it would be a
	# second writer for the one field that decides which slots a player is looking at.
	GameState.game = _game.id
	for p in _game.problems():
		push_error("World: game '%s': %s" % [_game.id, p])
	_config = _game.config
	if _config == null:
		push_error("World: game '%s' has no config" % _game.id)
		return false
	_hooks = _game.new_hooks()
	_camera = Camera2D.new()
	_dialog = _new_dialog()
	_hint = ControlsHint.new()
	add_child(_hint)
	return enter_map(_game.start_map, _game.start_spawn)


## Building the box and hearing its one signal are ONE statement, because they were two and
## the second is the easy one to forget. A DialogBox whose `closed` nobody hears leaves Router
## in DIALOG after the first conversation and the player never moves again - and the box hides
## itself, so on screen the conversation looks like it ended normally.
func _new_dialog() -> DialogBox:
	var box := DialogBox.new()
	box.closed.connect(_on_dialog_closed)
	add_child(box)
	return box


## Everything a game owns, gone, and every member back to what it was before _ready ran.
##
## free(), not queue_free(): start_game builds the replacement in this same call, and a
## queue_freed node is alive for the rest of the frame - still drawing, still handling input,
## and still found by a depth-first search for an ActorBody, which is how a scene test locates
## the player. The warp inside enter_map uses queue_free for the OPPOSITE reason and must keep
## it: it rescues the player out of the dying root a few lines later, which only works while
## the old tree is still standing.
func _teardown_game() -> void:
	# The map root owns the player (it lives under _built.sorted) and the player owns the
	# camera, so this one free takes all three. Freeing the player separately reads as thorough
	# and is not: it is redundant by construction, and a mutant proved no test could tell.
	if _built != null and _built.root != null and is_instance_valid(_built.root):
		_built.root.free()
	_built = null
	# Nulled by hand because a freed instance does NOT become null on its own - it becomes a
	# reference that every `!= null` check still passes and every use of which is an error.
	_player = null
	# Almost always freed as the player's child above. Not always: a start_game whose enter_map
	# failed before _configure_camera leaves one parented to nothing, which would leak.
	if _camera != null and is_instance_valid(_camera):
		_camera.free()
	_camera = null
	# These bodies were inside the root just freed. _spawn_npcs clears this too, but only if
	# the next enter_map gets that far, and _targets() iterates it unguarded.
	_npcs.clear()

	if _dialog != null and is_instance_valid(_dialog):
		_dialog.closed.disconnect(_on_dialog_closed)
		_dialog.free()
	_dialog = null
	if _hint != null and is_instance_valid(_hint):
		_hint.free()
	_hint = null
	# Its slot list names the game being torn down, so it cannot outlive it. free() rather than
	# queue_free() like everything else here: this is never reached from inside the screen's own
	# signal handler, and a deferred free would leave it on screen over the next game's world.
	if _pause != null and is_instance_valid(_pause):
		_pause.free()
	_pause = null

	_game = null
	_hooks = null
	_config = null
	_style = null
	_source = null
	# The sentinel, not the tile the player left the last game standing on: _check_warp compares
	# against this on the first frame of the next one, and a coincidental match would silently
	# skip the first warp walked onto - which reads as a broken door, not as stale state.
	_last_tile = Vector2i(-9999, -9999)
	# A hook that warped on entry and errored can leave this above zero, starting the next game
	# that much closer to the chained-entry ceiling.
	_entry_depth = 0

	# One game's flags must not unlock another's gate, and `seen` is keyed "<map>/<object>",
	# which two games are free to collide on. Both have existed since M3 and M5 with no caller;
	# a switch is what they were written for.
	GameState.reset()
	AudioBus.stop_music()


## Loads a map and puts the player on a named spawn. The one entry point, so a warp, a load
## and the first boot all take the same path - three ways into a map is three places for the
## camera limits to be forgotten.
##
## `at` overrides the spawn with an exact position, which is what restoring a save is: a save
## records where the player STOOD, and no spawn describes that. Nothing else passes it.
func enter_map(map_id: StringName, spawn_id: StringName, at: Vector2 = NO_SPOT) -> bool:
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

	# Anything outside the map - the letterbox on a map smaller than the viewport - is painted
	# with the style's own panel colour rather than the engine's default grey, so a small area
	# reads as framed rather than as unfinished. Style-driven, like every other colour.
	RenderingServer.set_default_clear_color(_style.ui_color("panel"))

	_source = FileSpriteSource.create(_style.id)
	# The dialog box takes its colours from the map's style, so a map in a different style
	# arrives with matching chrome rather than the previous map's.
	if _dialog.get_child_count() == 0:
		_dialog.setup(_style, get_viewport_rect().size)
	if _hint.get_child_count() == 0:
		_hint.setup(_style, get_viewport_rect().size, _game.controls_hint)
	_spawn_player(data, spawn_id, at)
	_spawn_npcs(data)
	_configure_camera(data)

	GameState.current_map = map_id
	Router.reset()
	EventBus.map_entered.emit({"map_id": map_id, "spawn_id": spawn_id})

	# Last, so a game's code sees a map that is fully built and a player already standing in
	# it. Its effects go through the same _apply as everything else - including a warp, which
	# is why the depth is counted: a hook that warps on entry can re-enter forever, and an
	# unguarded stack overflow reports as a crash with no clue which map caused it.
	if _hooks != null:
		if _entry_depth >= MAX_CHAINED_ENTRIES:
			push_error("World: %d chained map entries - a hook is warping on entry in a loop"
				% _entry_depth)
		else:
			_entry_depth += 1
			var ctx := _context()
			_hooks.on_map_entered(ctx)
			if ctx.has_effects():
				_apply(ctx)
			_entry_depth -= 1
	return true


func _spawn_player(data: MapData, spawn_id: StringName, at: Vector2) -> void:
	# A finite `at` is a restored position and is used as given. The spawn lookup below is
	# skipped rather than done-and-discarded, so a save into a map with no matching spawn name
	# does not report a spawn fault it does not have.
	if not at.is_finite():
		at = MapBuilder.spawn_position(data, spawn_id, _built.tile_size)
		if at == Vector2(-1.0, -1.0):
			push_error("World: map '%s' has no spawn '%s'" % [data.id, spawn_id])
			at = MapData.tile_to_world(Vector2i.ONE, _built.tile_size)

	if _player == null:
		_player = ActorBody.new()
		_player.name = "Player"
		_player.setup(_config, _source, _game.player_character)
	elif _player.get_parent() != null:
		_player.get_parent().remove_child(_player)
	# The player joins the y-sorted layer, not the map root: it has to sort against the decor
	# tiles, or it is permanently in front of or behind every bush in the map.
	_built.sorted.add_child(_player)
	# place(), not assign-then-halt. With a grid step in flight the halt would resolve it
	# against the cell the player left, in the map they left, and teleport them back there.
	_player.place(at, GameState.player_facing)
	# Seeded with the spawn tile so a spawn placed ON a warp does not immediately re-trigger
	# it - which is exactly what a two-way door between maps looks like.
	_last_tile = MapData.world_to_tile(at, _built.tile_size)


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
		# An unreadable or absent facing falls back to front-facing rather than erroring: a
		# map is data, and the worst case here is an NPC looking the wrong way.
		var facing := Dir.from_name(str(npc.get("facing", "")))
		body.place(MapData.tile_to_world(Vector2i(raw[0], raw[1]), _built.tile_size),
			facing if facing >= 0 else Dir.D.DOWN)
		# The whole entry is kept, not just the two fields the template reads. It is what a
		# game's hook is handed, so a key the template has no opinion about ("behavior",
		# whatever a game invents) survives the trip instead of being quietly dropped here.
		var record := npc.duplicate()
		record["id"] = npc_id
		record["kind"] = StringName(str(npc.get("kind", "npc")))
		record["body"] = body
		_npcs[npc_id] = record


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
		# The halt may have put a grid step back on its cell, and this is the write that gets
		# saved and that the QA harness reads. Without it, state would disagree with where the
		# player is actually standing for the whole conversation. A no-op in free movement.
		GameState.set_player(_player.global_position, _player.facing)
		return
	var input := Locomotion.read_input()
	if input != Vector2.ZERO:
		_hint.dismiss()
	var step := _player.apply(input)
	GameState.set_player(_player.global_position, step.facing)
	_check_warp()


## Moves the player to another map when they stand on a warp tile.
##
## Guarded by the tile they were on last frame: without it, arriving on the destination map
## next to a warp back would immediately send them home again, and the two maps would bounce
## the player between them forever.
func _check_warp() -> void:
	if _built == null:
		return
	var tile := _player.tile(_built.tile_size)
	if tile == _last_tile:
		return
	_last_tile = tile
	var warp := _built.data.warp_at(tile)
	if warp.is_empty():
		return
	var destination: StringName = warp["map"]
	if String(destination).is_empty():
		return

	if not MapData.warp_allowed(warp, GameState.flags, GameState.inventory.to_dict()):
		# Once per arrival, not once per frame: _last_tile is already updated above, so
		# standing against a locked gate says its line once rather than every tick.
		var locked: StringName = warp.get("locked_dialog", &"")
		if not String(locked).is_empty():
			_open_dialog(locked)
		return
	enter_map(destination, warp["spawn"])


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# One event, one action - the same guard the rest of the project uses. An interaction
	# handled twice opens a conversation and immediately advances past its first line.
	if not _gate.accept(event):
		return
	if not Router.accepts_world_input():
		return
	# Inside the same guard as interacting, so the pause menu cannot be opened from inside a
	# conversation - Router already refuses world input while one is on screen, and the dialog
	# box consumes `cancel` itself.
	if event.is_action(&"cancel"):
		if open_pause():
			get_viewport().set_input_as_handled()
		return
	if not event.is_action(&"interact"):
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
	var record: Dictionary = target.payload if target.payload is Dictionary else {}

	# Turning to face the player happens on being FOUND, not on a conversation opening, so
	# someone with nothing to say still looks at you rather than ignoring you.
	var body := record.get("body") as ActorBody
	if body != null:
		body.halt(Dir.facing_from_vector(_player.global_position - body.global_position, body.facing))

	var ctx := _context()
	if not Interaction.resolve(_hooks, ctx, target):
		return false
	EventBus.interacted.emit({"target_id": target.id, "kind": record.get("kind", &"")})
	return _apply(ctx)


func _on_dialog_closed(effects: Array) -> void:
	# Applied HERE, once the conversation actually reached them - the runner collects and never
	# writes, so an abandoned dialog leaves no promises behind. Through the same sink as
	# everything else: a gift from a conversation and a gift from a chest are one code path.
	_apply_effects(effects)
	Router.close_overlay()
	EventBus.dialog_changed.emit({"dialog_id": &"", "open": false})


func _targets() -> Array[Interactor.Target]:
	var out: Array[Interactor.Target] = []
	for npc_id: Variant in _npcs.keys():
		var record: Dictionary = _npcs[npc_id]
		var body: ActorBody = record["body"]
		# The payload is the RECORD now, not the body. Interactor has always carried one and
		# nothing ever read it: try_interact looked the target back up by id, which is why an
		# interaction could only ever be with an NPC.
		out.append(Interactor.Target.new(npc_id, body.global_position, _config.body_size, record))

	# Objects are interaction points with no body of their own: what the player sees is the
	# decor tile they stand on. They join the same list, so a sign and a villager are found
	# by the same "closest thing I am facing" rule rather than by two competing ones.
	if _built != null:
		for entry: Variant in _built.data.objects:
			var object: Dictionary = entry
			var raw := JsonFile.to_int_array(object.get("tile", []))
			if raw.size() != 2:
				continue
			var at := MapData.tile_to_world(Vector2i(raw[0], raw[1]), _built.tile_size)
			var record := object.duplicate()
			record["id"] = StringName(str(object.get("id", "")))
			out.append(Interactor.Target.new(record["id"], at, _config.body_size, record))
	return out


## The snapshot a hook is handed. Built here because this is the file that is allowed to name
## the autoloads; nothing under games/ may.
func _context() -> GameContext:
	var tile := MapData.world_to_tile(_player.global_position, _built.tile_size) if _player != null else Vector2i.ZERO
	return GameContext.create(GameState.current_map, tile, GameState.flags, GameState.seen, self,
		GameState.inventory.to_dict())


## The one place an effect reaches live state. Everything - the template's own verbs and a
## game's hooks alike - arrives here as the same list, so there is a single answer to "what
## can an interaction actually do".
##
## A failing effect logs and the rest still run: the flag on a chest is the durable half and
## the line of text is presentation, so a broken dialog file must not also swallow the pickup.
func _apply(ctx: GameContext) -> bool:
	return _apply_effects(ctx.effects())


## The one place any effect reaches live state - a hook's, an object's, or a conversation's.
## Two sinks would mean two places to look for "what does this actually do", and the second one
## is always the one that forgets to learn a new op.
func _apply_effects(effects: Array) -> bool:
	var did := false
	for effect: Dictionary in effects:
		var op := StringName(str(effect.get("op", "")))
		match op:
			GameContext.OP_FLAG:
				GameState.set_flag(StringName(str(effect.get("key", ""))), bool(effect.get("value", true)))
				did = true
			GameContext.OP_SEEN:
				GameState.mark_seen(str(effect.get("key", "")))
				did = true
			GameContext.OP_SOUND:
				EventBus.sound_requested.emit({"id": StringName(str(effect.get("id", "")))})
				did = true
			GameContext.OP_DIALOG:
				did = _open_dialog(StringName(str(effect.get("dialog", "")))) or did
			GameContext.OP_GIVE_ITEM:
				var item_id := StringName(str(effect.get("id", "")))
				# An item nothing describes cannot be drawn in a list or named to a player, so
				# it is refused here rather than carried invisibly.
				if Registry.get_resource(&"ItemDef", item_id) == null:
					push_error("World: nothing describes item '%s'" % item_id)
				elif GameState.give_item(item_id, int(effect.get("count", 1))):
					did = true
			GameContext.OP_TAKE_ITEM:
				# decide() and the dialog runner both refuse before emitting a take they cannot
				# cover, so reaching this and failing is a bug, said out loud.
				if GameState.take_item(StringName(str(effect.get("id", ""))), int(effect.get("count", 1))):
					did = true
				else:
					push_error("World: took '%s' the player is not carrying" % effect.get("id", ""))
			GameContext.OP_WARP:
				did = enter_map(StringName(str(effect.get("map", ""))),
					StringName(str(effect.get("spawn", "start")))) or did
			_:
				push_error("World: unknown effect '%s' - nothing carried it out" % op)
	return did


func _open_dialog(dialog_id: StringName) -> bool:
	var runner := DialogRunner.load_from("res://data/dialog/%s.json" % dialog_id, GameState.flags,
		GameState.inventory.to_dict())
	if not runner.ok:
		push_error("World: %s" % runner.error)
		return false
	for p in runner.problems():
		push_error("World: " + p)

	_player.halt()
	if not _dialog.open(runner):
		return false
	Router.open_overlay(Router.State.DIALOG)
	EventBus.dialog_changed.emit({"dialog_id": dialog_id, "open": true})
	return true


## Puts up the pause menu. Public for the same reason try_interact() is: a test should be able
## to pause without staging an input event. Refuses rather than rebuilding when one is already
## up, and refuses outright when no game is running - there would be no slots to list.
func open_pause() -> bool:
	if _pause != null or _game == null:
		return false
	_pause = PauseScreen.new()
	# Constructed and connected in one function, the DialogBox rule: a view built in one place
	# and wired in another is a view that eventually gets built and not wired.
	_pause.resumed.connect(_close_pause)
	_pause.save_requested.connect(_on_save_requested)
	_pause.load_requested.connect(_on_load_requested)
	add_child(_pause)
	_pause.setup(PauseMenu.of(_slot_summaries()), _style, get_viewport_rect().size)
	Router.open_overlay(Router.State.PAUSED)
	return true


## What is in each of this game's slots, for drawing. peek() rather than load_slot(): merely
## looking at the menu must not park files or announce loads nobody asked for.
func _slot_summaries() -> Array[SaveData]:
	var out: Array[SaveData] = []
	if _game == null or _config == null:
		return out
	for slot in _config.save_slots:
		out.append(SaveManager.peek(_game.id, slot))
	return out


func _close_pause() -> void:
	if _pause == null:
		return
	# queue_free, not free: this is reached from inside the screen's own input handler, and
	# freeing a node while it is dispatching an event is a crash.
	_pause.queue_free()
	_pause = null
	Router.close_overlay()


func _on_save_requested(slot: int) -> void:
	SaveManager.save(slot, GameState.to_save())
	# The menu stays up and is told what the slots hold NOW, so the row the player is looking
	# at shows what they just wrote. A save whose only feedback is the screen closing is
	# indistinguishable from one that failed.
	if _pause != null:
		_pause.refresh(_slot_summaries())


func _on_load_requested(slot: int) -> void:
	# Deferred, and not as a precaution: this tears down and rebuilds the map, and doing that
	# inside the screen's input callback frees nodes while the tree is still dispatching to
	# them. The `interact` press that asked for the load is also still in flight.
	_commit_load.call_deferred(slot)


func _commit_load(slot: int) -> void:
	# A frame passed. A teardown or a second event could have happened in it.
	if _pause == null or _game == null:
		return
	var data := SaveManager.load_slot(_game.id, slot)
	if data == null:
		# load_slot has parked the bytes and said so. The menu stays up showing what the slots
		# hold now - which is one fewer, and that is the honest thing for it to show.
		_pause.refresh(_slot_summaries())
		return
	_close_pause()
	restore(data)


## Puts a loaded save back into the world. The one path from a save to a running game, so
## "loading" cannot mean two slightly different things.
##
## State first, THEN the map: on_map_entered hooks read flags, so a map entered before the
## save's flags are in place runs its opening hook against the previous game's progress.
## enter_map resets the Router (so PAUSED is left) and re-runs those hooks, which is intended -
## they are flag-gated and route through _apply like every other effect.
func restore(data: SaveData) -> bool:
	GameState.from_save(data)
	return enter_map(data.map, &"", data.position)


## Test and QA access. Reaching for the node directly from outside would tie every test to
## the scene's shape; these are the things anything outside actually needs.
func player() -> ActorBody:
	return _player


func map_data() -> MapData:
	return _built.data if _built != null else null


func dialog_box() -> DialogBox:
	return _dialog


func pause_screen() -> PauseScreen:
	return _pause


func npc_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _npcs.keys():
		out.append(k)
	out.sort()
	return out
