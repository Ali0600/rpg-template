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

## An importer sits between the file you check and the asset the game plays

Godot re-encodes assets on import. Its WAV importer defaults to QOA, which is lossy, so a
generated cue can be verified byte-perfect on disk and still reach the player as something
else.

**Why it came up:** M14's drift gate compared committed PCM against freshly generated PCM and
passed. Reading one `.wav.import` showed `compress/mode=2` — every cue was being transcoded on
its way into the game, and nothing in the gate, the tests or the log mentioned it.

**Takeaway:** when a build gate checks a committed artifact, check what the RUNTIME loads too —
between the two sits an importer, a bundler or a minifier that is free to change it.

## A file that is committed but not imported is missing from the export

An imported asset ships as its `.import` sidecar plus the engine's cached copy; the original
file is not packed. So a generated asset with no committed `.import` works locally and is
absent from the build users get.

**Why it came up:** M14 generates 48 WAVs. The repo already commits `.png.import` files, but
nothing asserted it — and `.gitignore` ignores `.import/` the directory, which reads as though
it ignores the sidecars too.

**Takeaway:** if a pipeline generates assets, assert every one has its metadata sidecar
committed beside it — the failure only appears in the artifact nobody runs tests against.

## Bit-exact output across machines means avoiding the platform's maths library

IEEE-754 pins `+ - * /` to identical results everywhere. `sin`, `pow`, `exp` and `log` come
from the platform's libm and can differ in the last bit between architectures.

**Why it came up:** M14's generated audio is committed and compared by a CI gate that runs on
Ubuntu while the files are produced on macOS. One differing bit anywhere would fail the gate
for a reason unreproducible locally.

**Takeaway:** when output must be byte-identical across machines, build it from arithmetic and
integers only — and write down why, because the next person reaches for `sin()` immediately.

## A directory scan cannot see imported assets in an exported build

An exported Godot build does not contain the files you put in it. A `.tres` is packed beside a
`.remap`, and every imported asset — png, wav, ogg — is packed as its `.import` sidecar plus
the engine's cached copy, with the original left out. So `DirAccess`-based discovery looking
for `"ogg"` finds everything in the editor and nothing in the shipped build.

**Why it came up:** `AudioBus` discovered a game's drop-in sounds by scanning `data/audio` for
audio extensions. It had never been wrong because the directory had always been empty — the
seam was broken in exports from the day it was written, and had no payload to be broken with.

**Takeaway:** discovery that walks a directory is discovery that behaves differently in a
packaged build; resolve known paths where you can, and where you must scan, normalise the
packed name back to its source.

## Normalising two names to one means the environment with both now counts it twice

Stripping `.import` so a packed sidecar resolves to its source is correct in an export, where
only the sidecar exists. In the editor **both** exist, so every asset resolved twice and every
work list silently doubled.

**Why it came up:** the fix above turned 16 generated cues into 32 entries. Nothing crashed —
the drift gate still passed, because it iterates the cue vocabulary rather than the directory.
The only thing that noticed was an assertion comparing the shipped set against the expected set
exactly.

**Takeaway:** a normalisation that maps two names onto one must dedupe, and the bug appears in
exactly one environment — so assert the SET, not just that every member is present. "Everything
expected is here" is true of a list containing everything twice.

## A gate that classifies files by grepping their text can be flipped by a comment

This project's parse gate skips files naming an autoload, because a standalone parse cannot
resolve one. The skip list is derived by grepping each file — so *mentioning* an autoload in a
doc comment removes that file from the gate, as silently as calling one does.

**Why it came up:** teaching the dialog box to make a noise dropped it, and both suites that
depend on it, out of the parse gate. Rewriting the explanatory comment was part of the fix —
the prose alone was enough to keep the file excluded.

**Takeaway:** when a tool decides a file's treatment by scanning its source text — lint
directives, coverage exclusions, CI path filters — that decision is coupled to documentation as
well as to code, and the coupling is invisible at the point where it matters.

## A positional read of a collected list re-aims itself when anything is inserted

Tests that asserted `effects()[0]` and `effects()[1]` broke the moment a pickup cue was
appended ahead of them — the same failure as navigating a menu by counting presses, and it can
fail *silently* by pointing at whatever now sits at that index.

**Why it came up:** six interaction tests failed at once when `Interaction` started asking for
a sound. Rewriting them to address an effect by its OP made them immune, and clearer.

**Takeaway:** address an element of a collected list by what it IS, never by where it sits.

## A substring test for an identifier fires inside a longer identifier

The whole-project compile gate skipped files containing `Name + "."`. Adding a singleton called
`Settings` therefore matched every `ProjectSettings.` call, and nine files silently left the
gate.

**Why it came up:** the skip count went from 20 to 29 in a commit that referenced the new
singleton three times. Nothing failed — a skipped file is simply not compiled, so the gate went
on reporting success over a shrinking set.

**Takeaway:** match identifiers on whole-word boundaries, never as substrings; and when naming a
new global, check it is not the tail of something the platform already defines.

## A cycle test that only checks where it ENDS cannot see a cycle that never moves

`for each step: cycle()` then asserting the value is back at the default passes whether the
cycle visits all four steps or is pinned to the default the whole time.

**Why it came up:** the mutant replacing the advance with a constant survived. The fix was to
assert every step is visited exactly once on the way round.

**Takeaway:** for anything cyclic or reversible, assert the JOURNEY as well as the destination —
returning to the start is the one property a broken cycle shares with a working one.

## Headless does not mean fast when the loop is paced by the wall clock

A headless engine still runs its main loop in real time. A scripted play session that takes a
player three minutes takes the test suite three minutes, and no amount of CPU helps.

**Why it came up:** the play gate was 6m13s of an 18-minute CI run. `--fixed-fps 60` pins every
frame's delta and stops waiting between frames: 371s became 8s, with byte-identical output.

**Takeaway:** when a test harness is slow, check whether it is CPU-bound at all before
optimizing it — a simulation waiting on the clock is not working, it is sleeping.

## When a harness's cost is process startup, optimize the process count

The mutation sweep spent ~67% of ten minutes on engine startup: 275 boots at ~1.5s each, of
which 49 were baseline runs re-proving suites that a step 60 seconds earlier had proven green.

**Why it came up:** the tests inside those runs accounted for ~200s of 616s. Nothing about the
tests was slow.

**Takeaway:** profile a harness by counting the processes it starts, not by reading the code it
runs. The fix is fewer invocations — scope, deduplicate, or amortize — not faster tests.

## A speedup has to be proven not to have blunted the detector

Making a gate 17x faster is worthless if it now passes things it used to catch.

**Why it came up:** `--fixed-fps` changes the engine's timing, and every one of these harnesses
is timing-sensitive by design. The evidence that it was safe was not that the suite still went
green — a suite that tested nothing would also go green — but that **all 226 mutants were still
killed** and a deliberately wrong assertion still failed the run.

**Takeaway:** after any change that makes a gate faster, cheaper, or narrower, re-run the
thing that proves the gate can still fail. Green-after is not evidence; red-on-bad-input is.

## A gate over the source tree cannot see the packaging step

Every check can pass against `res://` in the project directory while the artifact users download
is missing something. Packing is a transformation, and an untested transformation is a place
defects live.

**Why it came up:** M14 shipped a fix for a bug that only exists in exports, and nothing could
verify it. Excluding the generated audio from the pack then produced a build that boots, walks,
talks and requests every cue exactly as it should — and is completely silent — while every
existing assertion stayed green.

**Takeaway:** if you ship an artifact, run a real check against the artifact. For anything with a
packaging step, the source tree and the package are two different programs.

## A missing input can present as a hang rather than an error

Pointing Godot's `--main-pack` at a nonexistent or truncated pack does not fail — it sits there
producing no output until killed.

**Why it came up:** the control for "does this gate bite" hung for five minutes. The same thing
then happened to the gate's own script, because a caller-supplied relative path stopped resolving
once the run changed directory.

**Takeaway:** bound any subprocess whose input you are deliberately breaking, and resolve paths to
absolute before anything changes directory. A gate that hangs reads as infrastructure flake, which
is the one failure nobody investigates.

## An assertion sited where the value is always full proves nothing

Three `assert_hp` calls across two long play sessions could not see the damage formula change,
because each sat right after a level-up and a level-up refills health.

**Why it came up:** a deliberately sabotaged combat formula passed five and a half minutes of
scripted play that appeared, from the file, to check health three times.

**Takeaway:** ask what the asserted value would be if the code were wrong. If the answer is "the
same, because something downstream normalises it", the assertion is decoration wherever it sits —
move it to the one window where the value is still the code's own output.

## Redirecting a command's output does not silence the shell's report of its death

