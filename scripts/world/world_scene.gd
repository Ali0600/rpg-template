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
## npc id -> the whole map record, plus {"body": ActorBody, "id", "kind"} and, for a mover,
## {"brain": NpcBrain}. The map's own keys survive because a game's hook is handed this.
var _npcs: Dictionary = {}
var _gate := InputGate.new()
var _hint: ControlsHint
## The style the running game asked for, BEFORE the player's palette was laid over it. _style is
## what everything is drawn with; this is what a re-choice starts from.
var _style_source: SpriteStyle = null
## The pause menu, when it is up. It belongs to the running game - its slot list is that
## game's - so _teardown_game frees it.
var _pause: PauseScreen
var _battle: BattleScreen
## Who the paused screen's pages are about. Reset to the leader whenever the menu opens, so a
## player who looked at a companion last time does not come back to their page.
var _pause_member: StringName = &""
var _shop: ShopScreen
var _game_over: GameOverScreen
var _night: RestScreen
var _saving: SaveScreen
## The title, when it is up. NOT part of a running game - it is what a game is started FROM -
## so _teardown_game frees it for the opposite reason it frees the pause menu: not because it
## belongs to the game being torn down, but because the thing tearing one down is about to
## build another over the top of it.
var _title: TitleScreen
## The credits, when they are up. Over the title rather than over a game, so it is torn down
## with the title for the same reason: the thing about to build a game frees what is on screen.
var _credits: CreditsScreen
## The game the title offers. Written at boot by the resolver AND by start_game, so a title
## reached back from a game-over offers the game that was actually RUNNING - which is the same
## thing as the resolved one for a player, and is not the same thing for the integration
## suites that hand start_game a manifest of their own.
var _offered: GameManifest
## Enemy id -> its ActorBody, for the ones still standing on this map.
var _enemies: Dictionary = {}
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
	_offered = game
	# Resolution still happens exactly once per process; what changed is that STARTING is now a
	# press rather than the next line. A title that cannot be drawn boots the way this always
	# did rather than not at all - it needs a style, and there is no map yet to supply one, so
	# the one thing that can fail here fails into the old behaviour instead of a black screen.
	if not open_title():
		start_game(game)


## Boots a game from scratch: tears down whatever was running, then builds the new one.
##
## Deliberately NOT enter_map with looser guards. enter_map is idempotent WITHIN a game, and
## the four guards that make it so - the player, the dialog box, the hint, the camera's parent
## - are right for a warp: rebuilding the player on every warp would re-run setup and lose its
## facing for no reason. Loosening them would be fixing the wrong thing. This restores the
## precondition each guard was written against instead, so the warp path is untouched.
func start_game(manifest: GameManifest) -> bool:
	if not _build_game(manifest):
		return false
	# Before the first map, so a hook or an encounter on the opening tile finds a real player
	# rather than one at zero health. _teardown_game has already reset the party, so this is
	# always the fresh-hero case here.
	_ensure_party()
	# The purse the game starts with. Fresh-game only: a LOAD replaces it wholesale through
	# from_save, which is why this is here and not in _build_game.
	GameState.give_gold(_game.starting_gold)
	return enter_map(_game.start_map, _game.start_spawn)


## Boots a game FROM A SAVE: the same machinery, then the save's own map - and never the start
## map in between. It exists because the title's Continue once went through start_game first,
## which enters the start map with a FRESH GameState on its way to the restore: the map-entry
## hooks fired against a player who had no flags, and the game's opening conversation replayed
## over the loaded save. A load must not travel THROUGH the beginning of a game to reach its
## middle.
##
## Two functions rather than a flag on one, because the endings share nothing: one enters a
## spawn fresh, the other restores a position. A boolean that changes what a function's ending
## MEANS is two functions wearing one name.
func boot_from_save(manifest: GameManifest, data: SaveData) -> bool:
	if not _build_game(manifest):
		return false
	# No _ensure_party and no starting gold: the save is about to say what the player is worth,
	# and restore()'s own _ensure_party covers a file written by a game that had no combat.
	return restore(data)


## Everything a running game needs before it has a map: the teardown, who is running, the
## config, the hooks, the voice, and the nodes every map re-parents. ONE copy, because the two
## ways in differ only in their last step - and the day they were two copies, the duplicated
## line that records which game is running made the mutant guarding it AMBIGUOUS, which is the
## aim check saying out loud that a fact had come to live in two places. (Note this comment
## may not quote that line: the aim check greps text, so prose repeating an anchor breaks it
## exactly the way a second copy of the code does.)
func _build_game(manifest: GameManifest) -> bool:
	_teardown_game()
	_offered = manifest
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
	# Which cues exist is a property of the GAME, so the bus is pointed at this one's voice
	# here rather than at boot. A null voice is a silent game and is a legal shape - AudioBus
	# then resolves only whatever a game dropped in data/audio, which may be nothing at all.
	AudioBus.use_style(_game.sound_style)
	_camera = Camera2D.new()
	_build_chrome()
	return true


## Building the box and hearing its one signal are ONE statement, because they were two and
## the second is the easy one to forget. A DialogBox whose `closed` nobody hears leaves Router
## in DIALOG after the first conversation and the player never moves again - and the box hides
## itself, so on screen the conversation looks like it ended normally.
## The one place a view's request for a noise becomes a noise. Every screen emits; nothing
## else in scripts/ui touches the speaker, which is what keeps those files inside the per-file
## parse gate along with every suite that depends on them.
func _on_sound_wanted(id: StringName) -> void:
	AudioBus.play_sfx(id)


## The player turned the volume. Settings owns the value and writes it; the menu is handed the
## new text the way it is handed new slot contents after a save.
func _on_sound_changed() -> void:
	Settings.cycle_sound()
	# Played AFTER the change, so the blip is at the volume just chosen - which is the only
	# feedback there is that Off means off.
	AudioBus.play(Sfx.Cue.MENU_CONFIRM)
	if _pause != null:
		_refresh_pause()


## Binds a style: what the world is drawn WITH, and how big the world IS.
##
## ONE function, called by enter_map and by open_title, because binding a style is three
## statements that must not come apart - the style itself, the letterbox colour, and the window
## the two are shown in. The title used to do two of the three, and the milestone before this
## one records what a partial bind costs: the title asked for its music through a bus with no
## voice and played nothing at all for four milestones, on every platform.
##
## rescale() is the pair to _mount_ui: the dialog box and the controls hint are built in
## _build_game, BEFORE any map has said which style is running, so mounting alone cannot know
## their scale. They are brought to it here, along with anything left over from another style.
##
## It is also the ONE place the player's chosen palette is laid over the style, for the reason
## there is one binder at all: a screen that composed its own colours would be a second answer to
## "what does this game look like", and the one that ran second would win by accident.
func _bind_style(style: SpriteStyle) -> void:
	# What the GAME asked for, kept beside what is being drawn with: a palette is laid OVER a
	# style, so re-choosing one has to start from the style again rather than from the last
	# composed result, which would layer a palette on a palette and never get back.
	_style_source = style
	var chosen := _palette_of()
	_style = style if chosen == null else style.with_ui_colors(chosen.colors)
	# Anything outside the map - the letterbox on a map smaller than the viewport - is painted
	# with the style's own panel colour rather than the engine's default grey, so a small area
	# reads as framed rather than as unfinished. Style-driven, like every other colour.
	RenderingServer.set_default_clear_color(_style.ui_color("panel"))
	UiScale.apply(get_window(), _style)
	UiScale.rescale(self, _style)


## _bind_style's PAIR. The window belongs to the ROOT, not to this scene, so a world that grew
## it and then went away has left somebody else's furniture moved. In the game that is the frame
## before quit and costs nothing; in a test run it is every suite that comes afterwards laying
## itself out against a window this one resized - which is what happened the day the demo became
## a 2x style. Eleven suites boot a world and exactly one of them put the window back, because
## the rule was written down in that suite rather than in the thing that breaks it. A driver
## here copes with the twelfth suite nobody has written yet.
func _exit_tree() -> void:
	UiScale.apply(get_window(), null)


## The palette the player chose, or nothing. The one place an id becomes colours.
##
## Resolved HERE rather than in the settings singleton because which palettes exist is a content
## question and that file may not ask the Registry - and because an id naming a palette this build
## does not ship must fall back in exactly one place. A game that ships no palettes at all reaches
## this and gets null, which is the same answer as "the player has not chosen one".
func _palette_of() -> UiPalette:
	var chosen := Settings.palette()
	if String(chosen).is_empty():
		return null
	var found := Registry.get_resource(&"UiPalette", chosen) as UiPalette
	if found == null:
		# Said out loud rather than swallowed: a save file naming a deleted palette draws in the
		# style's own colours, which is correct and looks exactly like the player never chose one.
		push_warning("World: no palette '%s'; drawing the style's own chrome" % chosen)
	return found


