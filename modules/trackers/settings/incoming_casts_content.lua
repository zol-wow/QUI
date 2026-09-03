local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local PAD = (Shared and Shared.PADDING) or 15

local function GetDB()
    local db = Shared.GetDB()
    return db and db.incomingCasts
end

local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

local function placeHint(L, parent, text)
    local f = CreateFrame("Frame", nil, parent)
    local lbl = GUI:CreateLabel(f, text, 11, C.textMuted)
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    L.placeCustom(f, 22)
end

ns.QUI_IncomingCastsOptions = {}

function ns.QUI_IncomingCastsOptions.BuildIncomingCastsContent(content)
    local db = GetDB()

    if not db then
        local noData = GUI:CreateLabel(content, ns.L["Incoming Casts settings are not available. Please reload the UI."], 12, C.textMuted)
        noData:SetPoint("TOPLEFT", PAD, -20)
        content:SetHeight(80)
        return
    end

    local function Refresh()
        local IC = ns.QUI_IncomingCasts
        if IC and IC.Refresh then IC.Refresh() end
    end

    -- Settings changes only refresh an already-open preview; preview is
    -- started solely by the toggle button (it suppresses live casts, so it
    -- must not be switched on as a side effect of editing a slider).
    local function RefreshPreview()
        Refresh()
        local IC = ns.QUI_IncomingCasts
        if IC and IC.IsPreviewActive and IC.IsPreviewActive() then
            IC.EnablePreview()
        end
    end

    local L = MakeLayout(content)

    L.headerAt(ns.L["General"])
    local sGen = L.sectionAt()
    local genEnableW = GUI:CreateFormCheckbox(sGen.frame, nil, "enabled", db, Refresh,
        { description = ns.L["Show a row of icons for enemy casts that are currently targeting you."] })
    sGen.AddRow(row(sGen.frame, ns.L["Enable Incoming Casts"], genEnableW))
    L.closeSection(sGen)
    placeHint(L, content, ns.L["Casters are detected through their nameplates, so enemies without a visible nameplate cannot be shown. Enabling offscreen nameplates in the game's interface options improves coverage."])

    L.headerAt(ns.L["Icons"])
    local sIco = L.sectionAt()
    local icoSizeW = GUI:CreateFormSlider(sIco.frame, nil, 12, 96, 1, "iconSize", db, RefreshPreview,
        { description = ns.L["Size of each incoming cast icon in pixels."] })
    local icoMaxW = GUI:CreateFormSlider(sIco.frame, nil, 1, 10, 1, "maxIcons", db, RefreshPreview,
        { description = ns.L["Number of icon slots reserved in the layout and shown in preview. When more enemies are casting at once, extra slots extend past the reserved area so a cast aimed at you is never suppressed."] })
    sIco.AddRow(
        row(sIco.frame, ns.L["Icon Size"], icoSizeW),
        row(sIco.frame, ns.L["Max Icons"], icoMaxW)
    )

    local icoSpacingW = GUI:CreateFormSlider(sIco.frame, nil, 0, 32, 1, "spacing", db, RefreshPreview,
        { description = ns.L["Gap between incoming cast icons in pixels."] })
    local growOptions = {
        { value = "CENTER", text = ns.L["Centered"] },
        { value = "LEFT", text = ns.L["Left"] },
        { value = "RIGHT", text = ns.L["Right"] },
        { value = "UP", text = ns.L["Up"] },
        { value = "DOWN", text = ns.L["Down"] },
    }
    local icoGrowW = GUI:CreateFormDropdown(sIco.frame, nil, growOptions, "growDirection", db, RefreshPreview,
        { description = ns.L["Direction in which additional icons are added. Each cast keeps its position for its whole duration. Centered places the first cast on the anchor and later casts alternating right and left of it."] })
    sIco.AddRow(
        row(sIco.frame, ns.L["Icon Spacing"], icoSpacingW),
        row(sIco.frame, ns.L["Growth Direction"], icoGrowW)
    )

    local icoCollapseW = GUI:CreateFormCheckbox(sIco.frame, nil, "collapseGaps", db, RefreshPreview,
        { description = ns.L["Shrink hidden icons when target information is readable so visible casts pack together. Restricted target data keeps fixed-width gaps."] })
    sIco.AddRow(row(sIco.frame, ns.L["Collapse Hidden Icons"], icoCollapseW))

    local icoSwipeW = GUI:CreateFormCheckbox(sIco.frame, nil, "showSwipe", db, RefreshPreview,
        { description = ns.L["Darken the icon with a cooldown swipe that tracks the remaining cast time."] })
    local icoReverseW = GUI:CreateFormCheckbox(sIco.frame, nil, "reverseSwipe", db, RefreshPreview,
        { description = ns.L["Reverse the direction of the cooldown swipe animation."] })
    sIco.AddRow(
        row(sIco.frame, ns.L["Show Cooldown Swipe"], icoSwipeW),
        row(sIco.frame, ns.L["Reverse Swipe"], icoReverseW)
    )

    local icoTextW = GUI:CreateFormCheckbox(sIco.frame, nil, "showCooldownText", db, RefreshPreview,
        { description = ns.L["Show the remaining cast time as countdown text on the icon."] })
    sIco.AddRow(row(sIco.frame, ns.L["Show Countdown Text"], icoTextW))
    L.closeSection(sIco)

    L.headerAt(ns.L["Border"])
    local sBD = L.sectionAt()
    local bdSizeW = GUI:CreateFormSlider(sBD.frame, nil, 0, 4, 1, "borderSize", db, RefreshPreview,
        { description = ns.L["Thickness of the icon border in pixels. 0 removes the border entirely."] })
    sBD.AddRow(row(sBD.frame, ns.L["Border Size"], bdSizeW))
    if ns.QUI_BorderControl then
        local srcW, colW = ns.QUI_BorderControl.Attach(GUI, sBD.frame, db, "", RefreshPreview,
            { label = ns.L["Border Color Source"], colorLabel = ns.L["Border Color"] })
        sBD.AddRow(row(sBD.frame, ns.L["Border Color Source"], srcW), row(sBD.frame, ns.L["Border Color"], colW))
    end
    L.closeSection(sBD)

    local previewSection = CreateFrame("Frame", nil, content)
    local previewBtn = GUI:CreateButton(previewSection, ns.L["Toggle Preview"], 140, 28, function()
        local IC = ns.QUI_IncomingCasts
        if not IC then return end
        if IC.IsPreviewActive and IC.IsPreviewActive() then
            IC.DisablePreview()
        else
            IC.EnablePreview()
        end
    end)
    previewBtn:SetPoint("TOPLEFT", 0, -6)
    L.placeCustom(previewSection, 40)

    L.finish()
end

if Registry and Schema and RenderAdapters
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "incomingCastsPage",
        moverKey = "incomingCasts",
        lookupKeys = { "incomingCasts" },
        category = "frames",
        nav = { tileId = "auras", subPageIndex = 7 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = ns.QUI_IncomingCastsOptions.BuildIncomingCastsContent,
            }),
        },
        render = {
            layout = function(host, options)
                return RenderAdapters.RenderLayoutRoute(host, options and options.providerKey or "incomingCasts")
            end,
        },
    }))
end
