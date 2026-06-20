-- tests/unit/skinbase_addon_loaded_test.lua
-- Run: lua tests/unit/skinbase_addon_loaded_test.lua

local events = {}

local function NewWatcher()
    local watcher = { registered = {}, scripts = {} }
    function watcher:RegisterEvent(event) self.registered[event] = true end
    function watcher:UnregisterEvent(event) self.registered[event] = nil end
    function watcher:SetScript(event, callback) self.scripts[event] = callback end
    return watcher
end

function CreateFrame()
    local watcher = NewWatcher()
    events[#events + 1] = watcher
    return watcher
end

C_Timer = { After = function(_, callback) callback() end }

local loadedOrLoading = false
local fullyLoaded = false
C_AddOns = {
    IsAddOnLoaded = function(name)
        assert(name == "Blizzard_TestAddon", "unexpected addon query: " .. tostring(name))
        return loadedOrLoading, fullyLoaded
    end,
}

local ns = {
    Helpers = {
        CHROME = {
            BORDER_PX = 1,
            BG_FALLBACK = { 0, 0, 0, 1 },
            BORDER_FALLBACK = { 1, 1, 1, 1 },
        },
        CreateStateTable = function()
            local store = setmetatable({}, { __mode = "k" })
            local function get(key)
                local value = store[key]
                if not value then
                    value = {}
                    store[key] = value
                end
                return value
            end
            return store, get
        end,
        GetCore = function() return nil end,
        GetSkinBorderColor = function() return 1, 1, 1, 1 end,
        GetSkinBgColorWithOverride = function() return 0, 0, 0, 1 end,
        GetSkinBarColor = function() return 0, 0, 0, 1 end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

local fired = 0
loadedOrLoading = true
fullyLoaded = false
SkinBase.OnAddOnLoaded("Blizzard_TestAddon", function() fired = fired + 1 end, 0)
assert(fired == 0, "OnAddOnLoaded must not fire while addon is only loading")
assert(#events == 1, "OnAddOnLoaded must register an ADDON_LOADED watcher while only loading")

fullyLoaded = true
events[1].scripts.OnEvent(events[1], "ADDON_LOADED", "Blizzard_TestAddon")
assert(fired == 1, "OnAddOnLoaded must fire after the matching ADDON_LOADED event")
assert(events[1].registered.ADDON_LOADED == nil, "OnAddOnLoaded must unregister after the matching addon event")

loadedOrLoading = true
fullyLoaded = true
SkinBase.OnAddOnLoaded("Blizzard_TestAddon", function() fired = fired + 1 end, 0)
assert(fired == 2, "OnAddOnLoaded must fire immediately when the addon is fully loaded")
assert(#events == 1, "OnAddOnLoaded must not create a watcher for fully-loaded addons")

print("OK: skinbase_addon_loaded_test")