## The style bound again, after the player changed what the windows look like.
##
## _bind_style recomposes the colours, and then the two layers that OUTLIVE a map have to be
## brought to them by hand: every other screen is built fresh when it opens and takes the new
## colours for free. The dialog box is rebuilt because it holds its colours in a StyleBox and half
## a dozen theme overrides made once in setup(), and a second way of applying them would be a
## second thing to keep in step; the hint is restyled in place because rebuilding it would put a
## dismissed hint back on screen.
##
## A recolour can only be asked for from the world or the title, and no conversation can be open
## in either - the pause menu opens from WORLD only - so rebuilding the box cannot destroy one
## mid-sentence.
func _rebind_style() -> void:
	if _style_source == null:
		return
	_bind_style(_style_source)
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.closed.disconnect(_on_dialog_closed)
		_dialog.free()
		_dialog = _new_dialog()
		_dialog.setup(_style, _ui_size())
	if _hint != null and is_instance_valid(_hint):
		_hint.restyle(_style)


## The size every screen lays itself out against: the design size, at every world scale, NEVER
## the live viewport. A screen that measured the viewport would space its rows twice as far
## apart in a 640x360 world and land its help line off the bottom - and every layout gate,
## which measures against 320x180, would still pass.
func _ui_size() -> Vector2i:
	return UiScale.DESIGN_SIZE


## The one way an interface layer joins the tree. See UiScale.mount: the tenth add_child is the
## one that forgets the scale, and what it produces is a quarter-size menu in the corner.
func _mount_ui(layer: CanvasLayer) -> void:
	UiScale.mount(layer, self, _style)


## The two interface layers that OUTLIVE a map: the dialog box and the controls hint. Built here
## rather than inline in _build_game because they are also rebuilt when the player recolours the
## windows - both take their colours in setup() and hold them in StyleBoxes and theme overrides
## built once, so a recolour is a rebuild rather than a repaint.
##
## Every other screen is built fresh when it opens and needs none of this. These two are the
## exception because they are made before any map has said which style is running - which is also
## why UiScale.rescale exists.
func _build_chrome() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.closed.disconnect(_on_dialog_closed)
		_dialog.free()
	_dialog = _new_dialog()
	if _hint != null and is_instance_valid(_hint):
		_hint.free()
	_hint = ControlsHint.new()
	_mount_ui(_hint)


func _new_dialog() -> DialogBox:
	var box := DialogBox.new()
	box.closed.connect(_on_dialog_closed)
	box.sound_wanted.connect(_on_sound_wanted)
	_mount_ui(box)
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
	# The same argument for both fight screens: each names an enemy or a slot list belonging to
	# the game being torn down, and neither is ever reached from inside its own handler here.
	if _battle != null and is_instance_valid(_battle):
		_battle.free()
	_battle = null
	# Nulled OUTSIDE the guard, like every other screen here. Consistency only, and worth
	# saying so rather than implying a bug: a freed reference compares EQUAL to null in this
	# engine, so the guarded version was harmless - measured, and pinned in
	# test_engine_assumptions.gd so the next reader does not have to re-derive it.
	if _credits != null and is_instance_valid(_credits):
		_credits.free()
	_credits = null
	if _title != null and is_instance_valid(_title):
		_title.free()
	_title = null
	if _night != null and is_instance_valid(_night):
		_night.free()
	_night = null
	if _shop != null and is_instance_valid(_shop):
		_shop.free()
	_shop = null
	# Its slot list names the game being torn down, the pause screen's argument exactly.
	if _saving != null and is_instance_valid(_saving):
		_saving.free()
	_saving = null
	if _game_over != null and is_instance_valid(_game_over):
		_game_over.free()
	_game_over = null
	# These bodies were inside the root just freed, and _despawn_beaten_enemies walks this
	# unguarded.
	_enemies.clear()

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
## `at_tile` overrides the spawn with an exact place, which is what restoring a save is: a save
## records where the player STOOD, and no spawn describes that. Nothing else passes it, and it
## is in TILES because the caller is `restore` - which has the file and has not yet loaded the
## map, so it cannot know how many pixels a tile of the destination is. That conversion happens
## below, once the map's own style has answered.
func enter_map(map_id: StringName, spawn_id: StringName, at_tile: Vector2 = NO_SPOT) -> bool:
	var data := MapData.load_from(MapData.path_of(map_id))
	var style := load("res://data/styles/%s.tres" % data.style_id) as SpriteStyle
	if style == null:
		push_error("World: map '%s' names unknown style '%s'" % [map_id, data.style_id])
		return false
	_bind_style(style)

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
		_dialog.setup(_style, _ui_size())
	if _hint.get_child_count() == 0:
		_hint.setup(_style, _ui_size(), _game.controls_hint)
	# Written here, from the map's own style, and by nobody else: a save records tiles, the
	# world moves in pixels, and this is the rate between them.
	GameState.tile_size = _built.tile_size
	# The ONE place a config learns how big a tile is, beside the state that records the same
	# fact from the same source. On every map entry rather than once at boot, because a warp can
	# cross into a map drawn at another scale.
	_config = _game.config.at(_built.tile_size)
	_spawn_player(data, spawn_id, at_tile)
	_spawn_npcs(data)
	_spawn_enemies(data)
	_configure_camera(data)

	GameState.current_map = map_id
	# Stated either way, never inherited, so what the player hears is a fact about where they
	# ARE rather than about which door they came through. The bus keeps a track that is already
	# playing playing, so two rooms of one town do not restart it.
	AudioBus.play_or_silence(data.music_id)
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


func _spawn_player(data: MapData, spawn_id: StringName, at_tile: Vector2) -> void:
	# A finite `at_tile` is a restored place and is used as given, converted here because this
	# is the first point where the map's tile size is known. The spawn lookup below is
	# skipped rather than done-and-discarded, so a save into a map with no matching spawn name
	# does not report a spawn fault it does not have.
	var at := at_tile * float(_built.tile_size)
	if not at_tile.is_finite():
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
		# Behaviour is data: `static` (the default, and what every shipped NPC is) needs no
		# brain at all, so a town of statues costs nothing per frame. The seed is built from
		# stable identifiers rather than a clock, which is what lets a play session assert an
		# NPC's position hundreds of frames into a run and get the same answer every time.
		var brain := NpcBrain.of(record, body.global_position, _built.tile_size,
			SeededRng.new(SeededRng.hash_seed(0, "%s:%s:%s" % [GameState.game, data.id, npc_id])))
		if NpcBrain.is_mover(brain.kind):
			record["brain"] = brain
		_npcs[npc_id] = record


## Puts a body on every enemy tile whose enemy is still standing.
##
## An enemy already beaten is simply not built - checked here rather than hidden later, because
## a hidden body still blocks the tile it stands on, and a corridor guarded by something
## invisible is a map the player cannot cross and cannot see why.
func _spawn_enemies(data: MapData) -> void:
	_enemies.clear()
	for entry: Variant in data.enemies:
		var record: Dictionary = entry
		var raw := JsonFile.to_int_array(record.get("tile", []))
		if raw.size() != 2:
			continue
		var enemy_id := StringName(str(record.get("id", "?")))
		if GameState.was_seen(Interaction.seen_key(data.id, String(enemy_id))):
			continue
		var def := Registry.get_resource(&"EnemyDef", StringName(str(record.get("enemy", "")))) as EnemyDef
		if def == null:
			continue
		var body := ActorBody.new()
		body.name = "Enemy_" + String(enemy_id)
		body.setup(_config, _source, def.character)
		_built.sorted.add_child(body)
		var facing := Dir.from_name(str(record.get("facing", "")))
		body.place(MapData.tile_to_world(Vector2i(raw[0], raw[1]), _built.tile_size),
			facing if facing >= 0 else Dir.D.DOWN)
		_enemies[enemy_id] = body


## Removes the bodies of anything beaten since the map was drawn, so the tile a fight was
## standing on opens the moment the fight ends rather than on the next visit.
func _despawn_beaten_enemies() -> void:
	if _built == null:
		return
	for enemy_id: StringName in _enemies.keys():
		if not GameState.was_seen(Interaction.seen_key(GameState.current_map, String(enemy_id))):
			continue
		var body: ActorBody = _enemies[enemy_id]
		if is_instance_valid(body):
			body.queue_free()
		_enemies.erase(enemy_id)


func _configure_camera(data: MapData) -> void:
	if _camera.get_parent() == null:
		_player.add_child(_camera)
	_camera.enabled = true
	# Smoothing fights pixel snapping: the camera lands on fractional positions and the whole
	# world shimmers by a pixel. Off unless a project deliberately turns it on.
	_camera.position_smoothing_enabled = _config.camera_speed_px() > 0.0
	_camera.position_smoothing_speed = _config.camera_speed_px()

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
	# Stepped ABOVE the gate, unlike anything else here: a night runs precisely while the
	# player cannot walk, so putting it below would freeze the fade it is meant to play.
	if _night != null:
		_night.step()
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
	if step.footfall:
		AudioBus.play(Sfx.Cue.FOOTSTEP)
	GameState.set_player(_player.global_position, step.facing)
	_drive_npcs()
	_check_triggers()


