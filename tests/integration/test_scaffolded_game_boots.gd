extends GdUnitTestSuite
## The template's own claim, run rather than asserted: a game scaffolded out of nothing but
## `GameScaffold.plan` boots into its first room, and the player can walk in it.
##
## This is the proof that used to be a paragraph. M7 built a whole second game to check that
## "art and design are the only things that have to change", M11 deleted it, and since then the
## claim has been history rather than something anything re-runs.
##
## It needs no second manifest on disk and no engine spawn. `world.start_game(manifest)` takes the
## manifest it is handed - the `test_game_switch` seam - so `GameSelect` is never consulted, and
## `MapData.root` is a var, so the scaffolded room is found without a map shipping that nobody
## plays. Both are put back in after_test: they are shared statics, and a suite that left either
## moved would report on the demo somewhere later in the run.

const ROOT := "user://scaffold_boot"

var _world: Node2D
var _planned := {}
## Derived rather than spelled in: the wizard invites scaffolding a game into this repo, and a
## suite that named its own game would go red over somebody else's.
var _id := ""


func before_test() -> void:
	GameState.reset()
	Router.reset()
	_id = GameFixtures.unused_game_id("scaffold_proof")
	_planned = GameScaffold.plan({"id": _id}, GameScaffold.known_from_disk())
	# Every refusal first: a plan that would not have been written is not a plan to boot.
	assert_array(GameScaffold.problems({"id": _id}, GameScaffold.known_from_disk())
		).override_failure_message("the scaffold refuses its own default game").is_empty()
	for path: Variant in _planned.keys():
		# The hooks and the play session are files for a repository, not for a boot: a Script
		# reached through user:// is a different question from whether a game starts.
		if str(path).begins_with("games/") or str(path).begins_with("tests/"):
			continue
		_write("%s/%s" % [ROOT, path], str(_planned[path]))


func after_test() -> void:
	MapData.root = MapData.MAP_DIR
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).override_failure_message("could not write %s" % path).is_not_null()
	file.store_string(text)
	file.close()


## The world, then the redirect, then the game - in that order and never another.
##
## _ready boots the shipped game the moment this node enters the tree, so moving MapData.root
## first sends that boot hunting for quest_village in a directory that does not have it: it fails
## half way through building a map, leaves the pieces behind, and every assertion below still
## passes. The suite's orphan baseline is what would eventually notice, which is a long way from
## the code that caused it.
func _boot() -> GameManifest:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	MapData.root = "%s/data/maps" % ROOT
	var manifest := ResourceLoader.load("%s/data/games/%s.tres" % [ROOT, _id], "",
		ResourceLoader.CACHE_MODE_IGNORE) as GameManifest
	assert_object(manifest).override_failure_message(
		"the scaffolded manifest does not load as a GameManifest at all").is_not_null()
	return manifest


func test_a_game_made_out_of_nothing_passes_the_gate_every_shipped_game_passes() -> void:
	# smoke_boot and test_game_manifest run exactly this over every manifest in data/games. A
	# scaffolded game has to clear the same bar on the day it is made, or the wizard's output is
	# something its author has to repair before it will start.
	_boot()
	var manifest := ResourceLoader.load("%s/data/games/%s.tres" % [ROOT, _id], "",
		ResourceLoader.CACHE_MODE_IGNORE) as GameManifest
	assert_str("\n".join(manifest.problems())).is_equal("")


func test_it_boots_into_its_own_first_room() -> void:
	var manifest := _boot()
	assert_bool(_world.start_game(manifest)).override_failure_message(
		"the world would not start the scaffolded game").is_true()
	assert_int(Router.state()).is_equal(Router.State.WORLD)
	assert_str(String(GameState.game)).is_equal(_id)
	assert_str(String(GameState.current_map)).is_equal("%s_start" % _id)
	assert_object(_world.player()).override_failure_message(
		"the game started with nobody in it").is_not_null()


func test_the_player_it_made_can_actually_walk() -> void:
	# The assertion that separates "a map parsed" from "a game runs". A body only moves if the
	# config bound to the map's tile size, the sprite resolved, and the collision shapes came up -
	# none of which a file check can see.
	var manifest := _boot()
	_world.start_game(manifest)
	var player: ActorBody = _world.player()
	var started: Vector2 = player.global_position
	for i in 30:
		player.apply(Vector2.LEFT)
		await get_tree().physics_frame
	assert_float(player.global_position.x).override_failure_message(
		"the player did not move west at all, so nothing in this room is real").is_less(started.x)


func test_the_greeter_is_standing_where_the_session_expects_to_find_them() -> void:
	# The scaffolded play session walks east until a body stops it. That leg is only geometry if
	# the greeter is actually spawned and actually solid - an npc record that produced no body
	# would leave the session walking into a wall two tiles further on and still passing.
	var manifest := _boot()
	_world.start_game(manifest)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: ActorBody = _world.player()
	var blocked := player.global_position
	for i in 60:
		player.apply(Vector2.RIGHT)
		await get_tree().physics_frame
	var tile: Vector2i = player.tile(GameState.tile_size)
	assert_int(tile.x).override_failure_message(
		"walking east from the spawn was not stopped beside the greeter, it reached %s" % tile
		).is_equal(GameScaffold.NPC_TILE.x - 1)
	assert_float(player.global_position.x).is_greater(blocked.x)
