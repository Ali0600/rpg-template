extends GdUnitTestSuite
## Everything the shipped battles are made of, checked against what is actually on disk.
##
## The failures this catches are all the same shape: a misspelt id, or art that was never
## generated. Neither errors. A map with a misspelt enemy is a map that merely looks empty,
## and an enemy with no sheet is a fight against a blank space - both read as level design
## rather than as typos, which is why they are scanned rather than listed.

const ENEMY_DIR := "res://data/enemies"
const COMBAT_DIR := "res://data/combat"
const SPELL_DIR := "res://data/spells"
const ITEM_DIR := "res://data/items"

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

func test_every_shipped_spell_is_valid_and_named_after_its_file() -> void:
	# The enemy files have had this since M13 and the spell files never did, which a mutant found
	# by breaking one and watching every gate stay green: a shipped spell with no duration or no
	# power is a row that spends magic and changes nothing, and it would have surfaced in play.
	var seen := {}
	for path in ContentScan.files_of(SPELL_DIR, "tres"):
		var spell := load(path) as SpellDef
		assert_object(spell).override_failure_message(
			"%s is under data/spells but is not a SpellDef" % path).is_not_null()
		assert_array(spell.problems()).override_failure_message(
			"%s: %s" % [path, ", ".join(spell.problems())]).is_empty()
		assert_str(String(spell.id)).is_equal(path.get_file().get_basename())
		assert_bool(seen.has(spell.id)).override_failure_message(
			"two files claim spell '%s'" % spell.id).is_false()
		seen[spell.id] = true
	assert_int(seen.size()).override_failure_message(
		"no spells were checked, so the loop above proved nothing").is_greater(0)

func test_every_element_a_resistance_answers_is_one_some_spell_is_made_of() -> void:
	# The two halves of the system live in different directories and are joined by a bare string,
	# so a typo on either side is a pairing that silently never fires - the enemy looks resistant
	# in its file, the spell looks elemental in its own, and the fight quietly applies 100%.
	# Nothing else can see that: both files are individually valid.
	var castable := {}
	for path in ContentScan.files_of(SPELL_DIR, "tres"):
		var spell := load(path) as SpellDef
		if spell != null and not String(spell.element).is_empty():
			castable[spell.element] = spell.id
	var answered := 0
	for path in ContentScan.files_of(ENEMY_DIR, "tres"):
		var enemy := load(path) as EnemyDef
		if enemy == null:
			continue
		for element: Variant in enemy.resistances:
			answered += 1
			assert_bool(castable.has(element)).override_failure_message(
				"'%s' answers '%s', which no shipped spell is made of - that resistance can "
				% [enemy.id, element] + "never fire. Spells offer: %s" % [castable.keys()]) \
				.is_true()
	# A game may ship no resistances at all, but THIS one does, and a loop that compared nothing
	# would report green about a table it never opened.
	assert_int(answered).override_failure_message(
		"no resistance was checked, so the loop above proved nothing").is_greater(0)

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
				% [map.id, enemy_id, enemy.character, map.style_id, sheet]).is_true()

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
				% [path, size, FightScreen.MAX_FOES]).is_less_equal(FightScreen.MAX_FOES)

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

## Every caption the CASTER policy produces across the shipped encounters, per encounter id.
##
## Built once and shared by the coverage tests below, because playing every fight at two levels
## on eight seeds is the expensive part and the assertions are three different questions about
## one traversal.
func _cast_reports() -> Dictionary:
	var out := {}
	var top: int = _quest().combat.xp_curve.size() + 1
	for entry: Variant in _encounters():
		var found: Dictionary = entry
		var record_id: String = found["id"]
		var seen: Array[BattleDriver.Report] = []
		for level in range(2, top + 1):
			for seed_value in range(1, 9):
				seen.append(BattleDriver.play(_fight(record_id, level, seed_value),
					BattleDriver.Policy.CASTER))
		out[record_id] = seen
	return out

