# Milestones

Every milestone this template has shipped, oldest first, one line each — the *what*. The *why*
behind each fork is in [DECISIONS.md](DECISIONS.md), and the genre research each player-facing
surface was built against is in [GENRE_CONVENTIONS.md](GENRE_CONVENTIONS.md).

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
- [x] **M41** — the edge between two materials is drawn: a tile may name a `ring` of twelve transition pieces and the ground it lies `over`, and the generator composes all 47 shapes a cell can take out of QUARTERS of them. A cell is still one tile id — the shapes sit in atlas columns no map can spell — so the map format, both editor translators and every map file were untouched, and a bank with no ring produces a byte-identical atlas
- [x] **M40d** — the ground is hand-drawn too: a tile bank says whether its pixels are authored rows or a CELL cut from art somebody drew, licence-gated and credited per file beside the cast. The demo's twelve tiles come out of the LPC base tileset with their ids, order and solid flags unchanged, so every map and all 23 sessions carried on untouched
- [x] **M40c** — the demo is hand-drawn: twelve characters composed from text recipes, creatures included (LPC has no non-human body, so a Slink is a child body wearing a lizard head), every map at 32px tiles, and all 23 play sessions unchanged
- [x] **M40b** — the world at 32px: a style states its `world_scale`, the window grows and every interface layer is drawn at it, so a 64x64 cast plays in a 640x360 world while every screen, font and layout gate keeps measuring against 320x180. Saves moved to tile units (v10) so a change of art cannot move a saved player
- [x] **M40a** — hand-drawn characters: a style's sheets come from the rig or from an import (`sheets_from`), Universal LPC exports are converted at build time, licence-gated by file, credited beside the sprites and drift-gated like everything else. The world at 32px, the credits screen and the cast itself are the phases that follow