## Walks every NPC that has a brain, one frame.
##
## It sits BELOW the `Router.player_can_move()` early return on purpose, and that placement is
## the whole design: a dialog, the pause menu, a fight or the game-over screen stops the town
## as well as the player. The speaker cannot wander off mid-sentence, and the one-shot
## turn-to-face done when the conversation opens stays true for as long as the box is up.
##
## Footfalls are read and DISCARDED. Every NPC body carries a working StepMeter, so a town of
## walkers would otherwise play a footstep cue each time any of them takes a stride - a sound
## the player cannot place and cannot escape.
func _drive_npcs() -> void:
	for entry: Variant in _npcs.values():
		var record: Dictionary = entry
		var brain := record.get("brain") as NpcBrain
		if brain == null:
			continue
		var body := record.get("body") as ActorBody
		if body == null:
			continue
		body.apply(brain.intent(body.global_position))


## What arriving on a new tile sets off. ONE guard for both kinds of trigger, because they
## share the question "is this the first frame on this tile" - two copies of that would be two
## `_last_tile`s, and the second one is the one that fires every frame.
##
## Guarded by the tile they were on last frame: without it, arriving on a destination map next
## to a warp back would immediately send them home again, and the two maps would bounce the
## player between them forever.
func _check_triggers() -> void:
	if _built == null:
		return
	var tile := _player.tile(_built.tile_size)
	if tile == _last_tile:
		return
	_last_tile = tile
	# A door first: a warp and a fight on adjacent tiles is a map-design mistake, and leaving
	# rather than fighting is the safer way to resolve it - the enemy is still there afterwards.
	if _try_warp(tile):
		return
	_try_encounter(tile)


## Moves the player to another map when they stand on a warp tile. Returns whether the tile
## had a warp at all - answered, refused or taken - so the caller knows to stop looking.
func _try_warp(tile: Vector2i) -> bool:
	var warp := _built.data.warp_at(tile)
	if warp.is_empty():
		return false
	var destination: StringName = warp["map"]
	if String(destination).is_empty():
		return false

	if not MapData.warp_allowed(warp, GameState.flags, GameState.inventory.to_dict()):
		# Once per arrival, not once per frame: _last_tile is already updated above, so
		# standing against a locked gate says its line once rather than every tick.
		AudioBus.play(Sfx.Cue.LOCKED)
		var locked: StringName = warp.get("locked_dialog", &"")
		if not String(locked).is_empty():
			_open_dialog(locked)
		return true
	# Here rather than in enter_map, which is also the first spawn and a save restore -
	# neither of which is a door being walked through.
	AudioBus.play(Sfx.Cue.WARP)
	enter_map(destination, warp["spawn"])
	return true


## Starts a fight when the player arrives NEXT TO something that fights back.
##
## Adjacency rather than collision, and it is not an approximation of one: a body stops the
## player six to ten pixels out, which is most of the way through the tile they are entering,
## so waiting for contact would mean the trigger frame depends on walk speed and the exact
## fraction of a tile a step happens to cover. Arriving on a tile is a whole number, on a known
## frame, identical on every machine - which is what lets a QA script fight a scripted battle.
##
## Diagonals deliberately do not count. A fight the player is meant to have is made unavoidable
## by GEOMETRY - a one-tile gap they must walk through - rather than by a radius, because a
## radius that catches you as you slip past a corner reads as the game grabbing you.
func _try_encounter(tile: Vector2i) -> void:
	if _game == null or _built.data.enemies.is_empty():
		return
	for step in Dir.ALL:
		var offset := Dir.vector_of(step)
		var record := _built.data.enemy_at(tile + Vector2i(int(offset.x), int(offset.y)))
		if record.is_empty():
			continue
		var seen_key := Interaction.seen_key(GameState.current_map, String(record["id"]))
		if GameState.was_seen(seen_key):
			continue
		# Every name the record carries, which is one for a lone enemy and several for a
		# formation. A missing one is said out loud and the fight goes ahead without it, because
		# a formation that opens one foe short is a legible bug where a fight that silently never
		# happens is the hardest kind of content bug there is.
		var defs: Array[EnemyDef] = []
		for named: StringName in record.get("foes", [] as Array[StringName]):
			var def := Registry.get_resource(&"EnemyDef", named) as EnemyDef
			if def == null:
				push_error("World: map '%s' places enemy '%s', which no file in data/enemies describes"
					% [GameState.current_map, named])
				continue
			defs.append(def)
		if defs.is_empty():
			continue
		open_battle_with(defs, seen_key)
		return


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
		out.append(Interactor.Target.new(npc_id, body.global_position, _config.body_size_px(), record))

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
			out.append(Interactor.Target.new(record["id"], at, _config.body_size_px(), record))
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
			GameContext.OP_SHOP:
				# DEFERRED, and this is the whole reason: _on_dialog_closed applies effects and
				# THEN pops the dialog overlay, so a counter opened here would be the thing
				# that pop closed - the shop would flash and vanish, leaving the conversation
				# up. Deferring lets the close finish first; the _commit_new_game precedent in
				# this file defers a rebuild for the same reason. No input is processed in
				# between, so there is no frame the player can act on.
				#
				# The narrow fix on purpose. Applying effects AFTER the close would also work
				# and would change the order for every dialog effect there is - a warp, a
				# chained conversation - which is a far wider change than the bug.
				open_shop.call_deferred(StringName(str(effect.get("shop", ""))))
				did = true
			GameContext.OP_SPEND_GOLD:
				# The runner already refused a price the purse could not meet, so arriving
				# here and failing means the two disagreed - a bug, said out loud, rather
				# than a silent no-op. The shop's buy handler is the same shape for the same
				# reason.
				if GameState.spend_gold(int(effect.get("amount", 0))):
					did = true
				else:
					push_error("World: spent %d the player does not have" % effect.get("amount", 0))
			GameContext.OP_REST:
				did = _rest() or did
			GameContext.OP_SAVE:
				# DEFERRED, the OP_SHOP rule and for its reason exactly: _on_dialog_closed
				# applies this list and THEN pops the dialog overlay, so a screen opened here
				# is the one that pop closes - it would flash and vanish, leaving the
				# conversation up and the save unwritten.
				open_save.call_deferred()
				did = true
			GameContext.OP_GOLD:
				# give_gold refuses a non-positive amount, so a malformed effect changes
				# nothing rather than quietly subtracting.
				if GameState.give_gold(int(effect.get("amount", 0))):
					did = true
			GameContext.OP_PARTY:
				# One effect carrying everybody, routed by member id: the empty id is the
				# leader, who is four fields on GameState, and everyone else is a record in a
				# map. Applied as a group so a party can never be written half-way - the
				# leader's new level saved and a companion's fall not is a state no rule in the
				# game produces and every rule downstream would then have to tolerate.
				for who: Variant in effect.get("members", []):
					var record: Dictionary = who
					var member := StringName(str(record.get("id", "")))
					if String(member).is_empty():
						GameState.set_party(int(record.get("hp", 0)), int(record.get("xp", 0)),
							int(record.get("level", 1)), int(record.get("mp", 0)))
					else:
						GameState.set_companion(member, int(record.get("hp", 0)),
							int(record.get("xp", 0)), int(record.get("level", 1)),
							int(record.get("mp", 0)))
					did = true
			GameContext.OP_WARP:
				did = enter_map(StringName(str(effect.get("map", ""))),
					StringName(str(effect.get("spawn", "start")))) or did
			_:
				push_error("World: unknown effect '%s' - nothing carried it out" % op)
	# A flag this list set may have been somebody joining, so anyone the roster now says is
	# along is made real here. Membership is derived, but a member's NUMBERS are not - and
	# filling them at the sink is what makes "they joined" and "they have health" the same
	# moment. Left to the next fight instead, a party page would show a companion at nought
	# health who is not hurt, merely unasked-for.
	# `joined` rather than `member`: three other loops in this file iterate the active party,
	# and four byte-identical lines make any mutant aimed at one of them report a verdict about
	# whichever sed reached first.
	for joined in _active_party():
		_ensure_member(joined)
	return did


