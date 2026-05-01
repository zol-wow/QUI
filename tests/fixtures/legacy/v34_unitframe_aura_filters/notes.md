# v34_unitframe_aura_filters

Pins v34 MigrateUnitFrameAuraFilters. Replaces the per-unit
`onlyMyDebuffs` checkbox with a structured `debuffFilter` table whose
`PLAYER` modifier carries the legacy intent.

Migration rules:
  - `onlyMyDebuffs == true`  → `debuffFilter.modifiers.PLAYER = true`
  - `onlyMyDebuffs == false` → no PLAYER modifier set
  - `onlyMyDebuffs` is removed from every unit's auras table afterwards.

The full `buffFilter`/`debuffFilter` table shells (with all flags set to
false and `exclusive` absent) are stamped at runtime by
`EnsureAuraSettings`. The migration itself only writes the minimum it
needs to preserve old behavior; everything else fills in via the
runtime ensure-helper. This fixture uses the `expected.post_migration.lua`
checkpoint (compared against `db.profile` only) so we can pin migration
deltas precisely without hand-writing the full ~6000-line SV snapshot.
The full-SV `expected.sv.lua` is regenerated via `--update` in Task 3
after the migration is in place.
