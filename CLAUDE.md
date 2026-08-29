# RPG template — engineering rules

**This file is the contract.** If a rule here conflicts with your instinct, the rule wins.

This repo is a *template*, not a game. Everything in it exists so that building a new RPG
means editing `data/` and writing gameplay — never rewriting movement, sprites, saves or
the boot sequence. A change that makes the template more specific to one game is a
regression, however good that game looks.

## 1. Hard rules

- **Typed GDScript everywhere.** `untyped_declaration` and `unsafe_method_access` warnings
  are on. No C#.
- **Art is data, with no exception left.** Colours, palettes, cell sizes, frame counts and
  outline rules live in a `SpriteStyle` resource under `data/styles/`. A colour literal in
  `scripts/world/` or `scripts/ui/` is a build failure (`tools/lint_rules.gd`). **Terrain is
  authored the same way characters are** - a `TileBank` under `data/tiles/` in the rig's own
  `.`/`1`/`2`/`3`/`o` alphabet, one bank dressing every style. It was a `const TILES` in
  `TileGen` drawn by five hardcoded routines until M16, and the cost was legible: no routine
  could draw a door, so the quest's cave was built out of grass-world tiles.
- **Sound is data too, and generated the same way.** A cue's SHAPE is a row in
  `data/banks/<id>.json`; its VOICE is a `SoundStyle` under `data/sounds/`. Three voices share
  one bank the way three sprite styles share one rig. Template code never names a cue as a
  string — `Sfx.Cue` is an enum, so a typo is a compile error rather than a warning nobody
  reads at the moment the sound should have played.
- **Numbers live in data, not code.** A literal in a script that a designer would want to
  change is a bug. Speeds, reaches and timings come from `data/game_config.tres`.
- **Randomness is seeded.** `SeededRng` only. `randi()`, `randf()`, `Array.pick_random()`
  and `Array.shuffle()` draw from a global generator nobody seeded, which silently breaks
  every "same seed, same sprite" guarantee. The linter fails the build on them.
- **Directions come from `Dir`.** Canonical order is `down, left, right, up`, everywhere,
  forever: sheet rows, animation names, facing values. A raw `"left"` in a script is a
  build failure.
- **No logic in `.tscn`.** Scenes hold views.
- **A player-facing surface is researched before it is built, against
  `docs/GENRE_CONVENTIONS.md`.** Read that surface's section first; if it is thin, do the
  research and thicken it BEFORE writing the screen. Two milestones shipped fully-green
  surfaces the person who asked for them rejected on sight - a shop that was three lines of
  text, and equipment folded into the bag - because the reference pass was skipped, and then
  because it was scoped to a feature's mechanics rather than to its PLACE. No gate can see a
  screen missing half of what its genre gives it. The question is "where does this live and
  what sits beside it", not only "how does it behave".

## 2. Architecture

```
scripts/spritegen/  pure RefCounted, deterministic, NO node access — the sprite generator
scripts/soundgen/   the same, for sound: synth, sound_bank, sound_source + two impls
scripts/util/       dir, sfx, json_file, seeded_rng, hashing, lint_core, content_scan,
                    image_file + sound_file (build-time readers, never shipped)
scripts/data/       Resource types (SpriteStyle, SoundStyle, CharacterSpec, GameConfig, SaveData, EnemyDef, CombatDef…)
scripts/world/      Locomotion + GridWalker + NpcBrain (all pure) + the nodes that apply them
scripts/ui/         DialogRunner + DialogBox, PauseMenu + PauseScreen,
                    BattleLogic + BattleScreen, GameOverMenu + GameOverScreen (pure + view)
scripts/autoload/   EventBus Registry GameState SaveManager Router AudioBus Settings Qa
scenes/             views only
data/               all content: games, styles, rigs, tiles (terrain art), characters,
                    maps, dialog, items, enemies, combat, banks (cue shapes), sounds (voices)
games/<id>/         a game's OWN code: a GameHooks subclass, and nothing generic
assets/generated/   build OUTPUT of tools/gen_sprites.gd — never hand-edited
```

Signals up, calls down, through `EventBus`. Autoloads hold state, scenes hold views; a view
never assigns `GameState.x` — it emits and the owner responds. One writer per piece of
state.

**Which game runs is data, not code.** `data/games/<id>.tres` (`GameManifest`) holds the first
map, the spawn, the player's character, the config and the controls hint. `GameSelect` picks
one: `--game=<id>` beats the `application/config/game` project setting, which beats "there is
only one game". Nothing in `scripts/world/` may name a map, a spawn or a character again.

**When nothing chooses, refuse — never guess.** `GameSelect.choose()` returns `""` when there
is more than one game and nothing picked between them, and the boot stops there with an error
naming them. One game ships, so the single-game fallthrough is the live path and the refusal is
unreachable — it is kept armed because the day a second game is added is exactly the day a
guessed game starts presenting as the game you meant to run behaving strangely. The shipped
`config/game` is empty for that reason: with one game it needs no answer, and with two it must
be given one.

**Gameplay goes in `games/<id>/`, never in `scripts/`.** A game's code is a `GameHooks`
subclass named by its manifest. It is handed a `GameContext` and **may not name an autoload** —
naming one removes a file from the per-file parse gate AND `compile_all.gd`, so it would leave
two of the four gates silently; `LintCore.RULE_AUTOLOAD` fails the build on it. Hooks read a
snapshot and append effects; `world_scene._apply` is the single place any of it reaches live
state. `on_interact` returning `false` means "not mine" and the data's own behaviour runs — a
game is additive or it is not using this seam.

**A view asks for a sound; it never plays one.** Every screen carries
`signal sound_wanted(id)` and `world_scene._on_sound_wanted` is the single place that reaches
the speaker - the `_apply_effects` shape, for audio. Two reasons, and the second is the one
that bites: `check.sh`'s per-file parse gate skips any file whose TEXT contains an autoload
name, so a view calling the audio singleton silently drops itself AND every suite that depends
on it out of that gate. **Naming it in a comment is enough to do this** - which is how the
signal came to exist. Pure classes (`BattleLogic`) go one step further and COLLECT cues for the
view to drain, because a fight's cues must survive a defeat, whose effects are discarded.

