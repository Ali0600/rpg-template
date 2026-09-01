extends GdUnitTestSuite
## The consistency gates: the rules that make a generated cast look like one game.
##
## These run over EVERY shipped style, character, direction and walk frame, because the way
## a generated cast goes wrong is never "all of it" - it is one frame, one direction, one
## character whose feet sit a pixel high or whose sleeve picked up a colour from nowhere.
## Looking at a contact sheet catches the loud failures; only this catches the quiet ones.
##
## Every gate here has a matching row in tools/mutants.tsv, so each one has been proven to
## fail on the defect it exists to catch.

func test_there_is_something_to_check() -> void:
	# A gate that iterates an empty list passes perfectly and proves nothing. Every other
	# test in this file loops over these, so their emptiness is checked once, here.
	var styles := ArtFixtures.rig_style_ids()
	assert_int(styles.size()).is_greater_equal(2)
	for style_id in styles:
		assert_array(ArtFixtures.characters_of(style_id)).is_not_empty()

func test_every_style_is_gated_by_exactly_one_suite() -> void:
	# An imported style cannot be drawn through the rig, so it leaves these gates for
	# test_imported_art.gd. Membership is asserted as a SET, both ways: the two lists together
	# must equal every style on disk, so a third kind of source cannot opt out of both - and no
	# style may be in both, answering to two contradictory rules.
	var rig := ArtFixtures.rig_style_ids()
	var imported := ArtFixtures.imported_style_ids()
	var together: Array[StringName] = []
	together.append_array(rig)
	together.append_array(imported)
	# By text, never Array[StringName].sort(): that ordered by pointer and once printed the
	# four ids back as dusk16, gbnes16, lpc32, nesgb16 - names that do not exist.
	ArtFixtures.by_text(together)
	assert_str(str(together)).is_equal(str(ArtFixtures.style_ids()))
	for style_id in rig:
		assert_bool(imported.has(style_id)).override_failure_message(
			"%s is in both lists" % style_id).is_false()
	# The template ships one imported style; an empty list here means the split stopped working.
	assert_array(imported).is_not_empty()

func test_every_pixel_comes_from_the_style_palette() -> void:
	# The core promise. A colour outside the palette means something entered the pipeline
	# from outside the style - a hardcoded literal, a blend, an interpolation - and once one
	# has, "change the style to change the art" is no longer true.
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		var rig := ArtFixtures.rig_for(style)
		var allowed := style.palette_rgba32()
		for spec in ArtFixtures.characters_of(style_id):
			for img in ArtFixtures.all_frames(rig, style, spec):
				var offenders := _off_palette(img, allowed)
				assert_array(offenders) \
					.override_failure_message("%s/%s paints colours that are not in its palette: %s"
						% [style_id, spec.id, offenders]) \
					.is_empty()

func test_tiles_use_the_same_palette_as_the_characters() -> void:
	# Terrain drawn from a different palette than the cast is the single most obvious way a
	# game made of mixed assets betrays itself.
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		var built := TileGen.build(style, ArtFixtures.tile_bank_for(style))
		var offenders := _off_palette(built["image"], style.palette_rgba32())
		assert_array(offenders).override_failure_message(
			"%s tiles use colours outside the style palette: %s" % [style_id, offenders]).is_empty()

func test_the_whole_cast_stands_on_one_ground_line() -> void:
	# Characters whose lowest pixel differs by even one row look like they are standing at
	# different depths, and the effect is unmistakable in motion and invisible in a still.
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		var rig := ArtFixtures.rig_for(style)
		var rows: Array[int] = []
		for spec in ArtFixtures.characters_of(style_id):
			for img in ArtFixtures.all_frames(rig, style, spec):
				var row := SpriteCompositor.ground_row(img)
				assert_int(row).override_failure_message(
					"%s/%s produced a blank frame" % [style_id, spec.id]).is_greater(0)
				if not rows.has(row):
					rows.append(row)
		assert_int(rows.size()).override_failure_message(
			"%s characters stand on %d different rows: %s" % [style_id, rows.size(), rows]).is_equal(1)
		# And that row is at the bottom of the cell, not floating somewhere in the middle.
		assert_int(rows[0]).is_equal(style.cell_size.y - 1)

