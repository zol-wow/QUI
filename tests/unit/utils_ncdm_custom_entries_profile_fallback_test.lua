function LibStub() return nil end

local ns = {}
assert(loadfile("core/utils.lua"))("QUI", ns)

local profileEntries = {
    enabled = true,
    placement = "before",
    entries = { { type = "spell", id = 12345 } },
}
local core = {
    db = {
        char = {},
        profile = {
            ncdm = {
                customEntriesSpecSpecific = false,
                essential = { customEntries = profileEntries },
            },
        },
        GetCurrentProfile = function() return "Imported" end,
    },
}

ns.Helpers.GetCore = function() return core end

local result = ns.Helpers.GetNCDMCustomEntries("essential")
assert(result ~= profileEntries, "profile custom entries should be cloned into character storage")
assert(result.enabled == true and result.placement == "before",
    "profile custom-entry settings should seed a missing per-profile bucket")
assert(result.entries[1] and result.entries[1].id == 12345,
    "profile custom entries should survive first access on an imported profile")

print("utils_ncdm_custom_entries_profile_fallback_test: all checks passed")
