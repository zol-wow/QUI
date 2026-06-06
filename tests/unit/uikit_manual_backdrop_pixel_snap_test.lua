-- tests/unit/uikit_manual_backdrop_pixel_snap_test.lua
-- The SkinBase manual-backdrop engine (EnsureManualBackdrop/ApplyTextureBackdrop)
-- draws its 1px edges as solid SetColorTexture quads. With the engine's default
-- texel snapping left on, a 1-physical-pixel solid texture rasterizes to NOTHING
-- at certain fractional screen offsets — observed as the CharacterFrame close
-- button losing its border box on the Reputation/Currency tabs (button parked at
-- TOPRIGHT -3,-5 inside the frame) while rendering fine on the Character tab
-- (button at +52, a different screen fraction). The sibling border path
-- (UIKit.CreateBorderLines -> ApplyColorTexture) already disables texel snapping
-- after every SetColorTexture; the manual-backdrop path must do the same.
-- Run: lua tests/unit/uikit_manual_backdrop_pixel_snap_test.lua
-- luacheck: globals CreateFrame

local function NewTexture()
    local texture = { points = {} }
    function texture:ClearAllPoints() self.points = {} end
    function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function texture:SetHeight(height) self.height = height end
    function texture:SetWidth(width) self.width = width end
    function texture:SetTexture(file) self.file = file end
    function texture:SetColorTexture(r, g, b, a)
        self.colorTexture = { r, g, b, a }
        -- The real client can reset snapping state when texture contents change;
        -- model that so the fix must re-apply DisablePixelSnap after recolors.
        self.snap = nil
        self.bias = nil
    end
    function texture:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function texture:SetSnapToPixelGrid(snap) self.snap = snap end
    function texture:SetTexelSnappingBias(bias) self.bias = bias end
    function texture:Show() self.visible = true end
    function texture:Hide() self.visible = false end
    return texture
end

local function NewFrame(parent)
    local frame = { parent = parent, textures = {}, points = {}, shown = false, frameLevel = 4 }
    function frame:CreateTexture(_, drawLayer, _, subLevel)
        local texture = NewTexture()
        texture.drawLayer = drawLayer
        texture.subLevel = subLevel
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function frame:SetAllPoints() self.allPoints = true end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    return frame
end

function CreateFrame(_, _, parent)
    local frame = NewFrame(parent)
    frame.scripts = {}
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetScript(name) return self.scripts[name] end
    return frame
end

local currentPixelSize = 0.5

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = function()
            return setmetatable({}, { __mode = "k" })
        end,
        SafeToNumber = function(value, default)
            return tonumber(value) or default
        end,
    },
}

local core = {}
function core:GetPixelSize() return currentPixelSize end
function core:Pixels(value) return value * currentPixelSize end
function ns.Helpers.GetCore() return core end

assert(loadfile("core/uikit.lua"))("QUI", ns)

local SkinBase = ns.SkinBase
assert(type(SkinBase.ApplyPixelBackdrop) == "function", "SkinBase must expose ApplyPixelBackdrop")

---------------------------------------------------------------------------
-- 1. Solid (default WHITE8x8) backdrop: every color-textured region — the
--    BACKGROUND fill and all 4 BORDER edges — must have texel snapping
--    disabled (snap=false, bias=0) or 1px edges vanish at fractional offsets.
---------------------------------------------------------------------------
local skinFrame = NewFrame()
SkinBase.ApplyPixelBackdrop(skinFrame, 1, true, true, { 0, 0, 0, 1 }, { 0.05, 0.05, 0.05, 0.95 })

local edgeCount, bgCount = 0, 0
for _, tex in ipairs(skinFrame.textures) do
    if tex.drawLayer == "BORDER" then
        edgeCount = edgeCount + 1
        assert(tex.snap == false,
            "manual-backdrop edge textures must SetSnapToPixelGrid(false) "
            .. "(got " .. tostring(tex.snap) .. ") — 1px solid edges vanish at "
            .. "fractional screen offsets with default snapping")
        assert(tex.bias == 0,
            "manual-backdrop edge textures must SetTexelSnappingBias(0) "
            .. "(got " .. tostring(tex.bias) .. ")")
    elseif tex.drawLayer == "BACKGROUND" then
        bgCount = bgCount + 1
        assert(tex.snap == false and tex.bias == 0,
            "manual-backdrop bg fill must get the same snap treatment as the edges")
    end
end
assert(edgeCount == 4, "expected 4 BORDER edge textures (got " .. edgeCount .. ")")
assert(bgCount == 1, "expected 1 BACKGROUND fill texture (got " .. bgCount .. ")")

---------------------------------------------------------------------------
-- 2. Recolor path: ManualSetBackdropBorderColor re-runs SetColorTexture
--    (which can reset snapping state in the client) — snapping must be
--    re-disabled afterwards, mirroring the ApplyColorTexture pattern.
---------------------------------------------------------------------------
skinFrame:SetBackdropBorderColor(1, 0, 0, 1)
for _, tex in ipairs(skinFrame.textures) do
    if tex.drawLayer == "BORDER" then
        assert(tex.snap == false and tex.bias == 0,
            "recoloring the border must re-disable texel snapping after SetColorTexture")
    end
end

---------------------------------------------------------------------------
-- 3. File-based (LSM) edges keep default snapping: the vertex-color branch
--    must NOT start touching snap state — textured borders render with the
--    engine defaults on purpose.
---------------------------------------------------------------------------
local lsmFrame = NewFrame()
SkinBase.ApplyPixelBackdrop(lsmFrame, 1, true, true, { 0, 0, 0, 1 }, { 0.05, 0.05, 0.05, 0.95 },
    nil, "Interface\\SomeAddon\\FancyBorder")
for _, tex in ipairs(lsmFrame.textures) do
    if tex.drawLayer == "BORDER" then
        assert(tex.snap == nil and tex.bias == nil,
            "file-based edge textures must keep engine-default snapping untouched")
    end
end

print("OK: uikit_manual_backdrop_pixel_snap_test")
