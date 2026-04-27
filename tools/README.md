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

## test_profiles.lua

Headless QUI profile regression test runner. Walks `tests/fixtures/`, runs
the round-trip pipeline against each, snapshot-diffs results.

```sh
# Run all fixtures
lua tools/test_profiles.lua

# Run only fixtures matching a pattern
lua tools/test_profiles.lua --only edge/

# List discovered fixtures
lua tools/test_profiles.lua --list

# Regenerate snapshots after intentional changes
lua tools/test_profiles.lua --update --only legacy/v22_pre_ncdm_containers
```

See `tests/README.md` for the full fixture authoring guide. Exit codes:
`0` all passed, `1` test failure, `2` harness error.

## _addon_env.lua

Internal: shared WoW-stub + module loader used by `decode_profile.lua` and
`test_profiles.lua`. Not meant to be invoked directly. Exposes:

- `env.LoadLibs()` — loads bundled libraries (LibStub, AceDB, etc.)
- `env.LoadCore()` — loads the QUI core slice (utils, defaults, migrations,
  compat, profile_io)
- `env.LoadHarness(seed)` — combines the above with a seeded `_G.QUI_DB`,
  returns a table with `db`, `QUI`, `QUICore`, `ns`

When WoW adds a new global the libs reach for, add the stub to `_addon_env.lua`
and both tools pick it up automatically.

## decode_profile.lua — `--to-seed-sv` flag

Convert any `QUI1:` import string into a fixture-shaped `seed.sv.lua`:

```sh
lua tools/decode_profile.lua user-bug-report.txt \
    --to-seed-sv tests/fixtures/edge/issue-123/seed.sv.lua
```

Then run with `--update`:

```sh
lua tools/test_profiles.lua --update --only edge/issue-123
```

The user's reported bug shape is now a permanent regression test.
