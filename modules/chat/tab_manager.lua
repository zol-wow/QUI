-- modules/chat/tab_manager.lua
-- Phase 1 tab state for the custom display: builds filter closures from the
-- existing settings.chat.tabs shape ({ groups = {KEY=true}, channels =
-- {Name=true}, invert = bool }) and drives DisplayLayer.Rebuild on switch.
-- Visual tab buttons are Phase 2 (tab_ui.lua); Phase 1 exposes the filter
-- machinery only.
--
-- Secret entries are NEVER classified — they always pass.
local ADDON_NAME, ns = ...

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_manager.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_manager.lua.")

ns.QUI.Chat.TabManager = ns.QUI.Chat.TabManager or {}
local TabManager = ns.QUI.Chat.TabManager

local activeFilter

local function HasAny(t)
    return type(t) == "table" and next(t) ~= nil
end

-- Returns a filter closure, or nil when tabData expresses no constraint
-- (nil filter = show everything; cheaper than an always-true closure).
--
-- SHAPE NOTE: expects SET-shaped constraints ({ SAY = true, Trade = true }).
-- The persisted settings.chat.tabs entries (written by tab_filters.lua)
-- store ARRAYS ({ "SAY", "Trade" }) and have no `invert` key — any future
-- caller wiring stored tabs into SetActiveTab MUST adapt array -> set first,
-- or every lookup silently misses. No Phase 1 caller does this yet.
function TabManager.BuildFilter(tabData)
    if type(tabData) ~= "table" then return nil end
    local groups = HasAny(tabData.groups) and tabData.groups or nil
    local channels = HasAny(tabData.channels) and tabData.channels or nil
    if not groups and not channels then return nil end
    local invert = tabData.invert and true or false

    -- An entry is "listed" if EITHER its typeKey or its channel name is
    -- constrained — whitelisting the CHANNEL group passes all channels.
    return function(entry)
        if entry.s then return true end -- secrets always pass
        local listed = false
        if groups and entry.k and groups[entry.k] then listed = true end
        if not listed and channels and entry.ch and channels[entry.ch] then listed = true end
        if invert then
            return not listed
        end
        return listed
    end
end

function TabManager.SetActiveTab(tabData)
    activeFilter = TabManager.BuildFilter(tabData)
    local Display = ns.QUI.Chat.DisplayLayer
    if Display and Display.Rebuild then
        Display.Rebuild(activeFilter)
    end
end

function TabManager.GetActiveFilter()
    return activeFilter
end
