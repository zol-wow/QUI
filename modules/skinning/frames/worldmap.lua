local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
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
    SkinBase.SetBackdropColors(backdrop, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

local function styleQuestHeader(f)
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

    if frame.BorderFrame then
        SkinBase.SkinButtonFrameTemplate(frame.BorderFrame)
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
        if frame.BorderFrame.Underlay then frame.BorderFrame.Underlay:Hide() end
        if frame.BorderFrame.InsetBorderTop then frame.BorderFrame.InsetBorderTop:Hide() end
    end

    RaiseMapCanvas(frame)

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

    RaiseMapCanvas(frame)

    SkinBase.MarkSkinned(frame)
end

local function RefreshFlightMap()
    local frame = _G.FlightMapFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end
    if frame.BorderFrame then
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
    end
    RaiseMapCanvas(frame)
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
