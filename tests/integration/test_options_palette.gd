extends GdUnitTestSuite
## The player's chosen window colours, measured where they land rather than where they were set.
##
## The setter's own readback proves nothing here: Settings holds a STRING, and the whole question
## is whether that string becomes pixels. So every assertion below reads a colour off something
## that draws - the dialog box's StyleBox, the label's theme override, the engine's clear colour -
## which is one layer downstream of the write and is what a player actually sees.
##
## It boots the fixture yard for test_world_scale's reason: the shipped maps are content, and a
## suite that entered one would be measuring the demo rather than the mechanism.

const GAME := "res://data/games/quest.tres"
const FIXTURE_MAPS := "res://tests/fixtures/maps"
const SCRATCH := "user://test_options_palette.json"
const MINT := &"mint"

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()
	# The redirect FIRST, and asserted: cycling a palette writes the file, and without this a
	# suite run - or the mutation harness, running it with the code deliberately broken - would
	# edit the real preferences of whoever is at the keyboard.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.use_path(SCRATCH)
	assert_str(Settings.path()).override_failure_message(
		"the redirect is not in effect - this suite would write the real settings file"
	).is_equal(SCRATCH)


func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	MapData.root = MapData.MAP_DIR
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.use_path(Settings.path_for(GameSelect.args()))
	GameState.reset()
	Router.reset()


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _manifest() -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.start_map = &"lpc32_yard"
	manifest.start_spawn = &"start"
	manifest.party = []
	manifest.hooks = null
	return manifest


func _instantiate() -> Node2D:
	MapData.root = MapData.MAP_DIR
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world


## The fixture root is moved AFTER instantiating, never before - _ready boots the shipped game and
## would hunt for its start map in the fixture directory, leaving a half-built map behind.
func _boot() -> Node2D:
	_instantiate()
	MapData.root = FIXTURE_MAPS
	assert_bool(_world.start_game(_manifest())).is_true()
	await _steps(1)
	return _world


func _palette(id: StringName) -> UiPalette:
	var found := Registry.get_resource(&"UiPalette", id) as UiPalette
	assert_object(found).override_failure_message(
		"no palette '%s' is registered, so this suite measured nothing" % id).is_not_null()
	return found


## The colour the dialog box's window is actually FILLED with - off the StyleBox it draws itself
## from, not off the style it was handed.
func _panel_color(world: Node2D) -> Color:
	var box: DialogBox = world.dialog_box()
	assert_object(box).is_not_null()
	var panel := box._panel as Panel
	var style_box := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_object(style_box).override_failure_message(
		"the dialog window has no StyleBoxFlat, so its fill could not be read").is_not_null()
	return style_box.bg_color


func test_a_world_with_no_palette_chosen_draws_the_styles_own_chrome() -> void:
	# The control, and the compatibility claim: every game shipped on this template before there
	# was a choice looked like this, and must still.
	var world := await _boot()
	var style := load("res://data/styles/lpc32.tres") as SpriteStyle
	assert_that(_panel_color(world)).override_failure_message(
		"with no palette chosen the window is not the style's own colour").is_equal(
			style.ui_color("panel"))


func test_choosing_a_palette_recolours_the_window_the_player_is_looking_at() -> void:
	var world := await _boot()
	var mint := _palette(MINT)
	Settings.set_palette(MINT)
	world._rebind_style()
	await _steps(1)
	assert_that(_panel_color(world)).override_failure_message(
		"the dialog window kept its old fill after the palette changed").is_equal(
			Color(str(mint.colors["panel"])))
	# The letterbox too, which is the other half of what _bind_style binds: a recoloured window on
	# the old surround is a screen that looks half-repainted.
	assert_that(RenderingServer.get_default_clear_color()).override_failure_message(
		"the area outside the map kept the style's colour after the palette changed").is_equal(
			Color(str(mint.colors["panel"])))


func test_going_back_to_no_palette_restores_the_styles_own() -> void:
	# The half a one-way test cannot see. A recolour that could not be undone would leave a player
	# who tried one stuck with it, and the cycle offers the way back precisely so they are not.
	var world := await _boot()
	var style := load("res://data/styles/lpc32.tres") as SpriteStyle
	Settings.set_palette(MINT)
	world._rebind_style()
	await _steps(1)
	Settings.set_palette(Settings.NO_PALETTE)
	world._rebind_style()
	await _steps(1)
	assert_that(_panel_color(world)).override_failure_message(
		"the style's own chrome did not come back").is_equal(style.ui_color("panel"))


func test_a_palette_is_laid_over_the_style_rather_than_over_the_last_palette() -> void:
	# What _style_source is for. Composing from the LAST composed style would work once and then
	# never get back - and it would look right in every single-change test, which is why this one
	# changes twice and checks a role the second palette also defines.
	var world := await _boot()
	Settings.set_palette(MINT)
	world._rebind_style()
	await _steps(1)
	Settings.set_palette(&"charcoal")
	world._rebind_style()
	await _steps(1)
	var charcoal := _palette(&"charcoal")
	assert_that(_panel_color(world)).override_failure_message(
		"a second palette did not fully replace the first").is_equal(
			Color(str(charcoal.colors["panel"])))


func test_a_palette_the_build_does_not_ship_draws_the_styles_own() -> void:
	# A settings file naming a palette that has been deleted. It falls back rather than erroring,
	# and it must fall back to something DRAWABLE: the failure this prevents is a white screen.
	var world := await _boot()
	var style := load("res://data/styles/lpc32.tres") as SpriteStyle
	Settings.set_palette(&"no_such_palette")
	world._rebind_style()
	await _steps(1)
	assert_that(_panel_color(world)).override_failure_message(
		"an unknown palette id did not fall back to the style's own chrome").is_equal(
			style.ui_color("panel"))


func test_the_title_is_drawn_in_the_palette_too() -> void:
	# Found by PHOTOGRAPHING the title under all three palettes and getting four byte-identical
	# images. open_title called _bind_style, which composed the colours correctly, and then handed
	# the screen the style that came IN rather than the composed one - every other screen in the
	# file already read _style, and this line was the odd one out.
	#
	# It matters more than it looks: the title is where a player who has just recoloured their
	# windows comes back to, so the one surface that would still be wrong is the one they check.
	# It is also M40's lesson exactly - a bind that does three things and only does two.
	# Chosen BEFORE the world boots, because _ready opens the title itself - which is also the
	# real sequence: a player's settings are read at startup and the title is the first thing
	# drawn with them.
	Settings.set_palette(MINT)
	var world := _instantiate()
	await _steps(1)
	var title: TitleScreen = world.title_screen()
	assert_object(title).is_not_null()
	var panel := title._frame.panel as Panel
	var box := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(box.bg_color).override_failure_message(
		"the title screen is drawn in the style's own colours, not the chosen palette's"
		).is_equal(Color(str(_palette(MINT).colors["panel"])))


func test_recolouring_does_not_bring_back_a_hint_the_player_has_dismissed() -> void:
	# The reason the hint is restyled where the dialog box is rebuilt. It teaches which keys move
	# you and goes away once you have moved; a fresh one would put that back on the screen of
	# somebody an hour into the game, and every colour assertion above would still pass.
	var world := await _boot()
	var hint: ControlsHint = world._hint
	assert_object(hint).is_not_null()
	hint.dismiss()
	Settings.set_palette(MINT)
	world._rebind_style()
	await _steps(1)
	assert_object(world._hint).override_failure_message(
		"the hint was replaced by the recolour, so a dismissed one came back").is_same(hint)
	assert_bool(world._hint._dismissed).override_failure_message(
		"the hint is no longer dismissed after a recolour").is_true()
