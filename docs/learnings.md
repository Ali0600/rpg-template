# Learnings

Transferable concepts from building this template.

## A parse is not a compile, and neither is a boot

Godot's `--check-only -s <file>` parses one script in isolation. It cannot resolve a type
that lives in another script, and it cannot run at all for a script that names an autoload,
because singletons only exist in a real project run.

**Why it came up:** three gates in `tools/check.sh` look redundant until you notice each
covers a hole the previous one leaves — per-file parse, whole-project `compile_all.gd`, and
`smoke_boot.gd` which starts the tree and asks the autoloads whether they are alive.

**Takeaway:** when a checker skips inputs it cannot handle, the skip list is a coverage gap
— name it and cover it with a different instrument.

## A skip list typed by hand goes stale the day something is added

`check.sh` and `compile_all.gd` both skip scripts that reference an autoload. Writing that
list of singleton names into each file would mean a new autoload silently drops every file
using it out of the compile gate.

**Why it came up:** the project this one borrows its tooling from hardcodes six names in
three places. Here both readers derive the list from `project.godot` — awk for the shell,
`ProjectSettings.get_property_list()` for GDScript — and fail loudly if it comes back empty.

**Takeaway:** derive a membership list from its source of truth, and treat an empty result
as a broken scan rather than a clean one.

## `PackedByteArray` has no `sha256_text()`

`sha256_text()` is a `String` method. Hashing raw bytes — an `Image.get_data()` for a golden
sprite check — goes through `HashingContext` (`start` / `update` / `finish` / `hex_encode`).

**Why it came up:** the first run of the gate failed to compile the engine-assumptions
suite, which then crashed gdUnit4 during discovery — and gdUnit4 exits **0** when that
happens. The suite-count guard was the only reason it read as a failure.

**Takeaway:** hash the raw pixel bytes, never the encoded PNG (encoders vary by platform for
identical pictures), and pin the hash function against a published test vector so a swap to
a weaker one cannot pass silently.

## `ProjectSettings.save()` drops settings equal to their default

Writing the input map with `tools/setup_input_map.gd` rewrote `project.godot` and removed
the `window/stretch/aspect="keep"` line that had been typed there by hand — because `keep`
*is* the default. The setting is still in effect; it is simply not stored.

**Why it came up:** a line vanishing from a config file right after a tool ran looks exactly
like the tool clobbering something.

**Takeaway:** a machine-written config is normalised, not corrupted — assert the *effective*
value via `ProjectSettings.get_setting()` (as `smoke_boot.gd` does) rather than grepping the
file for a line.

## A colour computed in floats does not survive an 8-bit image

`Color.to_rgba32()` **rounds** a channel; storing a colour in a `FORMAT_RGBA8` image
**truncates** it. So `Color("#008840").darkened(0.35)` reports itself as `#00582a` and comes
back out of the PNG as `#005829`.

**Why it came up:** the tinted-outline style failed the palette gate on its very first run.
Two pieces of code agreed on the formula and still disagreed on the answer, because one of
them had been through the image and the other had not. `Color8(r, g, b, a)` round-trips
exactly for all 256 values — measured, not assumed.

**Takeaway:** compute any colour that will be stored in a fixed-point buffer in whole bytes,
and when two sides of a pipeline "use the same formula" but disagree, suspect the storage
between them before the formula.

## An exemption belongs outside the scan loop

Every rule in `scripts/util/lint_core.gd` decides its exemptions once, before iterating
lines, and no rule can end the scan early.

**Why it came up:** the shape being avoided is a scanner whose per-hit exemption shares a
branch with a loop terminator, so the first exempted match ends the scan and every later
line goes unchecked — while the gate still reports green.

**Takeaway:** normalise and decide exemptions once, up front; report every hit, never the
first; and assert how many things were scanned, because "green" and "checked everything" are
different claims.

## An identity check on an input event breaks the second press

The engine reuses `InputEvent` instances between frames. A handler that guards against
double-delivery with "have I seen this object before?" therefore treats every genuine
repeated press of the same key as a duplicate — the button works exactly once and then dies.