func test_a_party_that_casts_still_wins_every_shipped_fight() -> void:
	# The balance half. Casting SPENDS a turn that could have been a swing, so a party that wins
	# by swinging is not automatically a party that wins by casting - and a spell list tuned so
	# badly that using it loses the fight is a trap the menu offers with no warning.
	var reports := _cast_reports()
	for record_id: String in reports:
		for report: BattleDriver.Report in reports[record_id]:
			assert_str(report.fault).is_empty()
			assert_bool(report.ended).override_failure_message(
				"the '%s' fight did not finish within the cap under a caster" % record_id).is_true()
			assert_int(report.outcome).override_failure_message(
				"'%s' (%s) is lost by a party that uses its magic - %d standing, %s"
				% [record_id, str(report.foes), report.standing(), str(report.party_hp)]) \
				.is_equal(BattleLogic.Outcome.VICTORY)

func test_every_shipped_spell_is_actually_cast_somewhere() -> void:
	# CONTENT coverage, not outcome coverage. A spell nobody can reach - learned past the level
	# the curve tops out at, or priced past a pool that size - is a row the player is never
	# offered, and every other gate here is blind to it: the file is valid, the resolver hands it
	# over correctly, and no fight ever gets to it.
	var cast := {}
	var reports := _cast_reports()
	for record_id: String in reports:
		for report: BattleDriver.Report in reports[record_id]:
			for id: StringName in report.casts:
				cast[id] = true
	# The control. A driver that cast nothing would satisfy every "was it cast correctly"
	# assertion by vacuum, and this whole file would go green about a system it never entered.
	assert_int(cast.size()).override_failure_message(
		"the casting driver cast nothing at all, so the coverage below proves nothing").is_greater(0)
	for path in ContentScan.files_of(SPELL_DIR, "tres"):
		var spell := load(path) as SpellDef
		assert_bool(cast.has(spell.id)).override_failure_message(
			"'%s' is shipped and is never cast in any fight the game contains, at any level or "
			% spell.id + "seed - so nothing here has ever played it. Cast: %s" % [cast.keys()]) \
			.is_true()

func test_every_shipped_resistance_is_told_to_the_player_somewhere() -> void:
	# THE ASSERTION THIS MILESTONE EXISTS FOR, and it found two defects the first time it ran.
	#
	# A resistance that never announces itself in any fight the game contains is a system the
	# player cannot learn: the cross-content check proves the two halves NAME the same element,
	# and this proves they MEET. It is `demo-must-show-the-feature` as a gate rather than as a
	# habit.
	#
	# What it caught: the Keeper's answer to fire was unobservable because the driver finished
	# the weakest foe first and never spent magic on the boss while it had any; and the slink's
	# weakness to wind was unobservable because the only wind spell is a SWEEP, and a sweep
	# carried no clause at all - its numbers being side by side only helps when they DIFFER.
	# SOMEWHERE, deliberately, rather than in every encounter that fields the enemy. A caster
	# aiming at the toughest foe never spends magic on the escort standing beside a boss, so the
	# gloom's own answer goes untold in the Keeper's fight and is told plainly in the cave's. What
	# has to hold is that a player CAN learn each pairing, not that every fight teaches it.
	var reports := _cast_reports()
	var told := {}
	for entry: Variant in _encounters():
		var found: Dictionary = entry
		var record_id: String = found["id"]
		var lines: Array[String] = []
		for report: BattleDriver.Report in reports[record_id]:
			lines.append_array(report.said)
		for def in _defs_of(record_id):
			if _was_told(lines, def):
				told[def.id] = record_id
	var checked := 0
	for entry: Variant in _encounters():
		var found: Dictionary = entry
		for def in _defs_of(str(found["id"])):
			if def.resistances.is_empty():
				continue
			checked += 1
			assert_bool(told.has(def.id)).override_failure_message(
				("'%s' answers %s and NO fight in the game ever says so, at any level or seed - "
				+ "so the pairing cannot be learned in play. Told: %s")
				% [def.id, str(def.resistances.keys()), str(told)]).is_true()
	# A game may ship no resistances at all; this one does, and a loop that checked nothing would
	# report green about a table it never opened.
	assert_int(checked).override_failure_message(
		"no resistance was checked, so the loop above proved nothing").is_greater(0)

