-- tests/unit/cdm_composer_spec_refresh_test.lua
-- Run: lua tests/unit/cdm_composer_spec_refresh_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("QUI_CDM/cdm/settings/composer.lua")

local previewStart = assert(source:find("RefreshPreview = function()", 1, true),
    "RefreshPreview should exist")
local previewDbRead = assert(source:find("local db = GetContainerDB(activeContainer)", previewStart, true),
    "RefreshPreview should read the active container DB")
local previewDormantRefresh = source:find("RefreshActiveContainerDormancy()", previewStart, true)
assert(previewDormantRefresh and previewDormantRefresh < previewDbRead,
    "RefreshPreview must reconcile dormant spells before reading ownedSpells")

assert(source:find('composerCDMEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")', 1, true),
    "composer must refresh when the player's specialization changes")
assert(source:find('composerCDMEventFrame:RegisterEvent("SPELLS_CHANGED")', 1, true),
    "composer must refresh after spellbook/talent updates settle")

local eventFrame = assert(source:find("local composerCDMEventFrame = CreateFrame", 1, true),
    "composer CDM event frame should exist")
local eventHandler = assert(source:find('composerCDMEventFrame:SetScript("OnEvent"', eventFrame, true),
    "composer event frame should handle events")
local specBranch = assert(source:find('event == "PLAYER_SPECIALIZATION_CHANGED"', eventHandler, true),
    "composer event handler should branch on spec changes")
local delayedRefresh = source:find("ScheduleComposerCDMRefresh(0.35)", specBranch, true)
assert(delayedRefresh,
    "spec/spell refreshes should be delayed until Blizzard spell data settles")

local scheduler = assert(source:find("local function ScheduleComposerCDMRefresh", 1, true),
    "composer refresh scheduler should exist")
assert(source:find('type(delay) ~= "number"', scheduler, true),
    "composer refresh scheduler should ignore EventRegistry owner tokens passed as the first callback argument")
assert(source:find("previewFrame and previewFrame:IsShown()", scheduler, true),
    "composer refresh scheduler should update the hoisted preview even when the entries body is hidden")

print("OK: cdm_composer_spec_refresh_test")
