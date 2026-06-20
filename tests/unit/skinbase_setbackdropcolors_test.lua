-- tests/unit/skinbase_setbackdropcolors_test.lua
-- Run: lua tests/unit/skinbase_setbackdropcolors_test.lua
--
-- Contract guard for SkinBase.SetBackdropColors (core/uikit.lua).
--
-- A frame skinned via ApplyPixelBackdrop / CreateBackdrop persists its colors in
-- the local pixelBackdropData (data.borderColor / data.bgColor). RefreshPixelBackdrop
-- rebuilds the manual 4-texture backdrop from that data on EVERY scale refresh.
-- A bare frame:SetBackdropColor only touches the live textures, so it is silently
-- discarded on the next rebuild ("live recolor reverts on scale refresh" bug class).
-- SetBackdropColors updates the persisted data and re-renders, so the new color
-- must survive a scale refresh. This test drives the REAL uikit.lua render path.
-- luacheck: globals CreateFrame C_Timer hooksecurefunc

local function NewTexture()
    local t = { alpha = 1 }
    function t:SetAlpha(a) self.alpha = a end
    function t:SetTexture(f) self.file = f end
    function t:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetTexCoord() end
    function t:SetDrawLayer() end
    function t:SetSnapToPixelGrid() end
    function t:SetTexelSnappingBias() end
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function t:SetHeight(h) self.height = h end
    function t:SetWidth(w) self.width = w end
    function t:SetSize(w, h) self.width, self.height = w, h end
    function t:Show() self.visible = true end
    function t:Hide() self.visible = false end
    function t:IsShown() return self.visible end
    function t:IsObjectType(objType) return objType == "Texture" end
    return t
end

local function NewFrame(parent)
    local f = { parent = parent, textures = {}, points = {}, frameLevel = 4 }
    function f:CreateTexture() local t = NewTexture(); self.textures[#self.textures + 1] = t; return t end
    function f:CreateFontString() return NewTexture() end
    function f:SetAllPoints() self.allPoints = true end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:GetFrameLevel() return self.frameLevel end
    function f:EnableMouse(e) self.mouseEnabled = e end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    return f
end

function CreateFrame(_, _, parent) return NewFrame(parent) end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 } },
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key)
                local s = tbl[key]
                if not s then s = {}; tbl[key] = s end
                return s
            end
            return tbl, get
        end,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    UIKit = {},
}

assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase
assert(type(SkinBase.SetBackdropColors) == "function", "uikit must expose SkinBase.SetBackdropColors")

-- uikit.lua owns the real scale-refresh registry (ApplyPixelBackdrop registers
-- RefreshPixelBackdrop into it). Drive a refresh through the genuine walk so the
-- test exercises the same path a UI-scale change triggers in-game.
local function SimulateScaleRefresh() SkinBase.RefreshScaleBoundWidgets() end

-- Scan the frame's manual-backdrop textures for one carrying the given solid color.
local function HasColor(frame, c)
    for _, t in ipairs(frame.textures) do
        local ct = t.colorTexture
        if ct and ct[1] == c[1] and ct[2] == c[2] and ct[3] == c[3] and ct[4] == c[4] then
            return true
        end
    end
    return false
end

local BG_A,     BORDER_A     = { 0.40, 0.50, 0.60, 0.90 }, { 0.10, 0.20, 0.30, 1.00 }
local BG_B,     BORDER_B     = { 0.12, 0.13, 0.14, 0.95 }, { 0.70, 0.65, 0.20, 1.00 }
local BG_BARE                = { 0.91, 0.92, 0.93, 0.50 }

local frame = NewFrame()
SkinBase.ApplyPixelBackdrop(frame, 1, true, false, BORDER_A, BG_A)
assert(HasColor(frame, BG_A), "precondition: ApplyPixelBackdrop renders the bg color")
assert(HasColor(frame, BORDER_A), "precondition: ApplyPixelBackdrop renders the border color")

-- SetBackdropColors recolors both components.
SkinBase.SetBackdropColors(frame, BORDER_B, BG_B)
assert(HasColor(frame, BG_B), "SetBackdropColors must apply the new bg color")
assert(HasColor(frame, BORDER_B), "SetBackdropColors must apply the new border color")
assert(not HasColor(frame, BG_A), "old bg color must be gone after SetBackdropColors")

-- THE FIX: a scale refresh rebuilds from persisted data — the new color survives.
SimulateScaleRefresh()
assert(HasColor(frame, BG_B), "FIX: bg must survive a scale refresh, not revert")
assert(HasColor(frame, BORDER_B), "FIX: border must survive a scale refresh, not revert")

-- Border-only / bg-only update: nil leaves the other component untouched.
SkinBase.SetBackdropColors(frame, BORDER_A, nil)
SimulateScaleRefresh()
assert(HasColor(frame, BORDER_A), "border-only update must apply the new border")
assert(HasColor(frame, BG_B), "border-only update (nil bg) must keep the existing bg")

-- Regression contrast: a BARE setter does NOT persist — proves why the helper exists.
frame:SetBackdropColor(BG_BARE[1], BG_BARE[2], BG_BARE[3], BG_BARE[4])
assert(HasColor(frame, BG_BARE), "precondition: bare setter touches the live texture")
SimulateScaleRefresh()
assert(not HasColor(frame, BG_BARE), "bare setter must NOT survive a scale refresh (the bug)")
assert(HasColor(frame, BG_B), "scale refresh reverts a bare setter to the persisted bg")

-- Unmanaged frame fallback: SetBackdropColors still recolors via live setters.
local plain = NewFrame()
local appliedBg
function plain:SetBackdropColor(r, g, b, a) appliedBg = { r, g, b, a } end
function plain:SetBackdropBorderColor() end
SkinBase.SetBackdropColors(plain, BORDER_A, BG_A)
assert(appliedBg and appliedBg[1] == BG_A[1], "unmanaged frame must fall back to live SetBackdropColor")

print("OK: skinbase_setbackdropcolors_test")
