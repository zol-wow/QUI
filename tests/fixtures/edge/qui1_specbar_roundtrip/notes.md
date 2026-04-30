# qui1_specbar_roundtrip

Locks in the QUI1 profile-string export/import bundling for spec-specific
custom-tracker bars. The harness performs a full export -> wipe-globals ->
import cycle on every fixture (test_profiles.lua steps 4-6); this fixture
seeds:

- A V2-shape spec-specific custom-tracker container at
  `db.profile.ncdm.containers.customBar_test_roundtrip` with `specSpecific = true`
  and empty `entries` (post-v32(d) shape).
- Per-spec entries at
  `db.global.ncdm.specTrackerSpells.customBar_test_roundtrip["PRIEST-256"]`
  with real retail Discipline Priest spellIDs that runtime would resolve.

The expected.sv.lua should show those entries surviving the round-trip
unchanged. If they go missing in expected, it means the export side
dropped `db.global.ncdm.specTrackerSpells` and the importing player would
get an empty bar — the regression this fixture exists to catch.

Profile is already at `_schemaVersion = 32`, so migrations are a no-op.
The test is purely on the export/import bundling path.
