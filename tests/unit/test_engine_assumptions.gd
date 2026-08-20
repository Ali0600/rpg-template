extends GdUnitTestSuite
## Pins the engine behaviours this template's determinism and pixel exactness rely on.
##
## Every assertion here is a documented Godot behaviour the sprite generator is built
## around. If a future engine version changes one, this suite fails with a clear name
## instead of surfacing three suites away as a golden-hash mismatch nobody can explain.

func test_seeded_rng_is_reproducible_and_seed_sensitive() -> void:
	# The whole "same seed, same sprite" promise rests on this.
	var a: Array[float] = _roll(7)
	var b: Array[float] = _roll(7)
	var c: Array[float] = _roll(8)
	assert_array(a).is_equal(b)
	assert_array(a).is_not_equal(c)

func _roll(seed_value: int) -> Array[float]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[float] = []
	for i in 5:
		out.append(rng.randf_range(0.0, 1.0))
	return out

func test_image_create_empty_is_transparent_rgba8() -> void:
	# Layers are stamped onto a blank image; if "blank" were opaque black, every sprite
	# would ship with a black box around it and the palette gate would fail confusingly.
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	assert_int(img.get_width()).is_equal(4)
	assert_int(img.get_format()).is_equal(Image.FORMAT_RGBA8)
	assert_int(img.get_pixel(0, 0).to_rgba32()).is_equal(0)

func test_color_equality_is_exact_through_rgba32() -> void:
	# Palette membership is decided by integer comparison. Colors are four floats, and two
	# visually identical colours built by different routes are not always `==`.
	var a := Color("#1a1c2c")
	var b := Color(26.0 / 255.0, 28.0 / 255.0, 44.0 / 255.0, 1.0)
	assert_int(a.to_rgba32()).is_equal(b.to_rgba32())

func test_set_pixel_preserves_exact_color_bytes() -> void:
	# The compositor draws with set_pixel precisely because it stores what it is given.
	# blend_rect would mix floats and produce off-palette values that no gate could name.
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	var c := Color("#a7f070")
	img.set_pixel(1, 1, c)
	assert_int(img.get_pixel(1, 1).to_rgba32()).is_equal(c.to_rgba32())
	assert_int(img.get_pixel(0, 0).to_rgba32()).is_equal(0)

func test_color8_survives_a_round_trip_through_an_image_but_floats_may_not() -> void:
	# Storing a colour in an 8-bit image TRUNCATES the channel, while Color.to_rgba32()
	# ROUNDS it. A colour computed in floats can therefore report one value and come back
	# out of the image as another, one unit darker - which is why every generated colour is
	# built from whole bytes with Color8.
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	for v in 256:
		var c := Color8(v, v, v, 255)
		img.set_pixel(0, 0, c)
		assert_int(img.get_pixel(0, 0).to_rgba32()).is_equal(c.to_rgba32())

	# The failure this rule exists to prevent, pinned so it cannot come back unnoticed.
	var floaty := Color("#008840").darkened(0.35)
	img.set_pixel(0, 0, floaty)
	assert_int(img.get_pixel(0, 0).to_rgba32()).is_not_equal(floaty.to_rgba32())

func test_flip_x_mutates_in_place_and_is_its_own_inverse() -> void:
	# The left-facing row is the right-facing row flipped. flip_x has NO return value: a
	# `var left = right.flip_x()` would bind null and silently mirror the original.
	var img := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	var c := Color("#41a6f6")
	img.set_pixel(0, 0, c)
	img.flip_x()
	assert_int(img.get_pixel(1, 0).to_rgba32()).is_equal(c.to_rgba32())
	assert_int(img.get_pixel(0, 0).to_rgba32()).is_equal(0)
	img.flip_x()
	assert_int(img.get_pixel(0, 0).to_rgba32()).is_equal(c.to_rgba32())