**A tile names a ramp, never a colour, and `solid` is art data.** `TileBank.problems()`
refuses a ragged row, a typo'd pixel, a duplicated id, a tile that is not the bank's declared
size, and a transparent pixel in anything not marked `decor` - a hole in the ground shows the
window's background through the world, and it is invisible while authoring because the tile
looks right on its own. A tile's `ramp` is a DEFAULT: `SpriteStyle.tile_ramps` overrides one
where a style wants it different, which is what stops adding a tile from being a mandatory
edit to every style. `TileGen.problems(bank, style)` holds the checks needing both, the way
`CharacterSpec.problems(rig, style)` does.

**A dialog line has a SIZE, and the build enforces it.** `DialogBox` shows two lines of text
with the choices in a band of their own below them, and the box grows only while a choice is
up. Those numbers are constants on `DialogBox`; `test_dialog_fit.gd` measures every shipped
line with the real font against those same constants and fails the build on anything that
would not fit, naming the file and node. It exists because the opposite is silent: a
`RichTextLabel` with scrolling off does not wrap, scroll or complain past its height - it
CLIPS, so a fact written into the data never reaches the player and every headless gate still
passes. A line that needs more room is another node on a `next` chain.

**A dialog choice line cannot be escaped.** `cancel` closes a dialog only while a line is
being shown; on a line with choices the box routes input to the choice list instead, because
the point of a choice is that one gets picked. So a conversation that loops back THROUGH a
choice node has no way out of it - both branches of a choice must eventually end the talk.

**No actor is a moving platform, and the default says otherwise.** `platform_floor_layers`
defaults to every layer, which is a platformer contract: a body touching another from above
reports `on_floor`, and a body on a MOVING floor inherits its velocity. Top-down, every actor
is a "floor" to anything touching it from above - so an NPC walking down into the player rode
along wherever he strafed, at exactly his walk speed, while one walking UP into him was
untouched (from below he is a ceiling, and ceilings carry nobody). `ActorBody._init` clears it.
An unset engine property is not a neutral one; it is whatever genre the engine assumed.

Deliberately NOT `MOTION_MODE_FLOATING`, which Godot recommends for top-down and which would
also fix this: floating changes how every body slides along every wall, and the eleven play
sessions are calibrated against the current sliding - switching it diverged
`finish_the_quest` at the hermit into 16 cascading failures. That is a movement-feel decision
for a person who has played the game, not a side effect of a bug fix. See `docs/DECISIONS.md`.

**Two movement modes, and `place()` is the only teleport.** `GameConfig.grid_step_pixels` at
zero is free pixel movement; set to the map's tile size it is one press = one tile. Both go
through `velocity` + `move_and_slide` and produce the same `Locomotion.Step`, so nothing
downstream can tell which is running. `ActorBody.place(at, facing)` is the ONE way an actor is
teleported — it cancels a step in flight *before* assigning the position, because abandoning
one afterwards resolves it against the cell the actor left, in the map it left.

**Items are a template noun, and every effect has ONE sink.** `ItemDef` under `data/items/`
(picked up by `Registry` from its `class_name`), `Inventory` pure beside it, and a snapshot
`Dictionary` at every seam - a hook, a save, a map file. `requires_item` sits beside
`requires_flag` on objects, warps and dialog choices, and wherever a refusal can happen a
`locked_dialog` is required. **A take implies a requires**: `Interaction.decide` and the runner
both refuse before appending anything, so an effect list is all-or-nothing and `once` never
records a chest that gave nothing. Gifts go on dialog CHOICES, never nodes (a node has no
condition and no memory, so a loop hands over a second key); the once-idiom is `set_flag X` +
`hidden_if_flag X` on the same choice. `world_scene._apply_effects()` is the only place any of
it reaches live state - `_on_dialog_closed` goes through it too.

**A fight is template logic over game data, and it never writes anything.** `BattleLogic` is
pure and has NO CLOCK: `tick()` is handed one physics frame at a time by `BattleScreen`, which
is what lets a QA script press on an exact frame and get the same fight on every machine. Only
the FIRST press of a cue is captured, or mashing lands a press in every window and "timing"
means "press a lot". Results are COLLECTED and applied through `world_scene._apply_effects`, so
"a beaten enemy stays beaten" is the same map-scoped `seen` key a chest uses - persisted and
migrated for free. Enemies are a map record (`enemies[]`), fully projected by `enemy_at()` the
way `warp_at()` is, and the encounter fires on ARRIVING at a tile adjacent to one: a body stops
the player 6-10px out, so waiting for contact would make the trigger frame depend on walk
speed. Diagonals deliberately do not count - a fight that must happen is made unavoidable by
GEOMETRY (a one-tile gap), never by a radius. A game with no `CombatDef` on its manifest cannot
fight, and that is a legal shape forever.

**A party is a LIST even when it is one, and who is in it is derived from a flag.** A game
with no `party` on its manifest is handed one synthesized member - the manifest's own
`player_character` and `combat`, named "You", knowing everything its level has reached - so
`BattleLogic`, the screen and the menus always see a list and there is ONE code path through a
fight. The proof is that all sixteen scripted sessions pass untouched. A `PartyMemberDef` under
`data/party/` carries a companion's name, art, own curve, own spell list and `joins_on_flag`;
**membership is derived from that flag every time it is asked**, the way knowing a spell is
derived from level - so recruiting is the `set_flag` a dialog choice already carries, and there
is no roster to save, migrate, or hand out twice. Only each member's NUMBERS are saved
(`GameState.companions`, save v9). An empty spell list means NONE for a companion where it means
EVERYTHING for the leader, which is why `_member_spells` and `_battle_spells` are two functions
rather than one parameter carrying two opposite meanings.

