# Tools

Standalone Lua scripts for development and debugging. None of these are
loaded by the addon at runtime — they're plain Lua intended to be run from
the command line.

Run each from the **repository root** so bundled libs (`libs/`) resolve.

## generate_search_cache.lua

Regenerates `options/search_cache.lua` from in-source settings definitions.
Run after adding or renaming user-visible settings.

```sh
lua tools/generate_search_cache.lua
```

## decode_profile.lua

Decodes and inspects a QUI profile import string without loading the addon
in WoW. Useful when triaging profile-import bug reports — paste the user's
import string into a file and read what's actually inside.

Supports all three QUI string formats:

| Prefix | Source                                         |
|--------|------------------------------------------------|
| `QUI1:` | Full profile export (`db.profile` only)       |
| `QCT1:` | All tracker bars export (with `db.global` spec entries) |
| `QCB1:` | Single tracker bar export                     |

```sh
# decode a string saved to a file
lua tools/decode_profile.lua path/to/import.txt

# read from stdin
echo "QUI1:..." | lua tools/decode_profile.lua -

# also write a depth-bounded full payload dump alongside the input
lua tools/decode_profile.lua path/to/import.txt --full
```

The default output highlights the parts most often relevant to support
issues:

- detected prefix and size
- top-level keys
- schema / spec metadata (`_schemaVersion`, `ncdm._lastSpecID`)
- legacy `customTrackers.bars[]` with per-entry inspection
- V2 `ncdm.containers["customBar_*"]` with spec stamps and entries

For `QCT1:` / `QCB1:`, prints the embedded bar(s) and any `specEntries`
table that came along.

`--full` additionally writes a `<input>.dump.txt` with a depth-8
pretty-print of the entire deserialized payload — handy for grepping when
a setting is suspected of being mis-stored.