func _open_dialog(dialog_id: StringName) -> bool:
	var runner := DialogRunner.load_from("res://data/dialog/%s.json" % dialog_id, GameState.flags,
		GameState.inventory.to_dict(), GameState.gold)
	if not runner.ok:
		push_error("World: %s" % runner.error)
		return false
	for p in runner.problems():
		push_error("World: " + p)

	_player.halt()
	if not _dialog.open(runner, _source):
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
	_pause.sound_wanted.connect(_on_sound_wanted)
	_pause.sound_changed.connect(_on_sound_changed)
	_pause.resumed.connect(_close_pause)
	_pause.save_requested.connect(_on_save_requested)
	_pause.load_requested.connect(_on_load_requested)
	_pause.equip_requested.connect(_on_equip_requested)
	_pause.unequip_requested.connect(_on_unequip_requested)
	_pause.member_selected.connect(_on_member_selected)
	_mount_ui(_pause)
	_pause_member = &""
	_pause.setup(PauseMenu.of(_slot_summaries(), _item_rows(), Settings.sound_name(),
		_gold_label(), _gear_rows(), _stats_label(), _status_lines(), _member_rows(),
		_saves_from_the_menu()), _style, _ui_size(), _source)
	Router.open_overlay(Router.State.PAUSED)
	return true


## Whether the pause menu offers a Save row, which is the running game's save_policy read once,
## here, and handed to the menu as an answer.
##
## The world resolves it for the reason it words the status lines: knowing what "at_point"
## means is a config question, and PauseMenu may not ask one. A game with no config at all
## saves from the menu - the default everywhere, and the shape every session recorded before
## this field existed was playing.
func _saves_from_the_menu() -> bool:
	return _config == null or _config.save_policy != GameConfig.SAVE_AT_POINT


## What is in each of this game's slots, for drawing. peek() rather than load_slot(): merely
## looking at the menu must not park files or announce loads nobody asked for.
func _slot_summaries() -> Array[SlotSummary]:
	return _slot_summaries_for(_game)


## The same, for a game that is not running yet. The title draws a slot list before start_game
## has ever been called, so it cannot read _game or _config - it reads the manifest it is
## offering, which is the only thing that exists at that point.
func _slot_summaries_for(manifest: GameManifest) -> Array[SlotSummary]:
	var out: Array[SlotSummary] = []
	if manifest == null or manifest.config == null:
		return out
	for slot in manifest.config.save_slots:
		out.append(SaveManager.peek(manifest.id, slot))
	return out


## The style a game's FIRST map is drawn in. The title needs colours before a map has been
## entered, and this is where they come from: a game's look is its starting map's look, which
## is the same answer enter_map would reach a moment later.
func _style_for(manifest: GameManifest) -> SpriteStyle:
	if manifest == null:
		return null
	var data := MapData.load_from(MapData.path_of(manifest.start_map))
	if not data.ok:
		return null
	return load("res://data/styles/%s.tres" % data.style_id) as SpriteStyle


## What the player is carrying, resolved into rows a menu can draw. The Registry lookup lives
## here because PauseMenu may not touch an autoload - and an item with no data file still gets
## a row, named by its id: a bag that silently hides something is worse than one that shows a
## name nobody wrote.
## The purse, as the text a menu draws. Resolved here rather than in PauseMenu for the same
## reason the item rows are: reading it means asking an autoload, and a pure class may not.
func _gold_label() -> String:
	return "Gold: %d" % GameState.gold


func _item_rows() -> Array:
	var out: Array = []
	for item_id in GameState.inventory.ids():
		var def := Registry.get_resource(&"ItemDef", item_id) as ItemDef
		var item_name := def.name if def != null else String(item_id)
		var description := def.description if def != null else ""
		var slot := def.slot if def != null else &""
		out.append(PauseMenu.ItemRow.of(item_id, item_name, GameState.item_count(item_id),
			description, slot, GameState.is_equipped(item_id), _candidate_effect(def)))
	return out


## Starts a fight against a resolved FORMATION. Public and taking defs rather than a map record,
## so a test can stage any fight it likes without needing a map that places one - the same
## reason try_interact() and open_pause() are public.
##
## An Array even for one foe, for the reason the party is a list even at one: there is a single
## code path through a fight, and the fights this template shipped for fifteen milestones are
## simply formations of one.
##
## `seen_key` is what a victory will mark, passed in rather than rebuilt here because the
## caller already knows which record this came from - and it stays ONE key however many foes
## stood on it, because the record is the encounter.
func open_battle_with(defs: Array, seen_key: String) -> bool:
	if _battle != null or _shop != null or _game_over != null or _game == null or defs.is_empty():
		return false
	if _game.combat == null:
		# A map placed an enemy in a game that has no combat definition. Said out loud: the
		# alternative is a fight that silently never opens, which reads as a broken trigger.
		push_error("World: game '%s' has no combat, but something tried to start a fight" % _game.id)
		return false
	for entry: EnemyDef in defs:
		if entry == null:
			push_error("World: a formation for '%s' carries nothing to fight" % seen_key)
			return false
		var faults := entry.problems()
		if not faults.is_empty():
			push_error("World: enemy '%s' is not fit to fight: %s" % [entry.id, ", ".join(faults)])
			return false

	_ensure_party()
	_player.halt()
	_battle = BattleScreen.new()
	# Constructed and connected in one function, the open_pause rule: a view built in one place
	# and wired in another is a view that eventually gets built and not wired.
	_battle.sound_wanted.connect(_on_sound_wanted)
	_battle.finished.connect(_on_battle_finished)
	_mount_ui(_battle)
	_battle.setup(BattleLogic.of(_game.combat, defs, _battle_members(), _battle_items(),
		seen_key, _battle_seed(seen_key)),
		_style, _ui_size(), _source)
	# A fight takes the room's music over. A game naming no battle theme touches nothing at all,
	# which is not merely a legal shape but is exactly the behaviour every fight had before this
	# existed - so the field being empty is the old game, unchanged.
	var scored := _encounter_music(defs)
	if not String(scored).is_empty():
		AudioBus.play_music(scored)
	Router.open_overlay(Router.State.BATTLE)
	EventBus.battle_changed.emit(
		{"enemies": _battle.logic().foe_ids(), "open": true, "outcome": &""})
	return true


## What THIS fight sounds like: the first foe that names a track, or the game's own battle
## theme, or nothing.
##
## Scanned in formation order rather than taken from the leader, because a formation with a boss
## anywhere in it is a boss fight - and reading only `defs[0]` would make the Keeper's theme
## depend on where in the record his escort was written down. Empty from every foe falls through
## to the manifest, which is every fight this template has ever opened.
func _encounter_music(defs: Array) -> StringName:
	for entry: EnemyDef in defs:
		if entry != null and not String(entry.music).is_empty():
			return entry.music
	return _game.battle_music


## A night, over the world. Deferred by its caller for the same reason a counter is: the
## dialog close pops an overlay, and a screen opened before that pop is the thing it closes.
func open_rest() -> bool:
	if _night != null or _game == null:
		return false
	_player.halt()
	_night = RestScreen.new()
	_night.sound_wanted.connect(_on_sound_wanted)
	_night.finished.connect(_close_rest)
	_mount_ui(_night)
	_night.setup(_style, _ui_size(), _config.rest_fade_frames,
		_config.rest_hold_frames, "The night passes.")
	Router.open_overlay(Router.State.RESTING)
	return true


func _close_rest() -> void:
	if _night == null:
		return
	_night.queue_free()
	_night = null
	Router.close_overlay()


## A save point, over the world. Deferred by its caller the way a counter and a night are: the
## dialog close pops an overlay, and a screen opened before that pop is the one it closes.
##
## Public for the reason open_shop() and open_pause() are - a game's hook may want a save point
## without a conversation in front of it, and a test must be able to stage one without a map
## that places one.
##
## It does NOT consult save_policy. That field says where the pause menu offers a Save row; a
## save point is the other way in and is legal under both, so a game that ships one in a
## save-anywhere world gets the redundancy it asked for rather than a screen that silently
## never opens.
func open_save() -> bool:
	if _saving != null or _battle != null or _game_over != null or _shop != null or _game == null:
		return false
	_player.halt()
	_saving = SaveScreen.new()
	# Constructed and connected in one function, the open_battle_with rule.
	_saving.sound_wanted.connect(_on_sound_wanted)
	_saving.save_requested.connect(_on_save_point_write)
	_saving.left.connect(_close_save)
	_mount_ui(_saving)
	_saving.setup(SaveMenu.of(_slot_summaries()), _style, _ui_size())
	Router.open_overlay(Router.State.SAVING)
	return true


## The save point wrote a slot. The same one writer the pause menu's Save row goes through, so
## there is one answer to "what does saving actually do" no matter which door the player used.
func _on_save_point_write(slot: int) -> void:
	if _saving == null:
		return
	SaveManager.save(slot, GameState.to_save())
	# The screen stays open and is told what the slots now hold, so the row the player is
	# looking at shows what they just wrote - the pause menu's rule for the same press.
	_saving.refresh(_slot_summaries())


func _close_save() -> void:
	if _saving == null:
		return
	_saving.queue_free()
	_saving = null
	Router.close_overlay()


