-- The export -> wipe -> import cycle must preserve spec-specific bar entries.
-- Without _quiBundledGlobals on the QUI1 export, db.global.ncdm.specTrackerSpells
-- gets dropped on the floor and the importing player ends up with an empty bar.
-- These invariants pin the survival of both halves: the container shell on
-- profile, and the per-spec entries on global.
return {
    {
        name = "container survives import on profile side",
        assert = function(sv, ctx)
            local containers = sv.QUI_DB
                and sv.QUI_DB.profiles
                and sv.QUI_DB.profiles.Default
                and sv.QUI_DB.profiles.Default.ncdm
                and sv.QUI_DB.profiles.Default.ncdm.containers
            return type(containers) == "table"
                and type(containers.customBar_test_roundtrip) == "table"
                and containers.customBar_test_roundtrip.specSpecific == true
        end,
    },
    {
        name = "per-spec entries survive import on global side",
        assert = function(sv, ctx)
            local byContainer = sv.QUI_DB
                and sv.QUI_DB.global
                and sv.QUI_DB.global.ncdm
                and sv.QUI_DB.global.ncdm.specTrackerSpells
                and sv.QUI_DB.global.ncdm.specTrackerSpells.customBar_test_roundtrip
            if type(byContainer) ~= "table" then return false end
            local list = byContainer["PRIEST-256"]
            if type(list) ~= "table" or #list ~= 3 then return false end
            local ids = {}
            for _, e in ipairs(list) do ids[e.id] = true end
            return ids[33206] and ids[47788] and ids[62618]
        end,
    },
    {
        name = "_schemaVersion stays at 32 after re-run",
        assert = function(sv, ctx)
            return sv.QUI_DB.profiles.Default._schemaVersion == 32
        end,
    },
}
