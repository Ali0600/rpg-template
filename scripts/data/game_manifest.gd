class_name GameManifest
extends Resource
## Which game this is, as data.
##
## Everything here used to be a `const` at the top of scripts/world/world_scene.gd - the
## first map, the spawn to stand on, whose sprite the player wears, the line of controls
## text - which meant a second game could not exist without editing the generic world code.
## The template's whole claim is that it does not need editing, so "which game is this" is
## the first thing that had to stop being code.
##
## A manifest is the ONLY file that names a game's content. Everything downstream is reached
## from here: the map names its style, the style names its rig, the characters are generated
## per style. Point this at different files and it is a different game.

## Used by Registry as this resource's key, and by --game= on the command line.
@export var id: StringName = &""

## Shown to a human, never matched on.
@export var title: String = ""

## Where a new game begins. The spawn must exist in that map, which problems() checks -
## a game whose first frame lands the player at (1,1) because a spawn name was misspelt is
## a bug that reads as a level-design mistake.
@export var start_map: StringName = &""
@export var start_spawn: StringName = &"start"

## The character spec whose generated sheet the player wears. It has to have been generated
## for the START MAP's style, since art is per style.
@export var player_character: StringName = &"hero"

## The feel of moving and interacting. A resource rather than a path so the reference is
## real: the exporter follows it, and a typo fails at load instead of at first step.
@export var config: GameConfig

## Who else fights beside the player. EMPTY IS NORMAL and is the template's default: a game
## with no party is a game with a party of one, which is Dragon Quest I's shape and a shipped
## genre shape rather than an absence. Real references rather than ids, for the reason `config`
## is one - the exporter follows them, and a typo fails at load.
##
## The LEADER IS NOT IN HERE. They are `player_character` plus `combat` above, synthesized into
## a member by the world, so this array holds companions only and a game that declares none
## still fights through exactly the same code. WHO of them is actually along is derived from
## flags at the moment it is asked (see PartyMemberDef.joins_on_flag) - this is the roster, not
## the party.
@export var party: Array[PartyMemberDef] = []

## Who the player is in a fight, how they grow, and how long a beat lasts. NULL IS NORMAL and
## is the template's default: a game with no battles has no combat definition, and a map that
## places an enemy in one is a content error the world reports rather than a crash. Kept off
## GameConfig so a peaceful game carries no battle knobs it will never turn.
@export var combat: CombatDef

## How this game SOUNDS. Null is normal and is the template's default: a game with no voice is
## a silent game, the same legal shape a null `combat` gives a game that cannot fight. A
## resource rather than an id for the reason `config` is one - the exporter follows a real
## reference, and a typo fails at load instead of at the first noise that does not happen.
@export var sound_style: SoundStyle

## The tune the title plays. A track id under data/music, not a Sfx.Cue, and that difference is
## the rule: template code names a CUE because a cue is the template's own vocabulary and a typo
## should be a compile error. A track is a game's content - nobody's template knows what a
## game's title sounds like - so it is named in data and validated on load, beside every other
## id here. Empty is normal: a game with no theme has a silent title, the same legal shape a
## null sound_style gives a silent game.
@export var title_music: StringName = &""

## The tune a fight plays, on title_music's exact terms. Empty is normal and means a fight
## sounds like wherever it happens - which is what every map with a theme did before this
## existed, so an empty field is not merely legal but is the old behaviour precisely.
@export var battle_music: StringName = &""

## The tune a WIN plays, once, before handing the room back to whatever the map states. A
## one-shot rather than a loop, and that is a property of how it is played rather than of the
## file: AudioBus.play_music_then is where a tune is declared to be a jingle.
##
## It cannot be called "victory" - MusicTrack.problems() refuses a track named after a cue, and
## Sfx.Cue.VICTORY is the sting that fires at the winning blow. The two are different sounds at
## different moments and the id has to say so.
@export var victory_music: StringName = &""

## The tune a GAME OVER plays. A loop, not a jingle: the screen sits there until the player
## chooses, so a one-shot would leave them in silence deciding what to do about it.
##
## It arrived in M32 because the code it replaced justified itself with a genre claim that is
## false. `_on_battle_finished` cut the music dead and said "every game this borrows from cuts
## the music at a game over" - and Final Fantasy I ships "Dead Music", a game-over theme, in
## 1987. The references do not fall silent at a death, they CHANGE what is playing, and each
## Final Fantasy has a different one. See docs/GENRE_CONVENTIONS.md §14.
##
## Empty keeps the silence exactly, which is what a game with nothing to say at a death wants
## and what every session recorded before M32 still hears.
@export var game_over_music: StringName = &""

## The one line of on-screen help. It belongs to the game because it names the game's verbs:
## "E or space to talk" is wrong for a game whose button does anything else.
## What the player starts with in their purse. Beside start_map and start_spawn because it is
## the same kind of fact - where the game begins - and a game with no economy leaves it zero.
@export var starting_gold: int = 0

@export var controls_hint: String = ""

## This game's own code: a GameHooks subclass, living under games/<id>/. Null is normal - a
## game whose whole design is expressible in maps and dialog has none, as the demo does not.
##
## A Script rather than a path string so the reference is real: the exporter follows it, and
## a rename fails at load rather than at the moment a player presses the button on a chest.
@export var hooks: Script