**The round is command-all-then-resolve, in party order.** Every standing member declares before
anything happens (FF1's manual and Dragon Quest both), then the orders resolve in PARTY order and
the enemy acts last. Not by a stat: FF1's own turn order is a random shuffle that ignores
everyone's numbers, and a declared order is the only one a replayed fight can have. `cancel` on
the menu takes back the previous member's order and hands the menu back to them - with one member
there is never a previous order, so a solo cancel is still refused exactly as it was. Each
member's ATTACK gets its own cue and its own first-press-only capture; a cast still has no window.

**The ally cursor exists only at two.** `Phase.ALLY` opens for a heal or an item when more than
one member is standing, over the STANDING only - reviving in a fight is a verb this template does
not have. At one member it is skipped wholesale, which is both the genre-honest call (a cursor
with one row is a question whose answer it already has) and what keeps every session recorded
before M27 pressing the same keys. There is still no ENEMY cursor: fights are one foe.

**Falling is not losing, and every living member earns the full award.** Zero hp means down, no
turns, no xp; the fight is lost only when EVERYONE is down. Dragon Quest's xp rule rather than
Final Fantasy's division - dividing punishes a small party for being small and needs a rounding
decision one shared curve has nowhere to put. The fallen stay at nought through victory and are
put back up by the inn, which is the genre's paid town service (DQ's priest, EarthBound's
hospital) and needed no new mechanism: `_rest()` loops the party. **`party_unset()` is therefore
"nought health AND nobody standing"** - with a party, a fallen leader beside a standing companion
is a real saveable state, and reading it as "never fought" would silently resurrect them on the
way into the next fight.

**The enemy's target is drawn from its OWN seeded stream**, `derive("target")` beside
`derive("moves")`, so the moves an existing fight draws are untouched and every solo replay is
byte-identical. Chosen BEFORE the defend cue opens, because the cue is the thing being reacted to
- the target's armour applies, the halving is theirs, and the screen marks them while there is
still time to press. `BattleScreen.MAX_PARTY` is the declared capacity a game may not exceed, the
M13.3 rule; a party of one draws exactly the layout that shipped.

**Magic is a level curve, and knowing a spell is DERIVED from level.** `CombatDef.base_mp`/
`mp_per_level` size the pool the way `attack_at` sizes a swing - zero is the default and means
a game with no magic. A spell is a `SpellDef` under `data/spells/`, and `learn_level` is the
whole learning mechanism: `world_scene._battle_spells()` filters the registered spells by the
player's level every time it opens a fight, so there is NO known-spells list to save, migrate,
hand out twice or let drift from the level that bought it. Dragon Quest and Chrono Trigger both
do exactly this. MP joined `set_party(hp, xp, level, mp)` rather than getting gold's
give/spend pair, and the argument is REQUIRED: gold moves on its own, where MP only ever moves
alongside hp - a fight, an inn, a level - so a call site that forgot it would silently empty
the player. Saves are v8; mp rides inside the `party` dict, because a game with no party has no
magic either.

**Three spell kinds, and a cast has no timing window.** `SpellDef.Kind` is `ATTACK | HEAL |
SLEEP`, closed the way `ItemDef.SLOTS` is. Three rather than two because every reference game
ships a non-damage, non-heal effect among its FIRST spells - Sleep is tier one in Final
Fantasy, and Dragon Quest 1's whole eight-spell list still has it. An ATTACK deals FLAT damage
that ignores the enemy's armour, which is what gives magic a job beside a stronger swing; the
timed press stays a property of SWINGING, or the whole fight becomes one reflex test and the
menu decides nothing. `Row.MAGIC` sits between Attack and Item - every reference game's order,
and the row every counting test and play session below it had to move for. A cast the purse
cannot cover is refused, SAID and costs no turn (money's precedent), and `can_afford()` is the
one function the screen dims by and the press refuses by, so the two cannot disagree. There is
no targeting step: fights are 1v1, so an offense spell hits *the* enemy.

**Money can leave through a conversation, and a refusal is SAID.** A dialog choice carrying
`spend_gold` is checked against the purse before anything is collected, and a choice that
charges MUST carry `poor_next` naming a node - the `locked_dialog` rule applied to
conversations. This is the one requirement that is shown-and-refused rather than hidden:
`requires_item` hides, because offering to hand over what you are not carrying can only go
wrong when taken, but a price is quoted out loud and a player who says yes to one they cannot
meet has to hear why not. The check counts what earlier choices in the same conversation have
already committed, for the reason `_flag_known` counts flags earned earlier - nothing has
reached live state yet, so two spends would otherwise both be checked against an untouched
purse. `_collect_reachable` follows `poor_next` too, or every correct refusal fails the build
as unreachable.

**A rest is a full heal, through the one party writer.** `{"op": "rest"}` carries no amount:
what "full" means is the running game's own `CombatDef`, which is why it cannot live in a
dialog file or a menu. It goes through `set_party`, which takes all three numbers because
they are one fact, so a rest hands xp and level back unchanged and moves only the hp - the
`_ensure_party` shape. A game with no `CombatDef` has no notion of full and nothing to heal,
so the op says so rather than quietly doing nothing. Deliberately NOT a parameterised
`heal(amount)`: a partial heal is a field-item verb this template does not have.

**An inn is a CONVERSATION, and the night is the thing the player experiences.** Not a counter:
the genre's innkeeper greets, names a price, asks yes or no and fades to black - there is
nothing to browse, so an inn is a dialog carrying `spend_gold` + `rest` + `poor_next`, and it
needs no `InnDef`, no menu and no list. `RestScreen` is the whole surface, and it exists
because the heal is not what a player experiences - the night is; a rest that snapped from
wounded to full with no beat between would read as a menu transaction. It is opened DEFERRED,
the `open_shop` precedent exactly, and it is a `Router` state so nobody can walk out through
the middle of a fade. Its frames come from `GameConfig`, never seconds. Kept as a rest screen
rather than a general fade because there is one caller; the day a second wants it is the day
it becomes a `FadeScreen`.

**A shop is a COUNTER, not a list.** The screen is the anatomy every classic shop converges
on, and M18 shipped without most of it: an item list with prices RIGHT-ALIGNED in their own
column and the owned count beside them, a purse panel that becomes the running total while a
deal is being sized, a description bar in the item's own words (`ItemDef.description`, which
existed since items did and no screen showed), and the keeper's window along the bottom in
the DialogBox's shape. Windows over the LIVE WORLD, never a full-screen dim - a shop is a
place you walked into. The buy flow is pick -> **how many** -> confirm: the count step is what
lets a player buy three of something, and the total travels on the Deal so the number they
agreed to is the number the purse moves by. The keeper's words are `ShopDef` fields with
template defaults, so a game re-voices a merchant without touching a script, and a refusal is
SAID as well as thudded.

