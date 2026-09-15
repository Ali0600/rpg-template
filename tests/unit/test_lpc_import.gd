extends GdUnitTestSuite
## LpcImport: a Universal LPC export becomes this template's sheet, or is refused by name.
##
## Every expectation here is a LITERAL - the LPC row numbers, the row order, the cycle -
## painted into a synthetic sheet and read back, never taken from the constants under test.
## A fixture painted through LpcImport.WALK_ROW would move with a mutant that shifts
## WALK_ROW, and pass.

## Where the universal sheet keeps each walk direction, as the generator's source states it.
const WALK_ROWS := {8: Dir.D.UP, 9: Dir.D.LEFT, 10: Dir.D.DOWN, 11: Dir.D.RIGHT}
## The order this template's sheets are read in, top to bottom.
const CANONICAL: Array = [Dir.D.DOWN, Dir.D.LEFT, Dir.D.RIGHT, Dir.D.UP]
const FRAME := 64
const SHEET_WIDE := 13 * FRAME
const MARK_Y := 50

func _color_of(d: int) -> Color:
	# One unmistakable colour per direction. Literals are fine here: tests are outside the linter.
	match d:
		Dir.D.UP:
			return Color8(255, 0, 0)
		Dir.D.LEFT:
			return Color8(0, 255, 0)
		Dir.D.RIGHT:
			return Color8(0, 0, 255)
		_:
			return Color8(255, 255, 0)

func _style(licenses: Array = ["CC0", "CC-BY", "OGA-BY", "CC-BY-SA"]) -> SpriteStyle:
	var s := SpriteStyle.new()
	s.id = &"lab"
	s.sheets_from = SpriteStyle.SHEETS_FROM_LPC
	s.cell_size = Vector2i(FRAME, FRAME)
	s.tile_size = 32
	s.rig_id = &""
	s.licenses = JsonFile.to_string_array(licenses)
	s.ramps = {"x": ["#000000", "#777777", "#ffffff"]}
	s.portrait_size = 24
	for role in SpriteStyle.UI_ROLES:
		s.ui_colors[role] = "#ffffff"
	return s

func _recipe(licenses: Array = ["OGA-BY 3.0", "CC-BY-SA 3.0"], file := "body/bodies/male/walk.png") -> Dictionary:
	return {"version": 2, "bodyType": "male", "selections": {}, "layers": [], "credits": [
		{"file": file, "authors": ["wulax", "bluecarrot16"], "licenses": licenses,
			"urls": ["https://opengameart.org/content/lpc-character-bases"]}]}

## An 832-wide sheet `rows` LPC rows tall. Every cell of every walk row gets one pixel in its
## direction's colour at (32, MARK_Y) and one at (column, ground) - so a converted cell can say
## which LPC row and which column it came from, and where its feet were.
func _sheet(rows := 12, ground := 63) -> Image:
	var img := Image.create_empty(SHEET_WIDE, rows * FRAME, false, Image.FORMAT_RGBA8)
	for lpc_row: int in WALK_ROWS.keys():
		if lpc_row >= rows:
			continue
		var color := _color_of(WALK_ROWS[lpc_row])
		for col in 13:
			img.set_pixel(col * FRAME + 32, lpc_row * FRAME + MARK_Y, color)
			img.set_pixel(col * FRAME + col, lpc_row * FRAME + ground, color)
	return img

func test_the_walk_block_lands_in_canonical_rows() -> void:
	var built := LpcImport.build(_sheet(), _recipe(), _style(), "hero")
	var img: Image = built["image"]
	var meta: SheetMeta = built["meta"]
	for r in CANONICAL.size():
		var dir: int = CANONICAL[r]
		assert_int(meta.directions[r]).is_equal(dir)
		assert_str(img.get_pixel(32, r * FRAME + MARK_Y).to_html(false)).override_failure_message(
			"canonical row %d should carry the %s frames" % [r, Dir.name_of(dir)]) \
			.is_equal(_color_of(dir).to_html(false))