`cmd >/dev/null 2>&1` hides everything the program writes. It does not hide
`Aborted (core dumped)` — that line comes from the **shell that waited on the command**, not
from the command, so it is written to the shell's stderr after the program is already gone.

**Why it came up:** the pack exporter writes a complete package and then aborts during shutdown.
The gate ignores that exit code for a stated reason, and the log still carried a crash line
sitting directly under the comment explaining the crash was expected — the kind of contradiction
that teaches people to skim a log.

**Takeaway:** to suppress it, make a wrapper shell the one that waits — discard *its* stderr and
have it exit normally, keeping the real status in a file if you still want it. And note this is
bash-version-dependent: bash 3.2 (macOS) does not print it and bash 5 (most CI) does, so "I
cannot reproduce it locally" is expected rather than evidence it is gone.

## A refactor with an exact expected output can be proven by a gate that already exists

Moving code to data usually leaves you asking "did I change behaviour?" and answering it by
reading the diff. When the output is a committed artifact, you can do better: the drift gate
already asserts `committed == what the generator makes now`, so a port that is meant to
change nothing is proven the moment that gate passes with the artifact untouched in `git
status`. No new test, no judgement call.

**Why it came up:** M16 moved six procedurally-drawn tiles out of `TileGen.TILES` and into
authored pixel art in `data/tiles/gb16.json`. Every pixel the old routines drew was one of
three ramp tones or transparent, so the conversion to the `.`/`1`/`2`/`3` alphabet was exact
— and `gen_sprites.gd --verify` reporting "39 files match" with `assets/generated` clean was
the whole proof. Reading the conversion by eye would have proven nothing.

Two details made it trustworthy rather than merely green. The converter read the old
routines back through **sentinel colours**, not a real style's ramp: two ramps in a real
palette can share a tone, and the read-back could then not tell tone 0 from tone 2. And the
port was followed by a **control** — flipping one character in the JSON turned all three
styles' tiles red — because a gate that passes after a change you cannot see is equally
consistent with the data never being read at all.

**Takeaway:** before hand-verifying a behaviour-preserving refactor, ask whether some
existing gate already pins the output exactly; if so, an untouched artifact is the proof.
Then break the new input once, to show the gate is looking at it.

## A gate that walks your data checks only the combinations your data happens to contain

A test that iterates a collection and asserts a rule per item reads as exhaustive. It is
exhaustive over the DATA, not over the rule — so any case the data has no example of is one
the gate silently stops checking, and it reports the same green either way.

**Why it came up:** `test_tiles.gd` walks every tile in the generated metadata and asserts
that solid tiles have a collision polygon and walkable ones do not. Sound. But every decor
tile the template shipped was also solid — the bush was the only one — so
"a decor tile that does not block" had never been checked by anything, and nobody could tell,
because the test passed on six tiles out of six. Authoring a rug (decor, walkable) closed it
by accident; a second test now asserts the bank has an example of all four solid × decor
combinations, and says which one is missing when it does not.

The general shape: when the *content* decides what the *gate* covers, coverage becomes a
property nobody is watching. Adding the missing example fixes today; asserting the
combinations exist is what stops it reopening the next time someone prunes the data.

**Takeaway:** for any gate that loops over data, write a second assertion about the data's
own coverage — every enum value, every flag combination, every branch of the thing you are
looping on has at least one example — so a shrinking corpus fails loudly instead of quietly
narrowing the check.

## Before placing something that moves, measure where your tests already walk

A test suite that drives a world through real input has an implicit map: the set of positions
it passes through. Nothing declares that set, so anything new placed in the world is placed
blind - and if the new thing MOVES, it can wander into a corridor a test depends on and break
it days later, in a test whose name has nothing to do with the change.

**Why it came up:** M17 gave NPCs patrol and wander behaviours. Exploration turned up that
seven of ten scripted play sessions use NPC bodies as *walls* - one asserts the exact tile a
particular NPC's body produces - so a wandering NPC in the wrong place would break sessions
about warps, sound and item pickups. Reasoning about which tiles were "probably safe" from
reading the scripts was going to be guesswork, so instead I put a one-line `print` on the
world's tile-change hook, ran all ten sessions, and rendered the result as an overlay on the
map. The answer was unambiguous: they use one vertical corridor and the right-hand third, and
the entire left half is untouched. Placing the walker there took a minute instead of an
argument, and the overlay also corrected a guess - one NPC everyone assumed was incidental
turned out to be standing on a visited tile.

The measurement is only half of it. A safe placement that is never *tested* for safety is a
claim, so the same session set was re-run with the route deliberately moved into the busy
corridor: one session failed, which is what makes "column 6 is safe" a finding rather than a
hope.

**Takeaway:** when adding something mobile to a world that tests already traverse, instrument
the traversal and look at it before choosing a position - a temporary print plus an ASCII
overlay costs minutes. Then prove the position matters by moving it somewhere bad and
watching a test fail.

## An unset engine property is not neutral - it is whatever genre the engine assumed

Engine defaults are chosen for the engine's most common use case, not for yours. Leaving one
alone reads as "no opinion" but is really "the default opinion", and when your genre differs
you inherit a feature you never asked for, doing something reasonable in a context where it
is wrong.

**Why it came up:** a player reported an NPC being dragged sideways when he walked past her -
but only when she approached from ABOVE; from below she just stopped. Two identical-looking
situations, one code path. `CharacterBody2D` treats every layer as a possible moving platform
by default, and a body reporting `on_floor` against a moving body inherits its velocity.
Touched from above, the player is a *floor*; from below, a *ceiling*. The asymmetry the player
described **was the diagnosis** - only a direction-dependent concept could produce it, which
pointed at the floor/platform machinery before any code was read.

Two things worth copying beyond the specific bug:

**Measure the symptom, not just the theory.** Instrumenting the running game showed her x
climbing in steps of exactly 0.8px per frame; walk speed is 48px/s at 60fps, so the drift rate
*was* the player's speed - which is what turns "something drags her" into "she inherits his
velocity". After the fix, 896 of 896 frames at exactly her column.

**Fix the feature, not the family.** The obvious fix was `MOTION_MODE_FLOATING`, which Godot
recommends for top-down and which deletes floors and ceilings outright. It also silently
changed how every body slides along every wall: eleven scripted play sessions were calibrated
against the old sliding, and one diverged into 16 cascading failures, none of them about NPCs.
The narrow opt-out (`platform_floor_layers = 0`) fixed the reported bug and changed nothing
else; the broader change became a recorded decision for someone who can *play* it. A fix whose
blast radius exceeds the bug is a redesign wearing a fix's clothes.

**Takeaway:** when behaviour differs by direction, orientation or side, suspect a
default-configured engine concept that is itself directional before suspecting your own logic.
Audit what you never set - that list is configuration you have implicitly accepted - and when
the clean fix and the narrow fix disagree in blast radius, ship the narrow one and write the
clean one down.

## A player-facing surface needs a reference pass before it is built, not a feel-check after

This project has a good habit for numbers a gate cannot judge: name them, ship them, and say
plainly that nobody has played them. That habit covers whether a window is 8 frames or 15. It
does not cover whether the screen should have a window at all.

**Why it came up:** M18 shipped a "shop" that was a transaction engine wearing three lines of
floating text — buy, sell, refuse and quest-item safety all correct and mutation-tested, with
no description bar (the field existed and went undisplayed), no quantity step, no keeper
dialogue, no windowed layout. Every gate passed. The user played it and asked whether I had
researched what a shop looks like in games. I had not: I had built it from the repo's own
menu idioms, which is how you get something internally consistent and externally wrong.

The reference pass took about ten minutes once done — a design codex already in the user's
own projects, a JRPG UI survey, a UI screenshot database — and produced a checklist the
implementation was then measured against: list with a price column, purse, description,
keeper voice, pick → how many → confirm.

**Takeaway:** before building a surface a player will look at, spend ten minutes on what that
surface conventionally IS — three real examples of the genre beats any amount of internal
consistency. "It matches our other menus" is not evidence that it matches the thing it claims
to be. And when a data field exists that the new screen could show, showing it is usually the
cheapest correctness win available.

**It happened again one milestone later, with the habit apparently working.** M19 DID do the
reference pass, and shipped everything it asked for: an `(E)` marker, a stat delta read
against what was already worn, a sell-counter refusal. The user played it and said equipment
should be its own menu screen like Items. The pass had been scoped to the equip
*interaction* — how it behaves — and never asked where equipment *lives*. Every reference
game keeps Equip beside Item as a sibling command; none of them equip from the item list. So
the question is two questions, and the second is the one that gets skipped because the first
one feels like diligence: **"how should this behave" and "where does this live, and what sits
beside it".** The fix was to stop re-deriving the answer per feature and write the anatomy
down once — `docs/GENRE_CONVENTIONS.md`, one section per surface, an audit table of what this
template has and does not, and named games behind every claim. A surface's section is now
read before it is built, and the same audit named two gaps nobody had noticed at all: no inn,
so gold only buys items and nothing outside a fight restores HP; and no way to see your own
HP or level outside a battle.