**A shop is a `ShopDef` and a dialog CHOICE, and `price = 0` means not for sale.**
`data/shops/<id>.json`-shaped `.tres` lists item ids; the price lives on the `ItemDef`, so two
keepers cannot disagree about what a tonic is worth. Zero is the DEFAULT, which is what keeps
quest items off both counters - a key that can be sold is a door that can be locked for the
rest of the run, and the failure lands hours later. `ShopMenu.tradable()` is that rule, once,
so the buy page and the sell page cannot drift. A keeper is opened by `"open_shop": "<id>"` on
a dialog choice, and the arm in `_apply_effects` DEFERS the open: `_on_dialog_closed` applies
effects and then pops the dialog overlay, so a counter opened inline would be the thing that
pop closed. The menu is the only affordability check; `spend_gold` behind it is the invariant,
and it says so loudly rather than overdrawing anyone.

**Equipment is a menu command of its own, and the flow is SLOT-FIRST.** `Row.EQUIP` sits
between Items and Save, which is the order every classic command menu uses and the one thing
a player navigates by muscle memory. It opens a slot list built from `ItemDef.SLOTS` -
"Weapon: Bronze sword", "Armor: (nothing)" - and a slot opens the carried gear that FITS it
plus a `(take off)` row. M19 shipped this as a confirm-toggle inside the bag instead; it was
fully tested, fully green, and the first person to play it said it should be its own screen,
because that is where every game it was modelled on keeps it. See `docs/GENRE_CONVENTIONS.md`.

The filter is what makes the page safe: a slotless item is never a candidate, so a tonic
cannot be offered as armour - the offer is never made, rather than refused at confirm time.
The take-off row is always drawn (so no slot can strand a cursor) and taking off an EMPTY
slot is refused, the empty-slot-load rule. Both answers pop back to the slot list before the
world hears them, so every refresh lands on a page whose rows are the template's own
vocabulary rather than on a candidate list built from a bag that is about to change.

**The preview is a SWAP, and the readout is what makes it one.** `_candidate_effect` words
the delta against what the slot already holds, so wearing what is already worn reads "no
change" rather than promising its stats a second time; `_stats_label` puts "Atk 5+3 Def 1+0"
beside the purse, because a delta needs a number to be a delta OF. Both are worded by the
WORLD - naming a stat is a Registry question and `PauseMenu` may not ask one. A game with no
`CombatDef` gets no readout at all rather than a screen inventing a stat it does not have.

`Kind.UNEQUIP` carries the slot rather than an EQUIP carrying an empty item: a verb spelled
as the absence of its opposite is one every listener has to remember to decode, and the one
that forgets equips nothing and reports success.

**The bag keeps the marker and loses the verb.** An `(E)` on the row still finds what is worn
at a glance, but `confirm()` on the ITEMS page answers NONE again - a potion heals in every
RPG ever written, where "use the rope on the well" is a puzzle, so a use verb stays a game's
business. **What is worn is not on the sell counter**, and that refusal lives in the world
rather than in ShopMenu: the counter has no business knowing what equipment is, and a spare
copy stays sellable while one is worn.

**Gear is a MODIFIER, never a stat, and it never leaves the bag.** Player attack and defense
are DERIVED (`CombatDef.attack_at(level)`), so equipment cannot be stored as a stat without
two sources of truth for one number; it arrives at `BattleLogic.of()` as two already-summed
ints, because that class may not reach the Registry. The world resolves them (`_equip_mod`),
which is the `_battle_items`/`_item_rows` precedent. `GameState.equipment` is slot -> item id
and the item STAYS in the inventory - equipping marks it, so the bag remains the one list of
what the player has, and a swap has nothing to put back. `take_item` clears the marker when
the last copy leaves by ANY path, because a slot map pointing at a phantom re-arms the moment
another copy is picked up; `SaveData.problems()` checks the same invariant against the file
itself, since a hand-edited save can describe a player who cannot exist.

**Money has ONE writer and a spend is refused, never clamped.** `GameState.gold` sits beside
hp/xp, but zero is a REAL value there (broke) rather than the "unset" hp uses, so it is a
plain field with a plain default. `give_gold`/`spend_gold` are the whole vocabulary and both
report whether they happened; a spend beyond the purse returns false and moves nothing,
because clamping turns "could not afford it" into "bought it and has nothing". Gold therefore
cannot go negative by construction rather than by a check somewhere downstream. An enemy's
`gold` rides the same collected effect list a fight already uses, so a DEFEAT - whose effects
the world discards wholesale - still pays nothing, and "a fight never writes" is untouched.
The purse is drawn on the pause screen as a READOUT, not a row: the cursor cannot land on it,
so every test that names a row by its enum stays aimed at the same row.

**An NPC's behaviour is data, and a moving one is driven by the player's own code.**
`behavior` on a map's npc record is `static` (the default), `wander` (bounded drift around
where it was placed) or `patrol` (an authored `path` of tiles, `loop` or ping-pong).
`NpcBrain` is pure and has NO CLOCK - it answers with an INTENT VECTOR, the same axis pair a
keyboard produces, so a walking NPC goes through the same `Locomotion`/`GridWalker`/`ActorBody`
the player does. Dwelling counts FRAMES; a wall-clock dwell would make a play session depend
on how busy the machine is. Draws come from a `SeededRng` keyed on game+map+npc id, never a
clock - the world had no per-frame randomness before this and still has none that a rerun
cannot reproduce.

`_drive_npcs()` sits BELOW the `Router.player_can_move()` early return, and that placement is
the whole design: a dialog, the pause menu, a fight or game-over stops the town as well as the
player, so a speaker cannot wander off mid-sentence. It is a placement rather than a line, so
no mutant can express it - `test_world_npcs.gd` proves it by moving the call above the gate.
NPC footfalls are read and DISCARDED, or a town of walkers plays footsteps the player cannot
place. **A `static` NPC is never given a brain at all**, which matters beyond cost: several QA
sessions use shipped NPC bodies as walls (the warden at village [5,3] stops every northward
leg), so a shipped NPC that started wandering would break sessions that look unrelated. A
typo'd behaviour FAILS THE BUILD rather than standing still, and a patrol waypoint in a wall
or on a warp is refused - an NPC parked on the only exit is a door that cannot be used.

