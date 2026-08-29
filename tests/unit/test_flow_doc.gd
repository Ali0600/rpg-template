extends GdUnitTestSuite
## The flow diagram, checked as a rendering of the model.
##
## check.sh already proves the committed file matches what the generator makes now. This proves
## the generator makes the RIGHT thing - the two are different questions, and only this one
## notices if the drawing rule itself changes.

const MODEL := "res://tools/flow_model.json"


func _model() -> Dictionary:
	var file := JsonFile.read(MODEL)
	assert_bool(file.ok).override_failure_message(
		"the flow model could not be read: %s" % file.error).is_true()
	return file.data


func test_every_state_and_move_reaches_the_page() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/FLOW.md")
	assert_str(doc).override_failure_message("docs/FLOW.md is empty or missing").is_not_empty()
	var model := _model()
	for key: Variant in model.get("states", {}):
		assert_str(doc).override_failure_message(
			"state '%s' is in the model and not on the page" % key).contains(str(key))
	for entry: Variant in model.get("edges", []) as Array:
		var edge: Dictionary = entry
		assert_str(doc).override_failure_message(
			"move '%s' is in the model and not on the page" % edge.get("action", "")) \
			.contains(str(edge.get("action", "")))


func test_a_move_that_changes_nothing_is_not_drawn_as_an_arrow() -> void:
	# A warp re-enters a map from WORLD and stays there. Drawing it would put a self-arrow on
	# the busiest node in the diagram for a move that changes no state at all - and the picture
	# would then disagree with the model it is drawn from.
	# Rendered here rather than read off disk: the committed page is what the drift gate
	# compares, and comparing a file with itself cannot tell whether the RULE that drew it is
	# still right. This calls the drawing rule with the real model.
	var doc := FlowDoc.render(_model())
	assert_str(doc).override_failure_message(
		"the diagram draws a state change where the model declares none").not_contains(
		"world --> world")


func test_the_page_says_it_is_generated() -> void:
	# Because the first thing somebody does with a diagram that is wrong is edit the diagram.
	var doc := FileAccess.get_file_as_string("res://docs/FLOW.md")
	assert_str(doc).contains("Do not edit")
	assert_str(doc).contains("tools/flow_model.json")
