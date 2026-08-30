# 2D (J)RPG conventions, and where this template sits against them

**What this file is for.** Before building anything a player looks at, read this file's
section for that surface. If the section is thin, do the research and thicken it *first* —
the research is the deliverable, and it belongs here rather than in a pull request nobody
re-reads.

**Why it exists.** Two milestones shipped a player-facing surface built from this repo's own
idioms rather than from the genre's, and the person who asked for them rejected both on
sight. M18's shop was three lines of floating text on a dim screen — no descriptions, no
quantity, no keeper, no windows. M19's equipment was a confirm-toggle hidden inside the bag,
when every game it was modelled on gives Equip its own menu command. Both were fully tested
and fully green. Gates cannot see a screen that is missing half of what its genre gives it.

The second failure is the more instructive one: M19 *did* do a genre pass. It researched the
equip **interaction** — the marker, the stat delta, the toggle — and never asked where
equipment **lives**. So the question this file exists to answer is not only "how should this
behave" but "where does this live, and what sits beside it".

**How to read it.** Each section states what the genre converges on **with named games**,
what the template does today, and the gap. "Classic JRPGs do X" without names is how the shop
shipped wrong; a convention with no games behind it is an opinion.

**It records, it does not mandate.** A gap is a candidate for `DECISIONS.md`, not a bug. This
template deliberately diverges in several places, and a deliberate divergence with a recorded
reason is a better answer than compliance. What it must never be is an *accident*.

**Scope note.** The references are the 2D era — NES through PS1-era sprites — because that is
what this template generates art for. Reference games: Final Fantasy I–VI, Dragon Quest I–VI
(NES and SNES remakes, which differ), Chrono Trigger, EarthBound, Pokémon R/B/G/S.

---

## Audit — the template against the conventions

