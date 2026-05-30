-- tests/unit/mplus_timer_backdrop_persist_test.lua
-- Run: lua tests/unit/mplus_timer_backdrop_persist_test.lua
--
-- Regression guard for the "M+ timer window shows a white background when
-- entering a key" bug.
--
-- Root cause: modules/skinning/gameplay/mplus_timer.lua skins the timer window
-- (root frame), the timer/forces bars, and the sleek bar with
-- SkinBase.ApplyPixelBackdrop, which registers each frame for scale refreshes.
-- Entering a key shows the timer and creates pixel borders, which queues a scale
-- refresh. RefreshPixelBackdrop then rebuilds the backdrop via SetBackdrop --
-- resetting the backdrop textures to white -- and only re-applies a color it can
-- find in data.bgColor or the frame's _quiBg*/_quiBorder* backup fields. The
-- module set its colors with a bare frame:SetBackdropColor(), which populates
-- none of those, so the rebuild dropped the color and the window went white.
--
-- The fix routes mplus_timer.lua's color writes through
-- Helpers.SetFrameBackdropColor / Helpers.SetFrameBackdropBorderColor
-- (core/utils.lua), which set the live color AND record _quiBg*/_quiBorder* so
-- the rebuild preserves it. This test drives the real _G.QUI_ApplyMPlusTimerSkin
-- production path through the real SkinBase rebuild to prove that contract.

-- luacheck: globals CreateFrame QUI_MPlusTimer QUI_ApplyMPlusTimerSkin

-- A frame whose backdrop API mirrors WoW: SetBackdrop recreates the backdrop
-- textures and resets their color to white until SetBackdrop*Color is called.
local function NewTexture()
    local t = {}
    function t:ClearAllPoints() end function t:SetPoint() end
    function t:SetHeight() end function t:SetWidth() end
    function t:Show() end function t:Hide() end
    function t:SetTexture() end
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    return t
end