## Whether any of `lines` tells the player about `def`'s answer.
##
## ONE SHAPE now, where M34 needed two. A sweep used to say one combined verdict naming nobody
## ("They are weak to it"), so this had to special-case a formation made entirely of one enemy to
## attribute it. Sequencing the sweep into a line per foe deleted that: every clause the game
## says now sits in a line that names the foe it is about, so the check is the same for a spell
## aimed at one thing and a spell that reached three.
func _was_told(lines: Array[String], def: EnemyDef) -> bool:
	for line in lines:
		if not line.contains(def.name):
			continue
		if line.contains("weak to") or line.contains("shrugs off"):
			return true
	return false

## Every report the DRINKER policy produces across the shipped encounters, built once and
## shared for `_cast_reports`' reason.
func _drink_reports() -> Dictionary:
	var out := {}
	var top: int = _quest().combat.xp_curve.size() + 1
	for entry: Variant in _encounters():
		var record_id: String = entry["id"]
		var seen: Array[BattleDriver.Report] = []
		for level in range(2, top + 1):
			for seed_value in range(1, 9):
				seen.append(BattleDriver.play(_fight(record_id, level, seed_value, _full_bag()),
					BattleDriver.Policy.DRINKER))
		out[record_id] = seen
	return out

func test_nothing_a_player_needs_can_be_drunk_in_a_fight() -> void:
	# THE GUARD WITH NO TEST, until now, and the worst failure in this file if it broke. Using an
	# item appends the same take-effect whatever it was, so a quest item on the battle menu is not
	# merely a row that disappoints - it is a key destroyed and a door shut for the rest of the
	# run, hours before the player finds out. The filter is one comparison and nothing proved it.
	var offered := {}
	for row: BattleLogic.ItemRow in _full_bag():
		offered[row.id] = true
	var checked := 0
	for def: ItemDef in _every_item():
		checked += 1
		if def.battle_heal > 0:
			assert_bool(offered.has(def.id)).override_failure_message(
				"'%s' heals %d and is not on the battle menu at all" % [def.id, def.battle_heal]) \
				.is_true()
			continue
		assert_bool(offered.has(def.id)).override_failure_message(
			("'%s' heals nothing and is offered mid-fight anyway. Using it spends it - if it "
			+ "opens a door, that door is now shut for the rest of the run.") % def.id).is_false()
	# Both halves of the filter have to be reachable, or this passes by testing one of them: the
	# game ships items that heal and items that do not, and a run over an empty directory would
	# report green about a rule it never applied.
	assert_int(checked).override_failure_message(
		"no item was checked, so the filter above was never applied").is_greater(1)

func test_a_party_that_drinks_still_wins_every_shipped_fight() -> void:
	var reports := _drink_reports()
	for record_id: String in reports:
		for report: BattleDriver.Report in reports[record_id]:
			assert_str(report.fault).is_empty()
			assert_bool(report.ended).override_failure_message(
				"the '%s' fight did not finish under a drinker" % record_id).is_true()
			assert_int(report.outcome).override_failure_message(
				"'%s' (%s) is lost by a party that uses its bag - %d standing, %s"
				% [record_id, str(report.foes), report.standing(), str(report.party_hp)]) \
				.is_equal(BattleLogic.Outcome.VICTORY)

