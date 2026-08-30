class_name SpellDef
extends Resource
## Something the player can cast, as data.
##
## The third combat noun beside ItemDef and EnemyDef, and it holds only what a fight needs: what
## it costs, when it becomes available, what kind of thing it does and how much of it. How a
## spell is DRAWN is the screen's business, and who knows it is not stored anywhere at all.
##
## KNOWING A SPELL IS DERIVED FROM LEVEL, never recorded. `learn_level` is the whole mechanism:
## the world filters the registered spells by the player's level every time it builds a battle,
## the way CombatDef derives attack from level rather than storing it. That is Dragon Quest's
## and Chrono Trigger's own shape - a spell arrives at a threshold, with no ceremony - and it
## means there is no "known spells" list to save, migrate, desynchronise from the level that
## bought it, or hand out twice. A designer retuning `learn_level` retunes every existing save.
##
## Registered automatically: Registry buckets every resource under data/ by its class_name, so
## a new file in data/spells/ is reachable as Registry.get_resource(&"SpellDef", id) with no
## registration step to forget.

## What a spell DOES, as the template's own closed vocabulary - the ItemDef.SLOTS shape, as an
## enum because unlike a slot this is never spelled out in content: a game writes a number the
## inspector picked from a dropdown, and problems() refuses anything outside the list.
##
## Three rather than two, and that is the load-bearing count. Every reference game ships a
## non-damage, non-heal effect among its FIRST spells - Sleep is tier one in Final Fantasy and
## early in Dragon Quest's eight-spell list - so "an attack spell and a heal spell" is thinner
## than the smallest system the genre actually shipped. SLEEP is the cheapest way to not be
## thinner: one counter on the fight, checked before the enemy moves.
##
## An element is NOT one of these. It answers "what is this made of", where a kind answers "what
## does it do" - and an ATTACK of any element still does the one thing an ATTACK does. Folding
## fire into the kind list would multiply this enum by every element a game invents, which is the
## shape a matrix exists to avoid. See `element` below.
##
## BOOST and SAP arrived in M30 and are APPENDED rather than inserted, because a `.tres` stores
## an enum as the integer it was when the file was written: putting a new kind in the middle
## would silently re-label every shipped spell.
##
## They are two verbs and not one signed number. A single kind whose `power` may be negative is
## a verb spelled as the absence of its opposite - the exact shape `PauseMenu.Kind.UNEQUIP`
## exists to avoid - and the reader who forgets the sign ships a spell that helps when it should
## hurt. The target follows from the kind, as it already does for HEAL and ATTACK.
enum Kind { ATTACK, HEAL, SLEEP, BOOST, SAP }

## Which number a BOOST or a SAP moves. Unused by the other kinds.
##
## Two, because two is what the references move: Final Fantasy I's TMPR raises weapon strength
## and its FOG raises armour, Dragon Quest's Buff doubles defence, EarthBound's Assist branch
## carries Offense up beside Defense down. Speed is not here because this template has no
## agility - turn order is party order, and a stat nothing reads would be a knob wired to
## nothing.
enum Stat { ATTACK, DEFENSE }

## How many things it reaches. The shape belongs to the SPELL rather than to a runtime cursor,
## which is Final Fantasy I's model ("some spells will affect all enemies on the screen") and
## Dragon Quest II's, whose list splits into one / a group / everything.
##
## Groups and multi-target magic arrive together in the genre - DQ1 has no group spells because
## it has no groups, and DQ2 introduces both in the same game - so this field arrived with
## formations rather than before them.
enum Target { ONE, ALL }

## Matched on everywhere. The content gate requires it to equal the file's own name, as items
## and enemies do.
@export var id: StringName = &""

## Shown to the player, in the battle menu's spell list.
@export var name: String = ""

## One line, shown under the list when this spell is selected, on ItemDef.description's terms.
@export var description: String = ""

## What casting it takes off the player's MP. Must be positive: a free spell is a second Attack
## row with better numbers, and the resource is the only thing making a choice out of it.
@export var mp_cost: int = 1

## The player level at which this spell becomes castable. One is legal and means "from the
## start". There is no upper bound here - a spell whose level the xp curve cannot reach is a
## design decision (an unreachable reward, a sequel's spell shipped early), not a fault.
@export var learn_level: int = 1

@export var kind: Kind = Kind.ATTACK

