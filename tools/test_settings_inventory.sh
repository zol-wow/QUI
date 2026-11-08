#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."

lua_bin="${LUA:-$(command -v lua5.1 || command -v lua)}"
jobs="${1:-${JOBS:-$(nproc 2>/dev/null || echo 4)}}"
if [ "$#" -gt 1 ] || ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    echo "usage: bash tools/test_settings_inventory.sh [positive worker count]" >&2
    exit 2
fi
[ "$jobs" -gt 4 ] && jobs=4
scratch=$(mktemp -d) || exit 1
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
started=$SECONDS
for ((shard=1; shard<=jobs; shard++)); do
    "$lua_bin" tests/unit/settings_controls_inventory_test.lua --shard "$shard/$jobs" \
        --output "$scratch/$shard.lua" >"$scratch/$shard.log" 2>&1 &
    pids+=("$!")
done
failed=0
reports=()
for ((shard=1; shard<=jobs; shard++)); do
    if ! wait "${pids[shard-1]}"; then
        echo "FAIL: settings inventory shard $shard/$jobs" >&2
        failed=1
    fi
    cat "$scratch/$shard.log"
    if [ ! -s "$scratch/$shard.lua" ]; then
        echo "FAIL: missing inventory report for shard $shard/$jobs" >&2
        failed=1
    fi
    reports+=("$scratch/$shard.lua")
done
pids=()
[ "$failed" -eq 0 ] || exit 1
"$lua_bin" tests/unit/settings_controls_inventory_test.lua --merge "$jobs" "${reports[@]}" || exit 1
echo "settings inventory: $jobs workers, $((SECONDS-started))s"
