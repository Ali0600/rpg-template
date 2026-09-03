extends GdUnitTestSuite
## The edge scheme, on its own: which shape a cell wants, which piece fills each quarter of it,
## and what the pixels come out as.
##
## Pure and synthetic throughout. The pieces here are flat colours rather than art, because
## every rule below is about WHICH piece reached WHICH quarter - a question a real shoreline
## answers only to the eye, and one a colour answers exactly. The shipped art meets these rules
## in test_tile_bank.gd and the world meets them in test_map_edges.gd.
##
## The bit values below are this suite's OWN literals rather than an alias of the ones under
## test, which is what stops every expectation here from moving with the thing it is checking.
## (A `const` aliasing a project class also crashes gdUnit4's scanner outright.)

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128

const SIZE := 8
const HALF := 4

# Distinct enough that a wrong pick names itself in the failure message.
const BASE_COLOUR := Color8(10, 20, 30)
const CENTRE_COLOUR := Color8(90, 90, 90)


## An opaque tile of one colour.
func _flat(colour: Color) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return img


## A tile whose four quarters are four different colours, so a quarter taken from the WRONG
## quarter of the right piece is a different colour rather than the same one.
func _quartered(first: int) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var q := (1 if y >= HALF else 0) * 2 + (1 if x >= HALF else 0)
			img.set_pixel(x, y, Color8(first + q, 200, 200))
	return img


## Every piece a distinct flat colour, keyed by its own index in RING_KEYS, plus the centre.
func _pieces() -> Dictionary:
	var out := {}
	for i in TerrainEdges.RING_KEYS.size():
		out[TerrainEdges.RING_KEYS[i]] = _flat(Color8(100 + i, 0, 0))
	out[TerrainEdges.CENTRE_KEY] = _flat(CENTRE_COLOUR)
	return out


func _piece_colour(key: String) -> Color:
	return Color8(100 + TerrainEdges.RING_KEYS.find(key), 0, 0)


## The four quarters of a composed tile, read one pixel in from each corner.
func _corners(img: Image) -> Dictionary:
	return {
		"nw": img.get_pixel(1, 1), "ne": img.get_pixel(SIZE - 2, 1),
		"sw": img.get_pixel(1, SIZE - 2), "se": img.get_pixel(SIZE - 2, SIZE - 2),
	}


## Neighbours in OFFSETS order, named rather than counted.
func _around(open_dirs: Array, material := "water", outside := "grass") -> PackedStringArray:
	const NAMES: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
	var out := PackedStringArray()
	for name in NAMES:
		out.append(outside if open_dirs.has(name) else material)
	return out


func _grass_edges(first := 12) -> Array:
	return [{"tile": "water", "over": ["grass"], "first": first, "count": 47}]


## Two blocks for one tile: the village's grass banks and the cave's dirt ones.
func _two_groups() -> Array:
	return [
		{"tile": "water", "over": ["grass"], "first": 12, "count": 47},
		{"tile": "water", "over": ["path"], "first": 59, "count": 47},
	]


func _mask(around: PackedStringArray, over: Array[String]) -> int:
	return TerrainEdges.mask_of(around, over)


# -- the mask ------------------------------------------------------------------------------

func test_the_bits_run_clockwise_from_north_beside_the_offsets() -> void:
	# The bit order and the neighbour order are one fact written twice, and mask_of pairs them by
	# INDEX - so a bit renumbered without its offset reads the tile diagonally opposite.
	var bits: Array[int] = [N, NE, E, SE, S, SW, W, NW]
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
	]
	for i in bits.size():
		assert_int(bits[i]).override_failure_message(
			"bit %d is not 1 << %d" % [bits[i], i]).is_equal(1 << i)
		assert_vector(TerrainEdges.OFFSETS[i]).override_failure_message(
			"neighbour %d is %s, not %s" % [i, TerrainEdges.OFFSETS[i], offsets[i]]) \
			.is_equal(offsets[i])
	assert_int(TerrainEdges.N).is_equal(N)
	assert_int(TerrainEdges.NE).is_equal(NE)
	assert_int(TerrainEdges.E).is_equal(E)
	assert_int(TerrainEdges.SE).is_equal(SE)
	assert_int(TerrainEdges.S).is_equal(S)
	assert_int(TerrainEdges.SW).is_equal(SW)
	assert_int(TerrainEdges.W).is_equal(W)
	assert_int(TerrainEdges.NW).is_equal(NW)

