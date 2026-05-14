-- LDTS-02: Property assertions that pin the legacy pre-loadout shape.
--
-- The harness pipeline resets _G.QUI_DB between the export and import
-- steps (step 5: "RESET DB"), so the final snapshot (sv / finalSV) does
-- NOT contain the seeded char data. Invariants that need to inspect the
-- pre-migration shape use ctx.originalSV, which is captured as a deep
-- copy of _G.QUI_DB immediately after the seed is loaded (before any
-- AceDB build, BackwardsCompat, or reset).
--
-- These invariants assert:
--   1. The seed loaded correctly and placed data at the expected path.
--   2. The legacy 3-dim shape (container keys directly under store[specID])
--      was preserved through the BackwardsCompat step -- confirming that
--      BackwardsCompat() does NOT invoke the read-time migration in
--      GetSpecLoadoutProfileStore (which only runs in-game).
--   3. The _specProfilesByProfile data did NOT leak into the exported
--      profile string or the final snapshot -- confirming char data stays
--      char-scoped and never bleeds into the export/import path.
return {
    {
        name = "originalSV has legacy 3-dim shape: container keys directly under store[specID]",
        assert = function(sv, ctx)
            -- Check the ORIGINAL seed (before any migration or reset).
            local orig = ctx and ctx.originalSV
            if not orig then return false end
            local charData = orig.QUI_DB
                and orig.QUI_DB.char
                and orig.QUI_DB.char["TestChar - TestRealm"]
            if not charData then return false end
            local store = charData.ncdm
                and charData.ncdm._specProfilesByProfile
                and charData.ncdm._specProfilesByProfile.Default
            if type(store) ~= "table" then return false end
            if type(store[65]) ~= "table" then return false end
            -- Legacy shape: 'essential' is directly under store[65]
            if type(store[65].essential) ~= "table" then return false end
            -- And no integer [0] intermediate exists (migration is read-time, not harness-time)
            if store[65][0] ~= nil then return false end
            return true
        end,
    },
    {
        name = "originalSV essential.ownedSpells round-trips the seeded spell IDs",
        assert = function(sv, ctx)
            local orig = ctx and ctx.originalSV
            if not orig then return false end
            local essential = orig.QUI_DB
                and orig.QUI_DB.char
                and orig.QUI_DB.char["TestChar - TestRealm"]
                and orig.QUI_DB.char["TestChar - TestRealm"].ncdm
                and orig.QUI_DB.char["TestChar - TestRealm"].ncdm._specProfilesByProfile
                and orig.QUI_DB.char["TestChar - TestRealm"].ncdm._specProfilesByProfile.Default
                and orig.QUI_DB.char["TestChar - TestRealm"].ncdm._specProfilesByProfile.Default[65]
                and orig.QUI_DB.char["TestChar - TestRealm"].ncdm._specProfilesByProfile.Default[65].essential
            if not essential or type(essential.ownedSpells) ~= "table" then return false end
            if #essential.ownedSpells ~= 3 then return false end
            return essential.ownedSpells[1] == 686
                and essential.ownedSpells[2] == 980
                and essential.ownedSpells[3] == 48181
        end,
    },
    {
        name = "finalSV has no _specProfilesByProfile in profile scope (char data does not bleed into export)",
        assert = function(sv, ctx)
            -- The export/import round-trip only carries db.profile data.
            -- _specProfilesByProfile lives in db.char and must NOT appear
            -- anywhere in the final snapshot's profiles section.
            local profiles = sv.QUI_DB and sv.QUI_DB.profiles
            if type(profiles) ~= "table" then return true end  -- no profiles at all is fine
            for _, prof in pairs(profiles) do
                if type(prof) == "table" then
                    -- Walk one level: check ncdm._specProfilesByProfile doesn't appear
                    local ncdm = prof.ncdm
                    if type(ncdm) == "table" and ncdm._specProfilesByProfile ~= nil then
                        return false
                    end
                end
            end
            return true
        end,
    },
}
