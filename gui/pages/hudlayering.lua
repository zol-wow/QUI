local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references for shared infrastructure
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent

--------------------------------------------------------------------------------
-- HUD LAYERING PAGE
--------------------------------------------------------------------------------
local function CreateHUDLayeringPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local y = -15
    local PAD = PADDING
    local FORM_ROW = 32

    local QUICore = _G.QUI and _G.QUI.QUICore
    local db = QUICore and QUICore.db and QUICore.db.profile

    -- Helper to get hudLayering table (with fallback initialization)
    local function GetLayeringDB()
        if not db then return nil end
        if not db.hudLayering then
            db.hudLayering = {
                essential = 5, utility = 5, buffIcon = 5,
                primaryPowerBar = 7, secondaryPowerBar = 6,
                playerFrame = 4, targetFrame = 4, totFrame = 3, petFrame = 3, focusFrame = 4, bossFrames = 4,
                playerCastbar = 5, targetCastbar = 5,
                playerIndicators = 6,  -- Player frame indicator icons (rested, combat, stance)
                customBars = 5,
                skyridingHUD = 5,
            }
        end
        return db.hudLayering
    end

    -- Refresh functions for each component type
    local function RefreshCDM()
        if NCDM and NCDM.ApplySettings then
            NCDM:ApplySettings("essential")
            NCDM:ApplySettings("utility")
        end
        if _G.QUI_RefreshBuffBar then
            _G.QUI_RefreshBuffBar()
        end
    end

    local function RefreshPowerBars()
        if QUICore and QUICore.UpdatePowerBar then
            QUICore:UpdatePowerBar()
        end
        if QUICore and QUICore.UpdateSecondaryPowerBar then
            QUICore:UpdateSecondaryPowerBar()
        end
    end

    local function RefreshUnitFrames()
        if _G.QUI_RefreshUnitFrames then
            _G.QUI_RefreshUnitFrames()
        end
    end

    local function RefreshCastbars()
        if _G.QUI_RefreshCastbars then
            _G.QUI_RefreshCastbars()
        end
    end

    local function RefreshCustomTrackers()
        if _G.QUI_RefreshCustomTrackers then
            _G.QUI_RefreshCustomTrackers()
        end
    end

    local function RefreshSkyriding()
        if _G.QUI_RefreshSkyriding then
            _G.QUI_RefreshSkyriding()
        end
    end

    -- Header description
    local info = GUI:CreateLabel(content, "Control which HUD elements appear above others. Higher values render on top of lower values.", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    local layeringDB = GetLayeringDB()
    if not layeringDB then
        local errorLabel = GUI:CreateLabel(content, "Database not loaded. Please reload UI.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, y)
        return scroll
    end

    -- =====================================================
    -- COOLDOWN DISPLAY MANAGER SECTION
    -- =====================================================
    local cdmHeader = GUI:CreateSectionHeader(content, "Cooldown Display Manager")
    cdmHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - cdmHeader.gap

    local essentialSlider = GUI:CreateFormSlider(content, "Essential Viewer", 0, 10, 1, "essential", layeringDB, RefreshCDM)
    essentialSlider:SetPoint("TOPLEFT", PAD, y)
    essentialSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local utilitySlider = GUI:CreateFormSlider(content, "Utility Viewer", 0, 10, 1, "utility", layeringDB, RefreshCDM)
    utilitySlider:SetPoint("TOPLEFT", PAD, y)
    utilitySlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local buffIconSlider = GUI:CreateFormSlider(content, "Buff Icon Viewer", 0, 10, 1, "buffIcon", layeringDB, RefreshCDM)
    buffIconSlider:SetPoint("TOPLEFT", PAD, y)
    buffIconSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local buffBarSlider = GUI:CreateFormSlider(content, "Buff Bar Viewer", 0, 10, 1, "buffBar", layeringDB, RefreshCDM)
    buffBarSlider:SetPoint("TOPLEFT", PAD, y)
    buffBarSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10  -- Section spacing

    -- =====================================================
    -- POWER BARS SECTION
    -- =====================================================
    local powerHeader = GUI:CreateSectionHeader(content, "Power Bars")
    powerHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - powerHeader.gap

    local primaryPowerSlider = GUI:CreateFormSlider(content, "Primary Power Bar", 0, 10, 1, "primaryPowerBar", layeringDB, RefreshPowerBars)
    primaryPowerSlider:SetPoint("TOPLEFT", PAD, y)
    primaryPowerSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local secondaryPowerSlider = GUI:CreateFormSlider(content, "Secondary Power Bar", 0, 10, 1, "secondaryPowerBar", layeringDB, RefreshPowerBars)
    secondaryPowerSlider:SetPoint("TOPLEFT", PAD, y)
    secondaryPowerSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10  -- Section spacing

    -- =====================================================
    -- UNIT FRAMES SECTION
    -- =====================================================
    local ufHeader = GUI:CreateSectionHeader(content, "Unit Frames")
    ufHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - ufHeader.gap

    local playerFrameSlider = GUI:CreateFormSlider(content, "Player Frame", 0, 10, 1, "playerFrame", layeringDB, RefreshUnitFrames)
    playerFrameSlider:SetPoint("TOPLEFT", PAD, y)
    playerFrameSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local playerIndicatorsSlider = GUI:CreateFormSlider(content, "Player Status Indicators", 0, 10, 1, "playerIndicators", layeringDB, RefreshUnitFrames)
    playerIndicatorsSlider:SetPoint("TOPLEFT", PAD, y)
    playerIndicatorsSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local targetFrameSlider = GUI:CreateFormSlider(content, "Target Frame", 0, 10, 1, "targetFrame", layeringDB, RefreshUnitFrames)
    targetFrameSlider:SetPoint("TOPLEFT", PAD, y)
    targetFrameSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local totFrameSlider = GUI:CreateFormSlider(content, "Target of Target", 0, 10, 1, "totFrame", layeringDB, RefreshUnitFrames)
    totFrameSlider:SetPoint("TOPLEFT", PAD, y)
    totFrameSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local petFrameSlider = GUI:CreateFormSlider(content, "Pet Frame", 0, 10, 1, "petFrame", layeringDB, RefreshUnitFrames)
    petFrameSlider:SetPoint("TOPLEFT", PAD, y)
    petFrameSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local focusFrameSlider = GUI:CreateFormSlider(content, "Focus Frame", 0, 10, 1, "focusFrame", layeringDB, RefreshUnitFrames)
    focusFrameSlider:SetPoint("TOPLEFT", PAD, y)
    focusFrameSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local bossFramesSlider = GUI:CreateFormSlider(content, "Boss Frames", 0, 10, 1, "bossFrames", layeringDB, RefreshUnitFrames)
    bossFramesSlider:SetPoint("TOPLEFT", PAD, y)
    bossFramesSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10  -- Section spacing

    -- =====================================================
    -- CASTBARS SECTION
    -- =====================================================
    local castbarHeader = GUI:CreateSectionHeader(content, "Castbars")
    castbarHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - castbarHeader.gap

    local playerCastbarSlider = GUI:CreateFormSlider(content, "Player Castbar", 0, 10, 1, "playerCastbar", layeringDB, RefreshCastbars)
    playerCastbarSlider:SetPoint("TOPLEFT", PAD, y)
    playerCastbarSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local targetCastbarSlider = GUI:CreateFormSlider(content, "Target Castbar", 0, 10, 1, "targetCastbar", layeringDB, RefreshCastbars)
    targetCastbarSlider:SetPoint("TOPLEFT", PAD, y)
    targetCastbarSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10  -- Section spacing

    -- =====================================================
    -- CUSTOM TRACKERS SECTION
    -- =====================================================
    local customHeader = GUI:CreateSectionHeader(content, "Custom Trackers")
    customHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - customHeader.gap

    local customBarsSlider = GUI:CreateFormSlider(content, "Custom Item/Spell Bars", 0, 10, 1, "customBars", layeringDB, RefreshCustomTrackers)
    customBarsSlider:SetPoint("TOPLEFT", PAD, y)
    customBarsSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10  -- Section spacing

    -- =====================================================
    -- SKYRIDING SECTION
    -- =====================================================
    local skyridingHeader = GUI:CreateSectionHeader(content, "Skyriding")
    skyridingHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - skyridingHeader.gap

    local skyridingSlider = GUI:CreateFormSlider(content, "Skyriding HUD", 0, 10, 1, "skyridingHUD", layeringDB, RefreshSkyriding)
    skyridingSlider:SetPoint("TOPLEFT", PAD, y)
    skyridingSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Set content height
    content:SetHeight(math.abs(y) + 20)

    return scroll
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_HUDLayeringOptions = {
    CreateHUDLayeringPage = CreateHUDLayeringPage
}
