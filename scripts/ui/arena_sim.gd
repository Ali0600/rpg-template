class_name ArenaSim
extends RefCounted
## A fight fought with a sword, as rules: no nodes, no singletons, no files and no clock.
##
## The second way this template resolves an encounter (docs/DECISIONS.md, M49 and M50), and it
## keeps BattleLogic's discipline exactly. `tick()` is ONE physics frame, handed in by the screen,
## so a whole fight fits in a loop, a scripted session replays on any machine, and a balance gate
## plays it to the end with opposed policies and no scene at all. Everything a fight is FOR is on
## the far side of the seam and unchanged: the world opens it, reads `finished()`, `outcome()` and
## `effects()`, and applies what arrives. What a win is worth goes through BattleLogic's own
## statics, so the award, the level-up and the seal are one set of lines for both resolvers.
##
## INTEGER, all the way down. A position is 256ths of a tile in a Vector2i, a heading is -1, 0 or 1
## per axis, a speed is carried forward as a remainder, and every box is a Rect2i. A replay is held
## to recorded numbers on a Mac and on the Linux runner, and a float may differ between two builds
## of one engine in its last place - which, over a thousand frames, is a box test flipping on one
## seed. See docs/DECISIONS.md.
##
## A position is the CENTRE of a body's footprint: the box at its feet it touches and is hit with,
## the shape the world's own collision box is. The screen stands a sprite's feet on its bottom edge.
##
## Every draw comes from ONE stream, `derive("arena")` off the fight's seed. `moves` and `target`
## belong to the turn fight, and a third reader of either would shift every replay recorded
## against it.

const UNITS_PER_TILE := 256
## Physics frames a second. A pure class cannot ask the engine, and a speed in tiles a second needs
## a rate; test_arena_sim pins this against the project's own setting.
const TICKS_PER_SECOND := 60
## What one frame's worth of a speed is divided by: a speed is units a second, scaled by `along`'s
## 256ths, so a frame's share of it is that over both.
const STRIDE := TICKS_PER_SECOND * UNITS_PER_TILE
## One over the square root of two, in 256ths (181/256 is 0.7070): a diagonal step is this much of
## a straight one on each axis, so holding two keys is not 41% faster.
const DIAGONAL := 181
## What a wanderer draws from when its countdown ends: standing still, or one of the four ways.
## The ORDER is part of every replay.
const WANDER_HEADINGS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
## How far an input axis must be pushed to count. A keyboard is exactly 0 or 1; a stick resting a
## little off true would otherwise walk every straight line on a diagonal.
const AXIS_THRESHOLD := 0.5


## A speed carried forward frame to frame, so a body making 12.8 units a frame moves 12, 13, 13,
## 13, 13 and covers exactly its speed over a second, with no fraction ever stored.
class Pace extends RefCounted:
	var carried_x := 0
	var carried_y := 0

	func step(heading: Vector2i, speed: int) -> Vector2i:
		var per := speed * ArenaSim.along(heading)
		carried_x = 0 if heading.x == 0 else carried_x + per
		carried_y = 0 if heading.y == 0 else carried_y + per
		var whole := Vector2i(ArenaSim.whole_units(carried_x), ArenaSim.whole_units(carried_y))
		carried_x -= whole.x * ArenaSim.STRIDE
		carried_y -= whole.y * ArenaSim.STRIDE
		return Vector2i(whole.x * heading.x, whole.y * heading.y)


## One foe on the floor: the fight's Foe - its numbers, its lettered name, whether it is down - and
## where it stands and what it is doing.
class Body extends RefCounted:
	var foe: BattleLogic.Foe
	var slot: int = 0
	var pos := Vector2i.ZERO
	var size := Vector2i.ZERO
	var speed: int = 0
	var facing: Dir.D = Dir.D.DOWN
	var heading := Vector2i.ZERO
	var pace := Pace.new()
	var hurt_left: int = 0
	var shove := Vector2i.ZERO
	var shove_left: int = 0
	var countdown: int = 0
	var moved := false


