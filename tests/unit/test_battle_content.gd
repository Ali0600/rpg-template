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

func test_no_map_asks_for_a_bigger_formation_than_the_screen_draws() -> void:
	# The capacity is the content contract, and this is the half that was missing. The view has
	# declared MAX_PARTY since M27 and nothing refused a manifest that exceeded it - the layout
	# was audited AT capacity, which proves the drawing and not the data. Both sides are gated
	# here now, because the failure mode of "too many to draw" is silence.
	for path in ContentScan.files("res://data/maps", ["json"]):
		var map := MapData.load_from(path)
		for entry: Variant in map.enemies:
			var record: Dictionary = entry
			var size := 1 + (record.get("group", []) as Array).size()
			assert_int(size).override_failure_message(
				"%s places a formation of %d, and the screen draws %d"
				% [path, size, BattleScreen.MAX_FOES]).is_less_equal(BattleScreen.MAX_FOES)

func test_no_game_asks_for_a_bigger_party_than_the_screen_draws() -> void:
	for path in ContentScan.files("res://data/games", ["tres"]):
		var manifest := load(path) as GameManifest
		if manifest == null:
			continue
		# Plus the leader, who is synthesized rather than declared and still needs a block.
		var size := manifest.party.size() + 1
		assert_int(size).override_failure_message(
			"%s declares a party of %d, and the screen draws %d"
			% [path, size, BattleScreen.MAX_PARTY]).is_less_equal(BattleScreen.MAX_PARTY)

func test_the_curve_lines_up_with_what_the_quest_actually_pays() -> void:
	# The difficulty design, pinned. The hollow's two required fights must be exactly level 2,
	# because that is what the Keeper's numbers assume; and the Keeper must carry the player to
	# level 3. If a designer retunes an enemy's xp, the curve, or the SIZE of a formation, this
	# is the test that says the fight it was balanced against has moved.
	#
	# The awards are summed from the map records rather than from one enemy file, which is the
	# whole difference: `slink.xp * 2` was a stand-in for "the hollow", and stopped being one the
	# moment a record could name more than one body.
	var combat := _quest().combat
	var first := _award_of(HOLLOW_REQUIRED[0])
	var hollow := first + _award_of(HOLLOW_REQUIRED[1])
	assert_int(combat.level_for(first)).override_failure_message(
		"the hollow's first fight is already a level - it stops teaching and starts rewarding"
	).is_equal(1)
	assert_int(combat.level_for(hollow)).override_failure_message(
		"the hollow's required fights (%d xp) no longer reach level 2, which is what the Keeper is tuned against"
		% hollow).is_equal(2)
	assert_int(combat.level_for(hollow + _award_of(BOSS))).override_failure_message(
		"beating the Keeper no longer reaches level 3").is_equal(3)

func test_the_boss_fight_is_won_by_timing_and_lost_by_mashing() -> void:
	# The whole difficulty statement, and it is now made of the FIGHT rather than of arithmetic
	# about it: the real BattleLogic, the formation the map actually names, and the party the
	# player is actually guaranteed, played to the end on twelve seeds by two drivers.
	#
	# What this replaced hard-coded one enemy acting once per round against one player. That was
	# true when it was written and is the exact shape CLAUDE.md calls worse than no gate - it
	# would have gone on reporting green about a duel the game no longer contains.
	for seed_value in range(1, 13):
		var won := BattleDriver.play(_fight(BOSS, BOSS_LEVEL, seed_value),
			BattleDriver.Policy.PERFECT)
		assert_str(won.fault).is_empty()
		assert_bool(won.ended).override_failure_message(
			"the Keeper fight did not finish within the frame cap on seed %d" % seed_value).is_true()
		assert_int(won.outcome).override_failure_message(
			"a party that times every press LOSES to the Keeper on seed %d - %d standing, %s"
			% [seed_value, won.standing(), str(won.party_hp)]).is_equal(BattleLogic.Outcome.VICTORY)

		var lost := BattleDriver.play(_fight(BOSS, BOSS_LEVEL, seed_value),
			BattleDriver.Policy.MASH)
		assert_bool(lost.ended).is_true()
		assert_int(lost.outcome).override_failure_message(
			"a party that times NOTHING survives the Keeper on seed %d - the timing mechanic is decorative"
			% seed_value).is_equal(BattleLogic.Outcome.DEFEAT)