**The status page is a READOUT, and every line of it is worded by the world.** `Row.STATUS`
sits after Equipment - Item, Equip, Status is the genre's order - and opens a page with
nothing on it to press: `confirm()` answers NONE, and the view draws no cursor, because a
cursor on a page with no verb points at something that does not exist. The lines come from
`world_scene._status_lines()`, because knowing that "Level" is what this game calls one, and
whether it HAS one, is a manifest question a pure menu may not ask. A game with no
`CombatDef` gets the gear lines only, and a game with nothing at all gets "(nothing to
report)" rather than a page of blanks. At the top of the xp curve the page says so instead of
promising a level that is not coming.

**Music is authored notes performed by the cue synthesiser, and a track is a GAME's content.**
A tune is `data/music/<id>.json` - bars of `<note><octave>:<steps>` tokens - rendered per
`SoundStyle` into `assets/generated/<style>/music/`, so three voices play one melody the way
three sprite styles draw one rig. `Tune` obeys everything `Synth` does and one thing more:
pitch is a 12-entry INTEGER Q20 ratio table with octaves applied by doubling, because
`pow(2, n/12)` is exactly where a naive version reaches for libm, and a decimal float literal
would lean on `strtod` instead. A track LOOPS, so it gets a note envelope with a flat sustain
and NO fade tail - a ramp at the end is a dip on every pass - and looping is set on the stream
in `AudioBus` at bind time, because `project.godot` pins WAV looping off project-wide and a
sidecar is build output the drift gate regenerates.

**A fight scores itself, and a jingle is a property of the CALL.** `GameManifest.battle_music`
takes the room over when a fight opens; `victory_music` plays ONCE on a win and then hands the
room back, through `AudioBus.play_music_then(id, then_id)`. Both empty is the default and is
the old behaviour exactly - a fight then sounds like wherever it happens. What makes a tune a
one-shot is that call, never a flag in its JSON: the same file could be somebody's title theme,
so "played once" is a fact about the playing. The one-shot is a DUPLICATE of the bound stream
with looping off, because `_play` hands the table's own instance to every later caller and
switching its loop off in place would leave the next map's theme playing once and stopping.

The chain is counted in PHYSICS FRAMES, not driven by `AudioStreamPlayer.finished`. That signal
is free and unconnected and would still be the wrong clock: headless runs on a dummy driver that
never reports a stream as playing, which is the measurement that made `music_starts()` exist.
Any new music call disarms a pending hand-back, so a second fight starting mid-fanfare is not
interrupted by the last one's chain firing into it - and a jingle asked for twice STINGS twice,
bypassing the no-restart guard, because a jingle is an event where a theme is a state.

**`AudioBus.play_or_silence(id)` is what a PLACE sounds like** - its track, or silence when it
names none. Three callers need that exact answer (entering a map, a fanfare handing back, a
fight ending), and written out three times it is three copies of "a map states its music or
states silence, never inherits" with one of them eventually stale. A defeat is the exception
and stops the music outright: every way out of a game over states its own music again.

**A cue is named by the template and a track is discovered.** `Sfx.Cue` is an enum so a typo is
a compile error; a track is named in a manifest (`title_music`) or a map record (`music`) and
found by `ContentScan`. They share ONE table in `AudioBus`, which is what lets a game drop
`theme.ogg` into `data/audio` and replace either - so `MusicTrack.problems()` refuses a track
named after a cue. **Music keeps its own request log**: `unknown_requests()` fails a play
session for anything `Sfx` does not name, and the first tune would otherwise have failed the
scripted sessions - intermittently, since a 64-entry ring buffer and every `sound_mark` can age
the id out. A map states its music or states silence, never inherits.

**A VOICE is bound wherever a manifest is presented, and the bus only claims what it started.**
`use_style` used to be called by `_build_game` alone, so the title - which opens at `_ready`,
before any game is built - asked for its theme through a bus with nothing bound and played
nothing at all, on every platform, for four milestones. `open_title` binds it too. Three checks
watched that happen and each asked a question one step short: `assert_music` reads the request
LOG and the request is made either way; `music_id()` was set whether or not the track could be
played, so even the check that reads the live track to avoid trusting the log inherited the
lie; and `assert_audio_ready` reads `missing_cues()`/`missing_tracks()`, which `reload()` fills
only when a voice is bound - so with none bound both are empty and the one gate built to catch
a silent artifact reported green precisely because nothing could make a sound.

So: `play_music` records a track only if `_play` SUCCEEDED, and leaves `_music_id` alone on
failure rather than clearing it - `_play` returns before touching the player, so whatever was
playing still is. And `assert_audio_ready` fails outright when no voice is bound; a game that
is deliberately silent simply does not write that step. **A gate that reports on a set it never
populated is worse than no gate**, and this is the third time that shape has shipped here.

**The flow is DATA, and it is updated before the code that changes it.** `tools/flow_model.json`
declares every state, what must be true while the machine is in it, and every way between them -
including the EXACT sequence of `flow_changed` events each move may emit.
`tests/integration/test_flow_model.gd` drives all of it through the real world scene and fails
when the recording differs, so the model is checked rather than believed; membership is asserted
both ways, so a new `Router.State` with no row in the model fails the build. `docs/FLOW.md` is
drawn from it by `tools/gen_flow_doc.gd` and drift-gated - a picture, never a source.

It exists because the knowledge of what a transition passes THROUGH lived only in scattered
code, and the question nobody asked - what does this new edge go through? - shipped a Continue
that replayed the game's opening conversation over the loaded save. The failure the gate is
built to catch is an UNDECLARED INTERMEDIATE STATE: an action that arrives where it promised,
having gone somewhere nobody wrote down.

