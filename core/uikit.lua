---------------------------------------------------------------------------
-- QUI UIKit
-- Shared UI primitives for creating frames, borders, backgrounds, text
-- Eliminates duplicated factory functions across modules
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local UIKit = {}
ns.UIKit = UIKit

local LSM = LibStub("LibSharedMedia-3.0", true)
local Helpers = ns.Helpers
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

--- Lazily resolve QUICore (safe if called before main.lua loads)
local function GetCore()
    return ns.Addon
end

---------------------------------------------------------------------------
-- FONT
---------------------------------------------------------------------------

--- Resolve a named font via LibSharedMedia, falling back to the user's
--- general font setting, then to the WoW default.
--- @param fontName string|nil  LSM font name (e.g. "Quazii"). nil = use general setting.
--- @return string Font file path
function UIKit.ResolveFontPath(fontName)
    if fontName and LSM then
        local path = LSM:Fetch("font", fontName)
        if path then return path end
    end
    if Helpers and Helpers.GetGeneralFont then
        return Helpers.GetGeneralFont()
    end
    return DEFAULT_FONT
end

---------------------------------------------------------------------------
-- BACKDROP
---------------------------------------------------------------------------

--- Build a backdrop info table with optional LSM border texture.
--- @param borderTextureName string|nil  LSM border name, or nil/"None" for no edge
--- @param borderSizePixels number|nil   Border thickness in physical pixels
--- @param frame Frame|nil               Reference frame for pixel scaling
--- @return table Backdrop info suitable for SetBackdrop()
function UIKit.GetBackdropInfo(borderTextureName, borderSizePixels, frame)
    local QUICore = GetCore()
    local edgeFile = nil
    local edgeSize = 0

    if borderTextureName and borderTextureName ~= "None" and LSM then
        edgeFile = LSM:Fetch("border", borderTextureName)
        local rawSize = borderSizePixels or 1
        edgeSize = QUICore and QUICore:Pixels(rawSize, frame) or rawSize
    end

    local px = QUICore and QUICore:GetPixelSize(frame) or 1
    return {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = edgeFile,
        tile = false,
        tileSize = 0,
        edgeSize = edgeSize,
        insets = { left = 0, right = px, top = 0, bottom = px },
    }
end

---------------------------------------------------------------------------
-- BORDER LINES (pixel-perfect overlay textures)
---------------------------------------------------------------------------

--- Create 4 OVERLAY textures for solid pixel borders around a frame.
--- Stores the result on frame.borderLines; no-ops if already created.
--- @param frame Frame  The frame to add borders to
--- @return table  { top, bottom, left, right } texture handles
function UIKit.CreateBorderLines(frame)
    if frame.borderLines then return frame.borderLines end

    local borders = {}

    borders.top = frame:CreateTexture(nil, "OVERLAY")
    borders.top:SetColorTexture(0, 0, 0, 1)
    borders.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borders.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, 0)

    borders.bottom = frame:CreateTexture(nil, "OVERLAY")
    borders.bottom:SetColorTexture(0, 0, 0, 1)
    borders.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
    borders.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

    borders.left = frame:CreateTexture(nil, "OVERLAY")
    borders.left:SetColorTexture(0, 0, 0, 1)
    borders.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borders.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)

    borders.right = frame:CreateTexture(nil, "OVERLAY")
    borders.right:SetColorTexture(0, 0, 0, 1)
    borders.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borders.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)

    frame.borderLines = borders
    return borders
end

--- Size, color, and show/hide pixel border lines.
--- @param frame Frame             Frame with .borderLines
--- @param sizePixels number       Border thickness in physical pixels
--- @param r number                Red (0-1)
--- @param g number                Green (0-1)
--- @param b number                Blue (0-1)
--- @param a number|nil            Alpha (0-1), defaults to 1
--- @param hide boolean|nil        Force-hide all borders
function UIKit.UpdateBorderLines(frame, sizePixels, r, g, b, a, hide)
    local borders = frame.borderLines
    if not borders then return end

    if hide or sizePixels <= 0 then
        for _, line in pairs(borders) do
            line:Hide()
        end
        return
    end

    local QUICore = GetCore()
    local pxSize = QUICore and QUICore:Pixels(sizePixels, frame) or sizePixels

    borders.top:SetHeight(pxSize)
    borders.bottom:SetHeight(pxSize)
    borders.left:SetWidth(pxSize)
    borders.right:SetWidth(pxSize)

    borders.top:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    borders.bottom:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    borders.left:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    borders.right:SetColorTexture(r or 0, g or 0, b or 0, a or 1)

    for _, line in pairs(borders) do
        line:Show()
    end
