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
# Vendored framexml/api-docs corpora are excluded (reference-only, never
# loaded in-game), as is a project-local .luarocks/ tree: CI installs luacheck
# into the workspace, and luacheck vendors a Lua 5.3-only sha1 backend that
# luac5.1 cannot parse. Shipped libs/ ARE compiled — in a second pass that strips
# the UTF-8 BOMs stock luac rejects (WoW's loader strips them itself) — since
# a vendored lib that fails 5.1 limits crashes in-game exactly like our code;
# libs were previously exempt from every gate, which let a shipped
# LibOpenRaid hazard ride through green suites (2026-07 external review).
set -uo pipefail

luac="${LUAC:-$(command -v luac5.1 || command -v luac)}"
if [ -z "$luac" ]; then
  echo "error: luac (Lua 5.1) not found. Install lua5.1 or set LUAC=/path/to/luac5.1" >&2
  exit 2
fi

fail=0
count=0
while IFS= read -r f; do
  # `git ls-files --cached` includes paths deleted in the working tree until
  # their deletion is staged. Skip those paths so local verification works
  # before staging, while `--others` below also compiles newly added files.
  [ -f "$f" ] || continue
  count=$((count + 1))
  if ! out=$("$luac" -p "$f" 2>&1); then
    echo "COMPILE FAIL: $f"
    echo "  ${out#*: }"
    fail=1
  fi
done < <(git ls-files --cached --others --exclude-standard '*.lua' | grep -viE '^libs/|^Libs/|^tests/framexml/|^tests/api-docs/|^\.luarocks/')

libcount=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  libcount=$((libcount + 1))
  # BOM-strip (first line only) then compile from stdin; luac reports the
  # file as "stdin", so print the real path ourselves on failure.
  if ! out=$(sed '1s/^\xEF\xBB\xBF//' "$f" | "$luac" -p - 2>&1); then
    echo "COMPILE FAIL (lib): $f"
    echo "  ${out#*: }"
    fail=1
  fi
done < <(git ls-files --cached --others --exclude-standard 'libs/*.lua' 'Libs/*.lua')

if [ "$fail" -eq 0 ]; then
  echo "luac (5.1): $count QUI-authored + $libcount vendored lib Lua files compile cleanly"
else
  echo "luac (5.1): compile failures above — these crash on in-game load" >&2
fi
exit "$fail"
