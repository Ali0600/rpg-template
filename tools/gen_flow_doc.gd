extends SceneTree
## Draws tools/flow_model.json as docs/FLOW.md.
##
##     Godot --headless --path . -s tools/gen_flow_doc.gd            # write
##     Godot --headless --path . -s tools/gen_flow_doc.gd --verify   # compare, write nothing
##
## The sibling of gen_sprites.gd and gen_sounds.gd, down to the shape of this file: --verify is
## the drift gate check.sh runs, and it fails if what is committed differs from what the model
## says now. The model is the source; this is output, and output that no longer matches its
## source is the quiet failure - somebody adds a state, the diagram still shows eight, and the
## next reader trusts the picture.
##
## The Mermaid block is the reason this exists at all: the model is written for a machine to
## check, and a person looking at the same file should not have to hold seventeen edges in
## their head to see the shape.

const MODEL := "res://tools/flow_model.json"
const OUT := "res://docs/FLOW.md"

var _verify := false


func _init() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--verify":
			_verify = true

	var file := JsonFile.read(MODEL)
	if not file.ok:
		printerr("gen_flow_doc: " + file.error)
		quit(1)
		return
	var text := FlowDoc.render(file.data)
	if text.is_empty():
		# A generator that renders nothing must not report success - the rule lint_rules.gd
		# and every other generator here follow.
		printerr("gen_flow_doc: the model produced no document")
		quit(1)
		return

	if not _verify:
		var handle := FileAccess.open(OUT, FileAccess.WRITE)
		if handle == null:
			printerr("gen_flow_doc: could not write %s" % OUT)
			quit(1)
			return
		handle.store_string(text)
		handle.close()
		print("gen_flow_doc: wrote %s" % OUT)
		quit(0)
		return

	if not FileAccess.file_exists(OUT):
		printerr("gen_flow_doc: OUT OF DATE  %s (missing)" % OUT)
		printerr("gen_flow_doc: re-run without --verify and commit the result.")
		quit(1)
		return
	if FileAccess.get_file_as_string(OUT) != text:
		printerr("gen_flow_doc: OUT OF DATE  %s (differs from the model)" % OUT)
		printerr("gen_flow_doc: re-run without --verify and commit the result.")
		quit(1)
		return
	print("gen_flow_doc: %s matches the model" % OUT)
	quit(0)
