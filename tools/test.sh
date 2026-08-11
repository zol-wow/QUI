#!/usr/bin/env bash
# Run every CI quality gate locally, in the order cheapest-first.
# Usage: bash tools/test.sh        (from the repository root)
#        JOBS=1 bash tools/test.sh (serialize everything)
#
# Gates (mirrors BOTH jobs of .github/workflows/lua-tests.yml, plus
# profile-tests.yml and taint-check.yml's analyze + self-test jobs):
#   1. luac 5.1 compile check        tools/check_compile.sh
#   2. taint analyzer, strict mode   tools/test_taint.lua --strict-only
#   3. taint analyzer unit tests     tests/taint/*_test.lua + parser
#   4. profile fixture tests         tools/test_profiles.lua
#   5. standalone unit tests         tests/unit/*.lua
#   6. tooling + i18n unit tests     tests/api-docs/extract_test.lua,
#                                    tools/lua_defs_gen_test.lua,
#                                    tools/test_i18n_{locale,extract,format}.lua
#   7. luacheck, CI lint scope       tools/lint.sh
#   8. search cache staleness        tools/generate_search_cache.lua + audit
#   9. i18n base staleness           tools/i18n/extract_strings.lua
#
# CI does NOT invoke this script — every workflow step is written out inline —
# so this mirror is maintained by hand. When you add a step to lua-tests.yml,
# add it here too, or it becomes a gate that can only fail after a push.
# Gate 7 is the one exception: CI's lint step shells out to tools/lint.sh, so
# the lint scope has a single definition and cannot drift.
#
# Gates 2, 3, 5, 6 and 7 fan out across $JOBS cores. Gate 2 alone was 91% of the
# suite's wall time before sharding (2m24s of 2m39s, measured 2026-07-26).
#
# Gates 8-9 run code generators that WRITE into the working tree. They snapshot
# every target first and restore it afterwards, so the suite never leaves your
# tree modified — including when a generated file was already dirty going in.
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

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
[ "$JOBS" -lt 1 ] && JOBS=1

fail=0
lint_skipped=0

# Run standalone Lua test files in parallel, then re-run any failure loudly so
# its output is readable and not interleaved with the other jobs'.
run_lua_tests() {
    local label="$1"; shift
    local failed t
    failed=$(printf '%s\n' "$@" | xargs -P "$JOBS" -I{} \
        sh -c '"$0" "$1" >/dev/null 2>&1 || printf "%s\n" "$1"' "$LUA_BIN" {})
    if [ -n "$failed" ]; then
        printf '%s\n' "$failed" | while IFS= read -r t; do
            echo "FAIL: $t"
            "$LUA_BIN" "$t" || true
        done
        return 1
    fi
    echo "$label: $# files passed"
    return 0
}

# check_stale <label> <generator-command> <generated-path>...
#
# Runs the generator and reports whether it changed any target, i.e. whether the
# committed copy has drifted from what the sources now produce. Compares against
# a pre-run snapshot rather than against HEAD (which is what CI does) so that an
# unrelated uncommitted edit to a generated file does not read as staleness, and
# restores that snapshot unconditionally so the gate has no side effects.
check_stale() {
    local label="$1" gen="$2"; shift 2
    local snap rc=0 p key
    snap=$(mktemp -d) || return 1
    for p in "$@"; do
        key=$(printf '%s' "$p" | tr / _)
        [ -f "$p" ] && cp -p "$p" "$snap/$key"
    done

    if ! eval "$gen" >"$snap/.gen.log" 2>&1; then
        echo "FAIL: $label generator errored:"
        cat "$snap/.gen.log"
        rc=1
    else
        for p in "$@"; do
            key=$(printf '%s' "$p" | tr / _)
            if [ ! -f "$snap/$key" ]; then
                echo "STALE: $p was not committed but the generator produces it"
                rc=1
            elif ! cmp -s "$p" "$snap/$key"; then
                echo "STALE: $p — regenerating it changes the file"
                git --no-pager diff --stat -- "$p" 2>/dev/null || true
                rc=1
            fi
        done
    fi

    for p in "$@"; do
        key=$(printf '%s' "$p" | tr / _)
        [ -f "$snap/$key" ] && cp -p "$snap/$key" "$p"
    done
    rm -rf "$snap"
    [ "$rc" -eq 0 ] && echo "$label: up to date"
    return "$rc"
}

# lua-tests.yml skips both staleness gates on beta and alpha, where the regen
# bots auto-commit instead (see regen-search-cache.yml / regen-i18n-base.yml).
# Keep running them here for early warning, but do not fail the suite over a
# drift the bot is going to fix. Keep this branch list in sync with the `if:`
# conditions in lua-tests.yml.
stale_advisory=0
case "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" in
    alpha|beta) stale_advisory=1 ;;
esac

# Record a staleness result, honouring the advisory branches above.
note_stale_result() {
    if [ "$1" -eq 0 ]; then return 0; fi
    if [ "$stale_advisory" -eq 1 ]; then
        echo "  (advisory only: the regen bot auto-commits this on $(git rev-parse --abbrev-ref HEAD))"
    else
        fail=1
    fi
}

echo "== gate 1/9: compile check (luac 5.1) =="
bash tools/check_compile.sh || fail=1