| Surface | The convention | This template today | Status |
| --- | --- | --- | --- |
| [Menu anatomy](#1-menu-anatomy) | Item / Equip / Status / Save as sibling commands | Resume, Items, Equipment, Status, Save, Load, Sound | **met** (M20) |
| [Equip screen](#2-the-equip-screen) | Slot list → candidates → preview the delta | Slot list, candidates, take-off row, swap preview, Atk/Def readout | **met** (M20) |
| [Status screen](#3-the-status-screen) | Level, HP, XP-to-next, stats, worn gear | A page of world-worded lines | **met** (M20) |
| [Inventory](#4-inventory) | List, counts, description, a use verb | List, counts, description, **no use verb** | **partial** — [use is a game's business](DECISIONS.md) |
| [Shop](#5-shops) | Windows over the world, keeper, quantity, prices | All of it | **met** (M18.1) |
| [Dialog](#6-dialog) | Bottom window, revealed text, choices | Bottom box, reveal, choice band, size-gated | **met** |
| [Battle](#7-battle) | Random encounters, turn menu, a party | Visible enemies, timed presses, **a party** | **met** (M27) for the party; encounters and timing [diverge deliberately](DECISIONS.md) |
| [Save/load](#8-saveload) | Save points or inns; menu save later in the era | Slots from the pause menu, anywhere | **diverges deliberately** |
| [Progression](#9-progression) | Level, XP curve, stats from level, gear as modifier | All of it | **met** |
| [Towns & NPCs](#10-towns-and-npcs) | Walking townsfolk, shops, an inn | Static, wander and patrol NPCs; a shop; an inn | **met** (M21) |
| [World structure](#11-world-structure) | Overworld → towns → dungeons, gated | Maps and warps, gated by items and flags | **met** in shape |
| [Title & game over](#12-title-and-game-over) | Title screen with Continue; death → menu | Title with Continue / New game; game-over routes back to it | **met** (M22) |
| [Magic & skills](#13-magic-and-skills) | MP, a spell list, a battle command | MP from the level curve, three spell kinds, a Magic command, an MP status line | **met** (M25) — [no field-menu page](DECISIONS.md) |
| [Music](#14-music) | Per-area themes, battle theme, fanfare | Three generated tracks per style: a road theme, a battle theme, and a fanfare that hands the room back | **met** (M24, M26) |

Two rules about this table. A **gap** is a backlog candidate, not a defect — the template
ships one small game and does not need every noun in the genre. A **deliberate divergence**
must link a `DECISIONS.md` entry saying who decided and why; if it cannot, it is a gap
wearing a nicer word.

---

## 1. Menu anatomy

**The convention.** The pause/field menu is a short list of *commands*, each opening a page.
Final Fantasy IV–VI: Item, Magic, Equip, Status, Config, Save. Chrono Trigger: Items, Tech,
Status, Equip, Save. Dragon Quest NES puts everything in a field-command list (Talk, Spell,
Status, Item, Stairs, Door, Search) and by DQ VI has condensed to a standard set — the SNES
remakes move Equip under Status
([DQ wiki](https://dragon-quest.org/wiki/Command_menu)).

Two things generalise. **Item and Equip are siblings, not nested**: in FF and Chrono Trigger
you never equip from the item list. And **the order is stable across the genre** — consumables
first, then gear, then the character read-out, then system rows (save, config). A player who
has played one of these games can find Save in a game they have never seen.

**This template.** `PauseMenu`/`PauseScreen`, opened with Escape from the world only:
Resume, Items, Save, Load, Sound. Rows are an enum the view indexes its labels by, so the
order lives in one place. Save and Load are separate rows rather than one page with a mode,
which is the DQ/FF slot-select shape flattened by one level. Sound sits at the bottom where
Config does, and `Resume` is explicit rather than Escape-only because this game boots straight
into the world and has no title screen to retreat to.

**Gap:** none. Equipment and Status both moved here in M20 (§2, §3). Equipment had been folded
into the bag, which is the one place the reference games never put it — and it was there
because the menu had no row for it, which is what makes a missing command more than a cosmetic
gap. Sound sits at the bottom where Config does.

---

## 2. The equip screen

**The convention.** Slot-first, and this is near-universal: FF I–VI, Chrono Trigger and the DQ
remakes all show a **list of slots with what is in them** ("Weapon: Bronze sword", "Armor:
—"), and confirming a slot opens **the carried gear that fits that slot**, plus a way to take
the current one off. Highlighting a candidate **previews the stat change before you commit**;
FF colours gains and losses. The character's stats are visible on the same screen, so the
delta has something to be a delta *of*.

FF adds **Optimize** (best-equip by attack and defence, ignoring everything subtler) and
Remove-all. Both are conveniences for games with five slots and forty items.

**With a party, the screen gains a step in front of it.** Gear is per-character in every
reference game — FF1 has each character carry up to four weapons of their own, and DQ2's
worn equipment even counts against that character's own eight item slots. So Equip opens a
**member window first**: Dragon Warrior II's Equip selection "brings up a smaller window
listing your characters, and you can select which character you wish to equip", and the same
step appears when an item can be used on someone. The slot list is the *second* page, not the
first. This is the §7a research applied to this screen, and it is the container question
again — the interaction below is already right, and a party changes only whose it is.

**This template.** `Row.EQUIP` opens a slot list built from `ItemDef.SLOTS`; each slot opens
its candidates plus a `(take off)` row; the line under the list previews the swap ("Wear: Atk
+3  (now Atk +0 Def +0)"), and an Atk/Def readout sits beside the purse. Confirming returns to
the slot list. Slotless items are never candidates, so the picker cannot offer a tonic as
armour, and taking off an empty slot is refused rather than silently ignored.

Before M20 this was a confirm-toggle inside the bag — the marker and the delta were right and
the container was wrong. That is the failure this whole file exists to prevent.

**Gap:** Optimize is deferred — at two slots it would be a button that does what one press
already does. Revisit hook: `ItemDef.SLOTS` growing past three.

---

## 3. The status screen

**The convention.** A read-only page: level, HP (current/max), MP, **experience and how much
until the next level**, the character's stats, and what they are wearing. The XP-to-next line
is the one players actually open the menu for — it turns "am I strong enough" into a number.
Present in every reference game; FF and DQ both put equipment on it, which makes it the
screen you check before shopping.

**This template.** `Row.STATUS` opens a read-only page of lines the world words: level, HP
against the maximum, XP with how much is left to the next level (or that there is no next
one), Atk/Def with the gear's contribution shown separately, and each slot's contents. A game
with no `CombatDef` shows only what it actually has, down to "(nothing to report)".

Before M20 every one of those numbers already existed and was only ever shown **inside a
fight** — a player could not answer "how hurt am I" without starting one.

**With a party, Status takes the same member step Equip does** (§2) — the page describes one
character, so something has to say which. EarthBound's Goods command cycles through the party
the same way. The alternative the genre also ships is one page per member with L/R paging,
which is the same choice made at a different point in the flow.

**Gap:** no portrait, which would be a second art pipeline beside the generated sprites. The
MP row landed with magic in M25 (§13).

---

## 4. Inventory

**The convention.** A list with names and counts, a description for the highlighted entry, and
a **use** verb that works in the field (potions heal, keys open, tools solve). Pokémon shows
"In Bag: ×3" on shop rows for the same reason. Quantity limits vary — DQ's per-character
carry limits, FF's flat 99 stacks.

**This template.** `Items` page: name, count when more than one, `(E)` on worn gear,
description on the line below. No stack limit. **No use verb** — confirming a non-gear item
does nothing.

**Gap:** the use verb, deliberately. A potion heals in every RPG ever written, but "use the
rope on the well" is a puzzle, and puzzle verbs are a game's business rather than a template's
— see `DECISIONS.md`. A game gets there through its `GameHooks`. Note the genre argues the
other way for consumables specifically, and if the template ever ships a second demo game with
field healing, this is the first thing to revisit.

---

## 5. Shops

**The convention.** Convergent anatomy, drawn from the reference games and the
[JRPG UI survey](https://thegamedesignforum.com/features/JRPG_UI_SURVEY.pdf) and
[Game UI Database](https://www.gameuidatabase.com/index.php?scrn=72): the keeper **talks**
(greeting, acknowledgement, a spoken refusal when you cannot afford it, a farewell); the
screen is **windows over the world**, not a full-screen takeover, because a shop is a place
you walked into; names left and **prices right-aligned**; the owned count on the row; a
description of the highlighted item; and buying goes **pick → how many → confirm**, with the
running total visible while you size the deal. Selling mirrors it at a reduced price.

**This template.** All of it (M18.1). `ShopDef` names the stock, the price lives on the
`ItemDef` so two keepers cannot disagree, `price = 0` means not for sale and is the default —
which keeps quest items off both counters by construction.

**Gap:** none for a template. Rotating stock, synthesis and deal boards are *game* patterns
(the user's own `jrpg-design-codex` covers those) and deliberately not template scope.

---

## 6. Dialog

**The convention.** A window at the **bottom** of the screen, text **revealed** rather than
appearing at once (with a blip per character in most), advanced by the confirm button, and
choices presented as a cursor list. EarthBound and Pokémon both let the player recolour the
box and set text speed. Portraits are common but far from universal in the 2D era.

**This template.** `DialogRunner`/`DialogBox`: two lines at the bottom, revealed, choices in a
band below that appears only when there are choices, `cancel` closes a plain line but not a
choice. Uniquely, **the build measures every shipped line against the box** and fails if it
would not fit — a `RichTextLabel` clips silently, so a fact written into the data would never
reach the player and every headless gate would still pass.

A choice can also carry money: `spend_gold` with a mandatory `poor_next`, which is the
refusal the player hears. See `DECISIONS.md` for why money is shown-and-refused where an item
requirement is hidden.

**Gap:** no portraits, no per-player text speed. Both are candidates; neither is load-bearing.

---

## 7. Battle

**The convention.** Random encounters on a step counter (FF, DQ, EarthBound's visible-on-map
variant aside), a **turn-based command menu** (Fight / Magic / Item / Run), a **party** of
three or four, HP/MP bars, and a victory screen paying XP and gold.

**This template diverges, deliberately.** Enemies are **visible records on the map** and the
fight fires on stepping to an adjacent tile — a fight that must happen is made unavoidable by
**geometry** (a one-tile gap), never by a random roll. The fight itself is **timing-based**: a
cue lights and a press inside its window doubles the blow or halves the incoming one.
`BattleLogic` has **no clock** — it is handed one physics frame at a time, which is what lets a
QA script press on an exact frame and get the same fight on every machine.

**Why the divergence is good.** Random encounters need a random source in the movement loop,
and this template's whole determinism story ("same seed, same everything") is what makes its
play sessions a gate. Visible enemies also make a template's demo game legible in a way a
step-counter never is. Recorded in
[Encounters are visible and presses are timed](DECISIONS.md).

**The party was the largest missing *system* in the template until M27**, and it reached into
`BattleLogic`, the status page and the equip screen (whose gear became per-character). The rest
of this section is the research that gap needed, because "a party of three or four" with no
games behind it is exactly the kind of sentence this file's preamble calls an opinion.

### 7a. What a party is, in the games this template is modelled on

**How many, and how it is decided.** The genre's range is one to four, and the mechanism
differs more than the number does. **Final Fantasy I** has the player build four characters
before the game starts and locks that choice for the whole game. **Dragon Quest I** is solo
from beginning to end — which is the shape this template ships today, and it is a shipped
genre shape rather than an absence. **Dragon Quest II** grows from one to three by story:
the Prince of Cannock joins at the inn in Leftwyne, and the Princess of Moonbrooke is a dog
until Ra's Mirror restores her — so DQ2 spends a substantial early stretch **at exactly two**,
and Yuji Horii's stated reason for recruiting them one at a time was that he was worried
players "would become confused by controlling too many characters at once". A two-member
party is therefore not a thin approximation of the genre; it is a stage the genre's most
influential designer engineered on purpose. **Dragon Quest III** assembles four at Patty's
bar (Luisa's Place in the NES localisation) and stores the rest there. **Dragon Quest IV**
runs four active with more in the wagon; **Chrono Trigger** three active of seven;
**EarthBound** reaches four by story. **Pokémon** carries six and fields one.

Whether the roster *equals* the battle line is its own fork: FF1, DQ2 and EarthBound say yes;
CT, DQ3 and DQ4 say no, and pay for a bench with a swap screen.

**Recruiting.** Three mechanisms, and the cheapest by a wide margin is the **story join** —
a member appears after an event or a conversation (DQ2, DQ4's chapter five, EarthBound's
Paula at Happy Happy Village, Chrono Trigger throughout). It needs no roster screen, no
bench, no creation flow: one fact changes, and the party is larger. Create-at-start (FF1)
costs a whole pre-game screen. Guild recruitment (DQ3) costs a roster, a bench and a swap
mode. From DQ4 onward the series drops creation entirely and joins are narrative.

**Command entry.** Three families. **Command-all-then-resolve** is the NES norm: FF1's manual
has the player enter commands for all four characters and *then* the round executes, and DQ
works the same way — orders are given at the beginning of a turn only. **Act-as-you-choose**
gives the turn to one character at a time: Super Mario RPG's characters "wait their turn to
perform an action", and "when it's your turn to act, you'll choose an action" — the choice and
the blow are the same beat, and SMRPG orders those turns by Speed. **ATB** (FF4–6,
Chrono Trigger) interleaves per-character timers instead. Resolution order is where the two
NES references disagree with each other: **DQ orders by Agility**, through a randomised
formula, while **FF1's order is a fully random shuffle of all thirteen combatants and does
not depend on anyone's stats at all**. That second fact is the useful one here — the genre's
foundational entry does *not* derive turn order from a stat, so a fixed declared order is
inside the convention rather than a concession to it.

**Targeting.** FF1 asks which *enemy* an attack hits; DQ2 asks which enemy **group**, and if
the group holds several you hit one at random — i.e. the target's shape is a property of the
action, which is the cheaper half. Ally targeting is attested plainly: EarthBound's manual
says to "Select the target of the attack, if applicable" with B to cancel, and DQ2's item
flow opens "a menu to select which character you want" when an item can be used on someone.
Whether a cursor is *skipped* when only one target is legal went unverified for either NES
reference through M27 — **§7b answers it**: Super Mario RPG skips the step outright, asking
which enemy only "if there is more than one". What was already verified is the consequence of
*not* skipping — FF1 lets you aim at an enemy that is already dead and answers "Ineffective",
and DQ2 whiffs the same way.

**Falling, and losing.** Zero HP means down, not dead-dead: the member stays down, takes no
turns, and earns nothing. **Neither NES reference retargets** — FF1's wasted attacks are the
single most complained-about thing in the game, and the remakes added automatic retargeting
precisely because of it. The fight is lost only when **every** member is down.

**Revival is a town service, and it is priced.** DQ2 gave churches real function: a priest
revives a fallen character for gold, at twenty gold per experience level in Dragon Warrior II.
EarthBound revives unconscious members at hospitals. **Final Fantasy I has no Phoenix Down** —
that is a later-FF noun; on the NES revival is the LIFE spell (which restores 1 HP and does
not work in battle) or a walk back to a town Clinic. The genre's minimal shape is therefore:
the survivors walk on, the fallen stay at zero, and a paid service in town puts them back up.

**Experience.** The two series genuinely disagree. **FF1 divides** the award among survivors,
and the dead and the fled get nothing — which is why a solo run levels four times as fast.
**DQ does not divide**: every character alive at the end receives the full listed amount, and
DQ4's wagon members earn it without fighting at all. Fallen members earn nothing in both.
Per-member levels on per-member curves are universal.

**Ownership.** Every reference game gives each member their own level curve, their own MP or
charges, their own spell list, and **their own equipped gear**. DQ2's split is the clean
archetype and it inverts the obvious assumption: the *hero* has no magic whatsoever, the
Prince of Cannock carries a weaker assortment, and the Princess of Moonbrooke is the
sorceress who holds the attack spells. FF1 uses per-tier spell *charges* rather than MP.
The one genuinely open question is consumables: DQ2 gives each character eight item slots
with worn equipment counting against them, while **FF1 shares consumables and key items in
one party bag and still holds equipment per character**. So "DQ is per-member and FF is
shared" is only true of consumables — for gear, every reference game is per-member.

**The overworld.** Final Fantasy I–VI show **one sprite** for the whole party on the field
and the world map, and nobody calls those games party-less. Chrono Trigger draws the leader
with the party following. A follower line is a presentation choice, not part of the system.

**The battle read-out.** FF1 puts the enemies left and the party right, with **one HP box per
character** stacked down the right edge. DQ2 uses text windows listing NAME, LV, HP and MP
per member, with names abbreviated to four characters — which is its answer to exactly this
problem on a screen no larger than this template's. EarthBound puts one HP/PP strip along the
bottom for all four.

**What M27 shipped against it.** A party is a list even when it is one, so a game declaring
none still fights through the same code. Membership is derived from a flag, which is the story
join in its cheapest form. A member acts the moment they choose, in party order — SMRPG's shape
rather than FF1's, and the one place this milestone's research led it wrong: M27 shipped
command-all-then-resolve on FF1's and DQ's authority, and the first person to play it rejected
it in a sentence (M27.1, and `DECISIONS.md` carries the reversal). Both are inside the genre;
only one of them survived contact with a controller, and no amount of citation could have told
us which. Order is party order — FF1's own ignores stats. Falling is not losing, the
living earn the full award (DQ's rule, not FF1's division), and the fallen are put back up by
the inn, which is the priced town service the genre already gave this template. One overworld
sprite, FF's answer. An ally cursor, no enemy cursor.

### 7b. What a crowd of enemies is, in those same games

Everything above concerns the player's side. This is the other half of the same fight, and it
is the research M28 needed before building — because "fights are one foe" was never a
convention, only a scope line.

**How many, and what a formation is.** The genre's fights are *formations*, authored in a
table, not counts rolled at runtime. **Final Fantasy I** carries nine enemy slots, and its
combat loop shuffles thirteen entries — nine enemies plus four heroes; a formation may be
"1-9 small enemies, 1-4 large enemies or a mix of up to 6 small and 2 large", so a *size*
budget rather than a flat cap. **Super Mario RPG** stores 512 formation records in ROM; the
Mack fight is the boss "accompanied by a quartet of Bodyguards", i.e. five sprites from one
touched body. **Dragon Quest II** fields one to eight, with larger sprites consuming two
slots. **EarthBound** labels its enemies A through H, and its manual notes the party may face
them "possibly in two separate rows if enough enemies are present". **Dragon Quest I** fights
exactly one — which is the shape this template shipped from M13 to M27, and a real genre shape
rather than an absence. So the attested floor for a *multi*-enemy fight is **two**, and both
FF1 and DQ2 range upward from one; what no reference does is decide the number at runtime.

Composition comes in three flavours, all attested: **same-species groups** (DQ2's "monster
groups", the source of "3 Slimes appear!"), **mixed formations** (FF1's explicit "6 small and
2 large"), and **boss-plus-minions**, whose sharpest example is SMRPG's Mack — the bodyguards
respawn, and "if the player fails to defeat all bodyguards within one turn, [Mack] will jump
out of the battle screen and will not return until all bodyguards on the field are defeated".
That last one is a different fight *shape*, not merely a bigger number, and it is worth
recognising as its own thing rather than as a formation with a boss in it.

**Targeting: individual, at these sizes.** FF1's manual says to "Move the 'finger' with the
Control Pad and press the A Button to select which enemy to FIGHT" — a pointer over the
sprites, with the names living in their own window on the bottom left. **Super Mario RPG**
does the same with the D-pad and, decisively for a template, **skips the step when there is
one enemy**: you attack, and "if there is more than one enemy, you then select which enemy".
EarthBound hedges identically in its manual ("Select the target of the attack, *if
applicable*") and disambiguates duplicates with letter suffixes. Dragon Quest is the outlier:
it targets a **group** and hits one of its members at random. That is a compression device for
eight sprites, and it comes at a cost the individual cursor does not pay — DQ2 still whiffs
when the chosen group has already been emptied. At two or three visibly-drawn foes, every
reference whose enemies are individually rendered asks for an individual.

**A dead target is a problem this template does not have.** FF1's "Ineffective" — aim at an
enemy that died earlier in the round and waste the turn — is the game's most complained-about
behaviour, and the remakes added automatic retargeting to answer it. Note *why* it happens:
FF1 enters all four commands before the round resolves, so a target can die in the gap between
choosing and striking. It is a consequence of command-all-then-resolve, not of per-enemy
targeting. Under **act-as-you-choose** the gap does not exist — the choice and the blow are
one beat — which is the round shape M27.1 adopted from SMRPG. So the dividend is free and it
is worth naming: a cursor listing the living at the moment it opens cannot go stale, and no
retarget rule is needed. (Group targeting would *reintroduce* the whiff, since a group can
empty between rounds.)

**Every living enemy acts, every round.** FF1's nine enemies are nine of the thirteen entries
in its turn shuffle. SMRPG interleaves both sides by Speed, where a fast character "could
attack multiple times before another character attacks once". Dragon Quest orders by Agility.
No 2D reference in this file's scope has enemies act as a *block* after the whole party — the
template's "party in order, then the enemy" is already a recorded divergence, and extending it
to "then each living foe in order" widens an existing divergence rather than opening a new one.
The pacing consequence is real and has to be accepted rather than designed around: N foes mean
N incoming blows, and here N defend cues. **SMRPG is the precedent that this is playable** —
its timed blocks are per incoming attack, and blocking well halves or negates the damage. What
the references do *not* do is skip enemy attacks to save time; the relief comes from elsewhere
— FF1 caps large enemies at four, DQ2 pairs groups with group-clearing magic, and EarthBound
skips the whole battle when it is a foregone conclusion (and pointedly refuses that shortcut
when "the number of enemies is greater than the number of characters who aren't unconscious").
For a template, the honest lever is a **small cap**.

**Groups and multi-target magic arrived together.** This is the strongest single finding for
scoping. **Dragon Quest I has no group spells because it has no groups**; DQ2 introduces both
in the same game, and its spell list is explicitly shaped by target — Firebal hits one, Sleep
and Infernos hit a group, Explodet hits everything. (Sources disagree on whether Firebane is
group or all; the existence of both shapes in DQ2 is not in doubt.) FF1's manual says the same
thing from the other direction: "Depending on the spell, you may need to choose which enemy to
use it on (some spells will affect all enemies on the screen)". EarthBound's PSI splits by row
versus all. So a spell's **target shape is a property of the spell**, authored in data — which
is exactly what this template's own backlog nominated years of milestones ago — and shipping
groups with a single-target-only spell list has no precedent in the reference set.

**Status is tracked per enemy.** FF1's sleep is the clean case: SLEP is cast at every enemy,
but each sleeper rolls its own wake, and "any sleeping creature has a chance to wake up on its
turn based on its maximum hit points". A battle-wide asleep flag cannot express that. DQ2's
group-targeted Sleep implies the same, since a group can hold both sleeping and waking members.

**The award is summed, and paid once at the end.** FF1's gold is "the direct sum of the gold
values of all monsters killed", and its experience is a per-battle total (which FF1 then
divides among survivors and DQ does not — the division fork is §7a's, and this template
already chose DQ's rule). A foe felled early in a fight still counts toward the total.

**Fleeing is a property of the encounter.** FF1's escape "depends on your agility level";
SMRPG lets you run from ordinary fights and refuses for bosses and mandatory encounters; DQ's
Dragonlord cannot be fled. Nothing in the reference set makes escape depend on the *number* of
enemies — a fight is unfleeable because the designer said so. This template already says so
with geometry rather than a flag, which is the same statement made in level design.

**The read-out, and the one number nobody shows.** FF1 puts enemies left and the party right,
with enemy *names* in their own box and **four HP boxes for the party only**. DQ2's lower-right
window "shows the enemy names and how many of them are still active in the fight" — names and
a living count, no health. EarthBound shows the party's HP/PP and the enemy sprites. SMRPG
shows no enemy HP either, and makes it a *reward*: Mallow's Psychopath spends a turn to read
one enemy's remaining HP. Chrono Trigger shows none. **That is five references to zero against
displaying enemy health**, and it is the sharpest divergence this template has from its own
sources — `BattleScreen` has drawn a numeric `name  hp/max` bar for its single foe since M13.
Extending that bar per foe is therefore a deliberate, stated divergence rather than a neutral
layout choice, and it is recorded as one in `DECISIONS.md`.

**Authoring a formation, when encounters are visible.** Two models, both attested, and they
differ in exactly the way this template cares about. **One body names a formation**: SMRPG's
battles "begin by moving into an enemy on a main game map" while the composition lives in the
ROM's formation table, and Chrono Trigger's encounters sit at set points where "all encounter
triggers will always be the same". **Neighbours join in**: EarthBound's manual says a battle
begins when you touch an enemy and "occasionally, other nearby enemies may join in on the
fight, even though they were wandering around separately" — note *occasionally*, which makes
composition a function of a random roll and of where wandering sprites happened to be. The
first model keeps composition in level design where this template's determinism story needs
it; the second makes a fight's shape depend on the movement loop, which is the same objection
M13 raised against step-counter encounters in the first place.

**Does the crowd grow with the party?** M28 answered "what is a formation"; this is the
question M29 asks, and the genre answers it with a date. **Dragon Quest I** is one hero
against one monster. **Dragon Quest II** is the first in the series with a party — three
characters — and it is the same game in which "enemies could appear in much greater numbers",
against the first game where "all battles were 1-on-1". The two arrived *together*, in one
release, along with the three targeting shapes that only a crowd needs (one, group, all). That
is not a coincidence to reason around: a party and a formation are the same design decision
seen from opposite sides of the field, and the genre made it once.

Which means party size is not a variable an encounter reconciles with — it is a **fact the
encounter table is authored against**. **Final Fantasy I** makes this literal: its manual has
no smaller party in it — "each of the Four Warriors in your party must have an occupation",
and the selection "continues until all characters are chosen and named" — so every one of its
formations was written knowing exactly how many swords would answer it. DQ2 gets
there through the story instead — the Prince of Cannock is chased down and joins at the inn at
Leftwyne — and the one place DQ2 lets you carry on short-handed is deliberately *late*: when
the Prince falls ill, the others may cure him "**or may leave him behind**", long after the
fights he was sized against were authored.

What no classic-era reference appears to do is adjust a formation's **size** to whoever
happens to be in the party. Composition is authored in a table — FF1's dumped formation ROM,
SMRPG's 512 records, Chrono Trigger's fixed encounter points, all cited above — so the two
numbers are reconciled by a designer, once, rather than by the game at every encounter. The
runtime alternative does exist, but as a *modern* idea and a different knob: what searching
turns up is enemy **level** scaling, sold as engine plugins, not enemy counts chosen to match
a party. Stated as a limit rather than a finding: this is a negative, and negatives are only
as good as the looking.

The consequence for a template is sharper than for a game. **A formation sized for two is a
promise, and a companion the player may decline turns one design into two** — of which only
one was ever balanced. The genre's own answer is to put the second sword on the critical path,
and M29 takes it.

**Gap:** multi-enemy fights are the system this section's research exists for; they land in
M28 — the cursor, the formation on the record, the foe side of the screen — and M29 spends
them on the game itself, ordinary encounters in pairs and a boss with an escort. Still out
after that: SMRPG's Mack shape, where minions *respawn* and the boss leaves the field until
they are cleared, which is a fight shape rather than a bigger number; a bench larger than the
battle line; and followers on the map. Each is a recorded divergence with a revisit hook
rather than an oversight.

---

## 8. Save/load

**The convention.** Early 2D RPGs save at **designated places** — DQ's kings and churches,
FF's save points in dungeons and anywhere on the overworld, Pokémon's menu-save-anywhere
(which is the modern end of the trend). Inns restore HP for gold and double as the save
prompt. Multiple slots are usual; a slot shows where you are and how long you have played.

**This template diverges, deliberately.** Save and Load are pause-menu rows and work anywhere.
Slots live per game at `user://saves/<game>/slot_N.json`, each save **names its game**, and a
file that disagrees with its directory is parked rather than loaded. The slot list is drawn
with a *silent* read, so drawing a menu never parks a file or announces a load.

**Why.** Save points are a difficulty mechanic — they exist to make a dungeon a commitment.
That is a *game's* decision, and a template that forced it would be making it for every game
built on it. A game wanting save points ships them as an object with a `GameHooks` interaction.

**On the inn:** M21 added one (§10), and it deliberately does NOT offer to save. The genre
pairs the two; this template does not, because save-anywhere is a decision already recorded
above and pairing them would relitigate it as a side effect of a healing feature.

---

## 9. Progression

**The convention.** XP from fights, levels from an XP curve, stats **derived from level**, gear
as a **modifier on top**, gold as a separate currency that gear and consumables cost.

**This template.** Exactly this. `CombatDef` holds the curve and the per-level growth
(`max_hp`, `attack_at`, `defense_at`, `xp_for_next`); equipment never becomes a stat, it
arrives at the fight as two already-summed ints, because a stored stat would be a second
source of truth for a derived number. Gold has one writer and a spend is **refused, never
clamped**, so a purse cannot go negative by construction.

**Gap:** none. The curve is data (`xp_curve`), so a game re-paces itself without touching code.

---

## 10. Towns and NPCs

**The convention.** Towns hold a shop, an inn, and **townsfolk who walk** — the wandering NPC
is what makes a town read as inhabited rather than as a room with statues. Most give
directions, rumours, or the next objective. Chrono Trigger and DQ both animate crowds; FF's
towns are quieter but still moving.

**This template.** `behavior` on a map's NPC record is `static`, `wander` (bounded drift) or
`patrol` (an authored path, loop or ping-pong). A walking NPC is driven by the *player's own*
movement code — `NpcBrain` answers with an intent vector, the same axis pair a keyboard
produces — so nothing about movement is written twice. The town freezes during dialog, pause,
fights and game-over, because a speaker who wanders off mid-sentence is a bug.

**The inn, added in M21**, closes the loop — fight → lose HP → pay gold → fight again — and
gives gold its second use. It is a **conversation, not a counter**: DQ and FF innkeepers greet,
name a price, ask yes/no and fade to night, and there is nothing to browse, so it is built from
the dialog grammar (`spend_gold` with a mandatory `poor_next`, and `rest`) rather than from the
shop's screen. It is also the game's first **interior**, because an inn in the genre is a place
rather than a person standing in a square.

**Gap:** the inn does not save (deliberate — see §8), and there is no innkeeper flavour beyond
the transaction.

---

## 11. World structure

**The convention.** An overworld connecting towns and dungeons, gated by items (a key, a boat,
a spell) and by story flags, with the gate usually *visible* long before it opens.

**This template.** Maps with warps; warps and objects carry `requires_item` and
`requires_flag`, and anywhere a refusal can happen a `locked_dialog` is required — the refusal
is always *said*. The demo game is a village, a road and a cave, gated by a key.

**Gap:** none in shape. There is no overworld *map scale* distinction (a world map where towns
are icons), which is a game's authoring choice rather than a missing feature.

---

## 12. Title and game over

**The convention.** A title screen with New Game / Continue, and death returning there or to a
Continue prompt. The title screen is also where the genre puts its music cue and its first
impression.

**This template.** `GameOverScreen` is an overlay with Continue / Start again, because the game
boots straight into the world. `Router.State.TITLE` exists and means "nothing to drive yet".

**Added in M22.** The title carries the game's own name from its manifest, Continue and New
game, and says *"Continue (nothing saved)"* rather than offering a page of empty rows. It is an
**overlay over an empty world**, not a second scene: the world node is what resolves which game
is running, and it does that exactly once per process — a title scene with its own boot would
be a second answer to that question. The game-over screen gained the Title row its own comment
had promised since M13.

One asymmetry worth knowing, because it looks like an inconsistency and is not: the title opens
its cursor on a row a press will *do* something with, and the game over deliberately does not.
A dud first press is friction; an accidental restart of a run you just lost is a loss. A
scripted session found that one.

**Gap:** none. There is still no quit — a game that wants one ships it.

---

## 13. Magic and skills

**The convention.** MP, a spell list that grows with level or purchase, a battle command
beside Attack, and out-of-battle utility spells (heal, warp, light). Present in every reference
game — it is arguably the defining JRPG system after "turns".

**The resource.** A pool sized by level, not farmed separately. Final Fantasy VI, Dragon Quest
and Chrono Trigger all derive MP from the level (Chrono Trigger via the Magic stat); EarthBound
calls it PP and does the same. The one true outlier is Pokémon, which gives every *move* its
own PP counter rather than the caster one pool. Worth knowing: FF1 originally shipped D&D-style
spell CHARGES per tier, refilled at an inn, and the remakes retrofitted MP onto it — so even
the series that defines the convention did not start with it.

**Learning.** Automatic, at a level threshold, is the majority convention: Dragon Quest learns
Heal at level 3 and Hurt at 4 from a flat table, and Chrono Trigger's baseline Techs unlock at
a Tech-Point threshold with no instructor. Teach-by-item is real but historically a *supplement*
— DQ2's Words of Wisdom, later scrolls. Equip-a-pool (FFVII Materia, FFVI's Espers, which teach
at a percentage rate until the spell is permanent) arrives late in the series and is a system of
its own.

**The battle command.** Second, immediately after Attack, without exception across the games
surveyed: FF1's Fight / Magic / Drink / Item, FF3(VI)'s Fight / Magic / Items / Row, Dragon
Quest's Fight / Run / Spell / Item, Chrono Trigger's Att / Tech / Item. Pokémon is the one that
merges them — "Fight" *is* the move list, with no separate physical attack.

**Categories.** Elements are near-universal but shallow-to-deep: FF1's first tier is Fire / Ice
/ Lightning, Dragon Quest bakes the element into the spell NAME (the Frizz line is fire, the
Crack line ice), Chrono Trigger binds an element per character and makes it load-bearing for
combo Techs, and Pokémon runs a full 18-type matrix. EarthBound is the legitimate counterexample:
PSI is organised by FUNCTION — Offense / Recover / Assist / Other — with named damage types and
shallow resistance.

**The floor.** "A damage spell and a heal spell" is thinner than anything the genre shipped.
Dragon Quest 1 has one character and eight spells total, and even that set is damage, heal,
*Sleep* and *Stopspell*; Sleep is a tier-1 spell in FF1. A non-damage, non-heal effect is
present from the earliest unlocks, not added later.

**A standalone Magic screen** splits two ways. FF6 and Dragon Quest give it its own field-menu
command (FF6's greys out battle-only spells and shows Esper learning progress per spell);
EarthBound and Chrono Trigger fold it into the Status screen instead.

**This template.** MP is a `CombatDef` curve (`base_mp`/`mp_per_level`), so it is derived from
level exactly as attack and defense are, and it refills at an inn and on a level-up. A spell is
a `SpellDef` under `data/spells/`, and **knowing one is derived from level too** — `learn_level`
is the whole mechanism, so nothing is stored, migrated or handed out twice. `Magic` is the
second battle command, between Attack and Item. Three kinds — attack, heal, sleep — with the
attack kind dealing FLAT damage that ignores armour, which is what gives magic a job beside a
stronger swing. The Status page carries an `MP` line beside `HP`.

**Divergences, each recorded in `DECISIONS.md`:** no field-menu Magic page (an inn already
covers the out-of-battle restore, and there is no warp/light utility to hook one to), no
elemental resistance system (the spell's name carries the flavour, EarthBound-style), no
targeting step (fights are 1v1, so single-enemy and single-ally are unambiguous), and no
teach-by-item or equip-a-pool learning.

**Remaining gap:** buffs and debuffs. Sleep is the only status effect, and it acts on the enemy
only. EarthBound gives a whole quarter of its PSI to Assist; this template has no stat-modifying
spell and no duration system to hang one on.

---

## 14. Music

**The convention.** A theme per area, a battle theme, a victory fanfare, and a title theme —
the genre's most recognisable output.

**This template.** `AudioBus.play_music` exists and is called by nothing. Sound effects are
generated the way sprites are (a cue's shape in a bank, its voice in a `SoundStyle`), so the
machinery for generated *music* is closer than it looks.

**Added in M24, and it is the unusual version.** A tune is authored as NOTES in
`data/music/<id>.json` and performed by the same synthesiser the cues are, so the three shipped
voices give three renditions of one melody the way three sprite styles draw one rig — a
triangle pitched down in `dusk16`, a bit-crushed square in `gb16`. Not one note changes between
them.

Where it plays follows the genre's own habit rather than a rule: the title and the settled maps
(town, village) carry the theme; the cave, the hollow and the keep are silent. A map **states**
its music or states silence and never inherits, so the dungeon is not quiet-or-loud depending on
which door you came through — and a track already playing keeps playing, so crossing between two
maps that share a theme does not restart it.

**M26 scored the fights.** `battle_music` takes the room over when one opens; `victory_music`
plays once on a win and hands the room back to whatever the map states, which may be that map's
own silence. A defeat cuts the music outright, which is what every reference game does at a game
over. Both manifest fields default to empty, and empty means the pre-M26 behaviour exactly: a
fight sounds like wherever it happens.

The one thing that was code rather than data: a fanfare plays ONCE and then hands back, and
"once" is a property of the play call (`AudioBus.play_music_then`) rather than of the file — the
same tune could be somebody's title theme. Length remains the whole cost here: three tracks
across three voices is about 2.3 MB, at 43 KB a second per voice, which is why
`MusicTrack.MAX_SECONDS` exists.

**Remaining gap:** a game-over theme, and per-encounter themes (a boss that sounds like a boss).
Both are `deferred` in [DECISIONS.md](DECISIONS.md) — the first needs a screen to name it, the
second an `EnemyDef` field that would outrank the manifest's.

---

## Sources

Convergent-anatomy claims above are drawn from these, plus the reference games directly:

- [The Game Design Forum — JRPG UI Survey, 1992–99](https://thegamedesignforum.com/features/JRPG_UI_SURVEY.pdf)
- [Game UI Database](https://www.gameuidatabase.com/) — screen-by-screen captures
- [Dragon Quest wiki — command menu evolution](https://dragon-quest.org/wiki/Command_menu)
- [Final Fantasy wiki — Menu](https://finalfantasy.fandom.com/wiki/Menu) and
  [Optimize](https://finalfantasy.fandom.com/wiki/Optimize)
- [Realm of Darkness — DQ NES vs SNES differences](https://www.realmofdarkness.net/dq/snes-dq2-differences/)
- [Wikipedia — random encounter](https://en.wikipedia.org/wiki/Random_encounter)

Party research (§7a) is drawn from these, and each claim above names the game it came from:

- [Wikipedia — Final Fantasy](https://en.wikipedia.org/wiki/Final_Fantasy_(video_game)) and the
  [NES manual](https://world-of-nintendo.com/manuals/nes/final_fantasy.shtml) — four characters
  fixed at creation, commands entered for all four before a round runs, targeting an enemy
- [TASVideos — Final Fantasy 1](https://tasvideos.org/GameResources/NES/FinalFantasy1) — the
  turn order is a random shuffle of all thirteen combatants and ignores stats
- [Gamer Corner Guides — FF (NES) LIFE](https://guides.gamercorner.net/ff/spells/life) — revival
  is a spell that does not work in battle, or a town Clinic; no Phoenix Down on the NES
- [Dragon Quest wiki — Dragon Quest II](https://dragon-quest.org/wiki/Dragon_Quest_II) — Horii's
  stated reason for recruiting one at a time; the church's revival function; the three casters
- [Dragon Quest wiki — Party](https://dragon-quest.org/wiki/Party) and
  [Patty's Party Planning Place](https://dragon-quest.org/wiki/Patty%27s_Party_Planning_Place)
- [Dragon Quest wiki — Agility](https://dragonquest-wiki.com/Agility) — DQ's randomised
  turn-order formula, against FF1's stat-free shuffle
- [Take on the NES Library — Dragon Warrior II](https://takeontheneslibrary.com/finished/79-dragon-warrior-ii/)
  — the member-select window on Equip, group targeting, the eight-item per-character bag
- [EarthBound SNES manual](http://world-of-nintendo.com/manuals/super_nes/earthbound.shtml) —
  "Select the target of the attack, if applicable", B to cancel; cycling members in Goods
- [Wikipedia — Chrono Trigger](https://en.wikipedia.org/wiki/Chrono_Trigger) and
  [EarthBound](https://en.wikipedia.org/wiki/EarthBound) — three-of-seven, story joins
Multi-enemy research (§7b) is drawn from these:

- [TASVideos — Final Fantasy 1](https://tasvideos.org/GameResources/NES/FinalFantasy1) — nine
  enemy slots in a thirteen-entry shuffle; formations of "1-9 small, 1-4 large, or a mix of up
  to 6 small and 2 large", so a size budget rather than a count
- [Final Fantasy NES manual](https://world-of-nintendo.com/manuals/nes/final_fantasy.shtml) —
  the "finger" cursor over the enemy sprites; enemy NAMES in their own box and HP boxes for the
  party only; "some spells will affect all enemies on the screen"; escape depends on agility
- [Final Fantasy — Monster Formation FAQ](https://gamefaqs.gamespot.com/nes/522595-final-fantasy/faqs/59202)
  — the formation table dumped from ROM: composition is authored, never rolled
- [Side Quest Hell — Ineffective Attacks](http://sidequesthell.blogspot.com/2015/06/ineffective-attacks.html)
  and [Gamer Corner Guides — SLEP](https://guides.gamercorner.net/ff/spells/slep) /
  [Sleep](https://guides.gamercorner.net/ff/statuses/sleep) — the stale-target whiff as a
  consequence of entering commands first, and sleep rolled per sleeping enemy
- [Realm of Darkness — Dragon Warrior II spells](https://www.realmofdarkness.net/dq/nes-dw2-spells/)
  and [Dragon Quest wiki — DQ2 spell list](https://dragon-quest.org/wiki/List_of_spells_in_Dragon_Quest_II)
  — one / group / all as a property of each spell (the two disagree on Firebane's shape)
- [Take on the NES Library — Dragon Warrior II](https://takeontheneslibrary.com/finished/79-dragon-warrior-ii/)
  — one to eight monsters, big sprites taking two slots; group targeting hitting one at random
  and whiffing at an emptied group; the lower-right window of names and living counts
- [Super Mario Wiki — How to battle!](https://www.mariowiki.com/Super_Mario_RPG:_How_to_battle!),
  [Mack](https://www.mariowiki.com/Mack) and [Psychopath](https://www.mariowiki.com/Psychopath)
  — the cursor skipped at one enemy; a boss with respawning minions as its own fight shape;
  enemy HP as a move you spend a turn on rather than a number on screen
- [Data Crystal — Super Mario RPG ROM map](https://datacrystal.tcrf.net/wiki/Super_Mario_RPG:_Legend_of_the_Seven_Stars/ROM_map)
  — 512 formation records behind the bodies you touch on the map
- [EarthBound SNES manual](http://world-of-nintendo.com/manuals/super_nes/earthbound.shtml) —
  two rows of enemies when there are enough; "occasionally, other nearby enemies may join in on
  the fight" — the merge model, and its *occasionally*
- [EarthBound Wiki — Instant Win](https://earthbound.fandom.com/wiki/Instant_Win) — skipping a
  foregone fight, and refusing to when the enemies outnumber the standing party
- [How Dragon Quest's Battle System Evolved](https://playdragonquest.wordpress.com/2020/08/03/how-dragon-quests-battle-system-evolved/)
  — DQ1's battles "all 1-on-1"; DQ2 bringing a party of three AND enemies "in much greater
  numbers" in the same release, with one/group/all targeting arriving beside them
- [Dragon Quest wiki — Prince of Cannock](https://dragon-quest.org/wiki/Prince_of_Cannock) —
  the second character joins by story at the inn at Leftwyne, and the party "may leave him
  behind" only much later, when he falls ill
- [Final Fantasy NES manual](https://world-of-nintendo.com/manuals/nes/final_fantasy.shtml),
  again — "each of the Four Warriors in your party must have an occupation", chosen and named
  before the quest starts: no smaller party exists to author encounters for
- [StrategyWiki — Chrono Trigger gameplay](https://strategywiki.org/wiki/Chrono_Trigger/Gameplay)
  — fixed encounter points; contact starts the fight on the map itself

- The user's own [`jrpg-design-codex`](https://github.com/Ali0600/jrpg-design-codex) — design
  *patterns* (progression systems, build economies), not screen anatomy. Cite it for what a
  system should do, not for what a screen should contain.
