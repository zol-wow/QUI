-- tests/unit/uikit_skinbase_merge_test.lua
-- Run: lua tests/unit/uikit_skinbase_merge_test.lua
-- Verifies the skinning engine was merged into core/uikit.lua: ns.SkinBase aliases
-- ns.UIKit (one table) and the merged kit exposes every UIKit + SkinBase method.

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
}
assert(loadfile("core/uikit.lua"))("QUI", ns)

assert(ns.SkinBase == ns.UIKit, "ns.SkinBase must alias ns.UIKit (one table)")
local K = ns.UIKit
for _, name in ipairs({
    "CreateBackdrop","ApplyPixelBackdrop","ApplyFullBackdrop","ApplyTextureBackdrop",
    "GetDepthColor","GetSkinColors","GetPixelSize","SkinFontString","SkinFrameText",
    "SkinButton","SkinEditBox","SkinDropdown","SkinScrollRow","SkinCategoryButton",
    "StripTextures","RefreshWidget","GetBackdrop","MarkSkinned","IsStyled",
    "CreateBorderLines","UpdateBorderLines","CreateBackground","GetBackdropInfo",
}) do
    assert(type(K[name]) == "function", "merged kit must expose " .. name)
end
print("OK: uikit_skinbase_merge_test")
