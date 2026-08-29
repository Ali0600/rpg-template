class_name FlowDoc
extends RefCounted
## Draws the flow model as Markdown. Pure: no nodes, no files, no clock.
##
## Split from tools/gen_flow_doc.gd for the reason every pure half here is split from its
## runner: the drift gate can only compare the committed page against what the generator makes
## NOW, which says nothing about whether the drawing rule is right. This is the half a test can
## call with a model of its own.

## The whole page, or an empty string for a model with nothing in it - which the caller
## reports rather than writing out, the generators' own rule.
static func render(model: Dictionary) -> String:
	var states: Dictionary = model.get("states", {})
	var edges: Array = model.get("edges", [])
	if states.is_empty() or edges.is_empty():
		return ""

	var out := "# Flow\n\n"
	out += "**Generated from `tools/flow_model.json` by `tools/gen_flow_doc.gd`. Do not edit.**\n"
	out += "The model is the source and a gate keeps it true: every edge below is driven\n"
	out += "through the real game by `tests/integration/test_flow_model.gd`, which compares what\n"
	out += "the router actually announced against what is written down.\n\n"

	out += "```mermaid\nstateDiagram-v2\n"
	for key: Variant in states:
		out += "\t%s : %s\n" % [str(key), str((states[key] as Dictionary).get("about", key))]
	for entry: Variant in edges:
		var edge: Dictionary = entry
		var from := str(edge.get("from", ""))
		var to := str(edge.get("to", ""))
		if from == to:
			continue
		out += "\t%s --> %s : %s\n" % [from, to, str(edge.get("action", ""))]
	out += "```\n\n"

	out += "## What each state must be true of\n\n"
	out += "| State | While in it |\n| --- | --- |\n"
	for key: Variant in states:
		var vertex: Dictionary = states[key]
		var names: Array[String] = []
		for raw: Variant in vertex.get("invariants", []) as Array:
			names.append("`%s`" % str(raw))
		out += "| **%s** | %s |\n" % [str(key), ", ".join(names)]

	out += "\n## Every declared move\n\n"
	out += "| Action | From | To | Announces |\n| --- | --- | --- | --- |\n"
	for entry: Variant in edges:
		var edge: Dictionary = entry
		var hops: Array[String] = []
		for raw: Variant in edge.get("trace", []) as Array:
			var pair := raw as Array
			hops.append("%s → %s" % [str(pair[0]), str(pair[1])])
		var announces := ", ".join(hops)
		if announces.is_empty():
			announces = "*nothing*"
		out += "| `%s` | %s | %s | %s |\n" % [str(edge.get("action", "")),
			str(edge.get("from", "")), str(edge.get("to", "")), announces]

	out += "\n## Notes the model carries\n\n"
	for entry: Variant in edges:
		var edge: Dictionary = entry
		var note := str(edge.get("note", ""))
		if not note.is_empty():
			out += "- **`%s`** — %s\n" % [str(edge.get("action", "")), note]
	return out
