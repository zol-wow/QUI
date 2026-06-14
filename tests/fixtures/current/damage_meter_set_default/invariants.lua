return {
    {
        name = "shipped defaults snapshot stored globally",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            local n = sv.QUI_DB.global
                and sv.QUI_DB.global._shippedProfileDefaults
                and sv.QUI_DB.global._shippedProfileDefaults.damageMeter
                and sv.QUI_DB.global._shippedProfileDefaults.damageMeter.native
            if not p or p._shippedDefaults ~= nil or not n then return false end
            for _, key in ipairs({"enabled","visibility","refreshRateCombat","refreshRateIdle",
                                  "showPinnedSelf","showHoverTooltip","breakdownAnchor",
                                  "appearance","windows"}) do
                if n[key] == nil then return false end
            end
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
            return sv.QUI_DB.profiles.Default._schemaVersion == 46
        end,
    },
}