## A regex that rewrites call sites does not know about nested commas

Changing a function's signature across ~90 call sites is exactly the job a regex is for, and
exactly the job where a regex quietly produces something that still looks like code.

**Why it came up.** M28 made `open_battle_with(def, key)` take a list, so 25 test call sites
needed `def` wrapped in brackets. The rewrite was
`open_battle_with\((?!\[)([^,]+?), ` → `open_battle_with([\1], `. On
`open_battle_with(_enemy(), "key")` that is perfect. On
`open_battle_with(_enemy(1, 1, 5), "key")` the `[^,]+?` stops at the FIRST comma — inside the
argument's own parentheses — and the result was `open_battle_with([_enemy(1], 1, 5), "key")`.
Twelve of them, all still shaped like function calls.

**What made it expensive was where the failure surfaced.** The parse error broke one test file,
gdUnit4 crashed on it with signal 11, and the crash was reported against
`test_image_file.gd` — a suite about reading PNGs, with no connection to battles at all. I ran
that suite alone (green), then diffed against a clean checkout to establish the crash was mine
before I had any idea which file was at fault. The whole detour was avoidable: the compile gate
had already named the real file, and I had read past it because the tests were passing.

**Takeaway:** a regex over code must be verified structurally, not by eye and not by "the tests
still run". After any bulk rewrite of call sites, re-parse or bracket-balance **every line you
touched** — a ten-line script that walks each rewritten line counting `([` against `)]` finds
in one second what a segfault in an unrelated suite hides for ten minutes. And when a crash
lands somewhere implausible, trust the *compiler's* file over the crash's: a parse error
anywhere can take down a test runner everywhere, so the stack trace names where it died, not
where it was wrong. (Pairs with the mutation-harness rule about proving a sabotage applied
where you meant it — same family: a mechanical edit is a hypothesis until something structural
confirms it landed.)


## A cited convention is still a hypothesis about how something feels to hold

The reference pass tells you what the genre DOES. It cannot tell you how your version of it
feels under a thumb, and those come apart most sharply on the mechanics that are about *pacing*
rather than about content.

**Why it came up.** M27's party research was the best this repo has done: every claim cited to
a named game, forks recorded, the round shape argued from Final Fantasy I's own manual (enter
commands for all four characters, *then* the round executes) and Dragon Quest's turn structure.
It shipped command-all-then-resolve, fully tested, layout-audited, mutation-covered. The first
person to play it rejected it in one sentence: *"if I choose Attack with the MC, it doesn't
attack right after, the new party member chooses. It shouldn't be like that."* Nothing was
broken. The citations were accurate. A press whose effect is invisible for a whole extra menu
simply reads as a press the game missed, and no amount of authority behind the design changes
what the hand expects.