func test_every_item_that_can_be_used_in_a_fight_actually_is() -> void:
	# CONTENT coverage, `test_every_shipped_spell_is_actually_cast_somewhere`'s twin. An item
	# whose heal is wrong, or which no fight ever reaches for, is invisible to every other gate
	# here: the file is valid, the filter hands it over correctly, and nothing drinks it.
	var used := {}
	var reports := _drink_reports()
	for record_id: String in reports:
		for report: BattleDriver.Report in reports[record_id]:
			for id: StringName in report.used:
				used[id] = true
	assert_int(used.size()).override_failure_message(
		"the drinking driver used nothing at all, so the coverage below proves nothing") \
		.is_greater(0)
	for def: ItemDef in _every_item():
		if def.battle_heal <= 0:
			continue
		assert_bool(used.has(def.id)).override_failure_message(
			"'%s' heals %d in a fight and no fight ever reaches for it, at any level or seed. "
			% [def.id, def.battle_heal] + "Used: %s" % [used.keys()]).is_true()

func test_a_fight_that_must_happen_is_the_only_one_that_cannot_be_run_from() -> void:
	# "A fight that must happen is made unavoidable by GEOMETRY, never by a radius" is a rule this
	# template states out loud, and the half of it living in the DATA - which encounter refuses
	# every escape - was asserted by nothing whatever.
	#
	# THE SET, not a property of whatever is in it. A first draft read each record's own `boss`
	# flag to decide what to expect of it, which is self-fulfilling: flagging a slink as a boss
	# made the tutorial inescapable AND moved the expectation to match, and the mutant survived.
	# So the expectation is declared here, independently - exactly ONE shipped encounter refuses -
	# and the played result is compared against it. That also catches the deletion case, which a
	# per-record property check cannot see at all: "everything flagged is refused" stays true when
	# the flag is dropped, because the set only got smaller.
	var refuses: Array[String] = []
	var checked := 0
	for entry: Variant in _encounters():
		var record_id: String = entry["id"]
		var report := BattleDriver.play(_fight(record_id, BOSS_LEVEL, 3),
			BattleDriver.Policy.RUNNER)
		assert_str(report.fault).is_empty()
		assert_bool(report.ended).override_failure_message(
			"the '%s' fight never ended under a runner" % record_id).is_true()
		checked += 1
		if report.outcome == BattleLogic.Outcome.FLED:
			continue
		refuses.append(record_id)
		# The refusal has to REACH the player. "Did not end in FLED" is equally satisfied by a
		# fight where Run silently did nothing, which is the reading a player gives a broken key.
		var said := false
		for line in report.said:
			if line.contains("no way past"):
				said = true
		assert_bool(said).override_failure_message(
			"'%s' refused the escape without saying so: %s" % [record_id, report.said]).is_true()
	assert_int(checked).override_failure_message(
		"no encounter was played, so nothing below was compared").is_greater(1)
	assert_array(refuses).override_failure_message(
		("the fights that cannot be run from are %s; the game declares exactly one, '%s'. A flag "
		+ "added makes a tutorial inescapable, and one dropped makes the mandatory fight optional.")
		% [refuses, BOSS]).contains_exactly([BOSS])

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
##
## The bag is EMPTY by default and every balance assertion leaves it that way, deliberately: a
## party carrying nothing is the pessimistic one, and a formation it beats is one the real player
## beats. Only the item-driver tests pass a bag, because a driver with nothing to reach for
## cannot exercise the page - and they assert coverage rather than difficulty.
func _fight(record_id: String, level: int, seed_value: int, items: Array = []) -> BattleLogic:
	var manifest := _quest()
	var found := _encounter(record_id)
	var map: MapData = found["map"]
	return BattleLogic.of(manifest.combat, _defs_of(record_id),
		BattleHelpers.party_of(manifest, _guaranteed_party(manifest, map.id), level),
		items, "%s/%s" % [map.id, record_id], seed_value)

## Every shipped item, read off disk - the whole of `data/items`, not a hand-picked healing
## subset. Handing the WHOLE catalogue to `ItemRow.bag` is the point: what comes back is what the
## filter let through, so a fight that offered a gate key would be offering it here too.
func _every_item() -> Array:
	var out: Array = []
	for path in ContentScan.files_of(ITEM_DIR, "tres"):
		out.append(load(path) as ItemDef)
	return out

