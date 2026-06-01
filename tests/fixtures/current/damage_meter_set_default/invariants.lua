return {
    {
        name = "damageMeter.native shelf present in shipped defaults with stable top-level keys",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            local n = p and p._shippedDefaults and p._shippedDefaults.damageMeter and p._shippedDefaults.damageMeter.native
            if not n then return false end
            for _, key in ipairs({"enabled","visibility","refreshRateCombat","refreshRateIdle",
                                  "showPinnedSelf","showHoverTooltip","breakdownAnchor",
                                  "appearance","windows"}) do
                if n[key] == nil then return false end
            end
            return true
        end,
    },
    {
        name = "damageMeter.native defaults match spec",
        assert = function(sv, ctx)
            local n = sv.QUI_DB.profiles.Default._shippedDefaults.damageMeter.native
            local g = n.appearance and n.appearance.global
            return n.enabled == true
               and n.visibility == "always"
               and n.refreshRateCombat == 0.5
               and n.refreshRateIdle == 2.0
               and g and g.barHeight == 18 and g.barSpacing == 2
               and g.useClassColor == true and g.numberFormat == "compact"
        end,
    },
    {
        name = "schema migrated to current version",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default._schemaVersion == 40
        end,
    },
}