func test_a_diagonal_survives_only_when_both_neighbours_beside_it_are_closed() -> void:
	# A notch is what a diagonal draws, and a notch is unreachable the moment either neighbour
	# beside it opens - that quarter is already an edge or an outer corner. Keeping the bit
	# would split one drawn shape across two atlas columns that must be identical.
	assert_int(TerrainEdges.normalise(NE)).is_equal(NE)
	assert_int(TerrainEdges.normalise(N | NE)).is_equal(N)
	assert_int(TerrainEdges.normalise(E | NE)).is_equal(E)
	assert_int(TerrainEdges.normalise(N | E | NE)).is_equal(N | E)
	# Every diagonal, so a rule written for one and copied three times says so.
	assert_int(TerrainEdges.normalise(S | SE)).is_equal(S)
	assert_int(TerrainEdges.normalise(E | SE)).is_equal(E)
	assert_int(TerrainEdges.normalise(W | SW)).is_equal(W)
	assert_int(TerrainEdges.normalise(S | SW)).is_equal(S)
	assert_int(TerrainEdges.normalise(W | NW)).is_equal(W)
	assert_int(TerrainEdges.normalise(N | NW)).is_equal(N)
	assert_int(TerrainEdges.normalise(255)).is_equal(N | E | S | W)

func test_there_are_forty_seven_shapes_and_every_reading_is_one_of_them() -> void:
	# The list is a literal spec; this is the rule checking it rather than deriving it. 47 is
	# the blob set Tiled's own terrain documentation names, and arriving at that number from
	# the other end is what says the normalisation is the standard one rather than merely
	# self-consistent.
	assert_int(TerrainEdges.MASKS.size()).is_equal(47)
	assert_int(TerrainEdges.MASKS[0]).is_equal(0)
	var seen: Array[int] = []
	for raw in 256:
		var shape := TerrainEdges.normalise(raw)
		assert_bool(TerrainEdges.MASKS.has(shape)).override_failure_message(
			"mask %d normalises to %d, which is not one of the 47" % [raw, shape]).is_true()
		if not seen.has(shape):
			seen.append(shape)
	assert_int(seen.size()).override_failure_message(
		"only %d of the 47 shapes are reachable from a real neighbourhood" % seen.size()) \
		.is_equal(47)

func test_every_shape_in_the_list_is_already_normalised_and_they_ascend() -> void:
	# A shape that normalises to something else is an atlas column nothing ever asks for, and
	# index_of would answer with a different one - drawn, wrong, and never failing.
	var previous := -1
	for mask in TerrainEdges.MASKS:
		assert_int(TerrainEdges.normalise(mask)).override_failure_message(
			"MASKS holds %d, which is not its own normalised form" % mask).is_equal(mask)
		assert_int(mask).override_failure_message(
			"MASKS is not ascending at %d" % mask).is_greater(previous)
		previous = mask

func test_a_shape_is_looked_up_by_its_place_in_the_list() -> void:
	assert_int(TerrainEdges.index_of(0)).is_equal(0)
	assert_int(TerrainEdges.index_of(N)).is_equal(1)
	assert_int(TerrainEdges.index_of(N | NE)).override_failure_message(
		"an unnormalised reading must land on the shape it draws").is_equal(1)
	for mask in TerrainEdges.MASKS:
		assert_int(TerrainEdges.index_of(mask)).is_greater_equal(0)

func test_a_neighbour_counts_as_open_only_when_it_is_the_other_material() -> void:
	var over: Array[String] = ["grass", "grass_alt"]
	assert_int(_mask(_around(["n"]), over)).is_equal(N)
	assert_int(_mask(_around(["n", "e", "ne"]), over)).is_equal(N | E | NE)
	assert_int(_mask(_around([]), over)).is_equal(0)
	assert_int(_mask(_around(["n"], "water", "grass_alt"), over)).is_equal(N)
	assert_int(_mask(_around(["s", "w"]), over)).is_equal(S | W)
	# Off the map arrives as "", which is in nobody's list - so a pond against the border does
	# not grow a shoreline into the wall.
	assert_int(_mask(_around(["n"], "water", ""), over)).is_equal(0)
	assert_int(_mask(_around(["n"], "water", "path"), over)).is_equal(0)


