extends GdUnitTestSuite
## Everything the shipped battles are made of, checked against what is actually on disk.
##
## The failures this catches are all the same shape: a misspelt id, or art that was never
## generated. Neither errors. A map with a misspelt enemy is a map that merely looks empty,
## and an enemy with no sheet is a fight against a blank space - both read as level design
## rather than as typos, which is why they are scanned rather than listed.

const ENEMY_DIR := "res://data/enemies"
const COMBAT_DIR := "res://data/combat"

func _known_enemy_ids() -> Dictionary:
	var out := {}
	for path in ContentScan.files_of(ENEMY_DIR, "tres"):
		var enemy := load(path) as EnemyDef
		if enemy != null:
			out[enemy.id] = path
	return out

func test_there_is_something_to_check() -> void:
	# A loop over an empty directory validates nothing and reports success. Every scanning
	# suite here opens with this for that reason.
	assert_int(ContentScan.files_of(ENEMY_DIR, "tres").size()).is_greater(0)
	assert_int(ContentScan.files_of(COMBAT_DIR, "tres").size()).is_greater(0)

func test_every_shipped_enemy_is_valid_and_named_after_its_file() -> void:
	var seen := {}
	for path in ContentScan.files_of(ENEMY_DIR, "tres"):
		var enemy := load(path) as EnemyDef
		assert_object(enemy).override_failure_message(
			"%s is under data/enemies but is not an EnemyDef" % path).is_not_null()
		assert_array(enemy.problems()).override_failure_message(
			"%s: %s" % [path, ", ".join(enemy.problems())]).is_empty()
		# The file's name IS the id, so "which file is enemy X" needs no search.
		assert_str(String(enemy.id)).is_equal(path.get_file().get_basename())
		assert_bool(seen.has(enemy.id)).override_failure_message(
			"two files claim enemy '%s'" % enemy.id).is_false()
		seen[enemy.id] = true

func test_every_shipped_combat_definition_is_valid() -> void:
	for path in ContentScan.files_of(COMBAT_DIR, "tres"):
		var combat := load(path) as CombatDef
		assert_object(combat).override_failure_message(
			"%s is under data/combat but is not a CombatDef" % path).is_not_null()
		assert_array(combat.problems()).override_failure_message(
			"%s: %s" % [path, ", ".join(combat.problems())]).is_empty()

func test_every_enemy_a_map_places_exists() -> void:
	var known := _known_enemy_ids()
	for path in ContentScan.files_of("res://data/maps", "json"):
		var map := MapData.load_from(path)
		for enemy_id in map.enemy_refs():
			assert_bool(known.has(enemy_id)).override_failure_message(
				"map '%s' places enemy '%s', which no file in %s describes"
				% [map.id, enemy_id, ENEMY_DIR]).is_true()

func test_every_enemy_a_map_places_has_art_in_that_map_s_style() -> void:
	# Art is generated per STYLE, and an enemy does not know which map places it - so "the art
	# exists" is only answerable here, where both facts are in scope. Same shape as
	# GameManifest's check on the player's character.
	var known := _known_enemy_ids()
	for path in ContentScan.files_of("res://data/maps", "json"):
		var map := MapData.load_from(path)
		for enemy_id in map.enemy_refs():
			if not known.has(enemy_id):
				continue
			var enemy := load(known[enemy_id]) as EnemyDef
			var sheet := "res://assets/generated/%s/%s.sheet.json" % [map.style_id, enemy.character]
			assert_bool(FileAccess.file_exists(sheet)).override_failure_message(
				"map '%s' places '%s', whose character '%s' has no generated art for style '%s' (expected %s)"
				% [map.id, enemy_id, enemy.character, map.style_id, enemy.character, sheet]).is_true()

func test_a_game_that_places_enemies_says_how_fighting_works() -> void:
	# A map placing an enemy in a game with no CombatDef is a fight that can never open. The
	# world says so at runtime; this says so at build time, which is the better moment.
	for game_path in ContentScan.files_of("res://data/games", "tres"):
		var manifest := load(game_path) as GameManifest
		if manifest == null:
			continue
		var places := false
		for map_path in ContentScan.files_of("res://data/maps", "json"):
			var map := MapData.load_from(map_path)
			if not map.enemy_refs().is_empty() and map.style_id == _style_of(manifest):
				places = true
		if places:
			assert_object(manifest.combat).override_failure_message(
				"game '%s' has maps with enemies on them but no combat definition"
				% manifest.id).is_not_null()

