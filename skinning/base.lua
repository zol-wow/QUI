---------------------------------------------------------------------------
-- QUI Skinning Base
-- Shared utilities for all skinning modules.
-- Loaded first via skinning.xml so all skinning files can reference ns.SkinBase.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local SkinBase = {}
ns.SkinBase = SkinBase

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
function SkinBase.GetSkinColors()
    return Helpers.GetSkinColors()
end

---------------------------------------------------------------------------
-- CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Creates (or updates) a pixel-perfect QUI backdrop on the given frame.
-- Stores the backdrop as frame.quiBackdrop.
---------------------------------------------------------------------------
function SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame.quiBackdrop then
        frame.quiBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.quiBackdrop:SetAllPoints()
        frame.quiBackdrop:SetFrameLevel(frame:GetFrameLevel())
        frame.quiBackdrop:EnableMouse(false)
    end

    local px = SkinBase.GetPixelSize(frame.quiBackdrop, 1)
    frame.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
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