func test_every_column_is_kept_and_the_cycle_skips_the_standing_pose() -> void:
	var built := LpcImport.build(_sheet(), _recipe(), _style(), "hero")
	var img: Image = built["image"]
	var meta: SheetMeta = built["meta"]
	assert_int(img.get_width()).is_equal(9 * FRAME)
	assert_int(img.get_height()).is_equal(4 * FRAME)
	for r in 4:
		for col in 9:
			assert_bool(img.get_pixel(col * FRAME + col, r * FRAME + 63).a > 0.0) \
				.override_failure_message("row %d column %d lost its marker" % [r, col]).is_true()
	assert_int(meta.columns).is_equal(9)
	assert_str(str(meta.frames_of("walk"))).is_equal("[1, 2, 3, 4, 5, 6, 7, 8]")
	assert_str(str(meta.frames_of("idle"))).is_equal("[0]")

func test_the_anchor_is_measured_from_the_feet_not_the_frame() -> void:
	var low: SheetMeta = LpcImport.build(_sheet(12, 63), _recipe(), _style(), "hero")["meta"]
	assert_int(low.anchor.y).is_equal(63)
	var high: SheetMeta = LpcImport.build(_sheet(12, 58), _recipe(), _style(), "hero")["meta"]
	assert_int(high.anchor.y).is_equal(58)
	assert_int(high.anchor.x).is_equal(32)

func test_the_output_describes_itself_and_plays_through_the_factory() -> void:
	var built := LpcImport.build(_sheet(), _recipe(), _style(), "hero")
	var img: Image = built["image"]
	var meta: SheetMeta = built["meta"]
	assert_array(meta.problems(img.get_size())).is_empty()
	assert_str(meta.source).is_equal("lpc")
	assert_str(meta.character).is_equal("hero")
	assert_str(meta.style).is_equal("lab")
	var frames := SpriteFramesFactory.build(ImageTexture.create_from_image(img), meta)
	assert_object(frames).is_not_null()
	assert_bool(frames.has_animation(&"walk_left")).is_true()
	assert_int(frames.get_frame_count(&"walk_left")).is_equal(8)
	assert_int(frames.get_frame_count(&"idle_up")).is_equal(1)

func test_a_sheet_too_short_for_the_walk_rows_is_refused_by_row_number() -> void:
	assert_str(str(LpcImport.problems(_sheet(11), _recipe(), _style()))).contains("rows 8-11")
	assert_array(LpcImport.problems(_sheet(12), _recipe(), _style())).is_empty()

func test_a_sheet_narrower_than_the_cycle_is_refused() -> void:
	var img := Image.create_empty(8 * FRAME, 12 * FRAME, false, Image.FORMAT_RGBA8)
	assert_str(str(LpcImport.problems(img, _recipe(), _style()))).contains("px wide")

func test_blank_walk_rows_are_refused() -> void:
	var img := Image.create_empty(SHEET_WIDE, 12 * FRAME, false, Image.FORMAT_RGBA8)
	var problems := LpcImport.problems(img, _recipe(), _style())
	assert_str(str(problems)).contains("blank")
	assert_str(str(problems)).contains("Walk enabled")

func test_a_layer_outside_the_style_licences_is_refused_by_name() -> void:
	var problems := LpcImport.problems(_sheet(), _recipe(["GPL 3.0"], "hair/afro/adult/walk.png"), _style())
	assert_str(str(problems)).contains("hair/afro/adult/walk.png")
	assert_str(str(problems)).contains("GPL")
	# One accepted family is enough: the artist offered a choice, and the style takes it.
	assert_array(LpcImport.problems(_sheet(), _recipe(["GPL 3.0", "CC-BY-SA 3.0"]), _style())).is_empty()

func test_share_alike_is_refused_by_a_credit_only_style() -> void:
	var strict := _style(["CC0", "CC-BY", "OGA-BY"])
	assert_str(str(LpcImport.problems(_sheet(), _recipe(["CC-BY-SA 3.0"]), strict))).contains("CC-BY-SA")
	assert_array(LpcImport.problems(_sheet(), _recipe(["CC-BY 3.0+"]), strict)).is_empty()

func test_a_credit_without_a_licence_and_an_export_without_credits_are_refused() -> void:
	assert_str(str(LpcImport.problems(_sheet(), _recipe([]), _style()))).contains("names no licence")
	assert_str(str(LpcImport.problems(_sheet(), {"version": 2}, _style()))).contains("no credits")

