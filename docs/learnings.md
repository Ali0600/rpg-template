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
