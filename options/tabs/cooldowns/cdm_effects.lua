--[[
    QUI Options - CDM Effects Sub-Tab
    BuildEffectsTab for Cooldown Manager > Effects sub-tab
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildEffectsTab(tabContent)
    local db = Shared.GetDB()
    local y = -10
    local FORM_ROW = 32
    local PAD = 10

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 6, subTabName = "Effects"})

    -- Refresh functions
    local function RefreshSwipe()
        if _G.QUI_RefreshCooldownSwipe then _G.QUI_RefreshCooldownSwipe() end
    end
    local function RefreshEffects()
        if _G.QUI_RefreshCooldownEffects then _G.QUI_RefreshCooldownEffects() end
    end
    local function RefreshGlows()
        if _G.QUI_RefreshCustomGlows then _G.QUI_RefreshCustomGlows() end
    end

    -- Initialize tables if needed
    if db then
        if not db.cooldownSwipe then db.cooldownSwipe = {} end
        if not db.cooldownEffects then db.cooldownEffects = {} end
        if not db.customGlow then db.customGlow = {} end
    end

    -- =====================================================
    -- COOLDOWN SWIPE
    -- =====================================================
    local swipeHeader = GUI:CreateSectionHeader(tabContent, "COOLDOWN SWIPE")
    swipeHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - swipeHeader.gap

    local swipeDesc = GUI:CreateLabel(tabContent, "Control which animations appear on CDM icons. Quazii's personal setup is to turn OFF all the below.", 11, C.textMuted)
    swipeDesc:SetPoint("TOPLEFT", PAD, y)
    swipeDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    swipeDesc:SetJustifyH("LEFT")
    y = y - 24

    if db and db.cooldownSwipe then
        local showCooldownSwipe = GUI:CreateFormCheckbox(tabContent, "Radial Darkening", "showCooldownSwipe", db.cooldownSwipe, RefreshSwipe)
        showCooldownSwipe:SetPoint("TOPLEFT", PAD, y)
        showCooldownSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
        local cdDesc = GUI:CreateLabel(tabContent, "The radial darkening of icons to signify how long more before a spell is ready again.", 10, C.textMuted)
        cdDesc:SetPoint("TOPLEFT", PAD, y + 4)
        cdDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        cdDesc:SetJustifyH("LEFT")
        y = y - 14

        local showGCDSwipe = GUI:CreateFormCheckbox(tabContent, "GCD Swipe", "showGCDSwipe", db.cooldownSwipe, RefreshSwipe)
        showGCDSwipe:SetPoint("TOPLEFT", PAD, y)
        showGCDSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
        local gcdDesc = GUI:CreateLabel(tabContent, "The quick ~1.5 second animation after pressing any ability (Global Cooldown)", 10, C.textMuted)
        gcdDesc:SetPoint("TOPLEFT", PAD, y + 4)
        gcdDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        gcdDesc:SetJustifyH("LEFT")
        y = y - 14

        local showBuffSwipe = GUI:CreateFormCheckbox(tabContent, "Buff Swipe on Essential/Utility", "showBuffSwipe", db.cooldownSwipe, RefreshSwipe)
        showBuffSwipe:SetPoint("TOPLEFT", PAD, y)
        showBuffSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
        local buffDesc = GUI:CreateLabel(tabContent, "Yellow radial overlay showing duration of aura on Essential and Utility icons", 10, C.textMuted)
        buffDesc:SetPoint("TOPLEFT", PAD, y + 4)
        buffDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        buffDesc:SetJustifyH("LEFT")
        y = y - 14

        local showBuffIconSwipe = GUI:CreateFormCheckbox(tabContent, "Buff Swipe on Buff Icons Bar", "showBuffIconSwipe", db.cooldownSwipe, RefreshSwipe)
        showBuffIconSwipe:SetPoint("TOPLEFT", PAD, y)
        showBuffIconSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
        local buffIconDesc = GUI:CreateLabel(tabContent, "Duration swipe on BuffIcon viewer only (procs, short buffs)", 10, C.textMuted)
        buffIconDesc:SetPoint("TOPLEFT", PAD, y + 4)
        buffIconDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        buffIconDesc:SetJustifyH("LEFT")
        y = y - 14

        local showRechargeEdge = GUI:CreateFormCheckbox(tabContent, "Recharge Edge", "showRechargeEdge", db.cooldownSwipe, RefreshSwipe)
        showRechargeEdge:SetPoint("TOPLEFT", PAD, y)
        showRechargeEdge:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
        local rechargeEdgeDesc = GUI:CreateLabel(tabContent, "Yellow radial line that shows cooldown recharge time. Note: This comes with a faint GCD swipe too.", 10, C.textMuted)
        rechargeEdgeDesc:SetPoint("TOPLEFT", PAD, y + 4)
        rechargeEdgeDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rechargeEdgeDesc:SetJustifyH("LEFT")
        y = y - 14
    end

    -- =====================================================
    -- COOLDOWN EFFECTS
    -- =====================================================
    local effectsHeader = GUI:CreateSectionHeader(tabContent, "COOLDOWN EFFECTS")
    effectsHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - effectsHeader.gap

    local effectsDesc = GUI:CreateLabel(tabContent, "Hides intrusive Blizzard effects: red flashes, golden proc glows, spell activation alerts.", 11, C.textMuted)
    effectsDesc:SetPoint("TOPLEFT", PAD, y)
    effectsDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    effectsDesc:SetJustifyH("LEFT")
    y = y - 24

    if db and db.cooldownEffects then
        local function PromptEffectsReload()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Changing cooldown effect visibility requires a UI reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end

        local hideEssentialEffects = GUI:CreateFormCheckbox(tabContent, "Hide on Essential Cooldowns", "hideEssential", db.cooldownEffects, PromptEffectsReload)
        hideEssentialEffects:SetPoint("TOPLEFT", PAD, y)
        hideEssentialEffects:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideUtilityEffects = GUI:CreateFormCheckbox(tabContent, "Hide on Utility Cooldowns", "hideUtility", db.cooldownEffects, PromptEffectsReload)
        hideUtilityEffects:SetPoint("TOPLEFT", PAD, y)
        hideUtilityEffects:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local effectsWarning = GUI:CreateLabel(tabContent, "Note: When toggled off, Blizzard's default effects will appear on top of your custom glows below.", 11, C.warning)
        effectsWarning:SetPoint("TOPLEFT", PAD, y)
        effectsWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        effectsWarning:SetJustifyH("LEFT")
        y = y - 24
    end

    local function CreateGlowSection(tabContent, sectionTitle, prefix, dbTable, y, refreshFn)
        local sectionHeader = GUI:CreateSectionHeader(tabContent, sectionTitle)
        sectionHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - sectionHeader.gap

        local sectionDesc = GUI:CreateLabel(tabContent, "Replace Blizzard's glow with a custom glow effect when abilities proc.", 11, C.textMuted)
        sectionDesc:SetPoint("TOPLEFT", PAD, y)
        sectionDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        sectionDesc:SetJustifyH("LEFT")
        y = y - 24

        if not dbTable then
            return y
        end

        local enabledKey = prefix .. "Enabled"
        local glowTypeKey = prefix .. "GlowType"
        local colorKey = prefix .. "Color"
        local linesKey = prefix .. "Lines"
        local thicknessKey = prefix .. "Thickness"
        local scaleKey = prefix .. "Scale"
        local frequencyKey = prefix .. "Frequency"
        local xOffsetKey = prefix .. "XOffset"
        local yOffsetKey = prefix .. "YOffset"

        local function UpdateWidgetState(widgets)
            local glowType = dbTable[glowTypeKey] or "Pixel Glow"
            local isPixel = glowType == "Pixel Glow"
            local isAutocast = glowType == "Autocast Shine"
            local isButton = glowType == "Button Glow"

            if widgets.lines then widgets.lines:SetEnabled(isPixel or isAutocast) end
            if widgets.thickness then widgets.thickness:SetEnabled(isPixel) end
            if widgets.scale then widgets.scale:SetEnabled(isAutocast) end
            if widgets.speed then widgets.speed:SetEnabled(true) end
            if widgets.xOffset then widgets.xOffset:SetEnabled(not isButton) end
            if widgets.yOffset then widgets.yOffset:SetEnabled(not isButton) end
        end

        -- Enable toggle
        local glowEnable = GUI:CreateFormCheckbox(tabContent, "Enable Custom Glow", enabledKey, dbTable, refreshFn)
        glowEnable:SetPoint("TOPLEFT", PAD, y)
        glowEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Glow Type dropdown
        local glowTypeOptions = {
            {value = "Pixel Glow", text = "Pixel Glow"},
            {value = "Autocast Shine", text = "Autocast Shine"},
        }

        -- Store references to conditional widgets for visibility updates
        local widgets = {}

        local glowTypeDropdown = GUI:CreateFormDropdown(tabContent, "Glow Type", glowTypeOptions, glowTypeKey, dbTable, function()
            if refreshFn then refreshFn() end
            UpdateWidgetState(widgets)
        end)
        glowTypeDropdown:SetPoint("TOPLEFT", PAD, y)
        glowTypeDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Color picker
        local glowColor = GUI:CreateFormColorPicker(tabContent, "Glow Color", colorKey, dbTable, refreshFn)
        glowColor:SetPoint("TOPLEFT", PAD, y)
        glowColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Lines
        local lines = GUI:CreateFormSlider(tabContent, "Lines", 1, 30, 1, linesKey, dbTable, refreshFn)
        lines:SetPoint("TOPLEFT", PAD, y)
        lines:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgets.lines = lines
        y = y - FORM_ROW

        -- Thickness
        local thickness = GUI:CreateFormSlider(tabContent, "Thickness", 1, 10, 1, thicknessKey, dbTable, refreshFn)
        thickness:SetPoint("TOPLEFT", PAD, y)
        thickness:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgets.thickness = thickness
        y = y - FORM_ROW

        -- Scale
        local scale = GUI:CreateFormSlider(tabContent, "Shine Scale", 0.5, 3.0, 0.1, scaleKey, dbTable, refreshFn)
        scale:SetPoint("TOPLEFT", PAD, y)
        scale:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgets.scale = scale
        y = y - FORM_ROW

        -- Animation Speed
        local speed = GUI:CreateFormSlider(tabContent, "Animation Speed", 0.1, 2.0, 0.05, frequencyKey, dbTable, refreshFn)
        speed:SetPoint("TOPLEFT", PAD, y)
        speed:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgets.speed = speed
        y = y - FORM_ROW

        -- X Offset
        local xOffset = GUI:CreateFormSlider(tabContent, "X Offset", -20, 20, 1, xOffsetKey, dbTable, refreshFn)
        xOffset:SetPoint("TOPLEFT", PAD, y)
        xOffset:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgets.xOffset = xOffset
        y = y - FORM_ROW

        -- Y Offset
        local yOffset = GUI:CreateFormSlider(tabContent, "Y Offset", -20, 20, 1, yOffsetKey, dbTable, refreshFn)
        yOffset:SetPoint("TOPLEFT", PAD, y)
        yOffset:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgets.yOffset = yOffset
        y = y - FORM_ROW

        -- Initial enable/disable state based on glow type
        UpdateWidgetState(widgets)

        return y
    end

    -- =====================================================
    -- CUSTOM GLOW - ESSENTIAL
    -- =====================================================
    y = CreateGlowSection(tabContent, "ESSENTIAL COOLDOWNS - CUSTOM GLOW", "essential", db.customGlow, y, RefreshGlows)

    -- =====================================================
    -- CUSTOM GLOW - UTILITY
    -- =====================================================
    y = CreateGlowSection(tabContent, "UTILITY COOLDOWNS - CUSTOM GLOW", "utility", db.customGlow, y, RefreshGlows)

    tabContent:SetHeight(math.abs(y) + 60)
end

-- Export
ns.QUI_CDMEffectsOptions = {
    BuildEffectsTab = BuildEffectsTab
}
