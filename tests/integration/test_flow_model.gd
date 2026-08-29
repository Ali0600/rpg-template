extends GdUnitTestSuite
## The flow model, checked against the game it describes.
##
## tools/flow_model.json declares every way a player moves between screens: what each action
## does, and the EXACT sequence of flow_changed events it may emit on the way. This drives all
## of it through the real world scene and fails when the recording differs.
##
## The failure it exists to catch is an UNDECLARED INTERMEDIATE STATE - an action that arrives
## where it said it would, having passed through somewhere nobody wrote down. That is precisely
## the shape of the Continue bug this model was built after: title -> world was declared and
## title -> world -> dialog is what happened, because the load went through the start map and
## its entry hooks fired on the way past.
##
## A model nothing checks is a comment that rots, so this suite is the reason that file is
## allowed to be believed.

const MODEL := "res://tools/flow_model.json"
const GAME := "res://data/games/quest.tres"

var _world: Node2D
var _seen: Array[Dictionary] = []
var _recording := false


func before_test() -> void:
	GameState.reset()
	Router.reset()
	EventBus.flow_changed.connect(_record)

func after_test() -> void:
	EventBus.flow_changed.disconnect(_record)
	Input.action_release(&"interact")
	Input.action_release(&"cancel")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()


func _record(info: Dictionary) -> void:
	if _recording:
		_seen.append(info)


## The trace so far, as ["from->to", ...] using the same names Router.state_name() reports and
## the model is written in - so a failure message reads as the model does rather than as a pair
## of enum ordinals nobody can place.
func _trace() -> Array[String]:
	var out: Array[String] = []
	for info in _seen:
		out.append("%s->%s" % [_name_of(int(info["from"])), _name_of(int(info["to"]))])
	return out


func _name_of(value: int) -> String:
	return str(Router.State.find_key(value)).to_lower()


func _declared(edge: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for hop: Variant in edge.get("trace", []) as Array:
		var pair := hop as Array
		out.append("%s->%s" % [str(pair[0]), str(pair[1])])
	return out


func _model() -> Dictionary:
	var file := JsonFile.read(MODEL)
	assert_bool(file.ok).override_failure_message(
		"the flow model could not be read: %s" % file.error).is_true()
	return file.data


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)


func _manifest() -> GameManifest:
	return (load(GAME) as GameManifest).duplicate() as GameManifest


## A game that opens somewhere quiet. The shipped start map greets the player, which is a
## dialog hop every edge would then have to declare - so the model is checked against a map
## with nothing to say, and the greeting has its own suite.
func _quiet_manifest() -> GameManifest:
	var manifest := _manifest()
	manifest.start_map = &"quest_town"
	manifest.start_spawn = &"start"
	return manifest


func _foe(hp := 1, attack := 1) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"flow_foe"
	out.name = "Flow Foe"
	out.character = &"quest_warden"
	out.max_hp = hp
	out.attack = attack
	out.defense = 0
	out.xp = 1
	out.moves = [{"name": "Clout", "power": 0}]
	return out


func _instantiate() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world


## Puts the machine in a state, WITHOUT recording - the arrival is somebody else's edge.
func _arrive_at(state: String, adapter := "") -> void:
	_instantiate()
	if state == "title":
		# _ready resolved the SHIPPED game, whose first map greets the player - which would put
		# a world->dialog hop on every edge out of the title. That greeting is the quest's
		# content, not the template's flow, so the title is pointed at a map with nothing to
		# say and the greeting keeps its own suite.
		_world._offered = _quiet_manifest()
		return
	assert_bool(_world.start_game(_quiet_manifest())).is_true()
	await _steps(1)
	match state:
		"world":
			return
		"dialog":
			_world._apply_effects([{"op": GameContext.OP_DIALOG, "dialog": "elder"}])
		"paused":
			assert_bool(_world.open_pause()).is_true()
		"shop":
			assert_bool(_world.open_shop(&"smith_shop")).is_true()
		"resting":
			assert_bool(_world.open_rest()).is_true()
		"battle":
			# A fight the player cannot win, when the edge under test is the losing one. Chosen
			# here because win and lose leave through the same door and differ only in who is
			# standing in the ring.
			var foe := _foe(999, 99) if adapter == "lose_battle" else _foe()
			assert_bool(_world.open_battle_with(foe, "flow/foe")).is_true()
		"game_over":
			assert_bool(_world.open_game_over()).is_true()
	await _steps(1)


