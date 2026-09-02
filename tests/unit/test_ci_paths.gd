extends GdUnitTestSuite
## The rule that decides which changes run the real gate, and the lane the gate runs in.
##
## The predicate itself lives in tools/ci_changed.sh - one script, with its own selftest -
## because it used to be a `paths:` list in ci.yml mirrored by an inverse list in a second
## workflow, and a rule spelled twice in YAML is one nobody can run. This suite calls that
## script the way CI does and pins the answers that matter, plus the two properties of the
## workflow file that no script can hold: that the drift-gated docs are re-included in the
## push filter, and that the required `check` job reports whatever happened above it.
##
## The stakes are asymmetric, which is why the wrong answers are named in the failure messages:
## a `true` too many runs the gate for nothing, and a `false` too many lands a change with a
## green check that tested it.

const REAL := "res://.github/workflows/ci.yml"
const PREDICATE := "res://tools/ci_changed.sh"


## What tools/ci_changed.sh answers for a set of changed paths - run exactly as ci.yml runs it,
## rather than re-implemented here. A test that re-implemented the rule would agree with itself.
func _needs_gate(paths: Array) -> bool:
	var args: Array[String] = [ProjectSettings.globalize_path(PREDICATE), "--files"]
	for p: Variant in paths:
		args.append(str(p))
	var out: Array = []
	var code := OS.execute("bash", args, out, true)
	assert_int(code).override_failure_message(
		"tools/ci_changed.sh exited %d for %s: %s" % [code, paths, out]).is_equal(0)
	var answer := str(out[0]).strip_edges()
	assert_bool(answer == "true" or answer == "false").override_failure_message(
		"the predicate answered '%s' for %s, which is neither true nor false" % [answer, paths]
		).is_true()
	return answer == "true"


## Every `- "..."` entry in the paths: block that follows `marker`, in order.
func _paths_after(path: String, marker: String) -> Array[String]:
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message("%s is missing or empty" % path).is_not_empty()
	var at := text.find(marker)
	assert_int(at).override_failure_message(
		"%s does not contain '%s'" % [path, marker]).is_greater(-1)
	var out: Array[String] = []
	var in_paths := false
	for line in text.substr(at).split("\n"):
		var lean := line.strip_edges()
		if lean == "paths:":
			in_paths = true
			continue
		if not in_paths:
			continue
		if lean.begins_with("#"):
			continue
		if lean.begins_with("- \""):
			# Between the quotes, so a trailing comment on an entry does not leak into the
			# value - one copy carries a comment precisely so the mutant harness can tell the
			# two otherwise-identical lists apart.
			var open_at := lean.find("\"") + 1
			out.append(lean.substr(open_at, lean.find("\"", open_at) - open_at))
			continue
		break
	assert_int(out.size()).override_failure_message(
		"no paths parsed after '%s' in %s - the shape changed and this read nothing"
		% [marker, path]).is_greater(0)
	return out


## The docs each generator writes and a drift gate compares, DERIVED from the generators
## rather than listed here - so the next gen_*_doc.gd cannot be forgotten by this test.
func _drift_gated_docs() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files("res://tools", ["gd"] as Array[String]):
		var text := FileAccess.get_file_as_string(path)
		var at := text.find("const OUT := \"res://docs/")
		if at < 0:
			continue
		var start := at + "const OUT := \"res://".length()
		out.append(text.substr(start, text.find("\"", start) - start))
	return out


func test_the_two_ci_scripts_prove_themselves() -> void:
	# Both carry a selftest and check.sh runs the scoper's at step 8b, which is enough to catch
	# a break and NOT enough to prove the rules are tested: a mutant needs a SUITE to judge it,
	# and a rule whose only witness is a step in a shell script has none. So they run here too.
	#
	# The scoper's is the one that matters most. Its harness rule used to sweep every mutant for
	# any change under tools/ - including tools/mutants.tsv, which this project's contract
	# requires every new rule to touch - so the pull request lane was the full sweep wearing a
	# fast name for nine of its last ten runs, and nothing said so.
	for script in [PREDICATE, "res://tools/mutants_scope.sh"]:
		var out: Array = []
		var code := OS.execute("bash",
			[ProjectSettings.globalize_path(script), "--selftest"], out, true)
		assert_int(code).override_failure_message(
			"%s --selftest failed:\n%s" % [script, "\n".join(PackedStringArray(out))]).is_equal(0)


func test_the_predicate_answers_for_the_things_that_can_break_the_gate() -> void:
	# Fixed points on both sides. Code, content, tests and the harness run it; prose does not.
	for path in ["scripts/world/world_scene.gd", "tests/unit/test_saves.gd",
			"data/maps/quest_village.json", "tools/check.sh", ".github/workflows/ci.yml",
			"project.godot", "assets/generated/lpc32/quest_wanderer.png"]:
		assert_bool(_needs_gate([path])).override_failure_message(
			"'%s' would skip the gate, landing with a check that tested it" % path).is_true()
	for path in ["CLAUDE.md", "README.md", "docs/DECISIONS.md", "docs/lpc_designs/the_road.json"]:
		assert_bool(_needs_gate([path])).override_failure_message(
			"'%s' runs the whole gate, which can prove nothing about it" % path).is_false()


func test_one_file_that_matters_pulls_the_whole_change_through_the_gate() -> void:
	# The direction that must not be an average: a change is docs-only when EVERY path in it is.
	assert_bool(_needs_gate(["docs/DECISIONS.md", "scripts/world/world_scene.gd"])) \
		.override_failure_message(
		"a change touching docs AND code skipped the gate").is_true()


