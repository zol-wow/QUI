#!/usr/bin/env python3
"""ONE-SHOT migration: reformat the ten committed locale overlays from a keyed
table (`["English key"] = "translation",`) to a POSITIONAL array (value N
belongs to key N of the sorted enUS key set).

Why this exists instead of a regeneration step: the overlays cannot be
regenerated. `tools/i18n/gen_all_caches.sh` only runs `extract_strings.lua`
(core/locale/enUS.lua) and `generate_search_cache.lua` -- it never writes the
ten overlays. Those are written by `tools/i18n/translate_delta.py`, which
requires a logged-in Codex session that is not available in CI (and is not
needed here: no new translation is happening, only a container
change). So the only way to flip their format is to parse the translations
that are ALREADY committed and re-emit them through the new writer.

This script is meant to run exactly once, immediately after Task 3 flips
`overlay_source` to positional output and rewrites `extract_strings.lua` to
emit `ns.LocaleData.keys` (an ordered array) instead of the current
`ns.LocaleData.enUS` (a keyed identity table). After that landing,
`translate_delta.py` owns the format going forward -- real translation runs
read/write positional overlays directly and this script is never invoked
again.

Ordering matters when this actually runs (see Task 3 Step 8): `enUS.lua` must
already be in the NEW array format before this script runs, because the array
IS the ID assignment this script maps every translation onto.

Usage (NOT run by this task -- see the plan's Task 2 Step 7):
  python3 tools/i18n/migrate_overlays_positional.py
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lua_literal import unescape_lua_string  # noqa: E402
from translate_delta import (  # noqa: E402
    ENUS, LOCALES, overlay_path, overlay_source, read_enus_keys,
)

# Same pair regex tools/i18n/test_overlay_roundtrip.py already uses to parse a
# committed (keyed) overlay -- that test proves this regex round-trips the
# committed files byte for byte, which is exactly the parse this migration
# depends on to not lose or corrupt a translation.
PAIR = re.compile(r'\["((?:\\.|[^"])*)"\]\s*=\s*"((?:\\.|[^"])*)"')

# The banner text every committed overlay carries and that
# test_overlay_roundtrip.py regenerates against, unchanged: no new
# translation happened here, only a change of container, so the writer
# attribution stays the one that owns the format going forward.
GENERATOR = "tools/i18n/translate_delta.py"


# read_enus_keys() -- the ordered `ns.LocaleData.keys` array, loaded through
# real Lua rather than regexed -- lives in translate_delta.py, the module that
# owns the overlay format, and is imported above for this script's own use. It
# used to be RE-EXPORTED from here because tools/i18n/stamp_enus_keyset.py
# imported it from this module; that tool now imports it from translate_delta
# directly, so no live tooling depends on this spent one-shot any more. One
# implementation: a second copy could disagree about the ID assignment, which
# is the exact corruption this migration exists to avoid.


def parse_overlay(loc):
    """Parse a committed (still-keyed) overlay's `["key"] = "value"` pairs.

    A parse that finds NO pairs is a hard error, not an empty table. The
    overlays this script converts TO have no `["key"] = "value"` rows at all,
    so re-running the spent migration against them would yield `existing = {}`,
    map every enUS key to None, and write ten overlays that are nothing but
    held `nil,` slots -- while printing a cheerful "migrated 0 translated /
    N total" for each. Every translation in the tree, silently blanked.
    Refusing here means the first locale stops the run before anything is
    written.
    """
    path = overlay_path(loc)
    text = Path(path).read_text(encoding="utf-8")
    table = {}
    for m in PAIR.finditer(text):
        table[unescape_lua_string(m.group(1))] = unescape_lua_string(m.group(2))
    if not table:
        raise SystemExit(
            f'{path}: no `["key"] = "value"` pairs found -- this overlay is ALREADY '
            f"positional and this one-shot migration is spent. Refusing to run: it "
            f"would rewrite all ten overlays as nothing but held `nil,` slots and "
            f"discard every committed translation.\n"
            f"  To re-number the overlays onto a changed enUS key set, use "
            f"tools/i18n/reslot_overlays.py instead.")
    return table


def migrate_one(loc, enus_keys, enus_set):
    existing = parse_overlay(loc)

    orphans = sorted(k for k in existing if k not in enus_set)
    if orphans:
        raise SystemExit(
            f"{loc}: {len(orphans)} key(s) in the committed overlay are absent from enUS -- "
            f"the overlay is NEWER than enUS and the ID mapping would be wrong. Refusing to "
            f"migrate.\n  first orphan: {orphans[0]!r}\n"
            f"  (regenerate enUS first, or drop the stale key from the overlay by hand)")

    # Positional: one slot per enUS key, in enUS order. A key with no overlay
    # entry maps to None, which the positional overlay_source emits as a held
    # `nil,` slot -- dropping it instead would shift every later ID.
    positional = {k: existing.get(k) for k in enus_keys}

    Path(overlay_path(loc)).write_text(
        overlay_source(loc, positional, GENERATOR), encoding="utf-8")

    held = sum(1 for k in enus_keys if k not in existing)
    print(f"{loc}: migrated {len(existing)} translated / {len(enus_keys)} total "
          f"({held} held nil slot(s))")


def main():
    enus_keys = read_enus_keys()
    enus_set = set(enus_keys)
    if len(enus_set) != len(enus_keys):
        raise SystemExit(f"{ENUS}: ns.LocaleData.keys has duplicate entries -- refusing to "
                          f"migrate onto an ambiguous ID assignment")
    for loc in LOCALES:
        migrate_one(loc, enus_keys, enus_set)


if __name__ == "__main__":
    main()