## The style a game draws in, taken from its start map - the same route GameManifest uses to
## decide which generated art the player's character needs.
func _style_of(manifest: GameManifest) -> StringName:
	var map := MapData.load_from("res://data/maps/%s.json" % manifest.start_map)
	return map.style_id if map.ok else &""

func test_the_shipped_quest_can_actually_be_fought() -> void:
	var manifest := load("res://data/games/quest.tres") as GameManifest
	assert_object(manifest.combat).override_failure_message(
		"the shipped game lost its combat definition, so every fight refuses to open").is_not_null()
	assert_array(manifest.problems()).override_failure_message(
		str(manifest.problems())).is_empty()

func test_the_curve_lines_up_with_what_the_quest_actually_pays() -> void:
	# The difficulty design, pinned. Two hollow slinks must be exactly level 2, because that is
	# what the Keeper's numbers assume; and the Keeper must carry the player to level 3. If a
	# designer retunes an enemy's xp or the curve, this is the test that says the fight it was
	# balanced against has moved.
	var combat := (load("res://data/games/quest.tres") as GameManifest).combat
	var slink := load("res://data/enemies/slink.tres") as EnemyDef
	var keeper := load("res://data/enemies/keeper.tres") as EnemyDef
	assert_int(combat.level_for(slink.xp)).override_failure_message(
		"one slink is already a level - the hollow stops teaching and starts rewarding").is_equal(1)
	assert_int(combat.level_for(slink.xp * 2)).override_failure_message(
		"the two hollow slinks no longer reach level 2, which is what the Keeper is tuned against"
	).is_equal(2)
	assert_int(combat.level_for(slink.xp * 2 + keeper.xp)).override_failure_message(
		"beating the Keeper no longer reaches level 3").is_equal(3)

func test_a_level_two_player_can_beat_the_keeper_by_timing_and_cannot_by_mashing() -> void:
	# The whole difficulty statement, as arithmetic rather than as a comment: perfect play wins
	# on every seed, and no play loses on every seed. A boss that is beatable by mashing has no
	# timing mechanic; one that is unbeatable with it is a wall.
	var combat := (load("res://data/games/quest.tres") as GameManifest).combat
	var keeper := load("res://data/enemies/keeper.tres") as EnemyDef
	var level := 2
	var hp := combat.max_hp(level)

	var timed := BattleLogic.damage(combat.attack_at(level), keeper.defense) * 2
	var rounds := ceili(float(keeper.max_hp) / float(timed))
	var worst_blocked := 0
	var worst_open := 0
	for move: Dictionary in keeper.moves:
		var raw := BattleLogic.damage(keeper.attack + int(move.get("power", 0)), combat.defense_at(level))
		worst_blocked = maxi(worst_blocked, maxi(raw / 2, 1))
		worst_open = maxi(worst_open, raw)
	assert_int(rounds * worst_blocked).override_failure_message(
		"a player who times every press can still lose to the Keeper: %d rounds x %d damage vs %d health"
		% [rounds, worst_blocked, hp]).is_less(hp)

	var untimed := BattleLogic.damage(combat.attack_at(level), keeper.defense)
	var slow := ceili(float(keeper.max_hp) / float(untimed))
	# The Keeper acts once per round after the first player swing, and its WEAKEST move is the
	# one to measure against: if even that kills in time, the fight is lost on every seed.
	var weakest := 999
	for move: Dictionary in keeper.moves:
		weakest = mini(weakest, BattleLogic.damage(
			keeper.attack + int(move.get("power", 0)), combat.defense_at(level)))
	assert_int(slow * weakest).override_failure_message(
		"a player who times nothing survives the Keeper: %d rounds x %d damage vs %d health - the timing mechanic is decorative"
		% [slow, weakest, hp]).is_greater_equal(hp)

func test_two_tonics_are_what_sits_between_those_two_outcomes() -> void:
	# The tuning point named out loud: the tonics are for the player who lands some presses and
	# misses others, and two of them have to be worth about a third of the fight.
	var tonic := load("res://data/items/tonic.tres") as ItemDef
	var combat := (load("res://data/games/quest.tres") as GameManifest).combat
	assert_int(tonic.battle_heal).override_failure_message(
		"the tonic stopped healing, so the Item command has nothing behind it").is_greater(0)
	assert_int(tonic.battle_heal * 2).is_between(
		combat.max_hp(2) / 4, combat.max_hp(2))
