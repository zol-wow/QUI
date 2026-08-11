#!/usr/bin/env bash
# Run a command over a list of items, N-way parallel. Reads items on stdin.
#
#   ls tests/unit/*.lua        | bash tools/pfor.sh lua5.1
#   seq 1 6                    | bash tools/pfor.sh sh -c 'lua5.1 tools/test_taint.lua --strict-only --shard $0/6'
#   git ls-files '*.lua'       | JOBS=8 bash tools/pfor.sh luacheck
#
# Exists because the reflex form -- `for f in ...; do cmd "$f"; done` -- leaves
# 31 of this box's 32 cores idle, and it is just as wrong in a one-off
# verification run as in a committed script. This is shorter than the loop, so
# there is no excuse to reach for the loop.
#
# Prints each failing item to stderr and exits 1 if any invocation failed, so it
# is usable as a gate. Item order in the output is not deterministic; if you
# need ordered output, collect per-item into files and cat them afterwards.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: <items on stdin> | pfor.sh <command> [args...]" >&2; exit 2; }

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
[ "$JOBS" -lt 1 ] && JOBS=1

# In `sh -c SCRIPT name arg...`, $0 is `name` and $1 is the first arg -- so the
# item arrives as $1 and the command words follow it. Capture the item, shift it
# off, and "$@" is then exactly the command to run.
failed=$(xargs -P "$JOBS" -I{} sh -c \
    'item="$1"; shift; "$@" "$item" >/dev/null 2>&1 || printf "%s\n" "$item"' \
    _ {} "$@")

if [ -n "$failed" ]; then
    echo "pfor: $(printf '%s\n' "$failed" | wc -l) item(s) failed:" >&2
    printf '%s\n' "$failed" | while IFS= read -r item; do echo "  $item" >&2; done
    exit 1
fi
