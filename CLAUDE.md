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
  could draw a door, so the quest's cave was built out of grass-world tiles. **Imported art is
  the one exception, and it has a name:** a style whose `sheets_from` is `lpc` shows pixels the
  artists drew, converted from a Universal LPC export, and a bank whose `pixels_from` is `files`
  cuts its ground out of art somebody drew. What stays data is WHERE it comes from and what it
  may be LICENSED under, and both are gated (§2).
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

**A BANK says where its pixels come from, and that is the whole switch.** `pixels_from` is
`rows` - authored in the rig's alphabet, drawn in the style's ramps - or `files`, where each tile
is a CELL cut from art an artist drew. The `sheets_from` shape one layer down: a StringName
checked against a list, a typo refused BY NAME, and the two arms stated as a pair rather than
inferred from an absence. The bank is the right home for it because a bank already IS the recipe,
the ordered list of ids with `solid` and `decor` on each; a style stays "which bank", so one game
paints hand-drawn ground and another the rig's own with no third concept. A `files` bank lists
the art it cuts from in `character.json`'s own credit shape, so it is handed to `LpcImport` as one
more recipe and the ground lands in `credits.json` beside the cast with no second reader.
`TileGen.problems` holds what needs both the bank and the art: the image present, the cell inside
it, a hole in a non-decor cut refused by tile name, and every file offered under a licence the
style accepts - through `LpcImport.license_allowed`, because a second opinion about licence
families is how share-alike ships as credit-only.

**`credits.json` and `LICENSE.txt` exist exactly when something imported went into them**, so
they are emitted after BOTH arms rather than inside the import one: a style can draw its own
characters and still stand on somebody else's ground. The notice names both routes, because one
sentence claiming the character generator drew the ground too is the wrong-genre-claim-in-a-
comment failure M32 already paid for.

**A palette rule cannot speak about imported pixels**, so the palette gate skips an imported bank
and COUNTS what it checked; membership is asserted as a SET over the banks the way it already is
over the styles, so a third kind of pixel source cannot opt out of both lists. And "no tile is
one flat colour" runs over every style, because the usual way to get a flat tile from a cut is to
pick the middle of a transition block - LPC's ground sheets have exactly one, and it is one
colour.

**Terrain has no transitions, and that is a stated divergence.** Every reference draws the edge
between two materials as its own tile, and LPC ships the 3x3 ring for it; this template paints
one id per cell, so a shoreline is a hard edge. Deferred rather than rejected, because a cell
would stop being one tile id and that is what every map file, both editor translators and
`MapData.problems` are built on. See `docs/GENRE_CONVENTIONS.md` §15, which is measured from the
artwork rather than recalled.

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

**The WORLD grows and the INTERFACE does not.** `SpriteStyle.world_scale` says how many world
pixels one interface pixel is; the window becomes `UiScale.DESIGN_SIZE` (320x180, pinned against
`project.godot` by `smoke_boot.gd`) times that, and every `CanvasLayer` is drawn at it. So a 32px
style shows the same twenty tiles across as a 16px one while every screen, font size, `DialogBox`
constant and layout audit keeps measuring against 320x180 - untouched, and still true. The
alternative was scaling the LAYOUTS, which would have re-tuned every constant in `scripts/ui/`
and left every gate measuring a window nobody is shown.

`UiScale` is pure and names no autoload, because the world scene and Sprite Lab both call it.
`world_scene._bind_style` is the ONE place a style is bound - `enter_map` and `open_title` both
go through it - and it does three things that must not come apart: the style, the letterbox
colour, and the window. M40's own cautionary tale is a partial bind (the title asked for music
through a bus with no voice for four milestones). `_mount_ui` is the one way an interface layer
joins the tree, and `UiScale.rescale` is its pair: the dialog box and the controls hint are built
in `_build_game`, BEFORE any map has said which style is running, so mounting alone cannot reach
them. A screen mounted around the helper is a quarter-size menu in the corner, which reads as a
broken screen rather than as a missed line - `test_world_scale` asserts membership over whatever
CanvasLayers it finds, so a new screen fails there without anybody remembering to add it.

`_ui_size()` returns the DESIGN size and never the live viewport. A screen that measured the
viewport would space its rows twice as far apart in a 640x360 world and put its help line off the
bottom - and every layout gate, which measures at 320x180, would still pass.

**A save records TILES, and that is a v10 migration.** `SaveData.tile` replaced `position`, and
the RENAME is the point: a style decides how many pixels a tile is, so a file recording pixels
describes a place only while nothing about the art changes - the demo's move to 32px tiles would
have put every existing save half way to where it was written, silently, on a map that still
parses. `Migrations.PRE_V10_TILE_PIXELS` is FROZEN at 16 (a historical fact about files on disk,
never a reading of the live style). `GameState.tile_size` is written by the world on entering a
map and by nothing else. `enter_map`'s third argument is therefore in TILES: only `restore()`
passes it, and `restore` cannot know the destination's tile size before the map is loaded. It
ends with `set_player`, because `from_save` converted with the size bound BEFORE the load - a
different number at a change of style - and that is the one line making state and body agree on
the frame the load lands. **A test of that guard must CROSS sizes and await no frame**: a load
that begins and ends at 32px gets the right answer by luck, and the physics tick would repair it
one frame later. Both traps were measured; the second showed up as a surviving mutant.

**`NpcBrain`'s arrival margin is per TILE**, because what "close enough" means is set by how far
a body travels in a frame. `1.5 / 16.0` is exact in binary, so a 16px map still gets precisely
the 1.5 every shipped session was recorded against. `Qa._assert_position` reads
`GameState.tile_size` rather than a literal, and the `tile_size` step key is GONE: a session
stating its own would keep passing after a map changed style, reporting on a tile that has moved.

**A fighter is drawn at `SPRITE_SCALE / world_scale`.** `BattleScreen` is a CanvasLayer already
drawn at the world's scale, so a bare 2.0 would put a 64px cell 128 pixels into the 180 the
layout was measured for. Derived rather than a field on the style, because it is a property of
THIS SCREEN's bands - the capacity `MAX_PARTY` and `MAX_FOES` are declared against. Do NOT assert
that two styles put a fighter on the same FRACTION of the screen: the cells are different shapes
(24 rows on a 16px tile, 64 on a 32px one), and that would be the template deciding a proportion
that belongs to whoever draws the characters.

**A game's maps must agree about `world_scale`, and `test_map_content` refuses it.** Two scales in
one game is a window that resizes under the player as they walk through a door, and every screen
would be correct on both sides of it. The same suite carries the NPC half of the per-placement art
check - enemies have had one since M13 and the people standing still never did. A character with
no sheet under the map's style is not an error a player sees as one: the body is still there,
still solid, still stops them walking north, and invisible.

**`MapData.path_of` is the one place a map id becomes a path**, and `MapData.root` is a var so a
suite can point the world at `tests/fixtures/maps` without a 32px room shipping as content nobody
plays. Move it AFTER instantiating the scene, never before: `_ready` boots the shipped game, and
with the root already moved that boot hunts for the quest's start map in the fixture directory,
fails, and leaves the half-built map it had already made behind. Six orphan nodes, no error, and
every assertion still passing - caught only because the suite's orphan baseline is zero.

**The demo is drawn in imported LPC art, and its config numbers are DOUBLE the template's.**
`data/game_config.tres` says 96 px/s, 24px of reach, a 20x12 body and a footfall every 28px -
each of which is the same distance in TILES as the template's default on a 16px map. That is
why all 23 scripted sessions, whose legs are counted in frames, play out unchanged. A
`GameConfig` stated in tile units would remove even that, and is recorded as deferred.

