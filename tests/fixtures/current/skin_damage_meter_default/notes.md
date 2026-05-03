# skin_damage_meter_default

Pinning the additive `general.skinDamageMeter = true` default introduced for
the Blizzard Damage Meter skin (`skinning/gameplay/damage_meter.lua`).

Purely additive — AceDB fills the key on first load; no migration required.

If a future change makes `skinDamageMeter` non-additive (renamed, default
flipped, moved to a different shelf), update both this fixture and add a
matching `legacy/` fixture pinning the pre-state.