**Two moves are two hops, and both are deliberate.** A defeat is `battle -> world -> game_over`
and leaving a game over for the title is `game_over -> world -> title`, because the screen being
left is torn down before the next is built - two full-screen views are never stacked. An EMPTY
trace is a legal answer: a warp re-enters a map from WORLD, and WORLD to WORLD is not a change.

**Every state change announces itself, including the ones that look like housekeeping.**
`reset()` and `to_title()` both go through `_to_base()`, which clears the stack and then calls
`set_state` - never assigning `_state` directly. `reset()` used to assign it, so map entry (and
therefore every boot, warp, load and restore) changed the state in SILENCE: the edge hiding
there was TITLE to WORLD, which is how a game starts. `set_state`'s no-op-on-same-state guard
is what keeps this from becoming noise - a warp resets WORLD to WORLD and still says nothing.
One `_to_base` rather than a stack-clear in each, because two literal clears in that file make
the mutant aimed at the first one ambiguous.

**A load must not travel THROUGH the beginning of a game to reach its middle.** `start_game`
and `boot_from_save` share `_build_game` and differ only in their last step: one enters the
start spawn fresh, the other restores a position. Continue from the title once called
`start_game` and then `restore`, which entered the START map with a fresh state on the way -
so the map-entry hooks fired against a player with no flags and the game's opening
conversation replayed over the loaded save. Two functions rather than a flag, because a
boolean that changes what a function's ending MEANS is two functions wearing one name.

**A game is started FROM a screen, and losing can end back at it.** `TitleScreen` +
`TitleMenu` over an EMPTY world, in `Router.State.TITLE` - which was the router's boot state
meaning "nothing to drive yet" from M2 until M22. `world_scene._ready()` resolves which game is
running and then stops; New Game calls the same `start_game` a game-over restart does. It is an
overlay rather than a second scene because `_ready()` is the ONE place `GameSelect.resolve()` is
called, and a title scene with its own boot would be a fifth surface answering "which game is
this" - the exact failure GameSelect exists to prevent. `GameOverScreen` gained the Title row
its own class comment had promised since M13.

`SlotMenu` is the base both screens share: they differ in the wording of two rows and nothing
else, and two copies of "nothing saved is nothing to continue from" is one screen that
eventually offers a list of nothing. GDScript refuses to let a subclass redeclare an inherited
enum, so the game-over's third row is a named constant one past the shared ones.

**The title opens its cursor on a pressable row and the game over deliberately does not.** At a
title a dud first press is friction; at a game over the player has just lost and is already
pressing, so opening on "Start again" turns one more press into a restarted run. A scripted
session found that one within a minute.

**A setting is not a save.** `Settings` owns `user://settings.json` - global, outside every
slot, surviving a new game and a deleted save. It carries no version: one field, an
unrecognised value falls back to the default, and the next write repairs the file. Redirected
under `--qa-script` exactly as saves are, and `test_settings.gd` ASSERTS the redirect is in
effect before touching anything - a suite that cycles the volume would otherwise write the
player's real preference, and the mutation harness runs that suite with the code deliberately
broken.

**Do not give an autoload a name that ends another identifier.** `compile_all.gd` decides what
to skip by looking for `Name.`, and `Settings.` occurs inside `ProjectSettings.` - nine files
silently left the compile gate, reported only as a count going up. The matcher now requires a
whole identifier; the hazard is the naming, so check a new singleton's name against the engine's
own globals.

**Saves are per game, and `restore()` is the one way back in.** Slots live at
`user://saves/<game>/slot_N.json` and each save NAMES its game; the two are cross-checked on
every read and a file that disagrees is parked, never loaded. `peek()` is the slot list's
silent read - drawing a menu must not park files or announce loads - which makes an unreadable
slot look *empty*, which is why `save()` parks whatever it is about to overwrite. Escape opens
`PauseMenu`/`PauseScreen` from `WORLD` only. `restore()` is the
single path from a save into a world (`from_save` then `enter_map`), and `enter_map`'s third
argument is a restored position that nothing else passes. A `--qa-script=` run saves under
`user://qa_saves`, wiped at boot, so a play script neither reads nor overwrites real progress.

**`move_and_slide()` picks its own delta** — the physics one inside a physics frame, the idle
one otherwise (pinned in `test_engine_assumptions.gd`). So never compute how far a call will
move something: end an operation by observing that it finished. This is also why the
integration suites can drive `apply()` by hand from a coroutine at all.

**The sprite contract is PNG + `<name>.sheet.json`.** Nothing engine-specific is committed
as art: `SpriteFramesFactory` turns that pair into a `SpriteFrames` at runtime. This is the
seam that lets a procedural rig, a downloaded pack or an AI generator feed the same game.

## 3. Testing

**Every gate ships with a proof that it fails on the input it exists to catch.** A
validator that has only ever passed is decoration.

- Pure logic (`spritegen/`, `Locomotion`, `DialogRunner`, `MapData`) is `RefCounted` and
  tested with no scene tree. Node behaviour uses gdUnit4's `scene_runner`.
- Mutants are mandatory: a rule with no row in `tools/mutants.tsv` is a rule nobody has
  proven is tested. `NOT APPLIED` means fix the pattern, never delete the row. A pattern must
  match exactly ONE line, and `tools/mutants_aim.sh` checks every row on every `check.sh` run —
  because writing NEW code is what breaks an old mutant's aim: repeat a line one anchors on and
  sed silently retargets it at your function. Fix by making the two lines differ (rename a
  local), never by loosening the pattern.
- Gates run **unpiped** — `cmd | tail` exits with `tail`'s status, so a failing gate
  reports success.
- Autoloads outlive a suite: call `GameState.reset()` in `before_test`.
- Assert on simulated frames, never wall-clock time. In a suite with no `scene_runner` that
  means `await get_tree().physics_frame`, not `await_millis()`: under load a millisecond
  spans no physics frame at all, and "the player did not move" becomes a fact about how busy
  the machine is. It fails as a mutation BASELINE FAILURE, which reads like a broken test.
- A simulated `InputEventAction` needs its matching RELEASE, the way `Qa.press` inserts one.
  An action left held is still held at the next press, and the engine sees no change.
