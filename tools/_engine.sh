# Shared engine resolution. Sourced by check.sh and mutate_check.sh so both survive the
# app being moved (Downloads -> Applications is the usual one). GODOT_BIN always wins.
resolve_godot() {
  if [ -n "${GODOT_BIN:-}" ]; then printf '%s' "$GODOT_BIN"; return; fi
  for c in \
    /Applications/Godot.app/Contents/MacOS/Godot \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
    "$(command -v godot 2>/dev/null)" \
    "$(command -v godot4 2>/dev/null)"
  do
    [ -n "$c" ] && [ -x "$c" ] && printf '%s' "$c" && return
  done
}

# Flags for anything driven by FRAMES - the test suite, the scripted play sessions, the
# mutation sweep. Headless does not mean fast: the engine still paces its main loop against the
# wall clock, so a play session that takes a player three minutes takes the gate three minutes
# too. --fixed-fps pins every frame's delta AND stops waiting for real time between them.
#
# It changes nothing a gate can observe. Every one of these harnesses counts PHYSICS FRAMES,
# never seconds, and the delta each frame reports is the same 1/60 it was before - which is why
# the ten play sessions produce byte-identical logs with it and without it, and why the whole
# suite returns identical verdicts on all 595 tests. Measured, not assumed: play 371s -> 8s,
# suite 37s -> 8s.
#
# Do NOT add this to the generators (gen_sprites, gen_sounds) or the one-shot tools. They quit
# in their first frame, so it would buy nothing and would put a flag in a command line nobody
# needs to understand.
GODOT_FRAMES="--fixed-fps 60"

require_godot() {
  GODOT="$(resolve_godot)"
  if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
    echo "FAIL: could not find a Godot binary."
    echo "  Looked in /Applications, ~/Applications, ~/Downloads, and \$PATH."
    echo "  Set GODOT_BIN=/path/to/Godot and re-run."
    exit 1
  fi
}
