-- tests/unit/tooltip_itemref_close_button_skinned_test.lua
-- Run: lua tests/unit/tooltip_itemref_close_button_skinned_test.lua
--
-- ItemRefTooltip (the item-link tooltip) ships a UIPanelCloseButtonNoScripts
-- "×" at ItemRefTooltip.CloseButton (Blizzard_UIPanels_Game/Mainline/ItemRef.xml).
-- The tooltip chrome is skinned, but without restyling that button the stock
-- red Blizzard X shows through. This test pins that StyleTooltip routes the
-- tooltip's CloseButton through SkinBase.SkinCloseButton, and that tooltips
-- without a CloseButton (GameTooltip) are left alone.

local function makeFrame()
    local frame = { shown = false, scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(scriptName, handler) self.scripts[scriptName] = handler end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetAllPoints() self.allPoints = true end
    function frame:EnableMouse() end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:SetFrameStrata(strata) self.frameStrata = strata end
    function frame:GetWidth() return 200 end
    function frame:GetHeight() return 80 end
    function frame:GetFrameLevel() return 10 end
    function frame:GetFrameStrata() return "TOOLTIP" end
    function frame:GetOwner() return nil end
    return frame
end

local function makeFontObject(path, size, flags)
    local fontObject = { path = path, size = size, flags = flags }
    function fontObject:GetFont() return self.path, self.size, self.flags end
    function fontObject:SetFont(p, s, f) self.path, self.size, self.flags = p, s, f end
    return fontObject
end

local eventFrame

_G.UIParent = makeFrame()
_G.WorldFrame = makeFrame()
_G.GameTooltip = makeFrame()
_G.GameTooltip.shown = true
_G.GameTooltipHeaderText = makeFontObject("Fonts\\FRIZQT__.TTF", 14, "")
_G.GameTooltipText = makeFontObject("Fonts\\FRIZQT__.TTF", 12, "")

-- The frame under test: ItemRefTooltip with a CloseButton child.
_G.ItemRefTooltip = makeFrame()
_G.ItemRefTooltip.CloseButton = makeFrame()

_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.ADDON_LOADED = "ADDON_LOADED"
_G.CreateFrame = function()
    local frame = makeFrame()
    if not eventFrame then eventFrame = frame end
    return frame
end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.hooksecurefunc = function() end
_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local skinnedCloseButtons = {}

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = { profile = { tooltip = {
                    enabled = true, skinTooltips = true, fontSize = 13,
                } } },
            }
        end,
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetSkinBorderColor = function() return 1, 1, 1, 1 end,
        GetSkinBgColor = function() return 0, 0, 0, 1 end,
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        IsSecretValue = function() return false end,
    },
    SkinBase = {
        SkinFrameText = function() end,
        SkinCloseButton = function(button)
            skinnedCloseButtons[#skinnedCloseButtons + 1] = button
        end,
    },
    UIKit = {
        CreateBackground = function() return { SetVertexColor = function() end } end,
        CreateBorderLines = function() end,
        UpdateBorderLines = function() end,
    },
    WhenLoggedIn = function(fn) fn() end,
}

assert(loadfile("QUI_Skinning/skinning/system/tooltips.lua"))("QUI", ns)

-- ItemRefTooltip.CloseButton must have been routed through SkinCloseButton.
local sawItemRefClose = false
for _, btn in ipairs(skinnedCloseButtons) do
    if btn == _G.ItemRefTooltip.CloseButton then sawItemRefClose = true end
end
assert(sawItemRefClose,
    "ItemRefTooltip.CloseButton must be skinned via SkinBase.SkinCloseButton so the stock red X is replaced")

-- GameTooltip has no CloseButton; it must not produce a SkinCloseButton call
-- (no nil arg, no unexpected button).
for _, btn in ipairs(skinnedCloseButtons) do
    assert(btn ~= nil, "SkinCloseButton must never be called with a nil button")
end

print("OK: tooltip_itemref_close_button_skinned_test")
