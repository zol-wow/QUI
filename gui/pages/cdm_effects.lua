--[[
    QUI Options - CDM GCD & Effects Page
    CreateCDEffectsPage for CDM GCD & Effects tab
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function CreateCDEffectsPage(parent)
    local scroll, content = Shared.CreateScrollableContent(parent)
    local db = Shared.GetDB()
    local y = -15
    local FORM_ROW = 32
    local PADDING = Shared.PADDING

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 7, tabName = "CDM GCD & Effects"})

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
    local swipeHeader = GUI:CreateSectionHeader(content, "COOLDOWN SWIPE")
    swipeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - swipeHeader.gap

    local swipeDesc = GUI:CreateLabel(content, "Control which animations appear on CDM icons. Quazii's personal setup is to turn OFF all the below.", 11, C.textMuted)
    swipeDesc:SetPoint("TOPLEFT", PADDING, y)
    swipeDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    swipeDesc:SetJustifyH("LEFT")
    y = y - 24

    if db and db.cooldownSwipe then
        local showCooldownSwipe = GUI:CreateFormCheckbox(content, "Radial Darkening", "showCooldownSwipe", db.cooldownSwipe, RefreshSwipe)
        showCooldownSwipe:SetPoint("TOPLEFT", PADDING, y)
        showCooldownSwipe:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
        local cdDesc = GUI:CreateLabel(content, "The radial darkening of icons to signify how long more before a spell is ready again.", 10, C.textMuted)
        cdDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        cdDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        cdDesc:SetJustifyH("LEFT")
        y = y - 14

        local showGCDSwipe = GUI:CreateFormCheckbox(content, "GCD Swipe", "showGCDSwipe", db.cooldownSwipe, RefreshSwipe)
        showGCDSwipe:SetPoint("TOPLEFT", PADDING, y)
        showGCDSwipe:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
        local gcdDesc = GUI:CreateLabel(content, "The quick ~1.5 second animation after pressing any ability (Global Cooldown)", 10, C.textMuted)
        gcdDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        gcdDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        gcdDesc:SetJustifyH("LEFT")
        y = y - 14

        local showBuffSwipe = GUI:CreateFormCheckbox(content, "Buff Swipe on Essential/Utility", "showBuffSwipe", db.cooldownSwipe, RefreshSwipe)
        showBuffSwipe:SetPoint("TOPLEFT", PADDING, y)
        showBuffSwipe:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
        local buffDesc = GUI:CreateLabel(content, "Yellow radial overlay showing duration of aura on Essential and Utility icons", 10, C.textMuted)
        buffDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        buffDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        buffDesc:SetJustifyH("LEFT")
        y = y - 14

        local showBuffIconSwipe = GUI:CreateFormCheckbox(content, "Buff Swipe on Buff Icons Bar", "showBuffIconSwipe", db.cooldownSwipe, RefreshSwipe)
        showBuffIconSwipe:SetPoint("TOPLEFT", PADDING, y)
        showBuffIconSwipe:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
        local buffIconDesc = GUI:CreateLabel(content, "Duration swipe on BuffIcon viewer only (procs, short buffs)", 10, C.textMuted)
        buffIconDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        buffIconDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        buffIconDesc:SetJustifyH("LEFT")
        y = y - 14

        local showRechargeEdge = GUI:CreateFormCheckbox(content, "Recharge Edge", "showRechargeEdge", db.cooldownSwipe, RefreshSwipe)
        showRechargeEdge:SetPoint("TOPLEFT", PADDING, y)
        showRechargeEdge:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
        local rechargeEdgeDesc = GUI:CreateLabel(content, "Yellow radial line that shows cooldown recharge time. Note: This comes with a faint GCD swipe too.", 10, C.textMuted)
        rechargeEdgeDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        rechargeEdgeDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        rechargeEdgeDesc:SetJustifyH("LEFT")
        y = y - 14
    end

    -- =====================================================
    -- COOLDOWN EFFECTS
    -- =====================================================
    local effectsHeader = GUI:CreateSectionHeader(content, "COOLDOWN EFFECTS")
    effectsHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - effectsHeader.gap

    local effectsDesc = GUI:CreateLabel(content, "Hides intrusive Blizzard effects: red flashes, golden proc glows, spell activation alerts.", 11, C.textMuted)
    effectsDesc:SetPoint("TOPLEFT", PADDING, y)
    effectsDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
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

        local hideEssentialEffects = GUI:CreateFormCheckbox(content, "Hide on Essential Cooldowns", "hideEssential", db.cooldownEffects, PromptEffectsReload)
        hideEssentialEffects:SetPoint("TOPLEFT", PADDING, y)
        hideEssentialEffects:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local hideUtilityEffects = GUI:CreateFormCheckbox(content, "Hide on Utility Cooldowns", "hideUtility", db.cooldownEffects, PromptEffectsReload)
        hideUtilityEffects:SetPoint("TOPLEFT", PADDING, y)
        hideUtilityEffects:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local effectsWarning = GUI:CreateLabel(content, "Note: When toggled off, Blizzard's default effects will appear on top of your custom glows below.", 11, C.warning)
        effectsWarning:SetPoint("TOPLEFT", PADDING, y)
        effectsWarning:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        effectsWarning:SetJustifyH("LEFT")
        y = y - 24
    end

    -- =====================================================
    -- CUSTOM GLOW - ESSENTIAL
    -- =====================================================
    local essentialGlowHeader = GUI:CreateSectionHeader(content, "ESSENTIAL COOLDOWNS - CUSTOM GLOW")
    essentialGlowHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - essentialGlowHeader.gap

    local essentialGlowDesc = GUI:CreateLabel(content, "Replace Blizzard's glow with a custom glow effect when abilities proc.", 11, C.textMuted)
    essentialGlowDesc:SetPoint("TOPLEFT", PADDING, y)
    essentialGlowDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    essentialGlowDesc:SetJustifyH("LEFT")
    y = y - 24

    if db and db.customGlow then
        -- Enable toggle
        local essentialGlowEnable = GUI:CreateFormCheckbox(content, "Enable Custom Glow", "essentialEnabled", db.customGlow, RefreshGlows)
        essentialGlowEnable:SetPoint("TOPLEFT", PADDING, y)
        essentialGlowEnable:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Glow Type dropdown
        local glowTypeOptions = {
            {value = "Pixel Glow", text = "Pixel Glow"},
            {value = "Autocast Shine", text = "Autocast Shine"},
        }

        -- Store references to conditional widgets for visibility updates
        local essentialWidgets = {}

        local essentialGlowType = GUI:CreateFormDropdown(content, "Glow Type", glowTypeOptions, "essentialGlowType", db.customGlow, function()
            RefreshGlows()
            local glowType = db.customGlow.essentialGlowType or "Pixel Glow"
            local isPixel = glowType == "Pixel Glow"
            local isAutocast = glowType == "Autocast Shine"
            local isButton = glowType == "Button Glow"

            if essentialWidgets.lines then essentialWidgets.lines:SetEnabled(isPixel or isAutocast) end
            if essentialWidgets.thickness then essentialWidgets.thickness:SetEnabled(isPixel) end
            if essentialWidgets.scale then essentialWidgets.scale:SetEnabled(isAutocast) end
            if essentialWidgets.speed then essentialWidgets.speed:SetEnabled(true) end
            if essentialWidgets.xOffset then essentialWidgets.xOffset:SetEnabled(not isButton) end
            if essentialWidgets.yOffset then essentialWidgets.yOffset:SetEnabled(not isButton) end
        end)
        essentialGlowType:SetPoint("TOPLEFT", PADDING, y)
        essentialGlowType:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Color picker
        local essentialGlowColor = GUI:CreateFormColorPicker(content, "Glow Color", "essentialColor", db.customGlow, RefreshGlows)
        essentialGlowColor:SetPoint("TOPLEFT", PADDING, y)
        essentialGlowColor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Lines
        local essentialLines = GUI:CreateFormSlider(content, "Lines", 1, 30, 1, "essentialLines", db.customGlow, RefreshGlows)
        essentialLines:SetPoint("TOPLEFT", PADDING, y)
        essentialLines:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        essentialWidgets.lines = essentialLines
        y = y - FORM_ROW

        -- Thickness
        local essentialThickness = GUI:CreateFormSlider(content, "Thickness", 1, 10, 1, "essentialThickness", db.customGlow, RefreshGlows)
        essentialThickness:SetPoint("TOPLEFT", PADDING, y)
        essentialThickness:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        essentialWidgets.thickness = essentialThickness
        y = y - FORM_ROW

        -- Scale
        local essentialScale = GUI:CreateFormSlider(content, "Shine Scale", 0.5, 3.0, 0.1, "essentialScale", db.customGlow, RefreshGlows)
        essentialScale:SetPoint("TOPLEFT", PADDING, y)
        essentialScale:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        essentialWidgets.scale = essentialScale
        y = y - FORM_ROW

        -- Animation Speed
        local essentialSpeed = GUI:CreateFormSlider(content, "Animation Speed", 0.1, 2.0, 0.05, "essentialFrequency", db.customGlow, RefreshGlows)
        essentialSpeed:SetPoint("TOPLEFT", PADDING, y)
        essentialSpeed:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        essentialWidgets.speed = essentialSpeed
        y = y - FORM_ROW

        -- X Offset
        local essentialXOffset = GUI:CreateFormSlider(content, "X Offset", -20, 20, 1, "essentialXOffset", db.customGlow, RefreshGlows)
        essentialXOffset:SetPoint("TOPLEFT", PADDING, y)
        essentialXOffset:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        essentialWidgets.xOffset = essentialXOffset
        y = y - FORM_ROW

        -- Y Offset
        local essentialYOffset = GUI:CreateFormSlider(content, "Y Offset", -20, 20, 1, "essentialYOffset", db.customGlow, RefreshGlows)
        essentialYOffset:SetPoint("TOPLEFT", PADDING, y)
        essentialYOffset:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        essentialWidgets.yOffset = essentialYOffset
        y = y - FORM_ROW

        -- Initial enable/disable state based on glow type
        local glowType = db.customGlow.essentialGlowType or "Pixel Glow"
        local isPixel = glowType == "Pixel Glow"
        local isAutocast = glowType == "Autocast Shine"
        local isButton = glowType == "Button Glow"

        essentialWidgets.lines:SetEnabled(isPixel or isAutocast)
        essentialWidgets.thickness:SetEnabled(isPixel)
        essentialWidgets.scale:SetEnabled(isAutocast)
        essentialWidgets.speed:SetEnabled(true)
        essentialWidgets.xOffset:SetEnabled(not isButton)
        essentialWidgets.yOffset:SetEnabled(not isButton)
    end

    -- =====================================================
    -- CUSTOM GLOW - UTILITY
    -- =====================================================
    local utilityGlowHeader = GUI:CreateSectionHeader(content, "UTILITY COOLDOWNS - CUSTOM GLOW")
    utilityGlowHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - utilityGlowHeader.gap

    local utilityGlowDesc = GUI:CreateLabel(content, "Replace Blizzard's glow with a custom glow effect when abilities proc.", 11, C.textMuted)
    utilityGlowDesc:SetPoint("TOPLEFT", PADDING, y)
    utilityGlowDesc:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    utilityGlowDesc:SetJustifyH("LEFT")
    y = y - 24

    if db and db.customGlow then
        -- Enable toggle
        local utilityGlowEnable = GUI:CreateFormCheckbox(content, "Enable Custom Glow", "utilityEnabled", db.customGlow, RefreshGlows)
        utilityGlowEnable:SetPoint("TOPLEFT", PADDING, y)
        utilityGlowEnable:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Glow Type dropdown
        local utilityGlowTypeOptions = {
            {value = "Pixel Glow", text = "Pixel Glow"},
            {value = "Autocast Shine", text = "Autocast Shine"},
        }

        -- Store references to conditional widgets for visibility updates
        local utilityWidgets = {}

        local utilityGlowType = GUI:CreateFormDropdown(content, "Glow Type", utilityGlowTypeOptions, "utilityGlowType", db.customGlow, function()
            RefreshGlows()
            local glowType = db.customGlow.utilityGlowType or "Pixel Glow"
            local isPixel = glowType == "Pixel Glow"
            local isAutocast = glowType == "Autocast Shine"
            local isButton = glowType == "Button Glow"

            if utilityWidgets.lines then utilityWidgets.lines:SetEnabled(isPixel or isAutocast) end
            if utilityWidgets.thickness then utilityWidgets.thickness:SetEnabled(isPixel) end
            if utilityWidgets.scale then utilityWidgets.scale:SetEnabled(isAutocast) end
            if utilityWidgets.speed then utilityWidgets.speed:SetEnabled(true) end
            if utilityWidgets.xOffset then utilityWidgets.xOffset:SetEnabled(not isButton) end
            if utilityWidgets.yOffset then utilityWidgets.yOffset:SetEnabled(not isButton) end
        end)
        utilityGlowType:SetPoint("TOPLEFT", PADDING, y)
        utilityGlowType:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Color picker
        local utilityGlowColor = GUI:CreateFormColorPicker(content, "Glow Color", "utilityColor", db.customGlow, RefreshGlows)
        utilityGlowColor:SetPoint("TOPLEFT", PADDING, y)
        utilityGlowColor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Lines
        local utilityLines = GUI:CreateFormSlider(content, "Lines", 1, 30, 1, "utilityLines", db.customGlow, RefreshGlows)
        utilityLines:SetPoint("TOPLEFT", PADDING, y)
        utilityLines:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        utilityWidgets.lines = utilityLines
        y = y - FORM_ROW

        -- Thickness
        local utilityThickness = GUI:CreateFormSlider(content, "Thickness", 1, 10, 1, "utilityThickness", db.customGlow, RefreshGlows)
        utilityThickness:SetPoint("TOPLEFT", PADDING, y)
        utilityThickness:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        utilityWidgets.thickness = utilityThickness
        y = y - FORM_ROW

        -- Scale
        local utilityScale = GUI:CreateFormSlider(content, "Shine Scale", 0.5, 3.0, 0.1, "utilityScale", db.customGlow, RefreshGlows)
        utilityScale:SetPoint("TOPLEFT", PADDING, y)
        utilityScale:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        utilityWidgets.scale = utilityScale
        y = y - FORM_ROW

        -- Animation Speed
        local utilitySpeed = GUI:CreateFormSlider(content, "Animation Speed", 0.1, 2.0, 0.05, "utilityFrequency", db.customGlow, RefreshGlows)
        utilitySpeed:SetPoint("TOPLEFT", PADDING, y)
        utilitySpeed:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        utilityWidgets.speed = utilitySpeed
        y = y - FORM_ROW

        -- X Offset
        local utilityXOffset = GUI:CreateFormSlider(content, "X Offset", -20, 20, 1, "utilityXOffset", db.customGlow, RefreshGlows)
        utilityXOffset:SetPoint("TOPLEFT", PADDING, y)
        utilityXOffset:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        utilityWidgets.xOffset = utilityXOffset
        y = y - FORM_ROW

        -- Y Offset
        local utilityYOffset = GUI:CreateFormSlider(content, "Y Offset", -20, 20, 1, "utilityYOffset", db.customGlow, RefreshGlows)
        utilityYOffset:SetPoint("TOPLEFT", PADDING, y)
        utilityYOffset:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        utilityWidgets.yOffset = utilityYOffset
        y = y - FORM_ROW

        -- Initial enable/disable state based on glow type
        local glowType = db.customGlow.utilityGlowType or "Pixel Glow"
        local isPixel = glowType == "Pixel Glow"
        local isAutocast = glowType == "Autocast Shine"
        local isButton = glowType == "Button Glow"

        utilityWidgets.lines:SetEnabled(isPixel or isAutocast)
        utilityWidgets.thickness:SetEnabled(isPixel)
        utilityWidgets.scale:SetEnabled(isAutocast)
        utilityWidgets.speed:SetEnabled(true)
        utilityWidgets.xOffset:SetEnabled(not isButton)
        utilityWidgets.yOffset:SetEnabled(not isButton)
    end

    content:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_CDMEffectsOptions = {
    CreateCDEffectsPage = CreateCDEffectsPage
}
