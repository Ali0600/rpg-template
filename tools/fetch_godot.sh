#!/usr/bin/env bash
# The pinned Godot engine, fetched and checksummed. ONE copy of the version and the sums.
#
#   tools/fetch_godot.sh                       # the engine, into ~/godot-bin
#   tools/fetch_godot.sh --dest=/tmp/godot     # somewhere else
#   tools/fetch_godot.sh --templates           # and the WEB export templates beside it
#   tools/fetch_godot.sh --print-version       # the pin, one line, for a cache key
#   tools/fetch_godot.sh --selftest            # prove the checksum refuses AND accepts
#
# It exists because this block was written out THREE times - ci.yml's gate, ci.yml's sweep and
# pages.yml's build - with GODOT_VERSION and GODOT_SHA512 duplicated verbatim across two files
# and NOTHING gating that they agree. A bump that edited one file and not the other would gate
# on one engine and deploy from another, and the only symptom is a difference nobody looks for.
#
# A composite action was the obvious alternative and is rejected on the CI audit's own stated
# principle: a rule written in YAML is a rule in a language neither copy can be RUN in. This is
# a script with a selftest, and tests/unit/test_ci_paths.gd runs it the way it runs the other
# two.
#
# NOTE FOR ANYONE ADDING A MUTANT HERE: mutants.tsv is pipe-delimited, so a line an anchored
# mutant needs cannot contain `|`. That is why the two rules below are written as `if` blocks
# rather than the shorter `cmd || return 1` - a rule no mutant can aim at is a rule nobody has
# proven is tested.
#
# Both sums are pinned in the repository rather than fetched from the release beside the file:
# a checksum served by the same host as the file it describes cannot detect that host serving a
# different file. To update, bump GODOT_VERSION and paste the new sums from
# https://github.com/godotengine/godot-builds/releases/download/<version>/SHA512-SUMS.txt
GODOT_VERSION=4.7.1-stable
GODOT_SHA512=4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f373758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9
TEMPLATES_SHA512=afcc83d8d3d298038f19c58744a0d660fa75dd4baa33cb55d1011bb2565a2a8c2381728924564cb909e37c205a23f21b521b23bd057993afd43ae4da0b2f9d47

set -uo pipefail

# The default is the CONTRACT: both workflows hardcode ~/godot-bin in their GODOT_BIN values
# and in the steps that run the engine, so CI passes no --dest at all. Change this and those
# six strings go stale.
DEST="$HOME/godot-bin"
WANT_TEMPLATES=0
MODE=fetch

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

_fail() {
  echo "fetch_godot: $1" >&2
  exit 2
}

# Prefer coreutils where it exists, fall back to shasum. NOT `sha512sum --check`, which is what
# the workflows used to run: macOS ships a /sbin/sha512sum that rejects --check outright, so the
# long-option form is unavailable rather than merely degraded. This is the one line here with a
# pipe in it, deliberately - see the note above about anchoring mutants.
SHA512_TOOL="shasum -a 512"
command -v sha512sum >/dev/null 2>&1 && SHA512_TOOL="sha512sum"
sha512_of() { # $1 file
  $SHA512_TOOL "$1" 2>/dev/null | awk '{print $1}'
}

# The engine reports its version with DOTS - "4.7.1.stable" - where the release tag has a dash.
# One function, because the templates directory and the already-installed check must not answer
# that differently: a naive comparison against the tag never matches, and the idempotency check
# would then silently never fire.
version_dotted() {
  printf '%s' "${GODOT_VERSION/-/.}"
}

templates_dir() {
  printf '%s/.local/share/godot/export_templates/%s' "$HOME" "$(version_dotted)"
}

# RULE 1: the bytes are the pinned ones. Refuses loudly and prints BOTH sums, because
# "checksum failed" without the two values sends you to re-download rather than to the pin.
verify_sha512() { # $1 file  $2 expected
  local got
  if [ ! -f "$1" ]; then
    echo "fetch_godot: $1 is not there to verify" >&2
    return 1
  fi
  got="$(sha512_of "$1")"
  if [ -z "$got" ]; then
    echo "fetch_godot: no sha512 tool on this host (looked for sha512sum, shasum)" >&2
    return 1
  fi
  if [ "$got" = "$2" ]; then return 0; fi
  echo "fetch_godot: REFUSED $1 - the bytes are not the pinned ones" >&2
  echo "  expected $2" >&2
  echo "  actual   $got" >&2
  return 1
}

# RULE 2, and it is a DIFFERENT rule: a detection has to STOP the install. Computing the
# verdict and carrying on is the classic fail-open, and it looks identical in a green run.
fetch_verified() { # $1 url  $2 destination file  $3 expected sum
  if ! curl -fsSL --retry 3 --retry-delay 5 -o "$2" "$1"; then
    echo "fetch_godot: could not fetch $1" >&2
    rm -f "$2"
    return 1
  fi
  if ! verify_sha512 "$2" "$3"; then rm -f "$2"; return 1; fi
  return 0
}

