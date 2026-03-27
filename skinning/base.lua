---------------------------------------------------------------------------
-- QUI Skinning Base
-- Shared utilities for all skinning modules.
-- Loaded first via skinning.xml so all skinning files can reference ns.SkinBase.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local SkinBase = {}
ns.SkinBase = SkinBase

-- Weak-keyed table to store backdrop references WITHOUT writing to Blizzard frames
-- All code that previously used frame.quiBackdrop should use SkinBase.GetBackdrop(frame) instead
local frameBackdrops = Helpers.CreateStateTable()

---------------------------------------------------------------------------
-- GetPixelSize(frame, default)
-- Returns the pixel-perfect edge size for the given frame.
---------------------------------------------------------------------------
function SkinBase.GetPixelSize(frame, default)
    local core = Helpers.GetCore()
    if core and type(core.GetPixelSize) == "function" then
        local px = core:GetPixelSize(frame)
        if type(px) == "number" and px > 0 then
            return px
        end
    end
    return default or 1
end

---------------------------------------------------------------------------
-- GetSkinColors()
-- Returns accent + background colors: sr, sg, sb, sa, bgr, bgg, bgb, bga
---------------------------------------------------------------------------
function SkinBase.GetSkinColors(moduleSettings, prefix)
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

function SkinBase.GetSkinBarColor(moduleSettings, prefix)
    return Helpers.GetSkinBarColor(moduleSettings, prefix)
end

---------------------------------------------------------------------------
-- CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Creates (or updates) a pixel-perfect QUI backdrop on the given frame.
-- Stores the backdrop in a local weak-keyed table (NOT on the frame itself)
-- to avoid tainting Blizzard frames in Midnight's taint model.
-- Use SkinBase.GetBackdrop(frame) to retrieve the backdrop.
---------------------------------------------------------------------------
function SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frameBackdrops[frame] then
        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:EnableMouse(false)
        frameBackdrops[frame] = backdrop
    end

    local backdrop = frameBackdrops[frame]
    local px = SkinBase.GetPixelSize(backdrop, 1)
    -- Store backup color fields so third-party frame cleanup recognizes this
    -- as a QUI-owned frame and skips it during orphan/NineSlice suppression.
    backdrop._quiBgR = bgr or 0.05
    backdrop._quiBgG = bgg or 0.05
    backdrop._quiBgB = bgb or 0.05
    backdrop._quiBgA = bga or 0.95
    backdrop._quiBorderR = sr or 0
    backdrop._quiBorderG = sg or 0
    backdrop._quiBorderB = sb or 0
    backdrop._quiBorderA = sa or 1
    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    backdrop:SetBackdropColor(backdrop._quiBgR, backdrop._quiBgG, backdrop._quiBgB, backdrop._quiBgA)
    backdrop:SetBackdropBorderColor(backdrop._quiBorderR, backdrop._quiBorderG, backdrop._quiBorderB, backdrop._quiBorderA)
end

---------------------------------------------------------------------------
-- ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Applies a pixel-perfect backdrop directly to a BackdropTemplate frame.
-- Unlike CreateBackdrop, this sets the backdrop on the frame itself
-- (for frames that already have BackdropTemplate or are addon-owned).
---------------------------------------------------------------------------
function SkinBase.ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end
    local px = SkinBase.GetPixelSize(frame, 1)
    -- Store backup color fields so third-party frame cleanup recognizes this
    -- as a QUI-owned frame and skips it during orphan/NineSlice suppression.
    frame._quiBgR = bgr or 0.05
    frame._quiBgG = bgg or 0.05
    frame._quiBgB = bgb or 0.05
    frame._quiBgA = bga or 0.95
    frame._quiBorderR = sr or 0
    frame._quiBorderG = sg or 0
    frame._quiBorderB = sb or 0
    frame._quiBorderA = sa or 1
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    frame:SetBackdropColor(frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA)
    frame:SetBackdropBorderColor(frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA)
end

---------------------------------------------------------------------------
-- GetBackdrop(frame)
-- Returns the QUI backdrop for a frame, or nil if none exists.
---------------------------------------------------------------------------
function SkinBase.GetBackdrop(frame)
    return frameBackdrops[frame]
end

---------------------------------------------------------------------------
-- Skinning state tracking (shared across all skinning modules)
-- Replaces frame.quiSkinned / frame.quiStyled / frame.quiBackdrop writes
-- which taint Blizzard frames in Midnight's taint model.
---------------------------------------------------------------------------
local skinnedFrames = Helpers.CreateStateTable()
local styledFrames = Helpers.CreateStateTable()

-- Mark a frame as skinned (replaces frame.quiSkinned = true)
function SkinBase.MarkSkinned(frame)
    skinnedFrames[frame] = true
end

-- Check if a frame has been skinned (replaces frame.quiSkinned check)
function SkinBase.IsSkinned(frame)
    return skinnedFrames[frame]
end

-- Mark a frame as styled (replaces frame.quiStyled = true)
function SkinBase.MarkStyled(frame)
    styledFrames[frame] = true
end

-- Check if a frame has been styled (replaces frame.quiStyled check)
function SkinBase.IsStyled(frame)
    return styledFrames[frame]
end

-- Store arbitrary per-frame data (replaces frame.quiXxx = value)
local frameData, getFrameData = Helpers.CreateStateTable()

function SkinBase.SetFrameData(frame, key, value)
    getFrameData(frame)[key] = value
end

function SkinBase.GetFrameData(frame, key)
    local data = frameData[frame]
    return data and data[key]
end

---------------------------------------------------------------------------
-- StripTextures(frame)
-- Hides all Texture regions on a frame (alpha → 0).
---------------------------------------------------------------------------
function SkinBase.StripTextures(frame)
    if not frame then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Global OnBackdropSizeChanged fix
-- BackdropTemplateMixin.SetupPieceVisuals re-creates backdrop texture pieces
-- with default white vertex color but does NOT re-apply the stored
-- backdropColor/backdropBorderColor. This hook ensures colors are always
-- re-applied after piece recreation on ANY BackdropTemplate frame.
---------------------------------------------------------------------------
if BackdropTemplateMixin and BackdropTemplateMixin.OnBackdropSizeChanged then
    hooksecurefunc(BackdropTemplateMixin, "OnBackdropSizeChanged", function(self)
        -- Fast exit for frames with no stored colors (most Blizzard frames).
        -- Without this guard the hook fires for EVERY BackdropTemplate resize
        -- in the entire UI — hundreds of times/sec in raids.
        if not self.backdropColor and not self._quiBgR
           and not self.backdropBorderColor and not self._quiBorderR then
            return
        end
        if self.backdropColor then
            pcall(self.SetBackdropColor, self, self.backdropColor:GetRGBA())
        elseif self._quiBgR then
            pcall(self.SetBackdropColor, self, self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA or 1)
        end
        if self.backdropBorderColor then
            pcall(self.SetBackdropBorderColor, self, self.backdropBorderColor:GetRGBA())
        elseif self._quiBorderR then
            pcall(self.SetBackdropBorderColor, self, self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA or 1)
        end
    end)
end

