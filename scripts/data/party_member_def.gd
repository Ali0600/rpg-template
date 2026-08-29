class_name PartyMemberDef
extends Resource
## Someone who fights beside the player, as data.
##
## The template's answer to "a party of three or four", which every reference game but Dragon
## Quest I has and this one did not until M27. A member is the numbers a fight needs plus the
## art it wears; who they ARE - what they say, why they came along - is dialog, and lives in
## the game's own content like every other conversation.
##
## MEMBERSHIP IS DERIVED FROM A FLAG, never recorded as a roster. `joins_on_flag` is the whole
## mechanism: the world filters the manifest's party by the flags that are set, every time it
## builds a fight or a menu, the way SpellDef.learn_level filters the spell list by level. So
## recruiting somebody is the `set_flag` a dialog choice already carries - there is no join op,
## no roster to save, no membership to migrate, and no way to hand out the same companion
## twice. What IS saved is each member's own numbers, which is a different fact (see
## GameState.companions).
##
## An empty flag means "in the party from the start", which is the shape a game with a fixed
## cast wants: Final Fantasy I picks four before the game begins and never changes them.
##
## THE LEADER IS NOT ONE OF THESE. The player is synthesized from the manifest's own
## player_character and combat, so a game that declares no party still fights with a party of
## one and there is exactly one code path through the battle. The cost is that a leader cannot
## be given a name or a narrowed spell list - Dragon Quest II's magic-less hero is not
## expressible here - which is recorded in docs/DECISIONS.md with its revisit hook.
##
## Registered automatically by Registry, like every resource under data/ - though the manifest
## holds real references, so nothing looks a member up by id at runtime.

## Matched on everywhere, and the key each member's saved numbers hang off. The content gate
## requires it to equal the file's own name, as items, enemies and spells do.
@export var id: StringName = &""

## Shown to the player: the battle read-out's caption, and the member window's row.
@export var name: String = ""

## The CharacterSpec whose generated sheet this member wears, exactly as the manifest's
## player_character names the leader's. Art is generated per style, so whether it EXISTS is a
## question only answerable once you know which map the game opens in - which is why that
## check lives in the manifest rather than here.
@export var character: StringName = &""

## This member's own growth. Null means the game's own CombatDef, which is the common case and
## means "grows like the player does". Per-member curves are universal in the genre - Dragon
## Quest II's three characters have visibly different HP and MP tables - and a member's curve
## is the only place their strength is stored, because stats are derived from level here.
##
## THE TIMING FIELDS ON A MEMBER'S CURVE ARE IGNORED. Cue lengths and the press window pace the
## whole fight, not one fighter in it; two members with different windows would be one screen
## asking the player to react at two speeds. Those come from the manifest's combat, always.
@export var combat: CombatDef = null

## Which spells this member can learn, by id. WHEN they learn one is still SpellDef.learn_level
## against this member's own level, so the derivation is unchanged - this only narrows the set
## it draws from. An empty array is a member with no magic at all, which is Dragon Quest II's
## hero exactly, and is the default because most companions in the genre are not casters.
@export var spells: Array[StringName] = []

## The flag whose presence puts this member in the party. Empty means "from the start". A game
## recruits by setting it - a dialog choice with `set_flag`, an object, a hook - so the join is
## whatever the game's own content says it is rather than a mechanism the template imposes.
@export var joins_on_flag: StringName = &""

## The level this member arrives at, the first time the party is built with them in it. One is
## legal and means "starts where the player started"; a higher number is the genre's "a veteran
## joins" - Dragon Quest IV's later chapters do exactly this. Their xp is set to the exact
## threshold that level costs, so the next fight advances them honestly rather than levelling
## them twice.
@export var join_level: int = 1


## Everything wrong with this member, in the idiom of every other problems() here: all of them,
## not the first. What is NOT here: whether the spell ids exist, and whether the art was
## generated. Both need the Registry or a map's style, which a resource cannot reach - they are
## content-gate checks, the way an enemy's art is.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("party member has no id")
	if name.is_empty():
		out.append("party member '%s' has no name" % id)
	if String(character).is_empty():
		# Without art there is nothing to draw in the fight, and the failure would be an
		# invisible fighter rather than an error.
		out.append("party member '%s' wears no character" % id)
	if join_level < 1:
		out.append("party member '%s' joins at level %d" % [id, join_level])
	var seen_spells: Dictionary = {}
	for spell_id: StringName in spells:
		if String(spell_id).is_empty():
			out.append("party member '%s' lists a spell with no id" % id)
		elif seen_spells.has(spell_id):
			# Twice in the list is once in the fight, so the duplicate is silent - and it is
			# usually a copy-paste that meant to name a different spell.
			out.append("party member '%s' lists spell '%s' twice" % [id, spell_id])
		seen_spells[spell_id] = true
	if combat != null:
		for fault: String in combat.problems():
			out.append("party member '%s': %s" % [id, fault])
	return out
