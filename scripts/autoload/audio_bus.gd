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
const MUSIC_SUBDIR := "music"
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
## What TRACKS have been asked for, in a log of their own. Separate from the cue log because
## unknown_requests() turns anything Sfx does not name into a red play gate - correct for a
## misspelled cue, and fatal for every track the moment music exists. Splitting the log keeps
## that gate exactly as strict about cues as it was.
var _music_requested: Array[StringName] = []
## The track playing now, so a second request for it is not a restart.
var _music_id: StringName = &""
var _missing_tracks: Array[StringName] = []
## How many times a track has actually been STARTED, as opposed to asked for. The only way to
## tell "still playing" from "started again" - the request log cannot, because the request is
## made either way, and the device cannot either: headless runs on a dummy driver where nothing
## ever reports itself as playing.
var _music_starts: int = 0
## What a ONE-SHOT track hands back to when it ends, and how many physics frames are left of it.
## A negative count means nothing is chained - zero would be indistinguishable from "ends this
## frame", which is a real state.
var _music_next: StringName = &""
var _music_left: int = -1
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
	_missing_tracks.clear()

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
		for track_id in MusicTrack.ids():
			var track_path := "%s/%s/%s/%s.wav" % [_generated_root, _style.id, MUSIC_SUBDIR,
				track_id]
			if _sounds.has(track_id):
				continue
			if not ResourceLoader.exists(track_path):
				_missing_tracks.append(track_id)
				continue
			var track_stream := load(track_path) as AudioStream
			if track_stream == null:
				_missing_tracks.append(track_id)
				continue
			# One table for cues and tracks, deliberately: the override walk above keys on
			# filename, so a game replaces a generated tune by dropping theme.ogg into its own
			# audio directory - the same seam that already replaces a cue, for free.
			# MusicTrack.problems() refusing a track named after a cue is what makes one table
			# safe.
			_sounds[track_id] = _looped(track_stream)

	_report()


