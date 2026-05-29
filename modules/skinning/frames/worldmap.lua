---------------------------------------------------------------------------
-- WORLD MAP FRAME SKINNING
--
-- WorldMapFrame's chrome is split into two parts per
-- Blizzard_WorldMap/Blizzard_WorldMap.xml:28-:
--   - WorldMapFrame itself inherits MapCanvasFrameTemplate (just the scroll
--     container + canvas — no decorative chrome).
--   - WorldMapFrame.BorderFrame inherits PortraitFrameTemplateMinimizable,
--     which is what carries NineSlice / Bg / TopTileStreaks / PortraitContainer
--     / TitleContainer / CloseButton / MaximizeMinimizeFrame.
--
-- So skinning WorldMapFrame == skinning its BorderFrame, plus killing the
-- BlackoutFrame dim overlay and the InsetBorderTop separator.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore
local MAP_CANVAS_FRAME_LEVEL = 100
local MAP_OVERLAY_FRAME_LEVEL = 200

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function RaiseFrame(frame, frameLevel)
    if not frame then return end
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(frameLevel)
end

local function RaiseMapCanvas(frame)
    if not frame then return end

    RaiseFrame(frame.ScrollContainer, MAP_CANVAS_FRAME_LEVEL)

    if frame.overlayFrames then
        for _, overlayFrame in ipairs(frame.overlayFrames) do
            RaiseFrame(overlayFrame, MAP_OVERLAY_FRAME_LEVEL)
        end
    end

    RaiseFrame(frame.NavBar, MAP_OVERLAY_FRAME_LEVEL)
end

local function ApplyBorderBackdrop(backdrop)
    if not backdrop then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

local function SkinWorldMap()
    if not IsSettingEnabled("skinWorldMap") then return end
    local frame = _G.WorldMapFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    -- BorderFrame carries the PortraitFrameTemplateMinimizable chrome.
    -- The shared helper handles chrome strip + backdrop + close button.
    -- BorderFrame is frameStrata="HIGH"; raise ScrollContainer and overlay
    -- controls to that strata so they stay above the full-frame skinned
    -- backdrop while title controls remain above the canvas at frameLevel 510.
    if frame.BorderFrame then
        SkinBase.SkinButtonFrameTemplate(frame.BorderFrame)
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
        if frame.BorderFrame.Underlay then frame.BorderFrame.Underlay:Hide() end
        if frame.BorderFrame.InsetBorderTop then frame.BorderFrame.InsetBorderTop:Hide() end
    end

    RaiseMapCanvas(frame)

    SkinBase.MarkSkinned(frame)
end

local function RefreshWorldMap()
    local frame = _G.WorldMapFrame
    if not frame then return end
    if frame.BorderFrame then
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
    end
    RaiseMapCanvas(frame)
end

_G.QUI_RefreshWorldMapColors = RefreshWorldMap
if ns.Registry then
    ns.Registry:Register("skinWorldMap", {
        refresh = RefreshWorldMap,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_WorldMap", SkinWorldMap, 0.1)