## Opens a counter. Public for the same reason open_pause() is: a game's hook may want one
## without a conversation in front of it.
func open_shop(shop_id: StringName) -> bool:
	if _shop != null or _battle != null or _game_over != null or _game == null:
		return false
	var def := Registry.get_resource(&"ShopDef", shop_id) as ShopDef
	if def == null:
		# Said out loud: the alternative is a counter that silently never opens, which reads
		# as a broken conversation rather than as a misspelt id.
		push_error("World: nothing describes shop '%s'" % shop_id)
		return false
	var faults := def.problems()
	if not faults.is_empty():
		push_error("World: shop '%s' is not fit to open: %s" % [shop_id, ", ".join(faults)])
		return false

	_player.halt()
	_shop = ShopScreen.new()
	# Constructed and connected in one function, the open_battle_with rule.
	_shop.sound_wanted.connect(_on_sound_wanted)
	_shop.bought.connect(_on_shop_bought)
	_shop.sold.connect(_on_shop_sold)
	_shop.left.connect(_close_shop)
	_shop.stock = def
	_mount_ui(_shop)
	_shop.setup(ShopMenu.of(_stock_rows(def), _sellable_rows(), GameState.gold,
		def.greeting, def.thanks, def.poor_line), _style, _ui_size())
	Router.open_overlay(Router.State.SHOP)
	return true


## What the keeper offers, resolved into rows. The Registry lookup lives here because ShopMenu
## may not touch an autoload - the _battle_items and _item_rows precedent.
##
## An unpriced or unknown item is DROPPED rather than drawn at zero: a free row is a row that
## empties the shop, and the content gate has already refused to let one ship.
func _stock_rows(def: ShopDef) -> Array:
	var out: Array = []
	for item_id in def.stock:
		var item := Registry.get_resource(&"ItemDef", item_id) as ItemDef
		if item == null or not ShopMenu.tradable(item.price):
			continue
		out.append(ShopMenu.ShopRow.of(item.id, item.name, item.price,
			GameState.item_count(item.id), item.description))
	return out


## What the player may sell: what they are carrying that CARRIES A PRICE. A quest item has
## none, so it never appears - which is what stops a key being sold and a door being locked
## for the rest of the run.
func _sellable_rows() -> Array:
	var out: Array = []
	for carried_id in GameState.inventory.ids():
		var item := Registry.get_resource(&"ItemDef", carried_id) as ItemDef
		if item == null or not ShopMenu.tradable(item.price):
			continue
		# What is WORN is not on the counter. Selling the sword off your own back is the
		# classic shop bug, and the refusal belongs here rather than in ShopMenu: the counter
		# has no business knowing what equipment is, and the world already knows.
		var spare := GameState.item_count(item.id)
		if GameState.is_equipped(item.id):
			spare -= 1
		if spare <= 0:
			continue
		out.append(ShopMenu.ShopRow.of(item.id, item.name, ShopMenu.sell_price(item.price),
			spare, item.description))
	return out


## The world is the only thing that moves money or items. The screen reported a deal; this
## decides whether it happens, and tells the counter what it looks like afterwards.
func _on_shop_bought(item_id: StringName, count: int, total: int) -> void:
	if _shop == null or count <= 0:
		return
	# The menu already refused what could not be afforded. This is the invariant behind that
	# guard rather than a second copy of it: if an impossible deal ever arrives, it is a bug
	# in the menu and it says so instead of quietly overdrawing the player.
	if not GameState.spend_gold(total):
		push_error("World: a shop sold %d of '%s' for %d the player did not have"
			% [count, item_id, total])
		return
	GameState.give_item(item_id, count)
	_refresh_shop()


func _on_shop_sold(item_id: StringName, count: int, total: int) -> void:
	if _shop == null or count <= 0:
		return
	if not GameState.take_item(item_id, count):
		push_error("World: a shop bought %d of '%s' the player is not carrying" % [count, item_id])
		return
	GameState.give_gold(total)
	_refresh_shop()


func _refresh_shop() -> void:
	if _shop == null or _shop.stock == null:
		return
	_shop.refresh(_stock_rows(_shop.stock), _sellable_rows(), GameState.gold)


func _close_shop() -> void:
	if _shop == null:
		return
	_shop.queue_free()
	_shop = null
	Router.close_overlay()


## Everything the paused screen draws, in one call. Four places refresh it - a save, a sound
## step, a refused load, and any change to what is worn - and four copies of the same six
## arguments is four places to forget the one that was just added.
func _refresh_pause() -> void:
	_pause.refresh(_slot_summaries(), _item_rows(), Settings.sound_name(), _gold_label(),
		_gear_rows(_pause_member), _stats_label(_pause_member),
		_status_lines(_pause_member), _member_rows(), _saves_from_the_menu())


## Who the paused screen's Equipment and Status pages are currently about. Empty is the leader.
## Held by the WORLD rather than read back off the menu, because it is the world that has to
## word the pages and the menu is the thing being told.
func _on_member_selected(member: StringName) -> void:
	_pause_member = member
	_refresh_pause()


## The party as the menu needs it: who, and what they are called. Their numbers are not in here
## - those are the world's words, handed over one member at a time as the selection changes.
##
## A game with no party gets an EMPTY list rather than a list of one, so the menu's "is there a
## member step" question answers no without having to count to two.
func _member_rows() -> Array:
	var out: Array = []
	if _game == null or _game.party.is_empty():
		return out
	# Each row carries what a LIST needs and what a PARTY PANEL needs: the menu reads `id` and
	# `name`, and the screen draws the rest. Assembled here for `_status_lines`'s reason - a
	# level is a Registry question and a pure menu may not ask one.
	out.append(_member_row(&"", "You", _game.player_character, GameState.player_level,
		GameState.player_hp, GameState.player_mp, _game.combat))
	for member in _active_party():
		_ensure_member(member)
		var numbers := GameState.companion(member.id)
		out.append(_member_row(member.id, member.name, member.character,
			_member_level(member.id), int(numbers.get("hp", 0)), int(numbers.get("mp", 0)),
			_member_curve(member.id)))
	# One name is not a party: with nobody recruited yet the leader stands alone, and a member
	# step in front of a page with one answer is the cursor-with-one-row problem again.
	return [] if out.size() < 2 else out


## One member, as both a row in a list and a block in a party panel. The maxima come from that
## member's own curve rather than being stored, which is the rule everywhere else: a stat that is
## DERIVED from level has one source, and a copy in a dictionary is a second one to drift.
func _member_row(id: StringName, name: String, character: StringName, level: int,
		hp: int, mp: int, curve: CombatDef) -> Dictionary:
	return {
		"id": String(id), "name": name, "character": String(character), "level": level,
		"hp": hp, "max_hp": 0 if curve == null else curve.max_hp(level),
		"mp": mp, "max_mp": 0 if curve == null else curve.max_mp(level),
	}


## One row per slot the template knows about, each naming what is in it. Built HERE for the
## reason the bag's rows are: asking what the thing worn in a slot is called means asking the
## Registry, and PauseMenu may not.
## The curve and the level of whoever a page is about. An empty member is the leader, whose
## numbers are the four fields on GameState; a companion carries their own of both. One
## function, so the gear rows, the stats line and the status page cannot end up describing
## different people on the same screen.
func _member_curve(member: StringName) -> CombatDef:
	if _game == null:
		return null
	if String(member).is_empty():
		return _game.combat
	for def in _active_party():
		if def.id == member:
			return def.combat if def.combat != null else _game.combat
	return _game.combat


func _member_level(member: StringName) -> int:
	if String(member).is_empty():
		return GameState.player_level
	return maxi(int(GameState.companion(member).get("level", 1)), 1)


func _gear_rows(member: StringName = &"") -> Array:
	var out: Array = []
	for slot in ItemDef.SLOTS:
		var worn := GameState.equipped(slot, member)
		var worn_name := ""
		if not String(worn).is_empty():
			var def := Registry.get_resource(&"ItemDef", worn) as ItemDef
			# An item with no data file still names itself by its id, the _item_rows rule: a
			# blank row would read as an empty slot, which is a different fact entirely.
			worn_name = def.name if def != null and not def.name.is_empty() else String(worn)
		out.append(PauseMenu.GearRow.of(slot, String(slot).capitalize(), worn_name,
			_takeoff_effect(slot, member)))
	return out


