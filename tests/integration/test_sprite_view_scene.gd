extends GdUnitTestSuite
## The contract, exercised through a real scene tree rather than in isolation.
##
## Unit tests prove SpriteFramesFactory builds the right animations. They cannot prove an
## AnimatedSprite2D actually plays them, that the feet land on the node's origin, or that a
## walk cycle advances - and those are the three ways a correct sheet still produces a
## broken-looking character.
##
## Everything here is driven by simulated frames, never by waiting: a headless run has no
## display pacing it, so a wall-clock wait is slow when it passes and flaky when it fails.

const LAB_SCENE := "res://scenes/sprite_lab/sprite_lab.tscn"

func test_a_view_plays_the_animation_for_the_direction_it_is_given() -> void:
	var view: SpriteView = auto_free(SceneHelpers.view_for(&"hero"))
	add_child(view)
	await await_idle_frame()
	for dir: int in Dir.ALL:
		view.set_pose(&"walk", dir)
		assert_str(String(view.current_animation())).is_equal(String(Dir.anim_name(&"walk", dir)))
		view.set_pose(&"idle", dir)
		assert_str(String(view.current_animation())).is_equal(String(Dir.anim_name(&"idle", dir)))

func test_the_walk_cycle_actually_advances() -> void:
	# The failure this catches: re-issuing play() every frame restarts the animation, so the
	# character is permanently on frame 0 and appears to moonwalk. Nothing errors.
	var view: SpriteView = auto_free(SceneHelpers.view_for(&"hero"))
	add_child(view)
	await await_idle_frame()
	view.set_pose(&"walk", Dir.D.DOWN)
	var seen: Array[int] = []
	for i in 12:
		if not seen.has(view.current_frame()):
			seen.append(view.current_frame())
		view.advance(0.1)
	assert_int(seen.size()).override_failure_message(
		"the walk cycle never left frame %d" % view.current_frame()).is_greater(1)

func test_an_unchanged_pose_is_not_re_issued() -> void:
	# set_pose is called every frame by the movement code, so it must be cheap AND safe to
	# repeat. This asserts the MECHANISM - how many times an animation was started - because
	# the guard changes how the work is done, not what is drawn: AnimatedSprite2D happens not
	# to restart when handed the animation it is already playing, so no assertion on the
	# rendered frame can tell a working guard from a missing one.
	var view: SpriteView = auto_free(SceneHelpers.view_for(&"hero"))
	add_child(view)
	await await_idle_frame()
	view.set_pose(&"walk", Dir.D.DOWN)
	var plays_after_first := view.play_count()
	for i in 10:
		view.set_pose(&"walk", Dir.D.DOWN)
	assert_int(view.play_count()).override_failure_message(
		"ten identical set_pose calls started %d animations" % (view.play_count() - plays_after_first + 1)) \
		.is_equal(plays_after_first)
	# And a real change still gets through.
	view.set_pose(&"walk", Dir.D.UP)
	assert_int(view.play_count()).is_equal(plays_after_first + 1)

func test_the_node_origin_sits_at_the_characters_feet() -> void:
	# Why it matters: collision shapes, y-sorting and tile coordinates all refer to this
	# point. If the origin were the sprite's centre, a taller character would need every one
	# of them re-tuned.
	var view: SpriteView = auto_free(SceneHelpers.view_for(&"hero"))
	add_child(view)
	await await_idle_frame()
	var sprite := SceneHelpers.find_by_class(view, "AnimatedSprite2D") as AnimatedSprite2D
	assert_object(sprite).is_not_null()
	assert_bool(sprite.centered).is_false()
	var source := FileSpriteSource.create(&"gb16")
	var meta: SheetMeta = source.sheet(&"hero")["meta"]
	assert_vector(sprite.offset).is_equal(-Vector2(meta.anchor))

func test_an_unusable_sheet_leaves_the_view_showing_what_it_had() -> void:
	# Fail visibly-unchanged rather than invisibly-blank: an empty node reads as a movement
	# or spawn bug and sends the search to the wrong place entirely.
	var view: SpriteView = auto_free(SceneHelpers.view_for(&"hero"))
	add_child(view)
	await await_idle_frame()
	view.set_pose(&"walk", Dir.D.LEFT)
	var before := view.current_animation()
	var broken := SheetMeta.new()
	broken.columns = 99
	assert_bool(view.apply_sheet(null, broken)).is_false()
	assert_str(String(view.current_animation())).is_equal(String(before))

func test_sprite_lab_boots_and_shows_every_direction() -> void:
	# The first scene_runner test in the project: it settles the headless recipe (load a
	# scene, simulate frames, read the tree) before the world scenes add physics on top.
	var runner := scene_runner(LAB_SCENE)
	await runner.simulate_frames(3)
	var views := SceneHelpers.find_all_by_class(runner.scene(), "SpriteView")
	assert_int(views.size()).is_equal(Dir.ALL.size())
	var animations: Array[String] = []
	for node in views:
		var view := node as SpriteView
		animations.append(String(view.current_animation()))
	# One per direction, all distinct: a lab that showed the same pose four times would look
	# fine in a screenshot and be useless for judging the art.
	assert_int(animations.size()).is_equal(4)
	for dir: int in Dir.ALL:
		assert_bool(animations.has(String(Dir.anim_name(&"walk", dir)))).override_failure_message(
			"Sprite Lab is missing the %s view; it shows %s" % [Dir.name_of(dir), animations]).is_true()

func test_sprite_lab_switches_character_on_input() -> void:
	# Proves the lab is actually interactive through the real input map, which is also the
	# first proof that simulate_action_pressed reaches a scene in this project.
	var runner := scene_runner(LAB_SCENE)
	await runner.simulate_frames(3)
	var title := SceneHelpers.find_by_class(runner.scene(), "Label") as Label
	assert_object(title).is_not_null()
	var before := title.text
	runner.simulate_action_pressed("move_right")
	await runner.await_input_processed()
	await runner.simulate_frames(2)
	assert_str(title.text).override_failure_message(
		"pressing move_right did not change the previewed character (%s)" % title.text) \
		.is_not_equal(before)

func test_one_press_toggles_the_pose_exactly_once() -> void:
	# A toggle is the one handler shape that makes double-delivery invisible: acted on twice,
	# it returns to where it started and the key looks dead. gdUnit's runner delivers each
	# simulated event twice on purpose (it parses the event AND calls _unhandled_input
	# directly), which makes it a good proxy for any real forwarding path - so this asserts
	# the exact state after one press, not merely that something changed.
	var runner := scene_runner(LAB_SCENE)
	await runner.simulate_frames(3)
	var view := SceneHelpers.find_by_class(runner.scene(), "SpriteView") as SpriteView
	assert_str(String(view.clip())).is_equal("walk")

	runner.simulate_action_pressed("interact")
	await runner.await_input_processed()
	await runner.simulate_frames(2)
	assert_str(String(view.clip())).override_failure_message(
		"one press did not toggle exactly once").is_equal("idle")

	runner.simulate_action_pressed("interact")
	await runner.await_input_processed()
	await runner.simulate_frames(2)
	assert_str(String(view.clip())).is_equal("walk")