func test_licence_families_drop_the_version_and_never_prefix_match() -> void:
	assert_str(LpcImport.license_family("CC-BY 3.0+")).is_equal("CC-BY")
	assert_str(LpcImport.license_family("CC-BY-SA 4.0")).is_equal("CC-BY-SA")
	assert_str(LpcImport.license_family("OGA-BY 3.0")).is_equal("OGA-BY")
	assert_str(LpcImport.license_family("CC0")).is_equal("CC0")
	assert_str(LpcImport.license_family("")).is_equal("")

func test_credits_are_merged_in_one_order_whatever_order_they_arrived_in() -> void:
	var a := {"credits": [
		{"file": "b.png", "authors": ["z", "y"], "licenses": ["CC0"], "urls": []},
		{"file": "a.png", "authors": ["m"], "licenses": ["OGA-BY 3.0", "CC-BY-SA 3.0"], "urls": ["u2", "u1"]}]}
	var b := {"credits": [a["credits"][1], a["credits"][0]]}
	assert_str(JSON.stringify(LpcImport.merged_credits(a))) \
		.is_equal(JSON.stringify(LpcImport.merged_credits(b)))
	assert_str(str(LpcImport.merged_credits(a)[0]["file"])).is_equal("a.png")
	# The cast-wide summary is the flat lists a credits screen says out loud.
	var summary := LpcImport.credits_summary(_style(), [a, b])
	assert_str(str(summary["authors"])).is_equal('["m", "y", "z"]')
	assert_str(str(summary["licenses"])).is_equal('["CC-BY-SA", "CC0", "OGA-BY"]')
	assert_int((summary["files"] as Array).size()).is_equal(2)
	# Across characters too: a later export must not append its files after an earlier one's.
	var later := {"credits": [{"file": "a.png", "authors": ["m"], "licenses": ["CC0"], "urls": []}]}
	var earlier := {"credits": [{"file": "z.png", "authors": ["m"], "licenses": ["CC0"], "urls": []}]}
	var cast := LpcImport.credits_summary(_style(), [earlier, later])
	assert_str(str((cast["files"] as Array)[0]["file"])).is_equal("a.png")

func test_the_notice_names_share_alike_only_when_a_layer_is() -> void:
	var text := LpcImport.license_notice(_style(), [_recipe(["CC-BY-SA 3.0"])])
	assert_str(text).contains("CC-BY-SA 4.0")
	var plain := LpcImport.license_notice(_style(), [_recipe(["OGA-BY 3.0"])])
	assert_bool(plain.contains("CC-BY-SA 4.0")).is_false()
	assert_str(plain).contains("credit the artists")

func test_a_style_that_does_not_import_or_has_the_wrong_cell_is_refused() -> void:
	var rig_style := _style()
	rig_style.sheets_from = SpriteStyle.SHEETS_FROM_RIG
	rig_style.rig_id = &"gb16"
	assert_str(str(LpcImport.problems(_sheet(), _recipe(), rig_style))).contains("does not import")
	var small := _style()
	small.cell_size = Vector2i(16, 24)
	assert_str(str(LpcImport.problems(_sheet(), _recipe(), small))).contains("64x64")


## The fixture with the DOWN block's standing frame drawn from `top` downward, which is where a
## face is measured from. LPC's down block is row 10 and the standing pose is its column 0.
func _sheet_with_head_at(top: int) -> Image:
	var img := _sheet()
	for col in 13:
		img.set_pixel(col * FRAME + 32, 10 * FRAME + top, Color(1, 1, 1, 1))
	return img


func test_a_face_is_measured_off_the_frame_this_character_faces_you_on() -> void:
	# It starts at the top of the drawn pixels, and it straddles the column the character stands
	# in - anything else is a square with somebody's ear in the middle of it.
	var style := _style()
	var built := LpcImport.build(_sheet_with_head_at(20), _recipe(), style, "hero")
	var meta: SheetMeta = built["meta"]
	assert_int(meta.portrait.position.y).override_failure_message(
		"the face starts at y=%d where this character's drawn pixels start at 20"
		% meta.portrait.position.y).is_equal(20)
	assert_int(meta.portrait.size.x).is_equal(style.portrait_size)
	assert_int(meta.portrait.size.y).is_equal(style.portrait_size)
	assert_int(meta.portrait.position.x).is_less_equal(meta.anchor.x)
	assert_int(meta.portrait.end.x).is_greater(meta.anchor.x)
	assert_array(meta.problems(Vector2i(FRAME * 9, FRAME * 4))).is_empty()

