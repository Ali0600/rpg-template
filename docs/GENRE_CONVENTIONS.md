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
| [Menu anatomy](#1-menu-anatomy) | Item / Equip / Status / Save as sibling commands | Resume, Items, Equipment, Save, Load, Sound | **partial** — no Status command |
| [Equip screen](#2-the-equip-screen) | Slot list → candidates → preview the delta | Slot list, candidates, take-off row, swap preview, Atk/Def readout | **met** (M20) |
| [Status screen](#3-the-status-screen) | Level, HP, XP-to-next, stats, worn gear | Nothing outside a fight | **gap** |
| [Inventory](#4-inventory) | List, counts, description, a use verb | List, counts, description, **no use verb** | **partial** — [use is a game's business](DECISIONS.md) |
| [Shop](#5-shops) | Windows over the world, keeper, quantity, prices | All of it | **met** (M18.1) |
| [Dialog](#6-dialog) | Bottom window, revealed text, choices | Bottom box, reveal, choice band, size-gated | **met** |
| [Battle](#7-battle) | Random encounters, turn menu, a party | Visible enemies, timed presses, solo | **diverges deliberately** |
| [Save/load](#8-saveload) | Save points or inns; menu save later in the era | Slots from the pause menu, anywhere | **diverges deliberately** |
| [Progression](#9-progression) | Level, XP curve, stats from level, gear as modifier | All of it | **met** |
| [Towns & NPCs](#10-towns-and-npcs) | Walking townsfolk, shops, an inn | Static, wander and patrol NPCs; a shop | **partial** — no inn |
| [World structure](#11-world-structure) | Overworld → towns → dungeons, gated | Maps and warps, gated by items and flags | **met** in shape |
| [Title & game over](#12-title-and-game-over) | Title screen with Continue; death → menu | Game-over overlay; **no title screen** | **gap** |
| [Magic & skills](#13-magic-and-skills) | MP, a spell list, a battle command | Nothing | **gap** — biggest one |
| [Music](#14-music) | Per-area themes, battle theme, fanfare | `play_music` exists, nothing calls it | **gap** |

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

Equipment moved here in M20 (§2). It had been folded into the bag, which is the one place the
reference games never put it — and it was there because the menu had no row for it, which is
what makes a missing command more than a cosmetic gap.

**Gap: Status.** The genre's fourth standard command (§3) is still missing, so a player cannot
see their own HP or level outside a fight.

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

**This template.** Nothing. `GameState` holds `player_hp`, `player_xp` and `player_level`,
and `CombatDef` can derive `max_hp`, `attack_at`, `defense_at` and `xp_for_next` — every number
the convention asks for already exists and is only ever shown **inside a fight**. A player
cannot answer "how hurt am I" without starting one.

**Gap: the page.** MP and a portrait stay out of scope (no magic — §13; and a portrait would
be a second art pipeline beside the generated sprites).

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

**Gap:** no portraits, no per-player text speed. Both are candidates; neither is load-bearing.

---

## 7. Battle

**The convention.** Random encounters on a step counter (FF, DQ, EarthBound's visible-on-map
variant aside), a **turn-based command menu** (Fight / Magic / Item / Run), a **party** of
three or four, HP/MP bars, and a victory screen paying XP and gold.

**This template diverges, deliberately.** Enemies are **visible records on the map** and the
fight fires on stepping to an adjacent tile — a fight that must happen is made unavoidable by
**geometry** (a one-tile gap), never by a random roll. The fight itself is **timing-based**: a
cue lights and a press inside its window doubles the blow or halves the incoming one. One
character, no party. `BattleLogic` has **no clock** — it is handed one physics frame at a time,
which is what lets a QA script press on an exact frame and get the same fight on every machine.

**Why the divergence is good.** Random encounters need a random source in the movement loop,
and this template's whole determinism story ("same seed, same everything") is what makes its
play sessions a gate. Visible enemies also make a template's demo game legible in a way a
step-counter never is. Recorded in `DECISIONS.md`.

**Gap:** no party. That is the single largest missing *system* after magic, and it reaches
into `BattleLogic`, the status page and the equip screen (whose gear becomes per-character).

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

**Gap:** no inn, which in the genre is where HP comes back for money. Currently nothing
restores HP outside a fight's own item use. That is a real hole in the loop — see §10.

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

**Gap:** **no inn.** The genre's HP economy is fight → lose HP → pay gold at an inn → fight
again, and this template has the first, second and fourth. Gold currently only buys items.
This is the highest-value gap in the table: it is small (a dialog choice, a price, a heal), it
closes the loop, and it gives gold a second use.

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

**Gap:** a real title screen. Small, and it would give `TITLE` its meaning and the music seam
its first caller. Backlog.

---

## 13. Magic and skills

**The convention.** MP, a spell list that grows with level or purchase, a battle command
beside Attack, and out-of-battle utility spells (heal, warp, light). Present in every reference
game — it is arguably the defining JRPG system after "turns".

**This template.** Nothing. Fights are Attack / Item / Flee.

**Gap:** the largest one in the table, and the most invasive: MP on the player, a spell
resource type, a battle command, a status row, and probably a targeting step. Worth doing as
its own milestone, not as an addition to another.

---

## 14. Music

**The convention.** A theme per area, a battle theme, a victory fanfare, and a title theme —
the genre's most recognisable output.

**This template.** `AudioBus.play_music` exists and is called by nothing. Sound effects are
generated the way sprites are (a cue's shape in a bank, its voice in a `SoundStyle`), so the
machinery for generated *music* is closer than it looks.

**Gap:** anything at all. The interesting version is procedural music generated per style, the
way art already is — which would be a genuinely unusual thing for a template to ship.

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
- The user's own [`jrpg-design-codex`](https://github.com/Ali0600/jrpg-design-codex) — design
  *patterns* (progression systems, build economies), not screen anatomy. Cite it for what a
  system should do, not for what a screen should contain.