- **Never navigate a menu by counting presses.** `move(PauseMenu.Row.SAVE)` and not `move(1)`:
  inserting a row re-aims every counting test at whatever now sits there, silently and while
  still passing. M12 turned a "refuse to load" test into one that SAVED a slot that way. The
  two places that DO count - `_to_the_third_slot()` and the QA sessions, which drive real
  keys and have no enum to name - write the count out with the row list in a comment above
  it, so inserting a row moves them deliberately. M20 inserted Equipment and then Status,
  and paid exactly that price, in three files, twice, on purpose.
- **A QA leg is held until a WALL or a BODY stops it**, never for a computed number of tiles.
  An arriving hold carries the player onward into the next map, so a leg that follows a warp
  must re-anchor against geometry rather than assume where the last one left off. The one
  legitimate count is "enough frames to reach the row a door is on" - past it is fine, because
  a warp fires on arrival.

### GDScript rules that are not optional here

- `--check-only -s <file>` is a parse, not a compile: it cannot resolve types from other
  scripts, and it cannot run at all for a script naming an autoload. `tools/compile_all.gd`
  and `tools/smoke_boot.gd` cover those two holes.
- gdUnit4 exits **100** on a failed assertion, and **0** when a discovery-time parse error
  crashes it — so `check.sh` greps for `handle_crash` and compares suites-ran against
  suites-on-disk.
- Never alias a project class in a `const` inside a test suite; it crashes the scanner.
  Aliasing an **enum** (`const D := Dir.D`) is fine. Typed helpers live in `tests/helpers/`.
- `Image.flip_x()` returns nothing and mutates in place. `var left = right.flip_x()` binds
  null and mirrors the original.
- Use `Image.create_empty`, `set_pixel`, and compare colours as `to_rgba32()` ints.
  `blit_rect` overwrites alpha; `blend_rect` blends floats and produces off-palette values.
- JSON has no integers. Cast every number you read, and `Array.assign()` into typed arrays.
- Adding an autoload changes what the parse gate skips: `check.sh` and `compile_all.gd` both
  derive that list from `project.godot`, so add the singleton there and cover it in
  `smoke_boot.gd` — never by editing a list in a tool.
- A new `class_name` script is invisible to gdUnit4 until `--import` has run — the failure is
  `Could not find type "X" in the current scope` at discovery, which reads as a typo. Run
  `Godot --headless --path . --import` after adding one. `check.sh` does this as step 1.
- Running gdUnit4 by hand needs `--ignoreHeadlessMode -c`, or it refuses with `Abnormal exit
  with 103` and no test output at all.
- `mutants.tsv` patterns are EXTENDED regexes, so `+` is a quantifier: `_index + delta` matches
  nothing and fails as `PATTERN-NOT-FOUND`. Escape it.
- **`LintCore.SOURCE_ROOTS` is the one list of directories this project owns.** The linter
  and `compile_all.gd` read it; `check.sh`'s parse gate keeps no list at all and excludes
  what is not ours. A new top-level source directory goes there and nowhere else, and
  `test_lint_core.gd` fails until it does.
- **Content is discovered through `ContentScan`, never a hand-rolled `DirAccess` walk.**
  Four of those existed and disagreed about recursion, so content one directory down was
  registered by the game, never generated, and the art-drift gate passed having compared
  nothing. Results are sorted because the generator's output order must not depend on the
  filesystem.
- **The deployed web build cannot be driven by browser automation.** Godot maps web input
  from `KeyboardEvent.code`; the automation available here sends trusted events with an empty
  `code`, and hand-built events with a correct `code` arrive untrusted and are ignored. A
  screenshot proves it renders and the console proves it booted — playability needs a human.

## 4. Commands

```bash
tools/check.sh                 # import, lint, parse, compile, tests, boot, art drift, play
MUTANTS=1 tools/check.sh       # + prove every gate bites (milestone close)
tools/mutate_check.sh --list   # what each mutant claims to cover
tools/mutants_scope.sh         # the mutants THIS branch's diff could have broken
tools/pack_check.sh            # export the .pck and PLAY it - the artifact, not the source tree
```

**Every gate except one runs against `res://` in the project directory. `pack_check.sh` runs
against the `.pck` a player downloads**, because that is where a whole class of defect lives: an
asset that is not packed, an exclude filter that grew, an importer that did not run. M14 shipped
one of those - the audio seam's drop-in half had been broken in exports since the day it was
written, and no gate could have seen it.

`--export-pack` needs no export templates and `--main-pack` boots the pack with the stock
binary, so the whole thing costs about five seconds and runs in `check.sh` as step 7b. The QA
scripts are read from an ABSOLUTE host path, because `tests/*` is excluded from the pack - the
shipping preset is never modified to make itself testable.

**A missing or truncated pack HANGS rather than failing.** Measured, both of them, with no output
at all. Every packed run is `timeout`-wrapped, and any path handed to `--main-pack` is made
absolute BEFORE the run changes directory - a relative one stops resolving and presents as that
same hang.

**An expected crash must not print like an unexpected one.** The pack exporter aborts during
shutdown after writing a complete package; bash reports that as `Aborted (core dumped)` from the
shell that WAITED on it, so redirecting the command's own streams does not stop it. Both export
sites run through a wrapper shell whose stderr is discarded and which exits normally. Note bash
3.2 (macOS) never prints it and bash 5 (CI) does — not reproducing it locally proves nothing.

**A swallowed exit code needs a stated reason.** `pages.yml` ignores the exporter's status for a
real, measured one (it aborts during shutdown after writing a complete package) and says so. It
used to ignore `--import`'s status for no reason at all, which was a fail-open in the step that
builds what ships.

**Anything driven by frames gets `$GODOT_FRAMES` (`--fixed-fps 60`), from `_engine.sh`.**
Headless does not mean fast: the engine still paces its main loop against the wall clock, so a
play session that takes a player three minutes took the gate three minutes. The flag pins every
delta at 1/60 AND stops waiting for real time between frames. It changes nothing a gate can
see - these harnesses count physics frames, never seconds - which is why the ten play sessions
give byte-identical logs with it and without, the suite returns identical verdicts on all 595
tests, and all 226 mutants are still killed. The whole gate went 7m35s to 27s. Do NOT add it to
the generators; they quit in their first frame.