func test_a_face_follows_the_head_it_was_measured_from() -> void:
	# The half that makes the one above an assertion rather than a coincidence. A fixed offset
	# would pass that test on every character and be wrong for the one wearing a hat - so the
	# head moves and the face has to come with it. The shipped cast measures from 10 to 25
	# depending on what is on their heads and how tall the body is, which is the spread this
	# would be wrong across.
	var style := _style()
	var low: SheetMeta = LpcImport.build(_sheet_with_head_at(20), _recipe(), style, "x")["meta"]
	var high: SheetMeta = LpcImport.build(_sheet_with_head_at(8), _recipe(), style, "x")["meta"]
	assert_int(high.portrait.position.y).override_failure_message(
		"a character whose head is drawn higher gets the same face rectangle as one who is not"
	).is_equal(8)
	assert_int(low.portrait.position.y).is_equal(20)

func test_a_character_drawn_low_in_its_cell_still_gets_a_face_inside_it() -> void:
	# The degenerate end, and a real one: a small creature drawn near its own feet has no
	# `portrait_size` of cell left below the top of its head. The square SLIDES UP to the lowest
	# place it still fits rather than running off the bottom, because a rect outside the cell is
	# an atlas region that samples whatever is drawn under it - the next row of the sheet.
	var style := _style()
	var meta: SheetMeta = LpcImport.build(_sheet(), _recipe(), style, "x")["meta"]
	assert_int(meta.portrait.position.y).override_failure_message(
		"a face measured at y=%d in a %dpx cell holding a %dpx square"
		% [meta.portrait.position.y, FRAME, style.portrait_size]).is_equal(
		FRAME - style.portrait_size)
	assert_bool(Rect2i(Vector2i.ZERO, Vector2i(FRAME, FRAME)).encloses(meta.portrait)) \
		.override_failure_message("the face runs outside the cell it was cut from").is_true()
	assert_array(meta.problems(Vector2i(FRAME * 9, FRAME * 4))).is_empty()


# -- the slash ---------------------------------------------------------------------------------

## Where the universal sheet keeps each SLASH direction, as the generator's source states it.
const SLASH_ROWS := {12: Dir.D.UP, 13: Dir.D.LEFT, 14: Dir.D.DOWN, 15: Dir.D.RIGHT}

## A full-height sheet with the walk markers at `ground` and a slash block: every slash cell marked
## in its direction's colour at (32, MARK_Y) and at (column, `low`), so a slash reaching lower than
## the walk's feet can be staged. `drawn` names the slash rows that get anything at all.
func _sheet_with_slash(ground := 58, low := 63, drawn: Array = [12, 13, 14, 15]) -> Image:
	var img := _sheet(54, ground)
	for lpc_row: int in SLASH_ROWS.keys():
		if not drawn.has(lpc_row):
			continue
		var color := _color_of(SLASH_ROWS[lpc_row])
		for col in 6:
			img.set_pixel(col * FRAME + 32, lpc_row * FRAME + MARK_Y, color)
			img.set_pixel(col * FRAME + col, lpc_row * FRAME + low, color)
	return img

func test_a_drawn_slash_becomes_columns_9_to_14_in_canonical_rows_and_plays_once() -> void:
	var style := _style()
	style.slash_fps = 11
	var built := LpcImport.build(_sheet_with_slash(), _recipe(), style, "hero")
	var img: Image = built["image"]
	var meta: SheetMeta = built["meta"]
	assert_int(img.get_width()).is_equal(15 * FRAME)
	assert_int(meta.columns).is_equal(15)
	assert_str(str(meta.frames_of("slash"))).is_equal("[9, 10, 11, 12, 13, 14]")
	var clip: Dictionary = meta.animations["slash"]
	assert_bool(bool(clip["loop"])).is_false()
	assert_int(int(clip["fps"])).override_failure_message("the slash does not play at the style's slash speed").is_equal(11)
	for r in CANONICAL.size():
		var dir: int = CANONICAL[r]
		for col in 6:
			assert_str(img.get_pixel((9 + col) * FRAME + 32, r * FRAME + MARK_Y).to_html(false)).override_failure_message(
				"slash column %d of canonical row %d should carry the %s frames" % [col, r, Dir.name_of(dir)]) \
				.is_equal(_color_of(dir).to_html(false))
	assert_array(meta.problems(img.get_size())).is_empty()

