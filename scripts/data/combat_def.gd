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

## What the player has to spend on spells, on exactly the terms hp is on. A curve rather than a
## stored pool for the reason every stat here is one, and it is also what the genre does: Final
## Fantasy VI, Dragon Quest and Chrono Trigger all size MP off the level, not off a resource
## farmed separately from it.
##
## ZERO BASE IS THE DEFAULT AND IT MEANS NO MAGIC, the "zero is off" shape ItemDef.battle_heal
## uses. A game that ships no spells never touches these, and its player then has nothing to
## spend and nothing to spend it on - which agree.
@export var base_mp: int = 0
@export var mp_per_level: int = 0

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

# -- the arena --------------------------------------------------------------------------------
#
# What a fight fought with a sword counts in (docs/GENRE_CONVENTIONS.md §7d). As above, a duration
# is PHYSICS FRAMES; a distance is TILES, so it means the same at any art size. They are validated
# whatever this game fights with, for the reason a companion's unused timing fields are: a number
# nothing reads today is the one that is wrong the day something does.

## How many frames a swing is live. The box in front of the player hurts for exactly this long,
## and no second swing begins until it ends. A Link to the Past's swing table walks to about 12.
@export var swing_frames: int = 12

## How far in front of the player the sword reaches, in tiles, from the edge of their body. It is
## as wide as the body is.
@export var swing_reach_tiles: float = 0.75

## How long the player cannot be hurt again after being hurt - and flickers for it, because the
## flicker is this counter made visible. Link's Awakening's spike trap sets 48.
@export var hurt_frames: int = 48

## The same for a foe the sword has struck: while it runs the foe cannot be struck again and
## cannot hurt anybody by touch, which is what A Link to the Past's hit timer does to both.
@export var foe_hurt_frames: int = 24

## How far a hit shoves what it hits, in tiles, and over how many frames. The player is shoved away
## from the foe that touched them, a struck foe away from the player. A WALL ENDS A SHOVE AND THE
## PROTECTION THAT CAME WITH IT (Link's Awakening's StopEntityRecoilOnCollision), so a body pinned
## against a wall can be hit again at once.
@export var push_tiles: float = 1.0
@export var foe_push_tiles: float = 1.0
@export var push_frames: int = 8

## How long a wandering foe holds a heading before drawing another, drawn inclusive between these.
## Link's Awakening's roaming enemies draw from 32 to 63.
@export var wander_min_frames: int = 32
@export var wander_max_frames: int = 63

## The floor, in tiles. The arena's screen declares how big a floor it can draw, and the content
## gate refuses a game that asks for more.
@export var arena_tiles: Vector2i = Vector2i(12, 4)


func max_hp(level: int) -> int:
	return base_hp + hp_per_level * (maxi(level, 1) - 1)


func max_mp(level: int) -> int:
	return base_mp + mp_per_level * (maxi(level, 1) - 1)


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
	# Separate from the gains above rather than folded in, because base_mp is allowed to be zero
	# where base_hp is not - so the pair has its own sentence and its own message.
	if base_mp < 0 or mp_per_level < 0:
		out.append("combat '%s' has negative magic - %d base, %d per level"
			% [id, base_mp, mp_per_level])
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
	# The arena's numbers, checked whatever style this is - see the fields.
	if swing_frames <= 0:
		out.append("combat '%s' swings for %d frames - no sword would ever be out" % [id, swing_frames])
	if swing_reach_tiles <= 0.0:
		out.append("combat '%s' reaches %s tiles with the sword - it would touch nothing"
			% [id, swing_reach_tiles])
	if hurt_frames <= 0 or foe_hurt_frames <= 0:
		out.append("combat '%s' protects a hit body for no frames - one touch would land every frame"
			% id)
	if push_tiles < 0.0 or foe_push_tiles < 0.0:
		out.append("combat '%s' shoves a hit body a negative distance" % id)
	if push_frames <= 0:
		out.append("combat '%s' delivers a shove over %d frames" % [id, push_frames])
	# A shove that outlasts the protection it came with slides a body into the next hit.
	elif push_frames > mini(hurt_frames, foe_hurt_frames):
		out.append("combat '%s' shoves for %d frames but protects for %d - a sliding body could be hit again"
			% [id, push_frames, mini(hurt_frames, foe_hurt_frames)])
	if wander_min_frames <= 0:
		out.append("combat '%s' lets a foe wander for %d frames" % [id, wander_min_frames])
	elif wander_min_frames > wander_max_frames:
		out.append("combat '%s' wanders between %d and %d frames - the range is backwards"
			% [id, wander_min_frames, wander_max_frames])
	if arena_tiles.x < 2 or arena_tiles.y < 2:
		out.append("combat '%s' has an arena of %s tiles - too small to stand apart in"
			% [id, arena_tiles])
	return out
