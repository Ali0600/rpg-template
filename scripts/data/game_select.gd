class_name GameSelect
extends RefCounted
## Decides which game this run is, once, so every surface agrees.
##
## Four surfaces have to answer identically and they do not share a mechanism: the editor,
## the exported web build (no command line at all), a `-s tools/x.gd` run (no autoloads
## exist, which is why nothing here names one), and a QA run driving the real game. One
## precedence, evaluated in one place, is the only way those four cannot drift.
##
## It is a PRECEDENCE, not a search, and the last rule is the important one: with two games
## and nothing choosing between them this REFUSES rather than picking the first. Booting the
## wrong game does not look like a selection bug - it looks like a content bug in the game
## you meant to run, and you go and debug that instead.

const DIR := "res://data/games"

## Committed in project.godot next to run/main_scene, so it rides in the exported .pck and
## the editor, CI and the web build all read the same fact.
const SETTING := "application/config/game"

## The override, for QA and for tools. `--game=quest` rather than `--game quest`: an
## optional-value flag written with a space silently becomes a positional argument.
const ARG := "--game="

## The QA harness's flag. It lives here rather than in `Qa` because SaveManager reads it in
## `_ready()` to decide where saves go, and SaveManager is registered as an autoload BEFORE
## Qa - so naming `Qa` there would reach for a singleton that does not exist yet. This file
## already owns "what did the command line ask for", which is the same question.
const QA_ARG := "--qa-script="


## The precedence, as a pure function so it can be proven with literal arrays rather than by
## arranging a filesystem and a project setting. Returns "" when nothing chooses.
static func choose(ids: Array[String], args: PackedStringArray, setting: String) -> String:
	for arg in args:
		if arg.begins_with(ARG):
			return arg.substr(ARG.length())
	if not setting.is_empty():
		return setting
	if ids.size() == 1:
		return ids[0]
	return ""


## Every game manifest on disk, sorted by id.
static func manifests() -> Array[GameManifest]:
	var out: Array[GameManifest] = []
	for res in ContentScan.resources(DIR):
		var manifest := res as GameManifest
		if manifest != null and not String(manifest.id).is_empty():
			out.append(manifest)
	out.sort_custom(func(a: GameManifest, b: GameManifest) -> bool: return String(a.id) < String(b.id))
	return out


## Every game id on disk, sorted.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for manifest in manifests():
		out.append(String(manifest.id))
	return out


## The games a human still has to choose between: every manifest on disk, but ONLY when the
## precedence chose nothing AND there is more than one. Empty otherwise - including for the two
## failures a menu cannot fix (no manifests at all, or a --game= naming a game that does not
## exist), which resolve() still reports as errors. A menu with one entry, or none, is a worse
## answer than the message.
##
## This is NOT a second precedence. It asks choose() the same question resolve() asks, in the
## same file, so the two cannot drift - which is the whole reason this file exists.
static func unresolved() -> Array[GameManifest]:
	var all := manifests()
	var available: Array[String] = []
	for manifest in all:
		available.append(String(manifest.id))
	if not should_ask(available, args(), str(ProjectSettings.get_setting(SETTING, ""))):
		return []
	return all


## Whether a human still has to choose, as a pure function over the same three inputs choose()
## takes - because the process a test runs in has its own command line and its own setting, and
## neither can be staged. The rule they share can be, and this is it: more than one game, and
## nothing else having chosen.
static func should_ask(game_ids: Array[String], args_in: PackedStringArray, setting: String) -> bool:
	if game_ids.size() < 2:
		return false
	return choose(game_ids, args_in, setting).is_empty()


## What a mid-play switch may offer: every game, when there is more than one. Unlike
## unresolved() the precedence is irrelevant here - the player has already overruled it by
## asking. A separate function rather than a flag, so the two questions cannot be confused at a
## call site.
static func switchable() -> Array[GameManifest]:
	var all := manifests()
	if all.size() < 2:
		return []
	return all


## The command line, from both halves of it. `-s tools/x.gd --game=quest` lands in
## get_cmdline_args; `-- --qa-script=... --game=quest` lands in get_cmdline_user_args. One
## flag name has to work in both or the QA harness cannot reach a second game at all.
static func args() -> PackedStringArray:
	var out := OS.get_cmdline_args()
	out.append_array(OS.get_cmdline_user_args())
	return out


## The chosen manifest, or null with an error saying which of the three ways it failed.
## Null is deliberate: there is no safe default. Guessing a game is the failure this exists
## to prevent.
static func resolve() -> GameManifest:
	var all := manifests()
	var available: Array[String] = []
	for manifest in all:
		available.append(String(manifest.id))

	var chosen := choose(available, args(), str(ProjectSettings.get_setting(SETTING, "")))
	if chosen.is_empty():
		if available.is_empty():
			push_error("GameSelect: no game manifests in %s" % DIR)
		else:
			push_error("GameSelect: %d games (%s) and nothing chose between them - set %s in project.godot or pass %s<id>"
				% [available.size(), ", ".join(available), SETTING, ARG])
		return null

	# Matched on the id INSIDE the resource, not on the filename: those two can disagree,
	# and the id is what Registry, the setting and the command line all speak.
	for manifest in all:
		if String(manifest.id) == chosen:
			return manifest
	push_error("GameSelect: no game with id '%s' in %s (have: %s)" % [chosen, DIR, ", ".join(available)])
	return null
