# Decisions

Forks with real alternatives, recorded as they were made. The backlog at the top is the
one-glance menu of things still worth trying.

## Backlog — alternatives worth trying later

- **An AI sprite source** (PixelLab or similar) for higher-fidelity art. Revisit hook:
  `scripts/spritegen/sprite_source.gd` — implement the interface, emit PNG + sheet.json,
  and the game does not change. Direction aliases for compass-named rows already exist in
  `scripts/util/dir.gd`.
- **A second cell size** (32×32 characters, 32px tiles). Revisit hook: `SpriteStyle`
  already carries `cell_size` and `tile_size`; the work is a rig authored at that size.
- ~~**Tiled / LDtk map import.**~~ **Finished 2026-09-01.** Both editors, both directions, and
  `tools/map_io.gd` is the command that makes it a workflow rather than a library. What is left
  is not code: nobody has OPENED a generated file in either editor, because neither is installed
  here. Revisit hook: install one, open one map, save it, and re-import — one round through the
  real tool would retire the largest remaining unknown in the feature.
- **A save point that does not ask which slot** — the genre's own answer, and this template's
  stated divergence since M39. Every reference either has one file (FF1, Pokémon) or picks it at
  the title (DQ1, EarthBound, Chrono Trigger); none asks at the moment of saving. Revisit hook:
  `SaveMenu` is the whole question — a `save_slots` of 1 already makes it a one-row list, so the
  work is deciding whether `at_point` should skip the screen entirely and write the slot the run
  was started from. That needs a title-side "which file am I playing" concept the template does
  not have, which is why it is deferred rather than done.
