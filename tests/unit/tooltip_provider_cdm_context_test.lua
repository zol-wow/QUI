-- tests/unit/tooltip_provider_cdm_context_test.lua
-- Run: lua tests/unit/tooltip_provider_cdm_context_test.lua

local now = 100

local function makeFrame(name)
    local frame = {
        name = name,
        children = {},
    }

    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetEffectiveScale() return 1 end
    function frame:IsForbidden() return false end
    function frame:IsVisible() return true end
    function frame:SetSize(width, height) self.size = { width, height } end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetClampedToScreen(value) self.clamped = value end
    function frame:ClearAllPoints() self.point = nil end
    function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function frame:SetScript(scriptName, handler) self.scripts = self.scripts or {}; self.scripts[scriptName] = handler end

    return frame
end

_G.UIParent = makeFrame("UIParent")
_G.WorldFrame = makeFrame("WorldFrame")
_G.CreateFrame = function(_, name, parent)
    local frame = makeFrame(name)
    frame.parent = parent
    return frame
end
_G.GetTime = function() return now end
_G.GetCursorPosition = function() return 100, 100 end
_G.InCombatLockdown = function() return false end
_G.IsShiftKeyDown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.GetMouseFoci = function() return {} end
_G.GetActionInfo = function() return nil end
_G.wipe = function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local tooltipSettings = {
    enabled = true,
    visibility = {
        abilities = "HIDE",
        cdm = "SHOW",
        customTrackers = "SHOW",
    },
}

local ns = {
    Helpers = {
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetCore = function()
            return {
                db = {
                    profile = {
                        tooltip = tooltipSettings,
                    },
                },
            }
        end,
        GetModuleDB = function(moduleName)
            assert(moduleName == "tooltip", "unexpected module db request: " .. tostring(moduleName))
            return tooltipSettings
        end,
        IsSecretValue = function() return false end,
        SafeToNumber = function(value, fallback)
            return tonumber(value) or fallback
        end,
    },
}

assert(loadfile("modules/qol/tooltip_provider.lua"))("QUI", ns)

local provider = assert(ns.TooltipProvider, "tooltip provider should be exported")
local cdmIcon = makeFrame("QUICDMIcon1")
cdmIcon._quiTooltipContext = "cdm"
cdmIcon.__quiTooltipContext = "cdm"

local context = provider:GetTooltipContext(cdmIcon)
assert(context == "cdm",
    "CDM-stamped tooltip owners must resolve to cdm context, got " .. tostring(context))
assert(provider:ShouldShowTooltip(context) == true,
    "CDM tooltip visibility should allow the CDM tooltip")
assert(provider:ShouldShowTooltip("abilities") == false,
    "test fixture must keep ability tooltips hidden to catch fallback leakage")

local customIcon = makeFrame("QUICustomTrackerIcon1")
customIcon._quiTooltipContext = "customTrackers"
assert(provider:GetTooltipContext(customIcon) == "customTrackers",
    "custom tracker tooltip context should still resolve from explicit owner context")

print("OK: tooltip_provider_cdm_context_test")
