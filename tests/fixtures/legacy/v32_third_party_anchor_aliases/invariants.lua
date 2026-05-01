-- v33 RemapThirdPartyAnchorAliases: rewrites legacy "Anchor To" alias
-- values stored on third-party integrations to canonical registry keys
-- so the unified categorized + searchable dropdown can render them.
-- Pre-existing canonical values and unrelated values must pass through.
return {
    {
        name = "_schemaVersion advanced past v33",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default._schemaVersion >= 33
        end,
    },
    {
        name = "BigWigs essential alias rewritten to cdmEssential",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.bigWigs and p.bigWigs.normal
                and p.bigWigs.normal.anchorTo == "cdmEssential"
        end,
    },
    {
        name = "BigWigs primary alias rewritten to primaryPower",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.bigWigs and p.bigWigs.emphasized
                and p.bigWigs.emphasized.anchorTo == "primaryPower"
        end,
    },
    {
        name = "DandersFrames utility alias rewritten to cdmUtility",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.dandersFrames and p.dandersFrames.party
                and p.dandersFrames.party.anchorTo == "cdmUtility"
        end,
    },
    {
        name = "DandersFrames secondary alias rewritten to secondaryPower",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.dandersFrames and p.dandersFrames.raid
                and p.dandersFrames.raid.anchorTo == "secondaryPower"
        end,
    },
    {
        name = "DandersFrames canonical playerFrame value preserved",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.dandersFrames and p.dandersFrames.pinned1
                and p.dandersFrames.pinned1.anchorTo == "playerFrame"
        end,
    },
    -- pinned2 is seeded with anchorTo = "disabled" + enabled = false to
    -- prove the migration doesn't trip over default-shaped entries; AceDB
    -- strips those on save so we don't assert anything about the post-save
    -- shape here. THIRD_PARTY_ANCHOR_ALIAS_MAP not having a "disabled" key
    -- already guarantees there's no unintended mapping.
    {
        name = "AbilityTimeline essential alias rewritten to cdmEssential",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.abilityTimeline and p.abilityTimeline.timeline
                and p.abilityTimeline.timeline.anchorTo == "cdmEssential"
        end,
    },
    {
        name = "AbilityTimeline already-canonical cdmUtility preserved",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.abilityTimeline and p.abilityTimeline.bigIcon
                and p.abilityTimeline.bigIcon.anchorTo == "cdmUtility"
        end,
    },
}
