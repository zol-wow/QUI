return {
    {
        name = "shipped defaults snapshot stored globally",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            local sd = sv.QUI_DB.global and sv.QUI_DB.global._shippedProfileDefaults
            return p and p._shippedDefaults == nil
                and sd and sd.general and sd.general.skinDamageMeter == true
        end,
    },
    {
        name = "no migration triggered for additive skinDamageMeter key",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            -- Match basic_fresh's pinned schema version. Bump in lockstep when
            -- CURRENT_SCHEMA_VERSION changes. See tests/fixtures/current/basic_fresh/invariants.lua line 10.
            return p._schemaVersion == 40
        end,
    },
}