func test_the_boss_fight_actually_swings_at_the_party() -> void:
	# The other half of the driver, and the reason there are two. A party that parries everything
	# is barely hurt, so "PERFECT wins" is equally true of a formation that never gets a turn -
	# an optimal driver only walks the branches optimal play reaches. This counts what happened:
	# every foe must have taken at least one turn, and the party must have been swung at.
	var report := BattleDriver.play(_fight(BOSS, BOSS_LEVEL, 5), BattleDriver.Policy.PERFECT)
	assert_int(report.foes.size()).override_failure_message(
		"the boss record fields nothing").is_greater(0)
	assert_int(report.blows).override_failure_message(
		"the Keeper's formation (%s) took %d turns in a whole fight - a foe that never acts is a foe that is not in the fight"
		% [str(report.foes), report.blows]).is_greater_equal(report.foes.size())
	assert_int(report.timed_presses).override_failure_message(
		"the perfect driver never pressed inside a window, so it was not playing perfectly"
	).is_greater(0)

func test_no_shipped_formation_is_unwinnable() -> void:
	# The disaster this catches is a fight nobody can win: a group tuned past what the game's own
	# curve can answer, which no unit test sees because every piece of it is individually fine.
	# Each shipped record is played by the guaranteed party at the top of the curve, with perfect
	# play - if it cannot be won THERE it cannot be won anywhere.
	var combat := _quest().combat
	var top := combat.xp_curve.size() + 1
	for entry: Variant in _encounters():
		var found: Dictionary = entry
		var record_id: String = found["id"]
		var report := BattleDriver.play(_fight(record_id, top, 3), BattleDriver.Policy.PERFECT)
		assert_str(report.fault).is_empty()
		assert_bool(report.ended).override_failure_message(
			"the '%s' fight did not finish within the frame cap" % record_id).is_true()
		assert_int(report.outcome).override_failure_message(
			"'%s' (%s) cannot be won at level %d even with every press timed"
			% [record_id, str(report.foes), top]).is_equal(BattleLogic.Outcome.VICTORY)

func test_no_fight_can_be_reached_by_a_party_it_was_not_balanced_for() -> void:
	# THE INVARIANT M29 EXISTS FOR, and the one nothing checked. A fight sized for two must be
	# unreachable by one: every companion the balance model counts on has to be un-declinable on
	# every map that places enemies - either they join unconditionally, or every road there
	# demands the flag that recruits them.
	#
	# Before M29 this was false, and correctly so: fights were solo, Rook was optional, the model
	# fought alone and the game was balanced for that. Making the fights pairs is what turned "she
	# is optional" from a player's choice into TWO games, of which only one was ever balanced -
	# alone, a mashing player dies to the first slink pair and a perfect one still loses to the
	# Keeper. So the roads demand her, and this is what keeps them demanding her.
	var manifest := _quest()
	var declared := manifest.party.size()
	assert_int(declared).override_failure_message(
		"the quest declares no party, so this says nothing about anything").is_greater(0)
	var checked := 0
	for path in ContentScan.files_of("res://data/maps", "json"):
		var map := MapData.load_from(path)
		if map.enemies.is_empty():
			continue
		checked += 1
		assert_int(_guaranteed_party(manifest, map.id).size()).override_failure_message(
			"'%s' places fights, and a player can stand on it having declined a companion - so those fights are balanced against a party the player need not have"
			% map.id).is_equal(declared)
	# A loop over no maps validates nothing and reports success, which is this suite's own idiom.
	assert_int(checked).override_failure_message(
		"no shipped map places a fight, so the loop above proved nothing").is_greater(0)
	# And the walk actually walks: a map nothing warps to must come back unreachable, or
	# "guaranteed" would be true of everyone everywhere and the derivation would be decoration.
	assert_bool(_reachable_without(manifest, &"quest_nowhere", &"")).override_failure_message(
		"the reachability walk reports a map that does not exist as reachable").is_false()

# -- reading the shipped fights out of the data --------------------------------------------
#
# Everything below answers a question about the GAME rather than about a class, and answers it
# from the files rather than from a constant here. Two record ids and one level are named,
# because "which fights are the hollow's required pair" and "what level is the Keeper tuned
# against" are design intent that no file states - but every NUMBER comes from the data, so
# adding a body to a formation moves the gate rather than sliding past it.

const QUEST_PATH := "res://data/games/quest.tres"
const HOLLOW_REQUIRED := ["slink_gate", "slink_stash"]
const BOSS := "keeper"
const BOSS_LEVEL := 2

func _quest() -> GameManifest:
	return load(QUEST_PATH) as GameManifest

## Every enemy record the shipped game places, as {"id", "map", "foes"}.
func _encounters() -> Array:
	var out: Array = []
	for path in ContentScan.files_of("res://data/maps", "json"):
		var map := MapData.load_from(path)
		for entry: Variant in map.enemies:
			var record: Dictionary = entry
			var tile := JsonFile.to_int_array(record.get("tile", []))
			if tile.size() != 2:
				continue
			# Through the map's OWN projection, so the gate and the world agree about what a
			# record fields by construction rather than by both being written correctly.
			var found := map.enemy_at(Vector2i(tile[0], tile[1]))
			out.append({"id": str(record.get("id", "")), "map": map, "foes": found.get("foes", [])})
	return out

