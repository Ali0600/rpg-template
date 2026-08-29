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
## No element here, deliberately. A resistance table is a system with a matrix, an enemy field
## and a rule per pairing; naming the attack spell "Ember" costs nothing and reads the same at
## this scale. See docs/DECISIONS.md.
enum Kind { ATTACK, HEAL, SLEEP }

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

## Damage for an ATTACK, hit points restored for a HEAL, unused for a SLEEP. One field rather
## than two named ones because a spell is exactly one of these kinds and the second field would
## be zero in every file that has it - a value that is always zero is a question nobody asked.
@export var power: int = 1

## How many of the enemy's turns a SLEEP takes away. Unused by the other kinds.
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
	if kind < 0 or kind >= Kind.size():
		out.append("spell '%s' has kind %d, which is not a kind of spell" % [id, kind])
	elif kind == Kind.SLEEP:
		if status_turns <= 0:
			out.append("spell '%s' puts the enemy out for %d turns" % [id, status_turns])
	elif power <= 0:
		# An ATTACK or a HEAL with no power is a spell that spends MP and changes nothing,
		# which reads in play as a broken button rather than as a weak spell.
		out.append("spell '%s' has %d power - casting it would do nothing" % [id, power])
	return out