var _combat: CombatDef
## Everyone on the player's side. Only the first stands on the floor; every one of them shares a
## win, which is the owner's call (docs/DECISIONS.md, M50).
var _members: Array = []
var _leader: BattleLogic.Fighter
var _foes: Array = []
var _bodies: Array = []
var _seen_key := ""
var _rng: SeededRng
var _floor := Rect2i()
var _allow_diagonal := true
var _pos := Vector2i.ZERO
var _size := Vector2i.ZERO
var _speed: int = 0
var _pace := Pace.new()
var _facing: Dir.D = Dir.D.UP
var _moved := false
var _swing_left: int = 0
var _hurt_left: int = 0
var _shove := Vector2i.ZERO
var _shove_left: int = 0
## Foes this swing has already landed on, by slot, so one swing is one hit on each.
var _struck := {}
var _last_struck: int = -1
var _reach: int = 0
var _shove_units: int = 0
var _foe_shove_units: int = 0
var _frame: int = 0
var _outcome: BattleLogic.Outcome = BattleLogic.Outcome.NONE
var _effects: Array[Dictionary] = []
var _sounds: Array[StringName] = []
var _swings: int = 0
var _hits: int = 0
var _touches: int = 0


## Builds a fight. Everything arrives already resolved, as BattleLogic's does, because this class
## may not look anything up. `members` holds the leader first, and there is always one. `config`
## is read in TILES only, so an unbound one is fine: speed, body and whether diagonals are allowed.
static func of(combat: CombatDef, enemies: Array, members: Array, seen_key: String,
		seed_value: int, config: GameConfig) -> ArenaSim:
	var out := ArenaSim.new()
	out._combat = combat
	out._members = members.duplicate()
	out._leader = members[0] as BattleLogic.Fighter
	out._seen_key = seen_key
	out._rng = SeededRng.new(seed_value).derive("arena")
	out._floor = Rect2i(Vector2i.ZERO, combat.arena_tiles * UNITS_PER_TILE)
	out._allow_diagonal = config.allow_diagonal
	out._speed = units(config.walk_tiles_per_second)
	out._size = Vector2i(units(config.body_tiles.x), units(config.body_tiles.y))
	out._reach = units(combat.swing_reach_tiles)
	out._shove_units = units(combat.push_tiles)
	out._foe_shove_units = units(combat.foe_push_tiles)
	out._foes = BattleLogic.formation(enemies)
	var count := out._foes.size()
	for i in count:
		var body := Body.new()
		body.foe = out._foes[i] as BattleLogic.Foe
		body.slot = i
		body.size = Vector2i(units(body.foe.def.body_tiles.x), units(body.foe.def.body_tiles.y))
		body.speed = units(body.foe.def.speed_tiles_per_second)
		# Spread along the far wall in the order the record named them, the player across from
		# them at the near one: nobody starts within reach of anybody.
		var spot := Vector2i(out._floor.size.x * (i + 1) / (count + 1), UNITS_PER_TILE / 2)
		body.pos = out._clamped(spot, body.size)
		out._bodies.append(body)
	var home := Vector2i(out._floor.size.x / 2, out._floor.size.y - UNITS_PER_TILE / 2)
	out._pos = out._clamped(home, out._size)
	return out


## A distance in tiles as units, rounded once when the fight is built and never again.
static func units(tiles: float) -> int:
	return roundi(tiles * UNITS_PER_TILE)


## How much of a step each axis takes on a heading: all of one straight, DIAGONAL/256 of one each
## way on a diagonal.
static func along(heading: Vector2i) -> int:
	if heading.x != 0 and heading.y != 0:
		return DIAGONAL
	return UNITS_PER_TILE


## The whole units a carried amount has earned.
static func whole_units(carried: int) -> int:
	return carried / STRIDE


## The heading an input asks for, -1, 0 or 1 per axis. An axis counts once it is pushed at least
## AXIS_THRESHOLD of the way, and with diagonals off the dominant one wins by Locomotion's own tie
## rule, so a key held in the arena turns the player the way it turns them on the map.
static func heading_of(input: Vector2, allow_diagonal: bool) -> Vector2i:
	var pressed := Vector2(_axis(input.x), _axis(input.y))
	if not allow_diagonal:
		pressed = Locomotion.axis_locked(pressed)
	return Vector2i(pressed)


static func _axis(value: float) -> int:
	if absf(value) < AXIS_THRESHOLD:
		return 0
	return 1 if value > 0.0 else -1


## One of eight ways toward `delta`. An axis counts unless it is under half the other, so a foe a
## little off the line is chased, and shoved, along the line rather than on a diagonal.
static func direction_of(delta: Vector2i) -> Vector2i:
	var x := signi(delta.x)
	var y := signi(delta.y)
	if absi(delta.x) * 2 < absi(delta.y):
		x = 0
	elif absi(delta.y) * 2 < absi(delta.x):
		y = 0
	return Vector2i(x, y)


