local ns = {
    SafeCall = function(_, fn, ...)
        return pcall(fn, ...)
    end,
    L = setmetatable({}, {__index = function(_, key) return key end}),
    Helpers = {
        CreateDBGetter = function()
            return function() return nil end
        end,
    },
}

local function NewFontString()
    return {
        SetAllPoints = function() end,
        SetFont = function() end,
        SetJustifyH = function() end,
        SetJustifyV = function() end,
        SetSpacing = function() end,
        SetText = function() end,
        SetTextColor = function() end,
        SetPoint = function() end,
    }
end

local function NewTexture()
    return {
        SetAllPoints = function() end,
        SetPoint = function() end,
        SetSize = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
        SetVertexColor = function() end,
        SetShown = function() end,
        Show = function() end,
        Hide = function() end,
    }
end

local frameMethods = {}
function frameMethods:SetBackdrop() end
function frameMethods:SetBackdropBorderColor() end
function frameMethods:SetBackdropColor() end
function frameMethods:SetClampedToScreen() end
function frameMethods:SetAllPoints() end
function frameMethods:SetFontString() end
function frameMethods:SetFrameLevel() end
function frameMethods:SetFrameStrata() end
function frameMethods:SetHeight() end
function frameMethods:SetMovable() end
function frameMethods:SetShouldNavigateOnClick() end
function frameMethods:SetShouldPanOnClick() end
function frameMethods:SetShouldZoomInOnClick() end
function frameMethods:SetPoint(_, _, _, x, y) self.point = {x, y} end
function frameMethods:SetScript(name, script) self.scripts[name] = script end
function frameMethods:SetSize() end
function frameMethods:SetText() end
function frameMethods:SetUseMaskTexture() end
function frameMethods:CreateFontString() return NewFontString() end
function frameMethods:CreateTexture() return NewTexture() end
function frameMethods:EnableMouse() end
function frameMethods:Hide() self.shown = false end
function frameMethods:IsShown() return self.shown == true end
function frameMethods:RegisterForClicks() end
function frameMethods:RegisterForDrag() end
function frameMethods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function frameMethods:Show() self.shown = true end
function frameMethods:StartMoving() end
function frameMethods:StopMovingOrSizing() end
function frameMethods:ClearAllPoints() end
function frameMethods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end

local function NewFrame(name, parent)
    local frame = setmetatable({name = name, parent = parent, scripts = {}, shown = false}, {__index = frameMethods})
    if name then _G[name] = frame end
    return frame
end

_G.UIParent = NewFrame("UIParent")
_G.CreateFrame = function(_, name, parent)
    return NewFrame(name, parent or UIParent)
end
_G.STANDARD_TEXT_FONT = "font"
_G.C_Timer = {After = function(_, callback) callback() end}
_G.strtrim = function(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
_G.SlashCmdList = {}

assert(loadfile("modules/qol/aztarec_helper.lua"))("QUI", ns)

local helper = ns.QUI_AztaRec
assert(type(helper) == "table", "Azta'rec helper API must be exported")
assert(helper.Record("star"), "star must be recordable")
assert(helper.Record("circle"), "circle must normalize to CIRCLE")
assert(helper.Record("3"), "numeric marker alias must be recordable")

local sequence = helper.GetSequence()
assert(#sequence == 3, "expected three recorded quadrants")
assert(sequence[1] == "STAR" and sequence[2] == "CIRCLE" and sequence[3] == "DIAMOND",
    "recorded sequence must preserve normalized marker order")

sequence[1] = "TRIANGLE"
assert(helper.GetSequence()[1] == "STAR", "GetSequence must return a copy")

helper.Reset()
assert(#helper.GetSequence() == 0, "reset must clear the recorded sequence")

helper.Show()
assert(_G.QUI_AztaRecFrame:IsShown(), "show must create and display the recorder")
assert(_G.QUI_AztaRec_STAR and _G.QUI_AztaRec_TRIANGLE, "all macro marker buttons must exist")
helper.Hide()
assert(not _G.QUI_AztaRecFrame:IsShown(), "hide must hide the recorder")

local requestedMapID
_G.C_Map = {
    GetBestMapForUnit = function() return 16986 end,
    GetMapArtLayers = function(mapID)
        requestedMapID = mapID
    end,
}
_G.C_DelvesUI = {HasActiveLair = function() return true end}
helper.Show()
assert(requestedMapID == 2634, "manual map display must use the Azta'rec map ID")
helper.Hide()
helper.RefreshAutoVisibility()
assert(not _G.QUI_AztaRecFrame:IsShown(), "active unrelated Nemesis lair must not auto-show the recorder")
_G.C_Map.GetBestMapForUnit = function() return 2634 end
helper.RefreshAutoVisibility()
assert(_G.QUI_AztaRecFrame:IsShown(), "active Azta'rec lair must auto-show the recorder")
_G.C_DelvesUI.HasActiveLair = function() return false end
helper.RefreshAutoVisibility()
assert(not _G.QUI_AztaRecFrame:IsShown(), "leaving the Nemesis lair must auto-hide the recorder")

_G.C_DelvesUI = {}
helper.RefreshAutoVisibility()
assert(_G.QUI_AztaRecFrame:IsShown(), "Venomfall Deeps must auto-show the recorder by map ID")
_G.C_Map.GetBestMapForUnit = function() return 2633 end
helper.RefreshAutoVisibility()
assert(not _G.QUI_AztaRecFrame:IsShown(), "leaving Venomfall Deeps must auto-hide the recorder")

print("OK: aztarec_helper_test")