The replacement — each member acting the moment they choose — turns out to be equally attested
(Super Mario RPG: characters "wait their turn to perform an action", and "when it's your turn to
act, you'll choose an action"). So the research had not been wrong; it had been *incomplete in a
way that could not be noticed from the inside*, because it surveyed the NES entries thoroughly
and stopped, and the two families it found both looked fine on paper. Choosing between them was
never a research question.

**What made the reversal cheap** is worth as much as the lesson: resolution order never changed,
only the asking, so the same choices produced the same damage, the same seeded draws and the same
sealed numbers. The played session came out at identical hp and xp afterwards, which is what
proved the change was choreography rather than balance. When a rework leaves an invariant like
that available, assert it explicitly — "if any expected value changes, stop and investigate" —
because silently re-recording the numbers is how a real regression gets accepted as part of a
refactor.

**Takeaway:** classify each researched decision as *content* (what exists — a description bar, a
price column, a status page; research settles it) or *pacing* (when things happen relative to the
press — a round shape, a window, an animation length; research narrows it and a person decides
it). Put pacing decisions in front of a player early, in the milestone that ships them, flagged
the way this repo already flags unjudged numbers. And when one is reversed, delete the machinery
it needed rather than leaving it switchable: the queue, its take-back, and the staleness re-checks
that only existed because a choice could go stale all went in the same commit as the rule.


## Designing a feature so it needs no persistence

Some state does not have to be stored — it can be **recomputed from something already
stored**. Deciding which of the two a new feature is, before writing it, changes how much
machinery it needs.

**Why it came up.** M25 added magic. The obvious shape is a known-spells list: the player
learns a spell, it goes in a set, the set is saved. That shape needs a `GameState` field, a
`SaveData` field, a migration step, a `problems()` rule, an effect op for learning, a menu
verb, and an invariant nobody can see — that the set agrees with the level that produced it.
The genre research killed all of it in one line: Dragon Quest and Chrono Trigger unlock
spells at a level threshold automatically. So `SpellDef.learn_level` is the whole mechanism,
the world filters the registered spells by the player's level every time it opens a fight,
and none of the machinery above exists. A designer retuning `learn_level` retunes every
existing save, for free, because there was never a second copy of the answer.

The same reasoning already ran through this codebase and it is worth naming as a pattern:
`CombatDef.attack_at(level)` derives a stat rather than storing one, for exactly this reason —
gear had to become a MODIFIER rather than a stat, because a stored attack would have been a
second source of truth for one number.

**Takeaway:** before adding a field to a save, ask what it could be *derived from* instead.
Anything derivable is a field, a migration, a validator and a drift bug you do not write —
and the drift bug is the expensive one, because it appears as the two copies disagreeing
hours into a run. Storage is for facts the system cannot recompute: what the player CHOSE,
where they are, what they were given. Not for conclusions.

## A cheap alternative is not the same as a cheap fix for the alternative

When a design records a rejected option as "deferred — worth trying", it is worth noting
*why* it was rejected, because "we did not need it yet" and "it costs more than it looks"
lead to different decisions later.

**Why it came up.** M25 rejected teach-by-item spell learning (Dragon Quest's scrolls) in
favour of level thresholds. Both are real conventions and the scroll one is arguably more
interesting. But it is not a small addition on top: it *requires* the stored known-spells set
that the chosen design exists to avoid, so picking it up later costs a save field, a
migration and a validator — the entire cost of the alternative is the thing the chosen
design was chosen for. Written into `DECISIONS.md` that way, the backlog entry now says what
it will cost rather than just what it is.

**Takeaway:** in a decision record, price the deferred alternatives, not just name them. An
option that is one afternoon and an option that reopens a schema both read as "deferred" on
a backlog, and the difference is the whole reason the list exists.

## Web audio loops on a DOM event, not on the audio buffer

A Godot web export plays sound two ways, and only one of them loops the way you would assume.
Since 4.3 the web default is **Sample** playback, which hands the whole track to the Web Audio
API as a buffer — and Godot then implements looping *itself, in JavaScript*, by listening for
the source node's `ended` event and building a fresh node when it fires. **Stream** playback
instead runs Godot's ordinary cross-platform mixer, which reads `AudioStreamWAV.loop_mode`
directly and waits on nothing.

**Why it came up.** Chasing a report of music not looping in Safari. The report turned out to
be the in-game volume, but the source-dive stands: setting `loop_mode` is *necessary and not
sufficient* on the web, and if the browser does not fire `ended`, the music simply stops — no
error, nothing in the console, and every headless gate green because a dummy audio driver
cannot hear anything either.

**Takeaway:** when a platform re-implements something you think of as primitive — looping,
timing, focus — find out what it actually rests on before trusting a property you set. The
question is never "did I set the flag", it is "what consumes the flag, and on what does *that*
depend". Here the answer was a DOM event, which is a very different reliability story from a
number in a buffer.

## A settings toggle makes a working system indistinguishable from a broken one

Anything a user can switch off is a state your debugging has to rule out first, because from
the outside "muted" and "broken" produce identical evidence: nothing happens, and nothing says
why.

**Why it came up.** A silent game was investigated through the browser's autoplay policy, an
iOS audio-channel quirk, WebKit's `ended`-event handling and Godot's web audio source — and the
cause was the Sound row in the pause menu, set to off in an earlier session and persisted to
`user://settings.json`. Every layer examined was working correctly.

**Takeaway:** before reaching for the platform, check the product's own switches — the ones it
persists across sessions are the dangerous ones, because the user who set it will not remember
and the next session looks broken from a cold start. Worth designing against as well as
debugging against: a muted state that is only visible on one row of one menu is a state people
will forget they are in.

## The degenerate case as a list of one, not as a second code path

When a system that handles ONE of something grows to handle N, the tempting shape is a fast
path for one and a general path for many. The cheaper and safer shape is to make the one case
a list of one, and delete the fast path entirely.

**Why it came up.** M27 gave the battle a party. A game that declares no party is handed one
*synthesized* member built from the manifest's own player character and curve, so `BattleLogic`,
the screen and the menus always see a list. There is no solo branch anywhere.

**Takeaway.** With two paths, the one that is exercised constantly is the one that stays
correct, and the other is where bugs live unseen. One path means every existing test is a test
of the new code — sixty of this repo's seventy-nine battle tests never mention a party and
proved the rewrite anyway.

## A new validation that subsumes an old one makes the old one unfalsifiable

Adding a stricter check above or below an existing one can silently swallow it. The old guard
still reads as load-bearing, but deleting it now changes no behaviour, because the new one
refuses the same inputs.

**Why it came up.** `GameState.equip` gained "you cannot claim more copies than you carry".
That refuses an item you carry NONE of, which is exactly what the `inventory.has(id)` guard
above it existed for. Local runs were green; CI's full mutation sweep found the older mutant
SURVIVING, which is the only signal that would ever have fired.

**Takeaway.** When you add a check near an existing one, ask what the old one still refuses
that the new one does not. If the answer is nothing, collapse them — a guard whose removal
nothing can detect is a guard nobody is relying on. Mutation testing over the WHOLE file is
what catches this; a scoped sweep over your own diff may not.

## A body is only a reliable wall when it is approached square-on

In a physics engine with sliding movement, walking into an obstacle at a partial overlap does
not stop you — `move_and_slide` slides you around it. The same obstacle is an immovable wall
head-on and a non-event from the side.

**Why it came up.** Placing the demo's companion so a scripted play session could reach her
took three attempts. The first tile was unreachable (the map is ringed with warps, so a leg
east walks into a door). The second was reachable and the player walked straight THROUGH her —
the approach arrived from the side, having been pressed against a boundary one tile off centre.
The third sits against a wall so the approach is down a single column, which is the geometry
that makes the shipped warden a reliable blocker.

**Takeaway.** When a body must stop a walk, give it an approach that is axis-aligned and
wall-anchored. And measure where the tests already walk before placing anything solid — a
`print` on the tile-change hook plus a run of every session answers it exactly, where reasoning
about the map answers it plausibly.

## An undefined regex construct picks a side, and the two platforms disagree

A pattern can be malformed and still *work* — on the machine you wrote it on. In an extended
regex a closing parenthesis with no group open is undefined, so implementations are free to
guess: BSD `sed` (macOS) treats it as a literal and matches, GNU `sed` (most Linux CI images)
does not. Same file, same expression, opposite answers.

**Why it came up.** A mutation row ended `def.target\))` — first paren escaped, second bare.
`mutants_aim.sh` confirmed it landed on exactly one line locally, the PR was opened with
auto-merge armed, and CI reported the row STALE twenty minutes later on a machine nobody was
watching. The milestone was reported as shipped while that PR sat unmerged.

**Takeaway.** Escape every literal parenthesis in a regex, including the closing one, even
where it currently works. More generally: when a tool is available in two implementations
(`sed`, `awk`, `date`, `readlink`, shells), an *undefined* construct is worse than an invalid
one — invalid fails everywhere and gets fixed in a minute, undefined fails only where you
aren't looking. Where a check exists to keep such patterns honest, teach it to refuse the
ambiguous construct outright rather than to test whether it happens to match here; that is a
guard that travels, and a lint rule beats remembering.

## A set helper reused for ordered data silently drops the duplicates

Deduplicating and ordering are different jobs, and a helper written for one reads perfectly
well at the call site of the other. The failure is not an error — it is a shorter list.

**Why it came up.** `MapData._formation_of` built a fight's foes by appending each name through
`_add_ref`, which skips names already present because `enemy_refs` wants each enemy once for its
"does this exist" scan. So a record naming `slink` twice opened a fight against one slink. It
shipped a whole milestone earlier and nothing caught it: the only formation authored then was a
slink *and* a gloom, so no same-species pair ever existed to come out short.

**Takeaway.** When you reuse a collection helper, name the property you are relying on — "each
name once" or "every body in order" — and check the helper actually provides that one. And when
a feature's fixtures only ever use *distinct* values, the duplicate case has no coverage at all;
add it deliberately, because it is usually the commonest case in the wild.

## A harness that can only play badly cannot test content that must be played well

Test drivers tend to be written as "mash until something happens", which is fine while every
outcome is reachable by mashing. The moment content requires skill, the harness has no way to
express it — and the fixtures start encoding skill as arithmetic instead.

**Why it came up.** Scripted play sessions landed timed hits by waiting a computed number of
frames between presses, chained off the cue and message lengths in the combat data. That
arithmetic described one fight shape. When the boss gained an escort, every chain stopped ending
the fight, and it failed as "the battle never ends" half a script away from what had changed.
The fix was a `fight_well` op — press inside every window, confirm through every menu — which is
the scripted twin of the balance gate's PERFECT driver.

**Takeaway.** Give the harness a verb for *competent* play, not only for mashing, and let it read
the game's own signals rather than recompute them. Keep the mashing verb too: playing badly on
purpose is how you prove the difficulty is real. A driver whose skill is hard-coded in frame
offsets is pinned to the exact content it was recorded against.

## Assert against the store the system actually writes, and know when it writes

A pure component that collects its effects and applies them at the end will read as "did
nothing" to any assertion that inspects the destination mid-run.

**Why it came up.** A play session asserted the player's MP in the middle of a battle to check a
spell had been cast. Battles here are pure — the spend is a collected effect the world applies
when the fight closes — so the reading was always the pre-fight value. It looked exactly like a
cast that silently failed, and cost an hour of tracing menu navigation and input gating before a
`print` showed the spell resolving perfectly all along.

**Takeaway.** Before asserting on state, ask *when* that state is written, not just *whether*.
For anything that batches its writes — a transaction, a collected effect list, a deferred
flush — the only honest assertion points are before it opens and after it commits. A mid-run
read is not a weaker check; it is a check of something else.

## A cost is not an identity: asserting the resource cannot say which thing spent it

Checking that a pool went down by N proves something was spent, not *what*. The moment two
options cost the same, the assertion stops distinguishing them — and it keeps passing.

**Why it came up.** A play session cast a new buff through the real menu and asserted the magic
pool afterwards: 11 became 8, so the spell had landed. Three of that game's spells cost 3. A
mutant that moved the buff past the level cap made the cursor land on a damage spell instead,
which cost the same 3 — and the session passed while testing nothing it claimed to. The fix was
to assert the thing only that spell produces: the status tag on the caption.

**Takeaway.** Assert an effect that is *unique* to the path under test, not a side effect it
shares with its neighbours. Costs, timestamps, "a row was written", "the counter went up" are
all shared by construction. If the unique effect is not observable, that is a gap in the
instrument and worth closing — here it meant one new read on the view, and it made the display
decision assertable for the first time as well.

## A validation gate written for one content type is not inherited by its siblings

Content types accumulate. The gate that scans and validates them is usually written for the
first one and then quietly not extended, so the newest type — the one most likely to be
malformed — is the one nothing checks.

**Why it came up.** Enemy files had been scanned against `problems()` since they existed:
every file valid, named after its id, no duplicates. Spell files had shipped four milestones
earlier and were never scanned at all. It surfaced only because a mutant broke a shipped spell's
duration and every gate stayed green — the class's own unit tests were fine, because they test
the class, not the content.

**Takeaway.** When a validator exists for one directory of content, enumerate the sibling
directories and ask which of them it covers. Better: write the scan over the *set* of content
types rather than one type, so a new directory is covered by construction. And note the shape of
the discovery — a mutation aimed at DATA is what found a missing gate, which is an argument for
mutating data and not only code.

## A fixture derived by truncation inherits whatever the cut left behind

Building a new test fixture by copying an existing one and cutting the tail off is cheap and
usually right. The hazard is *where* you cut: a marker that appears several times sends the knife
to the last one, and the steps between the two you meant are silently kept.

**Why it came up.** A new play session was sliced from an existing one at "everything up to the
last `assert_state battle`". That kept the source script's own spell leg, so the new script's
cursor opened two rows away from where it was written to be and cast a different spell — and
every assertion still passed, because the two spells cost the same. Two independent mistakes
lined up: a cut on a repeated marker, and an assertion that could not tell the paths apart.

**Takeaway.** Cut on the step that *opens* the part being replaced — the note, the walk, the
navigation into the screen — never on a marker the script reaches more than once. Then read the
kept tail rather than assuming it: a derived fixture's bug is always in the region you did not
look at, because the region you wrote is the one you checked.

## A test that rebuilds the world for every case can never see the second visit

Checking each unit once, from a clean fixture, is the cheap and usually right way to test a set
of transitions. The cost is invisible: every defect that needs a *history* to appear is out of
reach, and the suite reads as exhaustive because it covers every unit.

**Why it came up.** A state-machine gate drove all 17 declared transitions, each on a world
built for it — every edge individually correct, and nothing about sequences. Injecting faults
showed the gap precisely: a screen that is *closed* but never *freed* stays in the tree and goes
on consuming the key that opens it, so the second time the player opens the menu nothing
happens. Per-edge cannot see that, because per-edge nothing is ever opened twice. The fix was a
layer that walks the same edges in seeded sequences on one world that is never rebuilt.

**Takeaway.** When a suite tears the world down between cases, name what that teardown hides —
anything cumulative, anything about a second visit, anything about order — and add one layer
that composes cases without rebuilding. And *measure* that it earns its place: inject faults and
run them against the old gate and the new one. Of seven candidates here, five behaved
identically both ways, including all three that had been reasoned out in advance as certain.

## A reduction that cannot produce an invalid candidate needs no way to recognise one

When you minimise a failing sequence, the generic move is delta debugging: drop things, keep
whatever still fails. Over a *graph* walk that move mostly produces sequences that are not walks
at all, and the search then has to tell "this did not reproduce the failure" apart from "this
could never have run" on every candidate.

**Why it came up.** A failing 24-step journey through the flow model needed to be reported as
something a person could read. Deleting the steps between two positions in the same state —
eliding a cycle — leaves the two ends touching, so every candidate is drivable by construction.
The first real failure minimised to five steps, and the answer was the bug stated exactly.

**Takeaway.** Look for a reduction move that preserves the structure's own validity rule, and
you delete the entire "is this candidate even legal" branch along with the bugs that live in it.
Then keep the search PURE — offer a candidate, be told whether it still fails — so the part that
decides what to try next is unit-testable without the expensive machinery that runs it.

## A wrong fact in a code comment outlives a missing feature

A gap in a system invites work: somebody eventually notices it and fills it. A wrong claim about
*why* the gap is correct invites citation instead, and it sits in exactly the place the next
person looks before touching the code.

**Why it came up.** A defeat cut the music dead, under a comment reading "every game this
borrows from cuts the music at a game over". Final Fantasy I ships a dedicated game-over theme
in 1987, and every entry since has one; the references *change* what is playing at a death
rather than falling silent. The claim had stood for four milestones, and it stood precisely
because it was written where a reader would look for permission to change the branch. Nothing
could have caught it: no gate can check a sentence.

**Takeaway.** When you write down *why* a divergence from a norm is correct, mark whether the
norm was **checked** or **remembered** — a remembered one is a hypothesis, and hypotheses belong
in prose that says so. Two habits fall out: do the reference pass before building the surface
rather than after, and treat "we do X because everyone does X" in an existing comment as a claim
with an expiry date rather than as settled, especially when you are about to build on it.

## Widening a type turns every null test into a different question

Replacing `T` with a richer type that can no longer be null is a mechanical refactor that the
compiler polices — except for the checks written against the old nullability, which still
compile and now mean something else.

**Why it came up.** Save slots moved from `Array[SaveData]` (null meant "empty") to
`Array[SlotSummary]` (an empty slot is an object). Every signature the compiler flagged was
fixed in minutes. The one it could not flag was `for entry in _slots: if entry != null: return
true`, which had meant "there is a save" and now meant "there is a slot" — true of every row. It
would have offered Continue to a player with nothing saved. Five suites caught it.

**Takeaway.** After widening a type, grep the *old* type's null tests by hand rather than trusting
the compiler: it verifies shapes and cannot verify meanings. Give the new type a named predicate
for the question the null used to answer (`has_save()`), so the surviving call sites read as the
question rather than as the representation.

## When the secondary sources are blocked, the shipped binary is the primary one

A disassembly is a reverse-engineered rendering of the actual bytes that shipped. When a wiki
describes a game's mechanic and a disassembly of that game shows the branch, the disassembly is
the stronger source — not the fallback.

**Why it came up.** Researching elemental damage before building it, every Final Fantasy wiki
returned 402/403, GameFAQs returned 403 on every guide, and the Internet Archive was offline, so
the usual route to "what multiplier does FF1 use" was closed. Reading the disassembly instead
answered it in one grep — and contradicted the answer everyone repeats. FF1 does not double on a
weakness; its own code comment reads `damage *= 1.5`, and its physical weakness is a flat +4 that
**never fires at all**, the player's attack element being annotated `BUGGED … always 0`. Half of
the system that defines the convention did not work in the shipped game. No secondary source
carried that.

**Takeaway.** For any question about how a shipped program behaves — a game's formula, a
protocol's framing, a library's actual default — prefer an artifact derived from the binary
(disassembly, decompilation, the source itself) over prose describing it, and treat a blocked
wiki as a prompt to go one layer down rather than as a dead end. The widely-repeated number is
the one most worth checking, because nothing is re-deriving it.

## Where a system announces itself should follow from its arithmetic, not from taste

Whether to tell the user what just happened reads like a UX preference. It is usually determined
by whether the number alone carries the information.

**Why it came up.** Deciding whether a fight should say "weak to it" or just show a bigger
number, the references looked like a coin toss: Pokémon announces every non-neutral hit, Dragon
Quest announces only failures, Final Fantasy I says nothing whatever. The pattern appeared once
the *mechanics* were lined up beside the *messages*. Pokémon and FF1 multiply; DQ's resistance is
a **chance to negate outright**, so there is no partial result to describe and only the failure
needs words. Where effectiveness is a multiplier, a bare number cannot answer "is 12 big?" —
the player has nothing to compare it against on the turn it happens — so the words are load
bearing. Our system multiplies, which decided it.

**Takeaway.** When surveying how references present something and they disagree, sort them by
the underlying mechanic before concluding the choice is arbitrary. And note the corollary that
settled this one: our sweep needed no announcement, because it prints every target's damage side
by side — the comparison the words exist to supply was already in the output.

## Two identical lines make a mutation report about the wrong function

A mutation harness that finds its target by text edits whichever match comes first. Two
character-identical lines in one file therefore make every mutant aimed at either one report a
verdict about the other.

**Why it came up.** A damage helper and a wording helper both opened with the same lookup —
`var pct := target.def.resistance_to(row.element)` — because both needed the same answer for
different reasons. The aim check refused the ambiguity immediately, and the fix was to rename one
local (`answer`), never to loosen the pattern. The hazard is that the duplication arrives
*later*: the old mutant was aimed correctly the day it was written, and new code stole its aim.

**Takeaway.** Duplicated lines are a testing-infrastructure hazard, not only a style one. Keep an
always-on check that every mutation pattern matches exactly one line, and when it fires, make the
two lines differ rather than making the pattern cleverer — a more specific pattern is one more
thing that rots on the next refactor.

## A gate's fixtures can be missing the thing its driver refuses to use

A simulation gate has two independent ways of not covering a subsystem: the driver may never
choose it, and the world the driver is handed may not contain it. Fixing the first without
checking the second buys nothing.

**Why it came up.** The balance gate plays every shipped fight to the end. Its driver only ever
chose the Attack row, so magic was unobserved — that much was known and documented. What was not
known is that the fixture beneath it handed the party an **empty spell page**: even a driver that
wanted to cast would have found nothing there. The blind spot was two layers deep, and the lower
one is the worse, because it means the gate was reporting on a fight the game does not contain.

**Takeaway.** When you find a driver that never exercises a path, check what the fixture would
have given it if it had. And when a gate builds its own version of production state, derive that
state through the same function production uses — a second implementation of "what does this
configuration produce" drifts silently, and the gate then certifies a system nobody runs.

## An explanation of why something needs no words is a claim about the data

"The numbers speak for themselves" is a design argument with a precondition hiding in it, and the
precondition is usually about the shape of the input rather than the output.

**Why it came up.** A sweep that damages several targets prints each one's number side by side,
so it was shipped with no verbal indication of effectiveness — the comparison being right there
on the line. That reasoning is correct exactly when the numbers DIFFER. Against a uniform group
every figure is identical, there is no baseline in view, and the reader is told nothing at all.
Every ordinary encounter in the game happens to be uniform, so one whole mechanic had never been
communicated once. A gate that asserted "every shipped rule is told to the player somewhere"
found it; no amount of re-reading the code would have.

**Takeaway.** When you justify omitting an explanation because the data makes it obvious, state
the property of the data you are relying on and then check it holds across the real corpus — not
the example you had in mind. The general form: a UI that conveys meaning by COMPARISON needs at
least two distinguishable values, and the degenerate case is where all the values agree.

## A surviving mutant can mean the data masks the rule, not that the rule is dead

The standard readings of a surviving mutant are "the test entered below the thing it tests" and
"the assertion is a range where only an exact value distinguishes". There is a third: the
production data happens to make the mutated code and the original *equivalent*.

**Why it came up.** A test driver rotates through the items in a bag rather than always reaching
for the first row, and only reaches for one when somebody is hurt. Both rules survived mutation
against the shipped content — because the shipped bag EMPTIES. A driver that only ever wants the
first row still exhausts that stack and moves to the next; one that drinks regardless still stops
when there is nothing left. Neither rule was decoration; the content simply could not tell the
two implementations apart.

**Takeaway.** Before deleting a guard a mutant survived, ask what property of the *current data*
makes the two versions equivalent — and if the rule is real, move it to a suite whose fixtures
break that property. Two corollaries measured the hard way here. A "deep" fixture has to be deep
relative to the run, not just large: 99 of an item was not enough, because the run outlasted
them, and "both were eventually used" is satisfied by a driver with nowhere else to go — assert
the CONSECUTIVE pair instead, which no run length can mask. And a scenario cannot always stage
the degenerate case you want (there was no way to fight a foe that hurts nobody, because a
zero-power move still lands the attacker's base stat), so pin such a guard on the DECISION the
code makes rather than on how the whole run comes out.

## A test that derives its expectation from the field it is checking cannot fail

If a check reads a value to decide what to expect of that value, corrupting the value moves the
expectation with it. The assertion still reads as a real rule and is satisfied by construction.

**Why it came up.** A gate asserted that fights flagged as mandatory refuse an escape and the
rest allow one — deriving "is this one mandatory?" from each encounter's own flag. Setting that
flag on a tutorial enemy made the tutorial inescapable *and* changed what the test expected of it,
so the mutant survived. It was rewritten to compute the SET of fights that actually refuse and
compare it against an independently declared one. That fixed a second hole in the same move: the
original could not see a flag being DELETED either, because "everything flagged is refused" stays
true when the set only gets smaller.

**Takeaway.** An expectation must come from somewhere the code under test cannot reach — a
constant in the test, a spec file, a hand-written list. When the rule is about membership, assert
the membership: compute the set and compare it whole, rather than checking a property of whatever
happens to be in it. Both failure directions then fail.

## A containment check passes degenerate layouts

"Everything is inside the window" sounds like a complete statement about a layout. It is satisfied
by arrangements that are unusable, because the pathological cases are usually *smaller* than the
window rather than bigger.

**Why it came up.** A text label that ran off-screen was fixed by giving it a width and turning on
wrapping, gated by a new "nothing is drawn outside the window" audit. Mutation testing then showed
the width assignment could be removed with the audit still passing: with no width to wrap against
the label falls back to a single pixel, so the text becomes a tall column one word wide — entirely
inside the window, and entirely unreadable. Reading the code would not have found it; the audit
looked complete.

**Takeaway.** Bounds checks catch the overflow direction only. Pair them with a constraint in the
units the design actually declares — here a line count the view states as a capacity, matching a
sibling surface that already gated against the same number — so a layout has to be *drawable*
rather than merely *contained*.

## Replacing a slice of a file by its anchors deletes whatever grew between them

Editing a file by finding two landmarks and replacing everything in between is fast and reads as
surgical. It is not: anything added between those landmarks since you last looked goes with it.

**Why it came up.** Updating one helper in a test file, the edit cut from the helper's docstring
to the next test function by name — and four tests that had been added between them in the two
preceding milestones vanished. Nothing failed. The suite went green on 20 tests where it had run
24, because deleted tests do not report anything. The COUNT was the only signal, and it was
noticed because a previous run's number was still on screen.

**Takeaway.** Prefer an exact-match replacement of the thing you mean to change over a positional
slice, so a stale assumption fails loudly instead of taking neighbours with it. And whenever a
test file is edited mechanically, compare the test count against what it was before — the whole
class of "the tests are gone" failures is invisible to a pass/fail signal and obvious to a
denominator. This is the same instrument the build already uses to compare suites-ran against
suites-on-disk; it belongs one level down too.

## A check whose ability to DETECT depends on rendered metrics disagrees across machines

A test can assert the right thing and still be unable to see a fault, if what it measures is
produced by something the machine controls — font rasterisation, text shaping, DPI. The assertion
is correct on both machines; only its sensitivity differs.

**Why it came up.** A gate caught text drawn outside its window, proven by a mutation that turned
wrapping off. It killed locally and SURVIVED on the CI runner. The cause was not the platform
alone: a later change shortened the text, leaving the worst case one pixel over the limit —
305px against 304 — so the two platforms' metrics landed on opposite sides of it. Both runs were
"correct"; one simply could not tell.

**Takeaway.** When a check's power depends on ambient measurement, split the contract in two:
assert the CONFIGURATION that makes the outcome possible (this wraps, against a width somebody
chose) where nothing ambient can move it, and keep the measured assertion as the outcome check —
but aim your coverage proof at the deterministic half. Widening the fixture until it clears the
boundary is worth doing and is not enough on its own: it moves the boundary rather than removing
it, and the next content change moves it back. The tell is a mutant that dies in one place and
lives in another; treat that as a statement about your instrument, not about the platform.

## An assertion that can never be true is not a test, and only a sabotage will say so

A test that passes tells you nothing about whether it CAN fail. If the assertion is malformed
in a way that makes it vacuously true, it passes on the healthy tree, passes on the broken one,
and looks exactly like coverage in the file.

**Why it came up.** A new gate had to prove a menu row was absent for one configuration, so the
test read the rendered labels and asserted none of them `begins_with("Save")`. It passed. It
also passed with the code deliberately broken to draw that row — because every row here is drawn
with a `"> "` or `"  "` cursor prefix, so no label has ever begun with its own text. The
assertion could not have been true under any circumstances. Nothing in review would have caught
it; the mutation run caught it in one cycle, by SURVIVING.

**Takeaway.** Before trusting a new assertion, make it fail once on purpose. When it is about
rendered text, print what was actually drawn before writing the comparison — the string on
screen usually carries decoration (a cursor, a bullet, padding, a colour code) that the
predicate has to account for. Prefer a comparison that is exact after normalising (`strip`, then
`is_not_equal`) over a loose one like `begins_with`/`contains`, because the loose form is the one
that quietly becomes unfalsifiable. And read a surviving mutant as a claim about your TEST first
and about the code second.

## When two implementations of a rule exist, the second one is a view

Hiding one item from an ordered list breaks an identity nobody wrote down: that a cursor's index
IS the enum member it points at. Every reader of that list then needs the same mapping, and any
reader that keeps using the raw index is now pointing somewhere else.

**Why it came up.** Making a menu row conditional meant the index and the row stopped being the
same number. The logic layer got a `top_row(at)` mapping — and the VIEW still labelled its rows
by the raw index, so it drew "Save" over the row that answered "Load". Both halves were
internally consistent; the disagreement only existed between them. A mutation aimed at the view's
half was the thing that proved a test was needed there at all.

**Takeaway.** When you make a previously-total mapping partial (hiding a row, filtering an enum,
skipping a status), find every reader of the old identity in the same change — the logic, the
renderer, the input handler, the tests — and route them all through one function. Then test the
RENDERED result, not just the logic's answer: the logic being right proves nothing about the
layer that draws it, and the drawing layer is where the player actually experiences the bug.

## A deferred call and an immediate one are indistinguishable except on the real path

Code that says "do this next frame instead of now" is invisible to any test that does not
reproduce the reason for the delay. Every test that calls the thing directly passes either way,
so the deferral looks covered while being completely unprotected.

**Why it came up.** A screen opened from a conversation has to be opened DEFERRED, because the
conversation's own teardown closes the top overlay a moment later — opened inline, the new screen
is what gets closed, and the machine lands in a state nobody asked for with an orphaned screen
behind it. Nothing errors. Four tests of that feature all passed against the broken version,
because each staged the effect directly rather than through a real conversation.

**Takeaway.** For any "do it later" (`call_deferred`, `setTimeout`, a queued job, a debounce),
write the test that reproduces WHY the delay exists — the real caller, the real teardown, the
real ordering — and prove it fails without the deferral. If you cannot construct that scenario,
the deferral has no test, and saying so in the comment is more honest than the tests implying
otherwise. Everything else about the feature can be tested through the convenient seam; this one
rule cannot.

## A concurrency lane keyed on the branch lets two merges cancel each other

Superseding a stale run is right for a branch and wrong for a trunk. If both share one lane
key, the second merge kills the first merge's run — and everything gated on that run's success
quietly does not happen.

**Why it came up.** The gate's group was `check-${{ github.ref }}` with `cancel-in-progress`.
On a pull request `github.ref` is the branch, so a re-push supersedes its own earlier run, which
is what you want. On a push to the trunk it is always `refs/heads/main`, so every merge shares
ONE lane. Merging a second pull request a few minutes after the first cancelled the first one's
full mutation sweep mid-run; the deploy workflow triggers on that run completing and publishes
only on `conclusion == 'success'`, and a CANCELLED run is not a success, so that commit's deploy
was SKIPPED. Two green pull requests, a sweep that never finished, a site still serving the
commit before them, and nothing anywhere said so.

**Takeaway.** Key a concurrency group by the ARTIFACT the run produces, not by the ref:
`${{ github.event.pull_request.number || github.sha }}` gives a branch the superseding it wants
and gives two commits lanes they cannot share. Then look downstream — anything triggered by
`workflow_run` treats cancelled as not-success, so a cancelled gate silently withdraws a deploy,
a release, a notification. The reason this hides is that it self-heals: the next green run
subsumes the lost one and publishes the newer commit, so the damage is only ever visible in the
window between two merges, and only to somebody reading the run list rather than the checkmarks.

## A vendor's "required" list may describe what it WRITES, not what it accepts

Reading a JSON schema as if it were the loader's contract is a category error. The schema is
generated from the code that SERIALISES; the code that PARSES is a different function with
different opinions, and the two are not kept in step by anything.

**Why it came up.** LDtk's 1.5.3 schema marks 28 root fields required. Its own 0.9.3 sample
project — which current LDtk opens fine — is missing eleven of them. So "required" there means
"the editor always writes this". The loader's real requirements turned out to be both narrower
and sharper, and only readable in its source: three arrays it walks with no null guard on every
layer (a layer missing any of them aborts the entire file), a field reference that is dropped
silently when empty and CRASHES when it carries values, and duplicate ids that are accepted and
then silently corrupt cross-references.

**Takeaway.** When writing a file for somebody else's tool, rank your sources: the tool's own
OUTPUT (a real sample file) is the best, its loader source next, its schema after that, and prose
docs last. Emit what the tool itself emits rather than the minimum the schema permits — matching
the working example cannot be wrong, while trimming to the schema is guessing in a direction that
merely looks rigorous. And read the parser for what it does with what is MISSING: that is where
the real contract lives, and it is never in the schema.

## A round-trip test proves your reader understands your writer, and nothing else

Write-then-read is a satisfying, cheap, and almost entirely self-referential test. Both halves
share your assumptions, so any assumption that is wrong in both directions is invisible — and if
the point of the format is that a THIRD program reads it, that is the assumption that matters.

**Why it came up.** A converter to two editor formats round-tripped every shipped map perfectly.
It would have done so just as happily with tile positions written in grid cells where the editor
reads pixels — the file would import back correctly here and draw as a scrambled heap there.
Neither editor is installed, so nothing in the project could catch it. Validating the output
against the vendor's own published JSON schema was the nearest independent check available, and
it is a genuinely different question from the round trip.

**Takeaway.** For any format a third party consumes, find one check that does not run through
your own code — the vendor's schema, their validator, their sample file diffed against yours, or
best of all their actual application. Pin the meaning of each field with a test whose expected
value comes from the vendor's documentation rather than from your writer. Then say plainly, in
the suite's own docstring, what it does not prove; a green suite is persuasive, and the reader
deserves to know where its authority ends.

## An assertion whose expected value is the degenerate case cannot fail

Picking the convenient fixture — the first item, the empty list, index zero — often picks the one
value that makes a wrong implementation indistinguishable from a right one.

**Why it came up.** A test asserted that a tile's atlas offset equalled `index * tile_size`, using
the first tile in the bank. Its index is 0, so the expected value was `[0, 0]` — and a mutation
replacing the entire offset calculation with the literal `[0, 0]` SURVIVED. The assertion was
exactly right and could never fail. Repainting the fixture with a tile at index 4 killed the
mutant immediately.

**Takeaway.** When an assertion computes an expected value from an input, choose an input where
the computation has somewhere to be wrong: not the first element, not zero, not the identity. Then
assert the input itself is non-degenerate in the test, so the day somebody reorders the fixture
the test says why it stopped meaning anything rather than quietly passing.

## A file is not portable until the things it POINTS at travel with it

A generated file that references an asset by relative path is only correct where that asset sits
beside it. The reference looks fine in isolation, the file validates, and every test that reads
it back passes — because your own reader does not resolve the reference. Only the real consumer
does.

**Why it came up.** A map exporter wrote `image: "tiles.png"` into its tileset. Both editors
resolve that relative to the map file, and the atlas lived elsewhere in the project — so every
exported map would have opened with every tile BLANK. Nothing could catch it: the round-trip
importer takes the tile list as an argument and never looks at the image, and the vendor's JSON
schema is satisfied by any string. It surfaced the moment the file was opened in the real editor,
which is also the only place it could have.

**Takeaway.** When you emit a file that references another by path, ask what resolves that path
and from where — then make the export SELF-CONTAINED: copy the referenced asset in beside the
output and name it so two sources cannot collide. Test the NAME in the unit suite and the
PRESENCE in whatever gate does real file I/O, because they are different failures. And treat "my
reader round-trips it" as saying nothing whatsoever about references, since a reader that does
not follow them cannot notice they are broken.

## A uniform off-by-one across every cell is a convention, not a thousand bugs

When a comparison against an external tool fails on 100% of items by exactly the same amount, the
hypothesis "my data is wrong everywhere" is almost always worse than "we are using two different
encodings of the same thing".

**Why it came up.** Diffing a map exporter's output against the editor's own re-export reported a
mismatch on all 176 cells — and every single one was off by exactly 1. The file stores GIDs
(`firstgid + index`, so 1-based here); the editor's CSV export writes 0-based local tile ids. Both
were right. Correcting the comparison gave 352 cells and zero mismatches.

**Takeaway.** Before reading a mass failure as a mass defect, look at the DISTRIBUTION of the
error: uniform and small means an encoding or origin difference (0- vs 1-based, pixels vs cells,
inclusive vs exclusive, UTC vs local), and the bug is in the comparison. Scattered and varied
means the data. Check the tool's documented output convention before changing any code — the
instrument's units are part of the instrument, and reading them wrong nearly turned a correct
exporter into a fix.

## An open-content licence is a family plus a version, and share-alike is contagious

CC0, CC-BY, OGA-BY, CC-BY-SA and GPL are the standard terms free art carries. The first three
ask only for credit; the last two also require anything derived from the art to be released
under the same terms — one share-alike layer in a composed sprite makes the whole sprite
share-alike.

**Why it came up:** the LPC generator's catalogue names licences as "OGA-BY 3.0+" and "CC-BY-SA
3.0"; a style here lists FAMILIES and the importer refuses a layer offering none of them.
Matching by prefix would have accepted "CC-BY-SA 3.0" for a style that only allows "CC-BY".

**Takeaway:** enforce licensing in the build — by file, by family, version stripped, compared
whole — and write the derived work's own notice from the same data. A licence policy in a
README is a note nobody reads at the moment it matters.

## A fixed-offset sheet is addressed, never searched

The LPC "universal" sheet is always 832×3456 with every animation at a fixed row block (walk is
rows 8–11) whatever the user enabled; a missing animation is blank rows, not absent ones.

**Why it came up:** the first design searched the export for the walk block. The generator's
`constants.ts` has absolute `ANIMATION_OFFSETS`, so the importer addresses rows 8–11 directly,
refuses a sheet too short to hold them naming the rows, and refuses a blank block — "was it
exported with Walk enabled?".

**Takeaway:** before parsing a third-party layout, find the constant that defines it in the
tool's own source. A fixed layout is a contract you can assert against; a searched one is a
guess you can only hope about.

## `.gdignore` keeps build inputs out of the importer and out of the pack

An empty `.gdignore` file makes Godot's editor and exporter skip a directory entirely, while
`FileAccess` still reads everything in it.

**Why it came up:** `data/imports/` holds 832×3456 PNGs the game never loads. Without the marker
the importer would turn each into a texture and the exporter would pack it; with it,
`ImageFile.read_png` still reads the bytes at build time, and `strings index.pck` shows zero
`data/imports` entries beside a packed `credits.json`.

**Takeaway:** anything under `res://` that is an INPUT to a build step rather than an asset the
game loads goes under a `.gdignore` — and the pack is checked for its absence, not assumed.

## A typed array's `sort()` uses the element type's `<`, and StringName's is a pointer

`Array[StringName].sort()` orders by the address of the interned name, not its text, so a
"sorted" list of ids is deterministic within a run and meaningless to a human — or to a test
that expects `gb16` before `nes16`. Once, printed straight after the sort, four real ids came
back as `dusk16, gbnes16, lpc32, nesgb16` — so treat the call as unsafe, not merely unordered.

**Why it came up:** a scene test cycled Sprite Lab's styles by key presses and landed on the
wrong one; instrumenting the index showed it counting correctly through an order of
`dusk16, nes16, lpc32, gb16`. The lab had cycled in that order since M2.

**Takeaway:** sort identifiers as `String`s with an explicit comparator; a sort whose order
you never asserted is a sort you never had. Instrument the state before theorising about the
harness — the first two "fixes" were to the test.

## A recolour system is a palette-by-index contract, and the tolerance is part of it

The LPC generator ships one source image per layer, drawn in a material's BASE palette, and
makes every colour variant by replacing each base tone with the tone at the same index of the
target palette, matching source pixels within ±1 per channel. Older items ship one file per
colour instead, named after the variant.

**Why it came up:** composing a hero locally meant reproducing the browser's output pixel for
pixel. `palettes.ts` and the recolour guide gave the exact rule, and a test pins that ±1 matches
and ±2 does not — widening the tolerance is the mutant that paints colours the artist never keyed.

**Takeaway:** when re-implementing another tool's rendering, take the matching rule from its
source and pin it at both edges; a "close enough" tolerance is how two implementations of one
picture drift apart.

## A preview proves the pipeline ran; only looking for problems proves the output

**Why it came up:** all four hero previews rendered, the importer accepted all four, and two
were wrong for a person — a tattered cape whose fringe read as speckle at 64px, and a brown vest
on bronze skin over brown trousers that merged into one mass. Nothing headless could see either.

**Takeaway:** read a generated picture for what is WRONG with it — contrast, silhouette, noise —
before showing it to anyone, and record the re-cut in the recipe so the next reader sees why.

## Scale the container, not the contents

Two things can be made bigger: the numbers inside a layout, or the surface the layout is drawn
on. Scaling the surface leaves every constant, font size and measurement inside it true.

**Why it came up:** running the demo's art at 32px tiles meant the world had to double. Every UI
screen here lays out in raw pixels against 320x180 — margins of 6, fonts of 7 to 9, twelve save
rows down a 180px window — and three layout gates measure exactly those numbers. Doubling the
layout would have re-tuned all of it and left every gate measuring a window nobody is shown.
Doubling the WINDOW and drawing each `CanvasLayer` at 2x changed one property per layer, and not
one screen constant or layout assertion moved.

**Takeaway:** when a display has to change size, look for the one transform above the layout
before touching anything inside it — and keep the design size a constant the layout reads, never
a measurement of the live surface.

## A unit belongs in the field's NAME, not in a comment

A number is only a place if you know what it is measured in, and the thing that decides the unit
is usually somewhere else entirely.

**Why it came up:** saves recorded `position` in pixels, and how many pixels a tile is turns out
to be a property of the art style. Changing the demo from 16px to 32px tiles would have put every
existing save half way to where it was written — on a map that still parses, with every gate
green. The field became `tile` in tile units, and renaming it (rather than quietly re-meaning
`position`) made the compile gate enumerate all fourteen readers instead of leaving them to be
found by hand.

**Takeaway:** when a stored number's meaning depends on something outside the file, store it in
units that thing cannot move — and when you change what a field means, change its name in the
same commit so the compiler finds the readers for you.

## A conversion guard is invisible unless the test crosses the boundary

A line that reconciles two representations does nothing at all when both sides happen to agree,
and a fixture where they agree makes the line unfalsifiable.

**Why it came up:** loading a save re-derives the player's position with the destination map's
tile size, and a guard afterwards makes the game state agree with the body. The first test loaded
a 32px save into the 32px map it was already standing in — both conversions gave the same answer,
so deleting the guard changed nothing and the mutant survived. Starting the run in a 16px town
and loading into a 32px yard made the two answers differ and killed it. A second trap sat beside
it: waiting one physics frame after the load repaired the state anyway, because the tick writes
it every frame.

**Takeaway:** to test a line that reconciles two values, stage inputs where the two DISAGREE, and
check what else writes the same value before allowing a frame to pass.

## Redirect a fixture root after the thing under test has booted, not before

A test that repoints a directory constant is telling every reader of it a new story, including
the ones that ran before the test meant to start.

**Why it came up:** an integration suite pointed the map directory at `tests/fixtures/maps` and
then instantiated the world scene. The scene's `_ready` boots the shipped game, which went looking
for its own start map in the fixture directory, failed, and left the half-built map it had already
constructed behind. Six orphan nodes per test, no error, and every assertion still passing — the
only reason it surfaced is that the suite's orphan baseline was zero.

**Takeaway:** narrow a redirect to the window where it is needed — after the component's own
start-up, before the call under test — and keep a zero-orphan baseline so a leak is a failure
rather than a number nobody reads.

## A fixture that names live content goes stale as a refusal, not as an error

A test that spells out a value the shipped data also carries keeps agreeing with it until the
data changes, and then disagrees in the voice of the thing under test.

**Why it came up:** the demo's maps changed art style. Two editor round-trip suites had the old
style name written into their coupling checks, so every one of them reported every shipped map
as painted against the wrong tile bank. It reads as the translator failing. Worse was an NPC
suite that hardcoded the same tile size in two places: the pair cancelled, so it had been
passing against a world drawn at neither size, and correcting one half made it fail.

**Takeaway:** derive fixture values from the artefact under test, and when two places must agree
on a number, make one of them read the other rather than repeating it.

## Ask what a consistency gate is a proxy FOR before demanding equality

A gate that requires several things to be identical is often standing in for a weaker property
that is what you actually need, and the difference shows up when the population widens.

**Why it came up:** imported character sheets were required to share one ground row. That was
right for a procedural cast, where every frame comes from one rig. With hand-drawn art it
demanded that four different body types be drawn identically by a dozen artists — and they are
not, by one pixel. Since each sheet carries its own measured anchor, exact equality bought
nothing: the property actually needed was that nothing OTHER than a foot is being measured. The
rule became exact within a body type, and bounded across the cast.

**Takeaway:** when a gate starts failing on legitimate new inputs, restate what it protects
before either weakening it or bending the inputs — the restatement is usually narrower in one
direction and stronger in another.

## A spacing constant is a fraction of the thing being spaced

Layout numbers are chosen while looking at content of a particular size, and they silently
encode that size.

**Why it came up:** the battle screen staggered party members 18 pixels apart, which was chosen
for characters 32 pixels wide. Fighters twice that wide stood in each other, one face showing
over another's shoulder. Naming the width the number was chosen against and scaling by it kept
the group's shape at both sizes, and left the original numbers exactly as they were.

**Takeaway:** when a layout constant survives a change of content size unchanged, check whether
it should have — and express it against whatever it was measured against, so the old value falls
out arithmetically.

## A scoping rule that includes its own bookkeeping file scopes nothing

A filter meant to select a subset will select everything if the file the subset is DESCRIBED in
is inside the filter's own trigger.

**Why it came up:** CI picks which mutation tests a pull request needs by looking at what the
diff touched, and treats any change under `tools/` as "the harness moved, run everything". The
list of mutants lives at `tools/mutants.tsv`, and the project's contract requires every new rule
to add a row to it — so every pull request that obeyed the contract ran the full sweep. Nine of
the last ten did. The fast lane and the slow lane were the same eighteen minutes, and three
places in the documentation said otherwise.

**Takeaway:** when a rule says "changes to X mean we cannot narrow", list the files that
actually make narrowing unsafe instead of naming their directory — and check whether the data
the narrowing reads is sitting in that directory.

## An instrument that reads a log must skip the log's own echo of itself

Searching a CI log for a phrase finds the step that PRINTS the phrase as well as the step that
means it.

**Why it came up:** auditing which mutants each pull request selected, the first pass grepped
the run logs for "nothing this change touches has a mutant" and reported that every recent run
had scoped down to nothing. That string appears in the workflow's own shell script, which the
log prints verbatim before running it. The truth was the opposite — every run had selected
essentially all of them — and the wrong answer was the reassuring one.

**Takeaway:** when grepping output that contains the source of the thing being measured, anchor
on the part that only the RESULT can produce (a count, a timestamped line, a field the script
does not contain), and sanity-check the finding against a second signal such as the step's
duration.