func test_a_walk_frame_never_lifts_both_feet() -> void:
	# The bob is what makes a four-frame walk read as walking, and the reason parts are
	# marked "bob": false is that a bobbed foot leaves the ground. This asserts the split
	# actually held: every frame keeps a foot planted on the ground row.
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		var rig := ArtFixtures.rig_for(style)
		for spec in ArtFixtures.characters_of(style_id):
			var frames := ArtFixtures.all_frames(rig, style, spec)
			for i in frames.size():
				assert_int(SpriteCompositor.ground_row(frames[i])).override_failure_message(
					"%s/%s frame %d floats" % [style_id, spec.id, i]).is_equal(style.cell_size.y - 1)

func test_facing_left_is_facing_right_mirrored() -> void:
	# One authored side, two directions. If this drifts, a character walking left is drawn
	# with the detail on the wrong side and nothing reports it.
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		if not style.mirror_left_from_right:
			continue
		var rig := ArtFixtures.rig_for(style)
		for spec in ArtFixtures.characters_of(style_id):
			var resolved := spec.resolve(rig, style)
			for frame in style.walk_frames:
				var left := SpriteCompositor.compose(rig, style, resolved, Dir.D.LEFT, frame)
				var right := SpriteCompositor.compose(rig, style, resolved, Dir.D.RIGHT, frame)
				right.flip_x()
				assert_str(Hashing.image_digest(left)).override_failure_message(
					"%s/%s frame %d: left is not right mirrored" % [style_id, spec.id, frame]) \
					.is_equal(Hashing.image_digest(right))

func test_the_outline_wraps_the_silhouette() -> void:
	# Outlines are generated, not drawn, so the rule to check is structural: for a style with
	# an outline, no coloured pixel may touch empty space without an outline pixel between.
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		if style.outline_mode == SpriteStyle.Outline.NONE:
			continue
		var rig := ArtFixtures.rig_for(style)
		var outline_colors := style.outline_colors_rgba32()
		assert_array(outline_colors).is_not_empty()
		for spec in ArtFixtures.characters_of(style_id):
			var img: Image = ArtFixtures.all_frames(rig, style, spec)[0]
			var bare := _bare_edges(img, outline_colors)
			assert_int(bare).override_failure_message(
				"%s/%s has %d body pixels touching empty space with no outline"
					% [style_id, spec.id, bare]).is_equal(0)

func test_a_frame_is_not_accidentally_blank_or_full() -> void:
	# Two silent disasters a colour check cannot see: a part list that resolved to nothing,
	# and a stamp that filled the cell edge to edge.
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		var rig := ArtFixtures.rig_for(style)
		var area := style.cell_size.x * style.cell_size.y
		for spec in ArtFixtures.characters_of(style_id):
			for img in ArtFixtures.all_frames(rig, style, spec):
				var opaque := _opaque_count(img)
				assert_int(opaque).is_greater(area / 6)
				assert_int(opaque).is_less(area * 9 / 10)

func _off_palette(img: Image, allowed: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var v := c.to_rgba32()
			if allowed.has(v):
				continue
			var hex := "#" + c.to_html(false)
			if not out.has(hex):
				out.append(hex)
	return out

func _opaque_count(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				n += 1
	return n

## Counts body pixels (not outline) that sit against transparency inside the cell. Edges of
## the cell itself do not count: a sprite is allowed to reach the border.
func _bare_edges(img: Image, outline_colors: Array[int]) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var bare := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a == 0.0 or outline_colors.has(c.to_rgba32()):
				continue
			for step: Vector2i in SpriteCompositor.NEIGHBOURS:
				var nx := x + step.x
				var ny := y + step.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if img.get_pixel(nx, ny).a == 0.0:
					bare += 1
					break
	return bare
