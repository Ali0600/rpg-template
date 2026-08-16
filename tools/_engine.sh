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

require_godot() {
  GODOT="$(resolve_godot)"
  if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
    echo "FAIL: could not find a Godot binary."
    echo "  Looked in /Applications, ~/Applications, ~/Downloads, and \$PATH."
    echo "  Set GODOT_BIN=/path/to/Godot and re-run."
    exit 1
  fi
}