**Why it came up:** the guard was added to survive a test harness that delivers each event
twice (gdUnit4 both parses the event and calls `_unhandled_input` directly). It fixed that and
broke real input, and the symptom — a dialog that opened and then refused to advance — pointed
nowhere near the guard.

**Takeaway:** scope an idempotence guard to the window the duplication happens in. The same
object in the same *frame* is a duplicate; the same object a frame later is a person pressing
the button again. Both halves deserve a test, because each one alone is a bug.

## Setting input state and delivering an input event are different things

`Input.action_press()` updates the input singleton's state — which is what `Input.get_axis`
and other polling reads. It does **not** synthesise an event, so `_unhandled_input` never
sees it. `Input.parse_input_event()` does both.

**Why it came up:** the QA harness could walk the player anywhere and could not press a
button. The failure looked like the interact button being broken, not like the harness being
half-connected — the game was fine.

**Takeaway:** when scripted input drives one kind of code and not another, check which of the
two mechanisms you are using before debugging the code that "doesn't respond".

## A `break` inside an `if` is a syntax error, so that mutant never ran

A mutation that changed `while cond:` to `if cond:` turned a loop containing `break` into
invalid GDScript. The harness reported BROKEN — the runner never started, so no test judged
it — rather than passing it off as a killed mutant.

**Why it came up:** the mutant was meant to prove a migration chain runs every step rather
than one. It could never have proven anything.

**Takeaway:** a mutant must produce code that still *compiles*, or it tests the parser instead
of the tests. A harness that cannot tell "the suite went red" from "nothing ran" would have
scored this as success — which is why the runner counts executed suites, not just exit codes.

## A fix that changes HOW, not WHAT, needs an assertion on the mechanism

If a change alters the way work is done but not the output, no assertion on the output can
tell a working version from a broken one.

**Why it came up:** `SpriteView.set_pose` guards against re-issuing the animation that is
already playing. A mutant removed the guard and the test still passed — because
`AnimatedSprite2D.play()` happens to be forgiving about being handed its current animation, so
the rendered frame was identical either way. The test read as careful and proved nothing. It
now counts how many times an animation was started.

**Takeaway:** for a caching, guarding, or reordering change, assert the mechanism — a call
count, which method ran — and let a mutant prove the assertion can fail.

## Idle frames and physics frames are two different clocks

`_process` and `_physics_process` do not run at the same rate, and headless — with no display
pacing anything — they diverge wildly.

**Why it came up:** the QA harness counted `_process` frames while movement happens in
`_physics_process`, so "hold right for 30 frames" meant a different distance on every machine.
The first run reported the player moving at 40% of the configured speed and looked like a
movement bug.

**Takeaway:** a harness must count the same clock as the thing it is measuring — and a test
that counts ticks at all is baking in a tuning value, so prefer watching the outcome with a
bounded loop.

## Validating every element does not validate the whole

A checker that walks each item can pass completely while a property *of the collection* is
broken.

**Why it came up:** every tile in the demo map was valid, every legend entry resolved, every
spawn was in bounds — and one row was a character short of its east wall, so the player walked
straight out of the world. Nothing errored, because "the perimeter is closed" is not a
property any individual tile has.

**Takeaway:** ask what is true of the whole structure and not of its parts — a boundary, a
total, a reachability — and assert that separately.

## A regenerated asset is not a reloaded asset

Godot caches imported textures under `.godot/`. Rewriting the PNG on disk does not change what
the running engine draws until the project is re-imported.

**Why it came up:** the bush tile was fixed and regenerated, and the world still rendered the
old square version. The obvious reading is "the fix didn't work", and the next move is to
re-debug a correct fix.

**Takeaway:** in any tool with an asset cache, re-import before judging a change to a
generated file — and when a fix appears not to take, suspect the cache before the fix.

## A mutation harness reports design smells as well as coverage gaps

A mutant that cannot be applied to exactly one line is telling you two lines are identical.