## What this spell is MADE OF, paired against `EnemyDef.resistances` to scale its damage. Empty
## is the default and means elementless - damage lands at face value, which is what every spell
## did before this field existed.
##
## AN OPEN VOCABULARY, deliberately, where `Kind` is a closed enum. The template never branches
## on "fire": it looks the word up in the enemy's own map and multiplies, so it needs no opinion
## about which elements exist. A closed list here would be this template choosing the elements of
## every game built on it, and the references do not agree on a set worth choosing - Final
## Fantasy I's first tier is fire, ice and lightning, Dragon Quest bakes the element into the
## spell's NAME, Pokemon runs eighteen. What the content gate checks instead is that the two
## sides MEET: an element no shipped spell carries is a resistance nothing can trigger.
##
## Legal on an ATTACK only. A heal or a sleep has no damage for a resistance to scale, so an
## element on one would be a field nothing reads - the shape `problems()` already refuses when a
## move carries `turns` with no status, and the reason it refuses it: that is how a data file
## comes to describe an effect the fight never applies.
@export var element: StringName = &""

## ONE is the default and means the spell asks who. ALL is legal for an ATTACK only: a heal or a
## sleep that reached everybody is a real genre noun in both cases, but neither is needed to
## fight a crowd, and shipping a field's every combination before any of them has content is how
## a template grows rules nobody chose. `problems()` refuses the rest.
@export var target: Target = Target.ONE

## Damage for an ATTACK, hit points restored for a HEAL, the SIZE of the shift for a BOOST or a
## SAP, unused for a SLEEP. One field rather than four named ones because a spell is exactly one
## of these kinds and the other three would be zero in every file that has them - a value that is
## always zero is a question nobody asked.
##
## Always POSITIVE, including for a SAP: the kind says which way it points, so the number never
## has to. See the note on `Kind`.
@export var power: int = 1

## Which number a BOOST or a SAP moves. Unused by the other kinds, and defaulting to ATTACK
## rather than to a "none" that only these two kinds could ever mean.
@export var stat: Stat = Stat.ATTACK

## How many turns the effect lasts - the enemy's, for a SLEEP; the afflicted party's or foe's,
## for a BOOST or a SAP. Unused by ATTACK and HEAL.
##
## A STATED number, where the references roll one: Dragon Quest's Buff runs 4-6 turns and its Sap
## 6-9. M13 made flee odds and damage variance deterministic so that a designer can reason about
## a fight and a QA script can replay it byte-for-byte, and a duration is the same kind of
## number. docs/DECISIONS.md carries the fork.
@export var status_turns: int = 1


## Everything wrong with this spell, in the idiom of every other problems() here: all of them,
## not the first.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("spell has no id")
	if name.is_empty():
		out.append("spell '%s' has no name" % id)
	if mp_cost <= 0:
		out.append("spell '%s' costs %d mp - it would be free" % [id, mp_cost])
	if learn_level < 1:
		out.append("spell '%s' is learned at level %d" % [id, learn_level])
	# A hand-edited .tres can carry any integer here, and an unknown kind would fall through
	# every branch in the fight and cost a turn doing nothing.
	if target < 0 or target >= Target.size():
		out.append("spell '%s' has target %d, which is not a shape" % [id, target])
	elif target == Target.ALL and kind != Kind.ATTACK:
		out.append("spell '%s' reaches everything, which only an attack may do" % id)
	if kind < 0 or kind >= Kind.size():
		out.append("spell '%s' has kind %d, which is not a kind of spell" % [id, kind])
	elif kind == Kind.SLEEP:
		if status_turns <= 0:
			out.append("spell '%s' puts the enemy out for %d turns" % [id, status_turns])
	elif kind == Kind.BOOST or kind == Kind.SAP:
		# A shift needs BOTH halves to mean anything: a size with no duration expires before the
		# turn it was cast on ends, and a duration with no size is a spell that spends MP,
		# announces itself and changes no number. Either reads in play as a broken button.
		if power <= 0:
			out.append("spell '%s' shifts a stat by %d - casting it would do nothing"
				% [id, power])
		if status_turns < 1:
			out.append("spell '%s' lasts %d turns" % [id, status_turns])
		if stat < 0 or stat >= Stat.size():
			out.append("spell '%s' moves stat %d, which is not a stat" % [id, stat])
	elif power <= 0:
		# An ATTACK or a HEAL with no power is a spell that spends MP and changes nothing,
		# which reads in play as a broken button rather than as a weak spell.
		out.append("spell '%s' has %d power - casting it would do nothing" % [id, power])
	# Outside the chain above rather than repeated in three of its branches: an element is
	# scaling for damage, so every kind that deals none refuses it by the same one line.
	if kind != Kind.ATTACK and not String(element).is_empty():
		out.append("spell '%s' is made of '%s' but deals no damage for that to scale" % [id, element])
	return out
