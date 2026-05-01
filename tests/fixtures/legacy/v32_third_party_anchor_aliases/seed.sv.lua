-- Profile at _schemaVersion = 32 with the four legacy "Anchor To" alias
-- values that BigWigs / DandersFrames / AbilityTimeline historically wrote
-- when their per-integration BuildAnchorOptions emitted a flat dropdown.
-- v33's RemapThirdPartyAnchorAliases must rewrite these to the canonical
-- registry keys (cdmEssential / cdmUtility / primaryPower / secondaryPower)
-- so the new shared categorized + searchable widget can render them.
-- Values that are already canonical, or values that have nothing to do
-- with the alias map (e.g. playerFrame, disabled), must pass through
-- unchanged.
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 32,
            cdm = { engine = "owned" },

            bigWigs = {
                normal     = { anchorTo = "essential", enabled = true },
                emphasized = { anchorTo = "primary",   enabled = true },
            },
            dandersFrames = {
                party   = { anchorTo = "utility",     enabled = true },
                raid    = { anchorTo = "secondary",   enabled = true },
                pinned1 = { anchorTo = "playerFrame", enabled = true },  -- already canonical
                pinned2 = { anchorTo = "disabled",    enabled = false }, -- not in alias map
            },
            abilityTimeline = {
                timeline = { anchorTo = "essential", enabled = true },
                bigIcon  = { anchorTo = "cdmUtility", enabled = true },  -- already canonical
            },
        },
    },
}
QUIDB = {}
