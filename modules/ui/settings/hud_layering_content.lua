local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local PAD = (Shared and Shared.PADDING) or 15
local CreateScrollableContent = Shared.CreateScrollableContent

local GetCore = Helpers.GetCore

local MakeLayout = ns.QUI_ModulesSettingsLayout.MakeLayout
local row = ns.QUI_ModulesSettingsLayout.Row

--------------------------------------------------------------------------------
-- HUD LAYERING PAGE
--------------------------------------------------------------------------------
local function BuildHUDLayeringContent(content)
    GUI:SetSearchContext({tabIndex = 12, tabName = "Frame Levels"})

    local core = GetCore()
    local db = core and core.db and core.db.profile

    local function GetLayeringDB()
        if not db then return nil end
        if not db.hudLayering then
            db.hudLayering = {
                essential = 5, utility = 5, buffIcon = 5, buffBar = 5,
                primaryPowerBar = 7, secondaryPowerBar = 6,
                playerFrame = 4, targetFrame = 4, totFrame = 3, petFrame = 3, focusFrame = 4, bossFrames = 4,
                playerCastbar = 5, targetCastbar = 5,
                playerIndicators = 6,
                customBars = 5,
                skyridingHUD = 5,
            }
        end
        return db.hudLayering
    end

    local function RefreshCDM()
        if NCDM and NCDM.ApplySettings then NCDM:ApplySettings("essential"); NCDM:ApplySettings("utility") end
        if _G.QUI_RefreshCDMBuffLayout then _G.QUI_RefreshCDMBuffLayout() end
    end
    local function RefreshPowerBars()
        local c = GetCore()
        if c and c.UpdatePowerBar then c:UpdatePowerBar() end
        if c and c.UpdateSecondaryPowerBar then c:UpdateSecondaryPowerBar() end
    end
    local function RefreshUnitFrames() if _G.QUI_RefreshUnitFrames then _G.QUI_RefreshUnitFrames() end end
    local function RefreshCastbars() if _G.QUI_RefreshCastbars then _G.QUI_RefreshCastbars() end end
    local function RefreshCustomTrackers() if _G.QUI_RefreshCustomTrackers then _G.QUI_RefreshCustomTrackers() end end
    local function RefreshSkyriding() if _G.QUI_RefreshSkyriding then _G.QUI_RefreshSkyriding() end end

    local layeringDB = GetLayeringDB()
    if not layeringDB then
        local errorLabel = GUI:CreateLabel(content, ns.L["Database not loaded. Please reload UI."], 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, -15)
        content:SetHeight(80)
        return
    end

    -- Description (intro paragraph reserves 28px below the top before the first
    -- accent-dot header).
    local info = GUI:CreateLabel(content, ns.L["Control which HUD elements appear above others. Higher values render on top."], 11, C.textMuted)
    info:SetJustifyH("LEFT")
    info:SetPoint("TOPLEFT", PAD, -10)
    info:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local L = MakeLayout(content, -38)

    ---------------------------------------------------------------------------
    -- COOLDOWN DISPLAY MANAGER
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Cooldown Display Manager"])
    local sCDM = L.sectionAt()
    local cdmEssW = GUI:CreateFormSlider(sCDM.frame, nil, 0, 10, 1, "essential", layeringDB, RefreshCDM,
        { description = ns.L["Render layer for the Essential cooldowns viewer. Higher values draw over lower-layered HUD elements."] })
    local cdmUtilW = GUI:CreateFormSlider(sCDM.frame, nil, 0, 10, 1, "utility", layeringDB, RefreshCDM,
        { description = ns.L["Render layer for the Utility cooldowns viewer. Higher values draw over lower-layered HUD elements."] })
    sCDM.AddRow(
        row(sCDM.frame, ns.L["Essential Viewer"], cdmEssW),
        row(sCDM.frame, ns.L["Utility Viewer"], cdmUtilW)
    )

    local cdmBuffIconW = GUI:CreateFormSlider(sCDM.frame, nil, 0, 10, 1, "buffIcon", layeringDB, RefreshCDM,
        { description = ns.L["Render layer for the Buff Icon viewer. Raise this if buff icons are being hidden by other HUD pieces."] })
    local cdmBuffBarW = GUI:CreateFormSlider(sCDM.frame, nil, 0, 10, 1, "buffBar", layeringDB, RefreshCDM,
        { description = ns.L["Render layer for the Buff Bar viewer. Raise this if buff bars are being hidden by other HUD pieces."] })
    sCDM.AddRow(
        row(sCDM.frame, ns.L["Buff Icon Viewer"], cdmBuffIconW),
        row(sCDM.frame, ns.L["Buff Bar Viewer"], cdmBuffBarW)
    )
    L.closeSection(sCDM)

    ---------------------------------------------------------------------------
    -- POWER BARS
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Power Bars"])
    local sPB = L.sectionAt()
    local pbPrimaryW = GUI:CreateFormSlider(sPB.frame, nil, 0, 10, 1, "primaryPowerBar", layeringDB, RefreshPowerBars,
        { description = ns.L["Render layer for the primary resource bar (mana, rage, energy, etc.). Higher values draw over lower-layered HUD elements."] })
    local pbSecondaryW = GUI:CreateFormSlider(sPB.frame, nil, 0, 10, 1, "secondaryPowerBar", layeringDB, RefreshPowerBars,
        { description = ns.L["Render layer for the secondary resource bar (combo points, holy power, soul shards, etc.)."] })
    sPB.AddRow(
        row(sPB.frame, ns.L["Primary Power Bar"], pbPrimaryW),
        row(sPB.frame, ns.L["Secondary Power Bar"], pbSecondaryW)
    )
    L.closeSection(sPB)

    ---------------------------------------------------------------------------
    -- UNIT FRAMES
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Unit Frames"])
    local sUF = L.sectionAt()
    local ufPlayerW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "playerFrame", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for the player unit frame. Higher values draw over lower-layered HUD elements."] })
    local ufPlayerIndW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "playerIndicators", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for player status icons such as leader, PvP, combat, and resting indicators."] })
    sUF.AddRow(
        row(sUF.frame, ns.L["Player Frame"], ufPlayerW),
        row(sUF.frame, ns.L["Player Status Indicators"], ufPlayerIndW)
    )

    local ufTargetW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "targetFrame", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for the target unit frame. Higher values draw over lower-layered HUD elements."] })
    local ufTotW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "totFrame", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for the target of target frame."] })
    sUF.AddRow(
        row(sUF.frame, ns.L["Target Frame"], ufTargetW),
        row(sUF.frame, ns.L["Target of Target"], ufTotW)
    )

    local ufPetW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "petFrame", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for the pet unit frame."] })
    local ufFocusW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "focusFrame", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for the focus unit frame."] })
    sUF.AddRow(
        row(sUF.frame, ns.L["Pet Frame"], ufPetW),
        row(sUF.frame, ns.L["Focus Frame"], ufFocusW)
    )

    local ufBossW = GUI:CreateFormSlider(sUF.frame, nil, 0, 10, 1, "bossFrames", layeringDB, RefreshUnitFrames,
        { description = ns.L["Render layer for boss unit frames shown during encounters."] })
    sUF.AddRow(row(sUF.frame, ns.L["Boss Frames"], ufBossW))
    L.closeSection(sUF)

    ---------------------------------------------------------------------------
    -- CASTBARS
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Castbars"])
    local sCB = L.sectionAt()
    local cbPlayerW = GUI:CreateFormSlider(sCB.frame, nil, 0, 10, 1, "playerCastbar", layeringDB, RefreshCastbars,
        { description = ns.L["Render layer for the player castbar. Raise this if your castbar is being hidden behind other HUD elements."] })
    local cbTargetW = GUI:CreateFormSlider(sCB.frame, nil, 0, 10, 1, "targetCastbar", layeringDB, RefreshCastbars,
        { description = ns.L["Render layer for the target castbar. Raise this to keep enemy casts visible above other HUD elements."] })
    sCB.AddRow(
        row(sCB.frame, ns.L["Player Castbar"], cbPlayerW),
        row(sCB.frame, ns.L["Target Castbar"], cbTargetW)
    )
    L.closeSection(sCB)

    ---------------------------------------------------------------------------
    -- CUSTOM CDM BARS
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Custom CDM Bars"])
    local sCC = L.sectionAt()
    local ccW = GUI:CreateFormSlider(sCC.frame, nil, 0, 10, 1, "customBars", layeringDB, RefreshCustomTrackers,
        { description = ns.L["Render layer for custom item and spell tracker bars you've configured in the Cooldown Manager."] })
    sCC.AddRow(row(sCC.frame, ns.L["Custom Item/Spell Bars"], ccW))
    L.closeSection(sCC)

    ---------------------------------------------------------------------------
    -- SKYRIDING
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Skyriding"])
    local sSK = L.sectionAt()
    local skW = GUI:CreateFormSlider(sSK.frame, nil, 0, 10, 1, "skyridingHUD", layeringDB, RefreshSkyriding,
        { description = ns.L["Render layer for the skyriding vigor and dynamic flight HUD shown while mounted."] })
    sSK.AddRow(row(sSK.frame, ns.L["Skyriding HUD"], skW))
    L.closeSection(sSK)

    L.finish()
end

local function CreateHUDLayeringPage(parent)
    local _, content = CreateScrollableContent(parent)
    BuildHUDLayeringContent(content)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_HUDLayeringOptions = {
    BuildHUDLayeringContent = BuildHUDLayeringContent,
    CreateHUDLayeringPage = CreateHUDLayeringPage
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "frameLevelsPage",
        moverKey = "hudLayering",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 8 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildHUDLayeringContent,
            }),
        },
    }))
end
