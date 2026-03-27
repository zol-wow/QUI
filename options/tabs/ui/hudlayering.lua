local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers

-- Local references for shared infrastructure
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent

local GetCore = Helpers.GetCore

--------------------------------------------------------------------------------
-- HUD LAYERING PAGE
--------------------------------------------------------------------------------
local CreateCollapsiblePage = Shared.CreateCollapsiblePage

local function CreateHUDLayeringPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local PAD = PADDING
    local FORM_ROW = 32
    local P = Helpers.PlaceRow

    local core = GetCore()
    local db = core and core.db and core.db.profile

    local function GetLayeringDB()
        if not db then return nil end
        if not db.hudLayering then
            db.hudLayering = {
                essential = 5, utility = 5, buffIcon = 5,
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
        if _G.QUI_RefreshBuffBar then _G.QUI_RefreshBuffBar() end
    end
    local function RefreshPowerBars()
        local c = GetCore(); local d = c and c.db and c.db.profile
        if c and c.UpdatePowerBar then c:UpdatePowerBar() end
        if c and c.UpdateSecondaryPowerBar then c:UpdateSecondaryPowerBar() end
    end
    local function RefreshUnitFrames() if _G.QUI_RefreshUnitFrames then _G.QUI_RefreshUnitFrames() end end
    local function RefreshCastbars() if _G.QUI_RefreshCastbars then _G.QUI_RefreshCastbars() end end
    local function RefreshCustomTrackers() if _G.QUI_RefreshCustomTrackers then _G.QUI_RefreshCustomTrackers() end end
    local function RefreshSkyriding() if _G.QUI_RefreshSkyriding then _G.QUI_RefreshSkyriding() end end

    local layeringDB = GetLayeringDB()
    if not layeringDB then
        local errorLabel = GUI:CreateLabel(content, "Database not loaded. Please reload UI.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, -15)
        return scroll
    end

    -- Description
    local info = GUI:CreateLabel(content, "Control which HUD elements appear above others. Higher values render on top.", 11, C.textMuted)
    info:SetJustifyH("LEFT")
    info:SetPoint("TOPLEFT", PAD, -10)
    info:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local sections, relayout, CreateCollapsible = CreateCollapsiblePage(content, PAD, -38)

    -- CDM
    CreateCollapsible("Cooldown Display Manager", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormSlider(body, "Essential Viewer", 0, 10, 1, "essential", layeringDB, RefreshCDM), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Utility Viewer", 0, 10, 1, "utility", layeringDB, RefreshCDM), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Buff Icon Viewer", 0, 10, 1, "buffIcon", layeringDB, RefreshCDM), body, sy)
        P(GUI:CreateFormSlider(body, "Buff Bar Viewer", 0, 10, 1, "buffBar", layeringDB, RefreshCDM), body, sy)
    end)

    -- Power Bars
    CreateCollapsible("Power Bars", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormSlider(body, "Primary Power Bar", 0, 10, 1, "primaryPowerBar", layeringDB, RefreshPowerBars), body, sy)
        P(GUI:CreateFormSlider(body, "Secondary Power Bar", 0, 10, 1, "secondaryPowerBar", layeringDB, RefreshPowerBars), body, sy)
    end)

    -- Unit Frames
    CreateCollapsible("Unit Frames", 7 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormSlider(body, "Player Frame", 0, 10, 1, "playerFrame", layeringDB, RefreshUnitFrames), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Player Status Indicators", 0, 10, 1, "playerIndicators", layeringDB, RefreshUnitFrames), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Target Frame", 0, 10, 1, "targetFrame", layeringDB, RefreshUnitFrames), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Target of Target", 0, 10, 1, "totFrame", layeringDB, RefreshUnitFrames), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Pet Frame", 0, 10, 1, "petFrame", layeringDB, RefreshUnitFrames), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Focus Frame", 0, 10, 1, "focusFrame", layeringDB, RefreshUnitFrames), body, sy)
        P(GUI:CreateFormSlider(body, "Boss Frames", 0, 10, 1, "bossFrames", layeringDB, RefreshUnitFrames), body, sy)
    end)

    -- Castbars
    CreateCollapsible("Castbars", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormSlider(body, "Player Castbar", 0, 10, 1, "playerCastbar", layeringDB, RefreshCastbars), body, sy)
        P(GUI:CreateFormSlider(body, "Target Castbar", 0, 10, 1, "targetCastbar", layeringDB, RefreshCastbars), body, sy)
    end)

    -- Custom CDM Bars
    CreateCollapsible("Custom CDM Bars", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        P(GUI:CreateFormSlider(body, "Custom Item/Spell Bars", 0, 10, 1, "customBars", layeringDB, RefreshCustomTrackers), body, sy)
    end)

    -- Skyriding
    CreateCollapsible("Skyriding", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        P(GUI:CreateFormSlider(body, "Skyriding HUD", 0, 10, 1, "skyridingHUD", layeringDB, RefreshSkyriding), body, sy)
    end)

    relayout()

    return scroll
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_HUDLayeringOptions = {
    CreateHUDLayeringPage = CreateHUDLayeringPage
}
