# damage_meter_set_default

Pinning the additive `damageMeter` shadow shelf introduced for Stage 2 of the
Damage Meter roadmap. QUI options page writes here; the sync layer in
`skinning/gameplay/damage_meter.lua` pushes values through to Blizzard's
`DamageMeterMixin` setters.

Purely additive — AceDB fills the shelf on first load; no migration required.

If a future change makes the shelf non-additive (renamed, removed, key
renamed), update both this fixture and add a matching `legacy/` fixture
pinning the pre-state.
