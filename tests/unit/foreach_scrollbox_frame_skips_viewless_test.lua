-- Run: lua tests/unit/foreach_scrollbox_frame_skips_viewless_test.lua

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT

CreateFrame = function() return { CreateTexture = function() return {} end } end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "x"

local reported = {}
local CHROME = {
    BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
    BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
    DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } },
}
local ns = {
    SafeCallMethodIfPresent = function(_policy, obj, name, ...)
        if obj == nil then return nil end
        local method = obj[name]
        if method == nil then return nil end
        local ok, result = pcall(method, obj, ...)
        if not ok then reported[#reported + 1] = result end
        return ok, result
    end,
    Helpers = {
        CHROME = CHROME,
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetCore = function() return {} end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.10, 0.20, 0.30, 0.9 end,
        GetGeneralFont = function() return "Q" end,
        GetGeneralFontOutline = function() return "" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

local function NewScrollBox(view)
    local box = { view = view }
    function box:HasView() return self.view ~= nil end
    function box:ForEachFrame(fn)
        for _, frame in ipairs(self.view.frames) do fn(frame) end
    end
    return box
end

local styled = 0
local styleRow = function() styled = styled + 1 end

SkinBase.ForEachScrollBoxFrame(NewScrollBox(nil), styleRow)
assert(styled == 0, "a scroll box without a view must be skipped")
assert(#reported == 0,
    "skipping must not raise -- ScrollBoxListMixin:ForEachFrame indexes a nil view and the error surfaces as QUI's")

SkinBase.ForEachScrollBoxFrame(NewScrollBox({ frames = { {}, {} } }), styleRow)
assert(styled == 2, "a scroll box with a view must style every acquired frame")

local legacy = { ForEachFrame = function(_, fn) fn({}) end }
SkinBase.ForEachScrollBoxFrame(legacy, styleRow)
assert(styled == 3, "a scroll box without HasView must still be walked")

SkinBase.ForEachScrollBoxFrame(nil, styleRow)
assert(styled == 3 and #reported == 0, "a nil scroll box must be a no-op")

print("OK: foreach_scrollbox_frame_skips_viewless_test")
