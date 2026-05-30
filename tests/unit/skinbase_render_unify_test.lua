-- tests/unit/skinbase_render_unify_test.lua
-- Run: lua tests/unit/skinbase_render_unify_test.lua
-- #3: RefreshPixelBackdrop always uses the manual 4-texture path, even on a
-- frame that HAS SetBackdrop; the SkinBase.SafeSetBackdrop wrapper is removed.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT
local function NewTexture()
    local t = {}
    function t:ClearAllPoints() end function t:SetPoint() end function t:SetHeight() end
    function t:SetWidth() end function t:Show() end function t:Hide() end
    function t:SetTexture() end function t:SetColorTexture() end function t:SetVertexColor() end
    function t:SetAllPoints() end
    return t
end
local function NewFrame()
    local f = { texCount = 0, setBackdropCalled = false, level = 3 }
    function f:CreateTexture() self.texCount = self.texCount + 1; return NewTexture() end
    function f:SetAllPoints() end function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end function f:EnableMouse() end
    function f:Show() end function f:Hide() end
    function f:SetBackdrop() self.setBackdropCalled = true end
    function f:SetBackdropColor() end function f:SetBackdropBorderColor() end
    return f
end
CreateFrame = function() return NewFrame() end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "x"
local function CreateStateTable() local t = setmetatable({}, { __mode = "k" }); return t, function(k) local s=t[k]; if not s then s={}; t[k]=s end; return s end end
local CHROME = { BORDER_PX=1, BG_FALLBACK={0.05,0.05,0.05,0.95}, BORDER_FALLBACK={0,0,0,1}, BUTTON_BOOST=0.07, SCROLLROW_BOOST=0.03, DEPTH={PANEL={boost=0,alpha=0.95},SUBPANEL={boost=0.04,alpha=0.85},ROW={boost=0.07,alpha=0.75}} }
local ns = { Helpers = { CHROME=CHROME, CreateStateTable=CreateStateTable,
    GetCore = function() return {} end,  -- core stub has NO SafeSetBackdrop
    SafeToNumber = function(v,d) return tonumber(v) or d end,
    GetSkinBorderColor = function() return 0.6,0.7,0.8,1 end,
    GetSkinBgColorWithOverride = function() return 0.1,0.2,0.3,0.9 end,
    GetGeneralFont = function() return "Q" end, GetGeneralFontOutline = function() return "" end },
    UIKit = { RegisterScaleRefresh = function() end } }
assert(loadfile("modules/skinning/base.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

assert(SkinBase.SafeSetBackdrop == nil, "SkinBase.SafeSetBackdrop wrapper must be removed (#3)")

local frame = NewFrame()
SkinBase.ApplyPixelBackdrop(frame, 1, true, true)
assert(frame.setBackdropCalled == false, "RefreshPixelBackdrop must not call frame:SetBackdrop after #3")
assert(frame.texCount >= 5, "manual path must create bg + 4 border textures")
print("OK: skinbase_render_unify_test")
