# Profile Regression Tests

Headless test harness for the QUI profile lifecycle (load, migrate, export,
import, save). Runs under stock Lua 5.4 with no game dependency.

## Quick start

```sh
# Run all fixtures
lua tools/test_profiles.lua

# Run only fixtures matching a pattern
lua tools/test_profiles.lua --only edge/

# List fixtures without running
lua tools/test_profiles.lua --list
```

Exit codes: `0` all passed, `1` test failure, `2` harness error.

## Adding a fixture

A fixture is a directory under `tests/fixtures/<category>/<name>/` containing
at minimum a `seed.sv.lua`:

```lua
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            -- the profile shape you want to test
        },
    },
}
QUIDB = {}
```

Then generate the expected snapshot:

```sh
lua tools/test_profiles.lua --update --only <name>
```

Inspect the resulting `expected.sv.lua` to confirm it's reasonable, then run
without `--update` to verify it passes:

```sh
lua tools/test_profiles.lua --only <name>
```

Commit `seed.sv.lua` and `expected.sv.lua` together.

## Categories

- `current/` — profile shapes valid under today's defaults. `expected.sv.lua`
  should equal `seed.sv.lua` modulo strip-on-save behavior. If they ever
  diverge, current-build round-trip has regressed.
- `legacy/` — older `_schemaVersion` shapes. `expected.sv.lua` differs from
  `seed.sv.lua`; the diff documents what migrations did.
- `edge/` — hand-crafted fixtures pinning specific past bug shapes. Each
  one is a permanent regression test for one historical incident.

## When tests fail

The runner prints a path-rooted diff. Two paths:

1. **The diff is unintended** — code regression. Fix the code; rerun.
2. **The diff is intended** (e.g., you added a migration that intentionally
   reshapes data) — run with `--update` to regenerate the snapshot. **Read
   the diff before regenerating** — write the reason in the commit message.
   Tier-2 invariants (in `invariants.lua` files, see below) still fire after
   `--update`, so you can't accidentally re-introduce a known-bad shape.

## Optional fixture files

Beyond `seed.sv.lua` and `expected.sv.lua`, a fixture can include:

- `defaults.snapshot.lua` — pinned defaults table (replaces live
  `core/defaults.lua` for this fixture). Used for legacy fixtures where
  StampOldDefaults coverage matters.
- `invariants.lua` — list of named property assertions that fire in
  addition to the snapshot match. See Phase 3 fixtures for examples.
- `notes.md` — human context.
- `expected.post_migration.lua`, `expected.export.txt`,
  `expected.post_import.lua` — checkpoint snapshots for debugging
  pipeline-stage regressions.

## CI

`.github/workflows/profile-tests.yml` runs on every PR and push to main.
The local runner has zero CI-specific paths — same command, same output.

## Worked example: capture a bug report as a fixture

A user reports their auras teleport off-screen after upgrading. They send
their export string as `bug-report-456.txt`. To pin the regression
permanently:

```sh
# 1. Decode the report and inspect the shape
lua tools/decode_profile.lua bug-report-456.txt

# 2. Convert to a seed.sv.lua under edge/
lua tools/decode_profile.lua bug-report-456.txt \
    --to-seed-sv tests/fixtures/edge/issue-456-aura-teleport/seed.sv.lua

# 3. Generate the expected snapshot
lua tools/test_profiles.lua --update --only edge/issue-456-aura-teleport

# 4. Inspect the expected.sv.lua to confirm the migrations did the right thing
cat tests/fixtures/edge/issue-456-aura-teleport/expected.sv.lua

# 5. Verify it stays green
lua tools/test_profiles.lua --only edge/issue-456-aura-teleport

# 6. Commit
git add tests/fixtures/edge/issue-456-aura-teleport/
git commit -m "test: pin issue-456 (aura teleport) as edge fixture"
```

That single fixture is now a permanent test against any future regression
of the same shape.

## Adding an invariant

Open the fixture's `invariants.lua` (or create one). Add an entry:

```lua
{
    name = "no aura entry has off-screen offset",
    assert = function(sv, ctx)
        local fa = sv.QUI_DB.profiles.Default.frameAnchoring
        for _, e in pairs(fa or {}) do
            if math.abs(e.x or 0) > 5000 or math.abs(e.y or 0) > 5000 then
                return false
            end
        end
        return true
    end,
},
```

The runner runs invariants in addition to the snapshot match. If a future
`--update` regenerates the snapshot but the invariant catches the off-screen
shape, the fixture still fails — protecting against rubber-stamped snapshot
blesses.
