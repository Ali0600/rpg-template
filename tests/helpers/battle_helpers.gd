class_name BattleHelpers
extends RefCounted
## Building a fight in a test, without every suite knowing how a party is spelled.
##
## `solo` exists because a party of one is what almost every rule here is about: the timing
## window, the damage floor, the level curve and the flee refusal are all one-fighter facts, and
## a suite that had to assemble a Fighter to test them would be testing the assembly. It is also
## the shape the world builds for a game that declares no party, so a rule proven through it is
## proven through the live path.


## The leader as the world synthesizes them: no id, named the word every message used before
## there was anyone else, and knowing whatever they were handed.
static func leader(combat: CombatDef, hp := 20, xp := 0, level := 1, mp := 8,
		attack_mod := 0, defense_mod := 0, spells: Array = []) -> BattleLogic.Fighter:
	return BattleLogic.Fighter.of(&"", "You", &"quest_wanderer", combat, hp, xp, level, mp,
		attack_mod, defense_mod, spells)


## A companion, who differs from the leader in exactly one thing that matters to the fight:
## they have an id, which is what the effect sink routes them by.
static func companion(id: StringName, combat: CombatDef, member_name := "Rook", hp := 16,
		xp := 0, level := 1, mp := 4, attack_mod := 0, defense_mod := 0,
		spells: Array = []) -> BattleLogic.Fighter:
	return BattleLogic.Fighter.of(id, member_name, &"quest_warden", combat, hp, xp, level, mp,
		attack_mod, defense_mod, spells)


## A fight with one member on the player's side against one foe - the shape a game with no party
## and a plain map record gets, and the shape almost every rule in the suite is about.
##
## It takes a bare `EnemyDef` and wraps it, which is why formations cost the suite almost
## nothing: some ninety assertions were written through this one function against a single
## enemy, and they say the same thing about a formation of one without moving.
static func solo(combat: CombatDef, enemy: EnemyDef, hp := 20, xp := 0, level := 1,
		items: Array = [], attack_mod := 0, defense_mod := 0, mp := 8,
		spells: Array = [], seed_value := 7) -> BattleLogic:
	return BattleLogic.of(combat, [enemy],
		[leader(combat, hp, xp, level, mp, attack_mod, defense_mod, spells)],
		items, "map/foe", seed_value)


## A fight against a formation, with one member on the player's side. The foe-side mirror of
## `solo`, for the rules that only exist once there is more than one thing to point at.
static func against(combat: CombatDef, enemies: Array, hp := 20, xp := 0, level := 1,
		items: Array = [], mp := 8, spells: Array = [], seed_value := 7) -> BattleLogic:
	return BattleLogic.of(combat, enemies,
		[leader(combat, hp, xp, level, mp, 0, 0, spells)], items, "map/foe", seed_value)