## A fresh instance of this game's hooks, or null if it has none. Fresh rather than shared
## because a hook holding state across two runs of the same game is a save bug waiting to
## happen, and there is exactly one caller.
func new_hooks() -> GameHooks:
	if hooks == null:
		return null
	if not hooks.can_instantiate():
		push_error("game '%s': hooks script cannot be instantiated" % id)
		return null
	var made: Variant = hooks.new()
	var typed := made as GameHooks
	if typed == null:
		push_error("game '%s': hooks script is not a GameHooks" % id)
	return typed


## Everything wrong with this manifest, in the idiom of every other problems() here: all of
## them, not the first, so "what is broken about this game" is one read rather than five runs.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("manifest has no id")
	if starting_gold < 0:
		out.append("manifest '%s' starts the player %d gold in debt" % [id, starting_gold])
	if String(start_map).is_empty():
		out.append("manifest '%s' names no start_map" % id)
		return out

	var map_path := MapData.path_of(start_map)
	var map := MapData.load_from(map_path)
	if not map.ok:
		out.append("start_map '%s' does not load: %s" % [start_map, map.error])
		return out
	if map.spawn(start_spawn) == Vector2i(-1, -1):
		out.append("map '%s' has no spawn '%s' (it has: %s)"
			% [start_map, start_spawn, ", ".join(map.spawn_ids())])

	# Art is generated per style, and the style comes from the map - so "this character
	# exists" is only answerable once you know which map the game opens in.
	var sheet := "res://assets/generated/%s/%s.sheet.json" % [map.style_id, player_character]
	if not FileAccess.file_exists(sheet):
		out.append("player_character '%s' has no generated art for style '%s' (expected %s)"
			% [player_character, map.style_id, sheet])

	if config == null:
		out.append("manifest '%s' has no config" % id)
	else:
		for p in config.problems():
			out.append("config: " + p)

	# Only when there is one: a game without battles is not a game with a broken CombatDef.
	if combat != null:
		for p in combat.problems():
			out.append("combat: " + p)

	# Every companion checked the way the leader is, and their art asked the same question
	# against the same style - a member whose sheet was never generated is an invisible
	# fighter, which reads as a broken screen rather than as missing content.
	var member_ids: Dictionary = {}
	for member: PartyMemberDef in party:
		if member == null:
			out.append("manifest '%s' lists a party member that is not there" % id)
			continue
		for p in member.problems():
			out.append("party: " + p)
		if member_ids.has(member.id):
			# Two members under one id means one save record for two people, and the second
			# would silently inherit the first's health.
			out.append("manifest '%s' lists party member '%s' twice" % [id, member.id])
		member_ids[member.id] = true
		if String(member.character).is_empty():
			continue
		var member_sheet := "res://assets/generated/%s/%s.sheet.json" % [map.style_id,
			member.character]
		if not FileAccess.file_exists(member_sheet):
			out.append("party member '%s' has no generated art for style '%s' (expected %s)"
				% [member.id, map.style_id, member_sheet])
	# A party with nobody to lead it is a manifest that cannot build a fight at all: members
	# grow on a curve, and without a CombatDef there is no curve for them to grow on.
	if not party.is_empty() and combat == null:
		out.append("manifest '%s' has a party of %d and no combat definition"
			% [id, party.size()])

	# Same shape, and same reason as the art check above: a voice whose cues were never
	# generated is a game that boots fine and is silent, which reads as "sound is not built
	# yet" rather than as a missing file.
	if sound_style != null:
		for p in sound_style.problems():
			out.append("sound: " + p)
		var cue := "res://assets/generated/%s/sfx/%s.wav" % [sound_style.id, Sfx.id_of(Sfx.Cue.FOOTSTEP)]
		if not FileAccess.file_exists(cue):
			out.append("sound_style '%s' has no generated cues (expected %s) - run tools/gen_sounds.gd"
				% [sound_style.id, cue])

	# The themes, same shape four times: a game naming a tune nobody rendered is a silence, and
	# silence is a legal shape here - so the only way to tell it from a misspelling is to check.
	# One loop rather than four copies, because the fourth copy is where the check goes stale -
	# and M32 adding a field to this list without touching a line of the check is the argument.
	for named: Array in [["title_music", title_music], ["battle_music", battle_music],
			["victory_music", victory_music], ["game_over_music", game_over_music]]:
		var field := String(named[0])
		var tune := StringName(named[1])
		if String(tune).is_empty():
			continue
		if sound_style == null:
			out.append("%s '%s' has no voice to play it in" % [field, tune])
			continue
		var track := "res://assets/generated/%s/music/%s.wav" % [sound_style.id, tune]
		if not FileAccess.file_exists(track):
			out.append("%s '%s' was never generated (expected %s) - run tools/gen_sounds.gd"
				% [field, tune, track])

	if hooks != null:
		var made := new_hooks()
		if made == null:
			out.append("hooks script %s is not a GameHooks" % hooks.resource_path)
		else:
			for p in made.problems():
				out.append("hooks: " + p)
	return out