echo "== gate 2/9: taint analyzer (strict, $JOBS shards) =="
shard_dir=$(mktemp -d)
for s in $(seq 1 "$JOBS"); do
    (
        "$LUA_BIN" tools/test_taint.lua --strict-only --shard "$s/$JOBS" \
            >"$shard_dir/$s.out" 2>"$shard_dir/$s.err"
        echo $? >"$shard_dir/$s.rc"
    ) &
done
wait
taint_strict_shards=0
for s in $(seq 1 "$JOBS"); do
    cat "$shard_dir/$s.out"
    cat "$shard_dir/$s.err" >&2
    if [ "$(cat "$shard_dir/$s.rc" 2>/dev/null || echo 2)" -ne 0 ]; then
        taint_strict_shards=$((taint_strict_shards + 1))
        fail=1
    fi
done
rm -rf "$shard_dir"
[ "$taint_strict_shards" -gt 0 ] \
    && echo "taint: strict findings in $taint_strict_shards of $JOBS shards" >&2

echo "== gate 3/9: taint analyzer unit tests (tests/taint/) =="
run_lua_tests "taint tests" \
    tests/taint/*_test.lua tests/taint/parser/parser_test.lua || fail=1

echo "== gate 4/9: profile fixture tests =="
"$LUA_BIN" tools/test_profiles.lua || fail=1

echo "== gate 5/9: unit tests (tests/unit/) =="
run_lua_tests "unit tests" tests/unit/*.lua || fail=1

echo "== gate 6/9: tooling + i18n unit tests =="
run_lua_tests "tooling tests" \
    tests/api-docs/extract_test.lua tools/lua_defs_gen_test.lua \
    tools/test_i18n_locale.lua tools/test_i18n_extract.lua \
    tools/test_i18n_format.lua || fail=1

# The ten locale overlays have no staleness gate — translate_delta.py needs an
# API key, so CI cannot regenerate them — which leaves format drift between the
# committed files and their writer invisible. This round-trips each file
# through overlay_source and requires byte equality. Python-only; skipped with
# a warning rather than failing a Lua-only environment.
if command -v python3 >/dev/null 2>&1; then
    if python3 tools/i18n/test_overlay_roundtrip.py >/dev/null 2>&1; then
        echo "locale overlays: match their writer"
    else
        python3 tools/i18n/test_overlay_roundtrip.py >/dev/null
        echo "FAIL: locale overlays drifted from tools/i18n/translate_delta.py" >&2
        fail=1
    fi

    # Three parsers read core/locale/enUS.lua; translate_delta's regex once
    # silently dropped every pair whose value contained an embedded newline
    # (5721 of 5728 keys) because `.` does not cross a newline without
    # re.DOTALL. This pins all of them against a real Lua load.
    if python3 tools/i18n/test_enus_parser_agreement.py >/dev/null 2>&1; then
        echo "enUS parsers: agree with a real Lua load"
    else
        python3 tools/i18n/test_enus_parser_agreement.py >/dev/null
        echo "FAIL: an enUS.lua parser disagrees with a real Lua load" >&2
        fail=1
    fi
else
    echo "WARNING: python3 not installed — locale overlay round-trip and enUS" \
         "parser agreement NOT checked." >&2
fi

echo "== gate 7/9: luacheck (CI lint scope) =="
if command -v luacheck >/dev/null 2>&1; then
    bash tools/lint.sh || fail=1
else
    lint_skipped=1
    echo "WARNING: luacheck not installed — CI's lint job is NOT mirrored." >&2
fi

echo "== gate 8/9: generated search cache is not stale =="
# The path must match generate_search_cache.lua's OUTPUT_PATH. check_stale
# compares the generator's targets against a pre-run snapshot, so naming a path
# the generator no longer writes makes this gate pass unconditionally while
# checking nothing.
check_stale "search cache" \
    "\"$LUA_BIN\" tools/generate_search_cache.lua && \"$LUA_BIN\" tools/audit_search_cache.lua" \
    QUI_Options/search_cache.lua
note_stale_result $?

echo "== gate 9/9: i18n base is not stale =="
# The generator is TWO commands. extract_strings.lua rewrites core/locale/enUS.lua
# whole and cannot compute the `-- keyset:` checksum (Lua 5.1 has no SHA-256), so
# stamp_enus_keyset.py puts that line back. Running the extractor alone deletes
# it, and that line is what tests/unit/locale_keyset_checksum_test.lua compares
# the ten positional overlays against — so a bare run reads as permanent staleness.
i18n_gen="\"$LUA_BIN\" tools/i18n/extract_strings.lua"
if command -v python3 >/dev/null 2>&1; then
    i18n_gen="$i18n_gen && python3 tools/i18n/stamp_enus_keyset.py"
else
    echo "WARNING: python3 not installed — the enUS '-- keyset:' line cannot be" \
         "stamped, so this gate will report staleness it cannot fix." >&2
fi
check_stale "i18n base" "$i18n_gen" core/locale/enUS.lua
note_stale_result $?

if [ "$fail" -eq 0 ]; then
    if [ "$lint_skipped" -eq 1 ]; then
        echo "ALL GATES PASSED — WARNING: gate 7 (luacheck) SKIPPED, not installed"
    else
        echo "ALL GATES PASSED"
    fi
else
    echo "GATE FAILURES ABOVE" >&2
fi
exit "$fail"
