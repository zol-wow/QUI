-- tests/unit/skinbase_frametext_test.lua
-- Run: lua tests/unit/skinbase_frametext_test.lua
-- font universal, color preserved except chrome labels.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT
CreateFrame = function() return { CreateTexture = function() return {} end } end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "x"
local function CreateStateTable() local t = setmetatable({}, { __mode = "k" }); return t, function(k) return t[k] end end
local CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
    BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
    DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } }
local ns = { Helpers = { CHROME = CHROME, CreateStateTable = CreateStateTable,
    GetCore = function() return {} end, SafeToNumber = function(v, d) return tonumber(v) or d end,
    GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
    GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
    GetGeneralFont = function() return "QUI.ttf" end, GetGeneralFontOutline = function() return "OUTLINE" end },
    UIKit = { RegisterScaleRefresh = function() end } }
assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

local function NewFS(size, objType)
    local fs = { size = size, color = { 7, 7, 7, 1 }, _type = objType or "FontString" }
    function fs:SetFont(f, s, fl) self.font, self.size, self.flags = f, s, fl end
    function fs:GetFont() return self.font, self.size, self.flags end
    function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    function fs:GetObjectType() return self._type end
    return fs
end

-- fontOnly: sets font, leaves color
local fs = NewFS(12)
SkinBase.SkinFontString(fs, { fontOnly = true })
assert(fs.font == "QUI.ttf", "fontOnly must still set the font face")
assert(fs.color[1] == 7, "fontOnly must NOT change the text color")

-- SkinFrameText walks regions: font applied to every fontstring, color preserved
local title, body, tex = NewFS(14), NewFS(11), NewFS(0, "Texture")
local frame = { _regions = { title, body, tex } }
function frame:GetRegions() return unpack(self._regions) end
SkinBase.SkinFrameText(frame)
assert(title.font == "QUI.ttf" and body.font == "QUI.ttf", "SkinFrameText must font every fontstring region")
assert(title.color[1] == 7 and body.color[1] == 7, "SkinFrameText must preserve fontstring colors by default")
assert(tex.font == nil, "SkinFrameText must skip non-FontString regions")

-- chrome label: explicit near-white color
local lbl = NewFS(13)
SkinBase.SkinFontString(lbl, { color = nil })
assert(lbl.color[1] == 0.95, "chrome label (no fontOnly) must get near-white themed color")
print("OK: skinbase_frametext_test")
