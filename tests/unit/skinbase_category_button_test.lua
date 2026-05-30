-- tests/unit/skinbase_category_button_test.lua
-- Run: lua tests/unit/skinbase_category_button_test.lua
-- #2: SkinCategoryButton applies selected vs unselected backdrop by SelectedTexture
-- visibility; SkinButton honors belowChildren; SkinEditBox honors alpha opts.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT
local function NewTexture() local t = { a = 1 }
    function t:ClearAllPoints() end function t:SetPoint() end function t:SetHeight() end
    function t:SetWidth() end function t:Show() self.shown = true end function t:Hide() self.shown = false end
    function t:IsShown() return self.shown end function t:SetAlpha(v) self.a = v end
    function t:SetTexture() end function t:SetColorTexture() end function t:SetVertexColor() end
    function t:SetAllPoints() end function t:IsObjectType(o) return o == "Texture" end
    return t end
local function NewFrame()
    local f = { textures = {}, level = 4 }
    function f:CreateTexture() local t = NewTexture(); self.textures[#self.textures+1] = t; return t end
    function f:SetAllPoints() end function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end function f:EnableMouse() end
    function f:Show() end function f:Hide() end function f:HookScript(e, fn) self["on"..e] = fn end
    function f:GetRegions() return unpack(self.textures) end
    function f:GetNumRegions() return #self.textures end
    function f:GetHighlightTexture() return nil end function f:GetNormalTexture() return nil end
    function f:GetPushedTexture() return nil end
    function f:SetBackdrop() end
    function f:SetBackdropColor(...) self.bgc = { ... } end
    function f:SetBackdropBorderColor(...) self.bdc = { ... } end
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
    GetCore = function() return {} end, SafeToNumber = function(v,d) return tonumber(v) or d end,
    GetSkinBorderColor = function() return 0.6,0.7,0.8,1 end,
    GetSkinBgColorWithOverride = function() return 0.1,0.2,0.3,0.9 end,
    GetGeneralFont = function() return "Q" end, GetGeneralFontOutline = function() return "" end },
    UIKit = { RegisterScaleRefresh = function() end } }
assert(loadfile("modules/skinning/base.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

assert(type(SkinBase.SkinCategoryButton) == "function", "SkinCategoryButton must exist")
assert(type(SkinBase.RefreshCategorySelected) == "function", "RefreshCategorySelected must exist")

-- Selected button: backdrop = ROW depth (bg + 0.07, alpha 0.75). The manual render
-- path overrides SetBackdropColor → read back via _quiBgA.
local btn = NewFrame()
btn.SelectedTexture = NewTexture(); btn.SelectedTexture:Show()
SkinBase.SkinCategoryButton(btn)
local bd = SkinBase.GetBackdrop(btn)
assert(math.abs(bd._quiBgA - 0.75) < 1e-9, "selected category button uses ROW alpha 0.75")

-- Unselected: alpha 0.7 (dimmer), border halved
btn.SelectedTexture:Hide()
SkinBase.RefreshCategorySelected(btn)
assert(math.abs(bd._quiBgA - 0.7) < 1e-9, "unselected category button uses dimmer alpha 0.7")

-- SkinButton belowChildren lowers the backdrop frame level
local b2 = NewFrame(); b2.level = 5
SkinBase.SkinButton(b2, { belowChildren = true })
assert(SkinBase.GetBackdrop(b2):GetFrameLevel() == 4, "belowChildren lowers backdrop level by 1")

-- SkinEditBox alpha opts
local eb = NewFrame()
SkinBase.SkinEditBox(eb, { borderAlpha = 0.5, bgAlpha = 0.8 })
local ebd = SkinBase.GetBackdrop(eb)
assert(math.abs(ebd._quiBgA - 0.8) < 1e-9, "SkinEditBox bgAlpha override applied")
print("OK: skinbase_category_button_test")
