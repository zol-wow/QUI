return {
    {
        name = "skinDamageMeter present in shipped defaults",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            local sd = p and p._shippedDefaults
            return sd and sd.general and sd.general.skinDamageMeter == true
        end,
    },
    {
        name = "no migration triggered for additive skinDamageMeter key",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            -- Match basic_fresh's pinned schema version. Bump in lockstep when
            -- CURRENT_SCHEMA_VERSION changes. See tests/fixtures/current/basic_fresh/invariants.lua line 10.
            return p._schemaVersion == 35
        end,
    },
}
