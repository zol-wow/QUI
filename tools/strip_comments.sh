#!/usr/bin/env bash
# tools/strip_comments.sh — strip comments from QUI's own addon Lua.
#
# Scope: core/, modules/, QUI_*/, init.lua, importstrings/. Deliberately NOT
# libs/ (vendored — comments are what let you diff a lib against upstream and
# spot a local patch), NOT meta/ (those files are nothing BUT annotations), NOT
# tools/, NOT tests/.
#
# Every file is proved semantically unchanged before it is written, in two steps:
#
#   1. The stripper is run in --preserve-lines mode, which blanks comments out
#      in place rather than deleting them, so line numbering is identical. The
#      original and that output are both compiled with `luac -s` and the two
#      bytecode blobs must be byte-identical. (`luac -s` drops debug info but
#      still dumps every prototype's linedefined/lastlinedefined, which is
#      exactly why this step has to keep the line count.) This proves the lexer
#      only ever removed comments.
#   2. The real output must equal that same text with blank-only lines dropped
#      and indentation normalised — a pure whitespace difference, which Lua
#      cannot see. Compared line by line.
#
# A file that fails either step is left untouched and reported as FAIL.
#
#   bash tools/strip_comments.sh --dry-run   # report only, write nothing
#   bash tools/strip_comments.sh             # strip in place
set -uo pipefail

cd "$(dirname "$0")/.."

LUA_BIN=$(command -v lua5.1 || command -v lua) || { echo "no lua interpreter" >&2; exit 1; }
LUAC_BIN=$(command -v luac5.1 || command -v luac) || { echo "no luac" >&2; exit 1; }

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git ls-files -- \
    'core/*.lua' 'modules/*.lua' 'QUI_*/*.lua' 'init.lua' 'importstrings/*.lua' \
    > "$WORK/files.txt"

echo "scope: $(wc -l < "$WORK/files.txt") files"

# A few comments are structure rather than prose — the suite slices regions out
# of a source file on them. They are listed, with reasons, in a CURATED file
# rather than harvested: harvesting kept thousands of lines nothing needed.
ANCHORS=tests/helpers/comment_anchors.lua
cp "$ANCHORS" "$WORK/anchors.lua"
echo "pinned comments: $("$LUA_BIN" -e "print(#dofile('$ANCHORS'))") entries in $ANCHORS"

process_one() {
    local f="$1" work="$2" dry="$3" lua="$4" luac="$5" anchors="$6"
    local tag; tag=$(printf '%s' "$f" | tr '/' '_')
    local new="$work/$tag.new.lua" keep="$work/$tag.keep.lua"
    local a="$work/$tag.a.out" b="$work/$tag.b.out"

    if ! "$luac" -s -o "$a" "$f" 2>/dev/null; then
        echo "SKIP $f (original does not compile)"
        return
    fi

    # Step 1 — line-preserving strip must produce identical bytecode.
    if ! "$lua" tools/strip_comments.lua --anchors "$anchors" --preserve-lines "$f" > "$keep" 2>"$work/$tag.err"; then
        echo "FAIL strip $f: $(head -1 "$work/$tag.err")"
        return
    fi
    if ! "$luac" -s -o "$b" "$keep" 2>"$work/$tag.err"; then
        echo "FAIL compile $f: $(head -1 "$work/$tag.err")"
        return
    fi
    if ! cmp -s "$a" "$b"; then
        echo "FAIL bytecode differs $f"
        return
    fi

    # Step 2 — the real output must differ from step 1 only in whitespace.
    if ! "$lua" tools/strip_comments.lua --anchors "$anchors" "$f" > "$new" 2>"$work/$tag.err"; then
        echo "FAIL strip $f: $(head -1 "$work/$tag.err")"
        return
    fi
    local norm='s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
    if ! diff -q <(sed "$norm" "$keep") <(sed "$norm" "$new") >/dev/null; then
        echo "FAIL non-whitespace diff $f"
        return
    fi

    local before after
    before=$(wc -l < "$f")
    after=$(wc -l < "$new")
    if [[ "$before" != "$after" ]]; then
        [[ "$dry" == "0" ]] && cp "$new" "$f"
        echo "OK $f $before -> $after"
    fi
}
export -f process_one

xargs -a "$WORK/files.txt" -P "$(nproc)" -I{} \
    bash -c 'process_one "$@"' _ {} "$WORK" "$DRY_RUN" "$LUA_BIN" "$LUAC_BIN" "$WORK/anchors.lua" \
    > "$WORK/report.txt"

grep -c '^OK ' "$WORK/report.txt" | xargs -I{} echo "changed: {} files"
awk '/^OK /{b+=$3; a+=$5} END{printf "lines: %d -> %d (-%d)\n", b, a, b-a}' "$WORK/report.txt"
if grep -q '^FAIL\|^SKIP' "$WORK/report.txt"; then
    echo "--- problems ---"
    grep '^FAIL\|^SKIP' "$WORK/report.txt"
fi
cp "$WORK/report.txt" /tmp/strip_comments_report.txt
echo "full report: /tmp/strip_comments_report.txt"
