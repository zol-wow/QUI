-- tests/unit/skinbase_chrome_defaults_test.lua
-- Run: lua tests/unit/skinbase_chrome_defaults_test.lua
-- Verifies SkinBase.CHROME aliases the core table and primitives read defaults from it.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT
CreateFrame = function()
    local f = { textures = {}, level = 4 }
    function f:CreateTexture() local t = {}
        function t:ClearAllPoints() end function t:SetPoint() end function t:SetHeight() end
        function t:SetWidth() end function t:Show() end function t:Hide() end
        function t:SetTexture() end function t:SetColorTexture() end function t:SetVertexColor() end
        function t:SetAllPoints() end
        f.textures[#f.textures+1] = t; return t end
    function f:SetAllPoints() end function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end function f:EnableMouse() end
    function f:Show() end function f:Hide() end
    function f:SetBackdrop() end function f:SetBackdropColor(...) self.bgc = { ... } end
    function f:SetBackdropBorderColor(...) self.bdc = { ... } end
    return f
end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    return tbl, function(k) local s = tbl[k]; if not s then s = {}; tbl[k] = s end; return s end
end

local CHROME = {
    BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
    BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
    DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } },
}
local ns = {
    Helpers = {
        CHROME = CHROME, CreateStateTable = CreateStateTable,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetGeneralFont = function() return "Q.ttf" end,
        GetGeneralFontOutline = function() return "" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}
assert(loadfile("modules/skinning/base.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

assert(SkinBase.CHROME == CHROME, "SkinBase.CHROME must alias Helpers.CHROME (same table)")

local frame = CreateFrame()
SkinBase.CreateBackdrop(frame)
local bd = SkinBase.GetBackdrop(frame)
assert(bd._quiBgA == 0.95, "CreateBackdrop bg-alpha default must come from CHROME.BG_FALLBACK")
print("OK: skinbase_chrome_defaults_test")