The cast is eleven recipes under `docs/lpc_designs/` plus the wanderer. **A creature is a human
body wearing a beast head**, because LPC has no non-human body at all: the Slink is the CHILD
body with a lizard head and tail, the Gloom an ordinary body in the palette's own zombie green
under a charcoal cape. The first Gloom used the zombie BODY and was wrong on sight - pale, bare
chested and blood spattered. **Look at a composed character before it ships**; three of the
twelve were re-cut after their previews and none of the three was visible to any gate.

**A definition may be DRAWN off its material's base**, and says so with its own `base`
(`ulpc.green` for the lizard, `ulpc.zombie` for the undead, `lpcr.ivory` for the farm heads).
`LpcCompose` reads it: remapping those from the material's default takes human skin as the
source, finds almost none of it in the art, and changes almost nothing - a recolour that
silently does not happen, on exactly the layers a monster is made of. A scheme this composer
does not fetch is refused BY NAME rather than treated as a variant of the one it did.

**An imported cast shares a ground line PER BODY TYPE, not across the cast.** Every sheet
carries its own measured anchor and every character is placed by it, so their feet land on the
origin whatever row that is; demanding one row across the cast asks the LPC artists to draw four
bodies identically, and they do not - the female and teen bodies sit one pixel lower. So the
rule is the two halves that bite: exact within a body type, and within `MAX_GROUND_SPREAD`
across all of them, which is what catches a trailing cape measured as the ground.

**The battle file's stagger is a fraction of how wide a fighter DRAWS.** 18 and 14 were chosen
against a 16x24 cell at twice size; at a 64px cell they put one character in front of another
with a face over its shoulder. `STAGGER_WIDTH` is the width they were chosen for, so at that
width the numbers are exactly 18 and 14 and every layout measured before this is untouched.

**A suite that names the demo's style or tile size goes stale as a REFUSAL.** The editor
round-trip suites spelled `dusk16` into their coupling checks, so the day the maps changed style
every one of them reported every map as painted against the wrong bank - a true-looking failure
of the translator. They read the map's own style now. Same for `test_world_npcs`, which built a
test brain at 16 and worked out its waypoints at 16: the pair cancelled, and the suite was
passing against a world drawn at neither size.

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

**Both sides are a LIST, and one map record names the formation.** A record keeps its `enemy`
and gains an optional `group`, so the body you walk into is the first foe and the rest ride with
it - Super Mario RPG's shape, where one touched sprite opens a formation the ROM already knew
about. **A formation is an ordered list and DUPLICATES ARE THE POINT** - two slinks are two
slinks, and "3 Slimes appear!" is the genre's commonest crowd. `_formation_of` therefore appends
through `_add_foe` and not through `_add_ref`, which deduplicates because `enemy_refs` wants each
name once. M28 shipped that collapse and no gate saw it: the only formation it authored was a
slink AND a gloom, so no same-species pair existed to come out short until M29's hollow. Adjacent records never merge into one fight: EarthBound does that and its own manual says
"occasionally", which would make a fight's composition a roll over where wandering bodies happen
to stand. ONE RECORD IS ONE ENCOUNTER - one seen key, one seed, whatever the count - and a fight
of one is a formation of one, so nothing downstream needs a branch. "Fights are solo" was never a
convention this template honoured; Dragon Quest I is the only reference that fights one at a
time, and it was a scope line that M28 retired.

