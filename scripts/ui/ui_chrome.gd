class_name UiChrome
extends RefCounted
## What every screen in this game is drawn WITH: one font, at one size, in one place.
##
## The interface used to be nine screens each declaring its own 7, 8 and 9, drawn in whatever
## font the engine happened to fall back to. That is most of why it read as cheap: a vector face
## asked for 7 pixels is a smear, and three sizes of smear is not a hierarchy. A pixel font is
## drawn FOR one size and has no other - so the sizes live here, there are two of them, and the
## difference between a title and a row is a band and capitals rather than a point size.
##
## Pure and static, and it names no autoload - the UiScale rule, and for its reason: a file
## whose TEXT contains an autoload's name drops itself, and every suite that depends on it, out
## of check.sh's per-file parse gate.
##
## M42 opened this file with the font alone. The frames, bars and portraits every screen is
## rebuilt on land next, and they belong beside it: one place that knows what this game's
## interface is made of.

## The font every Control in the game draws in. It is NOT loaded here and handed out: it is
## named by the project setting `gui/theme/custom_font`, which Godot loads into
## ThemeDB.fallback_font and the default theme, so a Label built anywhere already has it.
##
## That is the whole reason to do it this way. A helper that handed the font out would only
## reach the labels that remembered to ask - and the one that forgot would draw in the engine's
## own face, at the right size, in the right place, looking almost right. This constant exists
## so the gate can say WHICH font its measurements are about: tests/unit/test_dialog_fit.gd
## holds what a REAL Label reports to this path.
##
## Deliberately asserted there and nowhere else. A second check on the project setting itself
## would restate the config rather than measure the outcome, and the outcome subsumes it - an
## unset setting and a deleted file both arrive as a Label reporting the wrong font. Two checks
## where one subsumes the other leave a mutant nothing can kill.
const FONT_PATH := "res://assets/fonts/pixel_operator_8.ttf"
## The bold face, for a window's header band. Named rather than loaded for the same reason the
## sizes are named: a second face is a decision, and decisions live in one file.
const FONT_BOLD_PATH := "res://assets/fonts/pixel_operator_8_bold.ttf"

## Body text, rows, captions, help lines - everything. Pixel Operator 8 is drawn for exactly
## this height; asking it for 7 or 9 scales a bitmap and undoes the reason it is here.
const FONT_SIZE := 8
## The one word on the title screen, and nothing else. Two is a whole size, so the glyphs are
## drawn rather than stretched.
const HEADING_SIZE := FONT_SIZE * 2
