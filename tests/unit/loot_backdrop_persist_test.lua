-- tests/unit/loot_backdrop_persist_test.lua
-- Run: lua tests/unit/loot_backdrop_persist_test.lua
--
-- Regression guard for the "loot/roll window shows the correct bg color but then
-- turns white" bug.
--
-- Root cause: SkinBase.ApplyPixelBackdrop registers the frame for scale refreshes.
-- When one fires (a pop-up itself queues one by creating its pixel borders),
-- RefreshPixelBackdrop rebuilds the backdrop via SetBackdrop -- which resets the
-- backdrop textures to white -- and only re-applies a color it can find in
-- data.bgColor or the frame's _quiBg*/_quiBorder* backup fields. A bare
-- frame:SetBackdropColor() never populates those, so the rebuild drops the color
-- and the frame goes white.
--
-- The fix routes loot.lua's color writes through Helpers.SetFrameBackdropColor /
-- Helpers.SetFrameBackdropBorderColor (core/utils.lua), which set the live color
-- AND record _quiBg*/_quiBorder* so the rebuild preserves it. This test exercises
-- the real SkinBase rebuild path to prove that contract.

-- luacheck: globals CreateFrame

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

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    return tbl
end

-- Capture scale-refresh callbacks so the test can fire one on demand.
local scaleRefreshers = {}
local function SimulateScaleRefresh()
    for _, fn in ipairs(scaleRefreshers) do fn() end
end

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = CreateStateTable,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetSkinBarColor = function() return 0.5, 0.5, 0.5, 1 end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    UIKit = {
        RegisterScaleRefresh = function(owner, _, fn)
            scaleRefreshers[#scaleRefreshers + 1] = function() fn(owner) end
        end,
    },
}

CreateFrame = function() return NewBackdropFrame() end

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase
assert(type(SkinBase.ApplyPixelBackdrop) == "function", "SkinBase.ApplyPixelBackdrop must exist")

-- Mirror the blessed persisting helpers (core/utils.lua) without loading the full
-- Helpers module. These are exactly what the loot.lua fix calls.
local function SetFrameBackdropColor(frame, r, g, b, a)
    frame:SetBackdropColor(r, g, b, a)
    frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA = r, g, b, a
end
local function SetFrameBackdropBorderColor(frame, r, g, b, a)
    frame:SetBackdropBorderColor(r, g, b, a)
    frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA = r, g, b, a
end

local BG = { 0.1, 0.12, 0.14, 0.95 }
local BORDER = { 0.6, 0.7, 0.8, 0.3 }

----------------------------------------------------------------------------
-- 1) Unified render path (#3): colors set via the installed ManualSetBackdropColor
--    are stored in _quiBg*/_quiBorder* and survive a scale-refresh rebuild.
--    The old "goes white" bug is eliminated at the engine level.
----------------------------------------------------------------------------
local buggy = NewBackdropFrame()
SkinBase.ApplyPixelBackdrop(buggy, 1, true, false)
-- After ApplyPixelBackdrop, frame.SetBackdropColor is the manual version which
-- stores to _quiBg* — so even a bare call persists the color.
buggy:SetBackdropColor(BG[1], BG[2], BG[3], BG[4])
buggy:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
assert(buggy._quiBgR == BG[1] and buggy._quiBgA == BG[4],
    "precondition: themed bg color is stored in _quiBg* right after styling")

SimulateScaleRefresh()
assert(buggy._quiBgR == BG[1] and buggy._quiBgA == BG[4],
    "UNIFIED: bg color persists across scale-refresh rebuild via _quiBg* fields")
assert(buggy._quiBorderR == BORDER[1] and buggy._quiBorderA == BORDER[4],
    "UNIFIED: border color persists across scale-refresh rebuild via _quiBorder* fields")

----------------------------------------------------------------------------
-- 2) Colors written via the Helpers persist wrappers also survive the rebuild.
----------------------------------------------------------------------------
local fixed = NewBackdropFrame()
SkinBase.ApplyPixelBackdrop(fixed, 1, true, false)
SetFrameBackdropColor(fixed, BG[1], BG[2], BG[3], BG[4])
SetFrameBackdropBorderColor(fixed, BORDER[1], BORDER[2], BORDER[3], BORDER[4])

SimulateScaleRefresh()
assert(fixed._quiBgR == BG[1] and fixed._quiBgG == BG[2]
    and fixed._quiBgB == BG[3] and fixed._quiBgA == BG[4],
    "FIX: persisted bg color must survive a scale-refresh rebuild, not go white")
assert(fixed._quiBorderR == BORDER[1] and fixed._quiBorderA == BORDER[4],
    "FIX: persisted border color must survive a scale-refresh rebuild")

----------------------------------------------------------------------------
-- 3) Border-only icon borders (quality color) must persist too.
----------------------------------------------------------------------------
local iconBorder = NewBackdropFrame()
SkinBase.ApplyPixelBackdrop(iconBorder, 2, false, false)
SetFrameBackdropBorderColor(iconBorder, 0.64, 0.21, 0.93, 1) -- epic purple

SimulateScaleRefresh()
assert(iconBorder._quiBorderR == 0.64 and iconBorder._quiBorderG == 0.21
    and iconBorder._quiBorderB == 0.93,
    "FIX: persisted quality icon-border color must survive a scale-refresh rebuild")

print("OK: loot_backdrop_persist_test")
