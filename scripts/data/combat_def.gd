class_name CombatDef
extends Resource
## Who the player is in a fight, how they grow, and how long a beat lasts.
##
## The battle half of GameConfig, kept separate for the reason GameConfig is kept separate
## from GameManifest: these are the numbers a designer tries three values of, and a game with
## no battles should not carry them. A manifest with no `combat` is a game that cannot fight,
## which is the template's default and stays a legal shape forever.
##
## Every duration here is in PHYSICS FRAMES, not seconds. A battle is driven by tick() from a
## _physics_process, so a frame count is the unit the logic actually counts in - and a
## headless QA script pressing on frame N is then pressing at exactly the moment it means to.

## Used by Registry as this resource's key.
@export var id: StringName = &""

## The level-1 player, and what each level adds. Stats are DERIVED from level rather than
## stored, so a designer retuning the curve changes every existing save's player too - which
## is the point of a curve living in data.
@export var base_hp: int = 20
@export var hp_per_level: int = 4
@export var base_attack: int = 5
@export var attack_per_level: int = 2
@export var base_defense: int = 1
@export var defense_per_level: int = 1

## What each level-up costs, as TOTAL xp thresholds accumulated in order: element 0 is the
## cost of level 1 -> 2, element 1 of 2 -> 3. The maximum level is therefore size() + 1, and
## a curve is the one place "how long is this game" is written down.
@export var xp_curve: Array[int] = []

## How long the player's swing winds up before it lands. A press inside the last
## `timed_window_frames` of it is a timed hit.
@export var attack_cue_frames: int = 36

## How long an enemy telegraphs before its hit lands. Longer than the attack cue on purpose:
## reacting to someone else's move is harder than timing your own.
@export var defend_cue_frames: int = 48

## The window, at the END of a cue, in which a press counts. One number for both cues so
## "how forgiving is this game" is a single knob.
@export var timed_window_frames: int = 8

## How long a line of battle text stays up. Every message is the same length regardless of
## what it says, which is what makes a scripted battle a fixed frame schedule.
@export var message_frames: int = 45


func max_hp(level: int) -> int:
	return base_hp + hp_per_level * (maxi(level, 1) - 1)


func attack_at(level: int) -> int:
	return base_attack + attack_per_level * (maxi(level, 1) - 1)


func defense_at(level: int) -> int:
	return base_defense + defense_per_level * (maxi(level, 1) - 1)


## The level a total xp count buys. Walks the whole curve rather than dividing by a constant,
## because a curve that is not linear is the only reason to have one - and it stops at the
## end of the curve rather than extrapolating, so the maximum level is a fact of the data.
func level_for(total_xp: int) -> int:
	var level := 1
	var spent := 0
	for step: int in xp_curve:
		if total_xp < spent + step:
			break
		spent += step
		level += 1
	return level


## Total xp needed to reach the NEXT level, or -1 at the cap. Used by the battle screen to
## draw progress, and by tests to pin the thresholds from the outside.
func xp_for_next(level: int) -> int:
	if level < 1 or level > xp_curve.size():
		return -1
	var spent := 0
	for i in level:
		spent += xp_curve[i]
	return spent


## Everything wrong with this combat definition. All of them, not the first.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("combat has no id")
	if base_hp <= 0:
		out.append("combat '%s' starts the player on %d hp" % [id, base_hp])
	if base_attack <= 0:
		out.append("combat '%s' has %d base_attack" % [id, base_attack])
	if base_defense < 0:
		out.append("combat '%s' has %d base_defense" % [id, base_defense])
	if hp_per_level < 0 or attack_per_level < 0 or defense_per_level < 0:
		out.append("combat '%s' has a negative per-level gain" % id)
	# A curve with no entries is a game where levelling cannot happen. That may be someone's
	# design, but it is not this field's default meaning, and silence would make the two
	# indistinguishable.
	if xp_curve.is_empty():
		out.append("combat '%s' has an empty xp_curve - nothing can level up" % id)
	for i in xp_curve.size():
		if xp_curve[i] <= 0:
			out.append("combat '%s' xp_curve step %d costs %d" % [id, i, xp_curve[i]])
	if attack_cue_frames <= 0 or defend_cue_frames <= 0:
		out.append("combat '%s' has a cue with no frames in it" % id)
	if message_frames <= 0:
		out.append("combat '%s' shows messages for %d frames" % [id, message_frames])
	if timed_window_frames <= 0:
		out.append("combat '%s' has a timed window of %d frames - no press could land in it"
			% [id, timed_window_frames])
	# A window at least as long as the cue makes EVERY press a timed one, which reads in play
	# as a timing mechanic that does not work rather than as one that is switched off.
	elif timed_window_frames >= attack_cue_frames or timed_window_frames >= defend_cue_frames:
		out.append("combat '%s' has a timed window (%d) as long as a cue - every press would be perfect"
			% [id, timed_window_frames])
	return out