func _encounter(record_id: String) -> Dictionary:
	for entry: Variant in _encounters():
		var found: Dictionary = entry
		if found["id"] == record_id:
			return found
	return {}

## What a record pays, summed over everything in it. The DQ rule means every living member earns
## this in full, so it is the party's award and not a share of one.
func _award_of(record_id: String) -> int:
	var out := 0
	for def in _defs_of(record_id):
		out += def.xp
	return out

func _defs_of(record_id: String) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	var found := _encounter(record_id)
	for named: Variant in found.get("foes", []):
		var def := load("res://data/enemies/%s.tres" % named) as EnemyDef
		if def != null:
			out.append(def)
	return out

## The fight itself: the map's formation against the party the player cannot avoid having.
func _fight(record_id: String, level: int, seed_value: int) -> BattleLogic:
	var manifest := _quest()
	var found := _encounter(record_id)
	var map: MapData = found["map"]
	return BattleLogic.of(manifest.combat, _defs_of(record_id),
		BattleHelpers.party_of(manifest, _guaranteed_party(manifest, map.id), level),
		[], "%s/%s" % [map.id, record_id], seed_value)

## Who the player is CERTAIN to have by the time they can stand on `map_id`.
##
## Derived, never assumed. A companion who joins on a flag is only guaranteed if there is no way
## into that map without the flag - so this asks the warp graph rather than the manifest, and a
## member the player may decline is correctly absent from the fight the gate balances. That
## distinction is the whole of M29's finding: sizing a fight for two while letting the player
## travel alone ships two games and balances one.
func _guaranteed_party(manifest: GameManifest, map_id: StringName) -> Array:
	var out: Array = []
	for member: PartyMemberDef in manifest.party:
		if member == null:
			continue
		if String(member.joins_on_flag).is_empty():
			out.append(member)
		elif not _reachable_without(manifest, map_id, member.joins_on_flag):
			out.append(member)
	return out

## Whether `map_id` can still be reached from the game's first map when every warp demanding
## `flag` is refused.
##
## A FIXPOINT rather than a plain walk, because a locked door moves with the key: the keep asks
## for `gate_key`, the key lies in the hollow, and the hollow asks for the flag - so refusing the
## flag closes the keep too, one room removed. A walk that ignored items would call the keep
## reachable alone and quietly conclude the player might arrive there without a companion.
##
## An item NO map object grants is assumed obtainable (the smith's tonics, the hermit's oil,
## which come out of conversations). That direction is the safe one: assuming an item is
## available can only make more maps reachable, which makes fewer companions count as guaranteed
## and the balance requirement HARDER. The reverse - failing to notice a source - would inflate
## the party the gate balances, which is the mistake this whole derivation exists to prevent.
func _reachable_without(manifest: GameManifest, map_id: StringName, flag: StringName) -> bool:
	var granted := _items_granted_by_maps()
	var reached := {manifest.start_map: true}
	var changed := true
	while changed:
		changed = false
		for here: Variant in reached.keys():
			var map := MapData.load_from("res://data/maps/%s.json" % here)
			if not map.ok:
				continue
			for entry: Variant in map.warps:
				var warp: Dictionary = entry
				if StringName(str(warp.get("requires_flag", ""))) == flag:
					continue
				var need := StringName(str(warp.get("requires_item", "")))
				if granted.has(need) and not reached.has(granted[need]):
					continue
				var there := StringName(str(warp.get("map", "")))
				if String(there).is_empty() or reached.has(there):
					continue
				reached[there] = true
				changed = true
	return reached.has(map_id)

## Which map hands out each item, for the walk above. Only map OBJECTS are sourced; anything a
## conversation gives is deliberately absent, and `_reachable_without` says why.
func _items_granted_by_maps() -> Dictionary:
	var out := {}
	for path in ContentScan.files_of("res://data/maps", "json"):
		var map := MapData.load_from(path)
		for entry: Variant in map.objects:
			var object: Dictionary = entry
			var gives := StringName(str(object.get("give_item", "")))
			if not String(gives).is_empty() and not out.has(gives):
				out[gives] = map.id
	return out

func test_two_tonics_are_what_sits_between_those_two_outcomes() -> void:
	# The tuning point named out loud: the tonics are for the player who lands some presses and
	# misses others, and two of them have to be worth about a third of the fight.
	var tonic := load("res://data/items/tonic.tres") as ItemDef
	var combat := (load("res://data/games/quest.tres") as GameManifest).combat
	assert_int(tonic.battle_heal).override_failure_message(
		"the tonic stopped healing, so the Item command has nothing behind it").is_greater(0)
	assert_int(tonic.battle_heal * 2).is_between(
		combat.max_hp(2) / 4, combat.max_hp(2))
