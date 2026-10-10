local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function SkinPVPMatchContents(frame)
    local content = frame.Content or frame.content
    if content then
        SkinBase.StripTextures(content)
        local sr, sg, sb, sa = SkinBase.GetWindowColors()
        local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(content, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
        SkinBase.SkinTrimScrollBar(content.ScrollBar or content.scrollBar)
        local scroll = content.ScrollBox or content.scrollBox
        if scroll and not SkinBase.GetFrameData(scroll, "qPVPMatchRowFontsHooked") then
            SkinBase.HookScrollBoxRowFonts(scroll, 4)
            SkinBase.SetFrameData(scroll, "qPVPMatchRowFontsHooked", true)
        end
        local container = content.TabContainer or content.tabContainer
        if container then
            SkinBase.StripTextures(container)
            local group = container.TabGroup or container.tabGroup
            if group then
                local tabs = { group.Tab1 or group.tab1, group.Tab2 or group.tab2, group.Tab3 or group.tab3 }
                SkinBase.SkinTabGroup(tabs, frame, { resizeToText = true })
            end
        end
    end
    local buttons = frame.buttonContainer
    SkinBase.SkinButton(buttons and buttons.requeueButton, { strip = true, font = true })
    SkinBase.SkinButton(buttons and buttons.leaveButton, { strip = true, font = true })
end

local function SkinPVPMatchFrame(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { depth = 5 })
    SkinPVPMatchContents(frame)
    frame:HookScript("OnShow", SkinPVPMatchContents)
    SkinBase.MarkSkinned(frame)
end

local function SkinPVPMatch()
    if not IsSettingEnabled("skinPVPMatch") then return end
    SkinPVPMatchFrame(_G.PVPMatchScoreboard)
    SkinPVPMatchFrame(_G.PVPMatchResults)
end

local function RefreshPVPMatch()
    SkinBase.RefreshFrameBackdropColors(_G.PVPMatchScoreboard)
    SkinBase.RefreshFrameBackdropColors(_G.PVPMatchResults)
end
if ns.Registry then
    ns.Registry:Register("skinPVPMatch", {
        refresh = RefreshPVPMatch,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_PVPMatch", SkinPVPMatch, 0)
