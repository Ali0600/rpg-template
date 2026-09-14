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

**For §7d only, two more are admitted, each for a reason.** The 2D Zeldas (Zelda II, A Link to the
Past, Link's Awakening), because their combat can be read out of reverse-engineered code rather than
remembered, and Ni no Kuni: Wrath of the White Witch, because it is the JRPG whose field-to-arena
shape a second fight resolver borrows. Ni no Kuni is neither 2D nor of the era, and is admitted on
secondary sources only, marked wherever it is cited. Neither is a reference for any other section.

---

## Audit — the template against the conventions

| Surface | The convention | This template today | Status |
| --- | --- | --- | --- |
| [Menu anatomy](#1-menu-anatomy) | Item / Equip / Status / Save as sibling commands | Resume, Items, Equipment, Status, Save, Load, Sound | **met** (M20) |
| [Equip screen](#2-the-equip-screen) | Slot list → candidates → preview the delta | Slot list, candidates, take-off row, swap preview, Atk/Def readout | **met** (M20) |
| [Status screen](#3-the-status-screen) | Level, HP, XP-to-next, stats, worn gear | A page of world-worded lines | **met** (M20) |
| [Inventory](#4-inventory) | List, counts, description, a use verb | List, counts, description, **no use verb** | **partial** — [use is a game's business](DECISIONS.md) |
| [Shop](#5-shops) | Windows over the world, keeper, quantity, prices, a headed list | All of it, and the columns are named since M42 | **met** (M18.1, chrome M42) |
| [Dialog](#6-dialog) | Bottom window, revealed text, choices, a named speaker, a portrait | Framed box, speaker in its header, the speaker's face, reveal, choice band, size-gated | **met** (M42) — no advance indicator, [named](#6-dialog) |
| [Battle](#7-battle) | Random encounters, turn menu, a party; in an action RPG, a sword on the field | Visible enemies, timed presses, **a party** | **met** (M27) for the party; encounters and timing [diverge deliberately](DECISIONS.md); a real-time resolver [researched](#7d-action-combat-the-sword-the-arena-and-the-fixed-step) and its shape [decided](DECISIONS.md) (M49); what its screen shows [read the same way](#7d-action-combat-the-sword-the-arena-and-the-fixed-step) before it was built, then built behind the same seam and shipped as a second game, The Barred Gate: Arena, picked on the title (M50) |
| [Save/load](#8-saveload) | Save points or inns; menu save later in the era | Slots from the pause menu, anywhere | **diverges deliberately** |
| [Progression](#9-progression) | Level, XP curve, stats from level, gear as modifier | All of it | **met** |
| [Towns & NPCs](#10-towns-and-npcs) | Walking townsfolk, shops, an inn | Static, wander and patrol NPCs; a shop; an inn | **met** (M21) |
| [World structure](#11-world-structure) | Overworld → towns → dungeons, gated | Maps and warps, gated by items and flags | **met** in shape |
| [Title & game over](#12-title-and-game-over) | Title screen with Continue; death → menu | Title with Continue / New game; game-over routes back to it | **met** (M22) |
| [Credits](#12a-credits-and-what-a-game-owes-the-people-who-drew-it) | A staff roll after the ending; a Credits screen where a licence requires one | A Credits row on the title, opening the composed list the generator writes | **met** (M43) — [rolled at the title rather than after an ending](DECISIONS.md), which is the licence's own instruction |
| [Magic & skills](#13-magic-and-skills) | MP, a spell list, a battle command | MP from the level curve, five spell kinds, a Magic command, an MP status line | **met** (M25) — [no field-menu page](DECISIONS.md) |
| [Statuses](#13a-statuses-and-which-way-they-point) | Boosts and afflictions as one system, aimed either way, counted in turns | `BOOST` / `SAP` / `SLEEP`, on the party as well as at it, expiring with the fight | **met** (M30) — [no persistent affliction](DECISIONS.md) |
| [Terrain](#15-terrain) | One tile per cell, and edges between materials drawn as their own tiles | Hand-drawn LPC ground at 32px; a cell is still one id, and the 47 edge shapes are composed from quarters into the atlas | **matches** — water and path both carry a ring and their boundary is drawn from one side, which is the [named divergence](DECISIONS.md) from a true blend |
| [Interface chrome](#16-interface-chrome-and-the-anatomy-of-a-battle-screen) | Framed windows with header bands, a highlight cursor, coloured HP/MP, portraits | All of it, on every screen: one pixel font, framed windows with bands, a cursor bar, gold HP and violet MP, and faces in the fight, the menu and the conversation | **met** (M42) — the enemy-bar and save-slot divergences are [recorded](DECISIONS.md) |
| [Options](#16b-options-where-a-player-changes-the-game-and-what-they-may-change) | A settings surface, on the title or in the field menu, with text speed and often the window's own look | An Options screen reached from both, carrying Sound and a named window palette | **met** (M46) — [palettes rather than colour bars, and a cycling row rather than an axis](DECISIONS.md); no text speed |
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
Resume, Items, Equipment, Status, Save, Load, Options. Rows are an enum the view indexes its labels by, so the
order lives in one place. Save and Load are separate rows rather than one page with a mode,
which is the DQ/FF slot-select shape flattened by one level. Options sits at the bottom where
Config does, and `Resume` is explicit rather than Escape-only because this game boots straight
into the world and has no title screen to retreat to.

**Gap:** none. Equipment and Status both moved here in M20 (§2, §3). Equipment had been folded
into the bag, which is the one place the reference games never put it — and it was there
because the menu had no row for it, which is what makes a missing command more than a cosmetic
gap. Options sits at the bottom where Config does - it was a Sound row that WAS the volume until
M46, and it opens a page now, which is what the references do.

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

**Two things M42 fixed that eighteen milestones of gates could not see**, because the counter had
no layout audit at all until then. Its help line told the player to press **Z**, which this game
binds to nothing — `interact` is Space, Enter and E. And the price column was drawn across the
whole row at the same position as the name, so a long enough item name ran underneath its own
price; the demo's own wares are short words, which is why nobody ever saw it.

**Gap:** none for a template. Rotating stock, synthesis and deal boards are *game* patterns
(the user's own `jrpg-design-codex` covers those) and deliberately not template scope.

---

## 6. Dialog

**The convention.** A window at the **bottom** of the screen, text **revealed** rather than
appearing at once (with a blip per character in most), advanced by the confirm button, and
choices presented as a cursor list. Text speed is a setting in EarthBound, Pokémon and Final
Fantasy alike; the box's own colour is offered by EarthBound (window *flavours*, which are
palette swaps) and by Final Fantasy VI (R/G/B bars), while Pokémon Gen I offers no window
customisation at all and Gen II offers a numbered border STYLE rather than a colour - see 16b,
which is disassembly-derived. Portraits are common but far from universal in the 2D era.

**This template.** `DialogRunner`/`DialogBox`: two lines at the bottom, revealed, choices in a
band below that appears only when there are choices, `cancel` closes a plain line but not a
choice. Uniquely, **the build measures every shipped line against the box** and fails if it
would not fit — a `RichTextLabel` clips silently, so a fact written into the data would never
reach the player and every headless gate would still pass.

A choice can also carry money: `spend_gold` with a mandatory `poor_next`, which is the
refusal the player hears. See `DECISIONS.md` for why money is shown-and-refused where an item
requirement is hidden.

**What the box LOOKS like, added in M42** — the section had position and behaviour and nothing
about chrome, which is what a rebuild needed. Read from screenshots on the Game UI Database
(Persona 4 Golden's Dialogue & Speech captures) rather than recalled:

- **The speaker is NAMED, in a tab of its own** sitting above the box's top-left corner in a
  second fill, not inline with the text. It is the one piece of the box that changes colour per
  speaker in Persona, and it is what makes a conversation with two people readable.
- **The portrait sits LEFT, and it is big** - a bust that overlaps the box's edge rather than a
  square inside it. The text column starts to its right.
- **There is an ADVANCE INDICATOR**, bottom-right of the box, marking "there is more, press on".
  Every reference has one; the shapes differ (a blinking triangle, a filled circle, an animated
  glyph) and the position does not.
- **Choices are their own small boxes**, stacked and right-aligned ABOVE the text box rather than
  inside it, so the question stays readable while the answers are being chosen.

**This template's adaptation, and what it does not take.** The speaker moves into the box's own
header band rather than a floating tab, because at 320x180 a tab outside a box six pixels from
the screen edge has nowhere to sit. The portrait is a 12-design-pixel FACE inside the box rather
than an overlapping bust, for the same reason - a Persona bust is a third of the screen's height,
and the equivalent here would be the whole box. Choices stay in their band INSIDE the box, where
they have been since M5 and where the fit gate measures them; lifting them out would put a second
window over the world for every question.

**Gap:** ~~no portraits~~ — **closed in M42**: a dialog node names its own `portrait`, so a
conversation with two speakers shows two faces, and a sign or a chest shows none. No per-player
text speed, and no advance indicator: the box reveals a character at a time and a reader can see
it is still going, but a finished line looks exactly like a line with nothing after it, which is
the one piece of the anatomy above this template still does not have.

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

### 7c. The battle message, and what happens when it does not fit

M36 needed this before widening a caption that had outgrown its window. It answers two questions
§7 never asked: how big the message area is, and what these games do when a line is too long.

**Sources note.** All four claims below come from disassemblies and decompilations of the shipped
games, grepped directly — the fan wikis do not carry window dimensions. That route also caught its
own hazard worth recording: a clone into an existing directory failed while a piped `tail` reported
success, which is the exact pipe-swallows-the-exit-code trap `CLAUDE.md` warns about; the files
were re-fetched and checksummed before anything here was written down.

**Every one of these message areas holds more than one line, and this screen held one.** Pokémon
Gen 1 draws its box `ld c, $12` — 18 interior columns — over four interior rows of which **two**
carry text. EarthBound's window table declares the in-battle box `$0018` wide by `$0006` tall,
which its own newline routine halves and decrements into **3** text lines. Dragon Warrior's window
definition is `.byte $18 ;Window Width. 24 tiles` by `.byte $05 ;Window height. 5 blocks`, giving
**22 × 8**, and battle uses that same window. Final Fantasy I is the outlier in the other
direction: it has no message *area* at all but **six combat boxes**, and composes an attack's
result across several of them at once.

**What happens to a line that does not fit — the games genuinely disagree.**

- **Dragon Warrior WRAPS, automatically.** It is the only one here that does, and the code is
  explicit: `CMP #$16` against a variable the source calls the position *"after current word is
  taken into account"*, with a companion routine classifying word boundaries. Then it scrolls
  (`CPX #$08`, *"at or beyond the last row"*) and waits on a control character.
- **Pokémon does NOT wrap.** There is no wrapping code anywhere; every break is hand-authored as
  a control character — `<LINE>` jumps to line 2, `<CONT>` shows the ▼, waits, and scrolls two
  lines, `<PARA>` clears the box for a fresh page.
- **EarthBound scrolls**, freeing the top line's tiles and copying upward, with a blinking prompt
  in battle.
- **Final Fantasy I never faces it**, because it never writes a sentence: its entire battle
  vocabulary is 35 one- or two-word constants.
- **Nobody clips.** Not one of the four truncates.

**And on multi-target messages the genre is unanimous — against what this template does.** Not one
of these games composes a sentence naming several targets. Every one resolves a multi-target
effect as a LOOP that redraws a short, single-target message per target. Final Fantasy I says so
in its own comments: its all-enemies path sets each foe as the defender in turn, draws the
defender box, resolves, and then calls a routine whose header reads *"clears all drawn combat
boxes except for 2: the attacker and the spell"* — the caster's name and the spell hold still
while the target half cycles. Pokémon's battle text bank contains **zero** messages naming two
battler slots. At 18 to 22 columns, a line naming every target's damage was never physically
available to these games.

**This template.** The caption wraps to `BattleScreen.MESSAGE_LINES` — **two**, the genre's own
floor and the number `DialogBox` already draws and size-gates against — and the layout audit
measures it at declared capacity. A one-line caption was the divergence, and it was not a chosen
one: the label simply had no width, and text past the window edge was drawn where nobody could
see it.

~~**Divergence:** the sweep caption names every foe's damage on one line.~~ **Closed by M37**,
which took the genre's answer whole. A sweep says one line per foe, in turn — and the first half
of each is identical, so the caster and the spell hold still while the target half cycles beneath
them. That is Final Fantasy I's *"clears all drawn combat boxes except for 2"* adapted to a
caption with two lines rather than six boxes, and it was only expressible once M36 gave the
caption its second line.

**It deleted a special case rather than adding one**, which is the strongest argument that the
research was right. M34 had given a *uniform* formation a single combined verdict — "They are
weak to it" — because a caption listing identical numbers can say nothing useful, and that needed
a matching special case in the content gate to attribute a clause naming nobody. Sequencing
removed both: every clause now sits in a line that names the foe it is about, so a formation that
answers uniformly is told about exactly as clearly as a mixed one.

**Unverified, and named rather than guessed:** Chrono Trigger has no public decompilation, and
Dragon Quest II — the first in its series with enemy *groups*, and so the likeliest to contradict
the multi-target finding — has no reachable disassembly either. Settling that one needs ROM-level
work rather than a repo clone.

---

### 7d. Action combat: the sword, the arena, and the fixed step

M49 needed this before a second way of resolving an encounter is built. Everything above is a
fight chosen from a menu; the backlog's largest item is a fight played with a sword, in an arena
that opens when the player meets an enemy. So this section reads the mechanics out of the 2D Zeldas
and the arena's shape out of Ni no Kuni, the two references the Scope note admits for this section
alone.

**Sources note.** The mechanics come from three reverse-engineered codebases, cloned at pinned
commits and grepped for every write to each variable: the Link's Awakening DX disassembly
(`zladx/LADX-Disassembly` at `880d24c`), the A Link to the Past C reimplementation
(`snesrev/zelda3` at `fbbb3f9`) and the Zelda II RAM map (`FiendsOfTheElements/z2disassembly` at
`c4c3a4c`). They are marked **(a)**, as in §8. Ni no Kuni has no such source, so everything said
about it is **(b)**, from an encyclopedia article and reviews, and is secondhand. A number below was
read at the line that writes it and the routine is named, because one variable takes different
values in different routines; where only a label was found, only the label is given. tcrf.net was
not used: this pass it served an anti-bot page in place of the article.

**A sword is a box in front of the facing, alive for a counted number of frames.**

- **(a) A hitbox is a TYPE, not a shape each enemy carries.** Link's Awakening packs it into one
  byte (`src/constants/hitbox.asm`): two bits choose a collision-box size, five choose a class
  (`HITFLAGS_HITBOX_ENEMY`, `_NPC`, `_PICKUP` and so on), and bit 7 is `HITFLAGS_IGNORE_HITS`.
  `ConfigureEntityHitbox` copies that class's four bytes, x, y, width and height, from one table
  into the entity's slot. Whether the sword can hit anything at all is a single flag,
  `wSwordCollisionEnabled`.
- **(a) A swing is nine steps paced by a table.** In A Link to the Past, `Link_CheckForSwordSwing`
  advances a step whenever a delay counter runs out and reloads it from `kSpinAttackDelays`,
  recomputing the sword's hitbox as it goes; past the ninth step a held button becomes a charge.
  Walking the table from a fresh press gives about twelve frames of swing. That figure is derived
  from the table and assumes the delay counter starts at zero; it was not measured in play. Letting
  go and pressing again from the fourth step on starts the swing over.
- **(a) A charge is a counter too.** Link's Awakening's `wSwordCharge` fills to `$28` for a spin
  attack, and `wIsUsingSpinAttack` runs down from `$20`. Zelda II's map names a sword-slash timer
  (`$50A`) and gives no value.

**Being hit makes you untouchable for a while, on both sides, and it is a counter, not a flag.**

- **(a) Link, A Link to the Past.** A hit is queued and applied in `Link_ControlHandler`, which
  starts `countdown_for_blink` at **58** unless it is already running. While it runs,
  `Sprite_AttemptDamageToLinkPlusRecoil` returns before doing anything. The counter is decremented
  inside the routine that draws Link (`src/player_oam.c`), in the same test that picks alternate
  frames, so the invulnerability and the flicker a player sees are one number.
- **(a) Link, Link's Awakening.** The spike trap's routine, `HurtBySpikes`, sets
  `wIgnoreLinkCollisionsCountdown` to `$10`, sixteen frames in which Link collides with no entity,
  and `wInvincibilityCounter` to `$30`, which its own comment calls 48 frames; `bank0.asm` counts
  the second down once a frame. The routine for an enemy's touch was not traced to its value.
- **(a) Link, Zelda II.** An invulnerability timer at `$518` and an injured-state timer at `$50C`.
- **(a) Enemies.** In A Link to the Past a sword hit hands `Sprite_GiveDamage` a hit timer of
  `0x9d` (`Sprite_CalculateSwordDamage`), and while an enemy's hit timer is non-zero it cannot hurt
  Link by touch (`Sprite_CheckDamageToPlayer_1`) and projectiles pass it by. Link's Awakening keeps
  two tables: `wEntitiesIgnoreHitsCountdownTable`, during which the entity takes part in no
  collision, and `wEntitiesFlashCountdownTable`, whose comment says a flashing entity takes no
  damage from the sword or projectiles. Zelda II's `$40E,X` is an enemy hit state that flashes.

**A hit is a push, the push has a size, and a wall ends it.**

- **(a) Link is shoved by what hit him, by an amount that depends on what it was.** A Link to the
  Past's `Sprite_ApplyRecoilToLink(k, vel)` aims `vel` from the enemy through Link and gives half of
  it as a hop. The call sites choose the size: **24** from touching an enemy, **48** or **32** when
  the sword strikes something armoured, **16** from an Octoballoon, **8** or **16** from a guard's
  parry, and **4** when a blow is simply turned aside. Each also takes control away through
  `link_incapacitated_timer`, set to 19 on contact and 16 on the others.
- **(a) An enemy is shoved the other way.** `Sprite_AttemptZapDamage` pushes a struck enemy away
  from Link at `0x50` mid-swing and `0x40` otherwise, and a recoiling enemy skips its own routine
  for the frame (`Sprite_ReturnIfRecoiling`, at the top of the rat's).
- **(a) A wall ends the push and the invulnerability together.** Link's Awakening fills
  `wEntitiesRecoilVelocityX/Y` with a vector away from Link (`ConfigureEntityRecoil`), applies it
  only while the entity's ignore-hits countdown runs, and `StopEntityRecoilOnCollision` zeroes that
  countdown the moment the entity touches a wall in the direction it is mostly travelling.

**Touching an enemy hurts, and the test is not run on every frame.** **(a)** In A Link to the Past
contact is a box overlap (`Sprite_DoHitBoxesFast`, `CheckIfHitBoxesOverlap`) and the damage is read
from a table by the enemy's bump class and Link's armour (`kPlayerDamages`). The ordinary path
tests each sprite on one frame in four, offset by its slot (`(k ^ frame_counter) & 3` in
`Sprite_CheckDamageToPlayer_1`), and another path one frame in two. It was a budget for the
hardware and costs nothing in determinism: which frame a sprite is tested on is a pure function of
the frame counter and the slot. Link's Awakening sends an ordinary enemy's contact through one
shared routine, `DefaultEnemyDamageCollisionHandler`, which the roaming enemies call on every
update.

**Enemies wander, and the ones that react read where you are on a timer.**

- **(a) Link's Awakening.** Octoroks, Moblins and Iron Masks share `AnimateRoamingEnemy`
  (`src/code/entities/03_moblin.asm`), which draws a new countdown of 32 to 63 frames from
  `GetRandomByte` each time the last one ends. At one fixed point in that countdown, if
  `GetEntityDirectionToLink` says the enemy already faces Link, it fires a rock or an arrow: it
  shoots when it happens to be facing you and never turns to find you. Being hit switches it to its
  second state with a `$40` countdown.
- **(a) A Link to the Past.** The rat (`Sprite_6D_Rat`) walks at 24 along one axis, turns when it
  meets a wall, and pauses and chooses again with `GetRandomNumber`. A guard routine,
  `Soldier_Func12`, re-aims at Link once every 32 frames, offset by the guard's slot, with
  `Sprite_ApplySpeedTowardsLink(k, 16)`, turns its head to face him, and holds that heading until the
  next re-aim. The same call moves Ropa, Geldman, the hog spearman and the Tektite. Chasing is a
  periodic re-aim, not homing on every frame.
- **This template** already has the wandering half in `NpcBrain`: bounded drift, dwell counted in
  frames, draws from a seeded stream. Its `intent` reads no target, so the chasing half is new.

**Ni no Kuni: a battlefield you are sent to, and what could not be confirmed.** **(b)** Wikipedia
describes fights on an open battlefield the party roams freely, and a win paying experience, money
and items. Nintendo World Report adds that backing away escapes melee while spells still land;
RPGFan that losing costs half to all of the party's money or sends it back to the last save;
TheGamer that the battle commands include running away. **What could not be reached** is how a
fight begins. A walkthrough and a set of guides that would have said whether an enemy that has seen
you starts the fight by touching you both refused the fetch, and the claim reached this pass only as
a search snippet, so it is not made here. It carries no weight: this template's encounters fire on
arriving next to an enemy (M13's rule, `_try_encounter`), and nothing a second resolver needs
depends on how Ni no Kuni opens a fight.

**Dying, and leaving.** **(a)** In A Link to the Past, a hit that would leave no health makes
`Link_ControlHandler` switch the whole game to module 18, `Module12_GameOver`, a mode of its own that
saves the music and the palette and closes an iris, rather than a window over the field. A Zelda has
nothing to flee, because the fight happens where Link stands and leaving is walking away. Ni no Kuni
**(b)** has both an arena and a way out of it. This template's turn fight can already end in
`BattleLogic.Outcome.FLED`, which `_on_battle_finished` handles on the same arm as a victory.

**A fixed step is what makes any of it replayable.** Glenn Fiedler's *Fix Your Timestep!* is the
standard statement: a simulation stepped by a varying delta behaves differently at different frame
rates, and one stepped by a fixed delta reproduces exactly from the same inputs. Godot's
`_physics_process` runs at a fixed rate, 60 a second by default, and every number above is a count
of frames at a fixed rate as well. The engine's own tools for this genre are `Area2D`, for overlap,
with its signals and its `monitoring`/`monitorable` pair, and `CharacterBody2D`, whose
`move_and_slide` belongs in the physics step and whose `MOTION_MODE_FLOATING` is for a world with no
floor. They are named here as what a build would first reach for, not as the rules.

**What a second resolver takes from it.** The fork itself is the M49 entry in `DECISIONS.md`; these
are the findings it rests on.

- Invulnerability on both sides, and a swing's live frames, are counts of physics frames stated in
  data, the shape `CombatDef.timed_window_frames` already has.
- A hitbox is a size an enemy names from a small table, Link's Awakening's scheme, rather than
  geometry every enemy carries.
- A push is a distance with a size per cause, stated in tiles by M44's rule, and a wall ends it
  together with the invulnerability that came with it.
- Touching a foe hurts, and the same invulnerability counter guards it.
- Foes wander, which `NpcBrain` already does, or re-aim at the player on a period, and every draw
  comes from a labelled seeded stream.
- The flicker is the invulnerability made visible, so there is no separate hurt pose to draw.
- The rules are a pure simulation stepped once per physics frame, `BattleLogic`'s discipline, so a
  balance gate and a replayed session can run them with no scene.

**What the screen shows while the sword is out.** Added in M50, before the arena's screen was
built, from the same three codebases at the same commits.

- **(a) The player's health is always on screen, and no ordinary enemy's is.** A Link to the Past's
  `Hud_Update_Hearts` (`src/hud.c`) draws the life meter from `link_health_current` against
  `link_health_capacity`, and nothing in `hud.c` reads `sprite_health`, the enemies' table. Link's
  Awakening builds its heart row as draw commands (`LoadHeartsCount`, `src/code/bank2.asm`) and has
  no enemy meter either.
- **(a) A struck enemy flashes, and the flash is its protection.** A Link to the Past's
  `Sprite_TimersAndOam` (`src/sprite.c`) writes `sprite_hit_timer[k] * 2 & 0xe` into the sprite's
  OAM palette bits on every frame the hit timer runs, and clears them when it ends, so the enemy
  cycles colour for exactly as long as it is being hurt. Link's Awakening's per-frame entity update
  (`src/code/bank14.asm`, after `.flashCountdownEnd`, commented "invert the palette every 4 frames")
  switches the second palette on and off in four-frame spans while `wEntitiesFlashCountdownTable`
  runs - the table whose own comment says a flashing entity takes no damage from the sword. The
  picture and the rule are one counter, which is what the paragraph above found for Link.
- **(a) Zelda II draws a meter for a boss.** Its RAM map names `$C7` "Boss Hit Points (00-20)" and
  `src/prg0.asm` carries the "draw boss hp bar" routine beside Link's own life meter (`$774`).
  Ordinary enemies get the flash (`$40E,X`, "causes flashing") and no meter.
- **(b) Ni no Kuni** draws HP and MP as coloured bars on its battle screen and separates the
  targeted enemy from the rest with a dark translucent strip, according to an interface analysis.
  Whether every enemy carries a bar or only the target does could not be confirmed: the page that
  would have said answered 403.

**What the arena takes from it.** The leader's health is the one number always drawn, in a window of
its own, with no magic and no command list, because there is nothing to choose. A foe's health is
still shown, as ONE bar for the foe last struck - or the nearest while nothing has been - which is
§16's rule for the turn fight rather than Zelda's. A template whose every other fight shows the
aimed-at foe's bar would otherwise hide the one number a sword changes, and Zelda II's boss meter
and Ni no Kuni's target are the precedent for drawing it. A foe that has just been struck flickers
for exactly as long as it cannot be struck again, and so does the player; there is no hurt pose,
because no sheet in this template has one.

**How the swing is drawn, what the fight stands on, and what the screen names.** Added in M50,
after the arena's first photographs showed a flat block for a sword and a bare panel for a floor. From
the same three codebases at the same commits (zelda3 `fbbb3f9`, Link's Awakening `880d24c`, Zelda II
`c4c3a4c`).

- **(a) A sword is a sprite the art draws, stepped by the counter that paces its hitbox.** A Link to
  the Past's `LinkOam_Main` (`src/player_oam.c`) draws the sword as OAM tiles of its own, at a
  position read from `kDrawSword_y` and `kDrawSword_x` per direction and step, indexed by
  `button_b_frames` - the counter the swing advances through `kSpinAttackDelays` (`src/player.c`) and
  `CalculateSwordHitBox` reads. An ordinary swing is nine drawn steps and nothing trails it: the
  swing sparkle belongs to the stronger swords, and the charge sparkles to the spin attack. Link's
  Awakening does the same in three steps: one index built from `hLinkDirection` and
  `wSwordAnimationState` picks the sword's direction, its drawn offsets and its hitbox in
  `UpdateLinkAnimation` (`src/code/bank2.asm`), and `func_020_4AB3` (`src/code/bank20.asm`) writes the
  two sprites.
- **(a) A fight is fought on the ground it began on.** A Link to the Past has no battle mode at all:
  `kMainRouting` (`src/misc.c`) runs enemies inside `Module07_Dungeon` and `Module09_Overworld`, over
  the room's own layers. Zelda II, which does cut to a side-view scene, picks the scene from the
  terrain: touching an overworld enemy sets `$0748` (`src/prg0.asm`), and
  `bank7_Determine_the_Random_Battle_according_to_Links_position_in_OW` (`src/prg7.asm`) indexes a
  table of scenes by `$0563`, "Type of terrain Link is facing in OW" - desert, grass, forest, swamp,
  graveyard, road, lava.
- **(a) Zelda names a button beside the thing it uses, and prints no controls line.** Link's
  Awakening's status bar puts a tile before each item slot, commented `B[   ] A[   ]`
  (`src/code/bank20.asm`); A Link to the Past's item menu draws Y, X, L and R beside the equipped item
  and A beside its "DO" (`src/hud.c`). Neither says how to move.

**What the arena takes from it, second pass.** The swing is the art's own: a hero whose sheet draws
LPC's slash plays it, one picture per step of the swing's own frames, which is both Zeldas' shape. Art
with no swing of its own - the procedural rig's - shows a bright edge sweeping the reach instead. The
floor is the ground under the encounter the player walked into: Zelda II's terrain-picked scene, and
in a Zelda without scenes the ground the fight was always on. The help line is this template's own
convention rather than a borrowing - every screen here names its keys, because a shop once named a
key nothing binds - and Zelda's letters beside its slots are the closest the references come.

**Unverified, and named rather than guessed:** how a Ni no Kuni fight begins; the values Link's
Awakening writes when an enemy touches Link and when the sword strikes an enemy (only the spike
trap's were traced); what unit A Link to the Past's `0x9d` hit timer counts in; whether Link's Awakening's `$BD` and `$BB` status-bar tiles
are drawn as the letters B and A, which its tilemap and comment agree on but whose glyphs nobody looked at; and whether its
swing's delay counter starts at zero, which the twelve-frame figure assumes. No 2D action RPG outside
Zelda has a public disassembly documenting any of this (Secret of Mana's is a tracking issue rather
than code, and none turned up for Crystalis or Ys), so a second lineage could not be checked.

---

## 8. Save/load

**The convention, re-researched for M39 and it corrected two things this section used to say.**
The findings below are marked **(a)** where they come from a disassembly or from ROM text the
project decoded itself, **(b-official)** for a publisher's own manual, and **(b)** for a
reputable secondary source. The wikis for three of these games are bot-blocked (403) or paywalled
(402), which is what forced reading the binaries — the same route M33 took for elements.

| Game | Where you save | Heals? | Cost | Slots |
|---|---|---|---|---|
| Dragon Quest I | King Lorik, and nowhere else **(a)** | no | free | 3, chosen at the title |
| Dragon Quest II / III | a king **(b-official)** | — | free | 3 |
| Dragon Quest IV+ | a **church** **(b)** | — | free (confession) | 3 |
| Final Fantasy I | the **inn**, or a tent/cabin/house on the overworld **(a)** | inn: full HP+MP | inn: paid | **1** |
| Pokémon R/B | anywhere, from the START menu **(a)** | no | free | 1 |
| EarthBound | a **telephone**, to Ness's dad **(a)** | no | the pay phone costs $1, not the save | 3 |
| Chrono Trigger | save points, and anywhere on the world map **(b-official)** | **no** | free | 3 |

**Three claims that are widely repeated and are wrong.** Dragon Quest's save prompt is *not*
"Dost thou wish to record thy deeds?" — that construction belongs to the **continue** question
that follows it; the save prompt is *"Will thou tell me now of thy deeds so they won't be
forgotten?"*, answered by *"Thy deeds have been recorded on the Imperial Scrolls of Honor."*
**(a)**. FF1's TENT restores **30** HP, not the 60 the guides quote **(a)**; and its HOUSE
restores MP only *after* the save branch, which the disassembly's own comment calls bugged.
And a Chrono Trigger save point does **not** heal — it is where a purchased **Shelter** may be
used, which is a different claim entirely **(b-official)**.

**A free save point heals NOTHING, in every single reference.** Kings, churches, telephones and
Chrono Trigger's save points all restore nothing at all. The one place saving heals fully is
FF1's **inn** — a paid rest that happens to also save. That is the whole answer to "should the
save point top the player up": no, unless it charges.

**Every one of them tells you it happened.** DQ1's scroll line, FF1's `Now saving..!` plus a
dedicated jingle, Pokémon's `<PLAYER> saved the game!` with `SFX_SAVE`, EarthBound's *"I have
created a record of your adventure to this point."* **(a)** Three of them also announce
FAILURE — Pokémon's `The file data is destroyed!` is the canonical one.

**The genre's verb is "record", not "save".** DQ writes deeds on scrolls; EarthBound's telephone
menu option is literally **"Record"** and Maxwell asks *"Would you like me to keep a record of
your journey?"* **(a)** — Dad never says the word "save". This template's chronicler is worded
against that finding rather than around it.

**None of them picks a slot AT the moment of saving.** DQ1, EarthBound and Chrono Trigger choose
the file at the **title screen**; FF1 and Pokémon have one file and nothing to choose. Only
Pokémon asks an overwrite question (`The older file will be erased to save. Okay?`), and only
because it is confirming against a single file.

**This template makes WHERE an axis, and diverges on the slot question.** `GameConfig.save_policy`
is `anywhere` (Pokémon's shape, and the default) or `at_point` (the Save row is gone; the
`open_save` dialog effect is the only way to write one). Slots live per game at
`user://saves/<game>/slot_N.json`, each save **names its game**, and a file that disagrees with
its directory is parked rather than loaded. The slot list is drawn with a *silent* read, so
drawing a menu never parks a file or announces a load.

The **divergence** is that a save point here shows a slot list, where every reference either has
one file or chose it at the title. It is stated rather than fixed, for the reason the foe bars
are: this template's pause menu has picked a slot at save time since M5 and has been played that
way, and a save point that answered the question differently would be two answers to one
question. `docs/DECISIONS.md` carries the fork and the genre's own answer as the deferred
alternative.

**Why an axis rather than a decision.** Save points are a difficulty mechanic — they exist to
make a dungeon a commitment — and that is a *game's* call, not a template's. Before M39 this
file argued that a game wanting them "ships them as an object with a `GameHooks` interaction",
which was true and was also the template declining to have an opinion: the pause menu's Save row
would still have been sitting there offering the thing the design had just forbidden.

**On the inn:** M21 added one (§10) and it still does NOT save, even though FF1's does. Here that
is a content choice rather than a template one — a game that wants FF1's inn puts `open_save`
on the innkeeper's yes beside its `spend_gold` and `rest`, which is three keys on one choice and
needs no new mechanism.

**A damaged save is TOLD, not hidden — added in M32.** The canonical case is Pokémon's *"The
file data is destroyed!"*: the save is checksummed, and a file that fails is declared unusable
to the player's face rather than presented as a blank slot. This template used to do the
opposite by accident — `SaveManager._read` distinguished "nothing here" from "here and
unreadable" and `peek()` collapsed both to null, so a slot list drew a file it could not read as
`empty`. That is the one wording that invites saving over it, and the thing being saved over is
the file a player would want back. The row now says `damaged`. Nothing else changed: the load
page already refused anything with no data behind it, and a save into that slot has parked the
original bytes since M5.

The reason is *not* shown. Which fault a file has — malformed JSON, a failed validation, a save
naming a different game — is a developer's question, and `load_slot` pushes the whole list as an
error when a player actually tries it.

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

### 12a. Credits, and what a game owes the people who drew it

**The convention, and why it does not decide this one.** The 16-bit references put no credits
option on the title at all: a staff roll plays after the ending, as the last thing a finished run
shows you. That route is not available to a template — it ships a vertical slice with no ending —
and it is the weaker route anyway for the thing credits are actually *for*, since a player who
never finishes never sees them.

**What decides it is an obligation, not a taste.** The demo is drawn in Liberated Pixel Cup art
and 38 of its 42 files carry CC-BY-SA 3.0, so the terms are a requirement rather than a courtesy.
The Universal LPC Spritesheet Character Generator's own README states them, and this is quoted
from the source rather than summarised:

> Make sure this credits file is accessible from within your game or app and can be reasonably
> discovered by users (for instance, show the information on the "Credits" screen directly, or
> provide a visible link).

and, on what may be shipped:

> Distribute the entire CREDITS.csv file along with your project **or** Distribute a composed list
> containing the credits for the assets you use in your project.

and, on the floor:

> If you generate a sprite using this tool, or use individual images taken directly from the
> `spritesheets` subdirectory from this repo, you must at least credit all the authors (except for
> CC0 licensed artwork).

Its own example statement names four things: the artists, the source (the LPC project on
OpenGameArt, as a URL), the licence with its URL, and a pointer to the detailed credits. So a
**"Credits" screen reachable from the title** is not this template inventing a placement — it is
the placement the licence's own instructions name first.

**This template.** `tools/gen_sprites.gd` has written `assets/generated/<style>/credits.json` since
M40 — the composed list, every file with its artists, licences and URLs, merged and sorted so the
drift gate can compare it — and it is a resource, so it ships in the pack. `LICENSE.txt` beside it
carries the share-alike sentence and is a `.txt`, so it does **not** ship. Between M40 and M43 the
composed list therefore existed and no player could reach it, which is the gap M43 closes.

**The shape, and the two things that forced it.** The screen is a notice page and then every
artist named in full, one per row, paged. Both halves were decided by measurement rather than by
preference:

- **Artists rather than one row per work.** The payload is 43 artists over 42 works. A work's row
  would read *title — artists — licence*, which fits comfortably for the nine terrain files (one
  or two artists each) and not at all for the LPC character layers, which carry up to eleven. The
  rows that would be trimmed are exactly the ones with the most people to attribute, and a
  truncated artist is a failed attribution rather than a cosmetic loss. Naming every artist in
  full and pointing at `credits.json` for the per-work mapping is what the README's own example
  statement does.
- **Paged rather than scrolled.** A 320x180 window at one font size holds about fourteen rows, so
  43 names is four pages however it is presented. Scrolling is not available here for a harder
  reason than room: every layout audit in this project collects `Panel`, `Label`, `ColorRect` and
  `TextureRect` by exact class, so a list inside a scroll container is a screen no gate can see —
  the M42 failure exactly, where an audit that measured two node classes could not see a readout
  drawn across the sprite it described. Chaining is this format's own pagination already, in
  `DialogBox`'s `next`.

**Divergence, stated:** the genre rolls credits after an ending and this template puts them behind
a title row. The reason is above, and it is the licence's.

**Gap:** the template's own font (Pixel Operator 8, CC0) asks for nothing and is named anyway, on
the notice page. Nothing else in the tree carries an attribution obligation: the audio, maps,
dialog and rigs are authored or generated here.

**Could not be reached on 2026-09-04, and therefore not cited above:** the Final Fantasy wiki's
Title screen page (HTTP 402) and the Game UI Database's category pages (403). A search index
summarised the former as saying that mobile and current-console re-releases of the early Final
Fantasy games add a staff-roll or "Additional Credits" option to the title menu where the
originals had none — which would support the placement chosen here, and is recorded as
**secondhand** rather than cited, because the page itself could not be opened.

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
covers the out-of-battle restore, and there is no warp/light utility to hook one to), ~~no
elemental resistance system~~ (**closed by M33 — see §13b**), no targeting step for a spell that
reaches everything, and no teach-by-item or equip-a-pool learning.

### 13b. Elements, and whether the game tells you

M25 gave spells element NAMES and no matrix, recorded as a divergence. This is the research M33
needed before closing it, and it answers two questions §13's Categories paragraph does not: how
much an element is actually WORTH, and whether the player is TOLD.

**Sources note.** The fan wikis for Final Fantasy were bot-blocked (402/403) and the Internet
Archive was offline during this pass, so the FF1 and Pokémon numbers below come from
disassemblies of the shipped ROMs — reverse-engineered renderings of the actual binary, which is
a stronger source than a description of it, not a weaker one. Where only a secondary source was
reachable it is marked, and where nothing was reachable the claim is left out rather than guessed.

**The multiplier is smaller than everyone remembers.** "Double damage on a weakness" is the
folklore and it is not Final Fantasy I: its damage-spell routine halves on resistance and, on
weakness, copies-halves-adds-back — the disassembly's own comment reads `damage *= 1.5`. So
**1.5× weak, 0.5× resist**, for magic. Pokémon Gen 1 is where 2× actually lives, as
`SUPER_EFFECTIVE = 20` scaled by ten, against `NOT_VERY_EFFECTIVE = 05` and `NO_EFFECT = 00`.
Both games therefore multiply, and the genre's honest range for a weakness is 1.5× to 2× rather
than a single number worth copying.

**FF1's physical weakness is a FLAT +4, and it never fires.** Worth knowing for two reasons. A
weakness bonus does not have to be multiplicative — but a flat one stops mattering as damage
grows through a game, which is the composition hazard `lessons.md` already carries about
mitigation order. And the elemental swords were meant to use it: the disassembly annotates the
lookup `BUGGED - uses player elemental weakness as attack element. This is always 0`, so half of
the game's own elemental system was unreachable on shipping. The series that defines the
convention did not manage to ship it working.

**Dragon Quest's resistance is a CHANCE, not a multiplier.** This is the fork that matters most
here, and it is the opposite model: a resisted spell does not do less, it does nothing. Gamer
Corner's stat glossary for the NES game is explicit that a monster resists at a rate and that
"if the spells work, they will deal full damage" [secondary]. Later entries tier the chance
rather than the damage (DQ6's Burning Breath connects at 50/20/10/0% by resistance tier). Modern
Dragon Quest switched to multipliers, but the 125%/150%/200% figures belong to the 2024 HD-2D
remake and must not be cited for the 1987 game.

**Immunity is normal; absorption is not attested.** Pokémon ships `NO_EFFECT = 00` as a
first-class value, Dragon Quest reaches the same place by fully resisting at a rate — and FF1
has no immunity tier at all, its resistance being only ×0.5. Healing from an element turned up
in none of the sources actually reached, so a template that wanted it could not justify it from
these games.

**Whether the game TELLS you splits, and the split tracks the arithmetic.** Pokémon announces
every non-neutral hit: `It's super effective!` and `It's not very effective...`, with immunity a
separate message on a separate path (`It doesn't affect ‹target›!`), and neutral hits saying
nothing — its routine compares the multiplier to neutral and returns silently when equal. Dragon
Quest announces the FAILURE, which is all a binary mechanic leaves to announce. Final Fantasy I
says nothing whatever: its complete battle-message table — all 35 constants — contains no
elemental string of any kind, and a resisted damage spell produces no message at all. (A resisted
STATUS spell does print, but the string is the generic "Ineffective" also used for hitting a dead
target, so it never says why.)

That is the useful shape: **where effectiveness is a multiplier, a bare number cannot tell the
player what happened** — is 12 big? compared to what? — so Pokémon supplies the words. Where it
is binary, the outcome is self-evident and only the failure needs any. FF1 is the outlier that
multiplies *and* stays silent, and it is also the one whose elemental system half-worked.

**This template.** `SpellDef.element` is an open string, `EnemyDef.resistances` is element →
percent taken, and a fight multiplies. Percents rather than tier words: a tier word puts the
multiplier in the script, which is the literal-a-designer-would-change this project keeps out of
code, and it caps the genre at two tiers when the references run from quarter damage through
immunity. The demo ships 200/150/50, so the table holds three different answers and the argument
for a number rather than a word is visible in the content.

Damage is floored at 1 wherever the element does not stop the spell outright, so *resisted* and
*immune* stay distinguishable — 1 power halved is 0 by integer division, which would collapse
them. Zero comes back only from a zero percent, and it is SAID.

**Announced, on Pokémon's side of the split rather than Final Fantasy's**, because this template
multiplies and the reasoning above applies directly: a weakness appends "X is weak to it", a
resistance "X shrugs most of it off", and a neutral hit appends nothing at all. A sweep is the
one exception and it is the same rule — its caption already names what each foe took side by
side, so the comparison is in the numbers.

**Divergence:** resistance is a multiplier, never a chance, so Dragon Quest's model is not
available here. Flee odds and damage variance were both made deterministic in M13 so a designer
can reason about a fight and a QA script can replay it byte-for-byte, and a roll to negate a
spell is exactly that kind of number. Recorded in `DECISIONS.md`.

**Remaining gaps:** elements on physical swings (FF1's Ice Brand, and the half of its system that
never worked), and party-side resistance — nothing shields the player, because no enemy move
carries an element. Both carry hooks in `DECISIONS.md`.

---

### 13a. Statuses, and which way they point

M25 left this section closing on a gap — sleep was the only status effect and it acted on the
enemy only. This is the research M30 needed before closing it.

**The party is a legitimate target, and every reference says so.** Final Fantasy I's manual
sells its cures by naming the afflictions: `PURE` *"will cure you if you are poisoned by an
enemy"*, `SOFT` *"will restore to life any character turned to stone by an enemy spell"*, and
Ghouls *"have the capability to paralyze members of your party"*. Darkness and silence are
there too, as the things `LAMP` and `MUTE` deal in. So the era's status vocabulary runs at the
party from the first game in the set, and a template whose only status verb points outward is
missing half of it.

**Buffs on the party are attested in all three.** FF1 has `TMPR` on one ally — *"Weapons
strength … by 14 points"* — and `FOG` on the caster — *"Shields by envelopment in a thick fog.
Armor will increase 8 points"*. Dragon Quest's **Buff** doubles one character's defence for 3
MP and lasts 4–6 turns, and its mirror **Sap** halves one foe's for 6–9. EarthBound devotes a
whole PSI branch to it: Assist is *"creating shields, boosting or weakening the stats of an ally
or foe (excluding HP or PP), or inflicting a status ailment"*, and its members are Offense up,
Defense down, Shield, PSI Shield, Hypnosis, Paralysis and Brainshock. Note what that list is:
**boosts and afflictions are one system pointed two ways**, not two systems.

**Durations are counted in turns, and in the references they are ROLLED.** DQ's 4–6 and 6–9 are
ranges. This template will not roll them — flee odds and damage variance were both made
deterministic in M13 so that a designer can reason about a fight and a QA script can replay it,
and a status duration is the same kind of number. A recorded divergence with an existing
precedent rather than a new argument.

**How a status is SHOWN is the part the manuals do not answer.** FF1's manual describes every
ailment's effect and never once says how the screen reports it. Two independent secondary
sources say the game replaces the character's **HP readout** in the battle block with an
abbreviation — `POIS`, `STON`, `DARK` — which is a sensible thing to do with a block that has
room for one number and nothing else. Both first-hand confirmations are bot-blocked (403/402),
so this is cited as secondary and marked as such rather than quoted as fact.

**This template.** A status is battle-only: it lasts a stated number of turns and expires with
the fight, which is where DQ's Buff and FF1's TMPR/FOG live too, and which keeps `BattleLogic`
pure — no save field, no migration, nothing written. Two spell kinds rather than one signed
number (`BOOST` at an ally, `SAP` at a foe), because a verb spelled as the absence of its
opposite is one every reader has to decode. Enemy moves gain the same vocabulary, which is what
makes the system point both ways. The battle caption keeps its numbers and **appends** a tag:
FF1 replaces the HP readout because its block cannot hold both, and this one has a caption line
*and* a bar, so keeping both is the honest adaptation rather than an imitation of a constraint
this screen does not have.

**Remaining gap:** persistent afflictions. FF1's poison follows you onto the map and drains as
you walk, and DQ's does the same; here a status cannot outlive the fight it was inflicted in.
That is a save field, a migration, a map tick and a cure — a milestone of its own, and
`DECISIONS.md` carries it with its hook.

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
own silence. Both manifest fields default to empty, and empty means the pre-M26 behaviour
exactly: a fight sounds like wherever it happens.

~~A defeat cuts the music outright, which is what every reference game does at a game over.~~
**That sentence was wrong, and M32 is the correction.** Final Fantasy I ships **"Dead Music"**
in 1987, and each Final Fantasy since has had its own Game Over scene — FF5's is "Requiem". The
references *change* what is playing at a death; they do not fall silent. So the template's
silence was a divergence written down as a convention, which is worse than a plain gap: a gap
gets filled, and a convention gets cited. It survived four milestones because it sat in a code
comment justifying the branch it described.

The one thing that was code rather than data: a fanfare plays ONCE and then hands back, and
"once" is a property of the play call (`AudioBus.play_music_then`) rather than of the file — the
same tune could be somebody's title theme. Length remains the whole cost here: three tracks
across three voices is about 2.3 MB, at 43 KB a second per voice, which is why
`MusicTrack.MAX_SECONDS` exists.

**M32 closed both remaining gaps.**

*The game over.* `GameManifest.game_over_music`, played through the same `play_or_silence` a map
entry uses — "a game states its game-over music or states silence" is the same sentence, and it
already had a function. A LOOP rather than a jingle: the screen is sat on while a player decides
what to do about a lost run, which is the one place a one-shot would leave them in silence.
Empty is still legal and is still what every session recorded before M32 hears.

*The boss.* `EnemyDef.music`, outranking the manifest's. **Which fights get a second battle
theme is the thing the references disagree about**, and that disagreement is the argument for
putting it on the enemy rather than behind the `boss` flag:

| game | a second battle theme? |
| --- | --- |
| Dragon Quest I (1986) | yes — eight tracks, one of them reserved for the Dragonlord |
| Final Fantasy I (1987) | **none.** One battle theme, played for every fight *including Chaos* |
| Final Fantasy II (1988) | "Battle Theme 2" for major bosses and the final boss |
| Final Fantasy IV (1991) | "Battle 2" for every boss but two |

A field on the enemy sits anywhere on that range without the template choosing for every game
built on it. In a formation the **first foe that states a track wins**, scanned in the order the
map record names them — a formation with a boss anywhere in it is a boss fight, and reading only
the first entry would make the Keeper's theme depend on where his escort was written down.

Note the order in which the genre acquired these: Dragon Quest had a boss theme before Final
Fantasy existed, and Final Fantasy had a game-over theme in the same game that had no boss
theme at all. Neither is downstream of the other, which is why they are two fields.

**Remaining gap:** whether the victory fanfare should differ after a boss. Deferred in
[DECISIONS.md](DECISIONS.md) — it is a second field answering a second question, and a fled boss
fight cannot happen here anyway (a boss refuses every escape).

---

## 15. Terrain

**The convention.** Ground is a grid of small square tiles, and the interesting part is what
happens where two materials MEET. Every reference draws those edges as tiles of their own: a
tileset carries a fill for each material plus a ring of edge and corner pieces, and the map
places them by hand or an editor places them from a rule. The count is what makes it concrete -
LPC's own ground sheets are a 3x3 ring of edges and corners around one centre fill, which is the
shape a Tiled or Godot "terrain" tool consumes, and the same nine-piece arrangement turns up in
tileset after tileset because it is the minimum that closes every corner.

Beside that, the vocabulary is small and stable across the era: a walkable ground, a second
ground that reads as a path or road, an impassable material (water, cliff, wall), something
green and solid to break the space up, and - indoors - a floor, a door, and stairs. This
template's twelve ids are that list plus a decor pair (a table and a rug), which is why the demo
could change art without changing a single map.

**Measured, not recalled.** The layout claim above is measured from the art this milestone
imports: `grass.png`, `dirt.png` and `water.png` in the LPC base tileset are each 3 cells by 6 at
32px - a 3x3 transition ring, a pair of decor clumps, and a row of plain fills. What the
reference CONSOLES did is left thin here on purpose: the NES and SNES tile data that would settle
it is reachable only through disassemblies this pass did not open, and the secondhand accounts
are about compression and metatiles rather than about edges. So the convention above is stated
from artwork that can be counted rather than from prose about games.

**How many pieces it takes.** Two numbers settle the shape of any implementation, and both are
Tiled's own, from its terrain documentation. A CORNER set or an EDGE set over two terrains is
sixteen tiles; a MIXED set - matching corners AND sides, which is what a shoreline needs - is
256, "but reduced sets like the 47-tile Blob tileset can be used with this type as well". Godot
carries the same three modes and says they "correspond to the previous bitmask modes autotiles
used in Godot 3.x: 2x2, 3x3 or 3x3 minimal"; its documentation states no rule for what the
engine picks when no tile matches exactly, which is one reason this template does not use it.

Thirteen pieces to forty-seven shapes is the gap every implementation has to close. The answer
in wide use is to compose each of a cell's four QUARTERS from the same pieces - RPG Maker's
autotile format, named here from the format rather than from a source, so treat the attribution
as secondhand while the arithmetic is not.

**This template.** A tile in a bank may carry a `ring` - LPC's twelve pieces - and an `over` list
naming the ground it is an edge against. The generator composes all 47 shapes from quarters of
those pieces and appends them to the atlas; the world picks one per cell from that cell's eight
neighbours. **A cell is still one tile id in a map file**: the shapes live in columns past the
paintable tiles, which no map can spell, so the map format and every map file are exactly what
they were. Since M48 an editor is SHOWN the shapes - both translators write the column the game
draws and fold it back on import - and Tiled gets a terrain brush per edge block.

**Divergence, named: the brush paints the ground, not the water.** Tiled's terrain model colours
the sides and corners BETWEEN cells, which is two-sided by construction; this bank has one side
draw each edge. The two meet only one way round - paint the grass around a pond and the water
shapes itself, exactly as the game draws it (108 of 108 cells, measured through Tiled's own
filler) - and a one-tile pool has no colouring of its own to paint. See `docs/DECISIONS.md`.

Water is an edge against grass and against `path`; a path is an edge against grass. Everything
else - walls, floors, doors, decor - is a hard edge, which is what the references do too: an
interior wall meets a floor at a line, not a fringe.

**Measured against the art, twice.** The quarter scheme is not a preference here, it is what the
demo's own geometry requires: the village and hollow ponds were ONE tile tall and half the paths
are ONE tile wide, and no whole piece is drawn for a cell that stops to the north AND the south.
And the art has a scale of its own - LPC's water bank is about ten pixels of transparency plus
six of mud per edge, so at 32px a pond one tile tall has no water left in it at all: both banks
meet in the middle and it reads as a mound of earth. Both ponds were deepened by one row rather
than the shoreline being thinned, because the bank is the artist's drawing and the pond is ours.
Every scripted session still passes byte-identically; the rows added were a dead-end corridor
against a wall and a strip of grass nothing walked.

**Divergence, named:** an edge between two materials that BOTH carry a ring is drawn once, from
ONE side - whichever of them names the other in its `over` - rather than as a true blend. In the
demo that is water against path, at the cave pool, and it is the only place the case arises.

The blend was built and looked at on 2026-09-05 rather than argued about, and it is rejected for a
reason that is not aesthetic: an edge is composed from the drawing tile's ring over the OTHER
material's plain art, so a path cell drawing its verge against water comes out mostly water-blue -
and a path cell is WALKABLE. Sixteen tiles the player crosses would read as water. One side draws
it, and `TileBank.problems()` refuses a bank whose tiles each name the other.

This paragraph said "by whichever the bank names first" until M48, which described nothing the code
does: `TerrainEdges.pick_group` ranks one tile's own groups and never sees a neighbour's.

**Gap, named:** animated water (LPC ships the frames; the atlas has one row and the runtime has
no clock for it) and multi-tile objects like a whole tree, which need a record rather than a cell.

---

## 16. Interface chrome, and the anatomy of a battle screen

The one surface this file had never covered: not what a screen SAYS, but what it is made OF.
Every section above asks where a feature lives and what sits beside it; this asks what a window,
a cursor and a readout look like, which is the question a player answers in the first second and
no gate can ask at all.

**Researched from pictures, 2026-09-03**, because a description of an interface is worth very
little - the claims below were read off screenshots on the Game UI Database (Sea of Stars, id
2196; Persona 5 Royal, id 618; Clair Obscur: Expedition 33, id 2060), with written sources cited
separately where a picture cannot carry the claim. What could not be reached is named at the end
rather than filled in from recall.

**The convention.** Four things, and every reference in this file has all four.

1. **A window is a FRAME, not a rectangle.** A filled panel with a border a shade or two lighter
   than its fill, and hard corners. Final Fantasy and Dragon Quest draw a literal blue box with a
   white rule; Chrono Trigger and EarthBound let the player choose the fill; Sea of Stars draws a
   dark navy panel with a one-pixel lighter border. Nobody draws text straight onto the world.
2. **A window has a HEADER.** A band across its top in a second fill, carrying the page's name or
   the acting character's, in capitals or a heavier face. It is what tells a player which
   question a list is answering - Sea of Stars heads its shop list "ITEM NAME / OWNED / PRICE"
   and its command window with the character's own name.
3. **The cursor is a HIGHLIGHT, or a hand.** The selected row is drawn on a lighter bar (Sea of
   Stars, Persona 5, Clair Obscur) or pointed at by a hand or triangle glyph (Final Fantasy,
   Dragon Quest, EarthBound). What no reference does is what this template did: prefix the row's
   own text with `>`, which shifts the text sideways and makes the marker part of the string.
4. **HP and MP are COLOURED, and they are the only coloured things.** Persona 5's rule is
   explicit and stated by its own designers - the game "did not use sub-colors other than in
   HP/MP elements, in order to keep the distinctive red color" - with HP turquoise and SP pink.
   Sea of Stars: HP gold, MP violet, bottom-left, one block per member. Clair Obscur: a thin bar
   per member down the left edge. A bar drawn in the same grey as the help text, which is what
   this template drew until M42, is a readout a player has to stop and parse.

**Where the party lives, and where the enemy's health does.** The party's readout is a fixed
block: bottom-left in Sea of Stars, bottom strip in Persona 5, a column down the left in Clair
Obscur - each with a **face portrait** beside the numbers. The enemy side is the interesting
divergence, and the three references disagree in a way worth recording:

| Game | Enemy health, on screen |
| --- | --- |
| Sea of Stars | none. Above an enemy sit damage-type "locks" and a turn counter; no bar, no number |
| Persona 5 | none. A name banner only |
| Clair Obscur | ONE long thin bar, top centre, for the targeted enemy alone; the rest show nothing |

That is the same finding S7b recorded from the 2D era (FF1 names only, DQ2 names and a living
count, EarthBound and Chrono Trigger nothing, Super Mario RPG charging a turn to peek) - eight
references now, and not one draws a bar per enemy. **The template's own answer since M28 was a
bar and a number per foe**, which put a readout on top of every sprite it belonged to. M42 takes
Clair Obscur's shape instead: one bar for the foe being aimed at. See `DECISIONS.md`.

**The command menu sits BESIDE the actor.** Sea of Stars opens a small framed window next to the
character whose turn it is, headed with their name. Persona 5 fans its commands out of the acting
character as angled tiles - "all buttons point to the character that is in the turn", and "the
character is placed on the left, the monster is on the right, which allows players observe the
scene without being disturbed by the menu". At 320x180 the fan is not available, but the rule
behind it is: the menu belongs where the eye already is, and it must not cover the fight.

**One banner names what is happening.** Sea of Stars runs a wide framed banner across the top
carrying the action ("Attack", "Spike Shower"); Clair Obscur names the targeted enemy above its
bar. It is the same job as this template's caption line and confirms the shape.

**This template, before M42.** Every screen was a bare `ColorRect` and a set of `Label`s: no
border, no header, no highlight, no portrait, three colours (`panel`, `text`, `dim`) with the HP
bar drawn in two of them, and a `>` prefix for a cursor. It had none of the four. The person this
is built for looked at the battle screen and said it "looks so low quality", which is the same
sentence M18's shop and M19's equipment screen earned, for the same reason: the surface was built
from this repo's idioms rather than from the genre's.

**Sources.** Screens read on gameuidatabase.com (game pages 2196, 618, 2060). Persona 5's colour
rule and team structure from Siliconera's write-up of the Atlus design interview; the command-tile
geometry from Jiaxin Wen's "The UI Design of Persona 5" (2017) and p5ui.tumblr.com. Sea of Stars'
HUD vocabulary (HP bottom-left, the MP meter beside it, the locks and turn counters over enemies)
from Game Voyagers' combat guide. Clair Obscur's minimalism from its producer in TweakTown, and
its combat vocabulary from the Wikipedia article's Gameplay section, which cites the developers'
own Sekiro and Final Fantasy VIII-X influences.

**Not reached, and therefore not cited:** seaofstars.fandom.com (402), interfaceingame.com's
Clair Obscur page and the ArtStation HUD-concept galleries (403), the Medium UX write-up (403),
and the itch.io Persona 5 study (403). Nothing above rests on them.

### 16a. Away from the fight: the menu, the counter, the save point, the title

Everything above is read off a battle screen. These are the same four rules on the surfaces a
player spends most of their time in, and they are here because §1, §5, §8 and §12 all describe
ORDER and BEHAVIOUR and say nothing about chrome - so a rebuild of those screens had §16's
generalities and nothing else to go on.

**A save screen is windows over the world, and each slot is its own frame.** Sea of Stars: a
titled bar reading "Save Game", then one framed panel per slot carrying its number, its name and
its timestamp right-aligned, a POINTER hand to the left of the chosen one, and underneath a
details panel - Level, Gold, Time, Location - with the party standing beside it as their own
walking sprites. The cave behind it all stays visible.

**This template diverges on one of those and says why:** rows in ONE window rather than a frame
each. Sea of Stars offers three slots and this template offers up to twelve, and twelve framed
panels do not fit 180 pixels - `GameConfig.MAX_SAVE_SLOTS` is the capacity the layout audit
measures at. The rest carries: the window sits over the live world, it is titled, and the chosen
row is marked.

**A shop is a row of windows, and the list is HEADED.** Sea of Stars heads its stock list with
its columns - "ITEM NAME", "OWNED", "PRICE" - which is the one thing that makes a list of numbers
readable without being told what they are, and the template's counter has had all three columns
since M18.1 with nothing naming them.

**A pause menu puts the party beside the commands.** All three modern references show the cast in
the menu: Sea of Stars as portraits and stats, Persona 5 as angled portrait tiles, Clair Obscur
as a column of framed portrait cards. This template drew a list of commands and nothing else -
who you are was somewhere else entirely, on a status page one press away.

**A title screen is mostly its own name.** Nothing in the references argues for a framed window
around a title's rows; what they share is that the name is the largest thing on screen and the
rows sit under it in the lower half. That is what this template already does, so the title's
rebuild is chrome on the rows and nothing more.

**Gap, named:** no window in this game is player-recolourable, which is the one convention in
this section the template does not follow. It is an options surface rather than a chrome one -
the mechanism (`ui_colors` on the style) already exists, and what is missing is a place to choose
from and somewhere per-player to keep it. Which references actually offer it, and in what form,
is 16b below.

---

### 16b. Options: where a player changes the game, and what they may change

**Where it lives is not settled, and the split is not arbitrary.** The two shapes in the
references are *a row in the field menu* and *a row on the title*, and which one a game picks
follows from whether its settings need a save file to belong to.

- **Final Fantasy VI: the field menu only.** Config is a state of the field menu
  (`MENU_STATE::CONFIG_INIT`, `src/menu/field_menu.asm:384`), so it is reached from the same list
  as Item, Skills, Equip and Status. There is no options entry on its title.
- **Pokémon Red/Blue: both, and the same routine.** The title menu is `CONTINUE` / `NEW GAME` /
  `OPTION` (`engine/menus/main_menu.asm:344-350`), and `OPTION` calls `DisplayOptionMenu`
  (`:443`); the in-game start menu carries `OPTION` too (`home/start_menu.asm:76`,
  `jp z, StartMenu_Option`). A player who wants to slow the text down before naming their rival
  can, and so can one who is already three towns in.
- **EarthBound: neither — it asks at the start of the run.** Text speed, sound and the window
  *flavour* are chosen during new-game setup, before the character is named
  (Legends of Localization, *EarthBound / MOTHER 2 Translation Comparison: New Game*).
- **Sea of Stars: both, and the accessibility settings are somewhere else again** — they are
  collectible **Relics** toggled from the Status page rather than options rows.

**What they let a player change, and the one that matters here is the window.**

Final Fantasy VI's Config offers a window **pattern** and a window **colour**, and they are two
different settings: `"Window"` sits above the row `"1 2 3 4 5 6 7 8"` (eight patterns), and
`"Color"` below it edits **R**, **G** and **B** on three gauge bars, aimed at either the `"Font"`
or the `"Window"` by a toggle, with a `"Reset"` beside them (`src/menu/menu_text.en.inc:363-381`).
So the genre's window customisation at its most generous is *free per-channel colour on two
components*, not a menu of themes.

Pokémon Gen I offers **no** window customisation at all: `DisplayOptionMenu` draws exactly three
settings and a cancel — `TEXT SPEED` (`FAST`/`MEDIUM`/`SLOW`), `BATTLE ANIMATION` (`ON`/`OFF`),
`BATTLE STYLE` (`SHIFT`/`SET`) (`engine/menus/main_menu.asm:443-470, 599-610`). Gen II adds one:
`FRAME`, cycling a numbered `:TYPE` (`pokecrystal`, `engine/menus/options_menu.asm`) — a border
**style**, not a colour. EarthBound's flavours (Plain, Mint, Strawberry, Banana, Peanut) are
palette swaps over one set of window graphics: the tiles are shared and only the palette differs,
which is why the flavour names are about colour and nothing about shape.

**What this template does, and the two places it diverges.**

An `Options` row on the title **and** in the pause menu, opening one screen — Pokémon's placement,
because this template has a title screen that FF6 does not and a player should not have to start a
run to turn the sound down. Its rows are **Sound** (four named steps) and **Window** (a named
palette).

- **Divergence 1: named palettes, not three colour bars.** FF6 edits one window's RGB, and this
  template's window is not one colour: `SpriteStyle.UI_ROLES` is eight roles, and a screen reads
  `panel`, `border`, `header`, `select`, `text`, `dim`, `hp` and `mp` separately. Three sliders
  would either recolour one role and leave seven behind, or need twenty-four. A named palette
  changes all eight at once and keeps every one of them a decision somebody made.
- **Divergence 2: a cycling row, not an axis.** Confirm advances the value, which is the M14
  decision for Sound and holds for the same reason — no menu view here reads `move_left`/
  `move_right`, so an axis would be a second input contract for one row.

**Gap:** text speed, which EarthBound, Pokémon and FF6 all offer and this template does not.
Recorded with its hook rather than built: `DialogBox` reveals one character per frame.

### 16c. Options that change how the game plays

Added in M51, from the two disassemblies §16b already reads, cloned at pinned commits this time
(`pret/pokered` at `a1a22aa`, `everything8215/ff6` at `8130132`), and one prose source.

**What the references let a player change about play, and when a change takes hold.**

- **(a) Final Fantasy VI: the pace of a fight, read when the fight begins.** Config's first row is
  `Bat.Mode`, Active or Wait, and below it `Bat.Speed` and `Msg.Speed` (1 to 6), `Cmd.Set`,
  `Gauge`, `Sound`, `Cursor` and `Reequip` (`src/menu/menu_text.en.inc:334, 347, 350-357`). Active
  or Wait is one bit, `$08` of `$1d4d`, flipped by `ChangeConfigOption_00`
  (`src/menu/config.asm:888-898`). The battle engine copies it as a fight starts:
  `src/battle/init.asm:69-81` reads `$1d4d`, sets `w7e3a8f` when the bit is on ("enable wait
  mode") and turns the low three bits into the battle speed constant `w7e3a90`, and the ATB clock
  reads the copy (`src/battle/atb.asm:11`). Config is a state of the field menu (§16b), so a change
  takes hold at the next fight.
- **(a) Pokémon Red/Blue: two rules of a fight, read at the moment each applies.** `BATTLE STYLE`
  and `BATTLE ANIMATION` are bits 6 and 7 of `wOptions` (`constants/ram_constants.asm:35-36`).
  The style is read each time a trainer is about to send out its next Pokémon, where Set skips the
  "will you switch?" prompt (`engine/battle/core.asm:1375-1377`), and the animation each time a
  move plays (`engine/battle/animations.asm:422-425`). The option menu is reached from the title
  and the start menu (`home/start_menu.asm:76`), so a change applies the next time the bit is read.
- **(b) Sea of Stars: difficulty as switches.** Its Relics change the rules of play - the Amulet of
  Storytelling doubles health and heals after a fight, the Artful Gambit takes almost all of it
  away - and once collected "can be toggled on and off at any time" (Can I Play That). They sit on
  the Status page, per §16b.

**What no reference does: let a player switch the fight SYSTEM.** Every setting above changes how
a fight is paced, how it is shown or how hard it is. None of these games offers a second way to
resolve an encounter, so the template's Fights row is a divergence, stated rather than borrowed: it
exists because this template ships two resolvers behind one seam (§7d, and M49 in `DECISIONS.md`),
and a player choosing between them is the template's own claim made visible.

**What this template does.** Options gains three rows about play, after Sound and Window: Fights
(turns or the sword), Movement (free, or one tile per press) and Saving (anywhere, or at save
points only). Each can be changed at any time from the title or the pause menu and takes hold the
next time it is read, which is FF6's and Pokémon's rule: a fight style at the next fight, movement
and saving when the page closes. A game's data still states the default, and a row that would
offer only one value is not drawn. Saving at save points only is §8's difficulty mechanic, and
Sea of Stars is the precedent for handing a difficulty switch to the player. See `DECISIONS.md`,
M51.

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

Options and window customisation (16b, added in M46). The two wikis that would ordinarily carry
this were unreachable on 2026-09-04 — `finalfantasy.fandom.com/wiki/Config` answered **402
Payment Required** and `wikibound.info` **403 Forbidden** — so the placement and contents claims
are taken from the disassemblies instead, which is the better source for how a shipped program
behaves anyway:

- [pret/pokered](https://github.com/pret/pokered) — `engine/menus/main_menu.asm` (the title's
  `OPTION` row and `DisplayOptionMenu`), `home/start_menu.asm` (the in-game `OPTION`)
- [pret/pokecrystal](https://github.com/pret/pokecrystal) — `engine/menus/options_menu.asm`
  (Gen II's numbered `FRAME`)
- [everything8215/ff6](https://github.com/everything8215/ff6) — `src/menu/config.asm`,
  `src/menu/field_menu.asm`, `src/menu/menu_text.en.inc` (Config as a field-menu state; the
  `Window` pattern list, the `Color` R/G/B bars, the `Font`/`Window` target toggle and `Reset`)
- For §16c (M51), the same two repositories pinned: `pret/pokered` at `a1a22aa` —
  `constants/ram_constants.asm` (`BIT_BATTLE_SHIFT`, `BIT_BATTLE_ANIMATION`),
  `engine/battle/core.asm` and `engine/battle/animations.asm` (where each bit is read);
  `everything8215/ff6` at `8130132` — `src/menu/config.asm` (`DrawActiveWaitText`,
  `ChangeConfigOption_00`), `src/battle/init.asm` (the config byte copied as a fight starts),
  `src/battle/atb.asm` (the copy read), `src/menu/menu_text.en.inc` (the Config rows)
- [Legends of Localization — EarthBound / MOTHER 2: New Game](https://legendsoflocalization.com/comparisons/earthbound/new-game/)
  — the window *flavour* chosen during new-game setup (prose, secondhand for the claim that it
  cannot be changed afterwards, which is **not** asserted here because no reachable source
  settled it)
- [Can I Play That — Sea of Stars accessibility review](https://caniplaythat.com/2023/11/01/sea-of-stars-accessibility-review/)
  — accessibility as collectible Relics rather than options rows, and (§16c) that they "can be
  toggled on and off at any time" (prose)

Music and save-integrity research (§14 and §8, added in M32):

- [Final Fantasy wiki — Battle Theme 2](https://finalfantasy.fandom.com/wiki/Battle_Theme_2) and
  [Battle (Final Fantasy)](https://finalfantasy.fandom.com/wiki/Battle_(Final_Fantasy)) — FF1's
  single battle theme plays for every fight *including Chaos*; FF2's "Battle Theme 2" is the
  series' first dedicated boss theme
- [Final Fantasy wiki — Battle 2 (Final Fantasy IV)](https://finalfantasy.fandom.com/wiki/Battle_2_(Final_Fantasy_IV))
  — debuts at the Mist Dragon and plays for every boss but two
- [Final Fantasy wiki — Game Over (term)](https://finalfantasy.fandom.com/wiki/Game_Over_(term))
  — each game has its own Game Over scene; FF1's is "Dead Music", FF5's is "Requiem"
- [Wikipedia — Koichi Sugiyama](https://en.wikipedia.org/wiki/Koichi_Sugiyama) — Dragon Quest I's
  eight melodies (Opening, Castle, Town, Field, Dungeon, Battle, Final Battle, Ending), the
  soundtrack shape the genre copied, with a boss theme in it before Final Fantasy existed
- [Glitch City Wiki — damaged save data error messages](https://glitchcity.wiki/wiki/Damaged_save_data_error_messages)

Terrain-transition research (§15, added in M41). The tile counts here are the whole argument, so
they come from the two tools that implement the schemes rather than from a description of them:

- [Tiled — Terrain sets](https://doc.mapeditor.org/en/stable/manual/terrain/) — a corner set and
  an edge set over two terrains are sixteen tiles each; a mixed set is 256, "but reduced sets
  like the 47-tile Blob tileset can be used with this type as well"
- [Godot 4.7 — Using TileSets](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilesets.html)
  — the three modes "correspond to the previous bitmask modes autotiles used in Godot 3.x: 2×2,
  3×3 or 3×3 minimal". The page gives no rule for what the engine picks when no tile matches
  exactly, which is one of the reasons this template composes its own shapes instead
- The quarter-composition scheme is RPG Maker's autotile format. Named here from the FORMAT
  rather than from a source that documents it, so it is marked secondhand — the arithmetic
  (thirteen pieces, four quarters, 47 shapes) is derived and checked, the attribution is not
- The piece layout in §15 is measured from `grass.png`, `dirt.png` and `water.png` in the LPC
  base tileset by reading their alpha, not from a description of the sheets
  — Pokémon Gen I checksums the save and says "The file data is destroyed!" rather than
  presenting a blank slot

Interface-chrome research (§16, added in M42). Read from SCREENSHOTS rather than descriptions,
because a claim about what a window looks like cannot be carried by prose:

- [Game UI Database](https://www.gameuidatabase.com/) — the screens themselves: Sea of Stars
  (`gameData.php?id=2196`), Persona 5 Royal (`id=618`), Clair Obscur: Expedition 33 (`id=2060`).
  Every claim about frames, header bands, highlight bars, portrait blocks and what does or does
  not appear over an enemy was read off those captures
- [Siliconera — Atlus reveals the design secrets behind Persona 5's distinctive UI](https://www.siliconera.com/atlus-reveals-design-secrets-behind-persona-5s-distinctive-ui/)
  — the sub-colour rule ("did not use sub-colors other than in HP/MP elements, in order to keep
  the distinctive red color") and that menu and battle UI had separate designers
- [Jiaxin Wen — The UI Design of Persona 5](https://jiaxinwen.wordpress.com/2017/04/27/the-ui-design-of-persona-5/)
  — the command tiles as long triangles that "point to the character that is in the turn", and
  the left-character / right-enemy split that keeps the menu off the fight
- [Game Voyagers — Sea of Stars: ultimate guide to combat](https://gamevoyagers.com/sea-of-stars-ultimate-guide-to-combat/)
  — HP bottom-left with the MP meter beside it, and the locks and turn counters drawn over
  enemies in place of a health bar
- [TweakTown — Clair Obscur: Expedition 33's stripped-back UI puts immersion first](https://www.tweaktown.com/news/104172/clair-obscur-expedition-33s-stripped-back-ui-puts-immersion-first/index.html)
  and [Wikipedia — Clair Obscur: Expedition 33](https://en.wikipedia.org/wiki/Clair_Obscur:_Expedition_33)
  — the minimalism the producer states, and the combat vocabulary its Gameplay section cites

Bot-blocked or paywalled on 2026-09-03 and therefore NOT cited anywhere above: the Sea of Stars
wiki (402), interfaceingame.com's Clair Obscur page, the ArtStation HUD-concept galleries and the
Medium UX write-up (403 each), and the itch.io Persona 5 study (403).

Credits research (§12a, added in M43). The obligation is quoted from the tool that produced the
art rather than from a description of the licence:

- [Universal LPC Spritesheet Character Generator — README](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/blob/master/README.md)
  — the credits file must be "accessible from within your game or app and can be reasonably
  discovered by users"; either CREDITS.csv or a composed list may be shipped; every author must be
  credited except for CC0 work; and the example statement names artists, source URL, licence URL
  and a pointer to the detailed credits
- [OpenGameArt — Properly licensing your Liberated Pixel Cup game entry](https://opengameart.org/content/properly-licensing-your-liberated-pixel-cup-game-entry)
  — the dual CC-BY-SA 3.0 / GPL licensing of LPC non-software assets. Read, and thinner than the
  README on attribution mechanics, which is why the README carries the quotes above

§6's appearance half and §16a were added the same way, from these screens:

- [Game UI Database — Dialogue & Speech](https://www.gameuidatabase.com/index.php?scrn=162) —
  Persona 4 Golden's boxes: the speaker's name in a tab above the box's corner, the portrait
  bust to the left overlapping its edge, the advance indicator bottom-right, and choices as
  their own stack of small boxes above the text
- [Game UI Database — Sea of Stars](https://www.gameuidatabase.com/gameData.php?id=2196), the
  Title and Modals captures: the save screen as a titled bar, one framed panel per slot with a
  pointer beside the chosen one, a details panel of Level / Gold / Time / Location, and the party
  drawn beside it as their own walking sprites - all of it over the live world

Element research (§13b, added in M33). The Final Fantasy and Pokémon numbers come from
disassemblies of the shipped ROMs, because the wikis were bot-blocked and the Archive was down;
that is a stronger source than a description, and it contradicted the most-repeated claim:

- [Entroper/FF1Disassembly](https://github.com/Entroper/FF1Disassembly) — `bank_0C.asm` and
  `Constants.inc`: magic weakness is ×1.5 and resistance ×0.5, NOT doubling; physical weakness is
  a flat +4 damage and +40 to hit; the complete 35-entry battle-message table contains no
  elemental string; and the player's attack element is annotated `BUGGED … always 0`
- [TASVideos — Final Fantasy 1](https://tasvideos.org/GameResources/NES/FinalFantasy1) — the
  elemental swords "were all supposed to do extra damage to some enemies. But they don't"
- [pret/pokered](https://github.com/pret/pokered) — `constants/battle_constants.asm` (2× / 0.5× /
  0×, scaled by ten), `data/text/text_2.asm` (the two effectiveness strings and the separate
  immunity line), and `engine/battle/display_effectiveness.asm` (neutral hits return silently)
- [Gamer Corner Guides — Dragon Warrior, Hurt](https://guides.gamercorner.net/dw/spells/hurt) —
  resistance is a RATE of full negation: "if the spells work, they will deal full damage"
- [Dragon Quest wiki — Sizz](https://dragon-quest.org/w/index.php?title=Sizz) and
  [Burning Breath](https://dragon-quest.org/w/index.php?title=Burning_Breath) — DQ1's fire spell
  may fail on resistance; DQ6 tiers the CHANCE to connect rather than the damage

Battle-message research (§7c, added in M36), all from disassemblies of the shipped games —
the wikis do not carry window dimensions, and each repo below was cloned and grepped:

- [pret/pokered](https://github.com/pret/pokered) — `engine/menus/display_text_id_init.asm`
  (`ld c, $12`, an 18-column box), `home/text.asm` (the `<LINE>`/`<CONT>`/`<PARA>` control
  characters and `ScrollTextUpOneLine`), `data/text/text_2.asm` (no message names two battlers)
- [Entroper/FF1Disassembly](https://github.com/Entroper/FF1Disassembly) — `bank_0C.asm`: six
  combat boxes rather than a message area; the all-enemies loop that redraws the defender box per
  target; and `RespondDelay_UndrawAllBut2Boxes`, whose comment states the persistent-frame rule
- [nmikstas/dragon-warrior-disassembly](https://github.com/nmikstas/dragon-warrior-disassembly) —
  `Bank01.asm`: the window definition (24 tiles × 5 blocks), the word-wrap check `CMP #$16`, the
  last-row check `CPX #$08` and the scroll; `Bank03.asm` shows battle using that same window
- [Herringway/ebsrc](https://github.com/Herringway/ebsrc) — `window_configuration_table.asm`
  (`$0018` × `$0006` for in-battle text), `print_newline.asm` and the scroll it calls

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

Status research (§13a) is drawn from these:

- [Final Fantasy NES manual](https://world-of-nintendo.com/manuals/nes/final_fantasy.shtml),
  a third time — the party-side afflictions named through their cures (`PURE` for poison, `SOFT`
  for stone, Ghouls that "paralyze members of your party", `LAMP` and `MUTE`), and the two
  buffs: `TMPR` on one ally and `FOG` on the caster, with their exact magnitudes. It describes
  every effect and never says how the screen reports one.
- [Dragon Quest wiki — Buff](https://dragon-quest.org/wiki/Buff) and
  [Sap](https://dragon-quest.org/wiki/Sap) — doubling one ally's defence for 3 MP over 4–6
  turns, halving one foe's over 6–9: durations as ROLLED RANGES, which is the thing this
  template deliberately does not copy
- [EarthBound Wiki — PSI](https://earthbound.fandom.com/wiki/PSI) — the Assist branch as one
  system pointed both ways: "boosting or weakening the stats of an ally or foe … or inflicting
  a status ailment", with Offense up and Defense down inside the same list
- **Secondary, and flagged as such:** that FF1 replaces a character's HP readout in the battle
  block with `POIS` / `STON` / `DARK`. Two independent summaries agree; the manual is silent and
  both first-hand pages are bot-blocked (403/402), so §13a cites it without leaning on it.

- The user's own [`jrpg-design-codex`](https://github.com/Ali0600/jrpg-design-codex) — design
  *patterns* (progression systems, build economies), not screen anatomy. Cite it for what a
  system should do, not for what a screen should contain.

Saving research (§8, rewritten in M39). Where a wiki was bot-blocked the shipped binary was read
instead, which is the M33 route and produced better evidence again — three widely-repeated
claims turned out to be wrong. Bot-blocked or paywalled this pass: gamefaqs, strategywiki,
woodus, nesworld, guides.gamercorner, wikibound, dragonquest.fandom (**402**), earthbound.fandom.

- [Dragon Warrior NES disassembly](https://github.com/nmikstas/dragon-warrior-disassembly) —
  `Bank03.asm` holds the game's ONE call to the save routine, inside `KingDialog2`; the exact
  NES strings were decoded from the text blocks in `Bank02.asm`. The save path writes no gold
  and no HP, and `InitDeathSequence` never reads the save file
- [Final Fantasy NES disassembly](https://github.com/BenWenger/FinalFantasyDisassembly) — every
  call site of `SaveGame`: the inn (`EnterShop_Inn`, which fills HP and MP first) and the
  tent/cabin/house items, gated to the overworld map. `LDA #30` / `#60` / `#120` are the three
  HP amounts; the house's MP restore sits after the save branch, commented *"some would say
  this is BUGGED"*. Menu and shop strings decoded through the game's own DTE tables in bank `0F`
- [pret/pokered](https://github.com/pret/pokered) — `DrawStartMenu` prints SAVE unconditionally
  (the one exception being a link session, where the row becomes RESET); all four save triggers,
  and the strings in `data/text/text_3.asm`
- [Herringway/ebsrc](https://github.com/Herringway/ebsrc) symbol map cross-checked against a
  CoilSnake text dump of the US ROM — the five `{save}` sites in the whole script, Dad's
  **"Record"** menu option, Maxwell's *"keep a record of your journey"*, and the structural
  negative that no HP-recovery opcode appears in any save script. The `$1` belongs to the pay
  phone (`REMOVE_MONEY 1`, refunded on hang-up), never to the save
- [Dragon Warrior](https://www.world-of-nintendo.com/manuals/nes/dragon_warrior.shtml),
  [II](https://www.world-of-nintendo.com/manuals/nes/dragon_warrior_2.shtml),
  [III](https://www.world-of-nintendo.com/manuals/nes/dragon_warrior_3.shtml),
  [IV](http://www.digitpress.com/library/manuals/nes/dw4.txt),
  [Final Fantasy](https://world-of-nintendo.com/manuals/nes/final_fantasy.shtml),
  [EarthBound](http://world-of-nintendo.com/manuals/super_nes/earthbound.shtml) and
  [Chrono Trigger](http://world-of-nintendo.com/manuals/super_nes/chrono_trigger.shtml) manuals
  — slot counts, and Chrono Trigger's Shelter being the thing that heals at a save point
- [dragon-quest.org — Dragon Quest IV](https://dragon-quest.org/wiki/Dragon_Quest_IV) — save
  moved from castles to churches, so the developers could write the monarchs as characters

Action combat research (§7d, added in M49; what the screen shows, added in M50). The three codebases were cloned at the commits named
and read directly, the M33 route again, and every number in §7d is a line in one of them. Ni no
Kuni is prose only and is marked so.

- [zladx/LADX-Disassembly](https://github.com/zladx/LADX-Disassembly) at `880d24c` —
  `src/constants/hitbox.asm` (the hitbox byte); `src/constants/memory/wram.asm`
  (`wIgnoreLinkCollisionsCountdown`, `wInvincibilityCounter`, `wEntitiesIgnoreHitsCountdownTable`,
  `wEntitiesFlashCountdownTable`, `wEntitiesRecoilVelocityX/Y`, `wSwordCharge`,
  `wIsUsingSpinAttack`, `wSwordCollisionEnabled`, `wEntitiesHitboxPositionTable`);
  `src/code/home/entities.asm` (`ConfigureEntityHitbox`, `StopEntityRecoilOnCollision`);
  `src/code/bank2.asm` (`HurtBySpikes`); `src/code/bank0.asm` (the per-frame invincibility
  decrement); `src/code/entities/bank3.asm` (`ConfigureEntityRecoil`,
  `DefaultEnemyDamageCollisionHandler`); `src/code/entities/03_moblin.asm` (`AnimateRoamingEnemy`);
  `src/code/entities/05__helpers_2.asm` (`GetEntityDirectionToLink_05`); and for the screen (M50),
  `src/code/bank2.asm` (`LoadHeartsCount`) and `src/code/bank14.asm` (the palette switched while
  `wEntitiesFlashCountdownTable` runs)
- [snesrev/zelda3](https://github.com/snesrev/zelda3) at `fbbb3f9` — `src/player.c`
  (`Link_ControlHandler`, `Link_CheckForSwordSwing`, `HandleSwordSfxAndBeam`, `kSpinAttackDelays`);
  `src/player_oam.c` (where `countdown_for_blink` is decremented); `src/sprite.c`
  (`Sprite_CheckDamageToPlayer_1`, `Sprite_CheckDamageFromLink`,
  `Sprite_AttemptDamageToLinkPlusRecoil`, `Sprite_ApplyRecoilToLink`, `Sprite_AttemptZapDamage`,
  `Sprite_CalculateSwordDamage`, `Sprite_GiveDamage`, `Guard_ParrySwordAttacks`);
  `src/sprite_main.c` (`Sprite_6D_Rat`, `Soldier_Func12`, `Octoballoon_RecoilLink`);
  `src/messaging.c` (`Module12_GameOver`, `Death_Func1`); and for the screen (M50), `src/hud.c`
  (`Hud_Update_Hearts`) and `src/sprite.c` (`Sprite_TimersAndOam`)
- [FiendsOfTheElements/z2disassembly](https://github.com/FiendsOfTheElements/z2disassembly) at
  `c4c3a4c` — `ram-map.txt`: `$518`, `$50C`, `$50A`, `$40E,X`; and for the screen (M50) `$C7`,
  `$774`, and the "draw boss hp bar" comments in `src/prg0.asm`
- [Wikipedia — Ni no Kuni: Wrath of the White Witch](https://en.wikipedia.org/wiki/Ni_no_Kuni:_Wrath_of_the_White_Witch)
  — the open battlefield and what a win pays (**secondhand**)
- [Nintendo World Report — Switch review](http://www.nintendoworldreport.com/review/51807/ni-no-kuni-wrath-of-the-white-witch-switch-review)
  — backing away from melee (**secondhand**)
- [RPGFan — Remastered review](https://www.rpgfan.com/review/ni-no-kuni-wrath-of-the-white-witch-remastered/)
  — what losing costs (**secondhand**)
- [TheGamer — combat tips](https://www.thegamer.com/ni-no-kuni-wrath-white-witch-combat-tips/) —
  the command to run away (**secondhand**)
- [Champicky — battle screen interface analysis](https://champicky.com/2020/12/15/ni-no-kuni-wrath-of-the-white-witch-battle-screen-interface-design-analysis/)
  — HP and MP drawn as bars, and the strip that marks the target (**secondhand**, M50)
- [Glenn Fiedler — Fix Your Timestep!](https://gafferongames.com/post/fix_your_timestep/)
- Godot documentation — [Idle and Physics Processing](https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html),
  [Area2D](https://docs.godotengine.org/en/stable/classes/class_area2d.html) and
  [CharacterBody2D](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html)

Bot-blocked or unreached on 2026-09-13 and therefore NOT cited above: the Neoseeker walkthrough and
the GameFAQs guide that would have said how a Ni no Kuni fight begins (403 each), and the Eurogamer,
IGN, GameSpot and RPGamer reviews. tcrf.net answered with an anti-bot page and was not read. In
M50 the Neoseeker controls page, which would have said whether every Ni no Kuni enemy carries a
bar, answered 403 as well.