func test_a_slash_reaching_below_the_feet_does_not_move_the_ground_line() -> void:
	# The whole cast is placed by its anchor, and the arena sizes its floor window from it: a lunge
	# or a blade held low must not move where this character stands.
	var meta: SheetMeta = LpcImport.build(_sheet_with_slash(58, 63), _recipe(), _style(), "hero")["meta"]
	assert_int(meta.anchor.y).override_failure_message("the slash was measured as the ground").is_equal(58)

func test_a_walk_only_sheet_imports_exactly_as_it_always_did() -> void:
	var built := LpcImport.build(_sheet(54), _recipe(), _style(), "hero")
	var meta: SheetMeta = built["meta"]
	assert_int((built["image"] as Image).get_width()).is_equal(9 * FRAME)
	assert_int(meta.columns).is_equal(9)
	assert_bool(meta.animations.has("slash")).is_false()
	assert_bool(LpcImport.has_slash(_sheet(54))).is_false()
	assert_bool(LpcImport.has_slash(_sheet(12))).override_failure_message(
		"a sheet too short to reach the slash rows claims to draw one").is_false()
	assert_bool(LpcImport.has_slash(_sheet_with_slash())).is_true()

func test_a_slash_drawn_facing_only_some_ways_is_refused_by_row() -> void:
	var problems := LpcImport.problems(_sheet_with_slash(58, 63, [12, 13, 14]), _recipe(), _style())
	assert_str(str(problems)).contains("slash row 15")
	assert_array(LpcImport.problems(_sheet_with_slash(), _recipe(), _style())).is_empty()

func test_the_slash_plays_through_the_factory_once() -> void:
	var built := LpcImport.build(_sheet_with_slash(), _recipe(), _style(), "hero")
	var frames := SpriteFramesFactory.build(ImageTexture.create_from_image(built["image"]), built["meta"])
	assert_int(frames.get_frame_count(&"slash_left")).is_equal(6)
	assert_bool(frames.get_animation_loop(&"slash_left")).is_false()


# -- a swing drawn below the sheet -------------------------------------------------------------

const BLOCK_Y := 54 * FRAME
const SWING := 128

## A composed sheet whose swing is drawn on 128px frames: the walk at `ground`, rows 12-15 holding the
## unarmed body the generator draws as well, and under the universal sheet a block in which every cell
## of LPC block row R carries its direction's colour at (64, 82) - except the up row's last frame, left
## blank - plus the two marks that set the crop: (20, 40) in the first cell and a half-clear (110, 100)
## in the last.
func _sheet_with_block(ground := 58) -> Image:
	var img := Image.create_empty(SHEET_WIDE, BLOCK_Y + 4 * SWING, false, Image.FORMAT_RGBA8)
	img.blit_rect(_sheet_with_slash(ground, ground), Rect2i(0, 0, SHEET_WIDE, BLOCK_Y), Vector2i.ZERO)
	for lpc_row: int in SLASH_ROWS.keys():
		var r := lpc_row - 12
		for col in 6:
			if r == 0 and col == 5:
				continue
			img.set_pixel(col * SWING + 64, BLOCK_Y + r * SWING + 82, _color_of(SLASH_ROWS[lpc_row]))
	img.set_pixel(20, BLOCK_Y + 40, Color8(9, 9, 9))
	img.set_pixel(5 * SWING + 110, BLOCK_Y + 3 * SWING + 100, Color8(9, 9, 9, 128))
	return img

## The export of that sheet, with the record LpcCompose writes, `changes` laid over the record.
func _block_recipe(changes := {}) -> Dictionary:
	var record := {"name": "slash_128", "clip": "slash", "frameSize": SWING, "x": 0, "y": BLOCK_Y,
		"columns": 6, "rows": 4}
	record.merge(changes, true)
	var recipe := _recipe()
	recipe["customAnimations"] = [record]
	return recipe

