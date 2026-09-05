class_name GameScaffold
extends RefCounted
## Every file a new game needs, as text, decided without touching a disk.
##
## The template's claim is that a game is files ADDED beside it - `docs/ARCHITECTURE.md` lists
## exactly what those files are, and has since M11. This turns that list into something a command
## can write, which is the difference between a claim and a check.
##
## Pure on purpose, and split from `tools/new_game.gd` for the reason `LintCore` is split from
## `tools/lint_rules.gd`: the TOOL gathers what exists on disk and hands it over as `known`, the
## TESTS hand the same shape in, and every rule below is then a function of its arguments. A
## planner that scanned for itself could not be shown a project it must refuse.
##
## `.tres` is emitted as TEXT rather than through ResourceSaver, which would drop the comments and
## re-order the fields: a scaffolded manifest should diff like `data/games/quest.tres` does, and
## read like something a person wrote.

## The one style a new game gets if it says nothing. Not a hidden preference - it is the style the
## demo is drawn in, so a scaffolded game looks like the thing the reader just played.
const STYLE_DEFAULT := "lpc32"

## A style whose id is also a voice speaks in its own; everything else falls back here. lpc32 has
## no SoundStyle of its own, which is why the demo draws in lpc32 and speaks in dusk16 - character
## sheets resolve under the MAP's style and cues under the VOICE's, and they are different
## namespaces that happen to share a spelling three times out of four.
const VOICE_FALLBACK := "dusk16"

const MOVEMENTS: Array[String] = ["free", "grid"]
const COMBATS: Array[String] = ["none", "turns"]

## The starter room: ten by seven, walled all the way round. The wall is not decoration -
## `MapData.problems` refuses a perimeter tile that is neither solid nor a warp, because a map with
## an open edge is one a player can walk out of.
const MAP_WIDTH := 10
const MAP_HEIGHT := 7
const SPAWN := Vector2i(4, 3)
## Beside the spawn, so a play session reaches them by holding one direction until a body stops it
## rather than by counting tiles.
const NPC_TILE := Vector2i(5, 3)

const GROUND := "grass"
const WALL := "wall"
const FLOOR_GLYPH := "."
const WALL_GLYPH := "#"

## A curve so a scaffolded game with fighting can actually level somebody up: CombatDef refuses an
## empty one, and it is the single field in that resource with no usable default.
const XP_CURVE: Array[int] = [20, 24]