# -- the quarters --------------------------------------------------------------------------

func test_each_quarter_picks_its_piece_from_its_own_two_neighbours() -> void:
	# The five cases, written out per quarter rather than looped, because the table under test
	# is the thing a loop would have to re-derive.
	assert_str(TerrainEdges.quarter_source(N | W, "nw")).is_equal("nw")
	assert_str(TerrainEdges.quarter_source(N, "nw")).is_equal("n")
	assert_str(TerrainEdges.quarter_source(W, "nw")).is_equal("w")
	assert_str(TerrainEdges.quarter_source(NW, "nw")).is_equal("nw_in")
	assert_str(TerrainEdges.quarter_source(0, "nw")).is_equal(TerrainEdges.CENTRE_KEY)

	assert_str(TerrainEdges.quarter_source(N | E, "ne")).is_equal("ne")
	assert_str(TerrainEdges.quarter_source(N, "ne")).is_equal("n")
	assert_str(TerrainEdges.quarter_source(E, "ne")).is_equal("e")
	assert_str(TerrainEdges.quarter_source(NE, "ne")).is_equal("ne_in")
	assert_str(TerrainEdges.quarter_source(0, "ne")).is_equal(TerrainEdges.CENTRE_KEY)

	assert_str(TerrainEdges.quarter_source(S | W, "sw")).is_equal("sw")
	assert_str(TerrainEdges.quarter_source(S, "sw")).is_equal("s")
	assert_str(TerrainEdges.quarter_source(W, "sw")).is_equal("w")
	assert_str(TerrainEdges.quarter_source(SW, "sw")).is_equal("sw_in")
	assert_str(TerrainEdges.quarter_source(0, "sw")).is_equal(TerrainEdges.CENTRE_KEY)

	assert_str(TerrainEdges.quarter_source(S | E, "se")).is_equal("se")
	assert_str(TerrainEdges.quarter_source(S, "se")).is_equal("s")
	assert_str(TerrainEdges.quarter_source(E, "se")).is_equal("e")
	assert_str(TerrainEdges.quarter_source(SE, "se")).is_equal("se_in")
	assert_str(TerrainEdges.quarter_source(0, "se")).is_equal(TerrainEdges.CENTRE_KEY)

func test_a_quarter_ignores_the_neighbours_on_the_other_side_of_the_tile() -> void:
	# The reason a one-tile-tall pond works at all: its cells are open north AND south, and
	# each quarter answers from its own pair rather than from the cell as a whole. Thirteen
	# whole pieces cannot draw this, which is the case that chose quarters.
	var both := N | S
	assert_str(TerrainEdges.quarter_source(both, "nw")).is_equal("n")
	assert_str(TerrainEdges.quarter_source(both, "ne")).is_equal("n")
	assert_str(TerrainEdges.quarter_source(both, "sw")).is_equal("s")
	assert_str(TerrainEdges.quarter_source(both, "se")).is_equal("s")
	assert_str(TerrainEdges.quarter_source(S | W | SW, "ne")).is_equal(TerrainEdges.CENTRE_KEY)

func test_a_diagonal_only_reaches_a_quarter_that_has_no_edge_in_it() -> void:
	assert_str(TerrainEdges.quarter_source(N | NW, "nw")).is_equal("n")
	assert_str(TerrainEdges.quarter_source(W | NW, "nw")).is_equal("w")
	assert_str(TerrainEdges.quarter_source(N | W | NW, "nw")).is_equal("nw")


# -- the pixels ----------------------------------------------------------------------------