local function NewBackdropFrame()
    local f = { frameLevel = 4 }
    function f:GetFrameLevel() return self.frameLevel end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:SetAllPoints() end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:EnableMouse() end
    function f:GetEffectiveScale() return 1 end
    function f:Show() end function f:Hide() end
    -- CreateTexture is required by EnsureManualBackdrop (unified render path #3).
    function f:CreateTexture() return NewTexture() end
    function f:SetBackdrop(info) self.backdrop = info end
    function f:GetBackdrop() return self.backdrop end
    -- Initial SetBackdropColor/SetBackdropBorderColor stubs; EnsureManualBackdrop
    -- will replace them with the manual versions after the first ApplyPixelBackdrop.
    function f:SetBackdropColor(r, g, b, a) self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a or 1 end
    function f:SetBackdropBorderColor(r, g, b, a) self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA = r, g, b, a or 1 end
    return f
end

-- Real CreateStateTable contract: returns the weak table AND a get() accessor
-- (base.lua's SetFrameData/GetFrameData rely on the second return value).
local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

-- Capture scale-refresh callbacks so the test can fire one on demand.
local scaleRefreshers = {}
local function SimulateScaleRefresh()
    for _, fn in ipairs(scaleRefreshers) do fn() end
end

-- The themed M+ settings the skin reads. Dark bg -> contrast bars use {0.18,0.18,0.20,1}.
local SETTINGS = { showBorder = true, frameBackgroundOpacity = 1 }

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = CreateStateTable,
        GetCore = function()
            return {
                GetPixelSize = function() return 0.5 end,
                db = { profile = { mplusTimer = SETTINGS } },
            }
        end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetSkinBarColor = function() return 0.5, 0.5, 0.5, 1 end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        -- The blessed persisting helpers (mirrors core/utils.lua) -- exactly what
        -- the mplus_timer.lua fix calls instead of a bare SetBackdropColor.
        SetFrameBackdropColor = function(frame, r, g, b, a)
            frame:SetBackdropColor(r, g, b, a)
            frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA = r, g, b, a
        end,
        SetFrameBackdropBorderColor = function(frame, r, g, b, a)
            frame:SetBackdropBorderColor(r, g, b, a)
            frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA = r, g, b, a
        end,
    },
    UIKit = {
        RegisterScaleRefresh = function(owner, _, fn)
            scaleRefreshers[#scaleRefreshers + 1] = function() fn(owner) end
        end,
    },
}

CreateFrame = function() return NewBackdropFrame() end

-- Load the real SkinBase, then the real M+ timer skinning module.
assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(type(ns.SkinBase) == "function" or type(ns.SkinBase) == "table", "SkinBase must load")
local SkinBase = ns.SkinBase
assert(loadfile("modules/skinning/gameplay/mplus_timer.lua"))("QUI", ns)
assert(type(_G.QUI_ApplyMPlusTimerSkin) == "function",
    "mplus_timer.lua must expose _G.QUI_ApplyMPlusTimerSkin")

-- The expected themed colors the skin should apply (and keep) for these settings.
local WINDOW_BG = { 0.1, 0.2, 0.3, 0.9 } -- bg color * opacity 1
local BAR_BG    = { 0.18, 0.18, 0.20, 1 } -- contrast barBg for a dark window

-- Build the timer object the way utils/qui_mplus_timer.lua does: a window root,
-- one timer bar, and the sleek bar -- the three frames that get a pixel backdrop.
local root = NewBackdropFrame()
local timerBar = { frame = NewBackdropFrame() }
local sleekBar = NewBackdropFrame()
_G.QUI_MPlusTimer = {
    frames = { root = root, sleekBar = sleekBar },
    bars = { timerBar },
}

----------------------------------------------------------------------------
-- Apply the skin. The window/bar/sleek backdrops must be themed immediately.
----------------------------------------------------------------------------
_G.QUI_ApplyMPlusTimerSkin()

local windowBackdrop = SkinBase.GetFrameData(root, "backdrop")
assert(windowBackdrop, "skin must create the window backdrop child frame")
-- After render-path unification (#3) colors are stored in _quiBg*/_quiBorder* fields
-- (written by ManualSetBackdropColor/ManualSetBackdropBorderColor) rather than a
-- .bgColor/.borderColor table on the frame object.
assert(windowBackdrop._quiBgR == WINDOW_BG[1] and windowBackdrop._quiBgA == WINDOW_BG[4],
    "precondition: themed window bg is applied right after skinning")
assert(timerBar.frame._quiBgR == BAR_BG[1] and timerBar.frame._quiBgG == BAR_BG[2],
    "precondition: themed timer-bar bg is applied right after skinning")
assert(sleekBar._quiBgR == BAR_BG[1] and sleekBar._quiBgG == BAR_BG[2],
    "precondition: themed sleek-bar bg is applied right after skinning")

----------------------------------------------------------------------------
-- Entering a key fires a scale refresh. The themed backdrops must survive it,
-- not revert to white.
----------------------------------------------------------------------------
SimulateScaleRefresh()

assert(windowBackdrop._quiBgR == WINDOW_BG[1] and windowBackdrop._quiBgG == WINDOW_BG[2]
    and windowBackdrop._quiBgB == WINDOW_BG[3] and windowBackdrop._quiBgA == WINDOW_BG[4],
    "FIX: M+ timer window bg must survive the key-entry scale refresh, not go white")
assert(timerBar.frame._quiBgR == BAR_BG[1] and timerBar.frame._quiBgG == BAR_BG[2]
    and timerBar.frame._quiBgB == BAR_BG[3],
    "FIX: M+ timer bar bg must survive the key-entry scale refresh, not go white")
assert(sleekBar._quiBgR == BAR_BG[1] and sleekBar._quiBgG == BAR_BG[2]
    and sleekBar._quiBgB == BAR_BG[3],
    "FIX: M+ timer sleek-bar bg must survive the key-entry scale refresh, not go white")

print("OK: mplus_timer_backdrop_persist_test")