**Why it came up:** a mutant on `Router` came back TOO BROAD, because `player_can_move()` and
`accepts_world_input()` had byte-identical bodies. Two copies of one predicate is precisely how
they drift apart the first time one of them needs to change. One now delegates to the other.

**Takeaway:** read a harness's refusals, not just its failures — "I cannot target this
uniquely" is a fact about the code, not about the harness.

## Browser automation may not be able to drive a Godot web build at all

Godot's web export maps input from `KeyboardEvent.code` — the physical key. Some browser
automation sends *trusted* key events with `code: ""`, `keyCode: 0`, and only `key`
populated; the engine receives an event it cannot map to any key. Synthetic events built by
hand with a correct `code` arrive with `isTrusted: false` and are ignored.

**Why it came up:** verifying the deployed demo. The page loaded, the engine logged its
version and renderer, the whole world drew correctly — and nothing responded to a keypress.
The obvious reading is "the web build is broken", and the next move is to go re-debug an
export that is fine.

**Takeaway:** before concluding a deployed build is broken, prove the *instrument* can
deliver the input at all — add a listener to the page and inspect what your own keypress
actually looks like when it arrives. An automation that cannot produce a `code` cannot test
any engine that reads one, and that is a fact about the tool rather than the deliverable.

## The same walk written four times is four walks that disagree

Four places discovered content under `data/`: `Registry`, the sprite generator, the art-gate
fixtures, and Sprite Lab. Registry's recursed into subdirectories. The other three did not.

**Why it came up:** planning a second game in the same repo, and asking where its content
files could live. The answer turned out to be "flat, or the gates stop working" — a spec in
`data/characters/quest/` would be registered by the running game, never generated by
`gen_sprites`, and the art-drift gate would compare the files it knew about and report green
having never looked at the new ones. Nothing errors in that sequence. The gate is not wrong
about what it checked; it is wrong about what it claimed to check.

The fix also exposed a second thing nobody had pinned: `DirAccess` returns entries in
filesystem order, so the *order* of the generated contact sheet depended on which machine ran
the generator. Sorting the walk is what makes "regenerate and diff" a stable check rather
than a usually-stable one — and the mutant proved it, because removing the sort changed the
order for a directory containing a subdirectory.

**Takeaway:** when the same question ("what content is there?") is answered in more than one
place, the copies drift and the failure is silent — one caller sees more than another and
whichever one is a *gate* quietly narrows. Write the walk once, and make the sorted order
part of the contract if anything downstream is compared byte for byte.

## A mutant's ability to kill can depend on the machine it runs on

The sort added above got a mutant: remove `out.sort()`, and the ordering test should go red.
It did — on macOS. On the Ubuntu CI runner the same mutant **survived**, because ext4 handed
back an already-alphabetical directory listing, so sorted and unsorted output were identical
and the assertion could not tell them apart.

**Why it came up:** the mutation harness is the thing that decides whether a test is real, so
a mutant that is only lethal on the developer's filesystem quietly certifies a decorative
test — on the one machine that gates the merge, no less. It was caught only because CI runs a
different OS than the laptop.

**Takeaway:** when a test's ability to *detect* depends on ambient state you cannot set
(directory order, hash order, clock, locale), move the contract into a pure function over
input you *can* set, and point the mutant at that. "It kills locally" is not the claim you
need; "it kills where the gate runs" is.

## An `await` inside a step machine that does not await is a race, not a wait

The QA harness runs one step per physics frame from `_physics_process`. One op,
`press_until_state`, was written as a coroutine: it `await`ed idle frames in a loop while
pressing a button. But the function that dispatches steps is not `async` and did not await it,
so calling it returned immediately and the *next* step ran a frame later while the presses were
still going.

**Why it came up:** building a second game on the template. Its script asserted a state
directly after a `press_until_state` and got the state from before it. The demo's own scripts
all happened to have a `wait` in exactly that spot, so nothing had ever exercised the bug.