func test_no_evidence_is_not_evidence_of_no_change() -> void:
	# An empty diff is more likely a base ref that did not resolve than a pull request with
	# nothing in it, and the safe answer to "I could not tell" is to run the gate.
	assert_bool(_needs_gate([])).override_failure_message(
		"an empty change list skips the gate, so a broken merge base reads as a docs change"
		).is_true()


func test_every_drift_gated_doc_runs_the_real_gate() -> void:
	# docs/FLOW.md is generated from the flow model and compared by check.sh - a hand-edit
	# landing without the gate would turn every LATER run red while its own was green. Derived
	# from the generators, so the day a second gen_*_doc.gd writes into docs/, this fails until
	# its output is excepted both in the predicate and in the push filter.
	var gated := _drift_gated_docs()
	assert_int(gated.size()).override_failure_message(
		"no generator writes into docs/ any more - if that is true, this rule and the "
		+ "exceptions in the predicate and the workflow can go").is_greater(0)
	var push_paths := _paths_after(REAL, "push:")
	for doc in gated:
		assert_bool(_needs_gate([doc])).override_failure_message(
			"%s is generated and drift-gated, but the predicate lets it skip the gate that "
			% doc + "exists to catch exactly that").is_true()
		assert_bool(push_paths.has(doc)).override_failure_message(
			"%s is generated and drift-gated, but ci.yml's push filter does not re-include it "
			% doc + "- a hand-edit pushed to main would run no gate at all").is_true()


func test_the_push_filter_still_starts_from_everything() -> void:
	# The push side is the one place a `paths:` list survives, and it is subtractive: start
	# from everything, then take the prose out. Inverted - a list of what to INCLUDE - a new
	# top-level directory would silently run no gate at all.
	var push_paths := _paths_after(REAL, "push:")
	assert_str(push_paths[0]).override_failure_message(
		"the push filter no longer starts from everything, so a new directory runs no gate"
		).is_equal("**")


func test_the_required_check_reports_whatever_happened_above_it() -> void:
	# GitHub reports a SKIPPED required check as success. The `check` job therefore has to run
	# in every outcome, including the ones where the jobs it needs were skipped or failed - so
	# its condition is `always()` and nothing else. Any other conditional here turns "the gate
	# never ran" into a green merge, silently, which is the exact failure the whole file exists
	# to prevent.
	var text := FileAccess.get_file_as_string(REAL)
	var at := text.find("\n  check:\n")
	assert_int(at).override_failure_message(
		"ci.yml has no job named `check`, which is the status the ruleset requires"
		).is_greater(-1)
	var block := text.substr(at, 200)
	assert_str(block).override_failure_message(
		"the required `check` job is conditional on something other than always(), so a run "
		+ "where the gate was skipped would report success").contains("if: always()")
	assert_str(block).override_failure_message(
		"the required `check` job does not wait for the gate and the sweep, so it can report "
		+ "before they have").contains("needs: [changes, gate, sweep]")


## The concurrency lane, which decides whether two merges can cancel each other.
func _concurrency_group(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message("%s is missing or empty" % path).is_not_empty()
	var at := text.find("concurrency:")
	assert_int(at).override_failure_message(
		"%s declares no concurrency block, so nothing supersedes anything" % path).is_greater(-1)
	for line in text.substr(at).split("\n"):
		var lean := line.strip_edges()
		if lean.begins_with("group:"):
			return lean.trim_prefix("group:").strip_edges()
	fail("%s has a concurrency block with no group in it" % path)
	return ""

func test_two_merges_cannot_cancel_each_other() -> void:
	# MEASURED, not reasoned about: keyed on github.ref, every push to main shared one lane -
	# github.ref is always refs/heads/main - so merging a second pull request killed the first
	# one's full mutant sweep mid-run, and pages.yml (which deploys only on
	# `conclusion == 'success'`) SKIPPED that commit's deploy. Two green pull requests, a sweep
	# that never finished, and a site still serving the commit before them.
	#
	# The group must therefore be keyed on something that DIFFERS between two merges. The commit
	# does; the branch does not.
	var group := _concurrency_group(REAL)
	assert_str(group).override_failure_message(
		"the gate's concurrency lane is keyed on the ref (%s), so the next merge to main "
		% group + "cancels this one's sweep and skips its deploy").not_contains("github.ref")
	assert_str(group).override_failure_message(
		"the gate's concurrency lane (%s) names nothing that differs between two merges to "
		% group + "main - keyed on anything shared, the second merge cancels the first"
		).contains("github.sha")

func test_a_branch_still_supersedes_its_own_earlier_run() -> void:
	# The other half, and the reason this is not simply `cancel-in-progress: false`: pushing
	# again to an open pull request SHOULD kill the run it just made stale, or every fix-up
	# commit leaves a run nobody is waiting for burning a runner for seventeen minutes.
	var text := FileAccess.get_file_as_string(REAL)
	var group := _concurrency_group(REAL)
	assert_str(group).override_failure_message(
		"the lane (%s) does not name the pull request, so two pushes to one branch no longer "
		% group + "supersede each other").contains("pull_request")
	assert_str(text).override_failure_message(
		"nothing is superseded any more, so a stale run can still gate a merge"
		).contains("cancel-in-progress: true")