## Everything the status page says, one line per row, worded HERE for the reason every other
## readout is: naming a level or a stat means knowing what this game calls one, and whether it
## has one at all. A game with no CombatDef gets the gear lines and nothing else - inventing
## an HP row for a game with no fighting in it would be the screen describing a system that
## does not exist.
func _status_lines(member: StringName = &"") -> Array[String]:
	var out: Array[String] = []
	var curve := _member_curve(member)
	if curve != null:
		# One member's numbers, read from wherever that member's numbers live: the leader's are
		# the four fields on GameState, a companion's are their record. Asked through two
		# helpers so this page and the equipment page cannot describe different people.
		var level := _member_level(member)
		var hp := GameState.player_hp
		var mp := GameState.player_mp
		var xp := GameState.player_xp
		if not String(member).is_empty():
			var numbers := GameState.companion(member)
			hp = int(numbers.get("hp", 0))
			mp = int(numbers.get("mp", 0))
			xp = int(numbers.get("xp", 0))
		out.append("Level %d" % level)
		out.append("HP %d/%d" % [hp, curve.max_hp(level)])
		# Only for a member who HAS magic. A member with no spells would otherwise carry a line
		# reading "MP 0/0" forever, which is a system the player is told about and can never find.
		if curve.max_mp(level) > 0:
			out.append("MP %d/%d" % [mp, curve.max_mp(level)])
		# The line a player actually opens this page for: "am I strong enough" as a number.
		# At the top of the curve there is no next level, and saying so is the honest answer -
		# a game that keeps promising one is a game whose numbers stopped meaning anything.
		var next_at := curve.xp_for_next(level)
		if next_at < 0:
			out.append("XP %d  (fully grown)" % xp)
		else:
			out.append("XP %d  (next in %d)" % [xp, maxi(next_at - xp, 0)])
		out.append("Atk %d+%d   Def %d+%d" % [
			curve.attack_at(level), _equip_mod(&"attack", member),
			curve.defense_at(level), _equip_mod(&"defense", member)])
	for row: PauseMenu.GearRow in _gear_rows(member):
		out.append(PauseMenu.gear_label(row))
	return out


## What the player's numbers are, gear counted separately so the contribution is legible.
## Empty for a game with no fighting in it - naming an attack stat a game does not have would
## be the screen inventing a system.
func _stats_label(member: StringName = &"") -> String:
	# `grown` rather than `level`, and `growth` rather than `curve`: the equivalent lines in
	# _status_lines below would otherwise be byte-identical to these, and a mutant aimed at
	# either would edit whichever function sed reached first and report a verdict about the
	# other one. Two functions that legitimately say the same thing have to SAY it differently.
	var growth := _member_curve(member)
	if growth == null:
		return ""
	var grown := _member_level(member)
	return "Atk %d+%d  Def %d+%d" % [
		growth.attack_at(grown), _equip_mod(&"attack", member),
		growth.defense_at(grown), _equip_mod(&"defense", member)]


## What wearing this INSTEAD of what is in its slot would do, for the line under the candidate
## list. Worded HERE because naming a stat is a Registry-shaped question and PauseMenu may not
## ask one - and shown BEFORE the press, which is the compare an equip screen exists for.
##
## The delta is against what the slot already holds rather than against nothing, so the thing
## already worn reads "no change" instead of promising its own stats a second time.
func _candidate_effect(def: ItemDef) -> String:
	if def == null or String(def.slot).is_empty():
		return ""
	var attack_delta := def.attack
	var defense_delta := def.defense
	var current := Registry.get_resource(&"ItemDef", GameState.equipped(def.slot)) as ItemDef
	if current != null:
		attack_delta -= current.attack
		defense_delta -= current.defense
	return "Wear: %s  (%s)" % [_delta_words(attack_delta, defense_delta), _totals_words()]


## What taking off whatever is in this slot would do. Empty when the slot is bare, which is
## also how the page knows a take-off there has nothing to take.
func _takeoff_effect(slot: StringName, member: StringName = &"") -> String:
	var worn := Registry.get_resource(&"ItemDef", GameState.equipped(slot, member)) as ItemDef
	if worn == null:
		return ""
	return "Take off: %s  (%s)" % [_delta_words(-worn.attack, -worn.defense), _totals_words()]


## A change to the two stats, in words. Shared by both previews so a wear and a take-off
## cannot end up phrased differently for the same pair of numbers.
func _delta_words(attack_delta: int, defense_delta: int) -> String:
	var parts: Array[String] = []
	if attack_delta != 0:
		parts.append("Atk %+d" % attack_delta)
	if defense_delta != 0:
		parts.append("Def %+d" % defense_delta)
	return ", ".join(parts) if not parts.is_empty() else "no change"


## The totals ALREADY worn, so a delta is read against something rather than in a vacuum.
func _totals_words() -> String:
	return "now Atk %+d Def %+d" % [_equip_mod(&"attack"), _equip_mod(&"defense")]


## What the worn gear adds to one stat. Resolved HERE because it means asking the Registry
## what an item is, and BattleLogic may not - the _battle_items and _item_rows precedent.
##
## An id the bag no longer holds contributes nothing rather than erroring: GameState clears
## the marker when the last copy leaves, so this is belt-and-braces against a save edited by
## hand, which SaveData.problems() reports separately.
func _equip_mod(stat: StringName, member: StringName = &"") -> int:
	var total := 0
	var worn_map: Dictionary = GameState.equipment if String(member).is_empty() \
		else GameState.companion_equipment.get(member, {})
	for slot: Variant in worn_map.keys():
		var worn := StringName(str(worn_map[slot]))
		if not GameState.has_item(worn):
			continue
		var item := Registry.get_resource(&"ItemDef", worn) as ItemDef
		if item == null:
			continue
		total += item.attack if stat == &"attack" else item.defense
	return total


## What the player could drink mid-fight, resolved into rows. The Registry lookup lives here
## because BattleLogic may not touch an autoload - and only things that HEAL are offered: a
## gate key in a battle menu is a row that can only disappoint.
## The Registry-and-inventory half of building a battle bag. WHICH items belong in one - only
## what heals - lives on `BattleLogic.ItemRow.bag`, because the balance gate needs the same
## answer and two implementations of "is this safe to spend mid-fight" would drift. The one that
## drifted would put a quest item on the menu, and using it destroys it.
func _battle_items() -> Array:
	var defs: Array = []
	var counts := {}
	# `carried` rather than `item_id`, which _item_rows uses: the two loops would otherwise be
	# character-identical, and a find-and-replace aimed at one of them - a mutant, a codemod,
	# a rename - silently edits both and reports a verdict about the wrong function.
	for carried in GameState.inventory.ids():
		defs.append(Registry.get_resource(&"ItemDef", carried) as ItemDef)
		counts[carried] = GameState.item_count(carried)
	return BattleLogic.ItemRow.bag(defs, counts)


## What the player could cast mid-fight, resolved into rows - and this is where KNOWING a
## spell is decided, because it is derived rather than stored: everything the game ships whose
## learn_level the player has reached. There is no list to consult and none to keep in step
## with the level, which is the whole reason the design is shaped this way.
##
## Sorted by the level it arrives at, then by name, so the page reads as the order a player met
## them in. Registry.ids_of already sorts, so the result does not depend on the filesystem.
func _battle_spells() -> Array:
	return _spells_up_to(GameState.player_level, [], true)


## What one MEMBER could cast: the same level derivation, narrowed to the spells their own
## definition names. An empty list here means NONE - Dragon Quest II's hero exactly - which is
## the opposite of what an empty list means for the leader, and is why this is a second
## function rather than a second meaning for one parameter.
func _member_spells(level: int, only: Array[StringName]) -> Array:
	return _spells_up_to(level, only, false)


## The Registry half of building a spell page. The FILTERING, ordering and conversion live on
## `BattleLogic.SpellRow.page`, because the balance gate needs the same answer and two
## implementations of "which spells has this level reached" would drift - the gate would then be
## balancing shipped fights against a spell list no player is ever handed.
##
## What stays here is the part that needs an autoload: turning the registered ids into defs.
func _spells_up_to(level: int, only: Array[StringName], everything: bool) -> Array:
	if _game == null or _game.combat == null:
		return []
	var defs: Array = []
	for spell_id in Registry.ids_of(&"SpellDef"):
		defs.append(Registry.get_resource(&"SpellDef", spell_id) as SpellDef)
	return BattleLogic.SpellRow.page(defs, level, only, everything)


## Everyone who fights on the player's side, fully resolved.
##
## THE LEADER IS SYNTHESIZED rather than declared: their art and curve are the manifest's own,
## their name is the word every message used before there was anyone else, and they know
## everything the game ships that their level has reached. So a game with no party still hands
## the fight a list, and there is one code path through a battle rather than a solo one and a
## party one - of which the solo one would be the tested one.
func _battle_members() -> Array:
	var out: Array = []
	if _game == null or _game.combat == null:
		return out
	out.append(BattleLogic.Fighter.of(&"", "You", _game.player_character, _game.combat,
		GameState.player_hp, GameState.player_xp, GameState.player_level, GameState.player_mp,
		_equip_mod(&"attack"), _equip_mod(&"defense"), _battle_spells()))
	for member in _active_party():
		_ensure_member(member)
		var numbers := GameState.companion(member.id)
		var curve: CombatDef = member.combat if member.combat != null else _game.combat
		var level := int(numbers.get("level", member.join_level))
		out.append(BattleLogic.Fighter.of(member.id, member.name, member.character, curve,
			int(numbers.get("hp", 0)), int(numbers.get("xp", 0)), level,
			int(numbers.get("mp", 0)),
			_equip_mod(&"attack", member.id), _equip_mod(&"defense", member.id),
			_member_spells(level, member.spells)))
	return out


