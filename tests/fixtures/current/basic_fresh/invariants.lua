-- Schema-wide invariants applicable to any profile, kept on basic_fresh
-- as a no-customization baseline. Add new invariants here when a new bug
-- class is discovered that should never recur.

return {
    {
        name = "_schemaVersion is at current value",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p._schemaVersion == 33  -- bump when CURRENT_SCHEMA_VERSION changes
        end,
    },
    {
        name = "_migrationBackup is absent from export string",
        assert = function(sv, ctx)
            return not ctx.exportString:find("_migrationBackup", 1, true)
        end,
    },
    {
        name = "no customTrackers.bars after v32",
        assert = function(sv, ctx)
            local p = sv.QUI_DB.profiles.Default
            return p.customTrackers == nil or p.customTrackers.bars == nil
        end,
    },
    {
        name = "no partyTracker subtree",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default.partyTracker == nil
        end,
    },
    {
        name = "no half-corner anchor entries (v24/v25 bug shape)",
        assert = function(sv, ctx)
            local fa = sv.QUI_DB.profiles.Default.frameAnchoring
            if type(fa) ~= "table" then return true end
            for _, e in pairs(fa) do
                if type(e) == "table"
                   and e.parent ~= "disabled"
                   and type(e.relative) == "string"
                   and e.relative:match("^TOP")
                   and ((e.x or 0) ~= 0 or (e.y or 0) ~= 0)
                   and e.point ~= e.relative then
                    return false
                end
            end
            return true
        end,
    },
}
