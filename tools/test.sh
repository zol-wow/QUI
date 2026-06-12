#!/usr/bin/env bash
# Run every CI quality gate locally, in the order cheapest-first.
# Usage: bash tools/test.sh        (from the repository root)
#
# Gates (mirrors .github/workflows/ lua-tests.yml, profile-tests.yml,
# taint-check.yml strict job):
#   1. luac 5.1 compile check        tools/check_compile.sh
#   2. taint analyzer, strict mode   tools/test_taint.lua --strict-only
#   3. profile fixture tests         tools/test_profiles.lua
#   4. standalone unit tests         tests/unit/*.lua
#
# WoW runs Lua 5.1. Prefer lua5.1/luac5.1; fall back to `lua` with a warning
# (5.4 accepts code 5.1 rejects — see tools/check_compile.sh header).
set -uo pipefail
cd "$(dirname "$0")/.."

LUA_BIN="${LUA:-$(command -v lua5.1 || command -v lua)}"
[ -z "$LUA_BIN" ] && { echo "error: no lua interpreter found" >&2; exit 2; }
case "$LUA_BIN" in
  *5.1*) : ;;
  *) echo "warning: lua5.1 not found, using $("$LUA_BIN" -v 2>&1 | head -1)." \
          "CI runs 5.1 — results may differ. (brew install lua@5.1)" >&2 ;;
esac

fail=0

echo "== gate 1/4: compile check (luac 5.1) =="
bash tools/check_compile.sh || fail=1

echo "== gate 2/4: taint analyzer (strict) =="
"$LUA_BIN" tools/test_taint.lua --strict-only || fail=1

echo "== gate 3/4: profile fixture tests =="
"$LUA_BIN" tools/test_profiles.lua || fail=1

echo "== gate 4/4: unit tests (tests/unit/) =="
unit_fail=0; unit_count=0
for t in tests/unit/*.lua; do
  unit_count=$((unit_count + 1))
  if ! "$LUA_BIN" "$t" >/dev/null 2>&1; then
    echo "FAIL: $t"
    "$LUA_BIN" "$t" || true   # re-run loudly so the error is visible
    unit_fail=1
  fi
done
[ "$unit_fail" -eq 0 ] && echo "unit tests: $unit_count files passed" || fail=1

if [ "$fail" -eq 0 ]; then echo "ALL GATES PASSED"; else echo "GATE FAILURES ABOVE" >&2; fi
exit "$fail"
