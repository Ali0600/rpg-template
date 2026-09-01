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