## Music LOOPS and a cue does not, which is the whole difference between the two - a one-shot
## with a name is a cue, and the victory fanfare already is one.
##
## Set HERE rather than in the .import file for two reasons. project.godot pins WAV looping off
## for the whole project on purpose, and there is one importer_defaults entry per importer, so
## there is no second default to add; and a per-file sidecar would be a list maintained by hand,
## which that file's own comment argues against. The better reason is that a loop is a PLAYBACK
## fact and a sidecar is build output the drift gate regenerates - a setting living there would
## not survive the next generator run.
func _looped(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# In SAMPLES, not bytes - pinned in test_engine_assumptions.gd, because getting it wrong
		# halves the loop and sounds exactly like a shorter tune.
		wav.loop_end = wav.data.size() / 2
	return stream


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
	if not _missing_tracks.is_empty():
		push_error("AudioBus: voice '%s' cannot play %s"
			% [_style.id, ", ".join(_as_strings(_missing_tracks))])


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
	_music_requested.clear()


## What tracks have been asked for lately. A log of its own, read by assert_music the way
## requested() is read by assert_sound.
func music_requested() -> Array[StringName]:
	return _music_requested.duplicate()


## The track playing now, or empty. The only way to tell "still playing" from "started again".
func music_id() -> StringName:
	return _music_id


## Tracks the running voice cannot play at all. missing_cues() for music, read by the same
## assert_audio_ready and the same boot check - which is the assertion that only bites against
## a packed build, where a file committed without its .import is simply absent.
func missing_tracks() -> Array[StringName]:
	return _missing_tracks.duplicate()


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


## Plays `id` ONCE and then hands the room back to `then_id`, which loops - or to silence, when
## `then_id` is empty. A fight won in a quiet cave hands back to the cave's own quiet.
##
## Counted in PHYSICS FRAMES rather than driven by the player's `finished` signal, which is
## free and unconnected and would still be the wrong clock: headless runs on a dummy driver
## that never reports a stream as playing, so a signal from it is not something any gate here
## could rely on - the same measurement that made music_starts() exist. Frames are what every
## other timed thing in this project counts, and --fixed-fps 60 pins them.
##
## The one-shot is a DUPLICATE of the bound stream with looping off. Never a mutation of the
## table's copy: _play hands that same instance to every later caller, so switching its loop
## off here would leave the map's theme playing once and stopping. And never a flag in the
## track's own JSON either - whether a tune is a one-shot is a fact about how it is USED, not
## about the file, and this call is where that is said.
func play_music_then(id: StringName, then_id: StringName) -> bool:
	_music_requested.append(id)
	if _music_requested.size() > LOG_LIMIT:
		_music_requested.remove_at(0)
	var stream := _sounds.get(id, null) as AudioStream
	if stream == null:
		# A fanfare the voice cannot play must not eat the theme it was going to hand back to.
		# Failing toward the follower is the difference between a missing sting and a silent map.
		if not _warned.has(id):
			_warned[id] = true
			push_warning("AudioBus: no sound '%s' for voice '%s'" % [id, style_id()])
		return play_or_silence(then_id)
	var once := stream.duplicate() as AudioStream
	var wav := once as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_music_next = then_id
	# ceili, so a tune that is not a whole number of frames long is never cut short of itself.
	_music_left = ceili(once.get_length() * float(Engine.physics_ticks_per_second))
	# Deliberately NOT the no-restart guard: a jingle is an EVENT where a theme is a state, and
	# two wins in a row must sting twice.
	_music_id = id
	_music_starts += 1
	if not _enabled:
		return false
	_music.stream = once
	_music.play()
	return true


## What a PLACE sounds like: its named track, or silence when it names none.
##
## The one function for it, because three callers now need exactly this answer - entering a map,
## a fanfare handing the room back, and a fight that displaced a theme ending. Written out three
## times it is three copies of "a map states its music or states silence, never inherits", and
## the one that goes stale is the one nobody is looking at.
func play_or_silence(id: StringName) -> bool:
	if String(id).is_empty():
		stop_music()
		return true
	return play_music(id)


func play_music(id: StringName) -> bool:
	# Remembered before anything else, exactly as _play does: what was ASKED FOR is a different
	# question from what happened, and the gates want the first one.
	_music_requested.append(id)
	if _music_requested.size() > LOG_LIMIT:
		_music_requested.remove_at(0)
	# A track already playing keeps playing. Walking through a door between two rooms of one
	# town must not restart the theme from the top - it is the single most recognisable bug in
	# this genre, and the only place that can answer it is the one that knows what is playing.
	#
	# Answered from what the BUS believes rather than from the player's `playing` flag, which
	# was the first attempt: headless runs on a dummy driver that never reports playing, so the
	# guard could not fire in the one environment every gate runs in - a rule true only in a
	# build nobody tests. stop_music() clears this, and music loops rather than ending, so the
	# bus's record cannot go stale behind the device.
	if id == _music_id:
		return true
	# Starting anything new cancels a pending hand-back. A second fight beginning mid-fanfare
	# must not be interrupted a moment later by the last fight's chain firing into it - and the
	# rule is stated where a track actually STARTS, so every path that starts one gets it.
	_disarm_chain()
	_music_id = id
	_music_starts += 1
	return _play(_music, id, false)


func stop_music() -> void:
	_disarm_chain()
	_music.stop()
	_music_id = &""


## One physics frame of a chained one-shot. The bus has no other clock and wants none: this
## counts the same frames BattleLogic does, so a play session lands on the same frame twice.
func _physics_process(_delta: float) -> void:
	if _music_left < 0:
		return
	_music_left -= 1
	if _music_left > 0:
		return
	var next := _music_next
	_disarm_chain()
	play_or_silence(next)


func _disarm_chain() -> void:
	_music_next = &""
	_music_left = -1


## How many times a track has been started. A test asserting a theme did not restart cannot use
## the request log - the request happens either way - and cannot use the device either.
func music_starts() -> int:
	return _music_starts


## Round-robin, so a cue does not cut the one before it. Assigning over a playing stream is
## exactly what made a footstep silence a dialog blip.
func _next_player() -> AudioStreamPlayer:
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	return player


## `log_it` is false for music, which keeps its own log. The cue log feeds unknown_requests(),
## which fails a play session for anything Sfx does not name - correct and strict for a
## misspelled cue, and fatal for every track the moment music exists. Splitting the logs keeps
## that gate exactly as strict about cues as it was, rather than teaching it to shrug.
func _play(player: AudioStreamPlayer, id: StringName, log_it := true) -> bool:
	# Logged BEFORE the lookup, and before the enabled check: what was asked for is a different
	# question from what could be played, and the tests and the play gate want the first one.
	if log_it:
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
