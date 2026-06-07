-- tests/unit/encounter_journal_dynamic_text_test.lua
-- Run: lua tests/unit/encounter_journal_dynamic_text_test.lua
--
-- Encounter Journal ability headers and bullet rows are created after the
-- top-level journal skin pass. They must be styled when Blizzard refreshes
-- section content, not only when the addon loads.

-- luacheck: globals _G C_Timer hooksecurefunc

_G.EncounterJournal_ToggleHeaders = function() end
_G.EncounterJournal_SetBullets = function() end
_G.EncounterJournal_SetDescriptionWithBullets = function() end
_G.EncounterJournal_UpdateButtonState = function() end

C_Timer = { After = function(_, fn) fn() end }

local hooks = {}
function hooksecurefunc(name, callback)
    hooks[name] = callback
end

local callbacks = {}
local calls = {}
local frameData = setmetatable({}, { __mode = "k" })
local lateHeader = { name = "lateHeader" }
local lateOverview = { name = "lateOverview" }
local lateButton = { name = "lateButton" }

function lateButton:GetParent()
    return lateHeader
end

_G.EncounterJournal = {
    name = "EncounterJournal",
    encounter = {
        infoFrame = { name = "infoFrame" },
        overviewFrame = {
            name = "overviewFrame",
            overviews = { lateOverview },
        },
        usedHeaders = {},
        freeHeaders = {},
    },
}

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    return tbl, function(key)
        local state = tbl[key]
        if not state then
            state = {}
            tbl[key] = state
        end
        return state
    end
end

local ns = {
    Helpers = {
        CreateStateTable = CreateStateTable,
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = {
                            skinEncounterJournal = true,
                        },
                    },
                },
            }
        end,
    },
    Registry = {
        Register = function() end,
    },
}

ns.SkinBase = {
    RefreshFrameBackdropColors = function() end,
    IsSkinned = function() return false end,
    SkinButtonFrameTemplate = function(frame)
        calls.buttonFrame = frame
    end,
    SkinFrameText = function(frame, opts)
        calls[frame] = opts or {}
    end,
    MarkSkinned = function(frame)
        calls.marked = frame
    end,
    SetFrameData = function(frame, key, value)
        frameData[frame] = frameData[frame] or {}
        frameData[frame][key] = value
    end,
    GetFrameData = function(frame, key)
        local data = frameData[frame]
        return data and data[key]
    end,
    OnAddOnLoaded = function(addon, callback)
        callbacks[addon] = callback
    end,
}

assert(loadfile("QUI_Skinning/skinning/frames/journals.lua"))("QUI", ns)
assert(type(callbacks.Blizzard_EncounterJournal) == "function", "Encounter Journal load hook must be registered")

callbacks.Blizzard_EncounterJournal()

assert(calls.buttonFrame == _G.EncounterJournal, "Encounter Journal must still get QUI frame chrome")
assert(calls.marked == _G.EncounterJournal, "Encounter Journal must be marked skinned")
assert(type(hooks.EncounterJournal_ToggleHeaders) == "function",
    "Encounter Journal skinning must hook section header refreshes")
assert(type(hooks.EncounterJournal_SetBullets) == "function",
    "Encounter Journal skinning must hook bullet text refreshes")
assert(type(hooks.EncounterJournal_UpdateButtonState) == "function",
    "Encounter Journal skinning must hook Blizzard header color refreshes")

calls = {}
_G.EncounterJournal.encounter.usedHeaders[1] = lateHeader

hooks.EncounterJournal_ToggleHeaders()

assert(calls[lateHeader] and calls[lateHeader].recurse == true and calls[lateHeader].chrome == true,
    "late Encounter Journal ability headers must receive recursive QUI chrome text styling")
assert(calls[lateOverview] and calls[lateOverview].recurse == true and calls[lateOverview].chrome == true,
    "late Encounter Journal overview sections must receive recursive QUI chrome text styling")

calls = {}
hooks.EncounterJournal_UpdateButtonState(lateButton)

assert(calls[lateButton] and calls[lateButton].recurse == true and calls[lateButton].chrome == true,
    "Encounter Journal button text recolored by Blizzard must be restyled")
assert(calls[lateHeader] and calls[lateHeader].recurse == true and calls[lateHeader].chrome == true,
    "Encounter Journal button parent text must be restyled after Blizzard color refresh")

print("OK: encounter_journal_dynamic_text_test")
