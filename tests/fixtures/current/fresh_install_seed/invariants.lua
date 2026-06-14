-- Asserts the new-profile Starter Profile seed actually landed on a fresh install.
-- These read distinctive seed values that differ from core/defaults.lua, so
-- they fail loudly if OnNewProfile stops firing or the seed is wired to the
-- wrong AceDB instance (the original bug).

return {
    {
        name = "themePreset seeded to Starter Profile value (not legacy default)",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            -- seed = "Classic Mint"; core/defaults.lua = "Horde"
            return p.themePreset == "Classic Mint"
        end,
    },
    {
        name = "profile carries seed payload, not a bare default profile",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            -- A non-seeded fresh profile strips to near-empty (only migration
            -- stamps survive). The seed leaves many genuine setting subtrees.
            local n = 0
            for k in pairs(p) do
                if type(k) ~= "string" or k:sub(1, 1) ~= "_" then n = n + 1 end
            end
            return n >= 20
        end,
    },
    {
        name = "_schemaVersion stamped at current value after seed",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default._schemaVersion == 46
        end,
    },
}
