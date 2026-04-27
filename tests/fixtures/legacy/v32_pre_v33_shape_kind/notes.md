# v32_pre_v33_shape_kind

A profile at _schemaVersion = 32 with five custom containers, one for each
relevant pre-v33 containerType plus a per-spec storage case. Pins the v33
MigrateContainerShapeAndEntryKind transform.

Containers seeded:
- `custom_cd` (containerType="cooldown") — icon shape, mixed entries.
- `custom_aura` (containerType="aura") — icon shape, all-spell + macro entry.
- `custom_bar` (containerType="auraBar") — bar shape, single spell entry.
- `customBar_legacy_one` (containerType="customBar") — legacy-migrated bar,
  spell + item entries directly on the container.
- `customBar_specced` (containerType="customBar", specSpecific=true) —
  empty container.entries; live entries live in the global per-spec store.

Expected post-migration state:
- All containers gain `shape`. Mapping: cooldown/aura/customBar → "icon",
  auraBar → "bar".
- Spell entries on previously-aura containers (aura/auraBar) gain
  `kind = "aura"`.
- Non-spell entries (item/trinket/slot/macro) gain `kind = "cooldown"`
  on all containers.
- Spell entries on previously-cooldown / previously-customBar containers
  are left without `kind` so the runtime classifier handles them.
- Per-spec entry storage at `db.global.ncdm.specTrackerSpells` receives
  the same stamping logic, with the source containerType determining
  whether spell entries get kind=aura.
- `_schemaVersion = 33`.
- Legacy `containerType` field is preserved (tombstone for one cycle so
  any reader not yet migrated to shape/kind keeps working).

Reference: core/migrations.lua MigrateContainerShapeAndEntryKind.
