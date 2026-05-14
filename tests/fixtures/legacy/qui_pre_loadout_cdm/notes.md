# qui_pre_loadout_cdm — pre-loadout shape fixture

**Pins:** The legacy 3-dim `_specProfilesByProfile[profileName][specID][containerKey]` shape that QUI used before the per-loadout CDM milestone (Phase 1: Storage, Events, and Infra Tests).

**Why it exists:** Catches regressions where a future change to CDM storage accidentally serializes the post-migration 4-dim shape (`[specID][loadoutID][containerKey]`) into SavedVariables before the read-time migration has run.

## What the harness does (and does NOT do)

`tools/test_profiles.lua` runs each fixture through:

1. Load `seed.sv.lua` into `_G.QUI_DB`
2. Build AceDB on `QUI_DB`
3. Run `QUI:BackwardsCompat()` (`db.profile` migrations from `core/migrations.lua`)
4. Export -> import round-trip through the `QUI1:` string format (`core/profile_io.lua`)
5. Strip defaults (simulate logout)
6. Snapshot the final `_G.QUI_DB`

The harness does NOT call `GetSpecLoadoutProfileStore`. That helper lives in `modules/cdm/cdm_containers.lua` and runs only at game-time, when CDM code accesses the store. Its in-place migration probe lifts pre-loadout data into `store[specID][0]` on first read.

Therefore: the migration LOGIC (existence of the helper, the legacy-keys probe, the lift sequence) is asserted by the **grep-style regression test** at `tests/cdm_spec_tracking_persistence_test.lua` — not by this fixture's invariants.

This fixture asserts the SavedVariables shape that the migration must recognize is round-tripped losslessly by the harness.

## What `expected.sv.lua` looks like

For the `db.char` section: IDENTICAL to `seed.sv.lua`. The harness does not transform it.

For the `db.profile` section: AceDB defaults are filled in (during build) and then stripped on logout. Whether `_schemaVersion` appears in the expected output depends on `core/migrations.lua`'s current `CURRENT_SCHEMA_VERSION`; the milestone's design explicitly does NOT bump it (the new storage is in `db.char`, outside `Migrations.Run` scope).

If you regenerate `expected.sv.lua` via `--update` and the diff shows changes to `_schemaVersion` or other profile-side fields, that's AceDB / `core/migrations.lua` evolving — verify the change is intentional and unrelated to the loadout work.

## Spell IDs in the seed

The `essential.ownedSpells` list contains three Affliction Warlock cooldowns (`686` Shadow Bolt, `980` Agony, `48181` Haunt). These are placeholder values purely to give the shape something non-empty; the actual spell IDs don't matter for the shape regression.

Spec ID `65` = Affliction Warlock. Picked arbitrarily; any positive integer works.

## What this fixture does NOT cover

- **Post-migration shape:** The 4-dim post-migration shape (`store[specID][0]`) is not asserted here. That's a game-time in-memory state, not a SavedVariables state.
- **Live API integration:** `GetLastSelectedSavedConfigID` / `C_ClassTalents` calls are not exercised. The fixture is pure data.
- **Event dispatch:** `TRAIT_CONFIG_UPDATED` / `ACTIVE_COMBAT_CONFIG_CHANGED` / `TRAIT_CONFIG_LIST_UPDATED` flows are not exercised. The fixture is pure data.

All three uncovered surfaces are asserted by the grep tests in `tests/cdm_spec_tracking_persistence_test.lua`.

## Related

- **SPEC:** `.planning/phases/01-storage-events-and-infra-tests/01-SPEC.md` — LDTS-02 requirement
- **Migration code:** `modules/cdm/cdm_containers.lua` — `GetSpecLoadoutProfileStore` (read-time migration probe)
- **Grep test:** `tests/cdm_spec_tracking_persistence_test.lua` — assertions for migration logic existence