## The battle bag a player could carry, three of everything the filter allows. Three because one
## is spent by the first sip and a driver that empties the bag stops exercising it.
func _full_bag() -> Array:
	var counts := {}
	for def: ItemDef in _every_item():
		counts[def.id] = 3
	return BattleLogic.ItemRow.bag(_every_item(), counts)

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
## `flag` is refused. The walk itself lives in WarpGraph, because the map-content gate asks the
## same question for a different reason - and two walks would eventually disagree about a
## locked door, each gate then reporting on a game the other does not believe in.
func _reachable_without(manifest: GameManifest, map_id: StringName, flag: StringName) -> bool:
	return WarpGraph.reachable(manifest, flag).has(map_id)
func test_two_tonics_are_what_sits_between_those_two_outcomes() -> void:
	# The tuning point named out loud: the tonics are for the player who lands some presses and
	# misses others, and two of them have to be worth about a third of the fight.
	var tonic := load("res://data/items/tonic.tres") as ItemDef
	var combat := (load("res://data/games/quest.tres") as GameManifest).combat
	assert_int(tonic.battle_heal).override_failure_message(
		"the tonic stopped healing, so the Item command has nothing behind it").is_greater(0)
	assert_int(tonic.battle_heal * 2).is_between(
		combat.max_hp(2) / 4, combat.max_hp(2))

# -- the arena --------------------------------------------------------------------------------
#
# Since M51 the sword is a choice a player makes in Options, so every encounter The Barred Gate ships
# can be fought in the arena, with the game's own fighter. Its fights are balanced by the same kind of
# instrument one resolver along: ArenaSim played to the end by ArenaDriver, over the formation the map
# names and the party the player is guaranteed. The leader fights alone and the party shares the
# award, which ArenaSim.of already does with the party it is handed. ArenaSim reads a fighter's
# numbers and never its `style`, so the curve the turn fight is balanced against is the arena's too,
# and every level beat of the quest stays true with a sword.

## Seeds the careless player is judged over, and how many of them it may win. Measured 2026-09-14:
## walking into the Keeper at level 2 won 4 of 48, and 2 or 3 at every flash length tried from 32
## frames to 48.
const CARELESS_SEEDS := 48
const CARELESS_WINS_ALLOWED := 6

func _arena_fight(record_id: String, level: int, seed_value: int) -> ArenaSim:
	var manifest := _quest()
	var found := _encounter(record_id)
	var map: MapData = found["map"]
	return ArenaSim.of(manifest.combat, _defs_of(record_id),
		BattleHelpers.party_of(manifest, _guaranteed_party(manifest, map.id), level),
		"%s/%s" % [map.id, record_id], seed_value, manifest.config)

## Everybody who fights on `manifest`'s side, by the art they are drawn with when they wear nothing:
## the leader, and every member of the roster.
func _wearers_of(manifest: GameManifest) -> Array[StringName]:
	var out: Array[StringName] = [manifest.player_character]
	for member: PartyMemberDef in manifest.party:
		if member != null and not String(member.character).is_empty():
			out.append(member.character)
	return out

## Every art a fighter drawn as `own` can be drawn with in a fight: their own, and whatever any of
## `items` draws them as while it is worn.
func _arts_of(own: StringName, items: Array) -> Array[StringName]:
	var out: Array[StringName] = [own]
	for item: ItemDef in items:
		if item != null and not out.has(item.art_for(own)):
			out.append(item.art_for(own))
	return out

## Every map `manifest` can be played into.
func _maps_of(manifest: GameManifest) -> Array[MapData]:
	var out: Array[MapData] = []
	for key: Variant in WarpGraph.reachable(manifest).keys():
		var map := MapData.load_from(MapData.path_of(StringName(str(key))))
		if map.ok:
			out.append(map)
	return out

