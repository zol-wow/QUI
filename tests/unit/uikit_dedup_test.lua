-- tests/unit/uikit_dedup_test.lua
-- De-dup regression: the two manual-texture border paths (UIKit.CreateBorderLines
-- and the SkinBase EnsureManualBackdrop engine) must build their 4 edge textures
-- through ONE shared internal helper (BuildEdgeTextures), while each preserving
-- its own draw layer:
--   * UIKit.CreateBorderLines       -> OVERLAY, subLevel 7
--   * SkinBase ApplyPixelBackdrop   -> BORDER  (no subLevel)
-- This guards against the texture-create code drifting back into two copies, and
-- proves the draw-layer param survives through the shared builder unchanged.
-- Run: lua tests/unit/uikit_dedup_test.lua
-- luacheck: globals CreateFrame

local refreshDrivers = {}

local function NewTexture()
    local texture = { points = {} }
    function texture:ClearAllPoints() self.points = {} end
    function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function texture:SetHeight(height) self.height = height end
    function texture:SetWidth(width) self.width = width end
    function texture:SetTexture(file) self.file = file end
    function texture:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function texture:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function texture:SetSnapToPixelGrid(snap) self.snap = snap end
    function texture:SetTexelSnappingBias(bias) self.bias = bias end
    function texture:Show() self.visible = true end
    function texture:Hide() self.visible = false end
    return texture
end

-- Capture the draw layer + subLevel each texture is created with so we can prove
-- the param is preserved through the shared builder. CreateTexture signature is
-- (name, drawLayer, templateName, subLevel) per the Blizzard SimpleFrame API.
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
    refreshDrivers[#refreshDrivers + 1] = frame
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

local UIKit = ns.UIKit
local SkinBase = ns.SkinBase
assert(type(UIKit.CreateBorderLines) == "function", "UIKit must expose CreateBorderLines")
assert(type(SkinBase.ApplyPixelBackdrop) == "function", "SkinBase must expose ApplyPixelBackdrop")

-- The shared builder must exist and expose its spy counter. This is what makes
-- the de-dup observable: both paths increment the SAME counter.
assert(type(UIKit._buildEdgeTexturesCount) == "number",
    "shared BuildEdgeTextures must exist and expose its call counter")

---------------------------------------------------------------------------
-- 1. UIKit border path: 4 edge textures on OVERLAY, subLevel 7.
---------------------------------------------------------------------------
local before = UIKit._buildEdgeTexturesCount
local uiFrame = NewFrame()
UIKit.CreateBorderLines(uiFrame)
UIKit.UpdateBorderLines(uiFrame, 1, 0, 0, 0, 1)

assert(UIKit._buildEdgeTexturesCount == before + 1,
    "CreateBorderLines must build its edge textures via the shared BuildEdgeTextures helper")

local uiEdges = 0
for _, tex in ipairs(uiFrame.textures) do
    if tex.drawLayer == "OVERLAY" then
        uiEdges = uiEdges + 1
        assert(tex.subLevel == 7,
            "UIKit border edge textures must keep subLevel 7 through the shared builder "
            .. "(got " .. tostring(tex.subLevel) .. ")")
    end
end
assert(uiEdges == 4,
    "CreateBorderLines must produce exactly 4 OVERLAY edge textures (got " .. uiEdges .. ")")

---------------------------------------------------------------------------
-- 2. SkinBase backdrop path: 4 edge textures on BORDER (no subLevel).
---------------------------------------------------------------------------
local before2 = UIKit._buildEdgeTexturesCount
local skinFrame = NewFrame()
SkinBase.ApplyPixelBackdrop(skinFrame, 1, true, true)

assert(UIKit._buildEdgeTexturesCount == before2 + 1,
    "ApplyPixelBackdrop (EnsureManualBackdrop) must build its edge textures via the SAME shared helper")

local borderEdges = 0
for _, tex in ipairs(skinFrame.textures) do
    if tex.drawLayer == "BORDER" then
        borderEdges = borderEdges + 1
        assert(tex.subLevel == nil,
            "SkinBase backdrop edge textures must stay on BORDER with no subLevel "
            .. "(got subLevel " .. tostring(tex.subLevel) .. ")")
    end
end
assert(borderEdges == 4,
    "ApplyPixelBackdrop must produce exactly 4 BORDER edge textures (got " .. borderEdges .. ")")

-- The backdrop path also builds a BACKGROUND fill texture, which is path-specific
-- and must NOT have leaked onto the BORDER layer.
local bgCount = 0
for _, tex in ipairs(skinFrame.textures) do
    if tex.drawLayer == "BACKGROUND" then bgCount = bgCount + 1 end
end
assert(bgCount == 1, "ApplyPixelBackdrop must still build its single BACKGROUND fill texture")

---------------------------------------------------------------------------
-- 3. Both paths went through the SAME code path: the shared counter advanced
--    once per path (verified above as +1 each). Confirm cumulative total.
---------------------------------------------------------------------------
assert(UIKit._buildEdgeTexturesCount == before + 2,
    "both border paths must funnel through the single shared BuildEdgeTextures helper")

print("OK: uikit_dedup_test")