end

---------------------------------------------------------------------------
-- TEXT
---------------------------------------------------------------------------

--- Create a FontString with sensible defaults.
--- @param parent Frame|Region     Parent frame or region
--- @param fontSize number         Font size in points
--- @param fontPath string|nil     Font file path (nil = general font)
--- @param fontOutline string|nil  Outline style ("OUTLINE", "THICKOUTLINE", "")
--- @param layer string|nil        Draw layer, defaults to "OVERLAY"
--- @return FontString
function UIKit.CreateText(parent, fontSize, fontPath, fontOutline, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    local path = fontPath or (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or DEFAULT_FONT
    local outline = fontOutline or (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    text:SetFont(path, fontSize, outline)
    text:SetTextColor(1, 1, 1, 1)
    text:SetWordWrap(false)
    return text
end

---------------------------------------------------------------------------
-- BACKGROUND
---------------------------------------------------------------------------

--- Create a BACKGROUND-layer texture filled with a solid color.
--- Uses WHITE8x8 + SetVertexColor so callers can update via SetVertexColor later.
--- @param parent Frame|Region     Parent frame
--- @param r number|nil            Red (default 0.149)
--- @param g number|nil            Green (default 0.149)
--- @param b number|nil            Blue (default 0.149)
--- @param a number|nil            Alpha (default 1)
--- @return Texture
function UIKit.CreateBackground(parent, r, g, b, a)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(r or 0.149, g or 0.149, b or 0.149, a or 1)
    return bg
end

---------------------------------------------------------------------------
-- BACKDROP BORDER
---------------------------------------------------------------------------

--- Create a BackdropTemplate frame used as a solid border around a parent.
--- The border frame is positioned to surround the parent with the given inset.
--- Callers may reposition or adjust frame level after creation.
--- @param parent Frame            Parent frame
--- @param borderSizePixels number Border thickness in physical pixels
--- @param r number|nil            Red (default 0)
--- @param g number|nil            Green (default 0)
--- @param b number|nil            Blue (default 0)
--- @param a number|nil            Alpha (default 1)
--- @return Frame  The border frame (also stored as parent.Border)
function UIKit.CreateBackdropBorder(parent, borderSizePixels, r, g, b, a)
    local QUICore = GetCore()
    local borderSize = QUICore and QUICore:Pixels(borderSizePixels, parent) or borderSizePixels

    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", parent, -borderSize, borderSize)
    border:SetPoint("BOTTOMRIGHT", parent, borderSize, -borderSize)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = borderSize,
    })
    border:SetBackdropBorderColor(r or 0, g or 0, b or 0, a or 1)

    parent.Border = border
    return border
end

---------------------------------------------------------------------------
-- ICON
---------------------------------------------------------------------------

--- Create an icon frame with a border texture and cropped artwork.
--- @param parent Frame            Parent/anchor frame
--- @param size number             Icon dimensions in virtual coords (width = height)
--- @param borderSizePixels number Border inset in physical pixels
--- @param r number|nil            Border red (default 0)
--- @param g number|nil            Border green (default 0)
--- @param b number|nil            Border blue (default 0)
--- @param a number|nil            Border alpha (default 1)
--- @return Frame  The icon frame; also sets parent.icon, parent.iconTexture, parent.iconBorder
function UIKit.CreateIcon(parent, size, borderSizePixels, r, g, b, a)
    local QUICore = GetCore()
    local borderSize = QUICore and QUICore:Pixels(borderSizePixels, parent) or borderSizePixels

    local iconFrame = CreateFrame("Frame", nil, parent)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    -- Border fills the iconFrame (background layer)
    local border = iconFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    border:SetAllPoints(iconFrame)
    iconFrame.border = border

    -- Icon texture inset by borderSize so border shows around it
    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", borderSize, -borderSize)
    iconTexture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -borderSize, borderSize)
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.texture = iconTexture

    parent.icon = iconFrame
    parent.iconTexture = iconTexture
    parent.iconBorder = border
    return iconFrame
end