- **A real-time combat resolution** (an arena on encounter, Ni no Kuni's shape). The largest
  open item, and the one the save axis is the small precedent for. Revisit hook is exactly two
  functions: `world_scene.open_battle_with(defs, seen_key)` in and `finished(outcome, effects)`
  out — everything between is `BattleScreen` + `BattleLogic`, and a second resolver honouring
  that contract inherits encounters, rewards, persistence and music unchanged. The open design
  question is `Router.player_can_move()`, which is one line and answers `WORLD` only.
- **Asymmetric side parts** (a satchel on one hip only). Blocked by
  `mirror_left_from_right`; revisit hook is the `left = flip_x(right)` branch in
  `sprite_compositor.gd`.
- ~~**Slots that say WHY they cannot be loaded**~~ ("unreadable" rather than "empty").
  **Taken up by M32**, exactly at the hook this entry named: `peek()` returns a `SlotSummary`
  instead of discarding what `_read` already knew, and the row says `damaged`.
- **Using an item from the bag** (a general "Use" verb on the pause menu's item list). Still
  deferred after M13: `ItemDef.battle_heal` is the template's first and only use verb, and it
  is deliberately narrow — a potion heals in every RPG ever written, where "use the rope on
  the well" is a puzzle, and a template that grew a verb for the second one would be
  designing somebody's game. Revisit hook unchanged: `PauseMenu.confirm()` on the ITEMS page
  already returns `NONE` where the answer would go.
- **Flee odds, and damage variance.** M13 made both deterministic — a boss refuses every
  escape and everyone else allows it; a hit is worth exactly what the numbers say. A designer
  can reason about that and a QA script can rely on it. Revisit hooks: the flee branch in
  `BattleLogic.press()`, and `BattleLogic.damage()`.
- **`MOTION_MODE_FLOATING` for actors** — Godot's recommended mode for top-down, and a
  cleaner answer to the NPC-carry bug than the narrow opt-out that shipped. It changes how
  every body slides along every wall, so it needs playing rather than proving. Revisit hook:
  one line in `ActorBody._init`.
- ~~**A real title screen.**~~ **Taken up by M22**, and this entry sat here stale for twelve
  milestones afterwards — which is worth more than the correction. A backlog line describing
  work already done invites building it a second time, and it sits exactly where somebody looks
  before starting. It is the same shape as the false genre claim M32 found in a code comment: a
  gap invites work, and a wrong statement invites belief. `TitleScreen` + `TitleMenu` run over an
  empty world in `Router.State.TITLE`, and `GameOverScreen` gained the Title row its own class
  comment had promised since M13, exactly as this entry predicted.
- **A field-menu Magic page.** M25 kept magic battle-only. Revisit hook: the day a spell is
  useful outside a fight — a warp, a light, a partial heal cheaper than an inn — it is a
  `PauseMenu.Row` between Items and Equipment plus a `_spell_rows()` beside `_gear_rows()`.
- ~~**Elemental resistances.**~~ **Taken up by M33**, at exactly the hook this entry named.
  What is still out: **elements on physical swings** (FF1's Ice Brand — and note FF1's own
  version of this never worked, its player attack element annotated `BUGGED … always 0` in the
  disassembly). Revisit hook: `ItemDef` gains an element and `_land_player_hit` scales the way
  `_cast` does. Also **party-side resistance** — nothing shields the player, because no enemy
  move carries an element; hook is the move dict plus a map on `Fighter`.
- ~~**A casting policy for `BattleDriver`.**~~ **Taken up by M34**, and the feared cost did not
  arrive: a casting party wins every shipped fight on every seed, so nothing needed retuning.
  What it did find was two pairings the player could never learn. **The item half was taken up by
  M35**, which found the same two layers and a guard with no test behind them. Still deferred
  here: **a driver that FLEES** — the fourth row, and the only one no policy has ever pressed.
  Revisit hook: `Policy`, plus a report field for the attempt, and note that a boss refuses every
  escape so the assertion has two halves.
- ~~**A width gate for the battle caption.**~~ **Taken up by M36**, at the hook this entry named,
  and the research turned "make it fit" into a correction: a ONE-LINE caption was the divergence,
  since every reference message area holds more than one. What is still out is the multi-target
  half — see the M36 entry below, and the FF1 persistent-frame alternative recorded there.
- ~~**Buffs, debuffs, and status effects on the PLAYER.**~~ **Taken up by M30** — `BOOST` and
  `SAP` aim either way, enemy moves can afflict the party, and durations count in turns. What
  is still out is **persistent affliction**: a status cannot outlive the fight it was inflicted
  in, where FF1's and DQ's poison follow you onto the map. Revisit hook: the `Status` holder,
  which would need a second home on `GameState` beside the party's numbers — plus a save
  version, a map tick and a cure.
- **Teaching a spell with an item.** Dragon Quest's scrolls, as a supplement to level
  learning. Revisit hook: it needs a stored known-spells set, which M25 deliberately does not
  have — so this one costs a save field and a migration, not just a verb.
- ~~**A game-over theme.**~~ **Taken up by M32**, and the research turned it from a
  nice-to-have into a correction: the branch that cut the music justified itself with a genre
  claim that is false. The "does the title's theme displace it" question answered itself — every
  way out of a game over already states its own music, so nothing had to be given back.
- ~~**Per-encounter themes**~~ (a boss that sounds like one). **Taken up by M32** at the hook
  named here. Both design questions dissolved: a fled boss fight cannot happen (a boss refuses
  every escape), and **whether the fanfare should differ after a boss is still deferred** — it is
  a second field answering a second question. Revisit hook: `_leave_battle_music`, which already
  takes `won` and would take the foes.
- **Moving the music player to `PLAYBACK_TYPE_STREAM` on the web.** Godot's web SAMPLE
  playback loops by listening for the source node's `ended` DOM event and rebuilding the node
  in JavaScript, so a web loop is one browser event away from silently not happening;
  godotengine/godot#101111, #100955 and #105620 are open against it. Stream uses the ordinary
  mixer and waits on nothing. NOT shipped, because it has never been needed here — see the
  entry below. Revisit hook: one line in `AudioBus._ready`, and the symptom to watch for is
  music that plays once and stops with nothing in the console.
- ~~**A targeting step for ENEMIES.**~~ and ~~**Multi-enemy fights.**~~ Both **taken up by
  M28** — the research is `GENRE_CONVENTIONS.md` §7b and the decisions are below. The hooks
  named `SpellDef` gaining a target shape, `BattleLogic._enemy`/`_enemy_hp` becoming a list,
  and `MapData.enemy_at` returning a group; all three are what M28 does.
- **A boss with minions**, as a fight SHAPE rather than a formation with a boss in it. Super
  Mario RPG's Mack summons his bodyguards back and leaves the field until they are cleared,
  which is a rule about the encounter rather than about any enemy in it. **M29 gives the Keeper
  an escort**, which is the formation and not the shape: its minions stay dead, and killing the
  boss first leaves them standing. Still deferred, and the revisit hook is unchanged — the
  encounter record, which names the foes and could name a rule about them.
- **Followers on the overworld** (Chrono Trigger's caterpillar). M27 ships one sprite, which is
  Final Fantasy I–VI's own answer. Revisit hook: a driver reading the leader's `Locomotion.Step`
  history and feeding it back as an intent, beside `NpcBrain` — harder under free pixel movement
  than it would be with grid steps to trail.
- **A roster larger than the battle line** — a bench, a swap screen, Dragon Quest IV's wagon.
  M27's roster IS the party. Revisit hook: `_active_party()`, which is the one place membership
  is decided.
- **A named or spell-scoped LEADER** (Dragon Quest II's magic-less hero). The leader is
  synthesized from the manifest, so they are called "You" and know everything their level has
  reached. Revisit hook: leader-override fields on `GameManifest` beside `player_character`.
- **Reviving mid-fight**, and turn order from a stat. Both `deferred`; the hooks are
  `ally_rows()` (which returns only the standing) and `_advance()`'s walk over `_living()`
  (which would take an agility order rather than index order).

---

## Maps go both ways, to two editors — *M38, finished*

The Tiled half shipped in M38 and the rest was owed: LDtk, and the command. Three forks.

**The fork: how a record's fields cross into LDtk.** LDtk, unlike Tiled, resolves every field
instance through a `defUid` pointing at a definition.

- **Hand-list the fields a record can carry** — *Status: rejected. A game may put anything on an
  npc, so a fixed list silently drops whatever the template did not know about — the
  hand-maintained-membership failure this repo has already paid for once.*
- **Carry every field as one opaque JSON blob** — *Status: rejected. It is robust and it throws
  away the point of the exercise: a designer editing `dialog` or `dwell` in the side panel is
  what the editor is FOR.*
- **Derive the definitions from the records being exported (chosen)** — scalars become real typed
  LDtk fields, and only what has no LDtk type (an array of tile pairs, which is what a patrol
  path is) travels as JSON behind the same marker Tiled uses. A field the records disagree about
  becomes a String and keeps its values losslessly rather than picking a winner.

**The fork: how much of LDtk's format to write.** Its schema lists 28 required root fields, and
its own 0.9.3 test file — which current LDtk opens — is missing eleven of them.

- **Trim to what the schema calls required** — *Status: rejected. `required` means "LDtk always
  writes this", not "the loader refuses without it"; trimming to it is guessing in the direction
  that looks rigorous.*
- **Write what the editor itself emits (chosen)**, read off its own sample projects, and check
  the narrower set the LOADER actually refuses by reading its source. That found three things no
  schema reading would: `gridTiles`/`entityInstances`/`intGridCsv` are walked raw on every layer
  with no guard, an unresolved field `defUid` crashes when it carries values, and duplicate
  `iid`s are accepted and silently collapse entity references.

**The fork: what the `--verify` gate compares.** *Status: chosen — the game's own reading, through
`MapData.differences()`, shared with both round-trip suites.* A byte comparison was never possible
(the legend is rebuilt, and a legend is a spelling choice), and a third private notion of "same
map" would have been three gates that eventually disagree about what a map is.

**Stated limitation rather than a hidden one:** no gate here proves either editor OPENS these
files. All of them are this reader understanding this writer. The one independent check made was
validating all six generated `.ldtk` files against LDtk's published 1.5.3 schema — zero errors —
and it is deliberately NOT in `check.sh`, because it needs a package fetched from an external
index and a gate that reaches one is a flaky gate. Backlog entry carries the hook.

---

## Where a game may be saved is an axis — *M39*

The first SYSTEM axis rather than a content one, and the small precedent for the real-time
combat arc: a rule the template used to decide for everybody becomes a field a game states,
with both sides gated. The research reversed the section that argued against it — §8 said "a
game wanting save points ships them as an object with a `GameHooks` interaction", which was
true and was also the template declining to have an opinion, because the pause menu's Save row
would still have been offering the thing that design had just forbidden.

**The fork: how the policy is spelled.**

- **An enum on `GameConfig`** — *Status: rejected. A `.tres` stores an enum as the bare int it
  was written as, so adding a third policy re-labels every shipped config; the same reason
  `SpellDef.Kind` is appended to and never reordered.*
- **A bool, `saves_anywhere`** — *Status: rejected — a two-valued field that the genre does not
  have only two of. Chrono Trigger's split (points in maps, anywhere on the world map) is a
  third value already, and a bool would need replacing rather than extending.*
- **A StringName checked against a list (chosen)** — a typo FAILS THE BUILD, the npc `behavior`
  rule; a third policy is one entry in `SAVE_POLICIES` and no migration.

**The fork: what an `at_point` game does with the Save row.**

- **Draw it and refuse the press** — *Status: rejected. A row that cannot be pressed is a dead
  key, and this is a capability the game does not have rather than a price the player cannot
  meet — the `requires_item` case, which hides, not the `spend_gold` case, which quotes and
  refuses out loud.*
- **Hide it (chosen)** — which costs a mapping: with a row gone, a cursor index is no longer its
  Row. `_top_rows()` derives the list and `top_row(at)` is the one place a cursor becomes a Row
  again, read by BOTH `confirm()` and the view's `_label_for` — two readings would draw "Save"
  over the row that answers Load. With saving on the list IS the enum, so every counting session
  and every `move(Row.SAVE)` test lands exactly where it did.

**The fork: does the save point ask which slot?** *Status: divergence, stated rather than fixed.*
No reference asks at the moment of saving — one file, or chosen at the title. This template's
pause menu has picked a slot at save time since M5 and has been played that way, and a save
point answering the question differently would be two answers to one question. Deferred entry
at the top of this file.

**The fork: does the save point heal?** *Status: no, and this one is researched rather than
assumed.* Every free save point in the genre restores nothing — DQ's king, DQ4's church,
EarthBound's telephone (proven structurally: no HP-recovery opcode appears in any of the five
`{save}` scripts), Chrono Trigger's save points (the **Shelter** item heals, not the point). The
one that heals fully is FF1's INN, a paid rest that also saves. The demo village already has an
inn charging four gold; a free full heal standing beside it would make the innkeeper a mistake.

**The demo keeps save-anywhere and gains a save point anyway** — the user's call, and it is the
both-directions proof on the surface a player touches: the pause menu still writes slots, and
the chronicler in the northwest corner writes them through a conversation. The `at_point`
restriction is proven on a fixture manifest that duplicates the shipped one and varies the
single field, which is the control-instance rule.

---

## A sweep tells you about one foe at a time — *M37*

**A gate whose DETECTION depends on font metrics is a gate that disagrees with itself across
machines.** M36's caption mutant killed on macOS and SURVIVED on the Ubuntu runner that gates the
merge — and not because of the platform alone: M37 shrank the caption (per-target lines are far
shorter than the combined one), which left the widest case landing within a PIXEL of the window
edge, where the two platforms' metrics fall on opposite sides. Measured: 305px against a 304px
budget.

- **Widen the fixture until it is comfortably over** — *Status: done, but not sufficient on its
  own. It moves the boundary rather than removing it, and the next content change moves it back.*
- **Aim the mutants at the CONFIGURATION instead (chosen)** — that the label wraps, and against a
  width somebody chose rather than the one pixel a Label falls back to. Nothing ambient can move
  that, so the mutant means the same thing on both machines. The measured audits stay as the
  outcome check; they are simply not what the coverage claim rests on.

**And `MESSAGE_LINES` went from 2 to 3** because M37's own change made two insufficient: the
caption is now a frame line PLUS a target line, and the target line can wrap on its own. Three is
EarthBound's in-battle box, and there is room before the foe bars. A milestone widening the thing
a previous milestone had just measured is the ordinary case, not a mistake — what would have been
a mistake is leaving the declared number at a value the view no longer keeps.



**Not a fork so much as a debt being paid**: M36 gathered the evidence and recorded the
divergence rather than acting on it, and this is the acting. The one real decision inside it:

**How do you express a "persistent frame" on a screen with ONE caption label?** Final Fantasy I
holds six boxes and undraws four of them between targets; this template has a label.

- **A second label for the frame** — closest to FF1 structurally. *Status: rejected — a second
  node to keep positioned, audited and themed, for a string that could simply be part of the
  first one.*
- **Repeat the whole sentence per target** — "You cast Gale. Gloom takes 12." then "You cast
  Gale. Slink takes 6." *Status: rejected — it says the frame rather than holding it, and reads
  as three separate casts.*
- **One label, two lines, the first identical across the sequence (chosen)** — which only became
  available when M36 gave the caption its second line. The frame does not move because it is the
  same string each time; nothing has to persist it.

**What makes it more than a faithful port:** it deleted a special case. M34's uniform-sweep
verdict and the content gate's matching attribution branch both existed because a combined
caption cannot say anything useful about identical numbers. Per-foe lines make the question
disappear rather than answering it — which is the shape worth noticing when a research finding
argues against something already shipped.

**Also folded in:** the effect clause takes its SUBJECT as an argument (one function, two call
sites that have named the target differently) and names the ELEMENT rather than saying "weak to
it" — which teaches the pairing instead of merely reporting that one exists.

---

## The caption wraps, and the fourth row gets pressed — *M36*

**The fork: what should a caption too long for its window DO?** §7c is the research, and it is
the rare case where the references genuinely disagree.

- **Clip or truncate** — *Status: rejected outright. Not one of the four games surveyed clips,
  and it is the worst option anyway: a caption that silently loses its tail is indistinguishable
  from one that was never written.*
- ~~**Split into sequential per-target messages**~~ — **Taken up by M37**, at the hook this entry
  named, and the feared cost did not arrive: all 22 sessions passed unchanged, because every one
  of them drives its fights with `fight_well` rather than counted waits. The persistent frame came
  with it.
- **Wrap to a second line (chosen)** — Dragon Warrior's answer, and the one the evidence made
  obvious once gathered: every reference message area holds more than one line (Pokémon 2,
  EarthBound 3, DW 8), so a one-line caption was this screen's divergence rather than its design.
  `MESSAGE_LINES = 2` is declared the way `MAX_PARTY` is, and is the number `DialogBox` already
  draws and size-gates against, so the two surfaces agree.

**Kept as a stated divergence:** the sweep caption still names every foe's damage on one line,
which §7c says the genre does not do. The numbers side by side are what let a player compare a
weakness against its neighbours — M33's argument for announcing at all — so it stays until the
sequencing alternative above is built.

**Not a fork, but the finding.** Containment alone is not enough, and the mutation run proved it
rather than a reading: with no width to wrap against a Label falls back to ONE PIXEL, and the
caption becomes a twenty-line column one word wide — absurd, technically inside the window, and
the containment audit passes it. The line count is what says a caption is drawable.

**And the flee assertion's first draft was self-fulfilling**, which is the transferable half. It
read each record's own `boss` flag to decide what to expect of that record, so flagging a slink as
a boss made the tutorial inescapable AND moved the expectation to match. It asserts the SET now —
exactly one shipped encounter refuses, declared independently — which also catches the deletion
case a per-record property check cannot see at all.

---

## The gate drinks, and a guard nothing had proven — *M35*

**The fork: does the casting policy also use items, or is that a fourth policy?**

- **Fold items into `CASTER`** — one fewer policy, and a driver that uses everything it has is
  arguably the most realistic player. *Status: rejected — it changes what CASTER means, and M34's
  three assertions were written against that meaning. It also makes a report ambiguous about
  which verb produced it: a fight won while both casting and drinking says nothing about either.*
- **A fourth policy (chosen)** — `DRINKER`, named for Final Fantasy I's own third command (Fight
  / Magic / DRINK / Item). Each verb policy adds exactly ONE page and the other stays a fault,
  which is what keeps each report about its own verb.

**The second fork: does the balance fixture carry a bag?** It never had one, and the comment on
`party_of` says why — the party carries nothing deliberately, so a formation it beats is one the
real player beats.

- **Give every balance fight a bag** — simpler, one fixture. *Status: rejected — it weakens every
  difficulty assertion in the file at a stroke, trading a pessimistic guarantee for a convenience.*
- **A defaulted argument (chosen)** — `_fight(..., items := [])`. Every difficulty assertion
  leaves it out and stays pessimistic; only the coverage tests pass a bag.

**Not a fork, but the finding.** `_battle_items` — the filter keeping a quest item off the battle
menu — had no test anywhere. It is one comparison, and behind it is the worst failure this
codebase can produce: using an item appends a take-effect whatever it was, so a key on that menu
is destroyed and its door shut for the rest of the run, hours before the player notices.

**Two mutants survived and neither was dead code**, which is worth recording as a pattern rather
than an incident. Reaching always for the first row, and drinking at full health, both passed the
content suite because the shipped bag EMPTIES — a driver that only wants the first row still
exhausts that stack and moves on, and one that drinks regardless still stops when the bag is
gone. The rules are real; the content masks them. They moved to `test_battle_driver.gd`, against
a bag that outlasts the fight.

---

## The gate casts, and aims the other way — *M34*

**The fork: how do you make a simulation gate see a subsystem it has never entered?**

- **Teach PERFECT to cast** — one driver, fewer moving parts, and the difficulty statement stays
  two policies rather than three. *Status: rejected — it changes what PERFECT MEANS, and every
  existing balance assertion was written against that meaning. A gate you retune to accept a new
  behaviour is a gate you have quietly weakened.*
- **A third policy (chosen)** — `CASTER`, appended so PERFECT and MASH keep the values every
  assertion already uses. The proof it is additive is that all 22 play sessions and all 17
  existing balance assertions are untouched, which is the same proof M33 offered for its fields
  and M27 for the party.

**The second fork: which foe does a casting driver aim at?** This looked like a detail and was
the milestone's main finding.

- **Weakest first, like PERFECT** — the sensible play, and what the driver already did. *Status:
  rejected — it makes the aim axis a constant across all policies, and a boss standing behind
  two mooks is then never the target of a spell while resources last. The Keeper's answer to
  fire was unobservable for exactly that reason.*
- **Toughest first (chosen)** — the opposite order, defensible on its own terms (magic is
  scarce, spend it on what takes longest to kill) and, being opposite, it reaches what PERFECT
  only arrives at once the fight is decided. **Aim is a policy axis exactly the way skill is.**

**The third fork, forced by the gate rather than chosen: should a SWEEP announce effectiveness?**
M33 said no, on the reasoning that its caption names what each foe took side by side. The gate
proved that reasoning holds only when the numbers DIFFER.

- **Never announce** — M33's answer. *Status: rejected by measurement — against a uniform
  formation every figure on the line is identical, so there is no baseline in view. Both hollow
  fights are uniform, and the only wind spell in the game is a sweep, so the slink's weakness had
  never once been announced in any fight at any level or seed.*
- **Announce per foe** — accurate and unaffordable: the caption is already 295px of a 312px
  budget. *Status: rejected — see the caption-width entry in the backlog.*
- **Announce only when uniform (chosen)** — one clause exactly when the numbers cannot carry the
  comparison themselves, nothing when they can, and the single-target wording when a sweep
  reaches one foe.

---

## An element is worth a percent, and the game says so out loud — *M33*

**The fork: how much is a weakness worth, and who writes the number down?** Tier words on the
enemy (`weak`/`resistant`) with the multipliers in `BattleLogic`, or a raw percent in the data.

- **Tier words + template multipliers** — reads better in a `.tres`, and the enemy file says
  something a designer can pronounce. But it puts a bare `* 2` in a script, which is exactly the
  literal-a-designer-would-want-to-change this project keeps out of code, and it caps the genre
  at whatever tiers the template invented: the references run from Pokémon's quarter damage
  (0.5 × 0.5 on a dual type) through immunity, and the day a game wants a fourth answer it has to
  come and ask for a new word. *Status: rejected — the vocabulary would be the template choosing
  the shape of every game's table.*
- **Percent in the data (chosen)** — `resistances = {&"fire": 200}`. One number, no vocabulary,
  and a game sits anywhere on the range without an edit to a script. Exactly 100 is refused
  rather than allowed as a no-op: it reads like a decision and changes nothing, so it is a typo
  or a note that belongs in a comment. The demo ships 200, 150 and 50, so the argument for a
  number over a word is visible in the content rather than only in this file.

**The second fork: a multiplier or a CHANCE?** Dragon Quest's resistance is not a reduction at
all — a resisted spell does not do less, it fails outright at a rate, and "if the spells work,
they will deal full damage". That is a real, attested genre model and it is not available here.

- **A chance to negate** — the DQ answer, and arguably the more dramatic one. *Status: rejected
  — M13 made flee odds and damage variance deterministic so a designer can reason about a fight
  and a QA script can replay it byte-for-byte, and a roll to negate a spell is precisely that
  kind of number.* Revisit hook: `_spell_damage`, which would draw from the fight's seeded stream
  the way `_pick_move` does.
- **A multiplier (chosen)** — Final Fantasy's and Pokémon's model, and the one that survives the
  determinism rule.

**The third fork: does the game TELL the player?** This is the one the reference pass reversed.
The genre splits, and §13b's finding is that **the split tracks the arithmetic**: Pokémon
multiplies and announces every non-neutral hit; Dragon Quest is binary, so only the failure needs
words; Final Fantasy I multiplies and says nothing at all — 35 battle-message constants and not
one elemental string.

- **Silent, FF1-style** — what the first implementation did, and the tempting one because this
  screen already draws a foe's health bar, so the number is visible. *Status: rejected — the bar
  shows what is left, not what was expected, so it cannot tell a player whether 12 was big. FF1
  is also the outlier that multiplies AND stays silent, and its elemental system shipped
  half-broken (the physical weakness bonus is unreachable for players, annotated `BUGGED` in the
  disassembly). It is a precedent worth not leaning on.*
- **Announced, Pokémon-style (chosen)** — a short clause where the element told, nothing at all
  where it did not, which is Pokémon's own dispatch: compare to neutral, return silently when
  equal. A sweep gets no clause, and that is the same rule rather than an exception — its caption
  names what each foe took side by side, so the comparison is already in the numbers.

**Not built, and recorded rather than forgotten:** the balance gate cannot see any of this.
`BattleDriver` only ever chooses Attack, so no element pairing can move a number it measures.
That is in the backlog above with its hook.

---

## A death and a boss get their own music, and a slot says why it is unreadable — *M32*

**The fork nobody expected to have:** whether a defeat should play anything at all. It was not
on the table — `_on_battle_finished` cut the music dead and said so in a comment, "every game
this borrows from cuts the music at a game over". The reference pass found that false. Final
Fantasy I ships **"Dead Music"** in 1987, and each Final Fantasy since has its own Game Over
scene. The references *change* what is playing at a death; they do not fall silent.

That is worth recording as a class of mistake rather than as a fact. **A wrong genre claim in a
code comment is more durable than a gap**, because a gap invites work and a claim invites
citation — and this one sat in the exact place anyone would look before changing the branch.
The rule that would have caught it is the one already in CLAUDE.md: research the surface before
building it. M26 built the surface and wrote the convention down from memory.

- **`game_over_music` on the manifest, played through `play_or_silence`** — *chosen.* "A game
  states its game-over music or states silence" is the same sentence a map's music is written
  as, and that function already exists for exactly it. A LOOP rather than a jingle: the screen
  is sat on while a player decides what to do about a lost run.
- *A jingle that plays once and then falls silent.* `rejected` — it is a fanfare's shape, and a
  fanfare is for a moment rather than for a screen you are still looking at.
- *Displace it with the title's theme on the way out.* `rejected — nothing had to be built`:
  every way out of a game over already states its own music, so the question the backlog entry
  called "a feel call" answered itself the moment the field existed.

**The fork within the boss theme: where does it live?**

- **A `music` field on `EnemyDef`** — *chosen*, and the references are the argument. Dragon
  Quest I (1986) ships eight tracks with one reserved for the Dragonlord; Final Fantasy I has
  ONE battle theme and plays it for every fight including Chaos; FF2 gives major bosses "Battle
  Theme 2"; by FF4 it plays for all but two. They disagree about *which* fights get one, so a
  template that decided would be deciding for every game built on it. A field on the enemy sits
  anywhere on that range. Note also that DQ had a boss theme before Final Fantasy existed, and
  FF1 had a game-over theme in the same game that had no boss theme — neither is downstream of
  the other, which is why they are two fields rather than one "extra music" feature.
- *Behind the existing `boss` flag.* Simplest, and no new field. `rejected — it fuses two
  questions`: `boss` means "cannot be fled", and a game wanting a themed non-boss (a rival, a
  duel) would have to make it unfleeable to get the music.
- *On the map's encounter record.* `rejected` — the encounter is where the FORMATION lives, and
  a theme belongs to the thing you are fighting rather than to the tile it stands on. It would
  also have to be repeated at every record that fields the same enemy.
- **In a formation, the first foe that STATES a track wins** — scanned in record order rather
  than read from `defs[0]`. A formation with a boss anywhere in it is a boss fight, and reading
  only the leader would make the Keeper's theme depend on where his escort was written down.

**The fork on the slot list: one object or two arrays.**

- **`SlotSummary`, replacing `Array[SaveData]` end to end** — *chosen.* The damaged fact and the
  save are one reading of one slot.
- *Keep `Array[SaveData]` and pass an `Array[bool]` beside it.* Much smaller — two signatures
  instead of nine. `rejected — it is the drift hazard this repo already has a rule against`: two
  paths answering one question, and the drift here pairs one slot's data with another slot's
  verdict, which is a wrong answer rather than a crash.
- *Have the world hand down finished row labels.* `rejected` — "Slot 2:" is view vocabulary, and
  `slot_label` is the one place three screens share it.

**What the type change cost, recorded because it is the interesting part.** `_has_any_save()`
tested each entry against `null`. An empty slot is now an *object*, so that check silently went
from "there is a save" to "there is a slot" — true of every row, and it would have offered
Continue to a player with nothing saved. Five suites caught it. **Widening a type turns every
null test written against the old one into a question with a different meaning**, and the ones
that still compile are the dangerous half.

## The flow model is walked, and a failing walk is shrunk — *M31*

**The fork:** M23's gate drives each edge once, from a world built for it. That is silent about
every SEQUENCE of edges — and the bug the model exists for *was* a sequence. So: how do you
check paths without checking all of them, and what do you hand back when one fails?

- **Seeded random walks, replayed from an explicit SEQUENCE** — *chosen.* Six walks of
  twenty-four steps on one world that is never rebuilt between steps. The plan is a list of edge
  indices, not just a seed, because minimising a failure means re-running walks the planner would
  never have drawn. A seed identifies the walk that failed; only a sequence can identify a
  *shorter* one.
- *Replay from the seed alone.* Smaller to store and enough to reproduce.
  `rejected — it makes shrinking impossible`: every candidate the minimiser wants to try is a
  walk no seed produces, so the whole search would have nowhere to send its answers.
- *Exhaustive paths up to length N.* Complete, and no randomness to explain.
  `rejected — the branching factor`: WORLD has six exits, so length six is already tens of
  thousands of walks and length twenty-four is not a number. Random walks with asserted edge
  coverage buy the same confidence for one second of gate time.

**The fork within it: how is a failing walk minimised?** A 24-step walk is not a bug report.

- **Cycle elision** — *chosen.* Delete the steps between two positions that sit in the SAME
  state. It is the one edit to a graph walk that cannot break connectivity, so every candidate is
  drivable by construction and a failed re-run means exactly one thing. It cut its first real
  failure from 24 steps to five: `continue, open_pause, close_pause, open_pause, close_pause` —
  the bug stated exactly, since it takes one close before the second open.
- *General delta debugging* (drop arbitrary steps, keep what still fails). The textbook answer.
  `rejected — most of its candidates are not walks`: dropping a step usually leaves the next one
  departing from a state the walk is no longer in, so the search would spend its budget on
  sequences that cannot be driven, and would have to tell "does not reproduce" apart from "is not
  a walk" on every one.
- *Report the seed and let a human read the walk.* `rejected — it is the thing this replaces`,
  and it is what makes a rare failure expensive rather than cheap.

**Where the walks live, and one thing that would have been tidier.** They are test functions in
`test_flow_model.gd`, beside the per-edge gate whose adapters they compose, rather than a new
suite with the adapters extracted into a shared driver. The extraction is the better-looking
shape and buys nothing today: one caller, one file, and a refactor of the gate that would have to
be proven byte-identical first. **Revisit hook:** the day a second suite wants to drive an edge,
`_drive`/`_arrive_at`/`_invariant_holds` are what move to `tests/helpers/`.

**How a walk reaches a LOSING fight**, which is the edge with two hops and therefore the one most
worth composing. `_drive` takes the adapter that follows it and opens an unwinnable fight when
the walk intends to lose. Rejected: giving the model a field for it (the model would then
describe the harness, not the game), and leaving `lose_battle` out of walks (which drops the
defeat path, the only two-hop edge that a walk can reach twice).

**What the walk actually proved, stated exactly.** It found no defect in shipped code — nothing
was broken. What it did was kill two mutations the per-edge gate SURVIVES, both the same shape: a
screen that is closed but never freed stays in the tree and goes on consuming input, so the
second time the player opens the menu nothing happens. Seven candidate mutations were run twice
each, with the walk tests collected and not collected; five behaved identically both ways. The
measured pair is the whole argument for the layer, and it is worth saying that it had to be
measured — the first three candidates reasoned out in advance all survived both ways.

## Ordinary fights are pairs, and the second sword moved onto the road — *M29*

M28 built formations and spent them on one optional encounter in a corner; a normal
playthrough never met a crowd. M29 spends them on the game: both hollow fights and the cave
become pairs, and the Keeper gets an escort. The research is `GENRE_CONVENTIONS.md` §7b's new
paragraphs, and it answers the question with a date — Dragon Quest I fights one monster with
one hero, Dragon Quest II is the first with a party AND the first with "enemies in much
greater numbers", in the same release. A party and a formation are one design decision seen
from two sides.

Which forces the fork, because this template's companion was **declinable**. The arithmetic is
not close: a lone player who mashes dies to the *first* slink pair, in a hollow whose own data
comments call it a tutorial that cannot kill you, and a lone player who times **every** press
still loses to the Keeper's escort. Sizing fights for two while letting the player travel alone
ships two games and balances one.

**The fork: how is the second character guaranteed?**

- **The roads out of the village require her.** *Chosen.* `requires_flag: rook_joins` plus a
  `locked_dialog` on the hollow and cave warps — the shape the barred keep gate has used since
  M12, so it cost no mechanism. It keeps the recruit conversation, keeps `joins_on_flag` proven
  as a live template seam rather than a feature only a test exercises, and Rook's existing line
  already argues it: *"Two of us come back from it; one doesn't."* The warden's *"one sword is
  enough for a village this size"* stops being flavour and becomes the rule the map enforces.
  It is also the genre's answer — DQ2 hands you the Prince through the story, and only lets you
  continue short-handed much later, when he falls ill.
- *She joins at boot.* Simplest by a distance, and no play session would need a recruit leg.
  `rejected — it deletes the only place the demo exercises joins_on_flag`, turning a template
  seam into dead code the day it shipped, and throws away a written scene to save editing test
  fixtures.
- *Keep the solo route winnable.* Tune the pairs down until one character clears them.
  `rejected — it makes the pairs token`: the fights would have to be weak enough that the
  second body is decoration, which is the opposite of what was asked for. Worth naming because
  it is the option that looks like it preserves player freedom and actually spends the feature.
- *A difficulty setting.* `deferred — worth trying` if a solo run is ever wanted back. Revisit
  hook: `GameManifest` would carry the alternative combat/formation data, which is a real
  design (two authored games) rather than a multiplier.

**The cost, stated:** seven QA sessions gain a recruit leg they did not need, and the village
now has a soft wall in it. That second one is a feel question and only playing answers it.

## Statuses expire with the fight, and point both ways — *M30*

`GENRE_CONVENTIONS.md` §13 carried the same closing line from M25 to M29: sleep was the only
status effect and it acted on the enemy only. §13a is the research that closed it, and it found
that boosts and afflictions are not two systems — EarthBound's Assist branch is one branch doing
both, "boosting or weakening the stats of an ally or foe … or inflicting a status ailment".

**The fork: how long does a status live?**

- **Battle-only, counted in turns.** *Chosen (user's call).* Everything lives in the pure
  `BattleLogic`, expires when the fight ends, and writes nothing — no `GameState` field, no save
  v10, no migration, and "a fight never writes" survives intact. It is also where the references
  put their buffs: DQ's Buff and FF1's `TMPR`/`FOG` are all battle-only.
- *Persistent afflictions* — FF1's poison follows you onto the map and drains as you walk, and
  DQ's does the same. `deferred — worth trying`, and it is a milestone rather than a field: a
  save version, a migration, a map tick that can reduce HP outside a fight, a cure to buy, and a
  decision about what reaching zero on the overworld means. Revisit hook: the `Status` holder,
  which would need a second home on `GameState` beside the party's numbers.

**The fork: one signed number, or two verbs?**

- **`Kind.BOOST` at an ally and `Kind.SAP` at a foe.** *Chosen.* Each names what it does, and
  the target follows from the kind exactly as it does for `HEAL` and `ATTACK`.
- *One kind with a signed `power`.* `rejected — a verb spelled as the absence of its opposite`.
  That is the same argument `Kind.UNEQUIP` was created for: a negative boost is a decode every
  reader has to remember, and the one who forgets ships a spell that heals when it should hurt.

**The fork: rolled durations, or stated ones?**

- **A fixed `status_turns` in data.** *Chosen.* DQ rolls its ranges (Buff 4–6, Sap 6–9), and
  this template does not: M13 made flee odds and damage variance deterministic so a designer can
  reason about a fight and a QA script can replay it byte-for-byte, and a duration is the same
  kind of number. `rejected — a rolled duration` for that reason, and the entry is here so the
  next person does not re-derive it.

**The display divergence, stated.** Two secondary sources say FF1 replaces a character's HP
readout in the battle block with `POIS`/`STON`/`DARK`; the manual is silent and both first-hand
pages are bot-blocked, so §13a cites it without leaning on it. This screen **appends** a tag and
keeps its numbers, because FF1 replaces out of necessity — one block, room for one number — and
this one has a caption line and a bar. Imitating a constraint the screen does not have would
cost the player information for the sake of fidelity.

**`Row.STATUS` gains nothing, deliberately.** A battle-only effect cannot be true while the
pause menu is open, so a status line there would describe a system the player can never catch in
the act — the same reasoning that keeps an `MP 0/0` line off a member with no magic.

## A scripted fight is played well by the harness, not by arithmetic — *M29*

Play sessions used to land timed hits by waiting a computed number of frames between presses,
chained off the cue and message lengths in `quest_combat.tres`. That arithmetic described a
four-round **duel**; the moment the Keeper gained an escort every chain stopped ending the
fight, and it failed as "the battle never ends" half a script away from what had changed.

- **A `fight_well` op.** *Chosen.* Confirms through every menu and presses inside every timing
  window, reading `BattleScreen.cue_on()`/`choosing()` — the scripted twin of the balance gate's
  `BattleDriver.Policy.PERFECT`, so the fight the gate proves winnable is the fight the session
  plays. Two small public reads on the view, and the harness finds the screen by TYPE, so
  nothing in the shipped scene carries a hook that exists only for tests.
- *Re-derive the frame offsets for the new formation.* `rejected — it buys one milestone`. The
  next change to a cue length, a message length or a foe count breaks it again, and the failure
  never points at the thing that moved.
- *Let the sessions mash.* `rejected — mashing cannot win the Keeper`, by design: that is the
  difficulty statement the balance gate proves in both directions.

`press_until_state` stays, and is now the deliberate way to play BADLY — only the first press of
a cue counts, so mashing never lands a timed hit. Both verbs are worth having.

## The Keeper's escort is mixed, and fills the screen — *M29*

**The fork: what stands beside the boss?**

- **Keeper + Gloom + Slink.** *Chosen (user's call).* A mixed formation, which is Final Fantasy
  I's attested shape ("a mix of up to 6 small and 2 large"), and three bodies exactly fills
  `BattleScreen.MAX_FOES`, so the boss out-scales the ordinary pairs instead of matching them.
  It also reuses art that already exists. Timed play wins with roughly half the party's health
  intact; mashing loses in about three rounds — so the difficulty statement the Keeper was
  built to make survives, now made of a formation against a party rather than a duel.
- *Keeper + two Slinks.* A gentler version of the same idea, and the one the arithmetic
  recommended. `rejected — the mixed pair is more interesting for the same press count`.
- *Keeper + one minion.* `rejected — the boss fight would be the same size as every other
  fight`, which stops "the boss has minions" reading as anything.
- *Keeper + two Glooms.* Not offered, because it was **measured as unwinnable**: two glooms
  plus the Keeper out-damage a level-2 party faster than the party can clear 58 health, even
  with every press timed. Recorded so nobody re-proposes it as the obvious escalation.

Killing the Keeper does not end the fight — every foe must fall, which is the template's rule
and the genre's. The Mack shape (minions respawn, the boss leaves the field) stays in the
backlog; this is a formation with a boss in it, and says so.

## Gold halved per body, rather than prices doubled — *M29*

Twice as many bodies pay twice as much. The purse is what the smith's prices and the "two
tonics sit between the two outcomes" tuning are built against, so it had to be held.

- **Halve each enemy's gold.** *Chosen.* `slink` 4 → 2, `gloom` 6 → 3, `keeper` 25 → 20, so
  every fight that GREW pays exactly what it paid before. Two-line edit, the required economy is
  untouched, and the play sessions' `assert_gold` values came back **unchanged through the whole
  hollow** — which is the independent check that the arithmetic was right, rather than numbers
  re-recorded because the suite said so.

  **The exception, and it is real:** `the_pair` in the hollow's north-west pocket was ALREADY a
  formation in M28, so its bodies did not double and its payout genuinely halved, 10 gold to 5.
  Its xp did not move either, which means the doubled curve slid past it: it used to carry the
  player to level 3 and now falls seven short. Optional bonus content, no required fight
  affected, and stated here rather than quietly re-recorded — the design promises a level for
  the optional CAVE, whose pair pays exactly one curve step and which the content gate pins.
- *Double the prices instead.* `rejected — more edits, and it moves numbers a player reads`.
  The inn's four gold a night is a nice number and the shop is tuned; halving a reward the
  player never sees itemised is the quieter change.
- *Leave gold alone and let the player be rich.* `rejected — it silently retunes the shop`,
  which is a design change nobody asked for arriving as a side effect of a content change.

XP goes the other way for the same reason: awards are left alone and the **curve doubles**
(`[10, 12]` → `[20, 24]`, in both combat definitions), which reproduces every levelling beat
exactly — level 2 still lands at the end of the hollow, the optional cave is still worth
precisely one level, and the Keeper is still met at level 2 and left at 3. Halving xp per enemy
would have needed non-integer awards; doubling the curve is one number on each side.

## A fight holds a crowd, and one map record names it — *M28*

The research is `GENRE_CONVENTIONS.md` §7b. What it settled first is that "one foe" was never
a convention this template was honouring — Dragon Quest I is the only reference that fights
one at a time, and every other game in the set fields formations. So this is a scope line
being retired, not a divergence being abandoned.

**The fork: where does a formation come from?**

- **One map record names its foes.** *Chosen.* The record keeps its `enemy` and gains an
  optional `group`, so the body you walk into is the first foe and the rest ride with it.
  Super Mario RPG is the shape — battles "begin by moving into an enemy on a main game map"
  while 512 formation records sit in ROM behind them — and Chrono Trigger's set encounter
  points are the same idea. Composition stays level design. Existing records need no edit,
  because a record with no `group` is a formation of one.
- *Adjacent bodies merge into one fight.* EarthBound does this, and its manual is the reason
  to refuse it: "**occasionally**, other nearby enemies may join in on the fight, even though
  they were wandering around separately." Occasionally is a roll, and composition would then
  depend on where a wandering NPC happened to stand — which is the objection M13 raised
  against step-counter encounters, arriving by a different door. `rejected — it makes a
  fight's shape a function of the movement loop`.
- *An `encounter` resource beside `EnemyDef`.* `deferred — worth trying` the day a formation
  needs a rule of its own rather than a list (a boss with respawning minions is the attested
  case). Revisit hook: the record's `group`, which would become an id.

**One record is one encounter is one seen key is one seed**, whatever the foe count. That
falls out of the record being the unit, and it is what keeps a fought-and-fled crowd replaying
identically: a foe downed before the party ran is standing again next time, because the
encounter was never marked. Deliberate, and stated because the alternative — a seen key per
foe — would make "which half of this fight did I already win" a thing saves have to carry.

## The cursor points at one foe, and is skipped when there is only one — *M28*

**The fork: how does the player say which foe?**

- **An individual cursor over the living foes.** *Chosen*, and it is the ally cursor mirrored
  exactly, down to the skip. Final Fantasy I moves a "finger" over the enemy sprites; Super
  Mario RPG uses the D-pad and asks **only "if there is more than one enemy"** — which also
  answers the question §7a had to leave open in M27 about whether the classics skip a
  one-option cursor. That skip is what keeps every fight this template has already shipped
  pressing the same keys.
- *Dragon Quest's group cursor*, which picks a group and hits a random member. `rejected` — it
  is a compression device for eight sprites, and at two or three it costs a whiff the
  individual cursor does not have (DQ2 misses outright at a group that has emptied).

**A stale target cannot happen here, and that is M27.1 paying for itself.** FF1's
"Ineffective" — aiming at an enemy that died earlier in the round — is its most complained-
about behaviour, and it exists *because* FF1 enters every command before the round resolves.
Act-as-you-choose closes the gap: the cursor lists the living at the moment it opens, and the
blow lands on the same beat. No retarget rule, no dead-target message, no test for either.

## Every living foe takes a turn, and the cap is what keeps that bearable — *M28*

- **Each living foe acts, in foe order, after the whole party.** *Chosen.* Every reference
  game gives every living enemy a turn — FF1's nine are nine of the thirteen entries in its
  shuffle, SMRPG interleaves both sides by Speed, DQ orders by Agility. None of them has
  enemies act as a *block* after the party, so this extends the divergence the template
  already recorded ("party in order, then the enemy") rather than opening a new one.
- The cost is honest and unavoidable: **N foes mean N defend cues in a round.** SMRPG is the
  precedent that a timed block per incoming blow is playable. What no reference does is skip
  an enemy's attack for pacing, so the relief comes from the cap: **three foes**, declared by
  the view and — this time — enforced by a content gate that refuses a map record asking for
  more. (M27 declared `MAX_PARTY` and enforced nothing, which M27.1 found and wrote down; the
  same gate now covers both sides.)
- Status is **per foe**: FF1's sleepers each roll their own wake, so a battle-wide asleep flag
  cannot express the rule. A sleeping foe loses its own turn and the others still swing.

**The two seeded streams stay two.** Draws are ordered by foe order over the existing
`derive("moves")` and `derive("target")`, so a one-foe fight draws exactly the sequence it
drew before and every shipped session replays byte-identically with no compatibility branch.
Rejected: a derived stream per foe, which would need foe 0 to keep the bare label — an
index-zero special case whose only observable effect is the compatibility itself. The
consequence, stated: a foe dying or falling asleep shifts the draws of foes after it *within
that fight*. That is deterministic in the seed and the inputs, which is all the replay
guarantee ever claimed.

## A spell's target shape is data, and the foe bars multiply — *M28*

**Groups and multi-target magic arrive together, in the genre and here.** Dragon Quest I has
no group spells because it has no groups; DQ2 introduces both in one game and shapes its list
by target (Firebal at one, Sleep and Infernos at a group, Explodet at everything). FF1's
manual says the same from the other side. So `SpellDef` gains a `Target` of `ONE` or `ALL` —
the shape is a property of the spell, authored in data, which is what this template's own
backlog nominated. `ALL` is refused on heals and on sleep for now: both are verbs whose
multi-target versions are real genre nouns and neither is needed to ship a crowd.

**The fork: does the enemy side show health?**

- **A bar per foe.** *Chosen by the person this is built for*, and it is a divergence stated
  out loud rather than a neutral layout call. **No reference game shows enemy HP** — FF1 lists
  enemy *names* in their own box and spends its four HP boxes on the party, DQ2's window shows
  names and how many are still up, EarthBound and Chrono Trigger show nothing, and Super Mario
  RPG makes it a *reward*: Mallow's Psychopath spends a whole turn to read one enemy's
  remaining health. Five references to zero. But the numeric foe bar has been on this screen
  since M13 and has been played that way ever since, so the choice was between extending a
  shipped divergence consistently and removing something the player already reads. Extending
  it also mirrors the party's own blocks, which is one visual language rather than two.
- *Names and a living count* (DQ2's answer, and the genre's). `deferred — worth trying`, and
  the hook is small on purpose: it lives in `_foe_caption` and one `_build` branch.

## A party is a list even when it is one, and membership is a flag — *M27*

The largest system the audit ever listed as missing, and the two calls that decided its shape.

**The fork: does a game without a party take a different path through a fight?**

- **One path, with the solo player synthesized into a member.** *Chosen.* A game that declares
  no `party` is handed a single Fighter built from `player_character` and `combat`, named "You",
  knowing everything its level has reached — so `BattleLogic`, `BattleScreen` and the menus
  always see a list. The evidence it worked: all sixteen scripted play sessions pass untouched,
  the solo layout is pixel-identical, and 60 of the 79 battle-logic tests never mentioned a
  party at all.
- *A solo path and a party path.* Rejected. The phase machine would exist twice, and the solo
  one would be the tested one — which makes the party path the place bugs live and nobody looks.
- **The cost, stated:** a leader cannot be given a name or a narrowed spell list, so Dragon
  Quest II's magic-less hero is not expressible. `deferred — worth trying`; the revisit hook is
  leader-override fields on `GameManifest` beside `player_character`.

**The fork: how is somebody recruited?**

- **Membership is DERIVED from a flag.** *Chosen.* The manifest declares the roster; each member
  carries `joins_on_flag`, and the party is everyone whose flag is set, computed every time it
  is asked. This is `SpellDef.learn_level` applied to people, and it deletes the same things:
  no join op, no roster save field, no migration, no way to hand out the same companion twice,
  and no membership that can drift from the event that granted it. Recruiting is the `set_flag`
  a dialog choice already carries, so a game recruits however its own content says.
- *A `join` effect op with a saved roster.* Rejected — it is a second list of who is in the
  party, and the one that goes stale is whichever the reader did not check.
- What IS saved is each member's numbers, which is a different fact entirely.

**Two more, decided with the person this is being built for.** The overworld draws ONE sprite
(Final Fantasy I–VI ship exactly that; a follower line is `deferred — worth trying`, and the
revisit hook is a driver reading the leader's `Locomotion.Step` history — it is meaningfully
harder under free pixel movement, which has no grid steps to trail). And **capacity is three**,
declared by the view and audited by the layout suite at exactly that number: the band between the
fighters' feet and the help line holds three blocks at 320x180, and the demo ships two. This
entry said "enforced by the build" until M27.1 went looking for the check and found none — the
layout was proven AT capacity, which proves the drawing and not the data. **M28 made the
sentence true**, on both sides: a content gate now refuses a manifest declaring more members
than the screen draws and a map record naming a bigger formation, each proven by a mutant that
zeroes the constant.

## A member acts the moment they choose, in party order — *M27, reversed in M27.1*

**The fork: when does a member's choice happen?**

- **Each member acts the moment they choose.** *Chosen in M27.1, on play.* The turn belongs to
  one member at a time: they pick, it happens, and the next member is asked once the blow has
  landed. [Super Mario RPG](https://www.nintendo.com/us/whatsnew/heres-all-you-need-to-know-about-battling-in-super-mario-rpg/)
  is the genre precedent — "all the characters will wait their turn to perform an action", and
  "when it's your turn to act, you'll choose an action" — though it orders those turns by Speed
  where this template uses party order.
- *Every standing member declares, then the round resolves* (Final Fantasy I's manual; Dragon
  Quest gives orders only at the start of a turn). **Shipped in M27 and rejected on play.** The
  citations were sound and the implementation was correct; what they could not tell us is how it
  feels to hold the controller. The first person to play it: *"if I choose Attack with the MC, it
  doesn't attack right after, the new party member chooses. It shouldn't be like that."* A press
  whose effect is invisible for a whole extra menu reads as a press the game ignored. `rejected —
  a faithful convention that plays badly here`, and the lesson is that a convention with named
  games behind it is still a hypothesis about feel.
- *ATB, interleaved on per-character timers* (FF4–6, Chrono Trigger). Rejected outright:
  `BattleLogic` has no clock by design — it is handed one physics frame at a time, which is what
  lets a QA script press on an exact frame. ATB needs the thing this class refuses to have.

**What the reversal deleted, rather than moved.** The declaration queue; the `cancel` that took
back the previous member's order (nothing is left to unwind once each choice has already
happened, so a menu `cancel` is refused for everybody — the pre-party rule, restored rather than
special-cased); and the re-checks asking whether a queued cast or item could still be paid for,
which guarded a gap between choosing and acting that no longer exists. Redundant defence that no
test can reach is an unkillable mutant waiting to be misdiagnosed, so it went with the rule.

**The fork: what decides who acts first?**

- **Party order.** *Chosen.* Dragon Quest rolls agility, and rolling anything here
  would put a random draw in the turn order of a template whose whole determinism story is what
  makes sixteen play sessions a gate. The precedent that makes this genre-honest rather than a
  concession: **Final Fantasy I's own resolution order is a random shuffle of all thirteen
  combatants that ignores everyone's stats**, so the foundational entry does not derive order
  from a stat either.
- *An agility stat on `CombatDef`.* `deferred — worth trying`, and it pairs with the backlog's
  "flee odds and damage variance". The revisit hook moved with M27.1: it used to be
  `_resolve_next`'s walk over the queue, and it is now `_advance()`, which walks `_living()` in
  index order and would instead walk it in an agility order settled once per round.

**And the cursor.** `Phase.ALLY` opens only when more than one member is standing — the same
argument that kept an enemy cursor out when fights went 1v1, applied to the ally side. Skipping
it at one is what keeps every session written before M27 pressing the same keys. Fallen members
are not offered as targets, because reviving mid-fight is a verb this template does not have
(`deferred`; the hook is `ally_rows()`, which returns the standing).

## Falling is not losing, and the living earn all of it — *M27*

- **A member at nought hp is DOWN, not out of the game**: no turns, no xp, and the fight is lost
  only when everyone is down. Every reference game.
- **Every living member earns the FULL award.** *Chosen: Dragon Quest's rule.* Final Fantasy I
  divides among survivors, which punishes a small party for being small — and the demo party is
  two, the size division hurts most — and needs a rounding decision that one shared xp curve has
  nowhere to put. The fallen earn nothing in both series.
- **Revival is the inn, and it needed no new mechanism.** Dragon Quest's priest charges by level
  and EarthBound's hospitals do it for money; this template already sells a full night through a
  conversation, so `_rest()` loops the party and a fallen member wakes whole. *Rejected:* a
  separate revival price or a Life spell — both are a second thing that means "full", and what
  "full" is already belongs to the running game's `CombatDef`.
- **`party_unset()` stopped being "nought health".** This is the one place M27 could corrupt a
  run. Since M13, zero hp has meant "never fought" and is what makes the world derive a player
  from the curve. With a party, **a leader at zero beside a standing companion is a real,
  saveable state** — they fell, somebody finished the fight, and the survivors are walking to an
  inn. Read the old way it refills them on the way into the next fight: a silent resurrection
  that deletes the consequence the player is walking to town to undo, and **no test about a solo
  game can see it**. The question is now "nought health AND nobody standing", asked in one
  function that `to_save` and the refill both read.

## Web audio looping was investigated and nothing was changed

A player reported music not looping in macOS Safari. It turned out the in-game sound setting
was off. Recorded because the investigation produced two things worth keeping, and because the
outcome — shipping nothing — is the part most likely to be re-litigated.

- **Kept: the finding.** Godot's web Sample playback does not use the browser's own looping.
  It waits for the source node's `ended` DOM event and then builds a new node and starts it,
  in JavaScript. `AudioStreamWAV.loop_mode` is therefore necessary and not sufficient there,
  and a failure would be silent — music once, then nothing, no error. That is a real hazard
  and it is now in the backlog above with its one-line fix.
- **Chosen: ship nothing.** With the volume off, no music played at all in either browser, so
  there is no observation of web looping succeeding *or* failing. The honest state is unknown,
  not broken. Stream playback carries a cost Godot's own docs warn about — "high audio latency
  and crackling, especially when exporting a single-threaded game" — and this build is
  single-threaded. Paying a documented cost to insure against an unobserved bug is the wrong
  trade, and the fix is one line the day the symptom is actually seen.
- **Rejected: keeping it anyway, since it was already written and green.** A change is
  justified by the defect it fixes, not by the effort spent building it. The worse half was
  the prose: the decision entry and CLAUDE.md paragraph asserted as fact that Safari had
  failed to loop, which would have been read later as evidence rather than as a guess.
- **What did survive the same investigation** is in the entry on the title's voice: the title
  played into a bus with no voice bound, which was real, reproducible headless, and had been
  shipping silently on every platform since M22. Two of the three audio gates could not have
  seen it. That bug was found by reading the deployed build's console while looking for
  something else entirely.

## A fanfare is a chained play, not a property of the track

- **Chosen: `AudioBus.play_music_then(id, then_id)`** — one-shot-ness lives in the CALL. The
  same file could be somebody's title theme, so "played once" is a fact about the playing, and
  a tune that has to be declared a jingle in its own JSON is a tune that cannot be reused.
- **Rejected: a `loop: false` flag in the track's JSON.** It would have to be plumbed through
  `MusicTrack` into `AudioBus.reload()`, which binds streams long before anything knows what
  they will be used for — metadata carried across two layers to answer a question asked at the
  third.
- **Rejected: `AudioStreamPlayer.finished` as the clock.** The signal is free and unconnected
  and would still be wrong: headless runs on a dummy driver that never reports a stream as
  playing, which is the same measurement that made `music_starts()` exist. Frames are what
  every other timed thing here counts, and `--fixed-fps 60` pins them.
- **Chosen: the one-shot is a DUPLICATE with looping off.** `_play` assigns the table's own
  instance to every later caller, so switching its loop off in place would leave the next map's
  theme playing once and stopping. Nearly unobservable — the frame counter replaces the stream
  either way — but `ceili` rounds the count up, so a looping fanfare gets up to a frame of its
  own head back before it is replaced. Asserted on the PLAYING stream, not just the stored one.
- **Chosen: a jingle asked for twice stings twice**, bypassing the no-restart guard. A jingle is
  an event where a theme is a state.

## Defeat stops the music, and a battle's end does not check whether it started one

- **Chosen: `stop_music()` on a defeat.** Every reference game cuts at a game over; the defeat
  sting is already a cue; and every way OUT of a game over states its own music again — the
  title plays the manifest's theme, and a restart or a load enters a map, which states one
  either way. This is the one deliberate behaviour change for a game that had map music only.
- **Rejected: guarding the restore on having displaced anything.** "Only put the map's music
  back if this game named a battle theme" reads as obviously right and is a branch nothing can
  distinguish: when nothing was displaced, the map's music is already playing and the bus
  refuses to restart a track it is already on. A branch no test can tell from its absence is
  decoration, and this repo removes those rather than keeping them with a mutant that cannot
  bite (the `NpcBrain.STATIC` early return, M17). The control test proves the no-op instead.
- **Chosen: `AudioBus.play_or_silence(id)` as the one answer to "what does this place sound
  like".** Three callers need it — entering a map, a fanfare handing back, a fight ending — and
  three copies of "states its music or states silence, never inherits" is two copies too many.

## Knowing a spell is derived from level, never stored

- **Chosen: `SpellDef.learn_level`, filtered per fight by `world_scene._battle_spells()`** —
  a spell is known the instant the player's level reaches it, computed fresh every time the
  way `CombatDef.attack_at(level)` is. Dragon Quest learns Heal at level 3 from a flat table
  and Chrono Trigger unlocks a Tech at a threshold; neither asks the player to do anything.
  What this buys is everything it does NOT need: no known-spells save field, no migration for
  it, no learn effect op, no menu verb, and no way for the list to disagree with the level
  that bought it. A designer retuning `learn_level` retunes every existing save.
- **Rejected: teach-by-item** (DQ2's Words of Wisdom, later scrolls). It is a real convention
  and a real supplement, but it *requires* the stored set this design avoids — the whole cost
  of the alternative is the thing the chosen one is chosen for. `deferred — worth trying`;
  revisit hook in the backlog above.
- **Rejected: equip-a-pool** (FFVII Materia, FFVI Espers). Arrives late in its own series and
  is a system of its own, with its own screen and its own progression. Not a template noun.
- **Rejected: skill points / a tree.** Not attested in any of the five games surveyed
  (FF1–6, Dragon Quest, Chrono Trigger, EarthBound, Pokémon) — a later-era and largely
  different-genre convention.

## Magic is battle-only, and MP joins the party writer rather than the purse

- **Chosen: no field-menu Magic page.** FF6 and Dragon Quest do give Magic its own field
  command, so this is a real divergence rather than an oversight — but every out-of-battle
  job such a page would do is already done. A full restore is the inn's entire reason to
  exist, and there is no warp, light or field-utility mechanic here to hook a spell to. The
  page would either duplicate the inn or sit empty. `deferred — worth trying`.
  EarthBound and Chrono Trigger's alternative (fold it into Status) is half-taken already:
  the Status page carries the MP line, just not the spell list.
- **Chosen: `set_party(hp, xp, level, mp)`, with mp REQUIRED**, rather than gold's
  `give_mp`/`spend_mp` pair. Gold moves on its own — a sale, a drop, a purchase — so it needs
  verbs of its own; MP only ever moves alongside hp, in a fight resolving, a night at an inn,
  or a level restoring the player. A separate writer would be a second place that has to
  remember to be called. Required rather than defaulted because a call site that omitted it
  would silently empty the player, and that reads in play as a bug in whatever spent it.
- **Chosen: mp inside the save's `party` dict**, not beside it like `gold`. It shares party's
  "empty means no combat here" answer exactly: a game with no fighting has no magic either,
  and a top-level key would be the one field claiming otherwise.
- **Chosen: an old save migrates to nought magic, not full.** The call every migration step
  before it made — but with a second reason of its own: what "full" is depends on the game's
  `CombatDef`, which a migration may not reach, so a number invented in `migrations.gd` would
  be wrong for every game but the one it was copied from.

## A cast has no timing window, and a spell's damage ignores armour

- **Chosen: no timed press on a cast.** The timing window is this template's own invention for
  swinging a weapon — a thing you aim — where a spell in every game this borrows from resolves
  because you chose it. Giving magic a window too would make the entire fight one reflex test
  and leave the menu with nothing to decide.
- **Chosen: flat damage, ignoring `EnemyDef.defense`.** It is what gives magic a job beside a
  stronger swing: the answer to something armoured, and a bad deal against something soft.
  It also means `SpellDef.power` is the damage and nothing else, which is one fewer number to
  tune against a second one.
- **Chosen: three kinds — attack, heal, sleep.** Two would have been thinner than anything the
  genre shipped: Dragon Quest 1 has one character and eight spells, and even that set is
  damage, heal, Sleep and Stopspell; Sleep is tier one in FF1. `SpellDef.Kind` is a closed
  enum, `ItemDef.SLOTS`'s shape, so a hand-edited kind fails the build.
- **Chosen: elements as NAMES, no resistance system.** EarthBound's own shape — PSI Fire and
  PSI Freeze with shallow mechanical payoff — and it costs nothing where a matrix costs a
  field on `EnemyDef` and a rule per pairing. `deferred — worth trying`.
- **Chosen: no targeting step.** Fights here are 1v1, so an offense spell hits *the* enemy and
  a heal targets *the* player; a cursor would be a mode with one option in it. `deferred` on
  the day a party or a multi-enemy fight exists.
- **Chosen: a refused cast is SAID and costs no turn.** Money's precedent exactly — a price is
  quoted out loud, so a player reaching for what they cannot pay for hears why rather than
  pressing a key that appears broken. Rejected: hiding unaffordable spells, which would make
  the list change shape as the player spends, and silently refusing, which is the dead key.

## NPC movement freezes with the player, and the brain is pure

- **Chosen: `NpcBrain`, a pure class answering with an intent vector, driven from
  `world_scene._physics_process` BELOW the `player_can_move()` gate.** The intent vector is
  what makes it cheap: `ActorBody` already handles both movement modes, animation and the
  step meter, and its own header always said the player and every NPC "differ only in what
  drives them". This is the other driver, and no movement code was written twice.
- *A Node per NPC with its own `_physics_process`* - rejected: it would move on its own
  schedule, which means a second answer to "is the world running" and a speaker who can
  wander off mid-sentence unless something remembers to pause her.
- *Freeze only the SPEAKER during dialog* - rejected: the halt-to-face done when a
  conversation opens would silently stop being true for everyone else, and a town walking
  behind a dialog box while the player cannot move reads as the game having lost the input,
  not as ambience. Freezing everything is one line's placement and covers pause, battle and
  game-over for free. Revisit hook: the `_drive_npcs()` call site.
- *Behaviours as a game hook rather than map data* - rejected: patrol and wander are RPG
  vocabulary, not one game's design. A hook would mean every game writes movement code.
- **A typo'd behaviour fails the build.** Falling back to `static` would make `"wonder"` look
  like a shy NPC rather than a misspelling, and nothing on screen would ever say otherwise.
- **Every shipped NPC stays `static`,** because seven of ten QA sessions use their bodies as
  walls. Movement ships as new content placed where no session walks - a constraint found by
  reading the sessions, not by assuming.

## Two Godot MCP servers, and the addon stays out of the repo

- **Chosen: add `godot-live` (`@satelliteoflove/godot-mcp`) beside `godot`
  (`@coding-solo/godot-mcp`) in `.mcp.json`, and do NOT commit its editor addon.** The bench
  (`tools/mcp_bench`) settled the first half: they are complements, not competitors. One
  scaffolds and spawns a headless engine per call (250ms; 835ms for `create_scene`); the other
  reads and drives a running editor over a WebSocket bridge at a flat 7ms and cannot create a
  scene at all. Two entries cost nothing - with no editor running, `godot-live` reports "not
  connected".
- *Also commit and enable `addons/godot_mcp`* - **rejected on measurement.** Its `plugin.gd`
  calls `ProjectSettings.save()` to force an `MCPGameBridge` autoload, and that save **strips
  every comment from `project.godot`**: the QOA-importer explanation and the `config/game`
  refusal note both disappeared, and restoring them by hand did not survive the next build
  that loaded the plugin. Those comments are load-bearing - CLAUDE.md cites both. The forced
  autoload is then a second problem with no good side: leave the addon in the pack and it
  ships (+1MB, `exec_commands` included); exclude it and every packed boot prints three
  `Failed to instantiate an autoload` errors, which is exactly the log noise #41 removed.
- *Replace `godot` with it* - rejected: it has no `create_scene` and no `add_node`, so
  scaffolding would be lost outright.
- **Not a security problem, checked rather than assumed.** The bridge autoload gates on
  `EngineDebugger.is_active()` and speaks the debugger protocol rather than opening a port,
  so it is inert in a release export even though it ships. The addon's own source says so and
  the packed run confirms it. The objection is comment loss and log noise, not RCE.
- **Deferred - worth revisiting** if the addon gains a way to run without registering the
  autoload, or if `project.godot` stops carrying documentation worth losing. Revisit hook:
  `_ensure_game_bridge_autoload()` in `addons/godot_mcp/plugin.gd`, and the on-demand recipe
  in CLAUDE.md.
- **`npx` launch kept** for both, despite `npx` costing 494ms to connect against 64ms for a
  resolved binary. A direct path is machine-specific or an npx cache path that can be
  garbage-collected; portability beat 430ms once per session.

## The NPC carry was fixed narrowly, not by switching motion mode

- **Chosen: `platform_floor_layers = 0` on every ActorBody.** A player found NPCs being
  dragged sideways when he walked past them - but only when they approached from ABOVE. The
  cause is the moving-platform feature: `on_floor` against a moving body inherits its
  velocity, measured at 0.8px a frame (exactly walk speed) until the NPC was two tiles off
  her route. Clearing the layers opts out of exactly that and changes nothing else.
- *`MOTION_MODE_FLOATING`* — **deferred, worth trying**: it is what Godot recommends for
  top-down and it removes the floor/ceiling concept the bug is built on, rather than one
  feature that hangs off it. Rejected for now because it is not a bug fix, it is a movement
  change: floating alters how every body slides along every wall, and all eleven play
  sessions are calibrated against the current sliding. Switching it diverged
  `finish_the_quest` at the hermit and cascaded into 16 failures - none of them about NPCs.
  Whether the resulting slide feels better is a question for someone who has played it.
  Revisit hook: one line in `ActorBody._init`, plus re-deriving the affected legs.
- *Collision layers, so actors never touch* — rejected: the player would walk through NPCs,
  and seven QA sessions use NPC bodies as walls. It also deletes a real interaction rather
  than fixing it.

## Terrain is authored pixel art in a bank of its own

- **Chosen: a `TileBank` in `data/tiles/<id>.json`, authored in the rig's alphabet.** Tiles
  were the one art noun still in code — a `const TILES` of six in `TileGen`, drawn by five
  hardcoded routines (`scatter`, `speckle`, `ripple`, `brick`, `blob`). The cost was not
  abstract: no routine can draw a door, so `quest_cave.json` built an interior out of
  grass-world tiles, and a game that wanted a floor edited a file under `scripts/`. Authored
  grids make a tile as expressive as a character part, and reuse the alphabet a rig author
  already knows.
- *Move only the LIST to data, keep the procedural kinds* — rejected: it reads like the same
  fix and unlocks nothing. A new tile could still only look like one of five existing
  patterns, so the interior problem would survive the refactor intact.
- *Keep both — procedural for texture, authored for shapes* — rejected: two ways to author
  one thing, forever, and the tile appearance would stay half in `scripts/`. The procedural
  routines earned their keep once, as the SOURCE of the port: every pixel they drew was one
  of three tones or transparent, so the six shipped tiles converted losslessly and the
  committed PNGs did not move.
- *A `tiles` key inside `data/rigs/<id>.json`* — deferred, worth revisiting if the two ever
  turn out to move together in practice: it needs no new directory and no new style field.
  Rejected for now because terrain and cast should swap independently — the day an AI sprite
  source draws the characters, the ground should not have to be redrawn with them. Revisit
  hook: `SpriteStyle.tile_bank_id`, which is the only thing keeping them apart.
- **A tile's `ramp` is a default, not a requirement.** Every style previously carried an
  identical six-key `tile_ramps` dict, so adding a tile was a mandatory edit to all three.
  The bank names the default and `tile_ramps` overrides it — the same shape as the rig's
  `slot_defaults`. All three styles dropped their dict entirely, which the drift gate proved
  was a no-op.

## The shop screen is windows over the world, and asks "how many"

- **Chosen: panels over the live world, with a quantity step.** M18 shipped a full-screen dim
  with three lines of floating text; the user played it and said, correctly, that it was not
  a shop. Researched afterwards rather than before (the process failure is in
  docs/learnings.md): the JRPG UI survey, Game UI Database's buying screens, and shop-flow
  write-ups converge on list + prices + purse + description + keeper, with pick -> how many ->
  confirm as the buy flow.
- *Full-screen shop screen* — rejected: it reads as the game changing screens rather than the
  player walking up to a counter, and it hides the town the shop belongs to.
- *A shopping cart (accumulate, then check out)* — deferred, worth trying if a game wants bulk
  trading: it is the other convention the research turned up. Rejected now because it needs a
  second confirm surface and a cart to draw, for a template whose shops sell two things.
  Revisit hook: `ShopMenu.Deal` already carries a count and a total, so a cart is a list of
  Deals rather than a redesign.
- **Rotating stock, synthesis shops and deal boards** (the jrpg-design-codex's shop patterns)
  are GAME design, not template scope: they are what a game builds on `ShopDef`, and baking
  any of them in would be designing somebody's game.

## Equipment stays in the bag, and arrives at a fight as two ints

- **Chosen: `GameState.equipment` is slot -> id, and the item never leaves the inventory.**
  The Dragon Quest model. Moving an item out of the bag on equip would make the bag a
  half-truth ("what you have, except what you are using"), and every existing reader — the
  pause list, the sell counter, `requires_item` — would need to learn about a second place
  things live.
- *Equipment as its own container* — rejected for that reason; revisit hook is
  `GameState.equipment`, which would become a second Inventory.
- **Mods reach `BattleLogic` through `of()`'s parameters, already summed.** Stats are derived
  from level, so gear must be a modifier or there are two sources of truth for one number;
  and BattleLogic may not reach the Registry, so the world does the resolving.
- *A stats struct passed into the fight* — deferred, worth it the day a third modifier source
  appears (a buff, a status effect): the revisit hook is `of()`'s two int parameters, which
  would become one object. Rejected now because two ints need no ceremony.
- **Cursed gear (negative mods) is refused** by `ItemDef.problems()`. A game that wants it
  wants a different noun with its own rules — the same call `battle_heal` made about negative
  healing.

## A price belongs to the item, not to the shop

- **Chosen: `ItemDef.price`, with `ShopDef` listing ids only.** One price per item is what
  makes the sell side honest without a second table: a shop that named its own prices would
  need a buy price and a sell price per keeper, and the two would drift.
- *Prices on the shop's stock rows* — deferred, worth trying the day a game wants a haggling
  keeper or a discount: the revisit hook is `ShopDef.stock`, which would become an array of
  dictionaries instead of ids. Rejected now because one keeper needs none of it.
- **`price = 0` means not tradable, and it is the default** — the same "zero is off" shape
  `ItemDef.battle_heal` and `GameConfig.grid_step_pixels` already use. An item joins the
  economy by being priced, never by being forgotten, so quest items are safe by construction.
- *The shop opening inline from the effect list* — rejected because it does not work:
  `_on_dialog_closed` applies effects and THEN closes the dialog overlay, so the counter is
  what the close pops. Deferred instead, which is the narrow fix; applying effects after the
  close would reorder every dialog effect there is, for a bug that is only about shops.

## Gold is party state, not an item

- **Chosen: `GameState.gold` as its own field, saved as its own key (v6).** It reads like an
  item ("a thing you carry, counted"), and the Inventory would have held it for free — but an
  item is something `ItemDef` describes, `Registry` resolves and the bag can refuse; money is
  none of those. Making it an item would have put a currency in the item list, in the pause
  bag page, and in every `requires_item` check that was never written to think about it.
- *Gold as an inventory entry* — rejected: free to build, and it leaks into every surface that
  iterates the bag. The one real benefit (saves and hooks carry it automatically) is one field
  and one migration step here.
- *A `Wallet` class beside `Inventory`* — rejected as premature: a wallet with one currency is
  an integer with ceremony. Revisit hook if a second currency ever appears: `GameState.gold`
  plus its two verbs are the only places that would change.
- **A spend is refused, never clamped**, matching `Inventory.remove`'s all-or-nothing rule —
  so a purse cannot go negative by construction, and no downstream check has to tolerate one.

## Engine and language

- **Chosen: Godot 4.7 with typed GDScript.** The user's other 2D RPG (saltcharter) is
  Godot, so its headless gate, mutation harness and gdUnit4 setup transfer directly instead
  of being reinvented — and a template is worth most in the engine its owner actually
  reaches for.
- *Phaser 3 (TypeScript)* — rejected: batteries-included tilemaps and physics would have
  reached a first screen sooner, but Phaser's own patterns would then be the template, and
  headless testing of movement is much harder.
- *Vanilla TypeScript + Canvas* — rejected: everything would be ours and testable, but it
  means writing a renderer, a tilemap and a physics layer before writing a game.

## The sprite generator is procedural, with a source seam

- **Chosen: a code-native paperdoll rig, deterministic from a seed, behind a
  `SpriteSource` interface.** Consistency is the actual requirement, and a procedural rig
  gives it *by construction*: every character is composed from the same parts, the same
  palette ramps and the same outline rule, so they cannot drift apart. It is free, offline,
  reproducible, and every consistency rule can be a test.
- *AI-first (PixelLab / Retro Diffusion)* — deferred, worth trying: higher fidelity, and
  its `character_id` does keep one character consistent across its own animations. Rejected
  as the default because it needs an API key and credits, cannot be regenerated
  deterministically in CI, and a template that cannot build its own art offline is not a
  template. Revisit hook: `scripts/spritegen/sprite_source.gd`.
- *Layered LPC art (Universal LPC Spritesheet)* — rejected: excellent art, but it is
  GPL/CC-BY-SA licensed and locks the template to one visual style, which is the opposite
  of the goal.
- **Expected quality tier, stated up front:** clean GB/SNES-era chibi with a strict
  palette. Not hand-painted. Higher fidelity is a source swap, not a rewrite.

## Cell size is 16×24, not 16×32

- **Chosen: a 16×24 character cell on 16px tiles.** Planned as 16×32, changed while laying
  out the rig: a 24-row cell gives a head that is a clean third of the height (the chibi
  proportion that stays readable at 16px wide) with no dead space, and 24 = 1.5 tiles keeps
  characters and terrain in one size family. A 32-row cell left eight empty rows above every
  head that only a tall hat would ever use.
- *16×32* — deferred: worth revisiting if the template ever wants hats, helmets or long
  weapons that break the head line. Revisit hook: `cell_size` on the style plus the `at`
  offsets in the rig; nothing in code assumes 24.

## Slots that must share a colour, share it

- **Chosen: `slot_ramp_from` in the rig — sleeves follow the body, hands follow the head.**
  Randomised characters otherwise get pale hands on a dark face, which reads as a rendering
  bug rather than as a data one. An explicit ramp on the character still wins, so gloves are
  expressible.
- *One ramp per slot, always* — rejected: simpler, and produces a visibly broken cast the
  moment skin tone is randomised.

## Generated colours are computed in whole bytes

- **Chosen: `Color8` arithmetic for the tinted outline, not `Color.darkened()`.** An 8-bit
  image truncates a float channel while `Color.to_rgba32()` rounds it, so a float-derived
  colour reports one value and comes back out of the PNG one unit darker. The palette gate
  caught it on the tinted style's first run.
- *Loosening the palette gate to a tolerance* — rejected outright: a palette whose members
  depend on which side of the pipeline you ask is not a palette, and a gate with a tolerance
  cannot catch the next colour that leaks in.

## Rigs and stamps are JSON, not .tres

- **Chosen: `data/rigs/*.json` holding ASCII pixel grids.** Pixel art authored as text
  (`.` transparent, `1/2/3` = ramp tones) is readable and diffable in a way a binary or a
  `.tres` multi-line string is not, and it is the idiom that worked in the user's earlier
  jrpg-1 sprite module.
- *Resources (.tres) for parts* — rejected: multi-line string arrays in a `.tres` are
  hostile to edit by hand and produce unreadable diffs.
- *A dedicated editor* — deferred: the Sprite Lab scene shows the result; an editing UI is
  a project of its own.

## Free pixel movement, not grid-step

- **Chosen: free movement with four-direction facing**, axis-separated collision so walls
  slide. It feels better to move around in, and it is the model both of the user's earlier
  2D projects used.
- *Grid-step* — **shipped in M9** as a mode rather than a replacement: `grid_step_pixels` at
  zero is free movement, and set to the tile size it is one press per tile. See "Grid stepping
  is a distance, not a timer" below. (This bullet said "deferred" for eleven milestones after
  the thing it deferred had shipped.)

## Maps are data files, not scenes

- **Chosen: `data/maps/*.json` — ASCII rows plus a legend, built at runtime.** A map you
  can read in a diff and generate from a script is worth more in a template than one that
  needs the editor open, and it keeps "add a game" inside `data/`.
- *Editor-authored .tscn maps* — not rejected: `MapBuilder` accepts a PackedScene too, so a
  project that outgrows ASCII can keep the same spawn/warp plumbing.

## Committed art is PNG + JSON only

- **Chosen: the generator writes PNGs and a sheet JSON; `SpriteFrames` and `TileSet` are
  built at runtime.** A committed `.tres` referencing a texture that has not been imported
  yet breaks on a fresh clone, and it would weld the contract to Godot — the same PNG+JSON
  pair can feed any engine.
- *Committing SpriteFrames/TileSet resources* — rejected: faster to load, but it puts
  engine internals in the art pipeline and makes a fresh checkout order-dependent.

## CI installs Godot itself, with a pinned checksum

- **Chosen: download the official build and verify a SHA-512 pinned in the workflow.** A
  checksum served by the same host as the file cannot detect that host serving a different
  file, so the sum lives in the repo where a change to it is reviewable.
- *A third-party setup-godot action* — rejected: one more supply-chain dependency to
  SHA-pin and audit for a step that is four lines of `curl` and `sha512sum`.

## The web build is single-threaded

- **Chosen: `variant/thread_support=false`, pinned in the committed export preset.** A
  threaded web build needs `SharedArrayBuffer`, which needs the COOP/COEP cross-origin
  isolation headers — and GitHub Pages cannot send custom headers, so a threaded build would
  export successfully, deploy successfully, and then refuse to start in the browser. Godot
  4.3+ makes single-threaded the default and supported path for exactly this reason.
- *Threaded, hosted somewhere that can send headers* — deferred: better audio latency and
  real threads, at the cost of the demo no longer being one file in a repo. Revisit hook:
  `export_presets.cfg`, one line, plus a host that is not Pages.

## Deploy waits for CI rather than racing it

- **Chosen: the Pages workflow triggers on `workflow_run` of the check workflow, gated on
  `conclusion == 'success'`, and checks out that run's `head_sha`.** A plain `push` trigger
  runs the deploy *beside* the tests, not after them — which looks identical every day until
  the one where a red build ships. Pinning the SHA matters too: `workflow_run` checks out the
  default branch's HEAD by default, which is not necessarily the commit that was tested.
- *A `needs:` in one workflow* — rejected: it would couple the demo's slow template download
  to every PR's feedback time.

## The QA harness drives the real game

- **Chosen: an autoload that reads a JSON script and drives the running game.** Not a choice
  so much as a discovery: `-s tools/x.gd` cannot even *load* a scene whose script names an
  autoload, because singletons are not registered as identifiers in that mode. Anything that
  needs the real game must be driven from inside it.
- Two things it must do that were not obvious. Count **physics** frames, not idle ones —
  headless they run at wildly different rates, so "hold right for 30 frames" would mean a
  different distance on every machine. And press through `Input.parse_input_event`, not
  `Input.action_press` — the latter sets input *state* (what polling reads) and never
  delivers an *event* (what handlers read), so a harness built on it can move the player
  around perfectly and never press a button.

## Testing: gdUnit4, vendored, with a mutation harness

- **Chosen: gdUnit4 6.2.0 committed into `addons/`, run from the CLI, plus
  `tools/mutants.tsv`.** Vendoring makes a fresh clone runnable with no plugin install, and
  the mutation harness is what keeps the other gates honest.
- *Trusting a green suite* — rejected on the evidence: gdUnit4 exits 0 when a discovery
  crash means it ran nothing, so `check.sh` counts executed suites against suites on disk.

## Which game runs is a manifest resource, chosen by a precedence that refuses to guess

The fork: `world_scene.gd` held `demo_town`, `start` and `hero` as consts, so a second game
could not exist without editing the generic world. Where should those live, and what picks
between two games?

- **Chosen: a `GameManifest` resource per game in `data/games/`, selected by
  `--game=` > the `application/config/game` project setting > "there is exactly one".**
  A resource rather than loose settings because a game is a *set* of decisions that travel
  together, and because `config: GameConfig` can then be a real reference the exporter
  follows rather than a path string that fails at first step.
- *Extra fields on `GameConfig`* — rejected: `game_config.tres` is the numbers a designer
  tunes, and "which map do we start in" is not a number. Two games sharing one feel would
  also have had to duplicate every tuning value.
- *A `--game` argument only* — rejected: the exported web build has no command line, so the
  browser demo could never be anything but the default.
- *A project setting only* — rejected: the QA harness cannot edit `project.godot` on its way
  past, so a second game would only ever be reachable by walking to it through a warp.
- *Picking the first game when nothing chooses* — **rejected on the failure mode, which is
  the whole point of the entry.** Booting the wrong game does not present as a selection
  bug; it presents as the game you meant to run behaving strangely, and you go and debug
  that. Refusing costs one line of config and is unmistakable.
- *A title screen that lists the games* — `deferred — worth trying`. It is the friendly
  version of the same choice and needs `Router.State.TITLE` to actually be entered, which
  nothing does yet. Revisit hook: `scripts/data/game_select.gd::ids()` already returns
  exactly the menu such a screen would show.

## Game code lives in `games/`, is reached through `GameHooks`, and never names an autoload

The fork: the template had nowhere to put gameplay. Every new mechanic landed in
`world_scene.gd` — the file whose entire job is to be game-agnostic — and `ARCHITECTURE.md`
said so out loud ("new mechanics → new files under `scripts/`").

- **Chosen: a `GameHooks` subclass under `games/<id>/`, named by the game's manifest, handed
  a `GameContext` rather than the autoloads.** One name in data resolves to one object with
  one lifecycle, it is a `RefCounted` testable with no scene tree, and `on_interact`'s
  return-`bool` shape is what a battle or a shop would need later without re-cutting the seam.
- *A per-kind handler registry that game code registers into* — rejected: something has to
  run before anything can register, and the only "runs at boot" slots are autoloads or
  `world_scene._ready`, so it needs the hooks seam as its bootstrap and you end up with two
  mechanisms. `deferred — worth trying` as an internal shape once a game outgrows a `match`;
  hooks can hold one privately. Revisit hook: `GameHooks.on_interact`.
- *A script path per map or per object in the map JSON* — `deferred — worth trying` as an
  escape hatch, rejected as the primary seam: the interesting state is cross-cutting ("she
  reacts because you opened the chest"), so it routes through flags anyway and the flag
  vocabulary ends up spread across a dozen files with nowhere to validate it. It is also the
  hardest to gate — there is no single function whose absence a mutant can prove.
  Revisit hook: `Interaction.resolve`, which already takes hooks as a parameter.

The **no-autoload** rule is the load-bearing half, and it is mechanical rather than stylistic.
`--check-only` and `tools/compile_all.gd` both skip any script naming a singleton, so game
code reaching for `GameState` would leave two of the four gates without saying anything.
`GameContext` is therefore a snapshot plus an effect list — the `DialogRunner` pattern, which
collects flags and lets the caller apply them — and `LintCore.RULE_AUTOLOAD` fails the build
rather than a doc paragraph asking nicely.

Three things stayed deliberately untouched, each with the reason it would have been the wrong
work now:

- *`Router`* — it owns input, not scenes, and does that correctly. `TITLE` and `PAUSED` are
  unreachable because no title screen or pause menu exists: a missing feature, not a broken
  router. (Its `state_name()` is a positional array literal that would mis-name every state
  if a member were ever inserted — `deferred — worth fixing`, revisit hook `router.gd:27`.
  **Both fixed in M10**: the pause menu reaches `PAUSED`, and the name is derived from the
  enum.)
- *Dialog effects* — conditional nodes, `clear_flag`, item/warp/sound nodes. An NPC reacting
  to what you carry is three lines of game code (`ctx.say(a if ctx.has_flag(k) else b)`), and
  `set_flag(key, false)` gives clearing for free. Inventing a mini-language instead would
  have proven nothing about whether the hooks seam works, which is the point of the milestone.
  `deferred — worth trying`; revisit hook `dialog_runner.gd::_go_to`.
- *`SaveData`* — a quest is expressible in `flags` and `seen`, both already typed, persisted
  and migrated. Adding a per-game dictionary is purely additive later and does not re-cut
  this seam. `deferred`; trigger: the first game that needs a count rather than a boolean.
  **That trigger fired in M12** — see "Items are the template's business after all".
  (A `game` FIELD landed in M10 for a different reason — see below — but the per-game
  dictionary is still deferred on the same terms.)

## The second game lives in this repo rather than in one that consumes the template — *superseded in M11*

The fork: the template's claim needed testing by building something else on it. Where should
that something else live?

- **Chosen: `data/games/quest.tres` plus `games/quest/`, beside the demo, in this repo.** CI
  runs both games' play sessions on every push, the gates cover the second game's content the
  same way they cover the first, and the acceptance criterion is checkable — the commit that
  adds the game must not touch `scripts/`, `tools/` or `scenes/`, which `git diff --stat`
  answers. It also makes the repo a worked example rather than a description of one.
- *A separate repo that pulls the template in* — `deferred — worth trying`, and it tests
  something this cannot: **starting from the template**, which is the actual use case. Cloning,
  renaming, deleting the demo, and finding out what breaks is a different question from
  "can a second game coexist". Not done now because template fixes would have to be ported
  back by hand, and CI could not see the result. Revisit hook: `data/games/` — a game is
  already a self-contained set of files, so lifting one out is a copy rather than a surgery.
- *A branch, or a throwaway spike* — rejected: a spike answers the question once and then
  rots, and nothing keeps the answer true. The point of the exercise is a claim that stays
  checked, which needs the second game in CI.

What it found, which is the argument for having done it at all: three template defects that
six milestones of unit tests, mutants and gates had not — a QA op that raced the steps after
it, an art gate that walked a different set of directories than the game did, and three
disagreeing lists of "which directories does this project own".

## Nothing choosing a game asks a human, rather than refusing — *superseded in M11*

M7 decided that two games with nothing choosing between them is a **refusal**, because a
guessed game presents as the game you meant to run behaving strangely. That was right, and it
was right for a reason with an expiry date: there was nobody to ask. This is that entry
landing, and it does not overturn the decision so much as finish it.

> **Superseded.** One game ships as of M11, so there is nothing to choose between and the
> picker was deleted with the second game. The precedence it consumed is unchanged, and the
> refusal below is what a second game would meet again. Kept for the reasoning, not as
> current behaviour.

- **Chosen: the picker is what happens when `GameSelect.should_ask()` is true** — more than
  one game, and neither `--game=` nor the project setting nor "there is only one" having
  answered. `choose()` is untouched, so the precedence stays one pure function in one file,
  and the picker is a new *consumer* of its "nothing chose" answer rather than a competing
  rule. Everything that already chose still skips the menu, which is why all seven scripted
  play sessions run unchanged.
- *A picker that always appears at boot, with `--game=` skipping it* — rejected: it makes the
  project setting mean "preselected row" instead of "the game that boots", and a template
  cloned down to one game would show a menu with one entry in it.
- *Reaching the picker only through Tab, leaving boot alone* — rejected: the deployed page has
  no command line and no Tab-before-you-start, so the one surface where choosing matters most
  would be the one surface that could not.
- *A separate title scene, swapped to with `change_scene_to_file`* — `rejected — for now`. It
  would fix the four build-once guards for free by rebuilding the world from scratch, but it
  is the repo's first ever scene change, `Router` deliberately owns input rather than scenes,
  autoloads survive a swap so `GameState.reset()` is still needed, and the deferred-frame
  timing is a new source of races for a QA harness that steps in physics frames. The overlay
  costs one `CanvasLayer` and a teardown that is testable in one file.

**The setting ships empty**, which turned two gates red and both fixes were improvements:
`smoke_boot` now validates *every* shipped manifest rather than only the one that boots — with
a picker, every game is reachable from the first screen — and `test_game_select` asserts the
project either boots a game or offers one, which is the real property.

Closing the M7 note that pointed at `GameSelect.ids()` as the revisit hook: a menu needs
titles, start maps and characters, so it is built on `manifests()` and `unresolved()` instead.

## A second game varies only what its design demands

The Barred Gate shipped with a `GameConfig` of its own, whose only difference from the
template's was `allow_diagonal = false` — "the pure four-direction feel of the earliest
top-down RPGs". The reasoning was fine. The decision was not mine to make quietly.

The user found it in the first minute of playing and asked the right question: *what else is
missing?* That is the real cost. A second game exists to **isolate** what building a game
actually changes, and every gratuitous difference destroys that: once one thing differs for no
reason the design asked for, the player cannot tell a deliberate choice from a defect, and the
control instance has stopped being a control.

- **Chosen: The Barred Gate shares `data/game_config.tres`, and `dusk16` matches `gb16`'s
  animation timing exactly.** The only axis the second game moves is colour — palette and
  outline. Anything that feels different from now on is a bug, by construction.
- *Keep the four-direction feel as a shipped design choice* — rejected. It is a good idea for
  some game; it is a bad idea for the one whose job is to hold everything else constant.
  A game that wants it sets one field, and `GameConfig.allow_diagonal` is still there for it.
- *Keep `dusk16`'s slower gait* — rejected for the same reason, though it was the more
  defensible of the two: `STYLE_GUIDE` does list timing as a style axis and `nes16` varies it.
  But the game wearing `dusk16` is the control, so its style is a control too.

The rule this leaves: **a game brings its own config when its design needs one, not to have
one.** `GameManifest.config` is still per-game — the capability is the point of the seam — and
`docs/ARCHITECTURE.md` now says when to use it.

`tests/fixtures/qa/quest/walk_diagonally.json` is the gate. Every one of the seven play
sessions that existed held a single direction at a time, so none of them could see this — the
new one holds two and requires both axes to move.

## Grid stepping is a distance in the config, and it has no clock

One press = exactly one tile, tweened, instead of free pixel movement. The first item in this
file's backlog, now built.

- **Chosen: a pure `GridWalker` beside `Locomotion`, one per actor, selected by
  `GameConfig.grid_step_pixels > 0`.** The direction still comes from `Locomotion.step()`, so
  `allow_diagonal` and the ties-go-horizontal rule have one implementation between the two
  modes rather than two that drift.
- *A second implementation of `Locomotion.step()`* — which the backlog entry and
  `locomotion.gd`'s own comment both promised — **rejected once it was looked at.** `Locomotion`
  is static and an actor holds only its facing, so there is nowhere to keep how far through a
  step it is. The per-actor state was the entire cost, and the comment has been corrected.
- *A `movement_mode` enum* — rejected: no enum exists in any `scripts/data/` resource,
  `camera_smoothing > 0.0` sets the "zero means off" precedent, and an enum would leave the
  step *distance* homeless. An actor holds a `GameConfig` and never the map's `SpriteStyle`, so
  the distance has to live with the selector or be plumbed through `setup()`.
  `GameManifest.problems()` checks the step against the start map's tile size, which is the one
  place both facts are in scope.
- *Landing the step by predicting distance-per-frame* — rejected on measurement.
  `move_and_slide()` picks its own delta (physics inside a physics frame, idle otherwise), so a
  prediction overshoots in exactly the hand-driven loop the integration tests use. A step ends
  when its target stops being *ahead*. `test_engine_assumptions.gd` pins that engine fact.
  The cost is that a step's duration quantises to whole frames — up to one frame per cell,
  invisible and consistent, where a mispredicted landing would be neither.
- *A pause between steps* — `rejected — not built`. Continuous walking under a held key is the
  expected feel, and a pause of three frames or more makes any "N still ticks means blocked"
  helper report blocked in open ground.
- *Input buffering* (a direction tapped mid-step being remembered) — `deferred — worth trying`.
  Today a tap during a step is lost and a direction still held when one ends is picked up on
  that same call, so there is never an idle frame between steps. Revisit hook: `GridWalker.plan`,
  which already sees the input every frame and could latch it.

**No shipped game uses it.** `data/game_config.tres` keeps free movement, both manifests keep
sharing it, and not one of the QA fixtures changed — about 10 of their steps encode
"N frames = M tiles" arithmetic that grid mode would void. The honest gap: the scripted play
gate never exercises the mode. It is covered by 21 unit cases and 8 integration cases driving a
real body into real walls, plus 15 mutants.

A blocked diagonal **slides** along its free axis rather than stopping dead, matching
`move_and_slide` and the existing diagonal-slide gate. It is free here: the grid is
axis-aligned, so the slid-to position is itself a cell centre.

## Saves are per game, and a file must agree with the directory it sits in

The fork: two games ship in one build, sharing this save format and these field names. Whose
progress is `slot_0.json`?

- **Chosen: `user://saves/<game>/slot_N.json`, and the save NAMES its game.** "Slot 1" then
  means one thing — the first slot of the game you are playing — and the pause menu lists only
  slots it could actually load. The name inside the file is checked against the directory on
  every read, so a file copied, moved or hand-edited into the wrong game is refused and parked
  rather than loaded. That check is the point: a demo save loading into the quest does not
  present as a mismatched file, it presents as the quest being broken, and you go and debug
  the quest.
- *Shared slots that switch game on load* — `deferred — worth trying`: one list, and loading
  a slot boots the game it belongs to. Rejected for now because a load becomes a full teardown
  and boot rather than a map entry, and the slot list has to render every game's palette and
  character to be readable. Revisit hook: `world_scene._commit_load`, which would call
  `start_game(manifest)` before `restore(data)`.
- *One flat namespace with the game stored inside* — rejected: the slot numbers still collide,
  so "slot 1" means whatever was saved there last, and the menu has to filter a list whose
  numbering then has holes in it.

### The v2→v3 step takes the game as an argument

A file older than v3 cannot say which game it is; the directory it was found in is the only
evidence there is. So `Migrations.apply(raw, game)` takes it as **data**, which keeps every
step a pure function of `(file, game)` — the frozen-forever property a migration needs.

- *An adopting loader* (fill the field in from the caller after migrating) — rejected: it
  makes "this file said nothing" and "this file said the right thing" the same case, so the
  cross-check that catches a misfiled save can never fire on an old one.
- *Refusing everything below v3* — rejected: the chain exists precisely so old saves survive,
  and refusing them makes `supported_versions()` a lie.

### A scripted session saves under `user://qa_saves`, wiped at boot

`SaveManager.dir_for()` reads the command line: any `--qa-script=` and saves go to a separate
directory, emptied on start. A play script that wrote to the real one would overwrite a
player's progress on a machine that has both, and one that READ from it would pass or fail
depending on who ran it. The QA fixture leans on this directly — it opens Load on an empty
slot and requires the refusal, which is only deterministic because the directory is known
empty.

- *A fresh temp directory per run* — rejected: it leaks one directory per run, and nothing
  ever proves the run started clean; wiping a fixed known path is checkable.

### Reading the slot list has no side effects

`peek()` is a separate, silent read: no `save_changed`, no parking, no `push_error`. Merely
LOOKING at the pause menu must not produce `.corrupt` files. The consequence is that an
unreadable slot is drawn as *empty*, which is why `save()` parks whatever it is about to
overwrite — otherwise the menu, which refuses to load an "empty" slot, could never park a
damaged one but could silently save over it.

- *Distinguishing empty / unreadable / another game's in the list* — `deferred — worth trying`:
  a row reading "Slot 2: unreadable" is more honest than one reading "empty". It needs a
  tri-state return where there is currently a nullable one. Revisit hook: `SaveManager._read`
  already computes exactly that distinction and throws it away at the boundary.

## The pause menu is Resume / Save / Load, and Escape is what opens it — *Items added in M12*

The fork: a pause menu is where a game puts everything that is not playing. What goes on it?

> **Amended in M12.** A fourth row, **Items**, sits directly after Resume: it is the row a player
> opens most often, and Save/Load keep their order relative to each other. The cost was one that
> only a mutant found - `test_pause_and_saves`' navigation helper counted two presses to reach
> Load and silently became a SAVE, quietly writing a slot in the middle of a test about refusing
> to load one. Any test that navigates a menu by counting is a test that re-aims itself when a
> row is inserted; those now name the row (`move(PauseMenu.Row.SAVE)`) rather than counting to it.

- **Chosen: three rows, and Escape opens it from the world.** Save and Load are the reason it
  exists; everything else on a typical pause menu is either already a keypress here or is a
  feature this template does not have yet. Escape (`cancel`) was the one bound action the world
  did not handle.
- *A "Switch game" row* — `deferred`: with one game there is nothing to switch to, and the
  row would come back with the second game rather than before it.
- *Settings (volume, window, bindings)* — `deferred — worth trying`: none of the three have
  anywhere to be stored yet. `AudioBus` is the seam a volume row would use.
- *Quit* — rejected: the web build cannot honour it, and a menu row that does nothing on one
  of two shipped platforms is worse than no row.

The pure/view split is `DialogRunner`/`DialogBox`'s exactly: `PauseMenu` is a cursor over pages
and slots with no nodes in it, `PauseScreen` paints it from a `SpriteStyle`. Opening a slot
page returns `NONE` — changing what is on screen is not something the world has to act on —
which is what keeps "arriving at the save list" from writing slot 0.

### Loading an empty slot is refused, not clamped

`PauseMenu.confirm()` on an empty LOAD row returns `NONE`. The precedent is
`DialogRunner.choose()`: clamping to the nearest filled slot turns a UI mistake into a
plausible-looking wrong answer, and here the wrong answer is loading a game the player did not
ask for. Saving is not symmetric — an empty slot is exactly where a save goes.

That refusal is also the first of two fail-closed layers for a misfiled save, and it fires
first: a save that does not read back reads as **empty**, so the menu never offers it. The
loader's own check is the second, and the only way to reach it through the menu is for a slot
to go bad between the frame that drew it and the frame that loaded it. That is the case the
integration suite stages, because it is the only one that exercises the screen's latch.

### The screen latches when it answers, and a refusal has to un-latch it

`PauseScreen` stops accepting input the moment it has emitted `resumed` or `load_requested`,
because a load rebuilds the world one frame later and a second press in that window would
answer a question already settled. The cost is that a load which comes back *refused* must
clear the latch — otherwise the menu sits there looking perfectly normal with every key dead,
and the only way out is killing the game. A mutant covers exactly that line, and it survived
the first time it was run: the test drove the refusal through the signal, which skips the
latch entirely. Driving it through real keypresses is what made the rule real.

## One game ships, and the picker went with the second one

The fork: the repo was called `sprite-generator` and shipped two games — a demo town and a
quest — with a picker to choose between them. The name described one feature of a project that
had become something else, and the second game had done its job.

- **Chosen: merge both worlds into one game, delete the picker, rename to `rpg-template`.**
  The demo's town and cave became the road into *The Barred Gate*, re-styled to `dusk16` with
  three new character specs; `data/games/demo.tres`, `GamePicker`, `GameMenu` and
  `GameSelect.should_ask/unresolved/switchable` are gone. What a visitor now meets is a game,
  not a menu asking which demo they would like.
- *Keep both games* — rejected: the second game was **proof**, not content, and it had already
  produced its findings (three template defects, plus the feel-parity correction). Kept, it is
  two worlds to maintain, two art sets to regenerate, and a first screen that asks a question
  nobody visiting a template wants to answer.
- *Keep the picker for a future second game* — `deferred — worth trying`: it is a real feature
  and it worked. It is deleted rather than left dormant because an unreachable screen rots
  quietly. **Revisit hook:** `GameSelect.choose()` still returns `""` for "more than one game
  and nothing chose", and `world_scene._ready()` is where a picker would consume that answer
  again — the seam it plugged into is intact, only the consumer is gone.

**What was given up, stated plainly.** The template's claim used to be checkable: *a second
game was added without touching `scripts/`, `tools/` or `scenes/`*, provable with
`git diff --stat`. That proof is now history rather than something CI re-runs. The seams it
tested are all still exercised — `GameHooks` by the warden, `GameManifest` by the boot,
`start_game`/`_teardown_game` by `restore()` and by `test_game_switch` — but nothing standing
in the repo re-proves the claim end to end. The honest replacement is the deferred item that
was always the stronger test: **a separate repo that consumes this one.**

### The road between the two worlds

The town and the village are joined by one door each, both anchored on a wall rather than on a
tile count: the village's is the south-east corner of its own east wall, the town's is the one
gap in its north wall. Every QA script that crosses them holds a direction into a wall and lets
the geometry stop it, so the scripts say "walk until something stops you" rather than "walk
4.5 tiles" — which is the difference between a fixture that survives a map edit and one that
does not.

The demo's NPCs needed `dusk16` art, and a character exists for exactly one style
(`CharacterSpec.style_id`). So `town_elder`, `town_kid` and `town_smith` are new specs with the
same seeds as their `gb16` originals — same parts, new palette, which is the style-swap the
generator exists to make free. `gb16` and `nes16` and their eight specs stay: they are what
`test_gates_consistency` compares styles across, and what Sprite Lab shows.

## Items are the template's business after all

The fork: the quest's key was a boolean flag, and `interaction.gd` said in as many words that
"items with names and counts… belong in a game's own hooks". Making the quest about *carrying*
things meant either building an inventory inside `games/quest/` or reversing that.

- **Chosen: items are a template noun.** `ItemDef` + a pure `Inventory`, `give_item`/`take_item`
  as effects, and `requires_item` beside `requires_flag` on objects, warps and dialog choices.
  The reversal is honest rather than reluctant: a key, a coin, a potion and a quest token are one
  mechanism wearing four names, and `docs/DECISIONS.md` had already written down the trigger for
  this — "the first game that needs a count rather than a boolean". Every game re-inventing the
  same dictionary-of-counts is exactly what the template exists to stop.
- *Keep it in the game's hooks* — rejected: it works, and the second game to want items writes it
  again, differently, with its own save-migration bug. The line the template still does not cross
  is prices, hit points and turn order — the moment a map file needs a type system, the template
  has started designing somebody's game.
- *A `kind` on an object plus game code* — rejected: it moves the vocabulary into a string the
  template cannot validate, so a typo becomes a silent no-op instead of a content error.

### No stack limit, and no "use" yet

A cap would let a pickup FAIL, and a chest marked `once` has already recorded being opened by the
time the give is applied — so a full bag eats the key and the door stays shut with nothing on
screen saying why. Unbounded counts cannot produce that; a game needing a cap enforces it in its
own hooks, where it can also say so. "Use" is `deferred — worth trying`: it needs a verb per item
and an effect vocabulary for what using does, which is a design decision no shipped item needs
yet. Revisit hook: `PauseMenu.confirm()` on the ITEMS page returns `NONE` where that answer goes.

### A take implies a requires

`Interaction.decide` and `DialogRunner._visible_choices` both refuse *before* appending any
effect when a `take_item` cannot be covered. Without that rule the take is emitted, fails at the
sink, and the `mark_seen` beside it still lands — a chest that is spent and gave nothing, which
looks like a lost item rather than a bug. It also makes an effect list all-or-nothing, so a
failure at the sink means a hook is wrong rather than a player being unlucky.

### Gifts live on choices, never on nodes

A dialog node has no condition and no memory of having been entered, so a conversation that loops
back through a gift node hands over a second key every pass. A choice can carry `set_flag X` and
`hidden_if_flag X` naming the same flag, which is "taken once, offered never again" — and
`_visible_choices` counts flags earned *earlier in this conversation*, because nothing has been
written to the game state until the box closes.

- *Node-level `give_item`* — rejected: it reads as the obvious place to put it and is a
  duplication bug waiting for the first looping conversation.
- *A `once` on a dialog node* — `deferred`: it is a second memory to persist and migrate, for a
  case the flag pair already covers.

### The dialog's second sink is gone

`_on_dialog_closed` used to write flags to `GameState` directly, which was fine while a
conversation could only earn flags. It now emits the same effect dictionaries a hook does and
goes through `_apply_effects` — one vocabulary, one place to look for "what does this actually
do", and one place that has to learn a new op.



## Hit points and turn order are the template's business after all — *M13*

`scripts/world/interaction.gd` has carried this sentence since M12: *"Prices, hit points and
turn order are still over the line - the moment a map file needs a type system, the template
has started designing somebody's game."* M12 wrote it while moving **items** across that same
line, on the grounds that "a count rather than a boolean" is the one noun every game
re-invents. M13 makes the identical argument one level up and moves hit points and turn order
too.

**The fork.** Where does a battle system live?

- **In the template, with all content as data** — `BattleLogic` beside `DialogRunner`,
  `EnemyDef`/`CombatDef` beside `ItemDef`, encounters as a map record. *Chosen.* Every RPG
  built on this thing would otherwise rewrite "a number that ticks down, a number that ticks
  up, and whose turn it is" — each with its own save-migration bug, its own idea of what a
  seeded damage roll is, and its own untested defeat path.
- **In `games/<id>/`, as that game's own code.** Rejected for the reason the second game
  would prove: it would re-invent HP from scratch, and the first thing it would get wrong is
  the save. This is the items argument verbatim.
- **A `kind: "enemy"` on an NPC record plus hook code.** Rejected: the template cannot
  validate a vocabulary it does not own. A misspelt enemy id would be an NPC that simply does
  nothing, where `enemy_refs()` makes it a build failure.

**Where the line is now.** Over it: *economy* (prices, shops, currency) and *battle
scripting* — what a particular boss does on turn three is a game's own business, and
`GameHooks` is where it goes. Under it: the numbers, the turn order, and the screen.

**What that bought, concretely.** "A beaten enemy stays beaten" is the same map-scoped `seen`
key an opened chest already used, so it persisted and migrated for free. A battle's results
go through `world_scene._apply_effects` like every other effect, so there is still exactly one
place where anything reaches live state.

**Retuned after play, M13.1.** The first timing values shipped without anyone playing the
game, and the user's verdict on the live build was one sentence: *"way too fast for human
reaction."* They were right, and the reason is structural rather than a matter of taste — the
`!` lights exactly WHEN the window opens (`cue_on()` is the same comparison the press is
judged by, deliberately, so the screen and the rule cannot drift), so the window is not a
margin around a beat the player already saw coming: it *is* the entire reaction budget. Eight
frames is 133ms against a human's ~250ms. The window went to 24 frames and the cues to 72/84
to keep the window a small fraction of the wind-up. Nothing about balance moved, because the
window is not in the damage arithmetic. The lesson generalises past this game: **when a cue
and its window open together, size the window for REACTING, not for precision** — and a feel
number that no test can judge needs a human before it ships, not after.

## Encounters are visible, presses are timed, and the fight was solo — *M13, written down M27*

`GENRE_CONVENTIONS.md` §7 has said "Recorded in `DECISIONS.md`" since M20 and it was not true.
The entry above records where a battle *lives*; nothing recorded what the battle *is*, which is
where this template departs from its references hardest. Written now because §7's own rule is
that a deliberate divergence without an entry behind it "is a gap wearing a nicer word", and
because M27 is about to change the third of the three.

**The fork was three separate ones, decided together in M13 and never argued in public.**

- **Visible enemy records versus random encounters on a step counter.** *Chosen: visible.*
  Every reference game rolls encounters against a step count. Doing that here would put a
  random draw inside the movement loop, and the determinism story — same seed, same
  everything — is what makes sixteen scripted play sessions a *gate* rather than a demo. A
  fight that must happen is then made unavoidable by **geometry** (a one-tile gap the player
  cannot walk around), never by a probability. Visible enemies also make a template's demo
  game legible: you can see what the map is going to ask of you. Rejected alternative: a
  seeded step counter, which would be reproducible but would still make "did the fight
  happen" a function of the route rather than of the level design.
- **A timed press versus a menu that resolves on its own.** *Chosen: timed.* A cue lights and
  a press inside its window doubles the blow or halves the incoming one. This is the one part
  of the fight that is not in any reference game — it is closer to Super Mario RPG's action
  commands than to FF1 — and it exists so the template ships a battle with a verb in it rather
  than a screen that watches numbers subtract. The cost was paid publicly in M13.1: the first
  window was 133ms and the first person to play it said no human could hit it, which is the
  entry above. Rejected: pure menu combat, which is more faithful and gives a player nothing
  to do with their hands.
- **One character versus a party.** *Chosen at the time: one* — and this is the one that was
  never really decided, only deferred by silence. Dragon Quest I is solo end to end, so solo
  is a shipped genre shape and not an absence; but every other reference game has a party, and
  the template's own audit called it the largest missing system for four milestones. **M27
  closes it**, which is why this entry exists: a divergence nobody wrote down cannot be
  revisited, because there is nothing to reopen.

**What stays diverged after M27.** The first two. Multi-enemy fights stay out of scope, so a
party arrives with an **ally** cursor and no enemy one — and the reason is the same one that
kept the cursor out in M25: a mode with one option in it is not a choice.

**M28 closes the solo half too**, and the reason to record it here rather than only below is
that this entry is where a reader comes to ask what the fight diverges on. After M28 the
answer is two things, not three: encounters are still **visible** and presses are still
**timed**. The number of foes is no longer one of them.

## A view that renders data declares its capacity, and the build enforces it — *M13.3*

A screenshot of the live build showed the warden's opening with a choice drawn on top of the
second line of her text. Measuring every shipped line found worse: the text area was 22px
against a 12px line, so only ONE line ever really fit, and four nodes were being silently
truncated - three of them the signposting lines added the day before to tell the player where
to go. Nine scripted play sessions pressed through those conversations on every CI run and
could not see any of it, because headless QA never renders a pixel.

**The fork.** How does a fixed 320x180 box cope with data of unbounded length?

- **Reserved bands + a build-time budget** *(chosen)*. Text gets a fixed two-line band,
  choices get their own band below it, the box grows only while a choice is up - and
  `test_dialog_fit.gd` measures every shipped line with the real font against constants owned
  by `DialogBox`, failing the build on an overflow and naming the node. Text too long for the
  box becomes another node on a `next` chain, which is this format's own pagination and paces
  the typewriter better anyway.
- *Runtime pagination* — `deferred — worth trying`: overflowing text continues on the next
  press, so any data ever written renders. Rejected for now because it duplicates what node
  chaining already does and makes an unbroken paragraph legal to write, which is a worse thing
  to have in the content than a build failure. Revisit hook: `DialogBox._show_line`, the day a
  game on this template needs prose it cannot break up.
- *A taller box* — rejected. It moves the cliff without telling anyone where the new one is,
  and the worst-case line is unbounded.
- *A smaller font* — rejected outright: 8px is already the readability floor at this
  resolution.

**The general rule.** A view that renders DATA has a capacity, and that capacity is part of
the content contract rather than an implementation detail of the view. State it in constants
the gate reads too - two copies is how the check and the thing checked drift apart - and
enforce it at build time, because the failure mode of "too big to draw" is usually silence.

## No fact a player needs may be single-sourced in optional dialog — *M13.2*

A play-test of the live build ended with the tester holding a flask of lamp oil, told about a
key they never found, and asking how the quest was supposed to be played. Nothing was broken.
Every gate was green. The data was built that way.

**What the audit found.** Classifying each of the eleven facts a player needs by how reachable
its statements are — FORCED (unavoidable on the critical path), LIKELY (a refusal fired by an
obvious attempt), OPTIONAL (needs pressing something skippable) — turned an argument about
taste into a list of defects:

- Two facts were stated **nowhere**: that the key is under the hollow's one bush, and that the
  ending is walking back to the warden.
- "The key is in the hollow, west" was OPTIONAL and **single-sourced** in the warden's dialog,
  and she is a static figure two tiles off the spawn with nothing to make you press her.
- Every statement of what the oil is FOR sat **downstream of the key** — one line requires
  carrying it, the other requires being inside the keep — while the oil itself was obtainable
  in the first minute, ungated. Getting oil first is a legal, natural, unpunished order that
  produces an item the game will not explain until you have solved the other half.
- The line carrying four facts at once (lantern dry / oil exists / hermit has it / cave east
  of town) was **destroyed by progress**: the hook's priority puts `was_seen(keeper)` above
  `has_item(key)` forever, so beating the Keeper first deleted it from that save permanently.
- Both refusals were dead ends. `gate_barred` never said "key"; `lantern_dry` never said "oil".

**The rule now.** No fact a player needs may be single-sourced in optional dialog. Every
refusal names what it wants and points somewhere. An item obtainable before its purpose is
statable carries its purpose at pickup. And a conditional line that can be permanently
outranked must have its facts repeated by the line that outranks it.

**The fork: how does the premise reach the player?** Chosen — **the opening conversation is
forced** (`GameHooks.on_map_entered`, guarded by a flag the dialog's own first node sets). A
quest whose premise is optional is one most players never learn they are on, and the genre has
opened this way since the eighties. What falls out for free from state that already exists: a
load does not replay it (`restore()` is state first, then `enter_map`), and Start Again after
a defeat does — which is right, because that is a new run of the story.

*Rejected — gating the hermit's oil on quest knowledge* (`requires_flag`, so the choice is
hidden until you know the lantern is dry). It enforces the intended order and would have made
the tester's confusion impossible, but at the cost of sending them back across two maps for a
flask they had already been shown. Making the world explain itself beats making the world
withhold. Revisit hook: the choice list in `data/dialog/hermit.json`.

*Rejected — reordering the hook so `has_item(key)` outranks `was_seen(keeper)`.* It would have
saved the lost line, but the priority order is correct as a matter of story — the warden should
react to the Keeper being gone before she reacts to a key. Fixed by redundancy instead: the
outranking line now carries the outranked one's facts.

## Game over is an overlay, and TITLE still means nothing — *M13*

Losing had to go somewhere. The user asked for "game over → title".

- **A `GAME_OVER` overlay offering Continue and Start again.** *Chosen.* It reuses the slot
  machinery the pause menu already had, and boot stays world-first — which the play scripts
  and every integration suite assume. (**Superseded in M22**: boot is title-first now, and the
  overlay gained the Title row this entry's own screen comment promised. Every scripted session
  pays one press for it, deliberately.)
- **Reusing `Router.State.TITLE`.** Rejected. TITLE has meant "nothing to drive yet" since
  M2, and it is the state the router boots in; making it also mean "the run ended" would give
  one honest state two meanings, and `state_name()` feeds QA assertions directly.
- **Building a real title scene.** Deferred, not rejected — see the backlog. It is a
  milestone of its own (a new scene, a boot path that does not go straight into a map, and a
  New Game flow that is more than `start_game` re-entry), and doing it badly to host a
  game-over screen would be the tail wagging the dog.

The honest caveat, recorded because it will be asked: this is not a title screen, and the
game still cannot be quit to anything. It is the minimum that makes losing mean something —
your save matters, and a fresh run is genuinely fresh.

## Sound is generated, the way art is — *M14*

The template had a whole audio seam and no audio: `AudioBus` resolving ids, a
`sound_requested` signal, a `GameContext.play()`, an `OP_SOUND` effect — and zero files, zero
callers, and a game that has been silent since M0. `data/audio/README.md` argued that was
correct: *"a placeholder beep committed to a template is a placeholder beep shipped in
somebody's game."*

That is the objection the ART side already answered, and answered better. The template does
not ship an art pack; it ships a generator driven by a style resource. Sound gets the same
answer, so nobody inherits anybody's beep.

- **A synthesiser driven by a voice resource.** *Chosen.* `data/banks/*.json` says what a cue
  is shaped like, `data/sounds/*.tres` says what it is played on, and three voices share one
  bank exactly as three sprite styles share one rig.
- **Shipping recorded sound effects.** Rejected on the grounds the art side already
  established for LPC art: licensing that follows the template into somebody's game, and one
  fixed aesthetic baked into a thing whose whole claim is that the aesthetic is swappable.
- **Keeping the seam empty and letting each game bring audio.** Rejected — that is the status
  quo, and the status quo is a subsystem no gate has ever exercised. A seam with no payload is
  not a feature, it is an untested code path with documentation.

*Deferred — music.* The user chose effects only for M14. A tune is content a designer writes,
not something a generator should compose, so the shape when it comes is a note sequence in
`data/music/*.json` performed by this same synthesiser. Revisit hook: `AudioBus.play_music`,
which already exists and has never been called.

## A cue names a shape; a voice names a sound — *M14*

Whether the two-file split was real, or ceremony copied from the art pipeline.

- **Bank plus voice.** *Chosen*, on the test of whether the two files fail differently: "the
  footstep is too long" edits the bank, "the whole game is too harsh" edits the voice. Both
  are real edits, so both files are honest. The proof it is not decorative is
  `test_two_voices_over_one_bank_do_not_sound_the_same`, plus three shipped voices — `gb16`
  square and bit-crushed, `nes16` square and brighter, `dusk16` a triangle pitched down for
  the quest's late-evening look — that re-author not one cue between them.
- **One resource holding both.** Rejected: it would make every re-voicing a full re-authoring,
  which is precisely the cost the art side pays nothing for.

## The cue vocabulary is an enum, not a lint rule — *M14*

`AudioBus` warns once on an id it does not have and carries on. That is right, and it is also
exactly how a misspelled cue ships: nobody notices a noise that was never there.

- **An enum in `Sfx`, with an id table keyed by it.** *Chosen.* Template code names a cue as
  `Sfx.Cue.HIT`, so a typo is a compile error — the strongest guarantee GDScript offers, and
  strictly better than catching it later.
- **A lint rule banning raw cue strings**, mirroring `RULE_DIRECTION`. Rejected: it cannot
  tell a cue string from any other string, so it would need domain-prefixed ids invented to
  keep it from firing on `"warp"`, `"victory"` and `"defeat"`, which are already in use as
  effect keys and spawn names. An enum needs no prefix and no exemption list.
- **Leaving it as strings and trusting the warning.** Rejected on the failure mode: the
  warning fires at the moment the sound should have played, in a log nobody is reading,
  in a build already shipped.

Content still names sounds as text, because content is data — `Sfx.of()` is what validates it,
beside every other id, at load.

## The generator calls no transcendental function — *M14*

The drift gate compares committed samples against freshly generated ones, on a Mac here and on
an Ubuntu runner in CI.

- **Square, triangle and saw from an integer phase accumulator; linear envelopes; noise from
  `SeededRng` integers.** *Chosen.* IEEE-754 pins `+ - * /` to identical results on every
  platform, so the generator is deterministic **by construction** rather than by luck.
- **`sin`, `pow`, `exp` for smoother waveforms and curves.** Rejected. Those come from the
  platform's libm and are not guaranteed bit-identical between architectures; one ULP anywhere
  makes the committed WAV differ and turns the drift gate red in CI for a reason nobody can
  reproduce locally — and a gate that flaps is a gate that gets switched off. The constraint
  costs nothing: a chip voice has no sine in it either.

## The importer is part of the pipeline, so the gate checks it — *M14*

Godot's WAV importer defaults to `compress/mode=2`, which is QOA — **lossy**. Left alone, the
drift gate would compare lossless samples while every player heard something else, and no
surface anyone looks at would say so.

- **Pin the defaults in `project.godot` `[importer_defaults]`, and have the gate compare the
  IMPORTED stream as well as the committed file.** *Chosen.* Both halves are needed: the pin
  makes new cues correct automatically, and the comparison is what would catch the pin being
  removed.
- **Setting `compress/mode` in each generated `.wav.import`.** Rejected as a list maintained
  by hand — the next cue added comes back with whatever the default is, which is the failure
  this project has hit twice with skip lists.
- **Comparing raw file bytes instead of decoded samples.** Rejected for the reason the art
  gate compares pixels rather than PNG bytes: a container header is not ours to author, and a
  gate that fails on a file which sounds identical is a gate people learn to ignore.

## A game's own file beats the generated cue — *M14*

Two roots can answer a sound id, and the order between them is the seam.

- **`data/audio` wins over the generated cue.** *Chosen.* A game replaces one sound by dropping
  one file in, and never has to delete build output to do it — which matters because the drift
  gate would put that output straight back on the next run. It is the `GameHooks` rule one
  level down: a game is additive, or it is not using this seam.
- **Generated wins, overrides as a fallback.** Rejected: it makes the generator authoritative
  over the game, which is backwards for a template whose whole claim is that a game brings its
  own look and sound.
- **One root only** (generate into `data/audio`). Rejected: `data/` is content a human authors
  and `assets/generated/` is output a gate overwrites. Merging them would mean the drift gate
  competing with a designer over the same directory.

An override is printed once at boot, and two files answering to one name is an **error** — the
loser is invisible and which one loses depends on the filesystem, which is the same reason
`Registry` refuses duplicate content ids rather than letting the last one win.

## A view asks for a sound; it never plays one — *M14*

Where the call to the speaker lives.

- **Every screen emits `sound_wanted(id)`, and `world_scene` is the one place that plays it.**
  *Chosen*, and not on purity grounds alone — it is the `_apply_effects` shape applied to
  audio, and the alternative turned out to break a gate.
- **Views calling the audio singleton directly.** Tried first, and rejected on evidence:
  `check.sh`'s per-file parse gate skips any file whose TEXT names an autoload, so a view that
  called it dropped ITSELF and every suite depending on it out of that gate. Two dialog suites
  stopped parsing the moment `DialogBox` learned to make a noise. A comment naming the
  singleton is enough to do the same thing, which is stated in `CLAUDE.md` beside the signal.
- **A pure class playing its own cues.** Not available: `BattleLogic` may not touch an
  autoload at all. It collects instead, and the view drains — which turned out to be necessary
  rather than merely tidy, because a fight's cues have to survive a DEFEAT, whose effects the
  world discards entirely. A defeat sting riding on the effect list would be silent at exactly
  the moment the player most needs telling.

## Footsteps are measured, not timed — *M14*

- **One `StepMeter` counting distance actually moved, for both movement modes.** *Chosen.* It
  slows when the player slows and stops when a wall stops them, which is what a footstep is.
  One accumulator rather than two keeps the invariant that nothing downstream can tell free
  movement from grid movement.
- **Firing on grid-step completion.** Rejected: it would need a second implementation for free
  movement, and the two would drift the first time either was touched.
- **A timer.** Rejected on the failure mode - a player walking into a wall would keep making
  footstep noises while standing perfectly still.

The honest cost of one accumulator: a diagonal grid step covers 22.6px rather than 16, so its
footfall lands part-way through the step. That is what walking sounds like anyway.

## A setting is not a save — *M14*

Where the player's volume lives.

- **Its own file, `user://settings.json`, outside every slot.** *Chosen.* A save is one run of
  one game; a setting belongs to the person at the keyboard and has to survive starting over,
  switching game and deleting every slot.
- **A field on `SaveData`.** Rejected: it would need a migration, it would be per-slot, and
  loading an old save would reset the volume — which is not a thing a load should do.
- **Not persisting at all (session-only).** Rejected on the deployed demo: every reload of the
  page would come back loud.

No version field, deliberately. There is one field; a value the enum does not contain falls
back to the default with a warning, and the next write repairs the file. A migration chain for
that would be ceremony, and `supported_versions()` would be describing a format that never
changed.

## Four named steps, cycled by confirm — *M14*

- **Off / Quiet / Normal / Loud, advanced by the confirm button.** *Chosen.* The pause menu has
  up, down and confirm; up and down move the cursor, so confirm is the only button left. Four
  steps is also what a menu row can say in one word.
- **A slider on left/right.** Rejected for now: it needs an input axis the menu does not use for
  anything else, and a continuous value has no name to draw on the row.
- **A plain on/off toggle.** Rejected: the honest complaint about game audio is rarely "silence
  it", it is "quieter than that".

The gains are not evenly spaced (0, 0.25, 0.6, 1.0) because hearing is roughly logarithmic and
even spacing sounds like three loud settings and one quiet one.

## The gate got 17x faster without losing an assertion — *M14.1*

Four milestones of M14 cost ~17 minutes of CI each, and the profile said the time was not in
the tests: 604 tests execute in 34 seconds. It was in engine boots and in the wall clock.

- **`--fixed-fps 60` on everything driven by frames.** *Chosen.* Headless Godot still paces its
  main loop against real time, so a play session that takes a player three minutes took the
  gate three minutes. Measured, both ways, before anything was built on it: play sessions
  371s → 8s with byte-identical logs, suite 37s → 8s with identical verdicts on all 595 tests,
  and **226/226 mutants still killed** — which is the real proof it did not blunt detection.
- **Rewriting the QA scripts to wait fewer frames.** Rejected outright: the frame counts ARE
  the test. A battle asserted on frame N is asserting the timing window exists.
- **Dropping the slowest two play sessions from CI.** Rejected: they are the two that play the
  whole quest and lose a fight, i.e. the only ones that cover the game end to end.

## A pull request proves what it could have broken; main proves everything — *M14.1*

The full 226-mutant sweep was 57% of every CI run, on both the PR and the merge.

- **Scoped on PR, full on main.** *Chosen by the user.* A change can only make decorative a
  mutant whose file or suite it touched, so that is what a PR runs — seconds instead of ten
  minutes. Every merge re-runs the whole sweep, where nobody waits on it, so a test that went
  decorative because of a change somewhere else is caught one step later rather than never.
- **Full sweep on every PR, sharded across parallel jobs.** Rejected for cost: identical rigor
  before merge, ~4x the runner minutes, for a window that main closes minutes later anyway.
- **Main only, nothing on PR.** Rejected: it gives up the one thing scoping is good at, which
  is catching the author's own change making the author's own test decorative.

What deliberately did NOT move: `mutants_aim.sh` runs over the whole file on every run of
both. It costs under a second and it is the check that catches new code stealing an old
mutant's aim — which has happened twice.

## The artifact is played, not enumerated — *M15*

Nothing in this project had ever looked at the `.pck` a player downloads. Two ways to fix that.

- **Boot the pack and play it** with the committed QA sessions, via `--main-pack`. *Chosen.* It
  subsumes any file list: a packed game that boots, walks, warps, talks, fights and asks for its
  sounds has demonstrably packed the maps, tiles, sheets, dialog, manifests and cues. It also
  needs no export templates and reuses a harness that already exists.
- **Enumerate the pack** — mount it with `ProjectSettings.load_resource_pack` and diff the walk
  against `ContentScan` over the source tree. Rejected as the primary gate because it proves
  presence, not playability, and presence is the weaker claim. Still worth doing one day for a
  different reason: it would finally test `ContentScan`'s docstring claim that "the same walk
  works from a .pck", which nothing exercises.
- **Grepping the raw pck for known paths.** Rejected: the packed name is `hit.wav.import`, not
  `hit.wav`, so the obvious grep proves the sidecar shipped and says nothing about the audio.

**Where it runs:** in `check.sh`, on every run, because it turned out to cost five seconds rather
than the thirty assumed while planning. That was measured before deciding. It ALSO runs in
`pages.yml` against the real deployed package, where `deploy needs: build` means a package that
does not play leaves the live page on the last good build.

## An assertion where the value is always full is decoration — *M15*

`finish_the_quest` and `fall_at_the_keep` between them make 99 assertions and five and a half
minutes of scripted play, and neither noticed `BattleLogic.damage()` returning three more than it
should.

The reason is exact: **every mid-run `assert_hp` in both scripts sits immediately after a
level-up, and a level-up is a full heal.** Damage taken is overwritten before it is ever read.
`assert_level` cannot help - xp is a per-enemy constant, so it is the same whether a fight took
two rounds or four - and `finish_the_quest` made zero `assert_xp` calls at all.

- **One `assert_hp` after a fight that does NOT level the player.** *Chosen.* That is the only
  window in either script where hp is neither full-at-start nor refilled. Both directions of the
  arithmetic are now caught (`+3` and `-1` both land on 13 against a pinned 14).
- **Recomputing the expected hp from the combat numbers.** Rejected: a test that derives its
  expectation from the thing under test cannot see that thing change. The value was read out of
  the run's own log.
- **More assertions everywhere.** Rejected as the fix. The file already *looked* like it asserted
  hp three times; the problem was never the count.

`mutate_check.sh` now drives a play session as a "suite" when the suite column points at
`tests/fixtures/qa/`, so the play gate is mutation-proven like everything else. That only became
reasonable when M14.1 made a session cost two seconds instead of ninety.

## Equipment is a screen of its own, and the flow is slot-first — *M20*

**The fork:** where does the verb "wear this" live, now that M19's answer has been played?

- **A page of its own, entered from a top-level `Equipment` row, slot-first** — *chosen.*
  A slot list showing what is in each slot, each opening the gear that fits it. Two reasons,
  and the first outranks the second: the person who asked for equipment played M19 and said
  it should be its own screen like Items; and every reference game agrees — FF I–VI, Chrono
  Trigger and the DQ SNES remakes all put Equip beside Item and none of them equip from the
  item list. "What am I wearing" becomes a glance rather than a scan of the whole bag.
- **The M19 bag toggle** — *rejected, and removed.* Confirming gear in the bag toggled
  Wear/Take-off. It was fully tested and fully green, which is exactly why it is worth
  recording: no gate can see a screen that is in the wrong place. Its good parts were kept —
  the `(E)` marker stays in the bag, and the stat preview moved to the candidate list.
- **Keeping both** (equip from either surface, the Dragon Quest III shape) — *rejected.* Two
  surfaces owning one verb drift: the bag's toggle and the picker's take-off row would have
  to agree forever about what a confirm means, and the wording already differs ("Take off"
  vs a row that removes). One verb, one owner.
- **Item-first** (pick gear, then be told where it goes) — *rejected.* It reads as an
  inventory with extra steps, and it cannot show an empty slot, which is the thing a player
  most needs to see.
- **Optimize / best-equip** — *deferred — worth trying.* An FF convenience for games with
  five slots and forty items; at two slots it is a button that does what one press already
  does. **Revisit hook:** `ItemDef.SLOTS` growing past three.

**Where a third slot plugs in:** `ItemDef.SLOTS` is the one list. Adding `&"trinket"` to it
grows the equipment page a row, teaches `problems()` the new word, and needs no screen edit.

## The stats readout is worded by the world, not composed by the menu — *M20*

**The fork:** the equip screen shows "Atk 5+3 Def 1+0". Who builds that string?

- **The world builds it and hands the menu text** — *chosen.* Naming a stat is a question
  about what a game calls things, and `PauseMenu` may not touch the Registry or a manifest.
  It is the `_gold` and `_sound` precedent exactly: a readout arrives as text.
- **The menu composes it from numbers it is handed** — *rejected.* It would need to know that
  "Atk" is what this game calls attack, and that a game with no `CombatDef` has neither.
- **The view reads the world directly** — *rejected outright.* A view that names an autoload
  drops itself, and every suite that depends on it, out of `check.sh`'s per-file parse gate.

## The status page is a readout the world words, not a screen that computes — *M20*

**The fork:** the genre's fourth standard command. Who builds "Level 3 / HP 28/28 / XP 35"?

- **The world builds the lines and hands the menu an array of strings** — *chosen.* Identical
  to the `_gold`, `_sound` and `_stats` precedents, and for the same reason: knowing that this
  game calls it a "Level", and whether it has one at all, means reading a manifest, which a
  pure `PauseMenu` may not do. It also makes the degenerate cases free — a game with no
  `CombatDef` simply produces fewer lines, rather than the page needing to know what a
  combat-less game looks like.
- **The menu composes from numbers** — *rejected.* It would need the vocabulary and the
  `CombatDef`, and every game that names things differently would need a menu change.
- **A structured `StatusRow` type** (label + value, so the view can column-align them) —
  *deferred — worth trying.* It buys right-aligned values like the shop's price column. Not
  taken now because the lines are short and one array of strings is the smallest thing that
  works. **Revisit hook:** `_status_lines()` — change its return type and the view's
  `_label_for` branch.
- **Making the page interactive** (confirm on a row to do something) — *rejected.* A status
  screen that acts is a different screen. `confirm()` answers NONE and the view draws no
  cursor at all, so the page cannot imply a verb it does not have.

**On the ordering cost:** inserting Equipment and then Status moved the two deliberately-counted
navigations (the `_to_the_third_slot` helper and `save_and_load.json`) twice in one milestone.
That is the price of putting rows where the genre puts them, and it is the right price: a row's
position is what a player navigates by muscle memory, and the counted tests write their counts
out longhand precisely so that this moves deliberately rather than silently.

## Money leaves through a conversation, and a rest is a full heal — *M21*

**The fork:** the genre's inn needs to charge gold and restore HP. Neither could happen from
data before this: `OP_GOLD` only ever gave, and the only writer of `player_hp` outside a fight
was `OP_PARTY`, which demands xp and level too.

- **Two effect verbs on a dialog choice — `spend_gold` and `rest`** — *chosen.* An inn is a
  **conversation**, not a counter (see `GENRE_CONVENTIONS.md` §10 — DQ and FF innkeepers greet,
  name a price, ask yes/no and fade to night; there is nothing to browse), so it is built out
  of the grammar every other conversation uses rather than out of the shop's trio.
- **An `InnDef` + `InnMenu` + `InnScreen`, mirroring the shop** — *rejected.* It would be a
  counter with one item on it. The shop's shape earns its keep because a shop has a list, a
  price column, quantities and two pages; an inn has a yes and a no.
- **A parameterised `heal(amount)`** — *deferred — worth trying.* It would cover a field-use
  verb for potions, which §4 records as deliberately absent, and "restore to full" is the only
  amount the genre's inn ever uses. **Revisit hook:** `GameContext.OP_REST` and the `_rest()`
  handler in `world_scene` — an amount would ride the effect dict.
- **Hiding the choice when the purse is short**, the way `requires_item` hides — *rejected.*
  A hidden room is a price the player can never discover. The shop already settled this: its
  `poor_line` exists because a refusal that makes no words reads as a dead key. So a spend
  requires a `poor_next`, and the build refuses a keeper who charges and says nothing.
- **Saving at the inn**, which the genre pairs with resting — *rejected.* This template
  deliberately diverges on saves (pause menu, anywhere — recorded above and in §8), and an
  inn save would quietly relitigate that decision as a side effect of a healing feature.

## The inn is a room you walk into, and the night is a screen — *M21*

**The fork:** where does the inn live, and what does resting look like?

- **A room, entered through a door in the town** — *chosen*, by the user, against the cheaper
  option. An inn in the genre is a **place**; the template's only previous keeper (the smith)
  stands in the square, and a second keeper in the same square would have been an innkeeper
  rather than an inn. It is also the game's first interior, and the first map to use the
  `floor` / `wall_rough` / `door` / `table` / `rug` tiles, which the bank has carried since M16
  with nothing using them.
- **An innkeeper standing in the town square** — *rejected*: one NPC record and one dialog
  file, no map change, no risk to the shipped sessions. Cheap, and not an inn.
- **Where the building went was MEASURED, not chosen.** A building makes tiles solid, and a
  solid tile under an existing leg breaks sessions that have nothing to do with inns. The M17
  method: print on the tile-change hook, run all twelve sessions, overlay every tile the gate
  actually walks. The footprint sits in the top-left quadrant, which nothing walked.
- **`RestScreen`, a fade held for a beat** — *chosen.* Every reference inn spends a moment in
  the dark before the "good morning".
- **No screen at all — heal and print a line** — *rejected*: it is the M18 shop mistake in
  miniature, shipping the mechanic without the surface the genre gives it.
- **A general `FadeScreen`** — *deferred — worth trying.* There is one caller. **Revisit hook:**
  `RestScreen.setup()` already takes its text as an argument, so the second caller is what
  turns it into a fade. A warp transition is the obvious one.
- **Four gold a night** — chosen as exactly one slink's drop, so an ambient fight pays for the
  night it costs you. A feel number; unjudged until played.

## A game is started FROM a screen, and that screen is an overlay — *M22*

**The fork:** `Router.State.TITLE` has been the router's boot state and meant "nothing to drive
yet" since M2. Giving it a meaning needed a screen, and a screen needed a boot path.

- **A `TitleScreen` overlay over an empty world** — *chosen.* `world_scene._ready()` resolves
  which game is running and then *stops*, where for twenty milestones it started one.
- **`scenes/title/title.tscn` as the main scene** — *rejected*, and the reason is `GameSelect`:
  four surfaces have to answer "which game is this" identically, and `_ready()` is the one
  place `resolve()` is called. A title scene with its own boot would be a fifth answer, which
  is the exact failure that design exists to prevent. New Game would also become a *second
  mechanism* for a verb `start_game` re-entry already implements, and every integration suite
  boots `world.tscn` — with the overlay, none of them changed.
- **A shared `SlotMenu` base for the title and the game over** — *chosen.* They differ in the
  wording of two rows and nothing else. Two copies of "nothing saved is nothing to continue
  from" is one screen that eventually offers a list of nothing. GDScript will not let a
  subclass redeclare an inherited enum, so the game over's extra row is a named constant one
  past the shared ones rather than a second `Row`.
- **The cursor opening on a row a press will DO something with** — *chosen for the title, and
  deliberately rejected for the game over.* At a title a dud first press is pure friction. At a
  game over the player has just lost and is already pressing, so opening on "Start again" turns
  one more press into a restarted run. The scripted session that mashes its way to a game over
  found this within a minute of the change: it restarted the game and then failed looking for a
  screen that was no longer there.
- **A Quit row** — *rejected*, still. A game that wants one ships it; the template has nothing
  to quit *to*, and on the web there is nothing to quit at all.

## The router announces every real change, and nothing else — *M23*

**The fork:** building a flow model meant deciding what the model would be checked against.
`EventBus.flow_changed` is the obvious instrument, and mapping all fourteen Router call sites
found it could not be trusted yet.

- **Route `reset()` and `to_title()` through `set_state`** — *chosen.* `reset()` assigned
  `_state` directly, so it never emitted. Since `enter_map` resets on every map entry, **every
  boot, warp, load and restore changed the state silently** — and the edge that hid there was
  TITLE → WORLD, which is how a game starts. `to_title()` was worse than silent: it called
  `reset()` first, so it always reported `{from: WORLD}` whatever the truth.
- **Model the silence instead, marking those edges `"silent": true`** — *rejected.* A model
  that faithfully encodes a lying signal is worse than no model: it makes the lie permanent and
  teaches every future reader that flow events are unreliable.
- **Emit unconditionally from `reset()`** — *rejected.* A warp resets WORLD to WORLD on every
  doorway, and a listener woken by every doorway is a listener nobody can use. `set_state`'s
  existing no-op guard already answers this, which is why the fix is to route through it rather
  than to add a second emit.
- **One `_to_base(base)` rather than a stack-clear in each** — chosen for a mechanical reason as
  much as a tidiness one: two literal `_stack.clear()` lines in that file make the mutant aimed
  at the first one ambiguous. The old comment said the dishonest shape existed *because* of
  that constraint; the helper satisfies both.

**A claim that did not survive measurement, recorded so it is not re-derived.** `_teardown_game`
nulls two screens inside their `is_instance_valid` guard and six outside it, which reads like a
dangling-reference bug: a screen freed elsewhere would keep a reference every `!= null` guard
passes, and `open_title`'s first guard is exactly that. It is not a bug — **a freed reference
compares equal to null in this engine**, measured and now pinned in
`test_engine_assumptions.gd`. The nulls were made consistent anyway; the test that "proved" the
bug passed with the code sabotaged, which is what exposed the wrong premise.

## The flow is a model the agent keeps, not a diagram a human reads — *M23*

**The fork:** after Continue-from-title replayed the game's opening, the question was what
stops the next bug of that class — a legal transition sequence nobody thought about.

- **The flow as machine-readable data plus a conformance gate** — *chosen, by the user*, who
  framed it exactly right: "godot-statecharts, but for you". The model is written for the agent
  to consult and update; `docs/FLOW.md` is a byproduct, generated and drift-gated, never a
  source. Knowledge that was re-derived every session becomes an artifact, and the gate is what
  stops it rotting into a comment.
- **[GraphWalker](https://graphwalker.github.io/) / [AltWalker](https://github.com/altwalker/altwalker)**
  — *rejected, with the research kept.* They are the reference model-based-testing tools:
  graph models, `random(edge_coverage(100))` generators, JavaScript guards, offline path
  generation. Adopting either puts Java (and for AltWalker, Python) into a gate that currently
  needs only the engine. The finding that settled it: **in every option the expensive part is
  identical** — the per-edge adapters and per-vertex invariants — and path generation over 8
  states and 17 edges is the trivial part. Their engines earn their keep at hundreds of nodes.
  **Revisit hook:** `tools/flow_model.json`'s edge list; if it ever outgrows a page, its
  generators are what to borrow.
- ~~**[Hypothesis](https://hypothesis.readthedocs.io/en/latest/stateful.html)-style stateful
  testing**~~ — was *deferred — worth trying* for one feature nothing else has: **shrinking**,
  which minimizes a failing 40-step sequence to the shortest one that still fails. **Taken up by
  M31**, at the seeded-walk layer this entry named as the hook. Not by adopting Hypothesis — it
  is Python and this gate needs only the engine — but by writing the search: cycle elision over a
  list of edge indices, pure and unit-tested with no scene. The entry above it holds why.
- **[godot-statecharts](https://github.com/derkork/godot-statecharts)** — *rejected.* It is a
  runtime library with a visual debugger: it would restructure how `Router` runs, generate no
  checks, and would not have caught this bug. This repo also has scar tissue from editor addons
  (the MCP one strips every comment out of `project.godot`).

**Why the model records traces and not just destinations.** The bug was not an action landing
in the wrong state — Continue *did* reach WORLD. It passed through the start map on the way,
and the entry hooks fired. So an edge declares the exact sequence of events it may emit, and an
undeclared intermediate hop is the failure. Two edges legitimately have two hops, and writing
them down is half the value of the file.

## A tune is written down and performed, not composed — *M24*

**The fork:** `AudioBus.play_music` had existed since M14 and had never been called. What
should it play?

- **Authored note sequences performed by the existing synthesiser** — *chosen*, and it was
  named as the shape back in M14: a tune is content a designer writes, and generating melodies
  is a different project with a much worse failure mode. The payoff is the same one the sprite
  rig has — one tune, three voices, and switching a style re-voices the music for free.
- **Generated (procedural) composition** — *rejected.* The template can promise a tune sounds
  like the machine it is playing on; it cannot promise a generated melody is any good, and
  nothing in a gate could tell us.
- **Committing the rendered WAVs, like every other generated asset** — *chosen*, against
  rendering at runtime. Runtime costs nothing on disk and would hitch: 176,400 samples × three
  voices through a GDScript loop, on the main thread, on a web export that has no threads
  because Pages serves no cross-origin-isolation headers. Committing also gives `pack_check.sh`
  something to bite on, which is exactly the M14 defect (the audio seam's drop-in half was
  broken in exports from the day it was written).
- **The cost, stated rather than discovered:** 43 KB per second, per voice, three voices
  committed. The theme is 8 seconds and takes the generated tree from 972 KB to 2.0 MB.
  `MusicTrack.MAX_SECONDS` makes that a validator rather than a good intention, because every
  addition would be individually reasonable.
- **One track, played by the title AND the settled maps** — chosen over a second track for a
  town theme. A title theme that is also the overworld theme is the genre's own habit, and it
  demonstrates all three rules (it plays, it does not restart between town and village, it
  stops on entering a dungeon) without a second megabyte. A battle theme is now data.

**Two things measurement changed.** The no-restart guard first read
`if id == _music_id and _music.playing:` — and headless runs on a dummy driver where nothing
ever reports itself as playing, so the guard could not fire in the one environment every gate
runs in. It now answers from what the bus believes, which is also what makes it testable. And
the rule needed an observable that was neither the request log (the request happens either way)
nor the device: `music_starts()` counts actual starts, and a mutant proved the earlier version
was unkillable.

## Docs-only changes skip the gate, and a stand-in answers the required check — *M24.1*

**The fork:** the user watched a comment-only change run two nine-minute gates. A docs change
can break nothing the gate tests, but `check` is a REQUIRED status - path-ignore it naively and
every docs pull request waits forever on a check that never comes.

- **A same-named no-op workflow on the inverse paths** — *chosen.* GitHub's own documented
  pattern for a skipped-but-required check: `check-docs.yml` carries the same workflow and job
  name, so the ruleset cannot tell the difference, and a docs PR merges in seconds.
- **Accept the cost** — *rejected this time.* It was the right call when the question was the
  two-runs-per-merge shape (that one is load-bearing); this one is pure waste, ~18 minutes of
  runner time per wrap-up commit.
- **Dropping the required check** — *rejected without much ceremony*: it is the merge gate.
- **The rule that makes it safe rather than clever:** the two path lists are ONE rule in two
  files, so `test_ci_paths.gd` asserts they are exact inverses - and the exceptions are
  DERIVED, not listed: any `tools/gen_*.gd` whose output lands in `docs/` must have that file
  re-included in the real gate and negated in the stand-in. `docs/FLOW.md` is the live case: it
  is generated and drift-gated, so a hand-edit landing through the no-op would turn every LATER
  run red while its own was green.
- **The known edge, recorded rather than discovered:** a PR touching docs AND code runs both
  workflows; the real one finishes last, so the final status is honest. Re-running the no-op BY
  HAND after a red real run would overwrite the verdict - do not.
- Three mutants aim at the workflow YAML itself - the first non-GDScript mutants in the file,
  which works because sed edits text. `mutants_aim.sh` immediately caught the first one
  matching both copies of the mirrored list; fixed by making the copies differ textually (a
  trailing comment) rather than by loosening the pattern.
