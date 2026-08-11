#!/usr/bin/env python3
"""Merge hand- or agent-supplied translations into a locale overlay.

Produces output byte-identical to a `translate_delta.py` run: it reuses that
module's `write_locale()`, the same `validate_format.lua` parity gate, the same
"prune keys no longer in enUS" rule, and the same `state.json` hash rewrite. Use
this instead of hand-editing an overlay -- a hand-edited overlay drifts from the
generator's formatting and the next real run rewrites it anyway.

  python3 tools/i18n/merge_translations.py <locale> <payload.json>
  python3 tools/i18n/merge_translations.py <locale> <payload.json> --dry-run

The payload is a flat JSON object mapping the exact English key to the
translated value. Keys absent from enUS are a hard error, not a warning: they
mean the payload was written against a stale enUS dump and silently dropping
them would lose work.

SERIALIZE CALLS. `tools/i18n/state.json` is a multi-megabyte read-modify-write,
so two concurrent merges interleave and silently drop hash entries -- nothing
downstream fails, the loss only surfaces later as keys being needlessly
retranslated. Same reason `generate_search_cache.lua` must not run in parallel.

Validation note: `validate_format.lua` is deliberately asymmetric -- it rejects
an ADDED specifier (which risks consuming a nil arg) but tolerates a DROPPED
one, because Lua's string.format ignores surplus args. A translation that
silently loses a `%d` therefore passes that gate. This script adds the stricter
exact-multiset check the gate does not do.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
os.chdir(REPO)
sys.path.insert(0, str(REPO))

from tools.i18n.translate_delta import (  # noqa: E402
    read_enus, load_existing, write_locale, sha1, STATE, LOCALES, lua_bin, luac_bin,
)

# Mirrors validate_format.lua's SPEC pattern (no space-flag, positional kept).
SPEC = re.compile(r"%(?:\d+\$)?[-+#0]*\d*\.?\d*[diouxXeEfgGqscp]")


def specifiers(s):
    """Multiset of printf specifiers, with %% masked out first."""
    masked = s.replace("%%", "\x02\x02")
    out = {}
    for tok in SPEC.findall(masked):
        out[tok] = out.get(tok, 0) + 1
    return out


def escapes(s):
    return (s.count("|c"), s.count("|r"), s.count("|T"), s.count("|H"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("locale", choices=LOCALES)
    ap.add_argument("payload", help="JSON object: {english_key: translated_value}")
    ap.add_argument("--dry-run", action="store_true",
                    help="validate and report, write nothing")
    args = ap.parse_args()
    loc = args.locale

    payload = json.load(open(args.payload, encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"{args.payload}: expected a JSON object, got {type(payload).__name__}")

    enus = read_enus()
    manifest = {k: sha1(v) for k, v in enus.items()}
    existing = load_existing(loc)

    orphans = [k for k in payload if k not in enus]
    if orphans:
        raise SystemExit(
            f"{loc}: {len(orphans)} key(s) absent from enUS -- payload is stale, refusing:\n  "
            + "\n  ".join(repr(k) for k in orphans[:20]))

    drift = []
    for k, v in payload.items():
        if specifiers(k) != specifiers(v):
            drift.append(f"specifier mismatch: {k!r}\n      -> {v!r}")
        elif escapes(k) != escapes(v):
            drift.append(f"escape mismatch:    {k!r}\n      -> {v!r}")
    if drift:
        raise SystemExit(f"{loc}: {len(drift)} payload entr(y/ies) failed the strict check:\n  "
                         + "\n  ".join(drift[:20]))

    for k, v in payload.items():
        existing[k] = v

    before = len(existing)
    existing = {k: v for k, v in existing.items() if k in enus}
    pruned = before - len(existing)
    missing = [k for k in enus if k not in existing]

    if args.dry_run:
        print(f"{loc}: DRY RUN -- would apply={len(payload)} prune={pruned} "
              f"total={len(existing)} still-missing={len(missing)}")
        return

    write_locale(loc, existing)

    # Reuse the Lua validator as the source of truth for format/escape parity.
    pairs = "return {" + "".join(
        f"[{json.dumps(k, ensure_ascii=False)}]={json.dumps(existing[k], ensure_ascii=False)},"
        for k in existing) + "}"
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as tf:
        tf.write(pairs)
        tf_path = tf.name
    chk = subprocess.run(
        [lua_bin(), "-e",
         'local V=assert(loadfile("tools/i18n/validate_format.lua"))();'
         f'local d=V.validate(assert(loadfile("{tf_path}"))());'
         'if #d>0 then for _,x in ipairs(d) do io.stderr:write(x.key.."\\n") end os.exit(1) end'],
        capture_output=True, text=True)
    os.unlink(tf_path)
    if chk.returncode != 0:
        raise SystemExit(f"{loc}: format parity drift:\n{chk.stderr}")

    # The overlay wraps its table in a long-bracket string that only compiles at
    # login, so `luac -p` on the file alone would pass with a broken table
    # inside. Load it the way the client does — GetLocale() stubbed to this
    # locale — which compiles the wrapper AND the inner chunk, and prove the
    # table actually materialized.
    #
    # The table is POSITIONAL: slot N holds the translation of enUS key N, so
    # "it materialized" is not enough — its length must match enUS's key array
    # or every ID past the drift point resolves to the wrong English string.
    # Integer-keys-only is the second half of that proof: a table still keyed
    # by English text is the retired format and would resolve to nothing.
    subprocess.run([luac_bin(), "-p", f"core/locale/{loc}.lua"], check=True)
    subprocess.run(
        [lua_bin(), "-e",
         f'GetLocale = function() return "{loc}" end; QUIDB = nil;'
         f'local ns = {{}};'
         f'assert(loadfile("core/locale/enUS.lua"))("QUI", ns);'
         f'local keys = ns.LocaleData and ns.LocaleData.keys;'
         f'assert(type(keys) == "table" and #keys > 0, '
         f'"core/locale/enUS.lua produced no ns.LocaleData.keys array");'
         f'assert(loadfile("core/locale/{loc}.lua"))("QUI", ns);'
         f'local t = ns.LocaleData and ns.LocaleData.active;'
         f'assert(type(t) == "table" and next(t), "{loc}: overlay produced no table");'
         f'for k in pairs(t) do assert(type(k) == "number", '
         f'"{loc}: overlay is keyed by English text, not positional") end;'
         f'assert(#t == #keys, "{loc}: overlay holds "..#t.." slots but enUS has "'
         f'..#keys.." keys — regenerate the overlays (a nil in the LAST slot also '
         f'truncates #, so every slot must be held)")'],
        check=True)

    state = json.load(open(STATE)) if os.path.exists(STATE) else {}
    state[loc] = {k: manifest[k] for k in existing}
    json.dump(state, open(STATE, "w"), indent=2, sort_keys=True)

    print(f"{loc}: applied={len(payload)} pruned={pruned} total={len(existing)} "
          f"still-missing={len(missing)}")
    print(f"{loc}: remember to run tools/i18n/gen_all_caches.sh (serially) when all merges are done")


if __name__ == "__main__":
    main()