## What is wrong with the art `items` draw their wearers with, for `manifests`: art named for a body
## no game fights as, which is a typo that silently never draws, and art a game that can wear it has
## no sheet for in the style of a map it fights on, which is a fighter who vanishes mid-fight.
func _worn_art_faults(items: Array, manifests: Array[GameManifest]) -> Array[String]:
	var out: Array[String] = []
	var bodies := {}
	for manifest in manifests:
		for wearer in _wearers_of(manifest):
			bodies[wearer] = true
	for item: ItemDef in items:
		for wearer: Variant in item.worn_art:
			if not bodies.has(StringName(str(wearer))):
				out.append("item '%s' names art for '%s', and no game fights as '%s'"
					% [item.id, wearer, wearer])
	for manifest in manifests:
		var styles := {}
		for map in _maps_of(manifest):
			styles[map.style_id] = true
		for wearer in _wearers_of(manifest):
			for art in _arts_of(wearer, items):
				for style_id: Variant in styles:
					if not FileAccess.file_exists("res://assets/generated/%s/%s.sheet.json" % [style_id, art]):
						out.append("game '%s' can draw '%s' as '%s', which has no art in style '%s'"
							% [manifest.id, wearer, art, style_id])
	return out

func test_every_art_worn_gear_draws_a_fighter_with_is_art_somebody_has() -> void:
	# `worn_art` is joined to the cast by a bare string on each side, so a typo either way is valid in
	# its own file and silently wrong in play (docs/DECISIONS.md, M50.4).
	var faults := _worn_art_faults(_every_item(), GameSelect.manifests())
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()

func test_worn_art_for_a_body_nobody_is_or_art_nobody_drew_is_refused() -> void:
	# Each direction with its own fixture, and the control beside them: no shipped item names worn art
	# before M50.4's swords are given out, so the shipped check alone would pass having read nothing.
	var games: Array[GameManifest] = [_quest()]
	var typo := ItemDef.new()
	typo.id = &"typo_sword"
	typo.worn_art = {&"quest_wandrer": &"quest_wanderer_saber"}
	assert_str("\n".join(_worn_art_faults([typo], games))).contains("no game fights as")
	var undrawn := ItemDef.new()
	undrawn.id = &"undrawn_sword"
	undrawn.worn_art = {&"quest_wanderer": &"nobody_drew_this"}
	assert_str("\n".join(_worn_art_faults([undrawn], games))).contains("has no art")
	var saber := ItemDef.new()
	saber.id = &"saber"
	saber.worn_art = {&"quest_wanderer": &"quest_wanderer_saber"}
	assert_array(_worn_art_faults([saber], games)).is_empty()

## What is wrong with the arena of each of `manifests` whose leader could wear any of `items`: a fight
## whose floor, with the widest art in it, does not fit the screen. Per encounter, in the style of the
## map it is fought on, over every art the leader can wear and every foe the record fields - the arena
## draws the leader alone of the party. Returns the faults and how many fights were measured.
func _arena_fit_faults(manifests: Array[GameManifest], items: Array) -> Dictionary:
	var faults: Array[String] = []
	var fights := 0
	for manifest in manifests:
		if manifest.combat == null:
			continue
		for map in _maps_of(manifest):
			var style := load("res://data/styles/%s.tres" % map.style_id) as SpriteStyle
			for entry: Variant in map.enemies:
				var tile := JsonFile.to_int_array((entry as Dictionary).get("tile", []))
				if tile.size() != 2 or style == null:
					continue
				var arts := _arts_of(manifest.player_character, items)
				for named: Variant in map.enemy_at(Vector2i(tile[0], tile[1])).get("foes", []):
					var foe := load("res://data/enemies/%s.tres" % named) as EnemyDef
					if foe != null:
						arts.append(foe.character)
				var sheets: Array[SheetMeta] = []
				for art in arts:
					var file := JsonFile.read("res://assets/generated/%s/%s.sheet.json" % [map.style_id, art])
					if file.ok:
						sheets.append(SheetMeta.from_dict(file.data))
				fights += 1
				var reach := ArenaScreen.reach_of(sheets, FightScreen.fighter_scale(style))
				var tiles := manifest.combat.arena_tiles
				if not ArenaScreen.floor_fits(tiles, reach, UiScale.DESIGN_SIZE):
					faults.append("'%s' fights on '%s' with a %s floor drawn %s, past the %s screen"
						% [manifest.id, map.id, tiles, ArenaScreen.floor_size(tiles, reach),
						UiScale.DESIGN_SIZE])
	return {"faults": faults, "fights": fights}