## Which of the game's roster is actually along, right now. Derived from flags every time it is
## asked rather than recorded, the way knowing a spell is derived from level - so recruiting is
## the set_flag a dialog choice already carries, and there is no membership to save or migrate.
func _active_party() -> Array[PartyMemberDef]:
	var out: Array[PartyMemberDef] = []
	if _game == null:
		return out
	for member: PartyMemberDef in _game.party:
		if member == null:
			continue
		if String(member.joins_on_flag).is_empty() or GameState.has_flag(member.joins_on_flag):
			out.append(member)
	return out


## THE one place a companion who has just joined becomes real, and the _ensure_party shape
## exactly: full health and magic on their own curve, at the level their game says they arrive
## at, with the xp that level actually costs so their next fight advances them honestly rather
## than levelling them a second time.
func _ensure_member(member: PartyMemberDef) -> void:
	if _game == null or _game.combat == null or GameState.has_companion(member.id):
		return
	var curve: CombatDef = member.combat if member.combat != null else _game.combat
	var level := maxi(member.join_level, 1)
	var earned := 0
	for step in level - 1:
		var at := curve.xp_for_next(step + 1)
		if at < 0:
			break
		earned = at
	GameState.set_companion(member.id, curve.max_hp(level), earned, level, curve.max_mp(level))


## A fight's seed, derived only from state that is already persisted.
##
## Never a clock: the whole point of a seeded fight is that a QA script fighting it gets the
## same enemy moves on every machine and every run. Deriving it from the player's own progress
## also means walking back into a fight you fled replays it exactly, which is a promise the
## save file can keep.
func _battle_seed(seen_key: String) -> int:
	return SeededRng.hash_seed(hash("%s/%s" % [GameState.game, seen_key]),
		"%d:%d" % [GameState.player_xp, GameState.player_level])


## The one place a fight's result reaches the world.
##
## The screen is closed FIRST: this arrives from inside its own _physics_process, and a defeat
## goes on to build another screen, so leaving the battle up while that happens would stack two
## full-screen views and free one of them mid-dispatch.
func _on_battle_finished(outcome: int, effects: Array) -> void:
	# Ids, and the same ids the open announced. This used to be the display name on the way out
	# and the def's id on the way in - one field answering in two vocabularies, which nothing
	# noticed because nothing listens. Read before the screen goes, because it is what holds them.
	var fought: Array[StringName] = []
	if _battle != null and _battle.logic() != null:
		fought = _battle.logic().foe_ids()
	_close_battle()
	match outcome:
		BattleLogic.Outcome.DEFEAT:
			# Nothing is applied. A lost fight earns no xp, marks nothing beaten and consumes
			# nothing - the run is over, and the save the player goes back to is the truth.
			# The game over's own theme, or silence when it names none.
			#
			# This used to be `stop_music()` unconditionally, justified in a comment that said
			# "every game this borrows from cuts the music at a game over". That is false:
			# Final Fantasy I ships "Dead Music" in 1987 and each Final Fantasy since has had
			# its own game-over scene. The references CHANGE what is playing at a death, they do
			# not fall silent - so silence is a divergence and belongs behind an empty field
			# rather than in the code as a convention.
			#
			# play_or_silence, not two branches: "a game states its game-over music or states
			# silence" is the same sentence a map's music is written as, and it is the one
			# function that already says it. Every way OUT of a game over states its own music
			# again, so nothing here has to be given back.
			AudioBus.play_or_silence(_game.game_over_music)
			EventBus.battle_changed.emit({"enemies": fought, "open": false, "outcome": &"defeat"})
			open_game_over()
		_:
			_apply_effects(effects)
			_despawn_beaten_enemies()
			_leave_battle_music(outcome == BattleLogic.Outcome.VICTORY)
			EventBus.battle_changed.emit({"enemies": fought, "open": false,
				"outcome": &"fled" if outcome == BattleLogic.Outcome.FLED else &"victory"})


## Giving the room back after a fight that was survived.
##
## A win with a fanfare CHAINS: the jingle once, then the map's own statement, which may be
## silence. Everything else states that statement at once - the enter_map shape - and a fled
## fight gets no jingle because nothing was won.
##
## Deliberately NOT guarded on having displaced anything. The obvious guard - "only restore if
## this game named a battle theme" - is a branch no test can tell from its absence: when nothing
## was displaced, the map's music is already what is playing, and the bus refuses to restart a
## track it is already on. A branch nothing can distinguish is decoration, and this repo removes
## those rather than keeping them with a mutant that can never bite. The control in
## test_world_music proves the no-op: a game naming neither field fights and its music never
## moves.
func _leave_battle_music(won: bool) -> void:
	if _game == null:
		return
	var here := &"" if map_data() == null else map_data().music_id
	if won and not String(_game.victory_music).is_empty():
		AudioBus.play_music_then(_game.victory_music, here)
	else:
		AudioBus.play_or_silence(here)


func _close_battle() -> void:
	if _battle == null:
		return
	# queue_free, not free: reached from inside the screen's own frame callback.
	_battle.queue_free()
	_battle = null
	Router.close_overlay()


## Fills in a player who has never fought, from the game's own curve.
##
## THE one place "no party yet" becomes a real hero, and it lives here because the curve is a
## CombatDef - which GameState may not load and a save file may not reach. Zero hp is the
## signal, so this is safe to call on every entry: a player mid-run is left exactly as they are.
## A full night. Through set_party because that is the one writer, and it takes all three
## numbers because they are one fact - so a rest passes xp and level back unchanged and moves
## only the hp. What "full" means is the running game's own curve, which is why this cannot
## live in a menu or a dialog: a game with no CombatDef has no notion of full, and has nothing
## to heal either, so it says so rather than quietly doing nothing.
func _rest() -> bool:
	if _game == null or _game.combat == null:
		push_error("World: a rest was asked for by a game that has no fighting in it")
		return false
	var level := GameState.player_level
	# Magic comes back with the health, which is the whole reason a night costs money: an inn
	# that refilled one and not the other would leave a caster with nothing to cast and no
	# reason to sleep again.
	GameState.set_party(_game.combat.max_hp(level), GameState.player_xp, level,
		_game.combat.max_mp(level))
	# Everybody who is along, on their own curve - and a member who FELL is exactly what this
	# undoes. Dragon Quest's priest and EarthBound's hospital are both paid town services that
	# put the fallen back up, and this template already charges for the night at the door.
	for member in _active_party():
		_ensure_member(member)
		var numbers := GameState.companion(member.id)
		var curve: CombatDef = member.combat if member.combat != null else _game.combat
		var at := int(numbers.get("level", member.join_level))
		GameState.set_companion(member.id, curve.max_hp(at), int(numbers.get("xp", 0)), at,
			curve.max_mp(at))
	# Deferred, the open_shop precedent exactly: _on_dialog_closed applies these effects and
	# THEN pops the dialog overlay, so a night opened here is what that pop would close.
	open_rest.call_deferred()
	return true


func _ensure_party() -> void:
	if _game == null or _game.combat == null or GameState.player_hp > 0:
		return
	var starting := GameState.player_level
	GameState.set_party(_game.combat.max_hp(starting), GameState.player_xp, starting,
		_game.combat.max_mp(starting))


## Puts up the end of the run. Public for the same reason open_pause() is.
## The screen a run is started from. Public for the same reason open_pause() is, and because
## the game-over screen routes back to it.
##
## Answers false when it cannot be drawn - no game resolved, or no style to draw it in - so
## the caller can fall back to starting rather than showing nothing.
func open_title() -> bool:
	if _title != null or _offered == null:
		return false
	var style := _style_for(_offered)
	if style == null:
		return false
	_teardown_game()
	_style = style
	# The VOICE, which until now was bound only by _build_game - so the title asked for its
	# theme through a bus that had nothing bound and played nothing at all. A title belongs to a
	# game exactly as a map does, and both of the things it needs to present one, the look and
	# the sound, are resolved here.
	AudioBus.use_style(_offered.sound_style)
	# The style is bound before a map has been entered, which is what puts the title on the
	# right letterbox colour AND at the right size: a game drawn at 32px opens its title in a
	# 640x360 window, not in one that resizes under the player the moment they press New game.
	_bind_style(style)
	_title = TitleScreen.new()
	_title.sound_wanted.connect(_on_sound_wanted)
	_title.load_requested.connect(_on_title_load)
	_title.new_game_requested.connect(_on_title_new_game)
	_title.credits_requested.connect(_on_title_credits)
	_mount_ui(_title)
	# _style, never the `style` argument: _bind_style has just laid the player's palette over it,
	# and handing the screen what came IN would draw the one surface a recolour is chosen from in
	# the colours it is being changed away from. Every other screen here already reads _style;
	# this line was the odd one out, and only a photograph of the title found it.
	_title.setup(TitleMenu.of(_slot_summaries_for(_offered)), _style, _ui_size(),
		_offered.title)
	if not String(_offered.title_music).is_empty():
		AudioBus.play_music(_offered.title_music)
	Router.to_title()
	return true