func test_a_quarter_is_taken_from_the_same_quarter_of_its_piece() -> void:
	# A piece is a whole tile and only a quarter of it is wanted. Taking the wrong quarter
	# draws a north edge across the middle of a cell, which reads as a smear, not as an edge.
	var pieces := _pieces()
	pieces["n"] = _quartered(10)
	var out := TerrainEdges.compose(N, pieces, _flat(BASE_COLOUR), SIZE)
	var corners := _corners(out)
	assert_int((corners["nw"] as Color).to_rgba32()).override_failure_message(
		"the top-left quarter came from somewhere else in the north piece").is_equal(
		Color8(10, 200, 200).to_rgba32())
	assert_int((corners["ne"] as Color).to_rgba32()).override_failure_message(
		"the top-right quarter is a copy of the top-left one").is_equal(
		Color8(11, 200, 200).to_rgba32())
	assert_int((corners["sw"] as Color).to_rgba32()).is_equal(CENTRE_COLOUR.to_rgba32())
	assert_int((corners["se"] as Color).to_rgba32()).is_equal(CENTRE_COLOUR.to_rgba32())

func test_every_quarter_of_a_four_sided_cell_comes_from_its_own_corner_piece() -> void:
	var out := TerrainEdges.compose(N | E | S | W, _pieces(), _flat(BASE_COLOUR), SIZE)
	var corners := _corners(out)
	for quarter in ["nw", "ne", "sw", "se"]:
		assert_int((corners[quarter] as Color).to_rgba32()).override_failure_message(
			"the %s quarter is not the %s corner piece" % [quarter, quarter]).is_equal(
			_piece_colour(quarter).to_rgba32())

func test_a_cell_with_nothing_open_is_the_plain_tile_it_always_was() -> void:
	# The shape at index 0, and the reason an interior cell needs no special case anywhere: it
	# is composed like every other one and comes out identical to the flat tile that shipped.
	var out := TerrainEdges.compose(0, _pieces(), _flat(BASE_COLOUR), SIZE)
	for y in SIZE:
		for x in SIZE:
			assert_int(out.get_pixel(x, y).to_rgba32()).override_failure_message(
				"an interior cell differs from its plain tile at %d,%d" % [x, y]) \
				.is_equal(CENTRE_COLOUR.to_rgba32())

func test_the_neighbouring_ground_shows_through_the_clear_half_of_a_piece() -> void:
	# What makes this compose rather than replace. A piece is transparent OUTSIDE the material,
	# so a shoreline is grass meeting water - not water meeting a guess about grass.
	var pieces := _pieces()
	var edge := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	edge.fill(Color(0, 0, 0, 0))
	for x in SIZE:
		for y in range(HALF, SIZE):
			edge.set_pixel(x, y, Color8(7, 8, 9))
	pieces["n"] = edge
	var out := TerrainEdges.compose(N, pieces, _flat(BASE_COLOUR), SIZE)
	assert_int(out.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"the clear half of the north piece did not show the ground beneath it") \
		.is_equal(BASE_COLOUR.to_rgba32())
	assert_int(out.get_pixel(1, HALF - 1).to_rgba32()).is_equal(BASE_COLOUR.to_rgba32())

func test_a_half_transparent_pixel_is_blended_in_whole_bytes() -> void:
	# The LPC grass and dirt sheets carry a few hundred partly transparent pixels between them,
	# so this path is real. It is integer arithmetic because the drift gate compares the
	# committed PNG byte for byte on two operating systems, and float rounding is not promised
	# to agree across them.
	var pieces := _pieces()
	var soft := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	soft.fill(Color8(200, 0, 0, 128))
	pieces["n"] = soft
	var out := TerrainEdges.compose(N, pieces, _flat(Color8(0, 100, 0)), SIZE)
	assert_int(out.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"200 over 0 at half alpha came out %s" % out.get_pixel(1, 1)) \
		.is_equal(Color8(100, 50, 0, 255).to_rgba32())

func test_the_blend_rounds_to_nearest_rather_than_towards_nought() -> void:
	# The case above is realistic and ROUNDS THE SAME either way in its red channel, which is
	# exactly the trap: an assertion that cannot tell the two apart proves the arithmetic runs,
	# not that it is right. One byte over black at half alpha is the smallest input where every
	# channel disagrees - 128/255 is 0 truncated and 1 rounded - so it fails on all three.
	var pieces := _pieces()
	var faint := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	faint.fill(Color8(1, 1, 1, 128))
	pieces["n"] = faint
	var out := TerrainEdges.compose(N, pieces, _flat(Color8(0, 0, 0)), SIZE)
	assert_int(out.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"1 over 0 at half alpha came out %s; rounded to nearest it is 1 in every channel"
		% out.get_pixel(1, 1)) \
		.is_equal(Color8(1, 1, 1, 255).to_rgba32())

