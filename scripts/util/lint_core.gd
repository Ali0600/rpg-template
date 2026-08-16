class_name LintCore
extends RefCounted
## The project's source rules, as a pure function over text so they can be tested.
##
## The rules exist because each one, broken, produces working-looking code that quietly
## destroys a promise the template makes:
##
##   unseeded_rng   - a sprite that is different on every run cannot be golden-hashed, and
##                    "regenerate and diff" stops being a usable check
##   direction_text - a raw "left" typed somewhere is a direction that scripts/util/dir.gd
##                    does not know about, so a rename fixes three call sites and misses one
##   color_literal  - a colour outside the style data is an art decision welded into code,
##                    which is exactly what swapping the art style is supposed to avoid
##
## The scanner runs as a RefCounted over strings rather than over files so the suite can
## feed it known-bad fixtures. tools/lint_rules.gd is the thin wrapper that walks the repo.
##
## Two structural rules, both learned the hard way: text is normalised ONCE before the rule
## loop (an exemption evaluated inside a loop that also breaks out of it silently ends the
## scan), and every hit is reported rather than the first.

const RULE_RNG := "unseeded_rng"
const RULE_DIRECTION := "direction_text"
const RULE_COLOR := "color_literal"

## Global-generator calls. They are only a hit when NOT preceded by a dot: `rng.randf_range`
## is a method on a seeded RandomNumberGenerator, `randf_range` on its own is the process
## generator nobody seeded.
const GLOBAL_RNG_CALLS: Array[String] = [
	"randi(", "randf(", "randi_range(", "randf_range(", "randfn(",
	"randomize(", "rand_from_seed(",
]

## These have no seeded form at all - Array.pick_random and Array.shuffle always draw from
## the global generator, so any occurrence is a hit. SeededRng.pick/shuffled replace them.
const GLOBAL_RNG_METHODS: Array[String] = [".pick_random(", ".shuffle("]

const DIRECTION_WORDS: Array[String] = [
	"down", "left", "right", "up", "north", "south", "east", "west",
]

## Files that must contain the very thing a rule bans.
const RULE_EXEMPT: Dictionary = {
	RULE_RNG: ["res://scripts/util/lint_core.gd", "res://tools/lint_rules.gd"],
	RULE_DIRECTION: [
		"res://scripts/util/dir.gd",
		"res://scripts/util/lint_core.gd",
		"res://tools/lint_rules.gd",
	],
	RULE_COLOR: ["res://scripts/util/lint_core.gd", "res://tools/lint_rules.gd"],
}

## Colour is allowed to be written down where art is generated and where art data is
## typed; everywhere else a colour belongs in a SpriteStyle resource.
const COLOR_ALLOWED_PREFIXES: Array[String] = [
	"res://scripts/spritegen/",
	"res://scripts/data/",
]


## Every rule this scanner knows. tools/lint_rules.gd prints it, and
## tests/unit/test_lint_core.gd asserts each one has a fixture - a rule with no known-bad
## input is a rule nobody has proven fires.
static func rule_names() -> Array[String]:
	return [RULE_RNG, RULE_DIRECTION, RULE_COLOR]


## Returns one string per violation: "<path>:<line>: <rule>: <detail>". Empty means clean.
static func scan_text(path: String, text: String) -> Array[String]:
	var hits: Array[String] = []
	var check_rng := not _is_exempt(path, RULE_RNG)
	var check_direction := not _is_exempt(path, RULE_DIRECTION)
	var check_color := not _is_exempt(path, RULE_COLOR) and not _color_allowed(path)

	var line_no := 0
	for raw_line in text.split("\n"):
		line_no += 1
		var parsed := _split_line(raw_line)
		var code: String = parsed["code"]
		var literals: Array = parsed["literals"]

		if check_rng:
			for token in GLOBAL_RNG_CALLS:
				var at := code.find(token)
				while at != -1:
					if not _is_member_call(code, at) and not _is_identifier_tail(code, at):
						hits.append(_hit(path, line_no, RULE_RNG,
							"%s draws from the unseeded global generator; use SeededRng" % token.trim_suffix("(")))
					at = code.find(token, at + 1)
			for token in GLOBAL_RNG_METHODS:
				if code.contains(token):
					hits.append(_hit(path, line_no, RULE_RNG,
						"%s always uses the global generator; use SeededRng.pick/shuffled" % token.trim_suffix("(")))

		if check_direction:
			for literal: String in literals:
				if DIRECTION_WORDS.has(literal.strip_edges().to_lower()):
					hits.append(_hit(path, line_no, RULE_DIRECTION,
						"\"%s\" is a direction typed as text; use Dir.NAMES / Dir.from_name" % literal))

		if check_color:
			for token in ["Color(", "Color8(", "Color."]:
				if code.contains(token):
					hits.append(_hit(path, line_no, RULE_COLOR,
						"%s outside spritegen/data; colours belong in a SpriteStyle" % token.trim_suffix("(")))
			for literal: String in literals:
				if _looks_like_hex_color(literal):
					hits.append(_hit(path, line_no, RULE_COLOR,
						"\"%s\" is a hex colour; colours belong in a SpriteStyle" % literal))

	return hits


static func _hit(path: String, line_no: int, rule: String, detail: String) -> String:
	return "%s:%d: %s: %s" % [path, line_no, rule, detail]


static func _is_exempt(path: String, rule: String) -> bool:
	var exempt: Array = RULE_EXEMPT.get(rule, [])
	return exempt.has(path)


static func _color_allowed(path: String) -> bool:
	for prefix in COLOR_ALLOWED_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false


## Splits a source line into the code outside string literals and the contents of the
## literals themselves. Doing both in one pass is what lets `#` inside a string stop
## truncating the line, and what gives the direction rule real literals to test instead of
## a substring search that would fire on the word "left" inside a comment.
static func _split_line(line: String) -> Dictionary:
	var code := ""
	var literals: Array[String] = []
	var current := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote.is_empty():
			if ch == "#":
				break
			if ch == "\"" or ch == "'":
				quote = ch
				current = ""
			else:
				code += ch
		else:
			if ch == "\\":
				# Skip the escaped character so \" does not close the literal.
				current += ch
				i += 1
				if i < line.length():
					current += line[i]
			elif ch == quote:
				literals.append(current)
				quote = ""
			else:
				current += ch
		i += 1
	if not quote.is_empty():
		# An unterminated literal (a multi-line string) - keep what we saw so a direction
		# word on the opening line is still caught.
		literals.append(current)
	return {"code": code, "literals": literals}


## True when the token is a method call on something: the character before it is a dot.
static func _is_member_call(code: String, at: int) -> bool:
	return at > 0 and code[at - 1] == "."


## True when the token is the tail of a longer identifier, e.g. `next_randi(` or the
## definition `func randf_range(`. Only a standalone call is a violation.
static func _is_identifier_tail(code: String, at: int) -> bool:
	if at == 0:
		return false
	var prev := code[at - 1]
	return prev == "_" or prev.is_valid_identifier() or (prev >= "0" and prev <= "9")


static func _looks_like_hex_color(literal: String) -> bool:
	var s := literal.strip_edges()
	if not s.begins_with("#"):
		return false
	var body := s.substr(1)
	if not (body.length() == 3 or body.length() == 6 or body.length() == 8):
		return false
	return body.is_valid_hex_number(false)
