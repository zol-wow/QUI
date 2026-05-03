--[[
    QUI Options - Skinning Tab
    BuildSkinningTab for Autohide & Skinning page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI

-- Import shared utilities
local Shared = ns.QUI_Options
local Helpers = ns.Helpers

local GetCore = Helpers.GetCore
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local THEME_COLORS_SUBPAGE_INDEX = 9

local function RefreshSkinSurfaces()
    if ns.Registry then
        ns.Registry:RefreshAll("skinning")
    end
    if _G.QUI_RefreshStatusTrackingBarSkin then
        _G.QUI_RefreshStatusTrackingBarSkin()
    end
end

local function RefreshChatSurfaces()
    if _G.QUI_RefreshChat then
        _G.QUI_RefreshChat()
    end
end

local function RefreshTooltipSkin()
    if ns.QUI_RefreshTooltipSkinColors then
        ns.QUI_RefreshTooltipSkinColors()
    elseif ns.QUI_RefreshTooltips then
        ns.QUI_RefreshTooltips()
    end
end

local function QueueAccentPanelRefresh()
    if not GUI.RefreshAccentColor then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if GUI.RefreshAccentColor then GUI:RefreshAccentColor() end
        end)
    else
        GUI:RefreshAccentColor()
    end
end

local function WatchAccentPickerClose()
    if not GUI.RefreshAccentColor or GUI._accentPickerWatcher then return end
    local watcher = CreateFrame("Frame")
    GUI._accentPickerWatcher = watcher
    watcher:SetScript("OnUpdate", function(self)
        if not ColorPickerFrame:IsShown() then
            self:SetScript("OnUpdate", nil)
            GUI._accentPickerWatcher = nil
            QueueAccentPanelRefresh()
        end
    end)
end

local function BuildThemePresetOptions()
    local options = {}
    for _, preset in ipairs(GUI.ThemePresets or {}) do
        options[#options + 1] = { value = preset.name, text = preset.name }
    end
    options[#options + 1] = { value = "Class Colored", text = "Class Colored" }
    options[#options + 1] = { value = "Faction Auto", text = "Faction Auto" }
    options[#options + 1] = { value = "Custom", text = "Custom" }
    return options
end

local function ApplyThemePreset(general, presetName)
    if type(general) ~= "table" or type(presetName) ~= "string" then return end
    general.themePreset = presetName
    general.skinUseClassColor = (presetName == "Class Colored")

    local r, g, b = 0.376, 0.647, 0.980
    if GUI.ResolveThemePreset then
        r, g, b = GUI:ResolveThemePreset(presetName)
    end
    general.addonAccentColor = { r, g, b, 1 }
    if GUI.ApplyAccentColor then
        GUI:ApplyAccentColor(r, g, b)
    end
    RefreshSkinSurfaces()
    RefreshTooltipSkin()
    QueueAccentPanelRefresh()
end

local function ApplyThemeColors()
    local db = Shared.GetDB()
    local general = db and db.general
    if type(general) ~= "table" then return end

    local presetName = type(general.themePreset) == "string" and general.themePreset or "Custom"
    general.skinUseClassColor = (presetName == "Class Colored")

    local r, g, b
    if GUI.ResolveThemePreset then
        r, g, b = GUI:ResolveThemePreset(presetName)
    end
    if not r then
        local accent = general.addonAccentColor or {0.376, 0.647, 0.980, 1}
        r, g, b = accent[1], accent[2], accent[3]
    end
    if presetName ~= "Custom" then
        general.addonAccentColor = { r, g, b, 1 }
    end
    if GUI.ApplyAccentColor then
        GUI:ApplyAccentColor(r, g, b)
    end
    RefreshSkinSurfaces()
    RefreshTooltipSkin()
    RefreshChatSurfaces()
    QueueAccentPanelRefresh()
end

local function ReloadConfirm()
    GUI:ShowConfirmation({
        title = "Reload UI?",
        message = "Skinning changes require a reload to take effect.",
        acceptText = "Reload",
        cancelText = "Later",
        onAccept = function() QUI:SafeReload() end,
    })
end

local function BuildThemeColorsTab(tabContent)
    local PAD = 10
    local FORM_ROW = 32
    local P = Helpers.PlaceRow
    local db = Shared.GetDB()

    GUI:SetSearchContext({
        tileId = "appearance",
        tabName = "Appearance",
        subPageIndex = THEME_COLORS_SUBPAGE_INDEX,
        subTabName = "Theme & Colors",
        featureId = "themeColorsPage",
        category = "appearance",
    })

    if not db then return end
    if not db.general then db.general = {} end
    if not db.chat then db.chat = {} end
    if not db.tooltip then db.tooltip = {} end

    local general = db.general
    local chat = db.chat
    local tooltip = db.tooltip

    if general.themePreset == nil then general.themePreset = "Custom" end
    if general.skinUseClassColor == nil then general.skinUseClassColor = (general.themePreset == "Class Colored") end
    if general.addonAccentColor == nil then general.addonAccentColor = {0.376, 0.647, 0.980, 1} end
    if general.skinBgColor == nil then general.skinBgColor = {0.05, 0.05, 0.05, 0.95} end
    if general.hideSkinBorders == nil then general.hideSkinBorders = false end
    if general.skinBorderUseClassColor == nil then general.skinBorderUseClassColor = false end
    if general.skinBorderColor == nil then
        local accent = general.addonAccentColor or {0.376, 0.647, 0.980, 1}
        general.skinBorderColor = { accent[1], accent[2], accent[3], accent[4] or 1 }
    end

    if not chat.glass then chat.glass = {} end
    if chat.glass.enabled == nil then chat.glass.enabled = true end
    if chat.glass.bgAlpha == nil then chat.glass.bgAlpha = 0.25 end
    if chat.glass.bgColor == nil then chat.glass.bgColor = {0, 0, 0} end

    if not chat.editBox then chat.editBox = {} end
    if chat.editBox.enabled == nil then chat.editBox.enabled = true end
    if chat.editBox.bgAlpha == nil then chat.editBox.bgAlpha = 0.25 end
    if chat.editBox.bgColor == nil then chat.editBox.bgColor = {0, 0, 0} end

    if tooltip.skinTooltips == nil then tooltip.skinTooltips = true end
    if tooltip.bgColor == nil then tooltip.bgColor = {0.05, 0.05, 0.05, 1} end
    if tooltip.bgOpacity == nil then tooltip.bgOpacity = 0.75 end
    if tooltip.showBorder == nil then tooltip.showBorder = true end
    if tooltip.borderThickness == nil then tooltip.borderThickness = 1 end
    if tooltip.borderColor == nil then tooltip.borderColor = {0.376, 0.647, 0.980, 1} end
    if tooltip.borderUseClassColor == nil then tooltip.borderUseClassColor = true end
    if tooltip.borderUseAccentColor == nil then tooltip.borderUseAccentColor = false end
    if tooltip.borderUseClassColor and tooltip.borderUseAccentColor then
        tooltip.borderUseAccentColor = false
    end

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

    CreateCollapsible("Theme Accent", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local themeDropdown
        local accentColorPicker
        themeDropdown = GUI:CreateFormDropdown(body, "Theme Preset", BuildThemePresetOptions(), "themePreset", general, function(presetName)
            ApplyThemePreset(general, presetName)
            if accentColorPicker and accentColorPicker.UpdateVisual then
                accentColorPicker:UpdateVisual(general.addonAccentColor)
            end
        end, { description = "Global accent preset used by the options panel and accent-colored UI surfaces." })
        sy = P(themeDropdown, body, sy)
        accentColorPicker = GUI:CreateFormColorPicker(body, "Custom Accent Color", "addonAccentColor", general, function(r, g, b)
            general.themePreset = "Custom"
            general.skinUseClassColor = false
            if themeDropdown and themeDropdown.UpdateVisual then
                themeDropdown:UpdateVisual("Custom")
            end
            if GUI.ApplyAccentColor then
                GUI:ApplyAccentColor(r, g, b)
            end
            RefreshSkinSurfaces()
            RefreshTooltipSkin()
            WatchAccentPickerClose()
        end, { noAlpha = true },
            { description = "Custom accent color used when Theme Preset is set to Custom." })
        P(accentColorPicker, body, sy)
    end)

    CreateCollapsible("Global Skin Colors", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", "skinBgColor", general, RefreshSkinSurfaces, { hasAlpha = true },
            { description = "Background fill color applied to globally skinned frames. Alpha controls how opaque the fill is." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Borders", "hideSkinBorders", general, RefreshSkinSurfaces,
            { description = "Hide the 1px accent border drawn around globally skinned frames." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Borders", "skinBorderUseClassColor", general, RefreshSkinSurfaces,
            { description = "Color global skin borders with your class color instead of the custom color below." }), body, sy)
        P(GUI:CreateFormColorPicker(body, "Border Color", "skinBorderColor", general, RefreshSkinSurfaces, { noAlpha = true },
            { description = "Custom global skin border color used when class color is off." }), body, sy)
    end)

    CreateCollapsible("Chat Background", 6 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Chat Background Texture", "enabled", chat.glass, RefreshChatSurfaces,
            { description = "Draw an opaque background behind the chat frame so text stays readable over busy scenery." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Chat Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.glass, RefreshChatSurfaces, nil,
            { description = "Opacity of the chat background (0 is invisible, 1 is fully opaque)." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Chat Background Color", "bgColor", chat.glass, RefreshChatSurfaces, nil,
            { description = "Color of the chat background." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Input Box Background Texture", "enabled", chat.editBox, RefreshChatSurfaces,
            { description = "Draw an opaque background behind the chat input box for better contrast while typing." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Input Box Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.editBox, RefreshChatSurfaces, nil,
            { description = "Opacity of the input box background (0 is invisible, 1 is fully opaque)." }), body, sy)
        P(GUI:CreateFormColorPicker(body, "Input Box Background Color", "bgColor", chat.editBox, RefreshChatSurfaces, nil,
            { description = "Color of the input box background." }), body, sy)
    end)

    CreateCollapsible("Tooltip Skinning", 8 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Skin Tooltips", "skinTooltips", tooltip, ReloadConfirm,
            { description = "Apply the QUI theme colors and border to all game tooltips. Requires a UI reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", tooltip, RefreshTooltipSkin, nil,
            { description = "Background color applied to skinned tooltips." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1, 0.05, "bgOpacity", tooltip, RefreshTooltipSkin, {precision = 2},
            { description = "Opacity of the tooltip background (0 is invisible, 1 is fully opaque)." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Border", "showBorder", tooltip, RefreshTooltipSkin,
            { description = "Draw a border around skinned tooltips." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Border Thickness", 1, 10, 1, "borderThickness", tooltip, RefreshTooltipSkin, nil,
            { description = "Thickness of the tooltip border in pixels." }), body, sy)

        local borderColorPicker = GUI:CreateFormColorPicker(body, "Border Color", "borderColor", tooltip, RefreshTooltipSkin, nil,
            { description = "Color of the tooltip border. Overridden by Class Color or Accent Color below if either is enabled." })
        sy = P(borderColorPicker, body, sy)

        local accentColorBorderCheck
        local classColorBorderCheck = GUI:CreateFormCheckbox(body, "Use Class Color for Border", "borderUseClassColor", tooltip, function(val)
            if val then
                tooltip.borderUseAccentColor = false
                if accentColorBorderCheck and accentColorBorderCheck.SetValue then accentColorBorderCheck:SetValue(false) end
            end
            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not val and not tooltip.borderUseAccentColor)
            end
            RefreshTooltipSkin()
        end, { description = "Color the tooltip border by the inspected unit's class (falls back to your class for non-unit tooltips)." })
        sy = P(classColorBorderCheck, body, sy)

        accentColorBorderCheck = GUI:CreateFormCheckbox(body, "Use Accent Color for Border", "borderUseAccentColor", tooltip, function(val)
            if val then
                tooltip.borderUseClassColor = false
                if classColorBorderCheck and classColorBorderCheck.SetValue then classColorBorderCheck:SetValue(false) end
            end
            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not val and not tooltip.borderUseClassColor)
            end
            RefreshTooltipSkin()
        end, { description = "Color the tooltip border using the UI accent color." })
        P(accentColorBorderCheck, body, sy)

        if borderColorPicker and borderColorPicker.SetEnabled then
            borderColorPicker:SetEnabled(not tooltip.borderUseClassColor and not tooltip.borderUseAccentColor)
        end
    end)

    relayout()
end

local function BuildSkinningTab(tabContent)
    local PAD = 10
    local FORM_ROW = 32
    local P = Helpers.PlaceRow
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 10, tabName = "Appearance", subTabIndex = 2, subTabName = "Skinning"})

    if not db or not db.general then return end

    local general = db.general

    -- Initialize defaults
    if general.skinUseClassColor == nil then general.skinUseClassColor = true end
    if general.addonAccentColor == nil then general.addonAccentColor = {0.376, 0.647, 0.980, 1} end
    if general.hideSkinBorders == nil then general.hideSkinBorders = false end
    if general.skinBorderUseClassColor == nil then general.skinBorderUseClassColor = false end
    if general.skinBorderColor == nil then
        local accent = general.addonAccentColor or {0.376, 0.647, 0.980, 1}
        general.skinBorderColor = { accent[1], accent[2], accent[3], accent[4] or 1 }
    end
    if general.skinKeystoneFrame == nil then general.skinKeystoneFrame = true end
    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

    local function EnsureBorderOverrideDefaults(settings, prefix)
        if type(settings) ~= "table" then return end
        local kp = type(prefix) == "string" and prefix or ""
        local overrideKey = kp ~= "" and (kp .. "BorderOverride") or "borderOverride"
        local hideKey = kp ~= "" and (kp .. "HideBorder") or "hideBorder"
        local useClassKey = kp ~= "" and (kp .. "BorderUseClassColor") or "borderUseClassColor"
        local colorKey = kp ~= "" and (kp .. "BorderColor") or "borderColor"
        if settings[overrideKey] == nil then settings[overrideKey] = false end
        if settings[hideKey] == nil then settings[hideKey] = false end
        if settings[useClassKey] == nil then settings[useClassKey] = false end
        if settings[colorKey] == nil then
            local fallback = general.skinBorderColor or general.addonAccentColor or {0.376, 0.647, 0.980, 1}
            settings[colorKey] = { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
        end
    end

    -- Border override controls builder (returns new sy)
    local function AddBorderOverrides(body, sy, settings, prefix)
        EnsureBorderOverrideDefaults(settings, prefix)
        local kp = type(prefix) == "string" and prefix or ""
        local overrideKey = kp ~= "" and (kp .. "BorderOverride") or "borderOverride"
        local hideKey = kp ~= "" and (kp .. "HideBorder") or "hideBorder"
        local useClassKey = kp ~= "" and (kp .. "BorderUseClassColor") or "borderUseClassColor"
        local colorKey = kp ~= "" and (kp .. "BorderColor") or "borderColor"

        sy = P(GUI:CreateFormCheckbox(body, "Override Global Border", overrideKey, settings, RefreshSkinSurfaces,
            { description = "Use a border style specific to this skin instead of the global default chosen in Theme & Colors." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Border", hideKey, settings, RefreshSkinSurfaces,
            { description = "Hide the border on this skin entirely. Only takes effect when the override above is enabled." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Color Border", useClassKey, settings, RefreshSkinSurfaces,
            { description = "Color this skin's border with your class color. Only takes effect when the override above is enabled." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Border Color", colorKey, settings, RefreshSkinSurfaces, { noAlpha = true },
            { description = "Custom border color used when override is on and class color is off." }), body, sy)
        return sy
    end

    -- Background override controls builder (returns new sy)
    local function AddBgOverrides(body, sy, settings, prefix)
        local kp = type(prefix) == "string" and prefix or ""
        local overrideKey = kp ~= "" and (kp .. "BgOverride") or "bgOverride"
        local hideKey = kp ~= "" and (kp .. "HideBackground") or "hideBackground"
        local colorKey = kp ~= "" and (kp .. "BackgroundColor") or "backgroundColor"

        sy = P(GUI:CreateFormCheckbox(body, "Override Global Background", overrideKey, settings, RefreshSkinSurfaces,
            { description = "Use a background color specific to this skin instead of the global default chosen in Theme & Colors." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Background", hideKey, settings, RefreshSkinSurfaces,
            { description = "Hide the background fill on this skin entirely. Only takes effect when the override above is enabled." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", colorKey, settings, RefreshSkinSurfaces, nil,
            { description = "Custom background color used when override is enabled." }), body, sy)
        return sy
    end

    ---------------------------------------------------------------------------
    -- Game Menu
    ---------------------------------------------------------------------------
    if general.skinGameMenu == nil then general.skinGameMenu = false end
    if general.addQUIButton == nil then general.addQUIButton = false end
    if general.addEditModeButton == nil then general.addEditModeButton = true end
    if general.gameMenuFontSize == nil then general.gameMenuFontSize = 12 end
    if general.gameMenuDim == nil then general.gameMenuDim = true end

    CreateCollapsible("Game Menu", 5 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Skin Game Menu (Req. Reload)", "skinGameMenu", general, ReloadConfirm,
            { description = "Apply the addon skin to the Escape game menu. Requires a reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Add QUI Button (Req. Reload)", "addQUIButton", general, ReloadConfirm,
            { description = "Add a button to the game menu that opens the QUI options panel. Requires a reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Add Edit Mode Button (Req. Reload)", "addEditModeButton", general, ReloadConfirm,
            { description = "Add a button to the game menu that toggles QUI Layout Mode. Requires a reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Button Font Size", 8, 18, 1, "gameMenuFontSize", general, function()
            if _G.QUI_RefreshGameMenuFontSize then _G.QUI_RefreshGameMenuFontSize() end
        end, nil, { description = "Font size used for the skinned game menu buttons." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Dim Background", "gameMenuDim", general, function()
            if _G.QUI_RefreshGameMenuDim then _G.QUI_RefreshGameMenuDim() end
        end, { description = "Dim the world behind the game menu while it is open so the panel reads more clearly." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Loot Window
    ---------------------------------------------------------------------------
    if not db.loot then db.loot = {} end
    if db.loot.enabled == nil then db.loot.enabled = true end
    if db.loot.lootUnderMouse == nil then db.loot.lootUnderMouse = false end
    if db.loot.lootUnderMouseOffsetX == nil then db.loot.lootUnderMouseOffsetX = 0 end
    if db.loot.lootUnderMouseOffsetY == nil then db.loot.lootUnderMouseOffsetY = 0 end
    if db.loot.showTransmogMarker == nil then db.loot.showTransmogMarker = true end
    local lootDB = db.loot

    CreateCollapsible("Loot Window", 5 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Skin Loot Window (Req. Reload)", "enabled", lootDB, ReloadConfirm,
            { description = "Apply the addon skin to the loot window. Requires a reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Loot Under Mouse", "lootUnderMouse", lootDB, nil,
            { description = "Anchor the loot window to your cursor position instead of the screen's default spot." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Loot Cursor X Offset", -200, 200, 1, "lootUnderMouseOffsetX", lootDB, nil, nil,
            { description = "Horizontal offset from the cursor when Loot Under Mouse is enabled." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Loot Cursor Y Offset", -200, 200, 1, "lootUnderMouseOffsetY", lootDB, nil, nil,
            { description = "Vertical offset from the cursor when Loot Under Mouse is enabled." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Transmog Markers", "showTransmogMarker", lootDB, nil,
            { description = "Tag items in the loot window with a marker when they're unlearned appearances for your class." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Roll Frames
    ---------------------------------------------------------------------------
    if not db.lootRoll then db.lootRoll = {} end
    if db.lootRoll.enabled == nil then db.lootRoll.enabled = false end
    if db.lootRoll.growDirection == nil then db.lootRoll.growDirection = "DOWN" end
    if db.lootRoll.spacing == nil then db.lootRoll.spacing = 4 end
    if db.lootRoll.maxFrames == nil then db.lootRoll.maxFrames = 4 end
    local lootRollDB = db.lootRoll

    local function RefreshRollPreview()
        local core = GetCore()
        if core and core.Loot and core.Loot:IsRollPreviewActive() then
            core.Loot:HideRollPreview(); core.Loot:ShowRollPreview()
        end
    end

    CreateCollapsible("Roll Frames", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Skin Roll Frames (Req. Reload)", "enabled", lootRollDB, ReloadConfirm,
            { description = "Apply the addon skin to the Need/Greed/Disenchant roll popups. Requires a reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Grow Direction", {
            {value = "DOWN", text = "Down"}, {value = "UP", text = "Up"},
        }, "growDirection", lootRollDB, RefreshRollPreview,
            { description = "Direction new roll frames stack from the anchor point — downward or upward." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Max Visible Frames", 1, 8, 1, "maxFrames", lootRollDB, RefreshRollPreview, nil,
            { description = "Maximum number of roll frames shown at once. Extra rolls queue up behind this limit." }), body, sy)
        P(GUI:CreateFormSlider(body, "Frame Spacing", 0, 20, 1, "spacing", lootRollDB, RefreshRollPreview, nil,
            { description = "Pixel gap between stacked roll frames." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Skin Blizzard Frames (combined toggles)
    ---------------------------------------------------------------------------
    if general.skinPowerBarAlt == nil then general.skinPowerBarAlt = true end
    if general.skinAlerts == nil then general.skinAlerts = true end
    if not db.lootResults then db.lootResults = {} end
    if db.lootResults.enabled == nil then db.lootResults.enabled = true end
    if general.skinCharacterFrame == nil then general.skinCharacterFrame = true end
    if general.skinInspectFrame == nil then general.skinInspectFrame = true end
    if general.skinOverrideActionBar == nil then general.skinOverrideActionBar = false end
    if general.skinInstanceFrames == nil then general.skinInstanceFrames = false end
    if general.skinAuctionHouse == nil then general.skinAuctionHouse = false end
    if general.skinCraftingOrders == nil then general.skinCraftingOrders = false end
    if general.skinProfessions == nil then general.skinProfessions = false end
    if general.skinStatusTrackingBars == nil then general.skinStatusTrackingBars = true end
    if general.skinDamageMeter == nil then general.skinDamageMeter = true end
    if not db.damageMeter then db.damageMeter = {} end
    local dm = db.damageMeter
    if dm.enabled         == nil then dm.enabled         = false end
    if dm.visibility      == nil then dm.visibility      = 0 end
    if dm.style           == nil then dm.style           = 0 end
    if dm.numberDisplay   == nil then dm.numberDisplay   = 0 end
    if dm.useClassColor   == nil then dm.useClassColor   = true end
    if dm.showBarIcons    == nil then dm.showBarIcons    = true end
    if dm.barHeight       == nil then dm.barHeight       = 25 end
    if dm.barSpacing      == nil then dm.barSpacing      = 4 end
    if dm.textSize        == nil then dm.textSize        = 100 end
    if dm.windowAlpha     == nil then dm.windowAlpha     = 100 end
    if dm.backgroundAlpha == nil then dm.backgroundAlpha = 100 end

    local function WriteDM()
        if _G.QUI_DamageMeter_ApplyToBlizzard then _G.QUI_DamageMeter_ApplyToBlizzard() end
    end

    CreateCollapsible("Skin Blizzard Frames", 13 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Alert Frames (Req. Reload)", "skinAlerts", general, ReloadConfirm,
            { description = "Skin the achievement, loot, and level-up alert popups. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Auction House (Req. Reload)", "skinAuctionHouse", general, ReloadConfirm,
            { description = "Skin the Auction House window and its tabs. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Crafting Orders (Req. Reload)", "skinCraftingOrders", general, ReloadConfirm,
            { description = "Skin the Crafting Orders interface used by professions. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Damage Meter", "skinDamageMeter", general, function()
            if _G.QUI_RefreshDamageMeterSkin then _G.QUI_RefreshDamageMeterSkin() end
        end, { description = "Skin Blizzard's built-in damage meter (Midnight 12.0+) when enabled in WoW's Gameplay Enhancements options." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Encounter Power Bar (Req. Reload)", "skinPowerBarAlt", general, ReloadConfirm,
            { description = "Skin the alternate power bar some encounters use (e.g., boss add health bars). Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Inspect Frame (Req. Reload)", "skinInspectFrame", general, ReloadConfirm,
            { description = "Skin the Inspect window that opens when you /inspect another player. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Instance Frames (Req. Reload)", "skinInstanceFrames", general, ReloadConfirm,
            { description = "Skin the Group Finder, PvP, and Mythic+ instance windows. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Keystone Window (Req. Reload)", "skinKeystoneFrame", general, ReloadConfirm,
            { description = "Skin the Mythic+ Keystone insertion and selection window. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Loot History (Req. Reload)", "enabled", db.lootResults, ReloadConfirm,
            { description = "Skin the group loot history popup that summarizes recent drops. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Override Action Bar (Req. Reload)", "skinOverrideActionBar", general, ReloadConfirm,
            { description = "Skin the temporary override bar shown during vehicles and special encounters. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Professions (Req. Reload)", "skinProfessions", general, ReloadConfirm,
            { description = "Skin the profession crafting and recipe window. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Reputation/Currency (Req. Reload)", "skinCharacterFrame", general, ReloadConfirm,
            { description = "Skin the reputation and currency tabs of the character pane. Requires a reload." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Status Tracking Bars (Req. Reload)", "skinStatusTrackingBars", general, ReloadConfirm,
            { description = "Skin the experience, reputation, and honor bars above the action bar. Requires a reload." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Status Tracking Bars (detailed settings)
    ---------------------------------------------------------------------------
    local function RefreshStatusTrackingBars()
        if _G.QUI_RefreshStatusTrackingBarSkin then
            _G.QUI_RefreshStatusTrackingBarSkin()
        end
    end

    if general.statusTrackingBarsBarColorMode == nil then general.statusTrackingBarsBarColorMode = "accent" end
    if general.statusTrackingBarsBarColor == nil then general.statusTrackingBarsBarColor = { 0.2, 0.5, 1.0, 1.0 } end
    if general.statusTrackingBarsBarHeight == nil then general.statusTrackingBarsBarHeight = 0 end
    if general.statusTrackingBarsBarWidthPercent == nil then general.statusTrackingBarsBarWidthPercent = 100 end
    if general.statusTrackingBarsShowBorder == nil then general.statusTrackingBarsShowBorder = true end
    if general.statusTrackingBarsBorderThickness == nil then general.statusTrackingBarsBorderThickness = 0 end
    if general.statusTrackingBarsShowBarText == nil then general.statusTrackingBarsShowBarText = true end
    if general.statusTrackingBarsBarTextAlways == nil then general.statusTrackingBarsBarTextAlways = false end
    if general.statusTrackingBarsBarTextAnchor == nil then general.statusTrackingBarsBarTextAnchor = "CENTER" end
    if general.statusTrackingBarsBarTextColor == nil then general.statusTrackingBarsBarTextColor = { 0.95, 0.95, 0.95, 1 } end
    if general.statusTrackingBarsBarTextFont == nil then general.statusTrackingBarsBarTextFont = "__QUI_GLOBAL__" end
    if general.statusTrackingBarsBarTextFontSize == nil then general.statusTrackingBarsBarTextFontSize = 11 end
    if general.statusTrackingBarsBarTextOutline == nil then general.statusTrackingBarsBarTextOutline = "_inherit" end
    if general.statusTrackingBarsBarTextOffsetX == nil then general.statusTrackingBarsBarTextOffsetX = 0 end
    if general.statusTrackingBarsBarTextOffsetY == nil then general.statusTrackingBarsBarTextOffsetY = 0 end

    CreateCollapsible("Status Tracking Bars", 15 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormDropdown(body, "Bar fill color", {
            { text = "Skin accent", value = "accent" },
            { text = "Class color", value = "class" },
            { text = "Custom color", value = "custom" },
            { text = "Blizzard default", value = "blizzard" },
        }, "statusTrackingBarsBarColorMode", general, RefreshStatusTrackingBars,
            { description = "How the experience and reputation bars are filled. Accent uses the skin color, Class uses your class color, Custom uses the picker below, Blizzard keeps the default bar art." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Custom bar fill", "statusTrackingBarsBarColor", general, RefreshStatusTrackingBars, {},
            { description = "Custom fill color used when the bar fill mode is set to Custom color." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Bar height (0 = default)", 0, 24, 1, "statusTrackingBarsBarHeight", general, RefreshStatusTrackingBars, nil,
            { description = "Pixel height of the tracking bar. Set to 0 to keep the default height." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Bar width %", 25, 100, 1, "statusTrackingBarsBarWidthPercent", general, RefreshStatusTrackingBars, nil,
            { description = "Width of the tracking bar as a percentage of its default width." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show bar border", "statusTrackingBarsShowBorder", general, RefreshStatusTrackingBars,
            { description = "Draw a 1px border around the tracking bars using the global skin border style." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Border thickness (0 = auto)", 0, 8, 1, "statusTrackingBarsBorderThickness", general, RefreshStatusTrackingBars, nil,
            { description = "Thickness of the tracking bar border in pixels. 0 uses the automatic pixel-perfect value." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show bar text", "statusTrackingBarsShowBarText", general, RefreshStatusTrackingBars,
            { description = "Show the XP, reputation, or honor numeric text on top of the bar." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Always show text (ignore game toggle)", "statusTrackingBarsBarTextAlways", general, RefreshStatusTrackingBars,
            { description = "Keep the bar text visible at all times, ignoring Blizzard's mouseover-only default behavior." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Text position", {
            { text = "Left", value = "LEFT" },
            { text = "Center", value = "CENTER" },
            { text = "Right", value = "RIGHT" },
        }, "statusTrackingBarsBarTextAnchor", general, RefreshStatusTrackingBars,
            { description = "Horizontal alignment of the bar text." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Text color", "statusTrackingBarsBarTextColor", general, RefreshStatusTrackingBars, {},
            { description = "Color of the numeric text drawn on top of the tracking bar." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Text font size", 6, 24, 1, "statusTrackingBarsBarTextFontSize", general, RefreshStatusTrackingBars, nil,
            { description = "Font size used for the bar text." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Text outline", {
            { text = "Inherit (global outline)", value = "_inherit" },
            { text = "None", value = "_none" },
            { text = "Thin", value = "OUTLINE" },
            { text = "Thick", value = "THICKOUTLINE" },
        }, "statusTrackingBarsBarTextOutline", general, RefreshStatusTrackingBars,
            { description = "Outline style for the bar text. Inherit follows the global font outline; None removes it; Thin and Thick set explicit widths." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Text X offset", -40, 40, 1, "statusTrackingBarsBarTextOffsetX", general, RefreshStatusTrackingBars, nil,
            { description = "Horizontal pixel offset of the text from its anchor." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Text Y offset", -40, 40, 1, "statusTrackingBarsBarTextOffsetY", general, RefreshStatusTrackingBars, nil,
            { description = "Vertical pixel offset of the text from its anchor." }), body, sy)
        sy = AddBorderOverrides(body, sy, general, "statusTrackingBars")
        AddBgOverrides(body, sy, general, "statusTrackingBars")
    end)

    CreateCollapsible("Damage Meter", 11 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Enable Damage Meter", "enabled", dm, WriteDM,
            { description = "Master toggle for Blizzard's built-in damage meter (Midnight 12.0+). Mirrors the damageMeterEnabled CVar." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Visibility", {
            { text = "Always",     value = 0 },
            { text = "In Combat",  value = 1 },
            { text = "Hidden",     value = 2 },
        }, "visibility", dm, WriteDM,
            { description = "When the meter is visible. Always = always shown when enabled; In Combat = only visible while you're in combat; Hidden = enabled but invisible." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Style", {
            { text = "Default",    value = 0 },
            { text = "Bordered",   value = 1 },
            { text = "Thin",       value = 3 },
        }, "style", dm, WriteDM,
            { description = "Bar layout style. Default = standard rows; Bordered = framed rows; Thin = compact rows with text above bar." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Number Display", {
            { text = "Minimal",    value = 0 },
            { text = "Compact",    value = 1 },
            { text = "Complete",   value = 2 },
        }, "numberDisplay", dm, WriteDM,
            { description = "How values are formatted on each bar. Minimal = single value; Compact = value (per-second); Complete = value (per-second) percentage%." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Colors", "useClassColor", dm, WriteDM,
            { description = "Color each row's bar by the player's class color. Disable for monochrome." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Bar Icons", "showBarIcons", dm, WriteDM,
            { description = "Show the spec or class icon on the left side of each row." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Bar Height", 15, 40, 1, "barHeight", dm, WriteDM, nil,
            { description = "Pixel height of each row (15-40)." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Bar Spacing", 2, 10, 1, "barSpacing", dm, WriteDM, nil,
            { description = "Pixel spacing between rows (2-10)." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Text Size", 50, 150, 10, "textSize", dm, WriteDM, nil,
            { description = "Text size as a percentage of default (50-150, step 10)." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Window Alpha", 50, 100, 1, "windowAlpha", dm, WriteDM, nil,
            { description = "Window transparency as a percentage (50-100). Lower values make the meter more see-through." }), body, sy)
        P(GUI:CreateFormSlider(body, "Background Alpha", 0, 100, 1, "backgroundAlpha", dm, WriteDM, nil,
            { description = "Background transparency as a percentage (0-100). 0 hides the row backgrounds entirely." }), body, sy)
    end)

    -- Objective Tracker — flattened into Skinning. All
    -- widgets inline instead of nesting the layout-mode provider. Position
    -- is handled by Layout Mode and intentionally omitted here.
    if general.skinObjectiveTracker == nil then general.skinObjectiveTracker = false end
    if general.objectiveTrackerClickThrough == nil then general.objectiveTrackerClickThrough = false end
    if general.objectiveTrackerHeight == nil then general.objectiveTrackerHeight = 600 end
    if general.objectiveTrackerWidth == nil then general.objectiveTrackerWidth = 260 end
    if general.objectiveTrackerModuleFontSize == nil then general.objectiveTrackerModuleFontSize = 12 end
    if general.objectiveTrackerTitleFontSize == nil then general.objectiveTrackerTitleFontSize = 10 end
    if general.objectiveTrackerTextFontSize == nil then general.objectiveTrackerTextFontSize = 10 end
    if general.hideObjectiveTrackerBorder == nil then general.hideObjectiveTrackerBorder = false end
    if general.objectiveTrackerModuleColor == nil then general.objectiveTrackerModuleColor = { 1.0, 0.82, 0.0, 1.0 } end
    if general.objectiveTrackerTitleColor == nil then general.objectiveTrackerTitleColor = { 1.0, 1.0, 1.0, 1.0 } end
    if general.objectiveTrackerTextColor == nil then general.objectiveTrackerTextColor = { 0.8, 0.8, 0.8, 1.0 } end

    local function RefreshOT()
        if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
    end

    CreateCollapsible("Objective Tracker", 11 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Skin Objective Tracker", "skinObjectiveTracker", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end, { description = "Apply the addon skin and font treatment to the quest/objective tracker. Requires a reload." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Click Through", "objectiveTrackerClickThrough", general, RefreshOT,
            { description = "Let mouse clicks pass through the tracker to the game world behind it. Useful if the tracker overlaps targetable mobs or nodes." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Max Height", 200, 1000, 10, "objectiveTrackerHeight", general, RefreshOT, nil,
            { description = "Maximum pixel height of the tracker. Content past this height scrolls or collapses." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Max Width", 150, 400, 10, "objectiveTrackerWidth", general, RefreshOT, nil,
            { description = "Maximum pixel width of the tracker." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Module Header Font", 6, 18, 1, "objectiveTrackerModuleFontSize", general, RefreshOT, nil,
            { description = "Font size of module headers like Quests, Campaign, and World Quests." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Quest Title Font", 6, 18, 1, "objectiveTrackerTitleFontSize", general, RefreshOT, nil,
            { description = "Font size of individual quest titles listed under each module." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Objective Text Font", 6, 18, 1, "objectiveTrackerTextFontSize", general, RefreshOT, nil,
            { description = "Font size of the objective/progress text shown beneath each quest title." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Border", "hideObjectiveTrackerBorder", general, RefreshOT,
            { description = "Hide the border drawn around the skinned objective tracker." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Module Header Color", "objectiveTrackerModuleColor", general, RefreshOT, nil,
            { description = "Color applied to module header text (Quests, Campaign, etc.)." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Quest Title Color", "objectiveTrackerTitleColor", general, RefreshOT, nil,
            { description = "Color applied to individual quest title text." }), body, sy)
        P(GUI:CreateFormColorPicker(body, "Objective Text Color", "objectiveTrackerTextColor", general, RefreshOT, nil,
            { description = "Color applied to objective/progress text beneath each quest title." }), body, sy)
    end)

    relayout()
end

-- Export
ns.QUI_SkinningOptions = {
    BuildSkinningTab = BuildSkinningTab,
    BuildThemeColorsTab = BuildThemeColorsTab,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "themeColorsPage",
        moverKey = "themeColors",
        lookupKeys = { "theme", "colors", "accent", "skinColors", "chatBackground", "tooltipSkinning" },
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = THEME_COLORS_SUBPAGE_INDEX },
        apply = ApplyThemeColors,
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildThemeColorsTab,
            }),
        },
    }))
end

if Registry and Schema and RenderAdapters
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "skinningPage",
        moverKey = "skinning",
        lookupKeys = { "objectiveTracker" },
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 3 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildSkinningTab,
            }),
        },
        render = {
            layout = function(host, options)
                return RenderAdapters.RenderLayoutRoute(host, options and options.providerKey or "skinning")
            end,
        },
    }))
end