## Everything wrong with what was asked for, before anything is written. Named refusals, in the
## idiom every problems() here uses - a wizard that wrote six files and then failed would leave a
## project that neither boots nor is worth keeping.
static func problems(options: Dictionary, known: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var want := resolved(options, known)
	var id := str(want["id"])
	if id.is_empty():
		out.append("a game needs an id: pass --id=<name>")
		return out
	if not _is_snake_case(id):
		out.append("id '%s' is not snake_case - it becomes a file name, a resource id and a "
			% id + "directory, so it may hold lower-case letters, digits and underscores only")
	if _list(known, "existing_ids").has(id):
		out.append("there is already a game called '%s'" % id)

	var style := str(want["style"])
	var styles := _list(known, "styles")
	if not styles.has(style):
		out.append("no art style '%s' - this project draws in: %s" % [style, ", ".join(styles)])
		return out

	var cast := _cast_of(known, style)
	if cast.is_empty():
		out.append("style '%s' has no generated characters at all, so nobody can be drawn in it"
			% style)
	for role in ["character", "npc"]:
		var who := str(want[role])
		if not cast.is_empty() and not cast.has(who):
			out.append("'%s' has no art in style '%s' - that style draws: %s"
				% [who, style, ", ".join(cast)])

	var voice := str(want["sound"])
	var voices := _list(known, "voices")
	if not voices.has(voice):
		out.append("no voice '%s' - this project speaks in: %s" % [voice, ", ".join(voices)])

	if not MOVEMENTS.has(str(want["movement"])):
		out.append("movement must be one of %s, got '%s'" % [MOVEMENTS, want["movement"]])
	if not GameConfig.SAVE_POLICIES.has(StringName(str(want["save"]))):
		out.append("save must be one of %s, got '%s'" % [GameConfig.SAVE_POLICIES, want["save"]])
	if not COMBATS.has(str(want["combat"])):
		out.append("combat must be one of %s, got '%s'" % [COMBATS, want["combat"]])
	return out


## What was asked for, with every unstated field filled in. Public because the tool PRINTS it: a
## default chosen by sort order is deterministic and arbitrary, and the only honest thing to do
## with an arbitrary choice is say which one it made.
static func resolved(options: Dictionary, known: Dictionary) -> Dictionary:
	var id := str(options.get("id", ""))
	var style := str(options.get("style", STYLE_DEFAULT))
	var cast := _cast_of(known, style)
	var voices := _list(known, "voices")
	return {
		"id": id,
		"title": str(options.get("title", "")) if not str(options.get("title", "")).is_empty()
			else _titled(id),
		"style": style,
		"character": str(options.get("character", "")) if not str(
			options.get("character", "")).is_empty() else _nth(cast, 0),
		"npc": str(options.get("npc", "")) if not str(options.get("npc", "")).is_empty()
			else _nth(cast, 1),
		"sound": str(options.get("sound", "")) if not str(options.get("sound", "")).is_empty()
			else (style if voices.has(style) else VOICE_FALLBACK),
		"movement": str(options.get("movement", MOVEMENTS[0])),
		"save": str(options.get("save", String(GameConfig.SAVE_ANYWHERE))),
		"combat": str(options.get("combat", COMBATS[0])),
		"hooks": bool(options.get("hooks", false)),
	}


## Every file the new game is made of, as project-relative path -> text. The caller decides where
## the root is, which is what lets the suites plan into user:// and the tool plan into res://.
##
## `root` is where those files will LIVE, and the manifest needs it because a `.tres` names its
## references absolutely. The distinction it encodes is the one that matters: a game's own config,
## combat definition and hooks travel with it, and the TEMPLATE's files - the scripts, the shared
## tuning, the voice - stay at res:// wherever the game is written, because they are not this
## game's to move.
static func plan(options: Dictionary, known: Dictionary, root: String = "res://") -> Dictionary:
	var want := resolved(options, known)
	var id := str(want["id"])
	var out := {}
	out["data/maps/%s_start.json" % id] = _map_text(want)
	out["data/dialog/%s_hello.json" % id] = _dialog_text(want)
	if _wants_own_config(want):
		out["data/config/%s.tres" % id] = _config_text(want)
	if str(want["combat"]) == "turns":
		out["data/combat/%s.tres" % id] = _combat_text(want)
	if bool(want["hooks"]):
		out["games/%s/%s_hooks.gd" % [id, id]] = _hooks_text(want)
	out["data/games/%s.tres" % id] = _manifest_text(want, root)
	# Always, and it is the difference between a game that exists and a game that is known to
	# work: check.sh runs every tests/fixtures/qa/<dir>/*.json with --game=<dir>, so a scaffolded
	# game joins the play gate the day it is made, with nobody editing the gate.
	out["tests/fixtures/qa/%s/boots.json" % id] = _session_text(want)
	return out


## A game shares data/game_config.tres unless its design actually asks for something else.
##
## The M11 lesson, stated as code: the demo shipped a config of its own whose only difference was
## a knob nobody had asked to turn, and the first person to play it asked what ELSE was different.
## A game that varies nothing is a control; a game that varies one thing has said why.
static func _wants_own_config(want: Dictionary) -> bool:
	return str(want["movement"]) == "grid" \
		or StringName(str(want["save"])) != GameConfig.SAVE_ANYWHERE


static func _map_text(want: Dictionary) -> String:
	var rows: Array[String] = []
	for y in MAP_HEIGHT:
		if y == 0 or y == MAP_HEIGHT - 1:
			rows.append(WALL_GLYPH.repeat(MAP_WIDTH))
			continue
		rows.append(WALL_GLYPH + FLOOR_GLYPH.repeat(MAP_WIDTH - 2) + WALL_GLYPH)
	var id := str(want["id"])
	return _json({
		"_readme": [
			"The first room of %s, written by tools/new_game.sh." % str(want["title"]),
			"",
			"Walled all the way round on purpose: MapData.problems refuses a perimeter tile that",
			"is neither solid nor a warp, because a map with an open edge is one the player walks",
			"off. Cut a door by putting a warp on a wall tile, the way the demo's maps do.",
			"",
			"The legend is the whole vocabulary of this map. Every glyph names a tile in the bank",
			"the style points at - add a row to the legend to use another one.",
		],
		"id": "%s_start" % id,
		"style": str(want["style"]),
		"legend": {FLOOR_GLYPH: GROUND, WALL_GLYPH: WALL},
		"ground": rows,
		"spawns": {"start": [SPAWN.x, SPAWN.y]},
		"npcs": [{
			"id": "greeter",
			"character": str(want["npc"]),
			"tile": [NPC_TILE.x, NPC_TILE.y],
			# Facing the spawn. Taken from Dir rather than written out, because a direction
			# spelled as a string literal is a build failure everywhere in this project.
			"facing": String(Dir.name_of(Dir.D.LEFT)),
			"dialog": "%s_hello" % id,
		}],
	})


static func _dialog_text(want: Dictionary) -> String:
	return _json({
		"_readme": [
			"One line, so the conversation seam has a worked example in this game's own files.",
			"A node needs `text` and the file needs a `start` naming one; everything else -",
			"a portrait, a `next` chain, `choices`, flags, items - is optional.",
		],
		"id": "%s_hello" % str(want["id"]),
		"start": "greet",
		"nodes": {
			"greet": {
				"speaker": "Stranger",
				"text": "Your game runs. Edit my line in data/dialog to change what I say.",
			},
		},
	})


## Where one of this game's own files will be, from the root it is being written to. res:// ends
## in a separator and a directory does not, and getting that wrong produces `res:/data`, which is a
## real path and a very confusing one.
static func _under(root: String, path: String) -> String:
	return root + path if root.ends_with("/") else "%s/%s" % [root, path]


static func _manifest_text(want: Dictionary, root: String) -> String:
	var id := str(want["id"])
	var refs: Array[Dictionary] = [
		{"type": "Script", "path": "res://scripts/data/game_manifest.gd", "id": "1_manifest"},
	]
	var config_path := _under(root, "data/config/%s.tres" % id) if _wants_own_config(want) \
		else "res://data/game_config.tres"
	refs.append({"type": "Resource", "path": config_path, "id": "2_config"})
	refs.append({"type": "Resource", "path": "res://data/sounds/%s.tres" % str(want["sound"]),
		"id": "3_sound"})
	var body: Array[String] = [
		'id = &"%s"' % id,
		'title = "%s"' % str(want["title"]),
		'start_map = &"%s_start"' % id,
		'start_spawn = &"start"',
		'player_character = &"%s"' % str(want["character"]),
		'config = ExtResource("2_config")',
		'sound_style = ExtResource("3_sound")',
	]
	if str(want["combat"]) == "turns":
		refs.append({"type": "Resource", "path": _under(root, "data/combat/%s.tres" % id),
			"id": "4_combat"})
		body.append('combat = ExtResource("4_combat")')
	if bool(want["hooks"]):
		refs.append({"type": "Script", "path": _under(root, "games/%s/%s_hooks.gd" % [id, id]),
			"id": "5_hooks"})
		body.append('hooks = ExtResource("5_hooks")')
	body.append('controls_hint = "WASD / arrows to walk    E or space to look    Esc to pause"')
	return _tres("GameManifest", refs, "1_manifest", body, [
		"%s, scaffolded by tools/new_game.sh." % str(want["title"]),
		"",
		"This file is the whole answer to \"which game is running\": its first map, where the",
		"player stands in it, who they are, the tuning it uses and the voice it speaks in.",
		"",
		"It is not chosen automatically. With more than one game in data/games and nothing",
		"picking between them the boot REFUSES rather than guessing, so either set",
		"application/config/game in project.godot or run the game with --game=%s." % str(want["id"]),
	])


static func _config_text(want: Dictionary) -> String:
	var body: Array[String] = ['id = &"%s"' % str(want["id"])]
	var why: Array[String] = []
	if str(want["movement"]) == "grid":
		body.append("grid_step = true")
		why.append("one press is one whole tile, rather than free pixel movement")
	if StringName(str(want["save"])) != GameConfig.SAVE_ANYWHERE:
		body.append('save_policy = &"%s"' % str(want["save"]))
		why.append("saving happens at a save point, so the pause menu has no Save row")
	return _tres("GameConfig", [
		{"type": "Script", "path": "res://scripts/data/game_config.gd", "id": "1_config"},
	], "1_config", body, [
		"%s's own tuning, and it exists because this game asked for something the" % str(want["title"]),
		"template's default does not do: %s." % "; ".join(why),
		"",
		"Nothing else is stated, deliberately. A game that varies a knob its design did not ask",
		"about turns every difference a player feels into a suspected defect - so state the axis",
		"you meant to move and inherit the rest.",
		"",
		"Every distance here is in TILES, so it means the same thing at any art size.",
	])


static func _combat_text(want: Dictionary) -> String:
	return _tres("CombatDef", [
		{"type": "Script", "path": "res://scripts/data/combat_def.gd", "id": "1_combat"},
	], "1_combat", [
		'id = &"%s"' % str(want["id"]),
		"xp_curve = Array[int](%s)" % str(XP_CURVE),
	], [
		"How fighting works in %s. A game with no combat definition simply cannot" % str(want["title"]),
		"fight, and that is a legal shape forever - this file is here because one was asked for.",
		"",
		"xp_curve is the one field with no usable default: it is what each level costs, and an",
		"empty curve is a game where nothing can level up, which CombatDef refuses.",
	])


static func _hooks_text(want: Dictionary) -> String:
	var id := str(want["id"])
	return "\n".join([
		"extends GameHooks",
		"## %s's own code, and the only file of it this game is allowed." % str(want["title"]),
		"##",
		"## Every method here is optional: override the verbs this game actually has and leave the",
		"## rest. Returning false from on_interact means \"not mine\", and the template's own",
		"## behaviour runs - which is what keeps a game additive rather than a fork.",
		"##",
		"## Two rules apply here and nowhere else, both enforced by the build rather than by",
		"## convention. This file may NOT name an autoload - no GameState, no Router, no EventBus -",
		"## because Godot's parse gate skips any script that does, so it would silently leave two",
		"## of the four gates. Read the GameContext you are handed instead. And everything the",
		"## template promises, game code promises too: colours from the style, directions from Dir,",
		"## randomness from SeededRng.",
		"",
		"",
		"## Called after a map is built and the player is standing in it.",
		"func on_map_entered(_ctx: GameContext) -> void:",
		"\tpass",
		"",
		"",
		"## First refusal on every interaction. Answer true only for the targets this game means to",
		"## handle itself; false lets the map's own data decide.",
		"func on_interact(_ctx: GameContext, _target: Interactor.Target) -> bool:",
		"\treturn false",
		"",
		"",
		"## The conversations this game opens from here, which no map record names. A content gate",
		"## walks the maps to find out what a game owns, and cannot see inside a branch.",
		"func dialog_ids() -> Array[StringName]:",
		"\tvar out: Array[StringName] = []",
		"\treturn out",
		"",
		"",
		"## Everything wrong with this game's own content, reported the way the template reports",
		"## its own, and joined to the same gate.",
		"##",
		"## What belongs here is anything THIS FILE names as a bare string - a dialog id, an item",
		"## id, a flag - because nothing in data can notice one of those going missing. The map",
		"## already names the greeting, so it is already checked; this file names nothing yet.",
		"func problems() -> Array[String]:",
		"\tvar out: Array[String] = []",
		"\treturn out",
		"",
	])


static func _session_text(want: Dictionary) -> String:
	var id := str(want["id"])
	return _json({
		"_readme": [
			"%s boots, and somebody in it can be talked to." % str(want["title"]),
			"",
			"check.sh runs every script under tests/fixtures/qa/<game>/ with --game=<that",
			"directory>, so this game is inside the play gate without the gate being edited.",
			"",
			"The walk east is held until the greeter's BODY stops it rather than counted in tiles:",
			"an NPC is a wall, and a leg that counts tiles is one that lies the day the room",
			"changes shape.",
		],
		"steps": [
			{"op": "note", "text": "a --qa-script run points saves at user://qa_saves and empties"
				+ " it at boot, so there is never anything to continue and the cursor opens on New"
				+ " game. Rows: Continue, New game. One press starts the run."},
			{"op": "assert_state", "state": "title"},
			{"op": "press", "action": "interact"},
			{"op": "wait", "frames": 10},
			{"op": "assert_state", "state": "world"},
			{"op": "assert_map", "map": "%s_start" % id},
			{"op": "assert_position", "tile": [SPAWN.x, SPAWN.y]},
			{"op": "note", "text": "east until the greeter stops us, which also turns us to face"
				+ " them - facing is what decides who you talk to."},
			{"op": "hold", "action": "move_right", "frames": 40},
			{"op": "release_all"},
			{"op": "wait", "frames": 3},
			{"op": "press", "action": "interact"},
			{"op": "wait", "frames": 10},
			{"op": "assert_state", "state": "dialog"},
			{"op": "press_until_state", "action": "interact", "state": "world", "limit": 60},
			{"op": "assert_state", "state": "world"},
		],
	})


## A resource file the way this project writes them: a header, the comments, the external
## references, then the fields. JSON.stringify's own tab indent and trailing newline are matched by
## JsonFile.write, so both kinds of output diff the same way.
static func _tres(script_class: String, refs: Array[Dictionary], script_ref: String,
		body: Array[String], comments: Array[String]) -> String:
	var lines: Array[String] = [
		'[gd_resource type="Resource" script_class="%s" load_steps=%d format=3]'
			% [script_class, refs.size() + 1],
		"",
	]
	for comment in comments:
		lines.append(("; " + comment) if not comment.is_empty() else ";")
	lines.append("")
	for ref in refs:
		lines.append('[ext_resource type="%s" path="%s" id="%s"]'
			% [ref["type"], ref["path"], ref["id"]])
	lines.append("")
	lines.append("[resource]")
	lines.append('script = ExtResource("%s")' % script_ref)
	lines.append_array(body)
	lines.append("")
	return "\n".join(lines)


static func _json(value: Dictionary) -> String:
	return JSON.stringify(value, "\t") + "\n"


static func _is_snake_case(id: String) -> bool:
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return re != null and re.search(id) != null


static func _titled(id: String) -> String:
	var words := PackedStringArray()
	for word in id.split("_", false):
		words.append(word.capitalize())
	return " ".join(words)


static func _list(known: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in (known.get(key, []) as Array):
		out.append(str(entry))
	return out


static func _cast_of(known: Dictionary, style: String) -> Array[String]:
	var by_style: Dictionary = known.get("characters_by_style", {})
	var out: Array[String] = []
	for entry: Variant in (by_style.get(style, []) as Array):
		out.append(str(entry))
	return out


## The nth character in a style's cast, wrapping, so a style that draws exactly one person still
## answers for both the player and the greeter rather than refusing.
static func _nth(cast: Array[String], at: int) -> String:
	if cast.is_empty():
		return ""
	return cast[at % cast.size()]


## What this project currently has, in the shape `plan` and `problems` take.
##
## The one impure function here, and it reads only. It lives beside the planner rather than in the
## tool so that the wizard and the suite that boots a scaffolded game ask the same question of the
## same directories - two implementations of "which characters does this style have" would drift,
## and the gate would end up certifying a project nobody runs.
static func known_from_disk() -> Dictionary:
	var styles: Array[String] = []
	var cast := {}
	for path in ContentScan.files_of("res://data/styles", "tres"):
		var style := load(path) as SpriteStyle
		if style == null:
			continue
		var id := String(style.id)
		styles.append(id)
		var drawn: Array[String] = []
		for sheet in ContentScan.files_of("res://assets/generated/%s" % id, "json"):
			var name := sheet.get_file()
			if name.ends_with(".sheet.json"):
				drawn.append(name.trim_suffix(".sheet.json"))
		drawn.sort()
		cast[id] = drawn
	var voices: Array[String] = []
	for path in ContentScan.files_of("res://data/sounds", "tres"):
		var voice := load(path) as SoundStyle
		if voice != null:
			voices.append(String(voice.id))
	styles.sort()
	voices.sort()
	return {
		"styles": styles,
		"characters_by_style": cast,
		"voices": voices,
		"existing_ids": GameSelect.ids(),
	}
