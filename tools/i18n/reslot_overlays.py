#!/usr/bin/env python3
"""Re-number the ten locale overlays onto the CURRENT core/locale/enUS.lua.

This is the answer to "I added (or removed) an English ns.L string and
tests/unit/locale_keyset_checksum_test.lua went red."

The overlays are POSITIONAL: `core/locale/<loc>.lua` is an array where slot N
holds the translation of enUS key N, and `core/locale/enUS.lua` is the ordered
key array that assigns those IDs. That is what makes them small -- no overlay
repeats the 5.7k English keys -- and it is also why editing ANY ns.L string
renumbers every slot after the insertion point. The `-- keyset:` line in each
file is the fingerprint of the key array its slots were written against; when
enUS moves and the overlays do not, the checksums stop matching and the gate
fires.

Nothing else in the tree can fix that:
  * tools/i18n/gen_all_caches.sh regenerates enUS.lua and the search cache but
    never writes an overlay;
  * tools/i18n/translate_delta.py can, but needs a translation API key, and no
    new translation is required here -- every string already exists, it just
    needs a different slot number;
  * tools/i18n/migrate_overlays_positional.py is the retired one-shot that
    parses the OLD keyed `["key"] = "value"` format, which no overlay is in
    any more.

So this tool exists. It preserves every translation by name:

    old enUS key array  (from a git ref, read-only)
        |  zip by index
    overlay slots  ->  {english key: translation}
        |  re-zip by name
    new enUS key array  (the working tree)  ->  new slots

Keys that no longer exist in enUS are dropped, with a warning naming them --
their UI string is gone, so there is no slot to hold them. Keys that are new
take a held `nil,` slot and render English until translated.

Safety, part 1 -- it cannot mis-zip. translate_delta.read_overlay() refuses to
interpret an overlay whose `-- keyset:` does not match the key array it is
being zipped against, so this cannot silently re-label translations by reading
committed files against the wrong generation. That check is the whole reason
the direction of this tool is "old array in, new array out" rather than "just
re-emit".

Safety, part 2 -- what the write phase does and does not guarantee. All ten
files are read, validated and RENDERED IN MEMORY before anything is written,
then staged as `<overlay>.reslot-tmp` beside their targets, then published with
os.replace(). Concretely:

  * every failure with a realistic chance of happening -- a wrongly numbered
    overlay, a missing file, a Lua subprocess, a permissions or disk error --
    lands in the read/render/stage phase and leaves all ten overlays UNTOUCHED;
  * each file is published by an atomic rename, so no overlay is ever observed
    half-written, truncated, or 0 bytes;
  * SIGINT is deferred across the ten renames, so ^C cannot tear the set.

NOT claimed: the ten renames are not a single transaction. A SIGKILL or machine
crash landing between two of them leaves every FILE whole but the SET
inconsistent -- some overlays on the new key array, some on the old. That state
is loud (tests/unit/locale_keyset_checksum_test.lua fails) and recoverable:

    git checkout -- core/locale/

A hard kill can also leave `core/locale/*.reslot-tmp` scratch files behind.
They are inert -- nothing loads them, they are not in QUI.toc -- and the
next run overwrites and consumes all ten, so they need no manual cleanup.

Usage:
  python3 tools/i18n/reslot_overlays.py                    # old array from HEAD
  python3 tools/i18n/reslot_overlays.py --ref beta         # from another ref
  python3 tools/i18n/reslot_overlays.py --old-enus F.lua   # from a file
  python3 tools/i18n/reslot_overlays.py --dry-run          # report, write nothing

Afterwards: lua5.1 tests/unit/locale_keyset_checksum_test.lua
            python3 tools/i18n/test_overlay_roundtrip.py
"""
import argparse
import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from translate_delta import (  # noqa: E402
    ENUS, LOCALES, keyset_checksum, overlay_bytes, overlay_keyset, overlay_path,
    read_enus_keys, read_overlay,
)

# Staging suffix for the write phase. Deliberately not tempfile.mkstemp: the
# staged file must live in the SAME directory as its target, or os.replace()
# could land on a different filesystem and stop being atomic.
TMP_SUFFIX = ".reslot-tmp"