func test_the_piece_is_drawn_over_the_ground_and_not_under_it() -> void:
	var pieces := _pieces()
	pieces["n"] = _flat(Color8(1, 2, 3))
	var out := TerrainEdges.compose(N, pieces, _flat(Color8(250, 250, 250)), SIZE)
	assert_int(out.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"the ground was painted over the edge piece").is_equal(Color8(1, 2, 3).to_rgba32())

func test_composing_leaves_the_images_it_was_handed_alone() -> void:
	# The same base and the same pieces are handed to all 47 shapes in a row, so composing into
	# either in place would make every shape after the first a composite of its predecessors.
	var pieces := _pieces()
	var base := _flat(BASE_COLOUR)
	TerrainEdges.compose(N | E | S | W, pieces, base, SIZE)
	assert_int(base.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"the base image was composed into in place").is_equal(BASE_COLOUR.to_rgba32())
	assert_int((pieces["n"] as Image).get_pixel(1, 1).to_rgba32()).is_equal(
		_piece_colour("n").to_rgba32())


# -- the lookup ----------------------------------------------------------------------------

func test_a_tile_with_no_edges_draws_the_column_it_always_did() -> void:
	assert_int(TerrainEdges.cell_index([], _around(["n"]), 3)).is_equal(3)

func test_a_cell_draws_its_shape_from_the_block_its_tile_owns() -> void:
	var edges := _grass_edges(12)
	assert_int(TerrainEdges.cell_index(edges, _around([]), 3)).override_failure_message(
		"an interior cell must be the first shape in the block, which is the plain one") \
		.is_equal(12)
	assert_int(TerrainEdges.cell_index(edges, _around(["n"]), 3)) \
		.is_equal(12 + TerrainEdges.index_of(N))
	assert_int(TerrainEdges.cell_index(edges, _around(["n", "s"]), 3)) \
		.is_equal(12 + TerrainEdges.index_of(N | S))

func test_a_cell_bordering_two_materials_takes_the_one_more_of_it_touches() -> void:
	# Water borders grass in the village and dirt in the cave, and nothing stops a map from
	# putting both beside one pool. Orthogonals decide, because they are what reads as the bank.
	var mostly_path := PackedStringArray(
		["path", "water", "path", "water", "path", "water", "grass", "water"])
	assert_int(TerrainEdges.cell_index(_two_groups(), mostly_path, 3)) \
		.is_equal(59 + TerrainEdges.index_of(N | E | S))
	var mostly_grass := PackedStringArray(
		["grass", "water", "grass", "water", "path", "water", "water", "water"])
	assert_int(TerrainEdges.cell_index(_two_groups(), mostly_grass, 3)) \
		.is_equal(12 + TerrainEdges.index_of(N | E))

func test_an_even_split_goes_to_the_group_the_bank_names_first() -> void:
	# Deliberate rather than incidental: the answer is the file's own order, so it is a thing a
	# person chose and can change, not whichever entry a Dictionary happened to hand back.
	var one_each := PackedStringArray(
		["grass", "water", "path", "water", "water", "water", "water", "water"])
	assert_int(TerrainEdges.cell_index(_two_groups(), one_each, 3)) \
		.is_equal(12 + TerrainEdges.index_of(N))

func test_a_tie_on_sides_is_broken_by_the_corners() -> void:
	# Neither is open on a side; path is open on a diagonal, so it is the one with something to
	# draw. Without the corner tie-break this answers 12 and draws a plain tile instead.
	var only_a_corner := PackedStringArray(
		["water", "water", "water", "path", "water", "water", "water", "water"])
	assert_int(TerrainEdges.cell_index(_two_groups(), only_a_corner, 3)) \
		.is_equal(59 + TerrainEdges.index_of(SE))