func _close_title() -> void:
	if _title == null:
		return
	_title.queue_free()
	_title = null


## Who drew the art. Opened INLINE, unlike the save point and the counter: those are reached
## through a conversation, whose close pops an overlay and would take a screen opened before it
## with it. Nothing pops anything here - the title is a base state, not an overlay.
func _on_title_credits() -> void:
	open_credits()


## Public for the reason open_save() and open_shop() are: a test must be able to stage this
## without pressing through a menu, and a game's hook may want a route to it of its own.
##
## The credits are read HERE rather than by the screen, because knowing where a style's generated
## art lives is a question about the running game and a view may not ask one. A style that draws
## its own art has no such file, and that is not an error: JsonFile.read answers an empty
## Dictionary and CreditsMenu says so on its notice page, which is a true and complete answer to
## "who drew this".
func open_credits() -> bool:
	if _credits != null or _title == null or _style == null:
		return false
	_credits = CreditsScreen.new()
	# Constructed and connected in one function, the open_battle_with rule.
	_credits.sound_wanted.connect(_on_sound_wanted)
	_credits.left.connect(_close_credits)
	_mount_ui(_credits)
	_credits.setup(CreditsMenu.of(_credits_for(_style)), _style, _ui_size())
	Router.open_overlay(Router.State.CREDITS)
	return true


func _close_credits() -> void:
	if _credits == null:
		return
	_credits.queue_free()
	_credits = null
	Router.close_overlay()


## The composed attribution list the sprite generator writes beside a style's art, or nothing.
## `assets/generated/<style>/credits.json` is a resource and ships in the pack, which is the whole
## reason a screen can read it at all - LICENSE.txt beside it is a .txt and does not.
func _credits_for(style: SpriteStyle) -> Dictionary:
	var file := JsonFile.read("res://assets/generated/%s/credits.json" % style.id)
	return file.data if file.ok else {}


func _on_title_load(slot: int) -> void:
	# Deferred for the reason every load here is: this builds a map, and doing that inside the
	# screen's own input callback frees nodes the tree is still dispatching to.
	_commit_title_load.call_deferred(slot)


func _commit_title_load(slot: int) -> void:
	if _title == null or _offered == null:
		return
	var data := SaveManager.load_slot(_offered.id, slot)
	if data == null:
		# load_slot has parked the bytes and said so. The screen stays up showing what the
		# slots hold now, and answering again, which refresh() re-enables.
		_title.refresh(_slot_summaries_for(_offered))
		return
	var manifest := _offered
	_close_title()
	boot_from_save(manifest, data)


func _on_title_new_game() -> void:
	_commit_new_game_from_title.call_deferred()


func _commit_new_game_from_title() -> void:
	if _title == null or _offered == null:
		return
	var manifest := _offered
	# Closed before start_game, which tears everything down: the screen is a child of this node
	# and _teardown_game would free it out from under the deferred call that is running.
	_close_title()
	start_game(manifest)


func open_game_over() -> bool:
	if _game_over != null or _game == null:
		return false
	_game_over = GameOverScreen.new()
	_game_over.sound_wanted.connect(_on_sound_wanted)
	_game_over.load_requested.connect(_on_game_over_load)
	_game_over.new_game_requested.connect(_on_game_over_new_game)
	_game_over.title_requested.connect(_on_game_over_title)
	_mount_ui(_game_over)
	_game_over.setup(GameOverMenu.of(_slot_summaries()), _style, _ui_size())
	Router.open_overlay(Router.State.GAME_OVER)
	return true


func _close_game_over() -> void:
	if _game_over == null:
		return
	_game_over.queue_free()
	_game_over = null
	Router.close_overlay()


func _on_game_over_load(slot: int) -> void:
	# Deferred for the same reason a pause-menu load is: this rebuilds the map, and doing that
	# inside the screen's input callback frees nodes the tree is still dispatching to.
	_commit_game_over_load.call_deferred(slot)


func _commit_game_over_load(slot: int) -> void:
	if _game_over == null or _game == null:
		return
	var data := SaveManager.load_slot(_game.id, slot)
	if data == null:
		# load_slot has parked the bytes and said so. The screen stays up showing what the
		# slots hold now - one fewer - and answering again, which refresh() re-enables.
		_game_over.refresh(_slot_summaries())
		return
	_close_game_over()
	restore(data)


func _on_game_over_title() -> void:
	_commit_title.call_deferred()


func _commit_title() -> void:
	if _game_over == null:
		return
	# Closed before open_title, which tears the game down: the screen is a child of this node
	# and _teardown_game would free it out from under the deferred call that is running. The
	# _commit_new_game shape exactly, with a different destination.
	_close_game_over()
	open_title()


func _on_game_over_new_game() -> void:
	_commit_new_game.call_deferred()


func _commit_new_game() -> void:
	if _game_over == null:
		return
	var manifest := _game
	# Closed before start_game, which tears the whole game down: the screen is a child of this
	# node and _teardown_game would free it out from under the deferred call that is running.
	_close_game_over()
	start_game(manifest)


func _close_pause() -> void:
	if _pause == null:
		return
	# queue_free, not free: this is reached from inside the screen's own input handler, and
	# freeing a node while it is dispatching an event is a crash.
	_pause.queue_free()
	_pause = null
	Router.close_overlay()


## Wear it, or take it off if it is already on. A toggle rather than two verbs because the
## list has one confirm, and a second key for "unequip" is a control nobody would find.
func _on_equip_requested(item_id: StringName) -> void:
	var def := Registry.get_resource(&"ItemDef", item_id) as ItemDef
	if def == null or String(def.slot).is_empty():
		return
	# Equip, never toggle. The candidate page has a row of its own for taking gear off, so a
	# confirm here means one thing - and confirming what is already worn is a no-op rather
	# than the surprise of undressing.
	GameState.equip(def.slot, item_id, _pause_member)
	if _pause != null:
		_refresh_pause()


func _on_unequip_requested(slot: StringName) -> void:
	GameState.unequip(slot, _pause_member)
	if _pause != null:
		_refresh_pause()


func _on_save_requested(slot: int) -> void:
	SaveManager.save(slot, GameState.to_save())
	# The menu stays up and is told what the slots hold NOW, so the row the player is looking
	# at shows what they just wrote. A save whose only feedback is the screen closing is
	# indistinguishable from one that failed.
	if _pause != null:
		_refresh_pause()


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
		_refresh_pause()
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
	# A save written before battles existed - or by a game that had none - restores with no
	# party at all. This is where that becomes a real hero, from the curve of whichever game is
	# actually running, which is a fact neither the file nor GameState can reach.
	_ensure_party()
	if not enter_map(data.map, &"", data.tile):
		return false
	# The state is told where the body actually stands. from_save() converted the file's tiles
	# with whatever tile size was bound BEFORE this load - the map the player was leaving, which
	# at a change of style is a different number - and enter_map has just converted them again
	# with the destination's. This is the one line that makes those two agree, on the frame the
	# load lands rather than on the next physics tick.
	GameState.set_player(_player.global_position, data.facing)
	return true


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


func shop_screen() -> ShopScreen:
	return _shop


## The night, for the flow model's gate. It is the one screen with no other reader, which is
## exactly why the model wants it: a state nothing can look at is a state nothing can check.
func rest_screen() -> RestScreen:
	return _night


func save_screen() -> SaveScreen:
	return _saving


## The credits, for the flow model's gate and the layout audit.
func credits_screen() -> CreditsScreen:
	return _credits


## Whether a game is built behind whatever is on screen. The title is the one state where the
## answer is no, and several guards elsewhere depend on that being true - so it is worth being
## able to ask rather than inferring it from a screen that happens to be null.
func game_is_running() -> bool:
	return _game != null


func battle_screen() -> BattleScreen:
	return _battle


## The title, for tests that read what it drew rather than driving keys at it.
func title_screen() -> TitleScreen:
	return _title


func game_over_screen() -> GameOverScreen:
	return _game_over


func enemy_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _enemies.keys():
		out.append(k)
	out.sort()
	return out


func npc_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _npcs.keys():
		out.append(k)
	out.sort()
	return out
