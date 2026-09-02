extends SceneTree
## Renders a scene once and writes a PNG, so a change can be LOOKED at.
##
##     Godot --path . --rendering-driver opengl3 --resolution 320x180 \
##         -s tools/screenshot.gd -- res://scenes/sprite_lab/sprite_lab.tscn /tmp/shot.png
##
## Tests prove the rules hold; they cannot tell you the result looks wrong. Every visual
## change in this project gets one of these read before it is called done - and read twice:
## once for "did the thing I built render", and once for "what is overlapping, stale or
## off-screen that I was not looking for".
##
## Not headless: --headless uses a dummy renderer that draws nothing, so the PNG would be
## blank. It needs a real driver and therefore does not run in CI.
##
## --resolution states the WINDOW, and a style that wants a bigger world resizes it from inside
## (UiScale.apply, when the style is bound) - so a shot of a 32px game comes back 640x360 whatever
## is passed here. Ask for the design size and let the scene say if it wants more.

const DEFAULT_SCENE := "res://scenes/sprite_lab/sprite_lab.tscn"
const DEFAULT_OUT := "user://screenshot.png"
## Frames to run before capturing, so scenes that build their children in _ready and settle
## over a frame or two are photographed after they have settled, not during.
const WARMUP_FRAMES := 6


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else DEFAULT_SCENE
	var out_path: String = args[1] if args.size() > 1 else DEFAULT_OUT

	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("screenshot: could not load %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())

	for i in WARMUP_FRAMES:
		await process_frame
	# The viewport texture is only valid after the frame has actually been drawn; reading it
	# a moment earlier yields the previous frame, or nothing at all.
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		printerr("screenshot: could not write %s (error %d)" % [out_path, err])
		quit(1)
		return
	print("screenshot: %s %s" % [out_path, img.get_size()])
	quit(0)
