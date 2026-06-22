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
-- So skinning WorldMapFrame == skinning its BorderFrame, plus hiding the
-- BorderFrame.Underlay texture and the InsetBorderTop separator.
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
    -- Recolor via the shared persistence helper (same idiom as achievement/weeklyrewards),
    -- rather than re-driving ApplyPixelBackdrop on the already-managed backdrop child.
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.SetBackdropColors(backdrop, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

-- Quest-log rows (QuestScrollFrame) are FramePool-pooled (QuestMapFrame.lua:
-- titleFramePool / objectiveFramePool) and Blizzard re-applies their font
-- OBJECT + difficulty color on every QuestLogQuests_Update / hover, reverting a
-- one-shot SkinFrameText. After each layout pass, lock the active pool rows so
-- the QUI face survives (fontOnly keeps Blizzard's readable difficulty colors).
-- A pooled quest row only SetText's its fontstrings on bind (Blizzard never
-- re-CALLS SetFontObject), so the QUI face must be APPLIED (SkinFrameText) on
-- each cold-acquired row, then locked.
local function styleQuestRow(f)
    SkinBase.SkinFrameText(f, { recurse = true })
    SkinBase.LockFrameTextObjects(f, 2)
end

-- Section-header rows are BUTTONS with a declared HighlightFont: the engine swaps
-- to the highlight font OBJECT on hover with no setter call, so also drive the
-- button font objects (LockFrameTextObjects alone can't beat the object-swap).
local function styleQuestHeader(f)
    SkinBase.SkinFrameText(f, { recurse = true })
    SkinBase.LockFrameTextObjects(f, 2)
    SkinBase.ApplyButtonFontObjects(f)
end

local function eachActive(pool, fn)
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do fn(f) end
    end
end

local function LockActiveQuestLogRows()
    local sf = _G.QuestScrollFrame
    if not sf then return end
    eachActive(sf.titleFramePool, styleQuestRow)
    eachActive(sf.objectiveFramePool, styleQuestRow)
    eachActive(sf.headerFramePool, styleQuestHeader)
    eachActive(sf.campaignHeaderFramePool, styleQuestHeader)
    eachActive(sf.campaignHeaderMinimalFramePool, styleQuestHeader)
    eachActive(sf.covenantCallingsHeaderFramePool, styleQuestHeader)
end

local function HookQuestLogText(frame)
    if SkinBase.GetFrameData(frame, "qQuestLogTextHooked") then return end
    if type(_G.QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", LockActiveQuestLogRows)
        SkinBase.SetFrameData(frame, "qQuestLogTextHooked", true)
    end
    LockActiveQuestLogRows()
end

local function SkinWorldMap()
    if not IsSettingEnabled("skinWorldMap") then return end
    local frame = _G.WorldMapFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    -- BorderFrame carries the PortraitFrameTemplateMinimizable chrome.
    -- The shared helper handles chrome strip + backdrop + close button.
    -- BorderFrame is frameStrata="HIGH"; raise ScrollContainer and overlay
    -- controls to that strata so they stay above the full-frame skinned
    -- backdrop while title controls remain above the canvas at
    -- MAP_OVERLAY_FRAME_LEVEL (200).
    if frame.BorderFrame then
        SkinBase.SkinButtonFrameTemplate(frame.BorderFrame)
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
        if frame.BorderFrame.Underlay then frame.BorderFrame.Underlay:Hide() end
        if frame.BorderFrame.InsetBorderTop then frame.BorderFrame.InsetBorderTop:Hide() end
    end

    RaiseMapCanvas(frame)

    SkinBase.SkinFrameText(frame, { recurse = true })
    HookQuestLogText(frame)
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

SkinBase.OnAddOnLoaded("Blizzard_WorldMap", SkinWorldMap, 0)

---------------------------------------------------------------------------
-- FlightMapFrame (taxi map) — same MapCanvasFrameTemplate split as WorldMap:
-- its BorderFrame carries the PortraitFrameTemplate chrome. LOD: Blizzard_FlightMap.
---------------------------------------------------------------------------
local function SkinFlightMap()
    if not IsSettingEnabled("skinFlightMap") then return end
    local frame = _G.FlightMapFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    if frame.BorderFrame then
        SkinBase.SkinButtonFrameTemplate(frame.BorderFrame)
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
        if frame.BorderFrame.Underlay then frame.BorderFrame.Underlay:Hide() end
        if frame.BorderFrame.InsetBorderTop then frame.BorderFrame.InsetBorderTop:Hide() end
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshFlightMap()
    local frame = _G.FlightMapFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end
    if frame.BorderFrame then
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
    end
end
if ns.Registry then
    ns.Registry:Register("skinFlightMap", {
        refresh = RefreshFlightMap,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_FlightMap", SkinFlightMap, 0)
