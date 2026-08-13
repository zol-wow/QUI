-- Run: lua tests/unit/onaddonloaded_defers_until_db_exists_test.lua

-- luacheck: globals CreateFrame C_Timer C_AddOns hooksecurefunc ScrollUtil STANDARD_TEXT_FONT

local watchers = {}

CreateFrame = function()
    local frame = {
        events = {},
        CreateTexture = function() return {} end,
    }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, handler) self.handler = handler end
    watchers[#watchers + 1] = frame
    return frame
end

C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "x"

local loadedAddOns = { Blizzard_AlreadyLoaded = true }
C_AddOns = {
    IsAddOnLoaded = function(name)
        local loaded = loadedAddOns[name] == true
        return loaded, loaded
    end,
}

local queued = {}
local CHROME = {
    BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
    BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
    DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } },
}
local ns = {
    RunAfterFirstFrame = function(callback) queued[#queued + 1] = callback end,
    Helpers = {
        CHROME = CHROME,
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetCore = function() return {} end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.10, 0.20, 0.30, 0.9 end,
        GetGeneralFont = function() return "Q" end,
        GetGeneralFontOutline = function() return "" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

local function Flush()
    local pending = queued
    queued = {}
    for _, callback in ipairs(pending) do callback() end
end

local alreadyLoadedRuns = 0
SkinBase.OnAddOnLoaded("Blizzard_AlreadyLoaded", function() alreadyLoadedRuns = alreadyLoadedRuns + 1 end, 0)

assert(alreadyLoadedRuns == 0,
    "an addon already loaded when the skin file runs must NOT fire inline -- QUI.db does not exist yet at file-load time")
Flush()
assert(alreadyLoadedRuns == 1, "the deferred callback must run once the first frame has rendered")

local lateRuns = 0
SkinBase.OnAddOnLoaded("Blizzard_LoadsLater", function() lateRuns = lateRuns + 1 end, 0)
assert(lateRuns == 0 and #queued == 0, "an unloaded addon must wait for ADDON_LOADED, not queue immediately")

local watcher = watchers[#watchers]
assert(watcher and watcher.events.ADDON_LOADED and watcher.handler, "a watcher frame must register ADDON_LOADED")

watcher.handler(watcher, "ADDON_LOADED", "Blizzard_SomethingElse")
assert(#queued == 0, "a different addon's ADDON_LOADED must be ignored")

watcher.handler(watcher, "ADDON_LOADED", "Blizzard_LoadsLater")
assert(lateRuns == 0, "the ADDON_LOADED path must defer too, not fire inside the event")
Flush()
assert(lateRuns == 1, "the watched callback must run after deferral")

print("OK: onaddonloaded_defers_until_db_exists_test")