func _drawn_in(img: Image, area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if img.get_pixel(x, y).a > 0.0:
				count += 1
	return count

func test_a_swing_drawn_below_the_sheet_is_cut_onto_a_grid_of_its_own_cropped_to_what_it_draws() -> void:
	var built := LpcImport.build(_sheet_with_block(), _block_recipe(), _style(), "hero")
	var img: Image = built["image"]
	var meta: SheetMeta = built["meta"]
	# The crop is everything drawn: (20, 40) to (110, 100) of a 128px cell, so 91 by 61. The feet, 32
	# across and 58 down a 64px frame, are 32 further in each way once the frame is centred - (64, 90) in
	# the cell - and (44, 50) in the crop.
	assert_vector(Vector2(img.get_size())).is_equal(Vector2(576, 500))
	assert_int(meta.columns).override_failure_message("the unarmed swing in rows 12-15 was imported too").is_equal(9)
	assert_str(str(meta.frames_of("slash"))).is_equal("[0, 1, 2, 3, 4, 5]")
	assert_vector(Vector2(meta.cell_of("slash"))).is_equal(Vector2(91, 61))
	assert_vector(Vector2(meta.origin_of("slash"))).is_equal(Vector2(0, 256))
	assert_vector(Vector2(meta.anchor_of("slash"))).is_equal(Vector2(44, 50))
	assert_int(meta.anchor.y).override_failure_message("the swing was measured as the ground").is_equal(58)
	for r in CANONICAL.size():
		var dir: int = CANONICAL[r]
		for col in 6:
			if dir == Dir.D.UP and col == 5:
				continue
			assert_str(img.get_pixel(col * 91 + 44, 256 + r * 61 + 42).to_html(false)).override_failure_message(
				"swing frame %d of canonical row %d should carry the %s frames" % [col, r, Dir.name_of(dir)]) \
				.is_equal(_color_of(dir).to_html(false))
	assert_array(meta.problems(img.get_size())).is_empty()

func test_a_crop_loses_nothing_the_swing_draws() -> void:
	var sheet := _sheet_with_block()
	var out: Image = LpcImport.build(sheet, _block_recipe(), _style(), "hero")["image"]
	var before := _drawn_in(sheet, Rect2i(0, BLOCK_Y, 6 * SWING, 4 * SWING))
	var after := _drawn_in(out, Rect2i(0, 256, 6 * 91, 4 * 61))
	assert_int(before).is_equal(25)	# 23 marks, and the two that set the crop
	assert_int(after).override_failure_message("%d of %d drawn pixels survived the crop" % [after, before]).is_equal(before)

func test_a_sheet_past_the_universal_size_that_does_not_say_where_its_swing_is_is_refused() -> void:
	# The browser's own download: its export records nothing about the block it drew below the sheet.
	assert_str("\n".join(LpcImport.problems(_sheet_with_block(), _recipe(), _style()))).contains(
		"does not say what is drawn there")
	assert_array(LpcImport.problems(_sheet_with_block(), _block_recipe(), _style())).is_empty()

func test_a_swing_record_the_sheet_cannot_be_cut_by_is_refused_by_name() -> void:
	var sheet := _sheet_with_block()
	assert_str("\n".join(LpcImport.problems(sheet, _block_recipe({"clip": "thrust"}), _style()))).contains(
		"this importer reads a slash")
	assert_str("\n".join(LpcImport.problems(sheet, _block_recipe({"columns": 8}), _style()))).contains(
		"6 frames on 4 rows")
	assert_str("\n".join(LpcImport.problems(sheet, _block_recipe({"y": 3600}), _style()))).contains(
		"outside the")

func test_a_swing_blank_facing_one_way_is_refused_by_row() -> void:
	var sheet := _sheet_with_block()
	sheet.fill_rect(Rect2i(0, BLOCK_Y + 2 * SWING, 6 * SWING, SWING), Color(0, 0, 0, 0))
	assert_str("\n".join(LpcImport.problems(sheet, _block_recipe(), _style()))).contains("swing row 2 (down)")
