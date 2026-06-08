#!/usr/bin/env bash
# Compile-check every QUI-authored Lua file under WoW's Lua 5.1.
#
# WoW runs Lua 5.1, whose per-function limits are MAX 60 upvalues and MAX 200
# locals. Lua 5.2+ raised the upvalue cap to 255, so `luac5.4 -p` SILENTLY
# accepts a 61+-upvalue function that WoW rejects at load with
#   "function at line N has more than 60 upvalues"
# (which then cascades: the whole file fails to compile, so later top-level
# assignments never run and unrelated files hit "attempt to call a nil value").
#
# The unit-test suite runs on 5.1 but only compiles files it loads, so a
# runtime-only file no test imports (e.g. the CDM event engine) is never
# compiled by any gate. This script closes that hole: it compiles EVERY shipped
# QUI Lua file under 5.1.
#
# Vendored trees are excluded: their locale files carry UTF-8 BOMs that WoW's
# loader strips but stock luac rejects, and they are pre-validated upstream.
set -uo pipefail

luac="${LUAC:-$(command -v luac5.1 || command -v luac)}"
if [ -z "$luac" ]; then
  echo "error: luac (Lua 5.1) not found. Install lua5.1 or set LUAC=/path/to/luac5.1" >&2
  exit 2
fi

fail=0
count=0
while IFS= read -r f; do
  count=$((count + 1))
  if ! out=$("$luac" -p "$f" 2>&1); then
    echo "COMPILE FAIL: $f"
    echo "  ${out#*: }"
    fail=1
  fi
done < <(git ls-files '*.lua' | grep -viE '^libs/|^Libs/|^tests/framexml/|^tests/api-docs/')

if [ "$fail" -eq 0 ]; then
  echo "luac (5.1): $count QUI-authored Lua files compile cleanly"
else
  echo "luac (5.1): compile failures above — these crash on in-game load" >&2
fi
exit "$fail"
