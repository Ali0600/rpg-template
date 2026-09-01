extends GdUnitTestSuite
## The two path filters that decide which changes run the real gate, kept as mirror images.
##
## ci.yml skips the gate for docs-only changes and check-docs.yml answers the required status
## in their place - which means the two lists are ONE rule written in two files, and a rule
## spelled twice is the drift this repo's lessons file warns about in every form. The stakes
## are asymmetric too: a path missing from ci.yml's negations runs the gate for nothing, but a
## path wrongly INCLUDED in check-docs.yml lets a change land with a green check that tested
## nothing at all.
##
## Godot has no YAML parser, so this reads the lists by line - which is fine, because the shape
## it accepts is the shape the files actually have, and a rewrite that breaks the parse fails
## this suite rather than silently reading an empty list.

const REAL := "res://.github/workflows/ci.yml"
const DOCS := "res://.github/workflows/check-docs.yml"


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


func test_the_push_and_pull_request_lists_are_the_same_list() -> void:
	# One rule, hand-copied because workflow YAML has no anchors worth trusting - so the copy
	# is pinned instead.
	assert_array(_paths_after(REAL, "push:")).is_equal(_paths_after(REAL, "pull_request:"))


func test_the_docs_check_is_the_exact_inverse_of_the_real_one() -> void:
	# Real: everything, minus the docs, plus the exceptions.
	# Docs: the docs, minus the exceptions.
	# Anything else and there is either a change no workflow answers - a pull request that
	# waits forever on its required check - or one BOTH answer where only the no-op is green.
	var real := _paths_after(REAL, "pull_request:")
	var docs := _paths_after(DOCS, "pull_request:")
	assert_str(real[0]).override_failure_message(
		"the real gate no longer starts from everything").is_equal("**")
	var real_skips: Array[String] = []
	var real_exceptions: Array[String] = []
	for entry in real.slice(1):
		if entry.begins_with("!"):
			real_skips.append(entry.trim_prefix("!"))
		else:
			real_exceptions.append(entry)
	var docs_includes: Array[String] = []
	var docs_exceptions: Array[String] = []
	for entry in docs:
		if entry.begins_with("!"):
			docs_exceptions.append(entry.trim_prefix("!"))
		else:
			docs_includes.append(entry)
	assert_array(docs_includes).override_failure_message(
		"the docs check answers for %s, the real gate skips %s - a change in the gap gets a "
		% [docs_includes, real_skips]
		+ "green check that tested nothing, or no check at all").is_equal(real_skips)
	assert_array(docs_exceptions).override_failure_message(
		"the real gate re-includes %s but the docs check still answers for %s"
		% [real_exceptions, docs_exceptions]).is_equal(real_exceptions)


func test_every_drift_gated_doc_is_kept_out_of_the_docs_shortcut() -> void:
	# docs/FLOW.md is generated from the flow model and compared by check.sh - a hand-edit
	# landing through the no-op check would turn every LATER run red while its own was green.
	# Derived from the generators, so the day a second gen_*_doc.gd writes into docs/, this
	# fails until its output is excepted in both files.
	var gated := _drift_gated_docs()
	assert_int(gated.size()).override_failure_message(
		"no generator writes into docs/ any more - if that is true, this rule and the "
		+ "exceptions in both workflows can go").is_greater(0)
	var real := _paths_after(REAL, "pull_request:")
	var docs := _paths_after(DOCS, "pull_request:")
	for doc in gated:
		assert_bool(real.has(doc)).override_failure_message(
			"%s is generated and drift-gated, but ci.yml does not re-include it - a hand-edit "
			% doc + "to it would skip the gate that exists to catch exactly that").is_true()
		assert_bool(docs.has("!" + doc)).override_failure_message(
			"%s is generated and drift-gated, but check-docs.yml still answers for it" % doc
			).is_true()


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
