# v32_third_party_anchor_aliases

Pins v33 RemapThirdPartyAnchorAliases. The third-party integrations
(BigWigs, DandersFrames, AbilityTimeline) previously built their
"Anchor To" dropdown from a per-integration flat list with four legacy
alias values that aren't in the canonical anchor-target registry:

- `essential`  → `cdmEssential`
- `utility`    → `cdmUtility`
- `primary`    → `primaryPower`
- `secondary`  → `secondaryPower`

Each integration's `GetAnchorFrame` had matching legacy resolver arms,
so the saved values worked at runtime — but when the integrations were
moved onto the same registry-driven categorized + searchable dropdown
the rest of QUI's movers use, those four alias values weren't in the
registry and would have shown up as unknown in the dropdown.

The migration covers all three integration namespaces:
`db.profile.bigWigs.<key>.anchorTo`, `db.profile.dandersFrames.<key>.anchorTo`,
`db.profile.abilityTimeline.<key>.anchorTo`. Values that are already
canonical or that have nothing to do with the alias map (e.g.
`playerFrame`, `disabled`, `cdmUtility`) must pass through unchanged.