base_url() {
  printf 'https://github.com/godotengine/godot-builds/releases/download/%s' "$GODOT_VERSION"
}

# Already the pinned engine? Then there is nothing to do, and it SAYS so - a skip that is
# silent is indistinguishable from a step that did not run.
already_installed() {
  [ -x "$DEST/godot" ] || return 1
  "$DEST/godot" --version 2>/dev/null | grep -q "^$(version_dotted)"
}

install_engine() {
  local zip="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  echo "fetch_godot: $zip"
  if ! fetch_verified "$(base_url)/$zip" "$WORK/$zip" "$GODOT_SHA512"; then return 1; fi
  mkdir -p "$DEST"
  if ! unzip -q -o "$WORK/$zip" -d "$DEST"; then return 1; fi
  mv "$DEST/Godot_v${GODOT_VERSION}_linux.x86_64" "$DEST/godot"
  chmod +x "$DEST/godot"
  "$DEST/godot" --version
}

# Only the WEB templates. The engine finds a template by looking for ONE FILE BY NAME
# (export_templates/<version>/<name>), so the other platforms' are 1.3GB of cache a web export
# can never use. The glob rather than the exact name because which of the eight it wants
# depends on the preset - this one has thread support off, so it needs web_nothreads_release.zip
# rather than web_release.zip, and that is the preset's decision to change.
install_templates() {
  local tpz="Godot_v${GODOT_VERSION}_export_templates.tpz" dest
  dest="$(templates_dir)"
  echo "fetch_godot: $tpz"
  if ! fetch_verified "$(base_url)/$tpz" "$WORK/$tpz" "$TEMPLATES_SHA512"; then return 1; fi
  mkdir -p "$dest"
  if ! unzip -q -o "$WORK/$tpz" 'templates/web_*' -d "$WORK/x"; then return 1; fi
  mv "$WORK"/x/templates/* "$dest"/
  ls -la "$dest"
}

set_options() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dest=*)        DEST="${1#--dest=}" ;;
      --templates)     WANT_TEMPLATES=1 ;;
      --print-version) MODE=print-version ;;
      --selftest)      MODE=selftest ;;
      # The 2026-08-04 lesson, made loud: a value written after a space lands in a positional
      # slot while the option keeps its DEFAULT, so the run reports on a configuration nobody
      # chose. Refused by name rather than guessed at.
      --dest)          _fail "write --dest=DIR, never --dest DIR - the space form leaves the value in a positional slot and --dest at its default" ;;
      --templates=*)   _fail "--templates takes no value; write --templates" ;;
      *)               _fail "unknown argument '$1' - every flag here is --flag=value" ;;
    esac
    shift
  done
  # Measured, not assumed: bash does NOT tilde-expand after `=` in an ordinary argument, so
  # --dest=~/godot-bin arrives as those literal characters and the engine lands in a directory
  # actually named `~`. Refused rather than expanded here, because inventing an expansion
  # policy teaches the caller nothing.
  case "$DEST" in
    '~'*) _fail "a path starting with ~ arrives literally, unexpanded - write --dest=\"\$HOME/godot-bin\"" ;;
  esac
}

# Every case drives the REAL function rather than a copy of its logic - the is_harness_change
# precedent in mutants_scope.sh. Nothing here touches the network: the propagation cases fetch
# over file://, which exercises the real curl line.
selftest() {
  local dir fail=0 good other out code
  dir="$WORK/selftest"
  mkdir -p "$dir"
  printf 'fetch_godot selftest\n' > "$dir/f"
  printf 'different bytes\n' > "$dir/g"

  ok() { # $1 label  $2 expected code  $3 actual code
    if [ "$2" != "$3" ]; then
      echo "  selftest FAIL: $1 (expected exit $2, got $3)"; fail=1
    else echo "  ok: $1"; fi
  }
  says() { # $1 label  $2 haystack  $3 needle
    case "$2" in *"$3"*) echo "  ok: $1" ;;
      *) echo "  selftest FAIL: $1 (said: $2)"; fail=1 ;; esac
  }

  # THE INSTRUMENT ITSELF, and this case is load-bearing rather than ceremony. If the expected
  # digest below came from sha512_of, then a sha512_of returning one constant for every file
  # would ACCEPT the good case and REFUSE the bad one - the whole selftest green over a
  # function that computes nothing. So the answer is a literal, measured on both tools.
  good=040f7c8b7f8bbc62f1ec34e016af1536ac43ac09e01256ca350d4308c2fdef970e762ed0c8b596bfa9ac388edf89e130c06c76e53cf9494698c337c72548f612
  out="$(sha512_of "$dir/f")"
  if [ "$out" = "$good" ]; then echo "  ok: sha512_of computes SHA-512 (known answer)"
  else echo "  selftest FAIL: sha512_of gave '$out', not the known answer"; fail=1; fi

  # Both directions. A checker that always refuses is indistinguishable from one that works,
  # so the acceptance case is what makes every refusal below evidence of anything.
  verify_sha512 "$dir/f" "$good" >/dev/null 2>&1
  ok "a correct sum is accepted" 0 $?
  # One character out, not a garbage string: one character is what a truncating or
  # prefix-matching comparison would wave through.
  verify_sha512 "$dir/f" "${good%?}0" >/dev/null 2>&1
  ok "a sum one character out is refused" 1 $?
  other="$(sha512_of "$dir/g")"
  verify_sha512 "$dir/f" "$other" >/dev/null 2>&1
  ok "another file's sum is refused" 1 $?
  verify_sha512 "$dir/f" "" >/dev/null 2>&1
  ok "an empty expected sum is refused" 1 $?
  verify_sha512 "$dir/gone" "$good" >/dev/null 2>&1
  ok "a missing file is refused rather than passed" 1 $?

  # RULE 2 - the verdict has to stop the install. A refusal that leaves the bytes at the
  # destination is a refusal the next step walks straight past.
  fetch_verified "file://$dir/f" "$dir/out_good" "$good" >/dev/null 2>&1
  ok "a verified fetch lands its file" 0 $?
  [ -f "$dir/out_good" ] && echo "  ok: the good file is there" \
    || { echo "  selftest FAIL: a verified fetch left no file"; fail=1; }
  fetch_verified "file://$dir/g" "$dir/out_bad" "$good" >/dev/null 2>&1
  ok "a fetch whose sum is wrong is refused" 1 $?
  [ -f "$dir/out_bad" ] && { echo "  selftest FAIL: a REFUSED fetch left its file behind"; fail=1; } \
    || echo "  ok: a refused fetch leaves nothing for the installer to find"

  # The parser, in a subshell so _fail's exit does not take the selftest with it.
  out="$(set_options --dest /tmp/whatever 2>&1)"; code=$?
  ok "the space form is refused" 2 $code
  says "the refusal names --dest" "$out" "--dest"
  out="$(set_options '--dest=~/godot-bin' 2>&1)"; code=$?
  ok "a literal tilde in a path is refused" 2 $code
  says "the refusal explains the tilde" "$out" "~"
  ( set_options --templates=yes ) >/dev/null 2>&1
  ok "--templates with a value is refused" 2 $?
  ( set_options --nonsense ) >/dev/null 2>&1
  ok "an unknown flag is refused" 2 $?
  out="$( set_options --dest=/tmp/somewhere >/dev/null 2>&1; printf '%s' "$DEST" )"
  if [ "$out" = "/tmp/somewhere" ]; then echo "  ok: --dest=VALUE actually sets the destination"
  else echo "  selftest FAIL: --dest=VALUE left DEST as '$out'"; fail=1; fi

  out="$(version_dotted)"
  if [ "$out" = "${GODOT_VERSION%%-*}.${GODOT_VERSION#*-}" ]; then
    echo "  ok: the version is dotted the way the engine reports it"
  else echo "  selftest FAIL: version_dotted gave '$out'"; fail=1; fi
  # Exactly the pin and nothing else: a cache key is built from this, and a banner line would
  # break $GITHUB_OUTPUT's format.
  out="$("$0" --print-version 2>/dev/null)"
  if [ "$out" = "$GODOT_VERSION" ]; then echo "  ok: --print-version prints exactly the pin"
  else echo "  selftest FAIL: --print-version said '$out', not '$GODOT_VERSION'"; fail=1; fi

  [ "$fail" -eq 0 ] || return 1
  echo "  fetch_godot: selftest passed"
}

set_options "$@"

case "$MODE" in
  print-version) printf '%s\n' "$GODOT_VERSION"; exit 0 ;;
  selftest)      selftest; exit $? ;;
esac

# The pin names a Linux x86_64 build and a digest that will never match anything else, so on
# any other host this would download a binary that cannot run. Said here rather than discovered
# at the checksum.
if [ "$(uname -s)" != "Linux" ]; then
  _fail "this fetches the Linux x86_64 build; on $(uname -s) install Godot yourself and point GODOT_BIN at it"
fi

if already_installed; then
  echo "fetch_godot: $DEST/godot is already $GODOT_VERSION"
else
  if ! install_engine; then exit 1; fi
fi
if [ "$WANT_TEMPLATES" -eq 1 ]; then
  if ! install_templates; then exit 1; fi
fi
exit 0
