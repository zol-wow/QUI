-- tests/unit/skinbase_frametext_test.lua
-- Run: lua tests/unit/skinbase_frametext_test.lua
-- font universal, color preserved except chrome labels.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT
local function NewTexture()
    local tex = { _type = "Texture" }
    function tex:SetAlpha(a) self.alpha = a end
    function tex:SetTexture(file) self.file = file end
    function tex:SetColorTexture(...) self.colorTexture = { ... } end
    function tex:SetVertexColor(...) self.vertexColor = { ... } end
    function tex:ClearAllPoints() self.points = {} end
    function tex:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function tex:SetHeight(h) self.height = h end
    function tex:SetWidth(w) self.width = w end
    function tex:Show() self.visible = true end
    function tex:Hide() self.visible = false end
    function tex:IsObjectType(objectType) return objectType == self._type end
    function tex:GetObjectType() return self._type end
    return tex
end

local function NewFrame()
    local frame = { _regions = {}, _children = {}, frameLevel = 4 }
    function frame:CreateTexture()
        local tex = NewTexture()
        self._regions[#self._regions + 1] = tex
        return tex
    end
    function frame:GetRegions() return unpack(self._regions) end
    function frame:GetChildren() return unpack(self._children) end
    function frame:GetNumRegions() return #self._regions end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:SetAllPoints() end
    function frame:EnableMouse() end
    function frame:HookScript() end
    return frame
end

CreateFrame = function() return NewFrame() end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "x"
local function CreateStateTable()
    local t = setmetatable({}, { __mode = "k" })
    return t, function(k)
        local state = t[k]
        if not state then
            state = {}
            t[k] = state
        end
        return state
    end
end
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

-- recursive text skinning should preserve Blizzard colors unless chrome text is explicit.
local defaultNested = NewFS(10)
local defaultChildFrame = NewFrame()
defaultChildFrame._regions = { defaultNested }
local defaultFrame = NewFrame()
defaultFrame._children = { defaultChildFrame }
SkinBase.SkinFrameText(defaultFrame, { recurse = true })
assert(defaultNested.font == "QUI.ttf", "recursive SkinFrameText must apply the font to nested fontstrings")
assert(defaultNested.color[1] == 7, "recursive SkinFrameText must preserve nested colors by default")

-- explicit chrome text should also apply readable chrome text color recursively.
local nested = NewFS(10)
local childFrame = NewFrame()
childFrame._regions = { nested }
local chromeFrame = NewFrame()
chromeFrame._children = { childFrame }
SkinBase.SkinFrameText(chromeFrame, { recurse = true, chrome = true })
assert(nested.color[1] == 0.95 and nested.color[2] == 0.95 and nested.color[3] == 0.95,
    "SkinFrameText must recolor nested text when chrome text is explicit")

-- chrome label: explicit near-white color
local lbl = NewFS(13)
SkinBase.SkinFontString(lbl, { color = nil })
assert(lbl.color[1] == 0.95, "chrome label (no fontOnly) must get near-white themed color")
print("OK: skinbase_frametext_test")