The dangerous half is that the race is symmetric. A false *failure* is what surfaced here and
it cost an hour of looking at the wrong file — but `assert_state world` written in the same
place would have *passed*, because the conversation had not opened yet. A check that resolves
before the thing it is checking has started is a green light wired to nothing.

**Takeaway:** in a frame-driven state machine, never mix in a coroutine unless every caller
awaits it — prefer expressing the wait in the machine's own currency (a flag the tick loop
honours). And when you find such a race, pin it: the regression test here is a shipped script
with the `wait` deliberately *removed*, so the assertion sits exactly where the race was.

## A held input survives a scene transition, so "walk until you arrive" overshoots into the next room

Scripting a play session across three maps, several routes walked into a door while still
holding the direction key. The warp fires, the new map is built, the player is placed on its
spawn — and the key is *still held*, so they keep walking in the new map for the remainder of
the hold. One route ended up against the far wall of a room it had only just entered.

**Why it came up:** the counts were written by dividing distance by speed, which is correct
right up to the moment the map underneath changes. It reads as a broken warp ("we ended up
somewhere else"), not as an input that outlived its context.

Two smaller versions of the same class turned up in the same session. A body stopped by a
collider rests with its feet exactly on the blocking tile's edge, so `floor(y / tile)` reports
the tile it is *touching* rather than the one it is standing in. And a walk of "exactly two
tiles" landed at y=63.1 rather than 64 — fractional accumulation — which floors into the row
above and silently misses a warp one row down.

**Takeaway:** in a scripted end-to-end test, aim at things that *stop* you — a wall, a body —
rather than counting frames to a coordinate: a collider lands on the same pixel every run,
while a count lands wherever the tuning happens to be today. And never let a hold span a
transition unless the far side also ends against something solid.

## Clearing a default can make a mutant survivable, because a test's inputs came from the process

Enabling the game picker meant emptying `config/game` so that nothing chooses at boot. One
test then failed — expected — but fixing it exposed something worse: a mutant that had been
killing happily started to **survive**. The test had been asserting `unresolved()` is empty
"when something already chose", and what made that true was the project setting, read out of
the running process. With the setting gone, the assertion was true for a different reason, and
the branch the mutant broke was no longer reachable from any test.

The fix was to make the decision pure — `should_ask(ids, args, setting)` — so a test supplies
all three inputs instead of inheriting two of them from whichever process it happens to run in.
That is the same shape as `choose()`, which was already written that way for the same reason.

A second mutant on the new function then survived too, and it was also right: the
`ids.size() < 2` guard is redundant for **one** game, because `choose()` already answers with
that game. It only earns its keep at **zero**, which nothing had asserted.

**Takeaway:** a test whose inputs come from ambient process state (a project setting, an env
var, the command line, the clock) is a test whose meaning changes when that state does — and
the change is silent, because the assertion still passes. When a mutant starts surviving after
a config change, the config was propping the test up. And when a guard's mutant survives, ask
which input it is really for; usually there is an edge case nobody wrote down.

## A control instance must hold constant everything the experiment does not vary

The second game shipped with `allow_diagonal = false` and a slower walk cycle. Both were
deliberate, both were reasonable in isolation, and both were wrong — because that game's job
is to be the template's control instance. It exists to answer "what does building a game
actually change?", and every knob it varies for its own reasons is noise in that answer.

**Why it came up:** the user played it, could not walk diagonally, and asked what *else* was
missing. That question is the whole cost. One unexplained difference converts every future
difference into a suspected defect, and there is no cheap way to win that trust back — you
have to go and prove the negative for every other knob.

The gates could not have caught it, and that part is instructive too. All seven scripted play
sessions hold a single direction at a time, so `allow_diagonal` is invisible to every one of
them; the shipped-with-the-bug config passes `finish_the_quest.json` cleanly. A feature can be
absent for a whole milestone while every gate stays green, if no gate ever exercises the axis
it lives on.

**Takeaway:** when you build a second instance to validate an abstraction, hold every variable
the design does not demand — same config, same timings, same everything — and vary only what
you are trying to prove is variable. And a difference chosen *on someone's behalf* is a
decision to surface, not a detail to write into a file comment.

## An API that takes no delta is picking one for you

`move_and_slide()` has no delta parameter. It chooses one internally: the physics delta when
called during a physics frame, the *idle* delta otherwise. So how far one call moves a body is
not something the caller controls or can predict.

**Why it came up:** designing grid stepping, the obvious implementation lands the step by
scaling the last frame's velocity to cover exactly the residual distance — which needs to know
how far a frame covers. That works right up until the call happens outside a physics frame,
which is exactly what this project's integration tests do: they drive `apply()` by hand from a
coroutine so the whole movement path can be tested without a running game. The prediction would
have overshot in the one harness the design was being careful for.

The fix was to stop predicting. A step ends when its target stops being *ahead* — a fact about
position, needing no clock at all — and the last fraction of a pixel is handed back. The design
got smaller, and gained a documented cost instead of a hidden one: duration quantises to whole
frames.

**Takeaway:** when an API takes no clock parameter, find out which clock it uses before building
arithmetic on top of it — and prefer ending an operation by *observing that it finished* over
computing when it will. Pin the answer as a test: this one lives in `test_engine_assumptions.gd`
and asserts it is not running in a physics frame first, so it cannot quietly become vacuous.

## A test that drives the last layer by hand cannot see the state the layers before it set

`PauseScreen` latches itself once it has sent an answer to the world: a load rebuilds the map a
frame later, and a second keypress in that window would answer a settled question. A load that
comes back *refused* therefore has to clear the latch, or the menu sits on screen looking
perfectly normal with every key dead.

**Why it came up:** the integration suite drove the refusal by emitting `load_requested`
directly — clean, fast, and it asserted exactly the right outcome. The mutant that deletes the
un-latching line **survived**. Emitting the signal skips `_act()`, which is the thing that sets
the latch, so the test staged a refusal in a state where there was nothing to clear. It proved
the world's behaviour and nothing about the screen's. Rewriting it to navigate the menu with
real key events — down, down, in, down, down, in — killed the mutant on the next run.

Two harness facts fell out on the way, both of which read as broken tests rather than as broken
instruments. A simulated `InputEventAction` needs its matching **release**, or the second press
of the same action lands on an engine that thinks nothing changed. And a suite with no
`scene_runner` must `await get_tree().physics_frame`, not `await_millis(1)`: under load — a
mutation run, say — a millisecond spans no physics frame at all, so "the player did not move"
becomes a fact about how busy the machine is. That one surfaced as a mutation `BASELINE
FAILURE` on a suite that had passed by hand minutes earlier.

**Takeaway:** driving a component by calling its inner layer directly tests that layer in a
state the outer layers never put it in. If a rule is *about* state the outer layer sets — a
latch, a guard, a mode — the test has to come in through the front door, and a surviving mutant
is usually the only thing that will tell you it did not.

## A refusal that fires early hides the refusal behind it

A save whose game does not match its directory is refused by the loader and its bytes parked.
Through the pause menu, that check is unreachable: the slot list reads each file silently, a
foreign save does not read back, so the row renders as *empty* and Load refuses it before the
loader is ever called.

**Why it came up:** an integration test staged a quest save in the demo's slot, pressed Load,
and asserted the bytes were parked. They were not — nothing had tried to load them. The layers
are both correct and the outer one is strictly earlier, so the test's premise was wrong rather
than the code. Reaching the inner check through the UI needs a slot that goes bad *between* the
frame that drew the menu and the frame that loaded it, which is a real scenario and now the one
the suite stages.

**Takeaway:** when a system defends the same thing at two layers, work out which one fires
first before writing a test that aims at the second — and then decide deliberately whether the
inner one is reachable at all. If it is not, either stage the race that reaches it or say
plainly that it is defence in depth. "Assert it was rejected" is not enough when more than one
thing can do the rejecting.

## A find-and-replace over source is broken by writing new code, not by editing the pattern

`tools/mutants.tsv` aims each mutation at one line by matching its text. Two rows that had
been correct and untouched for milestones both broke in the same PR, because functions added
*next to* the code they targeted happened to repeat a line character-for-character: a second
inventory loop beside the pause menu's, and a second tile lookup beside the warp one. `sed`
edits the first match and says nothing, so each mutant silently started reporting a verdict
about a function nobody was testing, and the rule it was written to protect stopped being
covered.

**Why it came up:** CI caught it as `TOO BROAD` twice in one session, twenty minutes into a
mutation run, having passed everything locally — because locally only the *new* rows had been
run. Nothing in either diff looks wrong: the new code is correct, the new tests pass, and the
old rule fails silently.

**Takeaway:** treat "this line is character-identical to one somewhere else" as a hazard to
every scripted edit over source — mutants, codemods, `sed`, a rename. Fix it by making the two
lines differ (rename a local, and say why in a comment) rather than by loosening the pattern;
the duplicate is usually telling you the two functions are one copy-paste apart. And put the
ambiguity check in the always-on gate rather than behind the slow opt-in one:
`tools/mutants_aim.sh` answers it in about a second where the full run takes twenty minutes,
and cheap enough to be unconditional is what makes it actually run.

## A fight stops the player where they stood, which is rarely on a tile centre

The encounter check fires on arriving at a tile next to an enemy, and the world freezes the
player there mid-step. Their collider is 10px wide on 16px tiles, so a player halted a few
pixels off-centre straddles two columns — and the next leg, which walks them through a
one-tile gap in a wall, clips the wall beside it and goes nowhere.

**Why it came up:** the hollow's slink stands *in* the gap, which is what makes that fight
unavoidable by geometry rather than by a trigger radius. Winning it and walking on failed
silently: the player simply did not move, and a position assertion two steps later reported a
tile that looked almost right.

**Takeaway:** any walking leg that follows something which can interrupt movement — a battle, a
cutscene, a dialog that halts the player — must re-anchor against a wall before threading a
gap narrower than a couple of tiles. This is the same family as the existing rule that an
arriving hold carries the player onward: both are about a leg inheriting a position it did not
choose. Anchor first, then move.

## Headless does not mean fast when the thing you are waiting for is physics

A play script that walks five maps and fights four battles took six and a half minutes
headless — not because anything was slow, but because `_physics_process` still ticks at 60Hz
in real time. Every `hold` for 400 frames costs 6.7 seconds of wall clock whether the player
reaches the wall in 100 frames or not.

**Why it came up:** the first complete run of the reworked quest blew a 400-second timeout and
looked like a hang. Trimming the anchoring holds from "20 tiles, more than any map is wide" to
what each map actually needs cut it to 3:22 without changing a single assertion.

**Takeaway:** in a frame-driven test harness, the cost of a leg is the frames you *asked* for,
not the frames the work took. Budget them: a hold only needs to outlast the widest crossing of
the map it runs in. And when a headless run appears to hang, add up its declared frames before
looking for a deadlock — 13,000 frames is not a hang, it is three and a half minutes.

## A cue and its window that open together make the window the whole reaction budget

A timing mechanic showed the player a `!` at the exact frame the scoring window opened —
deliberately, so that the thing drawn and the thing judged were one comparison and could not
drift apart. The window was 8 frames, about 133ms, and the file's own comment called it
"forgiving enough that a person lands it". It was not: a human needs roughly 250ms to see
something and move, before the display and the browser take their share. The mechanic was
only hittable by anticipation, and the first person to play it said so in one sentence.

**Why it came up:** the numbers had been chosen against the *arithmetic* — a window small
enough that holding the button through the cue does not score — and that constraint is real,
but it only sets the upper bound. Nothing set the lower one, because no gate can feel a
control, and every automated proof passed: the balance tests still showed timing winning and
mashing losing, because the window is not in the damage formula at all.

**Takeaway:** if the telegraph and the window open on the same frame, size the window for
REACTING (250ms plus latency plus slack), and grow the wind-up to keep the window a small
fraction of it. More generally: a number that only a human can judge is not shipped until a
human has judged it — get it in front of someone before the milestone closes, not after.

## Audit a quest by asking how reachable each fact is, not by replaying it

A play-tester finished with an item they could not explain and a goal they never found, and
every automated gate was green — the scripted play sessions prove the quest is *completable*,
which is a different claim from *learnable*. Replaying it myself would have proved nothing
either: I knew where the key was.

**Why it came up:** what surfaced the defects was mechanical rather than intuitive. List every
fact a player needs to finish. For each, list every place the game states it. Then label each
statement FORCED (unavoidable on the critical path), LIKELY (a refusal fired by an obvious
attempt) or OPTIONAL (requires pressing something skippable). Two facts turned out to have no
statement at all, one was single-sourced in an optional line, and one lived in a conditional
line that later progress deleted forever.

Two anti-patterns worth naming, because both read as fine in review:

- **A purpose statement downstream of an unrelated gate.** Every line explaining the oil sat
  behind having the key, while the oil itself was free to pick up first. The orderings a player
  can take are not the ordering the author had in mind.
- **A conditional line whose facts die when it is outranked.** A priority chain (`most advanced
  state first`) is correct for tone and lethal for information: the newest branch silently
  deletes everything only the older branch said.

**Takeaway:** for any content with an information graph — a quest, an onboarding flow, a
troubleshooting doc — audit by fact reachability rather than by walking the happy path, and
treat "stated in exactly one optional place" as equivalent to "not stated".

## A UI that renders data has a capacity, and exceeding it is usually silent

A dialog box drew a two-line text area at 22px against a 12px font line, so only one line ever
fit; and it placed the choice list at a fixed offset that assumed one line of text. Longer
lines were clipped with no error and no log, and choices were drawn on top of the story. Four
shipped conversations were affected — three of them lines added the day before *specifically*
to tell the player where to go, so the fix for one bug was silently swallowed by another.

**Why it came up:** every gate passed the whole time. Nine scripted play sessions pressed
through those exact conversations on every CI run, and a headless harness never renders a
pixel, so "the dialog advanced" was the only thing being checked. The defect is only visible to
a person looking at a screen — or to arithmetic nobody had written down.

**Takeaway:** when a view renders content that other people will write, its capacity is part of
the content contract, not an implementation detail. Name it in constants, have the gate read
*those* constants (a gate with its own copy drifts, and the day it drifts the failure goes
quiet again), and measure with the real font rather than counting characters — proportional
glyphs make a character count a guess. And assert overlap as GEOMETRY: rects that must not
intersect, taken off the built nodes, not re-derived from the arithmetic the view already used.

## A res:// image is not a file at runtime, and a benign warning still costs something

`Image.load_from_file()` on a committed PNG warns "this will not work on export" — correctly.
A `res://*.png` in a shipped Godot build is not a PNG any more: the importer has turned it into
a compressed texture and the original bytes are not packed, so code that reads the file works in
the editor and fails on a player's machine. The runtime must ask for art as a *resource*
(`load()`); only build-time tooling may read the raw file.

**Why it came up:** all three call sites here were build-time — an art-drift gate and a
determinism suite whose whole job is comparing the committed file's pixels — so the advice was
aimed at the wrong code and the warning was harmless. It still fired 21 times per run, and the
user noticed it in CI and asked. That is the actual cost: a log with routine noise in it is a
log people learn to skim, which is where the next real warning goes unread. Decoding the bytes
explicitly (`FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer`) is the same pixels
with no resource system involved and nothing to warn about.

**Takeaway:** when a platform warns about an API, check which *layer* the warning is aimed at
before dismissing it — the same call can be a bug in the shipping path and correct in tooling.
Then either fix the cause or write the justification down where the next reader will find it;
"we know about that one" is not a state a build log can hold. And when swapping how a gate
reads its inputs, prove the gate still bites afterwards — a reader that silently returned
nothing would make it compare absence to absence and report success.