# No new translation happens here, only a change of slot number, so the writer
# attribution stays the one that owns the format going forward.
GENERATOR = "tools/i18n/translate_delta.py"


def old_keys_from_ref(ref):
    """The enUS key array as of `ref`, without touching the working tree.

    `git show` writes to a temp file rather than the tree: this tool must never
    disturb the checkout it is repairing, and read_enus_keys() needs a real
    file to hand to Lua.
    """
    proc = subprocess.run(["git", "show", f"{ref}:{ENUS}"],
                          capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        raise SystemExit(f"git show {ref}:{ENUS} failed:\n{proc.stderr}")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as tf:
        tf.write(proc.stdout)
        path = tf.name
    try:
        return read_enus_keys(path)
    except SystemExit as err:
        raise SystemExit(
            f"could not read an enUS key array out of {ref}:{ENUS}.\n"
            f"  {err}\n"
            f"  If that ref predates the positional locale format its enUS.lua is a "
            f"keyed identity table, not ns.LocaleData.keys — point --ref at a newer "
            f"commit, or pass --old-enus with a copy of the array-shaped file the "
            f"committed overlays were numbered against.")
    finally:
        os.unlink(path)


def main():
    ap = argparse.ArgumentParser(
        description="Re-number the ten locale overlays onto the current enUS key array.")
    ap.add_argument("--ref", default="HEAD",
                    help="git ref to read the OLD enUS key array from (default HEAD)")
    ap.add_argument("--old-enus", metavar="PATH",
                    help="read the OLD key array from this file instead of a git ref")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would change, write nothing")
    args = ap.parse_args()

    new_keys = read_enus_keys()
    old_keys = (read_enus_keys(args.old_enus) if args.old_enus
                else old_keys_from_ref(args.ref))

    old_sum, new_sum = keyset_checksum(sorted(old_keys)), keyset_checksum(sorted(new_keys))
    source = args.old_enus or f"{args.ref}:{ENUS}"
    print(f"old key array: {len(old_keys)} keys, keyset {old_sum}  ({source})")
    print(f"new key array: {len(new_keys)} keys, keyset {new_sum}  ({ENUS})")

    if old_sum == new_sum:
        # Not an error: it is the answer to "is a re-slot what I need?". Writing
        # anyway would be a no-op at best, so say so and stop.
        print("\nThe two key arrays are identical — the overlays are already numbered "
              "correctly and there is nothing to re-slot.")
        print("If the checksum test is red, the overlays are stale for some other "
              "reason; check what `-- keyset:` they actually carry:")
        for loc in LOCALES:
            print(f"    {loc}: {overlay_keyset(loc) or '<absent>'}")
        return 0

    new_set, old_set = set(new_keys), set(old_keys)   # hoisted: rebuilding
    added = [k for k in new_keys if k not in old_set]  # old_set inside the
    removed = [k for k in old_keys if k not in new_set]  # comprehension is O(n^2)
    print(f"\nkeys added: {len(added)}   keys removed: {len(removed)}")
    for k in added[:10]:
        print(f"    + {k!r}")
    for k in removed[:10]:
        print(f"    - {k!r}")

    # PASS 1 -- read, validate, and RENDER all ten. Nothing touches the tree.
    #
    # Rendering here, not in the write loop, is deliberate. Everything that can
    # realistically fail -- an overlay numbered for the wrong key set, a Lua
    # subprocess, building the 5.7k-slot body -- happens before the first byte
    # is written, so those failures leave the checkout exactly as they found it.
    # It also drops the enUS key array from ten Lua loads to one: overlay_bytes
    # takes the array we already have.
    rendered = {}
    for loc in LOCALES:
        path = overlay_path(loc)
        if not os.path.exists(path):
            print(f"{loc}: MISSING {path} — QUI.toc lists all ten overlays",
                  file=sys.stderr)
            return 1

        # Refuses unless the overlay's own `-- keyset:` matches the OLD array,
        # i.e. unless its slots really are numbered the way we are about to
        # read them. This is what makes a re-slot safe to run unattended.
        table = read_overlay(loc, old_keys)

        dropped = sorted(k for k in table if k not in new_set)
        if dropped:
            print(f"{loc}: dropping {len(dropped)} translation(s) whose English key is "
                  f"gone from enUS:", file=sys.stderr)
            for k in dropped[:10]:
                print(f"    {k!r}", file=sys.stderr)
            if len(dropped) > 10:
                print(f"    ... and {len(dropped) - 10} more", file=sys.stderr)

        kept = {k: v for k, v in table.items() if k in new_set}
        rendered[loc] = (overlay_bytes(loc, kept, GENERATOR, keys=new_keys),
                         len(kept), len(dropped))
        print(f"{loc}: read {len(kept)} translated, {len(dropped)} dropped, "
              f"{len(new_keys) - len(kept)} will hold nil")

    if args.dry_run:
        print(f"\nDRY RUN — nothing written. All ten read and rendered cleanly "
              f"against keyset {old_sum}.")
        return 0

    # PASS 2a -- stage every file next to its target. Still nothing replaced:
    # a failure here (permissions, ENOSPC, ^C) unlinks the staged files and
    # leaves all ten overlays untouched.
    staged = []
    try:
        for loc in LOCALES:
            tmp = overlay_path(loc) + TMP_SUFFIX
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(rendered[loc][0])
                fh.flush()
                os.fsync(fh.fileno())
            staged.append((loc, tmp))
    except BaseException as err:            # BaseException: KeyboardInterrupt too
        for _, tmp in staged:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        try:
            os.unlink(overlay_path(LOCALES[len(staged)]) + TMP_SUFFIX)
        except (OSError, IndexError):
            pass
        print(f"\nstaging failed before any overlay was replaced: {err!r}",
              file=sys.stderr)
        print("All ten core/locale/<loc>.lua files are UNCHANGED. Nothing to undo.",
              file=sys.stderr)
        return 1

    # PASS 2b -- publish. Ten os.replace() calls, each atomic on POSIX and each
    # within one directory, so a file is never observed half-written and can
    # never be left 0 bytes.
    #
    # What this does NOT claim: the ten renames are not one transaction. SIGINT
    # is deferred across them so ^C cannot tear the set, but SIGKILL or a
    # crash landing between two renames would leave some overlays converted and
    # some not -- every file whole, the SET inconsistent. That state is loud
    # (the keyset test fails) and recoverable (git checkout -- core/locale/),
    # and the window is a handful of syscalls.
    interrupted = []
    previous = None
    try:
        previous = signal.signal(signal.SIGINT, lambda *a: interrupted.append(a))
    except ValueError:
        pass                                # not on the main thread; proceed
    try:
        for index, (loc, tmp) in enumerate(staged):
            try:
                os.replace(tmp, overlay_path(loc))
            except OSError as err:
                print(f"\n{loc}: replace failed after {index} of {len(staged)} "
                      f"overlays were published: {err}", file=sys.stderr)
                print("The tree is now INCONSISTENT: some overlays are on the new key "
                      "array, some on the old. Every individual file is intact.",
                      file=sys.stderr)
                print("Recover with:  git checkout -- core/locale/", file=sys.stderr)
                for rest_loc, rest_tmp in staged[index:]:
                    try:
                        os.unlink(rest_tmp)
                    except OSError:
                        pass
                return 1
    finally:
        if previous is not None:
            signal.signal(signal.SIGINT, previous)

    for loc in LOCALES:
        _, kept_n, dropped_n = rendered[loc]
        print(f"{loc}: re-slotted {kept_n} translated / {len(new_keys)} total "
              f"({len(new_keys) - kept_n} held nil slot(s), {dropped_n} dropped)")

    if interrupted:
        print("\n(^C received during the publish phase; it was deferred so the ten "
              "renames could finish. All overlays are on the new key array.)",
              file=sys.stderr)

    print("\nNow verify:  lua5.1 tests/unit/locale_keyset_checksum_test.lua"
          "  &&  python3 tools/i18n/test_overlay_roundtrip.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
