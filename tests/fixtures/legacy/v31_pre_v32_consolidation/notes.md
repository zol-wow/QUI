# v31_pre_v32_consolidation

A profile at _schemaVersion = 31 with:
- legacy customTrackers.bars[] (migrated to ncdm.containers[customBar_*] by v32a)
- orphan partyTracker subtree inside quiGroupFrames.party and .raid (cleaned by v32b)
- ncdm._lastSpecID (used by v32c/v32d for spec stamping)
- three standalone ncdm.containers entries with the legacy 4-value containerType
  (cooldown / aura / auraBar) — exercises v32e shape/kind stamping across all
  three branches. The customBar branch of v32e is exercised on the
  customBar_test_bar_* containers transforms (a)/(c)/(d) synthesise above.

Two custom-tracker bars are seeded:
- `test_bar_1`: plain bar with offsetX/offsetY, no spec specificity. Exercises
  transform (a) position translation and transform (c) row1 synthesis.
- `test_bar_spec`: spec-specific bar (`specSpecificSpells = true`) with entries
  stored directly on the bar (drag-drop-bug path). Exercises transforms (a), (c),
  and (d). QUIDB.specTrackerSpells["test_bar_spec"]["250"] is also present so
  transform (c)'s global spec-port path runs as well.

Three standalone containers are seeded directly under ncdm.containers:
- `custom_cd` (containerType=cooldown): mixed entries (spell + item + trinket).
  Spell entry left without kind for the runtime classifier; non-spell entries
  stamped kind=cooldown. shape=icon.
- `custom_aura` (containerType=aura): spell + macro entries. Spell entries get
  kind=aura; macro gets kind=cooldown. shape=icon.
- `custom_bar` (containerType=auraBar): single spell entry stamped kind=aura.
  shape=bar.

Expected post-migration state:
- customTrackers.bars survives (migration is non-destructive per spec)
- partyTracker absent from quiGroupFrames.party and quiGroupFrames.raid (v32b)
- ncdm.containers.customBar_test_bar_1 and customBar_test_bar_spec populated (v32a)
- each migrated container has row1 synthesised (v32c), anchorTo = "disabled"
- customBar_test_bar_spec.specSpecific = true, _sourceSpecID = 250 (v32d)
- customBar_test_bar_spec.entries cleared; entries moved to per-spec global storage (v32d)
- every container in ncdm.containers gains a `shape` field (v32e)
- spell entries on aura/auraBar containers gain `kind = "aura"` (v32e)
- non-spell entries gain `kind = "cooldown"` (v32e)
- spell entries on cooldown / customBar containers retain no kind (runtime classifies)
- _schemaVersion = 32

Reference: core/migrations.lua lines 108-148 (v32 documentation), plus
the v32 migration code below it.
