---------------------------------------------------------------------------
-- QUI Alts Module — entry point. A pure consumer of core storage
-- (ns.Storage): no scanners, no SavedVariables of its own. `alts.enabled`
-- gates only the window; collection runs regardless (core service).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("alts")
Alts.GetSettings = GetSettings

local started = false

local function IsEnabled()
    local s = GetSettings()
    return (s and s.enabled) and true or false
end
Alts.IsEnabled = IsEnabled

local function Refresh()
    if not started then return end
    if not IsEnabled() then
        if Alts.Window and Alts.Window.IsShown() then
            Alts.Window.Hide()
        end
        return
    end
    if Alts.Window and Alts.Window.OnProfileChanged then
        Alts.Window.OnProfileChanged()
    end
end

-- luacheck: globals SLASH_QUIALTS1 SLASH_QUIALTS2
SLASH_QUIALTS1 = "/quialts"
SLASH_QUIALTS2 = "/alts"
SlashCmdList["QUIALTS"] = function()
    if not IsEnabled() then
        print("|cff00ff00QUI:|r the Alts module is disabled (Options → Modules).")
        return
    end
    if Alts.Window then Alts.Window.Toggle() end
end

-- Options surfaces call _G.QUI_RefreshAlts after DB writes (bags precedent).
_G.QUI_RefreshAlts = Refresh

if ns.Registry then
    ns.Registry:Register("alts", {
        refresh = _G.QUI_RefreshAlts,
        priority = 50,
        group = "alts",
        importCategories = { "alts" },
    })
end

ns.WhenLoggedIn(function()
    started = true
end)