func test_every_game_that_can_fight_fits_its_arena_on_the_screen_with_anything_it_can_wear() -> void:
	# The capacity rule's third part, for the arena, as a MEASURED FIT (docs/DECISIONS.md, M50.4).
	# ArenaScreen.floor_fits is the screen's own layout sums, test_arena_layout holds those sums to what
	# the screen draws, and this refuses a game by them - over the widest art each fight could draw, so
	# a longer sword on the smith's shelf is measured before anybody buys it. Every shipped game that can
	# fight, because since M51 any of them can be fought with the sword.
	var found := _arena_fit_faults(GameSelect.manifests(), _every_item())
	var faults: Array[String] = found["faults"]
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()
	assert_int(found["fights"]).override_failure_message(
		"no shipped fight was measured, so the loop above proved nothing").is_greater(0)

func test_a_game_whose_hero_can_wear_a_sword_too_long_for_its_floor_is_refused() -> void:
	# The longsword reaches 26 pixels past a 16-tile floor that the bronze sword fits, so the same game
	# at 16 tiles passes bare-handed, fails with the longsword to wear, and passes again at the 14 tiles
	# the demo ships. Each half of that is a different way for the gate to be wrong.
	var game := _quest().duplicate() as GameManifest
	game.combat = game.combat.duplicate() as CombatDef
	game.combat.arena_tiles = Vector2i(16, 4)
	var games: Array[GameManifest] = [game]
	var longsword := ItemDef.new()
	longsword.id = &"longsword"
	longsword.slot = &"weapon"
	longsword.worn_art = {&"quest_wanderer": &"quest_wanderer_longsword"}
	var bare: Array[String] = _arena_fit_faults(games, [])["faults"]
	assert_array(bare).override_failure_message("\n".join(bare)).is_empty()
	var armed: Array[String] = _arena_fit_faults(games, [longsword])["faults"]
	assert_str("\n".join(armed)).override_failure_message(
		"a hero who can wear the longsword was let onto a floor it reaches past").contains("past the")
	game.combat.arena_tiles = Vector2i(14, 4)
	var shipped: Array[String] = _arena_fit_faults(games, [longsword])["faults"]
	assert_array(shipped).override_failure_message("\n".join(shipped)).is_empty()

func test_the_arena_boss_is_won_by_reach_and_lost_by_walking_into_him() -> void:
	# The arena's whole difficulty statement, made of the fight the way the turn fight's is.
	#
	# The careless player is judged as a RATE over forty-eight seeds, where the turn fight's masher
	# loses every one of twelve. A turn fight is a menu; an arena is a room of bodies wandering at
	# random, and walking into the Keeper does beat him now and then - on 4 seeds of 48 when this was
	# written, and on 2 or 3 at every shorter flash tried. A claim that it never wins would have been
	# tuned to twelve particular seeds; that it almost never does is the fact. A change that made the
	# sword's reach decorative moves that count to most of the forty-eight.
	for seed_value in range(1, 13):
		var won := ArenaDriver.play(_arena_fight(BOSS, BOSS_LEVEL, seed_value),
			ArenaDriver.Policy.PERFECT)
		assert_bool(won.ended).override_failure_message(
			"the arena Keeper fight did not finish within the frame cap on seed %d" % seed_value).is_true()
		assert_int(won.outcome).override_failure_message(
			"a player who uses the sword's reach LOSES to the Keeper on seed %d, %d health left"
			% [seed_value, won.leader_hp]).is_equal(BattleLogic.Outcome.VICTORY)
	var careless_wins := 0
	for seed_value in range(1, CARELESS_SEEDS + 1):
		var lost := ArenaDriver.play(_arena_fight(BOSS, BOSS_LEVEL, seed_value),
			ArenaDriver.Policy.CHARGE)
		assert_bool(lost.ended).is_true()
		if lost.outcome == BattleLogic.Outcome.VICTORY:
			careless_wins += 1
	assert_int(careless_wins).override_failure_message(
		"a player who walks into the Keeper beat him on %d of %d seeds - the sword's reach is decorative"
		% [careless_wins, CARELESS_SEEDS]).is_less_equal(CARELESS_WINS_ALLOWED)

