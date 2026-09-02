# 2D RPG Template

A reusable top-down RPG starting point for **Godot 4.7**, built so that *art style* and
*gameplay design* are the only things a new game has to change.

🎮 **[Play it](https://ali0600.github.io/rpg-template/)** — walk around, talk to the villagers,
find the key, open the gate.

![The town](docs/images/world.png)

It ships two halves:

1. **A consistent sprite generator** — a deterministic procedural paperdoll. Characters are
   composed from shared parts, one palette and one outline rule, so a whole cast is visually
   coherent *by construction* rather than by discipline. Same seed, same pixels, every run.
2. **The generic systems** — four-direction movement with tile collision, camera, data-driven
   maps with warps between them, NPCs and branching dialog, items you pick up and carry,
   game-flow states, a pause menu with per-game save slots, saves with migrations, a seeded
   RNG, procedurally generated sound effects, a headless QA harness, and CI that runs all
   of it.

## Why it looks the way it looks

Consistency in pixel art comes from rules, not talent: one limited palette, one outline style,
one size family, one set of proportions. A person applies those by discipline and drifts. The
generator applies them by construction and cannot — a rig part is an ASCII grid of tone
*indices*, and the style supplies what those indices mean, so there is no per-sprite place to
put a colour.

Those rules are then enforced as tests. Every generated pixel must be a palette colour; every
character's feet must sit on the same row; every left-facing frame must be its right-facing
frame mirrored; the same seed must produce the same bytes. Each gate ships with a mutant
proving it fails when broken.

![Two styles, one rig](docs/images/styles.png)

*`gb16` and `nes16` share a rig — **not one pixel of shape is redrawn between them**. They
differ only in palette, outline treatment and timings. Swapping the style re-skins the cast,
the terrain and the interface together.*

The output tier is honest GB/SNES-era chibi, not hand-painted art. Higher fidelity is a
*source swap*, not a rewrite: `SpriteSource` is an interface, and anything that writes the
`PNG + <name>.sheet.json` pair — a bought pack, an AI generator — feeds the game unchanged.

**M40 cashes that claim with hand-drawn art.** Characters designed in the [Universal LPC
Spritesheet Character Generator](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator)
come in through `data/imports/`, converted at build time by the same generator that draws the
procedural cast, drift-gated the same way, with every layer's licence checked by name and the
credits written beside the sprites. The procedural rig stays the default; `sheets_from` on a
style picks the arm.

The demo game is drawn that way now: twelve characters, each a short text recipe under
`docs/lpc_designs/`, composed by `tools/lpc_compose.sh` from layers it fetches on demand. The
two creatures are the interesting case — LPC has no non-human body at all, so a Slink is the
child body wearing a lizard head and tail.

Those characters are 64x64 on 32px tiles, which needs more room than the template's 320x180. So
a style says how big its WORLD is (`world_scale`) and the interface does not follow: the window
doubles, every screen is drawn at that scale, and each one keeps laying itself out against the
same 320x180 it always did. Twenty tiles across at either size, with no screen constant, font
size or layout gate touched. Saves record TILES rather than pixels for the same reason — a file
that recorded pixels would describe a different place the moment the art changed size.

![The warden, at the gate](docs/images/dialog.png)

## Quick start

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Run the full gate the way CI does:

```bash
tools/check.sh
```

Prove the gates actually bite (slower; run before calling a milestone done):

```bash
MUTANTS=1 tools/check.sh
```

Regenerate the art after editing a rig or a style:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sprites.gd
```

Draw a map in [Tiled](https://www.mapeditor.org/) instead of typing it — export, edit, import:

```bash
tools/map_io.sh --out=tiled --dir=build/map
tools/map_io.sh --in=build/map/quest_village.tmj
```

The maps that ship stay the readable ASCII files; the editor file is a working file, so a map
still diffs as a picture in a pull request. LDtk is supported the same way (`--out=ldtk`).

Bring in a hand-drawn character from the
[Universal LPC Spritesheet Character Generator](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator):
put its **Download PNG** and **Export JSON** files in `data/imports/lpc32/<character>/` and run
the generator above — `data/imports/lpc32/README.md` has the recipe. The converter re-cuts the
walk rows into the template's own sheet, writes `credits.json` and a licence notice beside the
sprites, and refuses any layer whose licence the style does not accept.

Or skip the browser: a hero is a text recipe naming the generator's layers and colours, and
`tools/lpc_compose.sh` fetches only the layers it needs and composes the same two files:

```bash
tools/lpc_compose.sh docs/lpc_designs/the_road.json --out=data/imports/lpc32/quest_wanderer
```

Four ready-made designs live in `docs/lpc_designs/`; add `--preview=build/hero.png` to look
before anything is written.

## Making it your game

| To change | Edit | Touch any code? |
| --- | --- | --- |
| Which game runs, and where it starts | `data/games/*.tres` | no |
| The whole art style | a file in `data/styles/` | no |
| Who the characters are | files in `data/characters/` | no |
| Hand-drawn characters | the LPC generator's two files, in `data/imports/<style>/` | no |
| The world | `data/maps/*.json` — ASCII rows plus a legend, or draw it in Tiled and import | no |
| What people say | `data/dialog/*.json` | no |
| How it feels to move, incl. free vs grid movement | `data/game_config.tres` | no |
| How many save slots there are | `data/game_config.tres` | no |
| What can be picked up and carried | `data/items/*.tres` | no |
| What a fight pays, and what the player starts with | `data/enemies/*.tres`, `data/games/*.tres` | no |
| What a shopkeeper sells, and for how much | `data/shops/*.tres`, `price` on `data/items/*.tres` | no |
| What can be worn, and what it is worth in a fight | `slot`/`attack`/`defense` on `data/items/*.tres` | no |
| New mechanics | a `GameHooks` subclass in `games/<id>/` | one file, never the template |
| New body parts | `data/rigs/*.json` | no |
| New terrain — a floor, a door, a cliff | `data/tiles/*.json` | no |

If changing any of these needs a code edit, that's a bug in the template.

A **game** is one `data/games/<id>.tres`: its first map and spawn, the character the player
wears, the tuning it uses, the line of on-screen help, and the one script it is allowed to
have. More than one can live side by side; with more than one and nothing choosing between
them the boot **refuses** rather than guessing, because a guessed game does not present as a
selection bug — it presents as the game you meant to run behaving strangely.

## The game it ships with

**The Barred Gate** — five maps on one palette. A town with a well, a smith and two people
with something to say, a cave east of it, a village up the north road, a hollow west of that,
and a keep behind a gate that stays shut until you find the key.

The warden barred that gate against the thing that took the keep. The key went into the
hollow, and what nests on it now is why nobody has fetched it.

| | |
| --- | --- |
| World | town, cave, village, hollow, keep — joined by five doors |
| Verbs | walk, talk, read a well, open a stash once, carry a key, unlock a gate with it, trade a word for a flask of oil, burn the oil lighting a lantern |
| Magic | five spells on a level curve: damage, a heal, a sweep, a sleep, and a **ward** that raises the party's guard for three turns. The Gloom answers with Chill, which lowers it |
| Fights | five, and every one of them a **crowd**: paired slinks twice in the hollow, paired glooms in the optional cave, a slink-and-gloom pair in the back of the hollow, and the Keeper with a gloom and a slink at its shoulders. Three are unavoidable. Both roads out of the village stay shut until Rook is along, because a fight sized for two must not be reachable by one |
| Combat | menu turns with a timing window — a press on the cue doubles your hit or halves theirs. A party of up to three, a formation of up to three against it, a cursor to pick which foe, XP, three levels, and a tonic you can drink mid-fight |
| Code | **one file**: which of the warden's four lines to say |
| Look | `dusk16`, one of three palettes that share a single rig |

That one file is the point. Everything else — every map, every conversation, every flag, the
gate that wants a key and the lantern that drinks the oil — is data, and the template never
learns a word of it. A chest hands something over with `give_item`, a door reads what you are
carrying with `requires_item`, and a lantern consumes it with `take_item`; each of those is a
line of JSON, and none of them is code. The game was built
**without editing a single file under `scripts/`, `tools/` or `scenes/`**, and building it found
three real defects in the template, which is what building on it is for: a QA op that raced the
steps written after it, an art-drift gate that walked a different set of directories than the
game did, and three separate lists of "which directories does this project own" that disagreed.

Fighting is the same story: an enemy is four lines of JSON on a map, its numbers are a
`.tres` beside the items, and the difficulty is arithmetic rather than feel — a player who
times every press beats the Keeper on every seed, and one who times none of them loses on
every seed. Both are proven by a play script rather than asserted in a comment. Lose and the
run ends; the only ways on are a save or a fresh start, which is what makes saving matter.

Escape pauses, and the same menu saves and loads. Slots belong to the game that wrote them —
`user://saves/<game>/slot_N.json` — and each save names its own game, so a file that ends up in
the wrong directory is refused and preserved rather than loaded.

## Sprite Lab

A live preview of the generator — all four directions and the whole cast, laid out at the
game's own 320×180 so the art is judged at the size it will actually be seen. An imported style
(`lpc32`) is shown from its committed sheets, which is where the first hand-drawn character is
judged before the world is rebuilt around it.

![Sprite Lab](docs/images/sprite_lab.png)

## Layout

| Path | What lives there |
| --- | --- |
| `scripts/spritegen/` | The generator. Pure, deterministic, no node access. |
| `scripts/world/` | Movement, collision, maps, camera, interaction. |
| `scripts/ui/` | Dialog runner and its view, the pause menu, Sprite Lab. |
| `scripts/autoload/` | EventBus, Registry, GameState, SaveManager, Router, AudioBus, Qa. |
| `scripts/util/` | Build-time readers, `Dir`, `Sfx`, and `UiScale` — how big a style's world is. |
| `data/` | All content: games, styles, rigs, characters, maps, dialog, config. |
| `games/<id>/` | A game's own code, if it has any. |
| `assets/generated/` | Build output of `tools/gen_sprites.gd` — never hand-edited. |
| `tools/` | Headless scripts and the gate. |
| `tests/` | gdUnit4 suites, fixtures, and the mutation harness's targets. |

- [CLAUDE.md](CLAUDE.md) — the engineering contract
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — the seams, and what each one protects
- [docs/STYLE_GUIDE.md](docs/STYLE_GUIDE.md) — the art rules, and how to change the look
- [docs/DECISIONS.md](docs/DECISIONS.md) — design forks, with a backlog of what's worth trying
- [docs/GENRE_CONVENTIONS.md](docs/GENRE_CONVENTIONS.md) — what 2D JRPGs converge on, and where this template sits against it
- [docs/learnings.md](docs/learnings.md) — the bugs that were interesting

## Milestones

- [x] **M0** — project skeleton, headless tooling, lint rules, mutation harness, CI
- [x] **M1** — the sprite generator, its consistency gates, and generated assets
- [x] **M2** — the sprite view scene and Sprite Lab preview
- [x] **M3** — movement, collision, camera, data maps, game-flow states, QA harness
- [x] **M4** — NPCs, interaction, branching dialog
- [x] **M5** — saves with migrations, audio seam, content registry
- [x] **M6** — web export and a live demo
- [x] **M7** — a second game, built to find out whether the first six were true
- [x] **M8** — a game picker, so switching is a keypress rather than an edit *(retired in M11)*
- [x] **M9** — grid-step movement as a second mode, off by default
- [x] **M10** — a pause menu, and save slots that belong to one game
- [x] **M11** — one game, one world, and the name this repo should have had
- [x] **M12** — items and an inventory, and a quest that runs on them
- [x] **M13** — turn-based battles with timed presses, XP and levels, and a quest reworked around them
- [x] **M13.1–.4** — the play-test round: reaction-sized timing windows, a quest that says where to go, a dialog box that declares its capacity, a quiet build log
- [x] **M14** — sound: a synthesiser driven by a cue bank and a voice, generated and drift-gated the way the sprites are, with the whole game finally audible
- [x] **M14.1** — the gate got 17x faster without losing an assertion: frame-driven runs stop waiting on the wall clock, and a pull request proves the mutants its own diff could have broken
- [x] **M15** — the gate finally looks at what ships: the exported .pck is booted and played on every run, and the played game now notices its own combat arithmetic
- [x] **M16** — terrain became data: tiles are authored pixel art in `data/tiles/*.json` in the rig's own alphabet, the six procedural ones ported losslessly, and a floor, a rough wall, a door, steps, a table and a rug added without touching a script
- [x] **M17** — NPCs move: `behavior` on a map record is `static`, `wander` or `patrol`, driven through the same Locomotion the player uses, and the whole town freezes with the player so nobody wanders off mid-sentence
- [x] **M18** — money: gold that a fight drops and a save carries, and a shopkeeper opened from a dialog choice who refuses what you cannot afford and will not touch a quest item
- [x] **M18.1** — the shop became a counter: an item list with a price column, a purse, a description bar, a keeper who talks, and a "how many?" step, all in windows over the world you are standing in
- [x] **M19** — equipment: a weapon and an armour slot whose stats reach the fight as modifiers, worn from the bag with an (E) marker and a stat preview, and refused by the shop counter while you are wearing it
- [x] **M20** — equipment became a screen: a menu command of its own opening a slot list, each slot offering the gear that fits it plus a way to take it off, with the swap previewed against what you are already wearing — and `docs/GENRE_CONVENTIONS.md`, which is what the genre research now lands in, plus a Status page — level, HP, how far to the next level, and what you are wearing, none of which could be seen outside a fight before
- [x] **M21** — an inn: the first interior you walk into, a keeper who names a price out loud and refuses in words, a night that fades, and the loop the economy rests on — fight, lose hit points, pay to get them back
- [x] **M22** — a title screen: the game's own name, Continue and New game, and a game-over screen that finally routes back to it
- [x] **M23** — the flow model: the state machine declared as data in `tools/flow_model.json`, a gate that drives every declared move through the real game and compares what the router actually announced, and `docs/FLOW.md` drawn from it
- [x] **M24** — music: a tune authored as notes in `data/music/`, performed by the same synthesiser the sound effects use, so each style plays the same melody in its own voice
- [x] **M25** — magic: MP as a level curve, spells in `data/spells/` known by reaching their own level, and a Magic command between Attack and Item with an attack, a heal and a sleep behind it
- [x] **M26** — a battle theme and a victory fanfare: a fight takes the room's music over, a win stings once and hands the room back to whatever the map states
- [x] **M27** — a party: a second fighter who joins through a conversation, an ally cursor that only exists once there is somebody to aim at, and per-member equipment and status pages
- [x] **M27.1** — a member acts the moment they choose: choosing Attack swings, and the turn passes to the next fighter once the blow has landed, rather than collecting everybody's orders first
- [x] **M28** — fights that hold a crowd: a map record names a formation, a cursor picks which foe to strike, every living enemy takes its own turn, and a spell can carry a shape that reaches all of them
- [x] **M29** — the crowd becomes the ordinary case: every encounter is a formation, the boss brings an escort, both roads out of the village stay shut until the second sword is along, and the balance gate stopped doing arithmetic about the fight and started playing it
- [x] **M30** — statuses that run both ways: a buff and a debuff the party can cast, an affliction enemies can inflict, durations counted in turns, and a well-timed guard that shrugs one off entirely
- [x] **M31** — the flow model is walked, not just stepped over: seeded random journeys through the state machine on one world that is never rebuilt, and a failing journey minimised to the shortest one that still fails before it is reported
- [x] **M32** — a death and a boss get their own music, and a save slot that cannot be read says so instead of drawing as empty
- [x] **M33** — elemental resistances: a spell is made of something, an enemy answers it with a percent, and a weakness or a resistance is announced rather than left as a number with nothing to compare it to
- [x] **M34** — the balance gate learned to cast: it plays every shipped fight with magic now, and asserts that every spell is used and every elemental weakness is actually told to the player somewhere
- [x] **M35** — the balance gate learned to use items too, and closed a guard nothing had ever proven: a quest item on the battle menu would be destroyed by using it
- [x] **M36** — the battle caption wraps instead of running off the screen, and a driver that presses Run asserts which fights the game will actually let you leave
- [x] **M37** — a spell that hits everything now reports one foe at a time, with the caster and the spell held still above it, the way the games it borrows from do
- [x] **M38** — maps can be authored in a visual editor: Tiled AND LDtk, both directions, round-tripped over every shipped map through real files by `tools/map_io.sh`
- [x] **M39** — where a game may be saved is now the game's own decision: save anywhere from the menu, or only at a save point, chosen in data with both sides gated. The village gained a chronicler who writes your journey down
- [x] **M40c** — the demo is hand-drawn: twelve characters composed from text recipes, creatures included (LPC has no non-human body, so a Slink is a child body wearing a lizard head), every map at 32px tiles, and all 23 play sessions unchanged
- [x] **M40b** — the world at 32px: a style states its `world_scale`, the window grows and every interface layer is drawn at it, so a 64x64 cast plays in a 640x360 world while every screen, font and layout gate keeps measuring against 320x180. Saves moved to tile units (v10) so a change of art cannot move a saved player
- [x] **M40a** — hand-drawn characters: a style's sheets come from the rig or from an import (`sheets_from`), Universal LPC exports are converted at build time, licence-gated by file, credited beside the sprites and drift-gated like everything else. The world at 32px, the credits screen and the cast itself are the phases that follow

## Experience Gained

- Integrated a third-party art toolchain through an existing source seam without touching the
  runtime: a build-time converter re-cuts the vendor's fixed-layout sheet into the internal
  contract, and the existing drift gate covers the imported output with no new pipeline step.
- Turned asset licensing into an enforced build gate rather than a README note: every imported
  layer's licence is checked against a per-style allow-list by family — not by prefix, since
  CC-BY is a prefix of CC-BY-SA — with credits and a licence notice generated deterministically
  alongside the sprites, and the build refusing a non-compliant layer by name.
- Scaled a rendering surface instead of its contents to support a second art resolution: one
  transform above the layout let a 2x world ship without re-tuning a single UI constant, font
  size or layout assertion, verified by measuring rendered rectangles in screen space rather
  than the properties that produce them.
- Automated a third-party asset pipeline end to end: characters are declarative text recipes,
  resolved against a remote catalogue, composed and licence-checked at build time, and the
  committed output is verified against the tool that produced it on every CI run.
- Migrated a persisted format to unit-independent coordinates (a versioned save migration with
  a frozen conversion constant), renaming the field alongside so the compiler enumerated every
  reader rather than leaving them to manual search.
- Split a quality gate by capability and proved the split with a membership assertion (the two
  lists of styles must together equal every style on disk), so a new kind of source cannot
  silently opt out of every gate.
- Derived the vendor format from its source code — frame size, fixed row offsets, direction
  order, cycle — rather than from documentation, and pinned each fact as a literal in the tests
  so a fixture cannot move with the constant under test.
- Verified the packaging outcome directly: read the exported archive for the presence of the
  shipped credits file and the absence of every build input, rather than trusting the ignore
  marker that was supposed to produce that result.
- Re-implemented a third-party tool's rendering contract from its source — per-layer draw
  order, palette-by-index recolouring at the tool's own ±1 tolerance, per-body-type asset paths
  — as a pure, unit-tested function, so a character is a text recipe rebuilt by one command
  rather than a browser session, with the tool's own importer validating the output.
- Reviewed generated previews for problems rather than presence and re-cut two of four designs
  before presenting them — a fringe that read as noise, and three same-value colours that merged
  — because a rendered preview only proves the pipeline ran, not that its output is usable.

- Built a bidirectional converter between an internal format and two third-party editor formats, deriving the schema from the vendor's published JSON schema, its own sample projects, and its loader source — which disagreed with each other in ways that mattered, and validating the output against the vendor schema caught what a self-round-trip never could.
- Reduced three separate implementations of an equivalence check to one shared function before adding the third consumer, then proved that function detects differences rather than assuming it, because a permissive comparison would have made three gates pass vacuously at once.
- Distinguished what a test suite proves from what it cannot: documented in the code that a round-trip verifies the reader against the writer and not against the third-party tool, and recorded the one-off external validation separately rather than presenting it as continuous coverage.
- Declined to add a CI gate that would depend on fetching an external package on every run, documenting the reasoning and the manual command instead of introducing a flaky check.
- Caught a fixture flaw in my own test during mutation testing: the value under assertion was the degenerate case, so a mutation replacing the entire calculation with a constant went undetected until the fixture was changed to one that could distinguish them.

- Converted a hard-coded product rule into a configurable policy with a validated vocabulary, designing the field so that a future third value costs no data migration — and made an invalid value fail the build rather than silently fall back to the default.
- Proved a behavioural change was strictly additive by holding 22 end-to-end scripted runs byte-identical across the release, so the new axis demonstrably altered nothing for existing consumers.
- Identified that a deferred UI callback was untestable through the obvious seam and built the one integration test that could distinguish it, after establishing that every existing test of that feature passed against both the correct and the broken implementation.
- Found a defect in my own test during mutation testing: an assertion could never evaluate true because of a rendering prefix, so it had been passing as decoration. Caught by requiring each new test to fail against a deliberately broken build before being trusted.
- Corrected three widely-repeated factual claims by reading shipped binaries and official documentation after the usual secondary sources proved unavailable, and recorded each finding with its verification tier so later readers can tell primary evidence from secondary.

- Replaced a shipped feature with the convention established by primary-source research, and
  chose the design that REMOVED two special cases rather than the one that preserved existing
  behaviour — the redundant branches were themselves evidence the original shape was wrong.
- Changed the pacing of a core interaction with no regression across 22 end-to-end scripted
  runs, because those runs had earlier been rewritten to drive on observed state rather than on
  counted delays.

- Caught a self-fulfilling assertion in review: a test derived its expected value from the same
  field it was validating, so corrupting that field moved the expectation with it and the mutant
  survived. Rewrote it to compare the computed SET against an independently declared one, which
  also covers deletion — a per-item property check cannot see a set that merely got smaller.
- Established that a containment check was insufficient on its own by mutation testing, not by
  inspection: a degenerate layout satisfied the bounds while being unusable, so the gate gained a
  second constraint expressed in the units the design actually declares.

- Added a regression test for a one-line filter that had shipped untested, after tracing its
  failure mode to permanent, unrecoverable data loss for the end user hours after the mistake.
- Distinguished masked behaviour from dead code when mutation testing reported a surviving
  mutant: the production data happened to make two distinct implementations equivalent, so the
  rules were relocated to a suite whose fixtures could tell them apart.

- Closed a two-layer blind spot in a simulation-based quality gate: the driver never exercised
  one input path, and the fixtures beneath it were built without the data that path consumes —
  so an entire subsystem was absent from the scenarios the gate reported on.
- Identified that a driver's *choice policy* bounds test coverage as strongly as its skill
  level, and added an opposed policy on that axis; it immediately surfaced a rule that could
  never be reached under the existing traversal order.
- Turned a product requirement previously enforced by convention — that a shipped mechanic must
  be discoverable by the user — into an executable assertion over simulated playthroughs, which
  failed on two of three cases the first time it ran.
- Eliminated a duplicated derivation between production code and test fixtures by extracting the
  shared predicate, so a quality gate cannot validate against configuration the application
  never produces.

- Grounded a design decision in primary evidence by reading disassemblies of the shipped
  binaries when the usual secondary sources were unreachable — which contradicted the most
  widely repeated claim about the reference implementation and changed the feature's output
  format before it shipped.
- Replaced a hand-maintained checklist in an integration test with one derived from the object
  under test at runtime, closing a gap the test's own comment had correctly described for two
  releases: the field that goes unpropagated is always the newest one, i.e. the one nobody
  remembered to add a line for.
- Diagnosed a structural blind spot in an existing simulation-based quality gate — its driver
  exercised only one of the system's input paths, so an entire subsystem lay outside anything it
  could measure — and documented the limitation with its remediation rather than allowing a
  passing run to imply coverage it did not provide.
- Added a cross-directory referential-integrity check between two independently valid data sets
  joined only by a free-text key, where a typo on either side degraded silently to default
  behaviour rather than failing.

- Extended a single-actor combat system to N actors without changing a line of its public
  behaviour, by making the single case a list of one rather than a second code path — verified
  by sixteen pre-existing end-to-end play sessions passing byte-identically against the
  rewritten engine.
- Eliminated an entire class of persistence bug by deriving party membership from existing
  game state instead of storing it: no roster field, no schema migration, and no way for
  membership to drift from the event that granted it.
- Isolated a new random draw onto its own seeded stream so that every previously recorded
  deterministic replay continued to produce identical output, making a behavioural change
  provably invisible to existing regression fixtures.
- Diagnosed and repaired a masking defect found only by mutation testing in CI, where a newly
  added validation silently subsumed an older one — leaving a guard whose removal no test
  could detect.
- Replaced a closed-form balance model with a deterministic simulation that plays the real
  engine to completion under two opposed policies, across many seeds — turning a difficulty
  guarantee from arithmetic that described one obsolete scenario into an executable check that
  reads its inputs from the shipped content and cannot drift from it.
- Derived a content precondition from the level graph rather than asserting it by hand: a
  reachability search establishes which capabilities a player is *guaranteed* to hold at each
  location, so balance checks are run against the weakest reachable configuration instead of an
  optimistic one.
- Found a latent defect shipped a milestone earlier — a set-semantics helper reused where
  ordered, duplicate-bearing data was required — by extending automated coverage to an input
  shape no existing fixture produced.
- Consolidated a value assembled independently at multiple call sites into a single derivation
  before adding a third contributor to it, on the reasoning that duplicated arithmetic fails
  silently and asymmetrically rather than loudly.
- Used mutation testing against *data* rather than code to discover an entire missing validation
  gate: one content type had been scanned against its own validator since it existed, and a
  sibling type shipped four milestones later had never been scanned at all.
- Built model-based testing over an application's state machine: seeded random traversals
  replayed from an explicit path, asserting a declared event trace and a set of per-state
  invariants after every transition — closing a coverage gap where each transition had been
  verified individually and no sequence of them ever had.
- Implemented automatic counterexample reduction (test-case shrinking) for those traversals,
  choosing a domain-specific reduction — eliding cycles between repeated states — over generic
  delta debugging, because it cannot generate an invalid path and therefore needs no way to
  distinguish "did not reproduce" from "was never runnable". First real failure reduced from
  24 steps to 5.
- Inverted the search loop so the reduction algorithm stays a pure function over integers,
  unit-testable in milliseconds with no runtime environment, while the expensive replay stays
  in the integration harness that owns the world.
- Justified a new test layer by measurement rather than argument: seven candidate faults were
  injected and run against both the old and new gates, and the layer shipped on the two that
  the existing gate demonstrably could not detect.
- Caught a factual error in a design document by running a domain-research pass before
  implementing against it — the code's own justifying comment asserted an industry convention
  that the primary sources contradict, and had stood for four release cycles.
- Replaced a pair of parallel arrays with a single value object across nine call sites in a UI
  layer, on the reasoning that two collections answering one question drift into mismatched
  pairs rather than into crashes; the type widening surfaced a latent null-check whose meaning
  had silently inverted, caught by five existing suites.

- Built deterministic audio sequencing on the simulation's own frame clock rather than on the
  audio device's completion callback, after measuring that the headless driver used by every
  CI gate never reports a stream as playing — the callback would have been correct in
  production and untestable everywhere it needed proving.
- Designed a feature's persistence to need no persistence: spell availability is recomputed
  from the player's level on every use rather than stored, which removed a save field, a
  migration, a synchronisation invariant and an entire class of drift bug from the design
  before any of them could be written — after researching how the reference systems in the
  domain actually behave rather than assuming.
- Versioned a persisted schema with a forward-only migration chain and proved the new step
  fail-first against a pinned fixture of the previous version, including that it preserves
  every field the older format already carried.
- Encoded the application's state machine as machine-readable data with a conformance gate:
  every declared transition is driven through the running system and the recorded event trace
  is compared against the declaration, so an action that arrives at the right state via an
  undeclared intermediate one fails the build - the exact class of sequencing bug that had
  shipped. Membership is asserted in both directions, so a new state without a model row
  cannot land quietly.
- Implemented cross-platform-deterministic audio synthesis: waveforms from arithmetic only (no
  libm transcendentals, which are unpinned between macOS and the Linux CI runner), musical
  pitch from an integer fixed-point ratio table with octaves applied as exact binary
  doublings, and the rendered PCM drift-gated byte-for-byte across both platforms.
- Partitioned CI by change type using GitHub's skipped-but-required-check pattern: docs-only
  pull requests are answered by a same-named stand-in workflow in seconds while code changes
  run the full gate, with the two path filters pinned as exact inverses by a test and the
  generated-and-drift-gated exceptions derived from the generators themselves - and mutation
  coverage extended to the workflow YAML, proving the filter rules are enforced rather than
  hoped.

- Designed a deterministic, seed-driven asset generation pipeline producing game-ready sprite
  sheets plus machine-readable metadata, with reproducibility enforced by golden-hash
  regression tests in CI.
- Built a multi-stage verification gate (static lint, isolated parse, whole-project compile,
  unit suites, runtime boot check, generated-artifact drift detection, and scripted
  end-to-end play) that fails closed, hardened against four known false-green modes: a piped
  exit code, a test runner that exits 0 having run nothing, a scan that visited no files, and
  a build artifact that no longer matches its source.
- Implemented mutation testing over the project's own quality gates, so each rule ships with
  machine-verified proof that it detects the defect it was written for; a rule whose mutant
  stops applying fails the build rather than quietly reducing coverage. Three tests were
  identified as decorative this way and rewritten to assert the mechanism.
- Authored CI/CD pipelines in GitHub Actions with SHA-pinned third-party actions,
  least-privilege token scopes, and checksum-verified toolchain downloads, avoiding
  third-party installer actions in the supply chain; the deployment job is gated on the test
  workflow's conclusion and pinned to the exact commit that passed rather than racing it.
- Built a scripted integration-test harness that drives the real application end to end
  (input, physics, state transitions) headlessly, used as both a local developer gate and a
  CI check.
- Architected a swappable-asset-source seam (interface plus a PNG/JSON contract) decoupling
  the runtime from how art is produced, enabling procedural, hand-authored or AI-generated
  assets behind one API.
- Implemented versioned save serialization with a forward-migration chain and fail-safe
  corruption handling that preserves the original bytes before any recovery path runs.
- Designed a deterministic, frame-quantised turn-based combat system whose entire rule set is
  a dependency-free unit under test: time is injected one simulation tick at a time rather
  than read from a clock, making every fight reproducible from a seed and drivable by
  automated play scripts on an exact frame.
- Specified game balance as executable assertions rather than designer intuition, proving from
  the shipped data that optimal play wins on every random seed and unskilled play loses on
  every seed — so a retuned stat fails the build with the reason, instead of silently making a
  skill mechanic decorative.
- Extended automated end-to-end coverage to both ends of the competence range after
  identifying that a competent test driver only exercises the branches competent play reaches;
  the deliberately-unskilled driver covers the failure, retreat and recovery paths a passing
  run never visits.
- Added a static pre-flight check to the mutation-testing pipeline after diagnosing that newly
  added code can silently re-target an existing, untouched mutation onto the wrong function;
  the check runs unconditionally in seconds where the full suite takes twenty minutes, moving
  detection from post-push CI to pre-commit.

---

🔗 **Live:** https://ali0600.github.io/rpg-template/ · **Repo:** https://github.com/Ali0600/rpg-template
