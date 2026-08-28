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

	var map_path := "res://data/maps/%s.json" % start_map
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
		# A grid step that is not the map's tile size lands the player between tiles, forever
		# and increasingly. It can only be checked here: an actor holds a GameConfig and never
		# the map's SpriteStyle, so this is the one place both facts are in scope. Same scope
		# as the art check above - the START map's style, not every map's.
		if config.grid_step_pixels > 0:
			var style := load("res://data/styles/%s.tres" % map.style_id) as SpriteStyle
			if style != null and config.grid_step_pixels != style.tile_size:
				out.append("config steps %dpx but map '%s' draws %dpx tiles - a step that is not a tile lands the player between them"
					% [config.grid_step_pixels, start_map, style.tile_size])
		for p in config.problems():
			out.append("config: " + p)

	# Only when there is one: a game without battles is not a game with a broken CombatDef.
	if combat != null:
		for p in combat.problems():
			out.append("combat: " + p)

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

	if hooks != null:
		var made := new_hooks()
		if made == null:
			out.append("hooks script %s is not a GameHooks" % hooks.resource_path)
		else:
			for p in made.problems():
				out.append("hooks: " + p)
	return out
