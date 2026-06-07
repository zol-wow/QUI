-- tests/unit/encounter_journal_font_scope_test.lua
-- Run: lua tests/unit/encounter_journal_font_scope_test.lua
--
-- The Encounter Journal contains nested Blizzard-managed text regions. Its QUI
-- skin should apply the QUI font and chrome text color recursively.

-- luacheck: globals _G

local callbacks = {}
local calls = {}
local frameData = setmetatable({}, { __mode = "k" })

_G.EncounterJournal = { name = "EncounterJournal" }

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
        calls[#calls + 1] = { frame = frame, opts = opts or {} }
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

local foundRecursiveText = false
for _, call in ipairs(calls) do
    if call.frame == _G.EncounterJournal and call.opts.recurse == true and call.opts.chrome == true then
        foundRecursiveText = true
    end
end
assert(foundRecursiveText, "Encounter Journal skinning must recursively apply QUI chrome text styling")

print("OK: encounter_journal_font_scope_test")
