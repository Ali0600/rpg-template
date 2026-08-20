extends Node
## Plays sounds by name, from a game's voice and from whatever it drops in beside it.
##
## Two roots answer, and the order between them is the seam:
##
##   1. res://data/audio  - a game's OWN files. These WIN.
##   2. the generated cues for the game's SoundStyle.
##
## A game replaces one cue by dropping one file in, and never has to delete build output to do
## it - which matters because the drift gate would put that output straight back. It is the
## GameHooks rule one level down: a game is additive, or it is not using this seam.
##
## An unknown id warns rather than failing silently, and only once per id. A fallback that says
## nothing is how a missing sound survives to release: nobody notices a noise that was never
## there. That is also why template code never names a cue as a string - Sfx.Cue is an enum, so
## the warning is reserved for content, which is validated on load anyway.

const OVERRIDE_DIR := "res://data/audio"
const GENERATED_ROOT := "res://assets/generated"
const SOUND_EXTS: Array[String] = ["ogg", "wav", "mp3"]

## How many cues may sound at once. One player meant every cue cut the one before it, so a
## footstep silenced the dialog blip it landed on. Six is well past what this game stacks and
## costs nothing but nodes.
const VOICES := 6

## How many requests to remember. Bounded because this is an autoload that outlives every
## scene: an unbounded log is a leak that only shows up in a long session.
const LOG_LIMIT := 64

var _sounds: Dictionary = {}
var _warned: Dictionary = {}
var _overridden: Array[StringName] = []
var _duplicates: Array[StringName] = []
var _missing: Array[StringName] = []
var _requested: Array[StringName] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music := AudioStreamPlayer.new()
var _enabled := true
var _volume := 1.0
var _style: SoundStyle
var _override_dir := OVERRIDE_DIR
var _generated_root := GENERATED_ROOT


func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	add_child(_music)
	reload()
	EventBus.sound_requested.connect(_on_sound_requested)
	EventBus.system_ready.emit({"system": &"AudioBus"})


## Points the bus at a game's voice. Called when a game starts, because which cues exist is a
## property of the GAME, not of the process - and the bus outlives both.
##
## The roots are arguments so a test can point them somewhere without shipping fixture audio
## into data/audio, where it would become part of every game built on this template.
func use_style(style: SoundStyle, override_dir: String = OVERRIDE_DIR,
		generated_root: String = GENERATED_ROOT) -> void:
	_style = style
	_override_dir = override_dir
	_generated_root = generated_root
	reload()


func style_id() -> StringName:
	return _style.id if _style != null else &""


## Rebuilds the id table from both roots. Generated first, overrides second and last-writer -
## so the override wins by construction rather than by a branch that could be got backwards.
func reload() -> void:
	_sounds.clear()
	_warned.clear()
	_overridden.clear()
	_duplicates.clear()
	_missing.clear()

	if _style != null:
		for cue in Sfx.ids():
			var path := "%s/%s/sfx/%s.wav" % [_generated_root, _style.id, cue]
			if not ResourceLoader.exists(path):
				continue
			var generated := load(path) as AudioStream
			if generated != null:
				_sounds[cue] = generated

	var seen: Dictionary = {}
	for path in ContentScan.files(_override_dir, SOUND_EXTS):
		# Keyed by filename, not by path, so a game can file its sounds into subdirectories
		# without changing the id anything asks for.
		var id := StringName(path.get_file().get_basename())
		if seen.has(id):
			# Two files answering to one name. Registry reports duplicate ids rather than
			# letting the last one win in silence, and a sound is no different: the loser is
			# invisible, and which one loses depends on directory order.
			if not _duplicates.has(id):
				_duplicates.append(id)
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		seen[id] = true
		if _sounds.has(id):
			_overridden.append(id)
		_sounds[id] = stream

	if _style != null:
		for cue in Sfx.ids():
			if not _sounds.has(cue):
				_missing.append(cue)

	_report()