func test_no_shipped_formation_is_unwinnable_with_a_sword() -> void:
	# The turn fight's version of this plays one seed; an arena wanders at random, so it plays twelve.
	var combat := _quest().combat
	var top := combat.xp_curve.size() + 1
	var played := 0
	for entry: Variant in _encounters():
		var record_id: String = (entry as Dictionary)["id"]
		played += 1
		for seed_value in range(1, 13):
			var report := ArenaDriver.play(_arena_fight(record_id, top, seed_value),
				ArenaDriver.Policy.PERFECT)
			assert_bool(report.ended).override_failure_message(
				"the arena '%s' fight did not finish on seed %d" % [record_id, seed_value]).is_true()
			assert_int(report.outcome).override_failure_message(
				"'%s' cannot be won with the sword at level %d on seed %d"
				% [record_id, top, seed_value]).is_equal(BattleLogic.Outcome.VICTORY)
	assert_int(played).override_failure_message(
		"no encounter was played, so nothing above was checked").is_greater(1)

func test_every_arena_fight_is_won_by_the_sword_and_can_be_lost_to_a_touch() -> void:
	# A win is only evidence about the sword if the sword did the winning, and a loss only evidence
	# about the foes if they did the hurting: a formation that never moved would be beaten by both
	# policies for the wrong reason. So what happened is COUNTED, per shipped fight - every foe
	# struck at least once by the player who plays well, and the careless one touched at least once.
	var played := 0
	for entry: Variant in _encounters():
		var record_id: String = (entry as Dictionary)["id"]
		var foes := _defs_of(record_id).size()
		played += 1
		var well := ArenaDriver.play(_arena_fight(record_id, BOSS_LEVEL, 3), ArenaDriver.Policy.PERFECT)
		assert_int(well.hits).override_failure_message(
			"'%s' fields %d foes and the sword landed %d times" % [record_id, foes, well.hits]
			).is_greater_equal(foes)
		var careless := ArenaDriver.play(_arena_fight(record_id, BOSS_LEVEL, 3),
			ArenaDriver.Policy.CHARGE)
		assert_int(careless.touches).override_failure_message(
			"nothing in '%s' ever touched a player who walked into it" % record_id).is_greater(0)
	assert_int(played).is_greater(1)


func test_no_leader_outgrows_the_readout_the_arena_is_laid_out_for() -> void:
	# The third part of READOUT_CAPACITY's rule: ArenaScreen declares it, test_arena_layout measures a
	# leader at it beside the help line, and this refuses a shipped game whose leader could grow past it
	# - the top of the curve being the most health anybody reaches. Every game that can fight, because
	# since M51 any of them can be fought with the sword.
	var checked := 0
	for manifest in GameSelect.manifests():
		if manifest.combat == null:
			continue
		checked += 1
		var top := manifest.combat.xp_curve.size() + 1
		assert_int(manifest.combat.max_hp(top)).override_failure_message(
			"'%s' lets its leader reach %d health; the arena's panel is laid out for %d"
			% [manifest.id, manifest.combat.max_hp(top), ArenaScreen.READOUT_CAPACITY]
			).is_less_equal(ArenaScreen.READOUT_CAPACITY)
	assert_int(checked).is_greater(0)