## Runs one declared action from the state it declares. Everything before this is setup and is
## not recorded; recording starts here and stops when the action has settled.
func _drive(adapter: String) -> void:
	_seen.clear()
	_recording = true
	match adapter:
		"boot":
			await _steps(2)
		"new_game":
			_world._commit_new_game_from_title()
			await _steps(2)
		"continue_from_title":
			_world._commit_title_load(0)
			await _steps(2)
		"open_dialog":
			_world._apply_effects([{"op": GameContext.OP_DIALOG, "dialog": "elder"}])
			await _steps(1)
		"close_dialog":
			for i in 12:
				if Router.state_name() != "dialog":
					break
				await _press(&"interact")
		"open_pause_by_key":
			await _press(&"cancel")
		"close_pause":
			_world._close_pause()
			await _steps(1)
		"open_shop":
			_world._apply_effects([{"op": GameContext.OP_SHOP, "shop": "smith_shop"}])
			await _steps(2)
		"close_shop":
			_world._close_shop()
			await _steps(1)
		"open_rest":
			_world._apply_effects([{"op": GameContext.OP_REST}])
			await _steps(2)
		"close_rest":
			for i in 240:
				if Router.state_name() != "resting":
					break
				await get_tree().physics_frame
		"open_battle":
			assert_bool(_world.open_battle_with(_foe(), "flow/foe")).is_true()
			await _steps(1)
		"win_battle", "lose_battle":
			for i in 90:
				if Router.state_name() != "battle":
					break
				await _press(&"interact")
		"game_over_to_title":
			_world._commit_title()
			await _steps(2)
		"game_over_new_game":
			_world._commit_new_game()
			await _steps(2)
		"warp":
			assert_bool(_world.enter_map(&"quest_cave", &"west_gate")).is_true()
			await _steps(1)
		_:
			fail("the model names adapter '%s', which this suite does not implement" % adapter)
	_recording = false


## Everything an arrival must be true of, by name. A vertex naming one of these that does not
## exist fails in _check_invariants rather than passing quietly.
func _invariant_holds(name: String) -> bool:
	match name:
		"title_screen_up":
			var title: TitleScreen = _world.title_screen()
			return title != null
		"no_game_running":
			return not _world.game_is_running()
		"game_running":
			return _world.game_is_running()
		"player_exists":
			var body: ActorBody = _world.player()
			return body != null
		"map_is_named":
			return not String(GameState.current_map).is_empty()
		"player_can_move":
			return Router.player_can_move()
		"player_cannot_move":
			return not Router.player_can_move()
		"no_overlay_up":
			return Router.overlay_depth() == 0
		"dialog_box_open":
			var box: DialogBox = _world.dialog_box()
			return box != null and box.visible
		"pause_screen_up":
			var pause: PauseScreen = _world.pause_screen()
			return pause != null
		"battle_screen_up":
			var battle: BattleScreen = _world.battle_screen()
			return battle != null
		"shop_screen_up":
			var shop: ShopScreen = _world.shop_screen()
			return shop != null
		"rest_screen_up":
			return _world.rest_screen() != null
		"game_over_screen_up":
			var over: GameOverScreen = _world.game_over_screen()
			return over != null
	return false


func _known_invariant(name: String) -> bool:
	return [
		"title_screen_up", "no_game_running", "game_running", "player_exists", "map_is_named",
		"player_can_move", "player_cannot_move", "no_overlay_up", "dialog_box_open",
		"pause_screen_up", "battle_screen_up", "shop_screen_up", "rest_screen_up",
		"game_over_screen_up",
	].has(name)


# --- the gate ------------------------------------------------------------------------------