**Every living foe takes a turn, after the whole party has gone.** Each behind its own defend
cue, each drawing its own target - which is every reference game's rule, and the cost is that a
formation of three is three blows to defend against in a round. No reference skips an enemy's
attack for pacing, so the relief is the CAP: `BattleScreen.MAX_FOES`, enforced on content the way
`MAX_PARTY` now is. Sleep is per foe (FF1's sleepers each roll their own wake), the award SUMS
the formation, and any boss in it refuses the escape - unfleeability is a property of the
encounter rather than an average over its members.

**The FOE cursor is the ALLY cursor mirrored, skip and all.** It opens over the living foes when
there is more than one, and is skipped outright when there is not - which is Super Mario RPG's
own rule ("if there is more than one enemy") and what keeps every fight this template already
shipped pressing the same keys. `Order` carries `target` for allies and `foe` for foes as two
fields, because a single signed number is a decode every reader has to remember and the one who
forgets aims a heal at member 1. A stale target cannot happen here: the cursor lists the living
at the moment it opens and the blow lands on the same beat, so FF1's "Ineffective" - its most
complained-about behaviour, and a consequence of entering commands first - is unreachable. That
is M27.1's round shape paying for a rule this template never has to write.

**The two seeded streams stay two**, drawn in foe order, so a fight of one draws exactly what it
drew before and every shipped session replays byte-identically with no compatibility branch. A
foe dying or sleeping shifts the draws of foes AFTER it within that fight, which is deterministic
in the seed and the inputs - all the replay guarantee ever claimed.

**A spell's target shape is data.** `SpellDef.Target` is `ONE` or `ALL`, and `ALL` is legal for
an ATTACK only. Groups and multi-target magic arrive together in the genre - DQ1 has no group
spells because it has no groups, and DQ2 introduces both in one game - so the field arrived with
formations rather than before them.

**The foe bars are a stated divergence.** No reference game shows enemy health at all: FF1 lists
names in their own box, DQ2 shows names and a living count, Super Mario RPG charges a whole turn
to peek. This screen has drawn a numeric bar for its single foe since M13 and been played that
way ever since, so it extends per foe rather than being removed. `docs/DECISIONS.md` carries the
fork and the genre's own answer as the deferred alternative.

**A fight sized for two must be unreachable by one, and that is a MAP rule.** M29 made every
ordinary encounter a pair and gave the boss an escort, which quietly turned a declinable
companion into two games of which only one was balanced: alone, a mashing player dies to the
first pair and a player who times every press still loses to the Keeper. So both roads out of
the village carry `requires_flag: rook_joins` + a `locked_dialog`, the shape the barred keep gate
has used since M12 - and the genre's own answer, since Dragon Quest II hands you the Prince
through the story. `test_battle_content` derives the guaranteed party from the WARP GRAPH rather
than from the manifest: a member who joins on a flag counts only if there is no route to that map
without it, and the balance gate fights with exactly that party. Before M29 that correctly
returned nobody. **The rule generalises past this game: whenever content assumes a capability,
something has to make the capability unavoidable, and the assumption belongs in a gate rather
than in a designer's head.**

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

**A member acts the moment they choose, in party order.** Choose Attack and that member SWINGS;
the turn passes to the next standing member only once the blow has landed, and the enemy goes
after all of them. M27 shipped FF1's command-all-then-resolve instead - every member declares,
then the round plays out - and the first person to play it rejected it at the controls: a press
that visibly does nothing reads as a press the game missed, however faithful to the manual it is.
Super Mario RPG is the genre's own precedent for the shape that replaced it. Order is still PARTY
order and not a stat, because a replayed fight has to draw the same numbers in the same places.

That collapse deleted three things rather than moving them: the declaration queue, the `cancel`
that took an order back (there is no previous choice to unwind once each one has already
happened, so a menu `cancel` is refused for EVERYBODY, which is the pre-party rule restored), and
the re-checks that asked whether a queued cast could still be paid for - confirming and acting are
now the same frame, so that gap cannot open. `_commander` therefore holds the turn through
choosing AND swinging, which is what lets the view mark one member the whole way rather than
losing them at the press; it goes to -1 for the enemy's turn so the mark can move to the target.
Each member's ATTACK still gets its own cue and its own first-press-only capture; a cast still has
no window.

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
still time to press. `BattleScreen.MAX_PARTY` and `MAX_FOES` are the capacities the view DECLARES,
the layout audit measures against AND the content gate refuses data for; a party of one draws
exactly the layout that shipped. M27 declared the first of those and enforced nothing - the
layout was audited at capacity, which proves the drawing and not the data - and M27.1 found the
claim overstated. Both halves of the M13.3 rule now hold, on both sides.

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

**An element is a percent in the data, and the fight multiplies ONCE.** `SpellDef.element` is
an open string (empty means elementless and lands at face value); `EnemyDef.resistances` is
element -> percent taken, where 200 burns, 50 shrugs and 0 is untouched. An open vocabulary
because the template never branches on "fire" - it looks the word up in the foe's own map - and a
closed one would be this template picking the elements of every game built on it. Percents rather
than tier words for the reason every number here is data: `weak` would put a bare `* 2` in a
script, and it would cap the genre at two tiers when the references run from quarter damage
through immunity. An entry of exactly 100 is REFUSED rather than allowed as a no-op - it reads
like a decision and changes nothing, so it is a typo or a note belonging in a comment.

`_spell_damage` is the one place the multiply happens, called by both arms of the attack branch.
Two arms each doing it is the `_attack_of`/`_defense_of` shape and the same failure: the copy
somebody forgets is a weakness that works when you aim and silently not when you sweep, which
reads as the spell being broken. Damage is floored at 1 wherever the element does not stop the
spell outright, so *resisted* and *immune* stay things a player can tell apart - 1 power halved is
0 by integer division, which would collapse them - and a zero SAYS so.

An element is legal on an ATTACK only: a heal has no damage for a resistance to scale, and a
field nothing reads is how a data file comes to describe an effect the fight never applies.

**A weakness and a resistance are ANNOUNCED, and a neutral hit is not.** The genre splits here
and **the split tracks the arithmetic**: Pokemon multiplies and announces every non-neutral hit;
Dragon Quest's resistance is a CHANCE to negate outright, so only the failure needs words; Final
Fantasy I multiplies (1.5x weak, 0.5x resist - not the doubling everyone quotes) and says nothing
at all, its whole 35-entry battle-message table holding no elemental string. This template
multiplies, so it announces: a bare damage figure cannot tell a player whether 12 was big,
because they have nothing to compare it against on the turn it happens. FF1 is the outlier that
proves the rule rather than the precedent that excuses it - its elemental system also shipped
half-broken. A SWEEP gets no clause, and that is the same rule: its caption already names what
each foe took side by side, so the comparison is in the numbers. See `docs/GENRE_CONVENTIONS.md`
S13b, which is research rather than recollection - the FF1 and Pokemon figures come from
disassemblies of the shipped ROMs, because the wikis were bot-blocked.

**The two halves live in different directories and are joined by a bare string**, so
`test_battle_content` requires every element a resistance answers to be one some shipped spell is
made of. A typo on either side is a pairing that silently never fires while both files stay
individually valid - the fight just applies 100% and nothing anywhere complains.

**The balance gate PLAYS all of this, as of M34, and before that it could not see any of it.**
`BattleDriver` only ever chose Attack - and beneath that, `BattleHelpers.party_of` handed the
balance party an EMPTY spell page, so the fights the gate played did not contain magic at all.
Two layers, and the lower one is the worse: a gate that reports on a fight the game does not
contain is worse than no gate. `Policy.CASTER` casts, the party resolves its page through the
same `SpellRow.page` the world calls, and three assertions ride on it - a casting party still
wins every shipped fight, every shipped spell is cast somewhere, and **every shipped resistance
is TOLD to the player somewhere**. That last is `demo-must-show-the-feature` as a gate: the
cross-content check proves the two halves NAME the same element, and this proves they MEET.

**Each verb policy adds exactly ONE page, and the other stays a fault.** `CASTER` casts and
`DRINKER` uses items - named for Final Fantasy I's own third command, whose menu is Fight /
Magic / DRINK / Item. `SPELLS` is still a fault for the drinker and `ITEMS` still one for the
caster, which is what keeps a report about the verb it is named for rather than about whatever
the menu happened to open. Each chooses its row at the MENU and falls back to Attack, because a
cancel has been refused for everybody since M27.1: a driver that opens a page it cannot act on
presses a dead row forever and HANGS the gate rather than failing it.

**`ItemRow.bag` is the one place a battle bag is filtered**, on `SpellRow.page`'s terms and for
its reason. `battle_heal` doubles as "does this belong in the fight menu at all", so a second
implementation of that predicate is a second opinion about which items are safe to spend - and
the one that drifted would put a quest item on the menu, where using it appends the same
take-effect a tonic does. **That guard had no test at all until M35**, and the failure it
prevents is a key destroyed and a door shut for the rest of the run, hours before the player
finds out. `test_nothing_a_player_needs_can_be_drunk_in_a_fight` asserts both directions over
the whole catalogue.

**The balance fights keep an EMPTY bag.** `_fight` takes items as a defaulted argument and every
difficulty assertion leaves it out: a party carrying nothing is the pessimistic one, and a
formation it beats is one the real player beats. Only the item-driver tests pass a bag, and they
assert COVERAGE rather than difficulty.

**AIM IS A POLICY AXIS, exactly the way skill is.** PERFECT finishes off whatever is closest to
falling; CASTER spends its scarce magic on whatever will take longest to kill. With both drivers
finishing the weakest first, a boss standing behind two mooks is never the target of anything
while resources last - so every rule that only shows up when you hit the BIG one is unobserved
by a suite that looks exhaustive. The Keeper's answer to fire was exactly that rule.

**`SpellRow.page` is the ONE place a spell page is derived**, and it takes defs rather than
reaching for them, because `BattleLogic` may not name an autoload. The world does the Registry
lookup and the balance gate reads the files; both then call the same filter. A second
implementation of "which spells has this level reached" drifts silently, and the gate would be
balancing shipped fights against a page no player is handed.

**A SWEEP SAYS ONE LINE PER FOE, and the first half of each is the same one.** No reference game
composes a sentence naming several targets; every one loops a short single-target message
instead, and Final Fantasy I's own comment for the routine between targets reads "clears all
drawn combat boxes except for 2: the attacker and the spell". So the caster and the spell hold
still while the target half cycles beneath them - FF1's persistent frame, expressible here only
because the caption has two lines. `_say_each` queues them and `_leave_message` drains the queue
BEFORE honouring `_after_message`: the queue paces the telling and decides nothing about the
turn.

That deleted a special case rather than adding one. M34 gave a uniform formation a single
combined verdict, because a caption listing identical numbers can say nothing useful - and the
content gate needed a matching branch to attribute a clause naming nobody. Both are gone: every
clause now sits in a line that names its own foe. **When a research finding argues against
something already shipped, the replacement that DELETES a case is the one to trust.**

A winning sweep reports what it did, which it did not before - the victory line replaced
everything, so the cast that decided a fight explained itself least. `_win` is split into
`_award_victory` (the outcome, the xp, the seal) and the telling, so the per-foe lines play and
the victory is last.

**Five spell kinds, and a cast has no timing window.** `SpellDef.Kind` is `ATTACK | HEAL |
SLEEP | BOOST | SAP`, closed the way `ItemDef.SLOTS` is, and APPENDED to rather than reordered -
a `.tres` stores an enum as the integer it was written as, so inserting a kind re-labels every
shipped spell. More than two because every reference game ships a non-damage, non-heal effect
among its FIRST spells - Sleep is tier one in Final Fantasy, and Dragon Quest 1's whole
eight-spell list still has it. An ATTACK deals FLAT damage
that ignores the enemy's armour, which is what gives magic a job beside a stronger swing; the
timed press stays a property of SWINGING, or the whole fight becomes one reflex test and the
menu decides nothing. `Row.MAGIC` sits between Attack and Item - every reference game's order,
and the row every counting test and play session below it had to move for. A cast the purse
cannot cover is refused, SAID and costs no turn (money's precedent), and `can_afford()` is the
one function the screen dims by and the press refuses by, so the two cannot disagree. There is
no targeting step: fights are 1v1, so an offense spell hits *the* enemy.

**A status is battle-only, counted in turns, and points BOTH WAYS.** One `Status` holder rides
both `Fighter` and `Foe` - the same fields, the same tick, the same fold - because a party
member and an enemy being afflicted differently is how one side quietly stops expiring.
EarthBound's Assist branch is one branch doing both ("boosting or weakening the stats of an ally
or foe ... or inflicting a status ailment"), so this is the genre's shape rather than a
convenience. `BOOST` aims at an ally and `SAP` at a foe: two verbs, never one signed `power`,
which is `Kind.UNEQUIP`'s argument - a verb spelled as the absence of its opposite is a decode
every reader has to remember. An `EnemyDef` move carrying a `status` afflicts INSTEAD of hurting,
and `problems()` refuses one that tries to do both, because a single defend cue cannot answer
two questions.

**Durations are STATED and expire with the fight.** Dragon Quest rolls its ranges (Buff 4-6, Sap
6-9) and this template does not: M13 made flee odds and damage variance deterministic so a
designer can reason about a fight and a QA script can replay it. A turn is counted at the top of
the holder's OWN turn, where `asleep_turns` has always been counted - so a shift of one covers
the enemy's answer and a shift of two also covers your next swing. Nothing is saved, nothing is
migrated, and `BattleLogic` still writes nothing; persistent affliction is a milestone of its own.

**Four contributors reach two numbers, so `_attack_of`/`_defense_of` are the ONLY places either
is assembled.** The level curve, worn equipment and a status shift all feed attack and defense,
and before M30 each hit resolver added its own two up. A third contributor is exactly when that
stops being safe: the copy somebody forgets is not a crash, it is a buff that works when you
swing and not when you are swung at, which reads as the spell being broken. A guard is floored at
nought rather than allowed to invert - a sap deep enough would otherwise make a blow land for
more than it does on an unarmoured target.

**A well-timed guard SHRUGS AN AFFLICTION OFF ENTIRELY**, where a timed guard against a blow only
halves it. All-or-nothing because there is no half of being asleep, and because a cue with
nothing to do would quietly become decoration in exactly the fights built on statuses. A sleeping
party member is skipped by `_hand_turn_to` the way a sleeping foe is skipped by
`_begin_foe_turn`, and SAYS SO: a turn that passed in silence reads as a press the game dropped,
which is the complaint that killed M27's round shape.

**The battle caption APPENDS a status tag and keeps its numbers.** Final Fantasy I overwrites the
HP readout with `POIS`/`STON`/`DARK` because its block holds one number and no more; this one has
a caption line AND a bar, so keeping both is the honest adaptation rather than the faithful one.
`Row.STATUS` gains nothing at all - a battle-only effect cannot be true while the pause menu is
open, and a line there would describe a system the player can never catch in the act.

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

**WHERE a game may be saved is an axis, and `save_policy` is the whole switch.**
`GameConfig.save_policy` is `anywhere` (the pause menu's Save row, Pokemon's shape) or
`at_point` (that row is gone, and the `open_save` dialog effect is the only way to write one -
Dragon Quest's king, Final Fantasy's inn). It is the `grid_step_pixels` shape one layer up: a
StringName checked against `SAVE_POLICIES` rather than an enum, because a `.tres` stores an
enum as the bare int it was written as and a third policy later would re-label every shipped
config. A typo'd value FAILS THE BUILD - the npc `behavior` rule, and for its reason: a policy
that silently reads as `anywhere` is a save point nobody can find beside a Save row nobody
removed, and both halves look correct on their own.

It governs WRITING only. Loading stays a pause-and-title verb under both, because a game that
makes saving a journey does not also make quitting one. The row is HIDDEN rather than refused:
a capability the game does not have is the `requires_item` case, which hides, not the
`spend_gold` case, which quotes a price out loud and says no.

**Hiding a row means the cursor index is no longer the Row.** `PauseMenu._top_rows()` is the one
place that list is derived and `top_row(at)` the one place a cursor is turned back into a Row;
`confirm()` and the view's `_label_for` both go through it, or the drawing and the pressing
disagree about which row is the fifth one. With saving on, the list IS the enum - which is what
leaves every test and session that lands on a row by naming it (`move(Row.SAVE)`) pressing
exactly what it always pressed. The world answers `_saves_from_the_menu()` and hands the menu a
BOOL, never the policy word: knowing what `at_point` means is a config question and `PauseMenu`
may not ask one - the `_status_lines`/`_gear_rows` precedent.

**A save point is a `Router` state of its own, and `SaveMenu.confirm()` inverts the rule every
other slot list follows.** `PauseMenu` and `SlotMenu` both REFUSE a slot with nothing behind it,
because both are about loading; the same guard on a save page is the bug, since a first save is
aimed at exactly the row those two turn away. A damaged slot is writable too - `save()` parks
whatever it overwrites either way, and refusing would strand a player whose only slot went bad.
`SaveScreen` is a window over the live world (the counter's rule: a save point is somewhere the
player walked to) and draws its rows through `PauseMenu.slot_label`, the one place a slot has
ever been put into words. Its own state rather than the pause menu jumped to a page, because a
priest does not hand you your equipment.

`OP_SAVE` is opened DEFERRED, the `OP_SHOP` rule and for its exact reason: `_on_dialog_closed`
applies effects and THEN pops the dialog overlay, so a screen opened inline is the one that pop
closes - it lands the machine in `dialog` with an orphaned screen behind a finished
conversation, and nothing errors. Only a test that stages a REAL dialog close can tell the two
apart; the save-point tests that open the effect directly pass either way.

**A save point heals NOTHING, and that is research rather than taste.** Every free save point in
the genre restores nothing - Dragon Quest's king, Dragon Quest IV's church, EarthBound's
telephone (structurally: no HP-recovery opcode appears in any of the ROM's five save scripts),
Chrono Trigger's save points (the purchased Shelter heals, not the point). The one that heals
fully is Final Fantasy I's INN, a PAID rest that also saves - which is why a game wanting that
shape puts `open_save` on the innkeeper's yes beside `spend_gold` and `rest`, three keys on one
choice and no new mechanism. The demo's village already charges four gold for a bed; a free full
heal beside it would make the innkeeper a mistake. See `docs/GENRE_CONVENTIONS.md` §8, which is
binary-derived because three of these wikis are bot-blocked and one is paywalled.

**A shipped NPC is a WALL, so a new one is placed against the sessions.** The chronicler stands
at village [1,2] and is `static`, and both facts are load-bearing: several sessions use bodies as
stops, and `write_it_down.json` uses HIM as one - north out of the spawn is stopped by the
warden, west by the map edge, north again by the chronicler, so the whole walk arrives facing him
with no counted leg anywhere. A wandering save point would break sessions that look unrelated.

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
names none. FOUR callers need that exact answer (entering a map, a fanfare handing back, a
fight ending, and a defeat), and written out four times it is four copies of "a map states its
music or states silence, never inherits" with one of them eventually stale.

**A defeat plays `GameManifest.game_over_music`, and the fact that it used to play NOTHING is
the cautionary tale in this file.** The branch called `stop_music()` under a comment reading
"every game this borrows from cuts the music at a game over". That is false - Final Fantasy I
ships "Dead Music" in 1987, and each Final Fantasy since has its own game-over scene; the
references CHANGE what is playing at a death rather than falling silent. A wrong genre claim in
a code comment is more durable than a gap, because a gap invites work and a claim invites
citation, and this one sat exactly where anyone would look before touching the branch. The rule
that would have caught it is already in section 1: research the surface before building it. Empty
is still legal and is still the old behaviour precisely, which is why every session recorded
before M32 hears the same silence.

**A fight's music can be named by the ENEMY, and the first foe that states one wins.**
`EnemyDef.music` outranks the manifest's `battle_music`, scanned in the formation's own order -
so a boss escorted by mooks is a boss fight wherever the escort was written down. On the enemy
rather than behind the `boss` flag because the references disagree about which fights get a
second theme (Dragon Quest I reserves one for the Dragonlord, Final Fantasy I has none and plays
one theme even for Chaos, Final Fantasy IV plays one for nearly every boss), and a template that
decided would decide for every game built on it. `boss` means "cannot be fled" and fusing the two
would make a themed duel unfleeable to get its music.

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

**The edges are also walked in SEQUENCES, and a failing walk is shrunk before it is reported.**
Per-edge checking builds a world, drives one action and throws the world away, which is silent
about anything that only goes wrong the SECOND time - it found a pause screen and a shop screen
that were closed but never freed, and that went on eating the very key that opens them. So six
seeded walks of twenty-four steps run on ONE world that is never rebuilt between steps, asserting
the same trace and the same invariants after every step. `FlowWalk` (`tests/helpers/`) is pure -
a walk is a list of edge indices - so the planner and the minimiser are unit-tested with no scene
at all, and the minimiser is driven from OUTSIDE (offer a candidate, be told whether it still
fails) because only the suite can run one. **Cycle elision is the shrink move**: deleting the
steps between two positions in the SAME state is the one edit that cannot disconnect a walk, so
every candidate is drivable and a failed re-run means exactly one thing. It earned itself on the
first bug it saw, cutting a 24-step walk to `continue, open_pause, close_pause, open_pause,
close_pause`. Coverage is ASSERTED - every walkable edge must be driven by one of the seeds, or a
walk that never reaches a game over reports green about defeat.

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
silent read - drawing a menu must not park files or announce loads - and it returns a
`SlotSummary`, so an unreadable slot draws as *damaged* rather than as *empty*. It used to
collapse both into one null, and "empty" is the one wording that invites saving over the row;
`save()` parks whatever it is about to overwrite either way. ONE object rather than an
`Array[bool]` beside the saves, because two paths answering one question drift and the drift
pairs one slot's data with another slot's verdict. The load page needed no change at all - it
already refused anything with no data behind it, and only the wording was missing. Escape opens
`PauseMenu`/`PauseScreen` from `WORLD` only. `restore()` is the
single path from a save into a world (`from_save` then `enter_map`), and `enter_map`'s third
argument is a restored position that nothing else passes. A `--qa-script=` run saves under
`user://qa_saves`, wiped at boot, so a play script neither reads nor overwrites real progress.

**`move_and_slide()` picks its own delta** — the physics one inside a physics frame, the idle
one otherwise (pinned in `test_engine_assumptions.gd`). So never compute how far a call will
move something: end an operation by observing that it finished. This is also why the
integration suites can drive `apply()` by hand from a coroutine at all.

**A map can be authored in an EDITOR, and the conversion is build-time.** `TiledMap` (and LDtk
beside it) translates between this template's legend-and-ASCII map format and an editor's, both
ways, as pure Dictionary-to-Dictionary with no file access - which is what lets the round-trip be a
unit test over the six maps the game already ships rather than over an invented fixture.

**Nothing new ships.** The committed artifact stays the native JSON, so a map authored in Tiled
arrives as the same file every other map is and still diffs as a picture in a pull request. That is
the sprite generator's shape exactly: author in the tool, run the generator, commit the output, and
a drift gate proves the committed output is what the tool now produces. Parsing an editor format at
RUNTIME would put a second shipped format behind `MapData.load_from` and give up the readable diff
for nothing, since the editor never reads the committed file anyway.

**THE TILESET IS A COUPLING AND IT IS CHECKED.** An editor stores a tile as an INDEX into a tileset
image, so a map painted against one bank and read against another is not a broken file - it is a
map full of the wrong tiles, and every other gate here would pass it. `problems()` refuses a
mismatch by NAME and by COUNT, so reordering `data/tiles/*.json` is a loud failure rather than a
silently redecorated map. Mutants cover both, plus dropping `firstgid` (every tile off by one).

**THE GRID IS THE SAME COUPLING IN ANOTHER UNIT, and it was wrong for four milestones.** Every
coordinate in either editor's file is in PIXELS - a record is written at `tile * tile_size` and
read back by dividing - so a file painted on one grid and read on another puts every record at a
fraction of its own tile, on a map that still parses. `map_io.gd` held a `const TILE_SIZE := 16`
and handed it to BOTH directions, so `--verify` round-tripped every map back to itself while every
exported file declared a 16px grid over the demo's 384x32 atlas: an editor slices that into quarter
tiles. **A constant both directions of a round trip share is invisible to that round trip.** The
size now comes from the generated `tiles.json`, beside the ids and for their reason, and
`problems()` refuses a declared grid that disagrees with the size the caller will read at (zero
means "no table to hand", the only case that skips the check).

**`tests/unit/test_map_io.gd` runs the COMMAND and reads what it wrote.** `--verify` is a step
inside `check.sh`, which no mutant can be judged by; this suite spawns the engine the way
`test_ci_paths.gd` spawns bash, exports both formats to `user://`, and asserts the declared grid
and the atlas beside them. Five mutants ride on it - the table's size, both translators' refusals,
and both writers' declared grid. No `--fixed-fps` on that spawn: `map_io` quits in its first frame.

**Tiled has no array property** - its types are string/int/float/bool/colour/file/object/class - so
a record field that is an array (a patrol `path`, a formation's `group`) travels as JSON behind a
marker. Scalars deliberately do NOT: they become real typed properties, which is the entire point,
since editing `dialog` or `dwell` in the side panel is what the editor is for.

**The round-trip is checked TWICE**, because equal-to-the-original is necessary and not sufficient -
both directions could be wrong the same way. Once that what comes back describes the same map, and
once by asking `MapData` itself whether it parses and puts every tile where it was.
`MapData.from_dictionary` (split out of `load_from`) and `JsonFile.of` exist for that second check.

**Compare the RESOLVED map, never the bytes.** An editor file carries no legend, so the importer
assigns characters as it meets tiles; two legends can spell the same map differently and both be
right. And **JSON has no integers** - a coordinate read off disk is `5.0` and the same one built in
code is `5` - so the comparison normalises the numeric TYPE on both sides rather than the
translator faking floats.

**The sprite contract is PNG + `<name>.sheet.json`.** Nothing engine-specific is committed
as art: `SpriteFramesFactory` turns that pair into a `SpriteFrames` at runtime. This is the
seam that lets a procedural rig, a downloaded pack or an AI generator feed the same game.

**A style's sheets come from the rig or from an IMPORT, and `sheets_from` is the whole switch.**
`SpriteStyle.sheets_from` is `rig` (the procedural generator, composed per `CharacterSpec`) or
`lpc` (sheets the Universal LPC Spritesheet Character Generator exported, converted by
`LpcImport`). The `save_policy` shape exactly: a StringName checked against `SHEET_SOURCES`, a
typo fails the build, and the two arms are stated as a PAIR - an imported style must name NO rig
and MUST list its `licenses` - because "an empty rig_id means imported" is the decode nobody
remembers. Both arms run inside `tools/gen_sprites.gd`, so `--verify` drift-gates imported output
with no new check.sh step, and the tiles are drawn the same way for both.

**The input is the generator's own two files, and the folder is the spec.**
`data/imports/<style>/<character_id>/sheet.png` + `character.json` - "Download PNG" and "Export
JSON", unmodified - under a `.gdignore`, so the editor never imports an 832x3456 input and the
exporter never packs one (`test_imported_art` pins the marker; `pack_check.sh` proves the
outcome, and `strings index.pck` shows zero `data/imports` entries). No `CharacterSpec` for an
imported character: the folder's name is the id, the way a `.tres`'s id is for a rig one.
Everything known about LPC's layout is a CONSTANT in `LpcImport`, measured from the generator's
source rather than remembered: 64px frames, 13 columns, every animation at a FIXED row whatever
was enabled (walk is always rows 8-11, so a sheet is addressed and never searched), rows within a
block running up, left, down, right - NOT this template's order, so the walk block is RE-CUT into
canonical rows rather than relabelled - and frame 0 the standing pose. Idle is that standing
frame, as the rig's is: the generator's own idle rows are drawn for only some assets, and a hat
that vanishes when a character stops walking is worse than no breathing.

**A licence is a GATE, and a family never prefix-matches.** Every layer file the export names
carries the licences its artist chose; `LpcImport.problems()` refuses a file offering none of the
style's `licenses` families, naming the file and the licence. Families are matched with the
version dropped (`"CC-BY-SA 3.0"` -> `CC-BY-SA`) and compared WHOLE, because `CC-BY` is a prefix
of `CC-BY-SA` and share-alike is exactly the term a prefix would wave through. The generator
writes `credits.json` beside the sheets (every file, artist and URL, merged and SORTED so the
drift gate can compare it; it is a resource, so it ships in the pack for a credits screen to
read) and `LICENSE.txt` (repository-facing; a `.txt` is not packed). One CC-BY-SA layer makes the
composed sheets CC-BY-SA and the notice says so. **The demo's `lpc32` accepts both buckets** -
CC0/CC-BY/OGA-BY and CC-BY-SA, the user's call with the terms explained - so its sheets ship
share-alike and an in-game credits surface is owed (M40 phase C).

**An imported style leaves the rig gates and enters its own, and membership is asserted as a
SET.** `ArtFixtures.rig_style_ids()` and `imported_style_ids()` together must equal every style
on disk (`test_gates_consistency`), so a third kind of source cannot opt out of both. The
consistency gates draw every frame through the rig and cannot draw an import; `test_imported_art`
asks what CAN be asked of art the template did not draw - output that describes itself, one
ground line across the cast, every layer credited under an accepted licence, the inputs kept out
of the pack, and committed output matching what the converter produces NOW (the drift gate as a
test, which is also what makes a mutant of the converter visible). A palette rule would be
meaningless there: the pixels are the artists', not the style's.

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
- Autoloads outlive a suite: call `GameState.reset()` in `before_test`. **So does the root
  WINDOW**, which a 32px style grows to 640x360 - `world_scene._exit_tree` puts it back as the
  scene leaves the tree, because eleven suites boot a world and the one that remembered to
  restore it in `after_test` was the only one where the rule was true. A shared global asserted
  at an arbitrary point in a run is order-dependent by construction, and suite order is sorted
  on APFS and hash-ordered on ext4: that combination passed locally every time and failed on the
  runner about half the time.
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
- **A rule the shipped content cannot distinguish belongs in a suite of its own.** Two driver
  rules survived mutation against the content suite and neither was dead code: the shipped bag
  EMPTIES, so a driver that only ever wants the first row still exhausts that stack and reaches
  the next, and one that drinks at full health still stops when there is nothing left. Read a
  survivor as "the content masks it" before "the guard is decoration" - `test_battle_driver.gd`
  exists for exactly that, and pins those rules against a bag that outlasts the fight.
- **A fight cannot stage "nobody is hurt", and a deep bag is deeper than you think.** A move with
  zero power still lands the enemy's ATTACK stat, so there is no harmless foe to fight - pin such
  a guard on the DECISION rather than on how a whole fight comes out. And 99 of an item was not
  enough: the fight outlasts them, so "both were eventually used" is satisfied by a driver with
  nowhere else to go. Assert the CONSECUTIVE pair - the second use differs from the first - which
  no fight length can mask.
- **`assert_foe_hp` is how a session proves HOW MUCH a blow was worth.** An element's whole
  effect is the size of a number, and every other reading is blind to it: the magic spent is the
  same whatever it hit, the fight is won either way, and no session reads a caption. So a shipped
  weakness with no `assert_foe_hp` behind it is a feature nothing would notice the loss of.
  Battle-only, for `assert_status`'s reason. **Aim it by reading the map's record**, not by
  assuming: `the_pair` names a slink AND a gloom, so foe 0 is the slink - a first draft aimed
  there and failed with the slink's arithmetic (10 - 7 = 3), which is correct behaviour and the
  wrong target.
- **`assert_status` is how a session proves WHICH spell was cast.** A cost cannot: three of the
  demo's spells cost 3 magic, so "the pool went down by three" is satisfied by whichever row the
  cursor happened to land on - a mutant moving the spell under test past the level cap passed a
  session asserting only that. Assert the effect that is UNIQUE to the path, and note the read is
  battle-only, because a status cannot outlive the fight it was got in.
- **A scripted fight is won with `fight_well`, never with counted waits.** The op confirms
  through every menu and presses inside every timing window - the scripted twin of
  `BattleDriver.Policy.PERFECT`, reading `BattleScreen.cue_on()`/`choosing()`. Landing timed
  hits by waiting a computed number of frames between presses is chained arithmetic over the cue
  and message lengths, and it describes ONE fight shape: M29 changed the Keeper from a duel to a
  trio and every such chain stopped ending the fight, half a script away from what moved.
  `press_until_state` is the opposite and is still right for playing BADLY on purpose - only the
  first press of a cue counts, so mashing never lands one.
- **Authoring a session by SLICING another one cuts on the step that opens the leg**, never on a
  repeated marker. Taking "everything up to the last `assert_state battle`" kept the source
  script's own spell leg, so the new script's cursor landed two rows off and cast the wrong
  spell - and every assertion still passed, because the two spells cost the same. Slice on the
  note or the walk that BEGINS the part being replaced.
- **Select the last row of a page with one press UP, not N presses down.** Counting is what
  CLAUDE.md already warns about for suites, and it is worse here: a QA script has no enum to
  name, so a miscount is silent. Wrapping onto the last row is one deliberate press.
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
- **`Array[StringName].sort()` orders by the interned POINTER, not the text.** Four style ids
  "sorted" that way came out `dusk16, nes16, lpc32, gb16`, and Sprite Lab cycled them in that
  order for months with nothing to notice. Sort ids with a `String` comparator
  (`ArtFixtures.by_text`), or keep them as the `String` paths `ContentScan` already ordered.
- **`str()` of an array of strings ESCAPES the quotes inside them**: `["it's"]` prints as
  `["it\'s"]`, so `assert_str(str(problems)).contains("'psd'")` can never pass and reads as the
  rule not firing. Join the array (`"\n".join(problems)`) before asking what it contains.
- Adding an autoload changes what the parse gate skips: `check.sh` and `compile_all.gd` both
  derive that list from `project.godot`, so add the singleton there and cover it in
  `smoke_boot.gd` — never by editing a list in a tool.
- A new `class_name` script is invisible to gdUnit4 until `--import` has run — the failure is
  `Could not find type "X" in the current scope` at discovery, which reads as a typo. Run
  `Godot --headless --path . --import` after adding one. `check.sh` does this as step 1.
- Running gdUnit4 by hand needs `--ignoreHeadlessMode -c`, or it refuses with `Abnormal exit
  with 103` and no test output at all.
- `mutants.tsv` patterns are EXTENDED regexes, so `+` is a quantifier: `_index + delta` matches
  nothing and fails as `PATTERN-NOT-FOUND`. Escape it. **A bare `)` is worse than wrong, it is
  wrong somewhere else**: a lone paren with no group open is undefined in an ERE, so BSD sed
  (macOS) takes it as a literal and matches while GNU sed (the runner) does not - the row aims
  perfectly here and goes STALE in CI twenty minutes later. `mutants_aim.sh` now refuses a bare
  paren on either platform, which is the only reason this is a note rather than a recurring bug.
  **A literal TAB in a pattern is the same class of hazard one layer up**: the file is
  tab-separated, so a tab inside the sed expression silently ends the column and the rest of the
  row becomes the suite and the label. Anchor on text rather than on leading indentation -
  `mutants_aim.sh` reports it as STALE, which reads as a rotted pattern rather than as a
  mis-parsed row.
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
tools/ci_changed.sh            # would this change run the gate? (the docs rule, runnable)
tools/pack_check.sh            # export the .pck and PLAY it - the artifact, not the source tree
```

Both scoping scripts carry a `--selftest` and `test_ci_paths.gd` runs them, because a rule whose
only witness is a step inside `check.sh` has no suite for a mutant to be judged by.

**Maps go out to a visual editor and come back.** `tools/map_io.gd` is the command; `TiledMap`
and `LdtkMap` are the translators behind it, and they answer the same four function names
(`problems`, `style_of`, `from_native`, `to_native`) so the command picks between them from a
table rather than branching - a third editor is a translator plus a row.

```bash
tools/map_io.sh --out=tiled --dir=build/maps
tools/map_io.sh --out=ldtk  --dir=build/maps
tools/map_io.sh --in=build/maps/quest_village.tmj
tools/map_io.sh --verify                       # check.sh step 6d
tools/lpc_compose.sh docs/lpc_designs/the_road.json --preview=build/hero.png
tools/lpc_compose.sh docs/lpc_designs/the_road.json --out=data/imports/lpc32/quest_wanderer
tools/fetch_tiles.sh data/tiles/lpc32.json      # the art an imported bank cuts from
```

**The atlas travels WITH the maps.** Both editors resolve their tileset image relative to the map
file, so an export directory has to contain it: `map_io.gd` copies each style's sheet in as
`tiles_<style>.png`, the name both translators write. Named per style because one directory may
hold maps from different banks. The first export wrote a bare `tiles.png` and every tile opened
BLANK - found by opening one in Tiled, and findable nowhere else, because the round trip never
reads the image and only an editor does.

**Tiled's own CLI is the strongest check available here**, and it is a one-off rather than a gate
(it needs Tiled installed, which CI does not have). `tiled --export-map csv <map>.tmj out.csv`
makes Tiled PARSE the file and re-emit its tile data; comparing that against the source map is an
independent reading. Measured 2026-09-01 on `quest_village`: 352 cells over both layers, zero
mismatches, all five object layers present with their counts, and NPC fields arriving as real
typed Tiled properties. Note Tiled's CSV writes 0-based LOCAL ids where the `.tmj` stores GIDs
(`firstgid + index`), so a uniform off-by-one between the two is the format's convention and not
a bug - it looked like 176 failures for a moment.

**Through the `.sh` wrapper, like `check.sh` and `pack_check.sh`** - it resolves the engine
through `_engine.sh` (honouring `GODOT_BIN`), so nobody types the app's path and nothing breaks
when the app moves. `build/` is gitignored, so an export leaves the tree clean. The underlying
`-s tools/map_io.gd` form still works if you want to name your own engine binary.

**Write every flag as `--flag=value`.** The space form is REFUSED out loud rather than ignored,
which is the 2026-08-04 lesson made into a guard: a value written after a space lands in a
positional slot while the option keeps its default, so the run reports on a configuration nobody
chose.

**A hero can be a text recipe.** `tools/lpc_compose.sh <recipe> --out=<dir>` fetches the layers a
recipe names from the generator's repository into `build/lpc/` (gitignored and `.gdignore`d) and
composes them the way the browser does. `LpcCompose` is the generator's rendering contract,
measured from its source: per-body-type paths, zPos order, palette-by-index recolour at the
generator's own +/-1 tolerance, file-variant items named by colour. It writes the SAME two files
the web app downloads plus the recipe beside them, and runs `LpcImport.problems()` on what it made
before writing anything. An authoring convenience, never a gate: the drift gate still compares
committed inputs to committed outputs and never reaches the network. `--preview=<png>` draws the
four directions through `LpcImport.build`, so what is looked at is what the game loads - and LOOK
FOR PROBLEMS: two of the first four designs were re-cut after their previews, one for a fringe
that read as speckle at 64px and one for three same-value colours that merged into a single
mass; both previews had rendered perfectly well. A layer with no art for the body type, no walk
cycle, or a licence outside the style is refused BY NAME, because the browser draws nothing and
says nothing. The path logic lives ONCE, in `LpcCompose`: the wrapper fetches the definitions a
recipe names, asks `--list` which files the plan resolves to, fetches those, and composes.

**The editor file is a WORKING file and is not committed.** The map that ships is still the
hand-readable legend-and-ASCII JSON, so it diffs as a picture in a pull request; a second
committed description of one map is two files that eventually disagree. `--verify` is the gate,
and it is the only one that runs the COMMAND: the suites round-trip in memory, Dictionary to
Dictionary, which says nothing about a path, an extension, a directory or an argument.

**`MapData.differences()` is the ONE place this project asks whether two maps are the same one.**
The Tiled round-trip, the LDtk round-trip and `--verify` all ask it there. It compares the GAME's
reading rather than the bytes, because a legend is a SPELLING choice - `#` and `w` are the same
wall, and a converted map assigns its own characters - and it normalises whole floats, because
JSON has no integers and a coordinate read off disk is `5.0` where the same one built in code is
`5`. `test_map_data.gd` proves it DETECTS, which is what stops three gates being vacuous at once.

**TILED IS VERIFIED; LDTK IS DELIBERATELY NOT.** A generated map was opened in Tiled on
2026-09-01 and read back through its own CLI: 352 cells over both layers matching the source
exactly, all five object layers with their counts, NPC fields arriving as editable typed
properties. That pass is also what found the atlas-path bug above, which no gate here could see.

LDtk has no Homebrew cask and checking it means a manual download, so it stays unopened by
choice rather than by oversight - a recorded state, not an open task (`docs/DECISIONS.md`). It is
still fully gated: 20 tests, 11 mutants, every shipped map round-tripped, and all six generated
`.ldtk` files validated once against LDtk's published 1.5.3 JSON schema with zero errors. That
validation is NOT in `check.sh`, because it needs a Python package the runner would fetch on
every run and a gate that reaches an external index is a flaky gate.

**Do not re-raise "go and open one in LDtk" as work.** It was weighed and declined; the Tiled
pass is the evidence the shared design is sound, since both translators are the same shape and
the one bug found applied to both.

**LDtk is stricter than its schema reads, and the difference was measured from its source.** The
schema's `required` list means "LDtk always WRITES this", not "the loader REFUSES without it" -
its own 0.9.3 test file, which current LDtk opens, is missing eleven fields the 1.5.3 schema calls
required. What the loader actually refuses is narrower and sharper: it reads `gridTiles`,
`entityInstances` and `intGridCsv` RAW on every layer with no null guard, so a layer missing any
of the three aborts the whole file; a field instance whose `defUid` resolves to nothing is dropped
silently when it carries no values and CRASHES when it does; and `iid` duplicates are accepted and
silently collapse entity references. Hence: every field instance gets a matching definition,
derived from the records rather than hand-listed, and every `iid` is a sha256 of its own name -
deterministic, because a drift gate cannot survive an id drawn fresh on every export.

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
second. Both CI paths pass `--assume-green`, which is sound because `gate` has just proven every
suite green ON THAT COMMIT; a shard shares nothing with it but the checkout, the binary and the
import cache, and rebuilds all three from the same inputs.

**THE HARNESS IS A LIST OF FILES, NOT A DIRECTORY, AND THAT IS WHY.** Touching the machinery
that RUNS mutants (`check.sh`, `mutate_check.sh`, `mutants_scope.sh`, `mutants_aim.sh`,
`_engine.sh`, `.github/`, `addons/gdUnit4/`) selects EVERY row, because such a change can
invalidate all of them at once. It used to be "anything under `tools/`", which swept in
`tools/mutants.tsv` - and this contract requires every new rule to add a row there, so nearly
every pull request that OBEYED the contract ran the full sweep. Measured 2026-09-02: nine of the
last ten pull request runs selected 513 to 579 of 579, the "fast" lane and the full sweep were
the same eighteen minutes, and the documentation in three places said otherwise. A change to
`mutants.tsv` needs no blanket: `added_rows()` already selects exactly the rows it added.

**The sweep is four shards, and `fail-fast` is off.** The default cancels the other shards the
moment one reports, which throws away three quarters of the answer to save minutes of a run
nobody is waiting on - and a surviving mutant is precisely when the rest of the list matters.
The list is chosen ONCE in `changes` and handed down as an artifact, so four jobs cannot become
four answers to one question and only one list is printed.

**One workflow, and the required status is a job that ALWAYS runs.** `check` is a REQUIRED
status, so a pull request that produces none can never merge; GitHub also reports a SKIPPED
required check as success, so a status job with any condition other than `always()` turns "the
gate never ran" into a green merge. The `check` job therefore accepts exactly two shapes -
everything succeeded, or nothing needed to run - and fails on anything else, including an empty
answer from `changes`. `tools/ci_changed.sh` holds the docs rule, once, where it can be RUN and
tested; `test_ci_paths.gd` calls it rather than parsing YAML, and derives the `docs/FLOW.md`
exception from the generators so the next drift-gated doc cannot be forgotten.

This replaced `check-docs.yml`, a second workflow with the same name answering the required
status on the inverse paths. That is GitHub's own documented pattern and it worked; it went
because two workflows named `check` made the Actions tab unreadable (which is how the scoper
bug above hid in plain sight), because `pages.yml` matches its trigger BY WORKFLOW NAME, and
because re-running the no-op by hand on a red pull request overwrote the real verdict - a
fail-open on the merge gate, one click away, documented in its own header.

**A merge runs `check` twice, and that is the design.** `pull_request` proves the gate plus the
mutants that diff could have broken; `push` to main proves the gate plus ALL of them, is the
green signal `pages.yml` deploys from, and is the only run that tests the SQUASHED tree - the PR
run tested a merge preview, which is a different tree the moment main moves. Skipping `check.sh`
on the main run does not save it either: `--assume-green` needs a suite run on that commit.

**`pages.yml` deploys only from a PUSH to main.** `branches: [main]` on a `workflow_run` filters
the triggering run's HEAD BRANCH, and a fork's pull request from a branch named `main` has
exactly that - so the event is checked too. It caches only the `web_*` export templates: the
engine finds a template by looking for one file by name, so the other platforms' were 1.3GB
restored on every deploy. A cache entry is immutable for its key, so trimming what goes in
does nothing until the KEY moves.

**Open the PR and walk away.** `gh pr merge --auto --squash` merges it when CI goes green;
polling is how a session gets spent. This needs a required status check on `main` - without
one, `--auto` merges immediately, which is the trap. The repository is squash-only (merge
commits and rebase merges are off), so a bare `gh pr merge` or a click in the UI cannot land
something the history was not written for.

**Write a commit message or a PR body to a FILE and pass `-F`, never `-m "..."`.** Every message
here is multi-paragraph prose full of backticks, `!=` and `${}`, and a double-quoted shell string
eats all three: backticks RUN as a command substitution and `!` history-expands under zsh. The
failure is silent and lands in history - two clauses vanished from a commit message here before
anyone looked, and the amend is only cheap while the branch has no PR. `gh pr create --body-file`
is the same rule for the same reason.

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

**Imported art is regenerated the same way, from the generator's own files.** Replace
`data/imports/<style>/<id>/sheet.png` + `character.json` (the recipe is in
`data/imports/lpc32/README.md`), re-run `gen_sprites.gd`, and commit the folder together with
what it produced - the sheet, its JSON, `credits.json` and `LICENSE.txt`.

**Imported TERRAIN is the same loop one directory along.** The sheets live at
`data/imports/tiles/<bank>/<file>` - under the same `.gdignore`, and NOT under
`data/imports/<style>/`, where the character arm reports any png that is not a `sheet.png`;
`data/tiles/<bank>.json` names a file and a CELL per tile plus the artists and licences;
`tools/fetch_tiles.sh` fetches whatever a bank's `url` fields name. **Choose the cells by
LOOKING** - the first pass here gave the inn a cold green stone floor and a table that sat high
in its cell like a stool, and both were re-cut against a screenshot. And after regenerating, run
`--import` before photographing anything: the game loads the IMPORTED texture, so a fresh
`tiles.png` behind a stale import reads as the change not having happened.

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

**A slot list has a CAPACITY, and it is the third thing MAX_PARTY's rule asks for.**
`GameConfig.MAX_SAVE_SLOTS` is 12: two screens draw one row per slot down a 180px window, and at
16 BOTH the pause menu's slot page and the save point walk their last rows off the bottom of it -
measured, silently, with every other gate green, because nothing headless looks at where a Label
ended up. So the data DECLARES the ceiling, `GameConfig.problems()` refuses more, and
`test_slot_layout.gd` measures both screens AT it. Any two of those three without the third is
the hole the pattern exists to close, which is what M27.1 found for the party.

Twelve rather than the fifteen that measurably still fits, because every reference game offers
one slot or three - the ceiling is nowhere near a real game's need, and the headroom means a font
or padding change cannot quietly push the last row off. The pause menu's half of this was
PRE-EXISTING and untested; the save point did not introduce it, it made it visible.

**Containment is never the whole assertion.** `test_slot_layout.gd` also requires every slot to
get a row, the rows to be DISTINCT, and them to go down the screen in order - because a screen
that drew nothing, or stacked all twelve rows on one line, is comfortably inside any window. That
is M36's lesson applied before the bug rather than after it.
