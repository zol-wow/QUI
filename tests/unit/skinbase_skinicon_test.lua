-- tests/unit/skinbase_skinicon_test.lua
-- Run: lua tests/unit/skinbase_skinicon_test.lua
-- Covers SkinBase.SkinIcon (core/uikit.lua): crop the icon TexCoord to the QUI
-- 0.08-0.92 convention, parent a thin pixel border, cache it per icon
-- (idempotent), default + explicit border color, and the crop=false opt-out.
-- ApplyPixelBackdrop / SetExpandedPixelPoints are spied after load so the test
-- targets SkinIcon's own logic, not the backdrop-texture machinery.
-- luacheck: globals CreateFrame C_Timer hooksecurefunc

local createdFrames = {}
local function NewFrame()
    local f = { frameLevel = 3 }
    function f:GetFrameLevel() return self.frameLevel end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:EnableMouse(e) self.mouseEnabled = e end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetAllPoints() end
    return f
end

local function NewIcon(parent)
    local t = { parent = parent }
    function t:SetTexCoord(l, r, b, top) self.texCoord = { l, r, b, top } end
    function t:GetParent() return self.parent end
    return t
end

function CreateFrame(_, _, parent)
    local f = NewFrame(); f.parent = parent
    createdFrames[#createdFrames + 1] = f
    return f
end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end

local skinBorder = { 0.6, 0.7, 0.8, 1 }
local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key) local s = tbl[key]; if not s then s = {}; tbl[key] = s end; return s end
            return tbl, get
        end,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return skinBorder[1], skinBorder[2], skinBorder[3], skinBorder[4] end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetSkinBarColor = function() return 0.5, 0.5, 0.5, 1 end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

-- Spy on the backdrop machinery so the test targets SkinIcon's own logic.
local applied = {}
SkinBase.SetExpandedPixelPoints = function() end
SkinBase.ApplyPixelBackdrop = function(frame, pixels, withBg, withInsets, borderColor)
    applied[#applied + 1] = { frame = frame, pixels = pixels, withBg = withBg, withInsets = withInsets, border = borderColor }
end
local recolors = {}
SkinBase.SetBackdropColors = function(frame, borderColor) recolors[#recolors + 1] = { frame = frame, border = borderColor } end

-- ── crop + border creation + default color ─────────────────────────────────
do
    local host = NewFrame()
    local icon = NewIcon(host)
    local before = #createdFrames
    local border = SkinBase.SkinIcon(icon)
    assert(icon.texCoord and icon.texCoord[1] == 0.08 and icon.texCoord[2] == 0.92,
        "SkinIcon must crop the icon TexCoord to 0.08-0.92")
    assert(border and #createdFrames == before + 1, "SkinIcon must create one border frame")
    assert(SkinBase.GetFrameData(icon, "iconBorder") == border, "SkinIcon must cache the border per icon")
    assert(#applied == 1 and applied[1].frame == border and applied[1].withBg == false,
        "SkinIcon must apply a hollow (no-bg) pixel backdrop to the border")
    assert(applied[1].border[1] == skinBorder[1] and applied[1].border[4] == skinBorder[4],
        "SkinIcon must default the border color to the skin border color")
end

-- ── idempotent: second call reuses the cached border, no new frame ─────────
do
    local host = NewFrame()
    local icon = NewIcon(host)
    local b1 = SkinBase.SkinIcon(icon)
    local n = #createdFrames
    local b2 = SkinBase.SkinIcon(icon)
    assert(b1 == b2, "SkinIcon must return the cached border on re-call")
    assert(#createdFrames == n, "SkinIcon must NOT create a second border frame on re-call")
end

-- ── explicit border color + recolor on re-call ─────────────────────────────
do
    local host = NewFrame()
    local icon = NewIcon(host)
    local custom = { 0.9, 0.1, 0.1, 1 }
    SkinBase.SkinIcon(icon, { border = custom })
    assert(applied[#applied].border[1] == 0.9, "SkinIcon must honor an explicit border color")
    SkinBase.SkinIcon(icon, { border = { 0.2, 0.3, 0.4, 1 } })
    assert(recolors[#recolors] and recolors[#recolors].border[1] == 0.2,
        "SkinIcon re-call with a new border must recolor via SetBackdropColors")
end

-- ── crop=false skips the TexCoord crop ─────────────────────────────────────
do
    local host = NewFrame()
    local icon = NewIcon(host)
    SkinBase.SkinIcon(icon, { crop = false })
    assert(icon.texCoord == nil, "SkinIcon{crop=false} must not crop the TexCoord")
end

-- ── nil / non-texture inputs are no-ops ────────────────────────────────────
SkinBase.SkinIcon(nil)
SkinBase.SkinIcon({})

print("skinbase_skinicon_test: OK")
