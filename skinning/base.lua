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
local frameBackdrops = setmetatable({}, { __mode = "k" })

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
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
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
    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
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
local skinnedFrames = setmetatable({}, { __mode = "k" })
local styledFrames = setmetatable({}, { __mode = "k" })

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
local frameData = setmetatable({}, { __mode = "k" })

function SkinBase.SetFrameData(frame, key, value)
    if not frameData[frame] then frameData[frame] = {} end
    frameData[frame][key] = value
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

