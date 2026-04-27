# v31_pre_v32_consolidation

A profile at _schemaVersion = 31 with:
- legacy customTrackers.bars[] (migrated to ncdm.containers[customBar_*] by v32a)
- orphan partyTracker subtree inside quiGroupFrames.party and .raid (cleaned by v32b)
- ncdm._lastSpecID (used by v32c/v32d for spec stamping)

Two bars are seeded:
- `test_bar_1`: plain bar with offsetX/offsetY, no spec specificity. Exercises
  transform (a) position translation and transform (c) row1 synthesis.
- `test_bar_spec`: spec-specific bar (`specSpecificSpells = true`) with entries
  stored directly on the bar (drag-drop-bug path). Exercises transforms (a), (c),
  and (d). QUIDB.specTrackerSpells["test_bar_spec"]["250"] is also present so
  transform (c)'s global spec-port path runs as well.

Expected post-migration state:
- customTrackers.bars survives (migration is non-destructive per spec)
- partyTracker absent from quiGroupFrames.party and quiGroupFrames.raid (v32b)
- ncdm.containers.customBar_test_bar_1 and customBar_test_bar_spec populated (v32a)
- each migrated container has row1 synthesised (v32c), anchorTo = "disabled"
- customBar_test_bar_spec.specSpecific = true, _sourceSpecID = 250 (v32d)
- customBar_test_bar_spec.entries cleared; entries moved to per-spec global storage (v32d)
- _schemaVersion = 32

Reference: core/migrations.lua lines 108-131 (v32 documentation), plus
the v32 migration code below it.