## One line, not one per cue: a game overriding its whole bank is doing the thing this is for,
## and twenty lines saying so is how a log stops being read.
func _report() -> void:
	if not _overridden.is_empty():
		print("AudioBus: %d generated cue(s) overridden from %s: %s"
			% [_overridden.size(), _override_dir, ", ".join(_as_strings(_overridden))])
	if not _duplicates.is_empty():
		push_error("AudioBus: %s answers to more than one file in %s - one of them is unreachable"
			% [", ".join(_as_strings(_duplicates)), _override_dir])
	if not _missing.is_empty():
		push_error("AudioBus: voice '%s' has no sound for %s"
			% [_style.id, ", ".join(_as_strings(_missing))])


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _sounds.keys():
		out.append(k)
	out.sort()
	return out


func has_sound(id: StringName) -> bool:
	return _sounds.has(id)


## The stream an id currently resolves to, or null. Exposed so a test can assert WHICH file
## won rather than that a flag was set - a precedence bug sets the same flags and binds the
## wrong audio, and only the bytes tell those apart.
func stream_for(id: StringName) -> AudioStream:
	return _sounds.get(id, null)


## Cues the game's own files replaced. Reported at boot and asserted by the suite, so the seam
## is observable rather than merely documented.
func overridden() -> Array[StringName]:
	return _overridden.duplicate()


## Ids more than one file answers to. Read by smoke_boot, the way Registry's are.
func duplicate_ids() -> Array[StringName]:
	return _duplicates.duplicate()


## Cues the current voice cannot play at all.
func missing_cues() -> Array[StringName]:
	return _missing.duplicate()


## What has been asked for lately, oldest first. The only way to assert a sound without a
## speaker: every gate here checks the id that was REQUESTED, never that audio was audible.
func requested() -> Array[StringName]:
	return _requested.duplicate()


func clear_requests() -> void:
	_requested.clear()


## Requests for names no cue has. A play session failing on a non-empty list turns AudioBus's
## warn-once - which fires into a log nobody is reading, in a build already shipped - into a
## red gate.
func unknown_requests() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _requested:
		if Sfx.of(id) < 0 and not out.has(id):
			out.append(id)
	return out


func set_enabled(value: bool) -> void:
	_enabled = value


## The player's chosen loudness, 0 to 1. Settings owns the VALUE and this owns the DEVICE, so
## there is one writer for each and neither has to know how the other stores it.
func set_volume(linear: float) -> void:
	_volume = clampf(linear, 0.0, 1.0)
	for player in _players:
		player.volume_db = linear_to_db(_volume)
	_music.volume_db = linear_to_db(_volume)


func volume() -> float:
	return _volume


func is_enabled() -> bool:
	return _enabled


## The way template code asks. A Cue cannot be misspelt, which is the whole reason it is an
## enum and not a string.
func play(cue: Sfx.Cue) -> bool:
	return play_sfx(Sfx.id_of(cue))


func play_sfx(id: StringName) -> bool:
	return _play(_next_player(), id)


func play_music(id: StringName) -> bool:
	return _play(_music, id)


func stop_music() -> void:
	_music.stop()


## Round-robin, so a cue does not cut the one before it. Assigning over a playing stream is
## exactly what made a footstep silence a dialog blip.
func _next_player() -> AudioStreamPlayer:
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	return player


func _play(player: AudioStreamPlayer, id: StringName) -> bool:
	# Logged BEFORE the lookup, and before the enabled check: what was asked for is a different
	# question from what could be played, and the tests and the play gate want the first one.
	_remember(id)
	if not _sounds.has(id):
		if not _warned.has(id):
			_warned[id] = true
			push_warning("AudioBus: no sound '%s' for voice '%s'" % [id, style_id()])
		return false
	if not _enabled:
		return false
	player.stream = _sounds[id]
	player.play()
	return true


func _remember(id: StringName) -> void:
	_requested.append(id)
	if _requested.size() > LOG_LIMIT:
		_requested.remove_at(0)


func _on_sound_requested(info: Dictionary) -> void:
	var id := StringName(str(info.get("id", "")))
	if str(info.get("kind", "sfx")) == "music":
		play_music(id)
	else:
		play_sfx(id)


func _as_strings(ids: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(id))
	return out
