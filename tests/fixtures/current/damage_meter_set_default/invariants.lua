return {
    {
        name = "damageMeter shelf present in shipped defaults with all 11 keys",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            local sd = p and p._shippedDefaults and p._shippedDefaults.damageMeter
            if not sd then return false end
            for _, key in ipairs({"enabled","visibility","style","numberDisplay",
                                  "useClassColor","showBarIcons","barHeight",
                                  "barSpacing","textSize","windowAlpha","backgroundAlpha"}) do
                if sd[key] == nil then return false end
            end
            return true
        end,
    },
    {
        name = "damageMeter defaults match spec",
        assert = function(sv, ctx)
            local sd = sv.QUI_DB.profiles.Default._shippedDefaults.damageMeter
            return sd.enabled == false
               and sd.useClassColor == true and sd.showBarIcons == true
               and sd.barHeight == 25 and sd.barSpacing == 4
               and sd.textSize == 100 and sd.windowAlpha == 100 and sd.backgroundAlpha == 100
        end,
    },
    {
        name = "no migration triggered for additive damageMeter shelf",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default._schemaVersion == 35
        end,
    },
}