**A WINDOWED run of a QA script needs the flag too, or it is a different session.** Driving a
play script with `--rendering-driver opengl3` to photograph it, WITHOUT `--fixed-fps 60`,
diverged from the headless run and failed assertions the gate passes - the waits count physics
frames, and an unpinned main loop spends them differently. Pass it whenever a session is
watched or screenshotted, which is also the answer to "why does the player walk so slowly in
that window".

**The mutation sweep is split by WHERE it runs, never weakened.** A pull request proves the
mutants its own diff could have broken (`mutants_scope.sh`: rows that mutate a file it touched,
name a suite it touched, or were added by it); every merge to `main` re-runs all of them, where
nobody is waiting. `mutants_aim.sh` still runs over the WHOLE file on every run of both -
that is the check that catches new code stealing an old mutant's aim, and it costs under a
second. Both CI paths pass `--assume-green`, which is only safe because `check.sh` has just
proven all 54 suites green in the same job.

**A docs-only change runs no gate, and the required status is answered by a stand-in.**
`check` is a REQUIRED status, so a pull request that produces none can never merge - which is
why the gate cannot simply ignore docs paths. `check-docs.yml` answers with the same workflow
and job name in seconds; ci.yml's paths and its are mirror images, and `test_ci_paths.gd`
fails the build when they drift - with the exceptions DERIVED from the generators, because
`docs/FLOW.md` is drift-gated output and a hand-edit to it must run the real gate. Three
mutants aim at the YAML itself, which works because sed edits text, not GDScript.

**A merge runs `check` twice, and that is the design.** `pull_request` proves the gate plus the
mutants that diff could have broken; `push` to main proves the gate plus ALL of them, is the
green signal `pages.yml` deploys from, and is the only run that tests the SQUASHED tree - the PR
run tested a merge preview, which is a different tree the moment main moves. Skipping `check.sh`
on the main run does not save it either: `--assume-green` is sound only because the suites were
just proven green in the same job.

**Open the PR and walk away.** `gh pr merge --auto --squash` merges it when CI goes green;
polling a 17-minute run is how a session gets spent. This needs a required status check on
`main` - without one, `--auto` merges immediately, which is the trap.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sprites.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sounds.gd
```

Drive the real game from a script, or photograph it. QA scripts live under
`tests/fixtures/qa/<game>/` and `check.sh` runs every one with `--game=<that directory>`, so
a new script needs no edit to the gate:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --qa-script=res://tests/fixtures/qa/quest/talk_to_npc.json --game=quest
```

Other headless tools: `setup_input_map.gd` (rewrites the input map — re-run after changing
bindings), `lint_rules.gd`, `compile_all.gd`, `smoke_boot.gd`, `screenshot.gd` (needs a real
rendering driver, so not headless and not in CI). `tools/_engine.sh` resolves the engine;
`GODOT_BIN` overrides it. The Godot MCP is an accelerator for interactive work, **never** a
dependency of the build.

**Two MCP servers, two jobs.** `godot` (`@coding-solo/godot-mcp`) scaffolds - create a scene,
add a node, load a sprite - by spawning a headless engine per call (250ms, 835ms for
`create_scene`). `godot-live` (`@satelliteoflove/godot-mcp`) reads and drives a RUNNING editor
over a WebSocket bridge at a flat 7ms: live scene tree, tilemap edits, input injection,
deterministic `freeze`/`step`. Measured in `tools/mcp_bench` - re-run it rather than trusting
these numbers. Neither does the other's job: `godot-live` cannot create a scene or add a node
at all.

**`godot-live` needs an addon this repo deliberately does NOT commit.** Enabling
`addons/godot_mcp` costs two things that were measured, not guessed. Its `plugin.gd` calls
`ProjectSettings.save()` to force an `MCPGameBridge` autoload, and **that save strips every
comment out of `project.godot`** - the QOA-importer note and the `config/game` refusal note
both vanished, and restoring them by hand did not survive the next build that loaded the
plugin. The forced autoload then either ships (+1MB in the pack, `exec_commands` included) or,
if excluded, makes every packed boot print three `Failed to instantiate an autoload` errors.
`--import` alone is safe; anything that loads the plugin is not. So install it on demand, use
it, and revert:

```bash
npx -y @satelliteoflove/godot-mcp --install-addon .   # then enable it in project.godot
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path .   # bridge on :6550
git checkout -- project.godot && rm -rf addons/godot_mcp                    # when done
```

The bridge runs headless - no editor window, despite what the addon's README says. With no
editor up, `godot-live` simply reports "not connected" and costs nothing.

Anything that needs the running game — the world, the player, the router — must be driven by
a `Qa` script rather than by `-s tools/x.gd`: in `-s` mode the autoload singletons are not
registered as identifiers, so a scene whose script names one will not even load.

## 5. Generated art and sound

`assets/generated/**` is output. Edit the rig (`data/rigs/*.json`) or the style
(`data/styles/*.tres`), re-run `gen_sprites.gd`, and commit both together — `check.sh`
regenerates and fails if the committed PNGs disagree with what the generator now produces.
Sound works identically: edit `data/banks/*.json` or `data/sounds/*.tres`, re-run
`gen_sounds.gd`, commit the WAVs.

**Commit the `.import` sidecar with every generated file.** An imported asset ships as its
sidecar plus the engine's cached copy; the original file is not packed, so a `.wav` or `.png`
without one works locally and is simply absent from the web build.

**The generator may not call `sin`, `pow` or `exp`.** IEEE-754 pins `+ - * /` to the same
result on every machine and libm pins nothing, so a transcendental anywhere in the render path
can make the committed bytes differ between this Mac and the Ubuntu runner — turning the drift
gate red for a reason nobody can reproduce. Waveforms are built from arithmetic and integer
noise, deliberately.

**The drift gate checks what `load()` returns, not just the file.** Godot's WAV importer
defaults to lossy QOA; `project.godot`'s `[importer_defaults]` pins it off, and
`gen_sounds.gd --verify` compares the imported stream too, because a file that matches while
the imported asset does not is a game whose every player hears something unchecked.
