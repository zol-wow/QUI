-- tests/unit/skinbase_fontstring_test.lua
-- Run: lua tests/unit/skinbase_fontstring_test.lua
--
-- Behavioral test for SkinBase.SkinFontString (the shared global-font helper)
-- and the opt-in {font=true} path on SkinButton. Mirrors the peer convention in
-- statustracking.lua: global font face + outline, default near-white text color,
-- and the fontstring's current size is preserved unless overridden.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT

local function NewFontString(size)
    local fs = { size = size, flags = "" }
    function fs:SetFont(font, sz, flags) self.font, self.size, self.flags = font, sz, flags end
    function fs:GetFont() return self.font, self.size, self.flags end
    function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    return fs
end

local function NewTexture()
    local t = { alpha = 1 }
    function t:SetAlpha(a) self.alpha = a end
    function t:SetTexture(f) self.file = f end
    function t:SetColorTexture(...) self.colorTexture = { ... } end
    function t:SetVertexColor(...) self.color = { ... } end
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function t:SetHeight(h) self.height = h end
    function t:SetWidth(w) self.width = w end
    function t:Show() self.visible = true end
    function t:Hide() self.visible = false end
    function t:IsShown() return self.visible end
    function t:IsObjectType(o) return o == "Texture" end
    return t
end

local function NewFrame()
    local f = { textures = {}, points = {}, frameLevel = 4 }
    function f:CreateTexture() local t = NewTexture(); self.textures[#self.textures + 1] = t; return t end
    function f:CreateFontString() return NewFontString(12) end
    function f:SetAllPoints() end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:GetFrameLevel() return self.frameLevel end
    function f:EnableMouse() end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:GetRegions() return unpack(self.textures) end
    function f:GetNumRegions() return #self.textures end
    function f:GetHighlightTexture() return nil end
    function f:GetPushedTexture() return nil end
    function f:GetNormalTexture() return nil end
    function f:GetFontString() self._fs = self._fs or NewFontString(13); return self._fs end
    function f:HookScript() end
    return f
end

CreateFrame = function() return NewFrame() end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

local generalFont = "Interface\\QUIFont.ttf"

local ns = {
    Helpers = {
        CreateStateTable = CreateStateTable,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetSkinBarColor = function() return 0.5, 0.5, 0.5, 1 end,
        GetGeneralFont = function() return generalFont end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("modules/skinning/base.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

assert(type(SkinBase.SkinFontString) == "function", "SkinBase.SkinFontString must exist")

-- Default: global font face + outline, preserve current size, near-white color
local fs = NewFontString(14)
SkinBase.SkinFontString(fs)
assert(fs.font == "Interface\\QUIFont.ttf", "SkinFontString must apply the global QUI font face")
assert(fs.flags == "OUTLINE", "SkinFontString must apply the global font outline")
assert(fs.size == 14, "SkinFontString must preserve the fontstring's current size by default")
assert(fs.color[1] == 0.95 and fs.color[2] == 0.95 and fs.color[3] == 0.95,
    "SkinFontString must default to near-white themed text color")

-- Overrides: explicit size, outline, color
local fs2 = NewFontString(10)
SkinBase.SkinFontString(fs2, { size = 20, outline = "", color = { 1, 0, 0, 1 } })
assert(fs2.size == 20, "SkinFontString must honor an explicit size override")
assert(fs2.flags == "", "SkinFontString must honor an explicit outline override")
assert(fs2.color[1] == 1 and fs2.color[2] == 0 and fs2.color[3] == 0,
    "SkinFontString must honor an explicit color override")

-- Safe on nil / objects without SetFont
SkinBase.SkinFontString(nil)
SkinBase.SkinFontString({})

-- Opt-in SkinButton{font=true} applies the font to the button's fontstring
local button = NewFrame()
SkinBase.SkinButton(button, { font = true })
local bfs = button:GetFontString()
assert(bfs.font == "Interface\\QUIFont.ttf", "SkinButton{font=true} must apply the global font to the button label")

-- SkinButton without font opt must NOT touch the label font (scope discipline)
local plainBtn = NewFrame()
SkinBase.SkinButton(plainBtn)
assert(plainBtn:GetFontString().font == nil, "SkinButton without {font=true} must leave the label font untouched")

-- RefreshWidget re-applies the QUI font on a live font change (font-skinned only)
generalFont = "Interface\\NewQUIFont.ttf"
SkinBase.RefreshWidget(button)
assert(button:GetFontString().font == "Interface\\NewQUIFont.ttf",
    "RefreshWidget must re-apply the global font to a font-skinned button on live change")

-- RefreshWidget must NOT font-touch a widget that did not opt in
SkinBase.RefreshWidget(plainBtn)
assert(plainBtn:GetFontString().font == nil,
    "RefreshWidget must not apply a font to a widget that wasn't font-skinned")

print("OK: skinbase_fontstring_test")
