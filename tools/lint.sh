#!/usr/bin/env bash
# Run CI's Luacheck lint job locally, fanned out across cores.
# Usage: bash tools/lint.sh        (from anywhere; cd's to the repo root)
#        JOBS=1 bash tools/lint.sh (serialize)
#
# This IS the `lint` job in .github/workflows/lua-tests.yml — that workflow's
# "Lint (luacheck)" step invokes this script, so TARGETS below is the single
# copy of the lint scope. It used to be duplicated as an inline argument list
# on that step, where a target added to one and not the other was a gate that
# could only fail after a push.
#
# tools/test.sh calls this as gate 7. Run it standalone when you want lint alone
# without paying for the full suite.
#
# Shard by DIRECTORY, never by file. Measured 2026-07-26: by-directory
# 15.9s -> 4.2s; by-file was 57s, i.e. slower than serial.
set -uo pipefail
cd "$(dirname "$0")/.."

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
[ "$JOBS" -lt 1 ] && JOBS=1

TARGETS=(
    QUI_Debug/ core/ modules/ init.lua
    QUI_ActionBars/ QUI_Bags/ QUI_CDM/ QUI_Chat/
    QUI_DamageMeter/ QUI_GroupFrames/ QUI_Nameplates/ QUI_Options/
    QUI_ResourceBars/ QUI_UnitFrames/
    tests/unit/ tests/helpers/ tests/replay/ tests/taint/
)

if ! command -v luacheck >/dev/null 2>&1; then
    echo "error: luacheck not installed — CI's lint job cannot be mirrored." >&2
    echo "       (this host has no luarocks; install luacheck however you like)" >&2
    exit 2
fi

# Fast path: parallel, output discarded. Findings are rare, so pay for readable
# output only when there are some — a parallel run interleaves the per-target
# reports and makes them hard to read.
if printf '%s\n' "${TARGETS[@]}" \
    | xargs -P "$JOBS" -I{} luacheck {} >/dev/null 2>&1; then
    echo "luacheck: clean across ${#TARGETS[@]} CI targets"
    exit 0
fi

echo "luacheck findings — re-running serially for readable output:" >&2
luacheck "${TARGETS[@]}"
exit 1
