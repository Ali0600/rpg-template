extends GdUnitTestSuite
## The one place a style's world scale becomes a window size and a layer scale.
##
## The claim under test is arithmetic and one engine behaviour: that setting content_scale_size
## actually makes the viewport report that size. That second half is the reason this suite
## builds a node and asks the tree, rather than reading back the property it just set - a
## setter's readback can only tell you what you wrote.

const DUSK := "res://data/styles/dusk16.tres"
const LPC := "res://data/styles/lpc32.tres"


func after_test() -> void:
	# An autoload outlives a suite and so does the window. A suite that left it at 640x360
	# would silently re-scale every layout audit that ran after it.
	UiScale.apply(_window(), _style(DUSK))


func _style(path: String) -> SpriteStyle:
	return load(path) as SpriteStyle


func _window() -> Window:
	return get_tree().root


func test_the_design_size_is_the_project_s_own_viewport() -> void:
	# The two must not drift: every screen lays out against DESIGN_SIZE, and the project
	# setting is what the game is actually shown in at scale 1. Were they different, every
	# layout gate would be measuring a window nobody is looking at.
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))) \
		.is_equal(UiScale.DESIGN_SIZE.x)
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))) \
		.is_equal(UiScale.DESIGN_SIZE.y)


func test_a_style_states_how_big_the_world_is() -> void:
	assert_vector(Vector2(UiScale.window_size(_style(DUSK)))).is_equal(Vector2(320.0, 180.0))
	assert_vector(Vector2(UiScale.window_size(_style(LPC)))).is_equal(Vector2(640.0, 360.0))
	assert_vector(UiScale.layer_scale(_style(DUSK))).is_equal(Vector2.ONE)
	assert_vector(UiScale.layer_scale(_style(LPC))).is_equal(Vector2(2.0, 2.0))


func test_no_style_at_all_is_the_template_s_own_size() -> void:
	# The dialog box and the controls hint are built before a map has said which style is
	# running. A null there must be the default world rather than a crash or a zero-size window.
	assert_int(UiScale.scale_of(null)).is_equal(1)
	assert_vector(Vector2(UiScale.window_size(null))).is_equal(Vector2(320.0, 180.0))


func test_binding_a_style_resizes_the_world_the_viewport_reports() -> void:
	# The OUTCOME, not the readback: what matters is that a node in the tree measures 640x360,
	# because that is the number the camera clamps against and the world is drawn into.
	var probe := auto_free(Node2D.new()) as Node2D
	add_child(probe)
	UiScale.apply(_window(), _style(LPC))
	assert_vector(probe.get_viewport_rect().size).override_failure_message(
		"the window took the style's size and the viewport did not follow"
		).is_equal(Vector2(640.0, 360.0))
	UiScale.apply(_window(), _style(DUSK))
	assert_vector(probe.get_viewport_rect().size).is_equal(Vector2(320.0, 180.0))


func test_a_mounted_layer_is_drawn_at_the_world_s_scale() -> void:
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var layer := CanvasLayer.new()
	UiScale.mount(layer, parent, _style(LPC))
	assert_object(layer.get_parent()).is_same(parent)
	assert_vector(layer.scale).is_equal(Vector2(2.0, 2.0))


func test_a_layer_built_before_a_style_was_known_is_brought_up_afterwards() -> void:
	# mount() cannot help a layer created while no style was bound. rescale() is the pair, and
	# without it the dialog box would draw at a quarter of the window it is shown in.
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var early := CanvasLayer.new()
	UiScale.mount(early, parent, null)
	assert_vector(early.scale).is_equal(Vector2.ONE)
	UiScale.rescale(parent, _style(LPC))
	assert_vector(early.scale).override_failure_message(
		"a layer already in the tree kept the scale of a style that is no longer bound"
		).is_equal(Vector2(2.0, 2.0))