func test_image_data_is_stable_for_hashing() -> void:
	# Golden hashes are taken over get_data() (raw RGBA bytes), not over encoded PNG bytes,
	# which carry encoder settings and can differ between platforms for the same picture.
	var a := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
	var b := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
	a.set_pixel(2, 2, Color("#ffcd75"))
	b.set_pixel(2, 2, Color("#ffcd75"))
	assert_str(Hashing.image_digest(a)).is_equal(Hashing.image_digest(b))
	b.set_pixel(0, 0, Color("#ffcd75"))
	assert_str(Hashing.image_digest(a)).is_not_equal(Hashing.image_digest(b))

func test_the_digest_is_a_real_sha256() -> void:
	# Pinned against a known vector so a future refactor cannot quietly swap in a weaker or
	# differently-encoded hash and keep every comparison "passing".
	assert_str(Hashing.sha256_bytes("abc".to_utf8_buffer())) \
		.is_equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

func test_json_numbers_arrive_as_floats() -> void:
	# Every int read out of a map or sheet file is cast, because this is what JSON gives.
	var parsed: Variant = JSON.parse_string('{"cell": 16}')
	var d := parsed as Dictionary
	assert_bool(is_same(d["cell"], 16)).is_false()
	assert_int(int(d["cell"])).is_equal(16)

func test_stringname_and_string_are_the_same_dictionary_key() -> void:
	# EventBus payloads are keyed by StringName; tests read them with String literals.
	var d: Dictionary = {&"kind": "interacted"}
	assert_bool(d.has("kind")).is_true()
	assert_bool(d.has(&"kind")).is_true()

func test_typed_array_needs_assign_not_direct_cast() -> void:
	# filter()/map() return untyped arrays; assigning one to a typed field is a runtime
	# error. Every such site in scripts/ uses .assign() or an explicit loop.
	var untyped: Array = [1, 2, 3]
	var typed: Array[int] = []
	typed.assign(untyped)
	assert_array(typed).is_equal([1, 2, 3])

func test_move_and_slide_picks_its_own_delta_rather_than_one_you_pass() -> void:
	# The assumption the whole grid-step design rests on, so it is pinned rather than trusted.
	#
	# move_and_slide() takes no delta. It chooses one itself - the PHYSICS delta when called
	# during a physics frame, the IDLE delta otherwise - so the distance one call covers is
	# not something a caller can predict or control. That is why a grid step ends by noticing
	# it has arrived rather than by computing which frame it will arrive on: a step that
	# predicted the landing frame from a delta it passed in would overshoot in exactly the
	# harness tests/integration/test_world_movement.gd uses, which drives apply() by hand from
	# a coroutine and is therefore NOT in a physics frame.
	var body := CharacterBody2D.new()
	add_child(body)
	auto_free(body)
	body.velocity = Vector2(100.0, 0.0)

	# Called from a test coroutine: not a physics frame.
	assert_bool(Engine.is_in_physics_frame()).override_failure_message(
		"this suite is running inside a physics frame, so the case below proves nothing").is_false()
	var before := body.global_position.x
	body.move_and_slide()
	var moved := body.global_position.x - before

	# It moved SOMETHING - the call is not inert outside a physics frame, which is what makes
	# the hand-driven integration harness work at all.
	assert_float(moved).is_greater(0.0)
	# And it is the idle delta, not the physics one. If these ever coincide the assertion
	# below is vacuous, so the guard above states the frame kind explicitly.
	var idle_step := 100.0 * get_process_delta_time()
	assert_float(moved).is_equal_approx(idle_step, 0.001)


func test_reading_a_missing_file_as_bytes_is_empty_and_quiet() -> void:
	# ImageFile.read_png has no file_exists guard in front of its read, because this makes one
	# unreachable: a missing path comes back as an empty array rather than as an error or a
	# crash. The reader turns that into null, which is what the art-drift gate reports as
	# "(unreadable)". If a future engine made this noisy or fatal, the gate would start
	# crashing on a missing sprite instead of naming it, and this is where that shows up.
	var bytes := FileAccess.get_file_as_bytes("res://assets/generated/does_not_exist.png")
	assert_int(bytes.size()).override_failure_message(
		"a missing file no longer reads as empty bytes").is_equal(0)
	assert_int(FileAccess.get_open_error()).is_equal(ERR_FILE_NOT_FOUND)