static func _box(centre: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(centre - size / 2, size)


# -- one frame ----------------------------------------------------------------------------------


## One physics frame: the player, the blade, the foes, the touch, the countdowns, the verdict - in
## that order, which is part of every replay. `swing` is a REQUEST for this frame; the screen turns
## a press into exactly one, so holding the button is one swing and mashing is one per re-arm.
func tick(input: Vector2, swing: bool) -> void:
	if _outcome != BattleLogic.Outcome.NONE:
		return
	_frame += 1
	_step_player(input, swing)
	_strike()
	for body: Body in _bodies:
		_step_foe(body)
	_touch()
	_count_down()
	_decide()


func _step_player(input: Vector2, swing: bool) -> void:
	if swing and _swing_left == 0 and _shove_left == 0:
		_swing_left = _combat.swing_frames
		_struck.clear()
		_swings += 1
		_want(Sfx.Cue.SWING)
	var was := _pos
	var shoved := _shove_left > 0
	if shoved:
		_pos += _shove
		_shove_left -= 1
	elif _swing_left > 0:
		# Rooted, facing locked: the sword stays where it was pointed when the button went down.
		pass
	else:
		var heading := heading_of(input, _allow_diagonal)
		if heading != Vector2i.ZERO:
			_facing = Dir.facing_from_vector(Vector2(heading), _facing)
		_pos += _pace.step(heading, _speed)
	var kept := _clamped(_pos, _size)
	if kept != _pos:
		_pos = kept
		if shoved:
			# A wall ends the shove and the protection that came with it, so a player pinned
			# against a wall can be hit again at once.
			_shove_left = 0
			_hurt_left = 0
	_moved = _pos != was


## The blade: every standing foe the live sword box meets, once a swing, unless it is still
## flashing from the last blow.
func _strike() -> void:
	if _swing_left <= 0:
		return
	var blade := sword_box()
	for body: Body in _bodies:
		if body.foe.down() or _struck.has(body.slot):
			continue
		if body.hurt_left > 0:
			continue
		if not blade.intersects(_box(body.pos, body.size)):
			continue
		var took := BattleLogic.damage(BattleLogic.attack_of(_leader),
			BattleLogic.foe_defense(body.foe))
		body.foe.hp = maxi(body.foe.hp - took, 0)
		_struck[body.slot] = true
		_last_struck = body.slot
		_hits += 1
		_want(Sfx.Cue.HIT)
		if body.foe.down():
			continue
		body.hurt_left = _combat.foe_hurt_frames
		body.shove = _shove_toward(body.pos - _pos, _foe_shove_units, Dir.vector_of(_facing))
		body.shove_left = _combat.push_frames


func _step_foe(body: Body) -> void:
	body.moved = false
	if body.foe.down():
		return
	var was := body.pos
	var shoved := body.shove_left > 0
	if shoved:
		# A recoiling foe skips its own routine for the frame, as A Link to the Past's
		# Sprite_ReturnIfRecoiling has it.
		body.pos += body.shove
		body.shove_left -= 1
	else:
		_steer(body)
		body.pos += body.pace.step(body.heading, body.speed)
	var kept := _clamped(body.pos, body.size)
	if kept != body.pos:
		body.pos = kept
		if shoved:
			body.shove_left = 0
			body.hurt_left = 0
		elif body.foe.def.chase_every_frames == 0:
			# A wanderer turns when it meets a wall, the way A Link to the Past's rat does.
			body.heading = -body.heading
	if body.heading != Vector2i.ZERO:
		body.facing = Dir.facing_from_vector(Vector2(body.heading), body.facing)
	body.moved = body.pos != was


func _steer(body: Body) -> void:
	var every := body.foe.def.chase_every_frames
	if every > 0:
		# A Link to the Past's guards re-aim once every 32 frames, offset by their slot, and hold
		# the heading in between: chasing is a periodic re-aim, not homing on every frame.
		if (_frame + body.slot) % every == 0:
			body.heading = direction_of(_pos - body.pos)
		return
	if body.countdown > 0:
		body.countdown -= 1
		return
	# Link's Awakening's roaming enemies draw a fresh countdown, then a way to go. The two draws
	# happen in this order on every frame a countdown ends, which is what makes a replay a replay.
	body.countdown = _rng.next_int(_combat.wander_min_frames, _combat.wander_max_frames)
	body.heading = WANDER_HEADINGS[_rng.next_int(0, WANDER_HEADINGS.size() - 1)]


## Touching a foe hurts, unless the player is still protected from the last touch or the foe is
## still flashing from a blow - the counter A Link to the Past guards both with.
func _touch() -> void:
	if _hurt_left > 0:
		return
	var mine := player_box()
	for body: Body in _bodies:
		if body.foe.down() or body.hurt_left > 0:
			continue
		if not mine.intersects(_box(body.pos, body.size)):
			continue
		var took := BattleLogic.damage(BattleLogic.foe_attack(body.foe),
			BattleLogic.defense_of(_leader))
		_leader.hp = maxi(_leader.hp - took, 0)
		_hurt_left = _combat.hurt_frames
		_shove = _shove_toward(_pos - body.pos, _shove_units, -Dir.vector_of(_facing))
		_shove_left = _combat.push_frames
		# Being hit takes the sword away, the way A Link to the Past's incapacitated timer takes
		# control.
		_swing_left = 0
		_touches += 1
		_want(Sfx.Cue.HURT)
		return


func _count_down() -> void:
	_hurt_left = maxi(_hurt_left - 1, 0)
	_swing_left = maxi(_swing_left - 1, 0)
	for body: Body in _bodies:
		body.hurt_left = maxi(body.hurt_left - 1, 0)


## A lost arena leaves no effects: the world discards a defeat's wholesale, as it does a turn
## fight's. A won one pays every member still standing through BattleLogic's own lines.
func _decide() -> void:
	if _leader.down():
		_outcome = BattleLogic.Outcome.DEFEAT
		_want(Sfx.Cue.DEFEAT)
		return
	if nearest_standing() >= 0:
		return
	_outcome = BattleLogic.Outcome.VICTORY
	var standing: Array = []
	for member: BattleLogic.Fighter in _members:
		if not member.down():
			standing.append(member)
	var levelled := BattleLogic.share_award(standing, BattleLogic.xp_of(_foes))
	_want(Sfx.Cue.VICTORY)
	if not levelled.is_empty():
		_want(Sfx.Cue.LEVEL_UP)
	_effects = BattleLogic.seal_effects(true, _seen_key, _members, BattleLogic.gold_of(_foes))


## A shove: `distance` units along `away`, spread over push_frames. When two bodies stand exactly
## on each other `away` has no direction, and `fallback` gives it one.
func _shove_toward(away: Vector2i, distance: int, fallback: Vector2) -> Vector2i:
	var way := direction_of(away)
	if way == Vector2i.ZERO:
		way = Vector2i(fallback)
	return way * (distance * along(way) / UNITS_PER_TILE / _combat.push_frames)


func _clamped(centre: Vector2i, size: Vector2i) -> Vector2i:
	var half := size / 2
	return Vector2i(
		clampi(centre.x, _floor.position.x + half.x, _floor.end.x - (size.x - half.x)),
		clampi(centre.y, _floor.position.y + half.y, _floor.end.y - (size.y - half.y)))


func _want(cue: Sfx.Cue) -> void:
	_sounds.append(Sfx.id_of(cue))


func _body(at: int) -> Body:
	return _bodies[at] as Body


# -- what can be read ---------------------------------------------------------------------------


func finished() -> bool:
	return _outcome != BattleLogic.Outcome.NONE


func outcome() -> BattleLogic.Outcome:
	return _outcome


func effects() -> Array[Dictionary]:
	return _effects.duplicate(true)


## The cues asked for since the last call, and then none: the screen plays each once.
func take_sounds() -> Array[StringName]:
	var out := _sounds.duplicate()
	_sounds.clear()
	return out


func frame() -> int:
	return _frame


func floor_rect() -> Rect2i:
	return _floor


func player_pos() -> Vector2i:
	return _pos


func player_facing() -> Dir.D:
	return _facing


func player_box() -> Rect2i:
	return _box(_pos, _size)


func player_moved() -> bool:
	return _moved


func player_hurt() -> int:
	return _hurt_left


func shoved() -> bool:
	return _shove_left > 0


func swinging() -> bool:
	return _swing_left > 0


## Which of `steps` pictures of a swing belongs on screen now, or -1 when the sword is away. A swing
## is painted on swing_frames - 1 frames - the countdown runs at the end of the tick that started
## it - and the pictures are spread across exactly those, so the last is showing as the sword goes.
func swing_step(steps: int) -> int:
	if _swing_left <= 0 or steps <= 0:
		return -1
	var painted := maxi(_combat.swing_frames - 1, 1)
	var shown := _combat.swing_frames - 1 - _swing_left
	return mini(shown * steps / painted, steps - 1)


## The box the sword covers when it is out: `swing_reach_tiles` deep from the leading edge of the
## player's body, as wide as the body, on the side they face.
func sword_box() -> Rect2i:
	var mine := player_box()
	var across := _size.x
	match _facing:
		Dir.D.UP:
			return Rect2i(_pos.x - across / 2, mine.position.y - _reach, across, _reach)
		Dir.D.DOWN:
			return Rect2i(_pos.x - across / 2, mine.end.y, across, _reach)
		Dir.D.LEFT:
			return Rect2i(mine.position.x - _reach, _pos.y - across / 2, _reach, across)
		_:
			return Rect2i(mine.end.x, _pos.y - across / 2, _reach, across)


func foe_count() -> int:
	return _bodies.size()


func foe_pos(at: int) -> Vector2i:
	return _body(at).pos


func foe_box(at: int) -> Rect2i:
	return _box(_body(at).pos, _body(at).size)


func foe_hp(at: int) -> int:
	return _body(at).foe.hp


func foe_max_hp(at: int) -> int:
	return _body(at).foe.def.max_hp


func foe_hurt(at: int) -> int:
	return _body(at).hurt_left


func foe_down(at: int) -> bool:
	return _body(at).foe.down()


func foe_name(at: int) -> String:
	return _body(at).foe.name


func foe_facing(at: int) -> Dir.D:
	return _body(at).facing


func foe_moved(at: int) -> bool:
	return _body(at).moved


func foe_heading(at: int) -> Vector2i:
	return _body(at).heading


func foe_countdown(at: int) -> int:
	return _body(at).countdown


func foe_character(at: int) -> StringName:
	return _body(at).foe.def.character


## The def ids, in formation order - what the world announces a fight with and despawns by.
func foe_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for foe: BattleLogic.Foe in _foes:
		out.append(foe.def.id)
	return out


## The standing foe nearest the player, ties to the lower slot, or -1 when nobody is standing.
func nearest_standing() -> int:
	var best := -1
	var best_distance := 0
	for body: Body in _bodies:
		if body.foe.down():
			continue
		var gap := body.pos - _pos
		var distance := gap.x * gap.x + gap.y * gap.y
		if best < 0 or distance < best_distance:
			best = body.slot
			best_distance = distance
	return best


## The ONE foe whose bar is drawn: the one last struck while it stands, else the nearest standing -
## §16's rule, applied to a fight that has no cursor to say who is being aimed at.
func shown_foe() -> int:
	if _last_struck >= 0 and not foe_down(_last_struck):
		return _last_struck
	var near := nearest_standing()
	return near if near >= 0 else 0


## Whether the sword, if it were out now, would meet this standing foe - whatever it is flashing.
func sword_reaches(at: int) -> bool:
	if foe_down(at):
		return false
	return sword_box().intersects(foe_box(at))


## The first standing foe that could touch the player on the next frame, or -1. "Could" is its box
## grown by one frame of its stride, so something choosing a move can step away before the touch.
func threat() -> int:
	var mine := player_box()
	for body: Body in _bodies:
		if body.hurt_left > 0 or body.foe.down():
			continue
		var stride := whole_units(body.speed * UNITS_PER_TILE) + 1
		if mine.intersects(_box(body.pos, body.size).grow(stride)):
			return body.slot
	return -1


func member_count() -> int:
	return _members.size()


func member_hp(at: int) -> int:
	return (_members[at] as BattleLogic.Fighter).hp


func member_max_hp(at: int) -> int:
	return (_members[at] as BattleLogic.Fighter).max_hp()


func member_name(at: int) -> String:
	return (_members[at] as BattleLogic.Fighter).name


func member_character(at: int) -> StringName:
	return (_members[at] as BattleLogic.Fighter).character


func leader_hp() -> int:
	return _leader.hp


func swings() -> int:
	return _swings


func hits() -> int:
	return _hits


func touches() -> int:
	return _touches


# -- test seams ---------------------------------------------------------------------------------


## Puts the player and the foes where a test needs them, past the spawn.
func stage(player_at: Vector2i, facing: Dir.D, foes_at: Array[Vector2i]) -> void:
	_pos = player_at
	_facing = facing
	for i in mini(foes_at.size(), _bodies.size()):
		_body(i).pos = foes_at[i]


## Sets where a foe is heading and how long it holds that, past its own draws.
func steer(at: int, heading: Vector2i, countdown: int) -> void:
	_body(at).heading = heading
	_body(at).countdown = countdown