func test_every_declared_edge_emits_exactly_what_it_says() -> void:
	# The heart of it. For each edge: arrive at its `from` without recording, drive its action
	# WITH recording, and require the trace to match the declaration exactly - not to contain
	# it, not to end at the same place. An extra hop nobody declared is the failure, because
	# an extra hop nobody declared is what shipped a Continue that replayed the game's opening.
	var edges: Array = _model().get("edges", [])
	assert_int(edges.size()).override_failure_message(
		"the model declares no edges, so this gate checked nothing").is_greater(0)
	for entry: Variant in edges:
		var edge: Dictionary = entry
		var action := str(edge.get("action", ""))
		await _arrive_at(str(edge.get("from", "")), str(edge.get("adapter", "")))
		if str(edge.get("adapter", "")) == "continue_from_title":
			await _seed_a_save()
		await _drive(str(edge.get("adapter", "")))
		assert_array(_trace()).override_failure_message(
			"'%s' was declared as %s and actually emitted %s"
			% [action, _declared(edge), _trace()]).is_equal(_declared(edge))
		assert_str(Router.state_name()).override_failure_message(
			"'%s' said it would end in '%s' and ended in '%s'"
			% [action, edge.get("to", ""), Router.state_name()]).is_equal(str(edge.get("to", "")))
		_teardown_world()


func test_every_arrival_leaves_its_state_intact() -> void:
	# The other half: a trace can be right while the world behind it is wrong. Every invariant
	# the destination names is checked on arrival, so "we got to WORLD" also means a player
	# exists, a map is named and nothing is stacked over it.
	var model := _model()
	var states: Dictionary = model.get("states", {})
	for entry: Variant in model.get("edges", []) as Array:
		var edge: Dictionary = entry
		await _arrive_at(str(edge.get("from", "")), str(edge.get("adapter", "")))
		if str(edge.get("adapter", "")) == "continue_from_title":
			await _seed_a_save()
		await _drive(str(edge.get("adapter", "")))
		var arrived := str(edge.get("to", ""))
		var vertex: Dictionary = states.get(arrived, {})
		for raw: Variant in vertex.get("invariants", []) as Array:
			var name := str(raw)
			assert_bool(_known_invariant(name)).override_failure_message(
				"state '%s' names invariant '%s', which this suite does not implement"
				% [arrived, name]).is_true()
			assert_bool(_invariant_holds(name)).override_failure_message(
				"after '%s' the machine is in '%s', where '%s' is supposed to hold and does not"
				% [edge.get("action", ""), arrived, name]).is_true()
		_teardown_world()


func test_the_model_and_the_router_name_the_same_states() -> void:
	# Membership BOTH ways, because "every state I wrote down is real" is silent about a state
	# nobody wrote down - and a new state with no model row is exactly the change this file is
	# meant to make impossible to land quietly.
	var declared: Array[String] = []
	for key: Variant in _model().get("states", {}):
		declared.append(str(key))
	declared.sort()
	var real: Array[String] = []
	for value: Variant in Router.State.values():
		real.append(_name_of(int(value)))
	real.sort()
	assert_array(declared).override_failure_message(
		"the model describes %s and the router has %s" % [declared, real]).is_equal(real)


func test_every_state_can_be_arrived_at_and_left() -> void:
	# A vertex nothing reaches is a state the gate above never enters, and a vertex nothing
	# leaves is a trap. Both are invisible to a per-edge check, which only ever looks at the
	# edges that ARE written down.
	var reached: Array[String] = []
	var left: Array[String] = []
	for entry: Variant in _model().get("edges", []) as Array:
		var edge: Dictionary = entry
		var to := str(edge.get("to", ""))
		var from := str(edge.get("from", ""))
		if not reached.has(to):
			reached.append(to)
		if not left.has(from):
			left.append(from)
	for key: Variant in _model().get("states", {}):
		var state := str(key)
		assert_bool(reached.has(state)).override_failure_message(
			"no declared edge arrives at '%s'" % state).is_true()
		assert_bool(left.has(state)).override_failure_message(
			"no declared edge leaves '%s', so it is a trap" % state).is_true()


func _teardown_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()


## A save for the Continue edge to load. Written from the running game, then the title is
## rebuilt over it - the only way to have one, since a fresh process has none.
func _seed_a_save() -> void:
	assert_bool(_world.start_game(_quiet_manifest())).is_true()
	await _steps(1)
	GameState.current_map = &"quest_cave"
	GameState.player_position = Vector2(88.0, 104.0)
	GameState.set_party(9, 3, 1)
	assert_bool(SaveManager.save(0, GameState.to_save())).is_true()
	assert_bool(_world.open_title()).is_true()
	_world._offered = _quiet_manifest()
	await _steps(1)
