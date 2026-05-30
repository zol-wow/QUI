-- tests/unit/skinbase_depthcolor_test.lua
-- Run: lua tests/unit/skinbase_depthcolor_test.lua

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT
CreateFrame = function() return { CreateTexture = function() return {} end } end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "x"
local function CreateStateTable() local t = setmetatable({}, { __mode = "k" }); return t, function(k) return t[k] end end
local CHROME = {
    BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
    BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
    DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } },
}
local ns = { Helpers = {
    CHROME = CHROME, CreateStateTable = CreateStateTable,
    GetCore = function() return {} end, SafeToNumber = function(v, d) return tonumber(v) or d end,
    GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
    GetSkinBgColorWithOverride = function() return 0.10, 0.20, 0.30, 0.9 end,
    GetGeneralFont = function() return "Q" end, GetGeneralFontOutline = function() return "" end,
}, UIKit = { RegisterScaleRefresh = function() end } }
assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
assert(math.abs(r - 0.14) < 1e-9 and math.abs(g - 0.24) < 1e-9 and math.abs(b - 0.34) < 1e-9,
    "SUBPANEL must add boost 0.04 to the themed bg")
assert(a == 0.85, "SUBPANEL alpha must be 0.85")

local _, _, _, pa = SkinBase.GetDepthColor("PANEL")
assert(pa == 0.95, "PANEL alpha must be 0.95")

local _, _, _, ua = SkinBase.GetDepthColor("NOPE")
assert(ua == 0.95, "unknown tier must fall back to PANEL")

local cr = select(1, SkinBase.GetDepthColor("ROW", nil, nil))
assert(cr <= 1, "channels must clamp at 1.0")
print("OK: skinbase_depthcolor_test")
