--[[
    QUI Options - Skinning Tab
    BuildSkinningTab + BuildThemeColorsTab. Migrated to V3 body pattern.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local Shared = ns.QUI_Options
local Helpers = ns.Helpers

local GetCore = Helpers.GetCore
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local THEME_COLORS_SUBPAGE_INDEX = 10

local PAD = (Shared and Shared.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

---------------------------------------------------------------------------
-- Refresh helpers (unchanged)
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- V3 layout helpers
---------------------------------------------------------------------------
-- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

-- Pair an iterable list of cells 2-per-row, with a trailing unpaired cell.
local function pairCells(card, cells)
    local i = 1
    while i <= #cells do
        local left = cells[i]
        local right = cells[i + 1]
        if right then
            card.AddRow(left, right)
            i = i + 2
        else
            card.AddRow(left)
            i = i + 1
        end
    end
end

---------------------------------------------------------------------------
-- THEME & COLORS TAB
---------------------------------------------------------------------------
local function BuildThemeColorsTab(tabContent)
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
    if general.skinBorderColorSource == nil then
        general.skinBorderColorSource = general.skinBorderUseClassColor and "class" or "theme"
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
    if tooltip.borderColorSource == nil then
        tooltip.borderColorSource = tooltip.borderUseClassColor and "class" or "theme"
    end

    local L = MakeLayout(tabContent)

    -- Theme Accent
    L.headerAt("Theme Accent")
    local sTA = L.sectionAt()
    local themeDropdown, accentColorPicker
    themeDropdown = GUI:CreateFormDropdown(sTA.frame, nil, BuildThemePresetOptions(), "themePreset", general, function(presetName)
        ApplyThemePreset(general, presetName)
        if accentColorPicker and accentColorPicker.UpdateVisual then
            accentColorPicker:UpdateVisual(general.addonAccentColor)
        end
    end, { description = "Global accent preset used by the options panel and accent-colored UI surfaces." })
    accentColorPicker = GUI:CreateFormColorPicker(sTA.frame, nil, "addonAccentColor", general, function(r, g, b)
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
    sTA.AddRow(
        row(sTA.frame, "Theme Preset", themeDropdown),
        row(sTA.frame, "Custom Accent Color", accentColorPicker)
    )
    L.closeSection(sTA)

    -- Global Skin Colors
    L.headerAt("Global Skin Colors")
    local sGS = L.sectionAt()
    local gsBgColorW = GUI:CreateFormColorPicker(sGS.frame, nil, "skinBgColor", general, RefreshSkinSurfaces, { hasAlpha = true },
        { description = "Background fill color applied to globally skinned frames. Alpha controls how opaque the fill is." })
    local gsHideBordersW = GUI:CreateFormCheckbox(sGS.frame, nil, "hideSkinBorders", general, RefreshSkinSurfaces,
        { description = "Hide the 1px accent border drawn around globally skinned frames." })
    sGS.AddRow(
        row(sGS.frame, "Background Color", gsBgColorW),
        row(sGS.frame, "Hide Borders", gsHideBordersW)
    )

    local BORDER_SOURCE_OPTIONS = {
        { value = "theme",  text = "Theme" },
        { value = "class",  text = "Class" },
        { value = "custom", text = "Custom" },
    }
    local gsBorderColorW
    local gsBorderSourceW = GUI:CreateFormDropdown(sGS.frame, nil, BORDER_SOURCE_OPTIONS, "skinBorderColorSource", general, function(value)
        if gsBorderColorW and gsBorderColorW.SetEnabled then
            gsBorderColorW:SetEnabled(value == "custom")
        end
        RefreshSkinSurfaces()
    end, { description = "Where global skin borders get their color: Theme (follows your theme accent), Class (your class color), or Custom (the color picker)." })
    gsBorderColorW = GUI:CreateFormColorPicker(sGS.frame, nil, "skinBorderColor", general, RefreshSkinSurfaces, { noAlpha = true },
        { description = "Custom global skin border color, used when Border Color Source is set to Custom." })
    if gsBorderColorW and gsBorderColorW.SetEnabled then
        gsBorderColorW:SetEnabled((general.skinBorderColorSource or "theme") == "custom")
    end
    sGS.AddRow(
        row(sGS.frame, "Border Color Source", gsBorderSourceW),
        row(sGS.frame, "Border Color", gsBorderColorW)
    )
    L.closeSection(sGS)

    -- Chat Background
    L.headerAt("Chat Background")
    local sCB = L.sectionAt()
    local cbEnableW = GUI:CreateFormCheckbox(sCB.frame, nil, "enabled", chat.glass, RefreshChatSurfaces,
        { description = "Draw an opaque background behind the chat frame so text stays readable over busy scenery." })
    local cbAlphaW = GUI:CreateFormSlider(sCB.frame, nil, 0, 1.0, 0.05, "bgAlpha", chat.glass, RefreshChatSurfaces,
        { precision = 2, description = "Opacity of the chat background (0 is invisible, 1 is fully opaque)." })
    sCB.AddRow(
        row(sCB.frame, "Chat Background Texture", cbEnableW),
        row(sCB.frame, "Chat Background Opacity", cbAlphaW)
    )

    local cbColorW = GUI:CreateFormColorPicker(sCB.frame, nil, "bgColor", chat.glass, RefreshChatSurfaces, nil,
        { description = "Color of the chat background." })
    local cbEditEnW = GUI:CreateFormCheckbox(sCB.frame, nil, "enabled", chat.editBox, RefreshChatSurfaces,
        { description = "Draw an opaque background behind the chat input box for better contrast while typing." })
    sCB.AddRow(
        row(sCB.frame, "Chat Background Color", cbColorW),
        row(sCB.frame, "Input Box Background Texture", cbEditEnW)
    )

    local cbEditAlphaW = GUI:CreateFormSlider(sCB.frame, nil, 0, 1.0, 0.05, "bgAlpha", chat.editBox, RefreshChatSurfaces,
        { precision = 2, description = "Opacity of the input box background (0 is invisible, 1 is fully opaque)." })
    local cbEditColorW = GUI:CreateFormColorPicker(sCB.frame, nil, "bgColor", chat.editBox, RefreshChatSurfaces, nil,
        { description = "Color of the input box background." })
    sCB.AddRow(
        row(sCB.frame, "Input Box Background Opacity", cbEditAlphaW),
        row(sCB.frame, "Input Box Background Color", cbEditColorW)
    )
    L.closeSection(sCB)

    -- Tooltip Skinning
    L.headerAt("Tooltip Skinning")
    local sTS = L.sectionAt()
    local tsSkinW = GUI:CreateFormCheckbox(sTS.frame, nil, "skinTooltips", tooltip, ReloadConfirm,
        { description = "Apply the QUI theme colors and border to all game tooltips. Requires a UI reload to take effect." })
    local tsBgColorW = GUI:CreateFormColorPicker(sTS.frame, nil, "bgColor", tooltip, RefreshTooltipSkin, nil,
        { description = "Background color applied to skinned tooltips." })
    sTS.AddRow(
        row(sTS.frame, "Skin Tooltips", tsSkinW),
        row(sTS.frame, "Background Color", tsBgColorW)
    )

    local tsBgOpW = GUI:CreateFormSlider(sTS.frame, nil, 0, 1, 0.05, "bgOpacity", tooltip, RefreshTooltipSkin,
        { precision = 2, description = "Opacity of the tooltip background (0 is invisible, 1 is fully opaque)." })
    local tsShowBorderW = GUI:CreateFormCheckbox(sTS.frame, nil, "showBorder", tooltip, RefreshTooltipSkin,
        { description = "Draw a border around skinned tooltips." })
    sTS.AddRow(
        row(sTS.frame, "Background Opacity", tsBgOpW),
        row(sTS.frame, "Show Border", tsShowBorderW)
    )

    local tsBorderThickW = GUI:CreateFormSlider(sTS.frame, nil, 1, 10, 1, "borderThickness", tooltip, RefreshTooltipSkin,
        { description = "Thickness of the tooltip border in pixels." })
    local tsBorderSourceW, tsBorderColorW = ns.QUI_BorderControl.Attach(
        GUI, sTS.frame, tooltip, "", RefreshTooltipSkin,
        { label = "Border Color Source", colorLabel = "Border Color" }
    )
    sTS.AddRow(
        row(sTS.frame, "Border Thickness", tsBorderThickW),
        row(sTS.frame, "Border Color Source", tsBorderSourceW)
    )
    sTS.AddRow(
        row(sTS.frame, "Border Color", tsBorderColorW)
    )
    L.closeSection(sTS)

    L.finish()
end

---------------------------------------------------------------------------
-- SKINNING TAB
---------------------------------------------------------------------------
local function BuildSkinningTab(tabContent)
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 10, tabName = "Appearance", subTabIndex = 2, subTabName = "Skinning"})

    if not db or not db.general then return end

    local general = db.general

    -- Initialize defaults
    if general.skinUseClassColor == nil then general.skinUseClassColor = true end
    if general.addonAccentColor == nil then general.addonAccentColor = {0.376, 0.647, 0.980, 1} end
    if general.hideSkinBorders == nil then general.hideSkinBorders = false end
    if general.skinBorderColorSource == nil then
        general.skinBorderColorSource = general.skinBorderUseClassColor and "class" or "theme"
    end
    if general.skinKeystoneFrame == nil then general.skinKeystoneFrame = true end

    -- Helper: ensure border-override keys exist on a settings table.
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

    -- Append the 4 border-override widgets as 2 paired rows in a card.
    local function AddBorderOverrides(card, settings, prefix)
        EnsureBorderOverrideDefaults(settings, prefix)
        local kp = type(prefix) == "string" and prefix or ""
        local overrideKey = kp ~= "" and (kp .. "BorderOverride") or "borderOverride"
        local hideKey = kp ~= "" and (kp .. "HideBorder") or "hideBorder"
        local useClassKey = kp ~= "" and (kp .. "BorderUseClassColor") or "borderUseClassColor"
        local colorKey = kp ~= "" and (kp .. "BorderColor") or "borderColor"

        local overrideW = GUI:CreateFormCheckbox(card.frame, nil, overrideKey, settings, RefreshSkinSurfaces,
            { description = "Use a border style specific to this skin instead of the global default chosen in Theme & Colors." })
        local hideW = GUI:CreateFormCheckbox(card.frame, nil, hideKey, settings, RefreshSkinSurfaces,
            { description = "Hide the border on this skin entirely. Only takes effect when the override above is enabled." })
        card.AddRow(
            row(card.frame, "Override Global Border", overrideW),
            row(card.frame, "Hide Border", hideW)
        )

        local classW = GUI:CreateFormCheckbox(card.frame, nil, useClassKey, settings, RefreshSkinSurfaces,
            { description = "Color this skin's border with your class color. Only takes effect when the override above is enabled." })
        local colorW = GUI:CreateFormColorPicker(card.frame, nil, colorKey, settings, RefreshSkinSurfaces, { noAlpha = true },
            { description = "Custom border color used when override is on and class color is off." })
        card.AddRow(
            row(card.frame, "Use Class Color Border", classW),
            row(card.frame, "Border Color", colorW)
        )
    end

    -- Append the 3 background-override widgets as paired rows in a card.
    local function AddBgOverrides(card, settings, prefix)
        local kp = type(prefix) == "string" and prefix or ""
        local overrideKey = kp ~= "" and (kp .. "BgOverride") or "bgOverride"
        local hideKey = kp ~= "" and (kp .. "HideBackground") or "hideBackground"
        local colorKey = kp ~= "" and (kp .. "BackgroundColor") or "backgroundColor"

        local overrideW = GUI:CreateFormCheckbox(card.frame, nil, overrideKey, settings, RefreshSkinSurfaces,
            { description = "Use a background color specific to this skin instead of the global default chosen in Theme & Colors." })
        local hideW = GUI:CreateFormCheckbox(card.frame, nil, hideKey, settings, RefreshSkinSurfaces,
            { description = "Hide the background fill on this skin entirely. Only takes effect when the override above is enabled." })
        card.AddRow(
            row(card.frame, "Override Global Background", overrideW),
            row(card.frame, "Hide Background", hideW)
        )

        local colorW = GUI:CreateFormColorPicker(card.frame, nil, colorKey, settings, RefreshSkinSurfaces, nil,
            { description = "Custom background color used when override is enabled." })
        card.AddRow(row(card.frame, "Background Color", colorW))
    end

    local L = MakeLayout(tabContent)

    ---------------------------------------------------------------------------
    -- GAME MENU
    ---------------------------------------------------------------------------
    if general.skinGameMenu == nil then general.skinGameMenu = false end
    if general.addQUIButton == nil then general.addQUIButton = false end
    if general.addEditModeButton == nil then general.addEditModeButton = true end
    if general.gameMenuFontSize == nil then general.gameMenuFontSize = 12 end
    if general.gameMenuDim == nil then general.gameMenuDim = true end

    L.headerAt("Game Menu")
    local sGM = L.sectionAt()
    local gmSkinW = GUI:CreateFormCheckbox(sGM.frame, nil, "skinGameMenu", general, ReloadConfirm,
        { description = "Apply the addon skin to the Escape game menu. Requires a reload to take effect." })
    local gmQUIW = GUI:CreateFormCheckbox(sGM.frame, nil, "addQUIButton", general, ReloadConfirm,
        { description = "Add a button to the game menu that opens the QUI options panel. Requires a reload to take effect." })
    sGM.AddRow(
        row(sGM.frame, "Skin Game Menu (Req. Reload)", gmSkinW),
        row(sGM.frame, "Add QUI Button (Req. Reload)", gmQUIW)
    )

    local gmEditModeW = GUI:CreateFormCheckbox(sGM.frame, nil, "addEditModeButton", general, ReloadConfirm,
        { description = "Add a button to the game menu that toggles QUI Layout Mode. Requires a reload to take effect." })
    local gmFontW = GUI:CreateFormSlider(sGM.frame, nil, 8, 18, 1, "gameMenuFontSize", general, function()
        if _G.QUI_RefreshGameMenuFontSize then _G.QUI_RefreshGameMenuFontSize() end
    end, { description = "Font size used for the skinned game menu buttons." })
    sGM.AddRow(
        row(sGM.frame, "Add Edit Mode Button (Req. Reload)", gmEditModeW),
        row(sGM.frame, "Button Font Size", gmFontW)
    )

    local gmDimW = GUI:CreateFormCheckbox(sGM.frame, nil, "gameMenuDim", general, function()
        if _G.QUI_RefreshGameMenuDim then _G.QUI_RefreshGameMenuDim() end
    end, { description = "Dim the world behind the game menu while it is open so the panel reads more clearly." })
    sGM.AddRow(row(sGM.frame, "Dim Background", gmDimW))
    L.closeSection(sGM)

    ---------------------------------------------------------------------------
    -- LOOT WINDOW
    ---------------------------------------------------------------------------
    if not db.loot then db.loot = {} end
    if db.loot.enabled == nil then db.loot.enabled = true end
    if db.loot.lootUnderMouse == nil then db.loot.lootUnderMouse = false end
    if db.loot.lootUnderMouseOffsetX == nil then db.loot.lootUnderMouseOffsetX = 0 end
    if db.loot.lootUnderMouseOffsetY == nil then db.loot.lootUnderMouseOffsetY = 0 end
    if db.loot.showTransmogMarker == nil then db.loot.showTransmogMarker = true end
    local lootDB = db.loot

    L.headerAt("Loot Window")
    local sLW = L.sectionAt()
    local lwSkinW = GUI:CreateFormCheckbox(sLW.frame, nil, "enabled", lootDB, ReloadConfirm,
        { description = "Apply the addon skin to the loot window. Requires a reload to take effect." })
    local lwMouseW = GUI:CreateFormCheckbox(sLW.frame, nil, "lootUnderMouse", lootDB, nil,
        { description = "Anchor the loot window to your cursor position instead of the screen's default spot." })
    sLW.AddRow(
        row(sLW.frame, "Skin Loot Window (Req. Reload)", lwSkinW),
        row(sLW.frame, "Loot Under Mouse", lwMouseW)
    )

    local lwXW = GUI:CreateFormSlider(sLW.frame, nil, -200, 200, 1, "lootUnderMouseOffsetX", lootDB, nil,
        { description = "Horizontal offset from the cursor when Loot Under Mouse is enabled." })
    local lwYW = GUI:CreateFormSlider(sLW.frame, nil, -200, 200, 1, "lootUnderMouseOffsetY", lootDB, nil,
        { description = "Vertical offset from the cursor when Loot Under Mouse is enabled." })
    sLW.AddRow(
        row(sLW.frame, "Loot Cursor X Offset", lwXW),
        row(sLW.frame, "Loot Cursor Y Offset", lwYW)
    )

    local lwTransmogW = GUI:CreateFormCheckbox(sLW.frame, nil, "showTransmogMarker", lootDB, nil,
        { description = "Tag items in the loot window with a marker when they're unlearned appearances for your class." })
    sLW.AddRow(row(sLW.frame, "Show Transmog Markers", lwTransmogW))
    L.closeSection(sLW)

    ---------------------------------------------------------------------------
    -- ROLL FRAMES
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

    L.headerAt("Roll Frames")
    local sRF = L.sectionAt()
    local rfSkinW = GUI:CreateFormCheckbox(sRF.frame, nil, "enabled", lootRollDB, ReloadConfirm,
        { description = "Apply the addon skin to the Need/Greed/Disenchant roll popups. Requires a reload to take effect." })
    local rfGrowW = GUI:CreateFormDropdown(sRF.frame, nil, {
        {value = "DOWN", text = "Down"}, {value = "UP", text = "Up"},
    }, "growDirection", lootRollDB, RefreshRollPreview,
        { description = "Direction new roll frames stack from the anchor point — downward or upward." })
    sRF.AddRow(
        row(sRF.frame, "Skin Roll Frames (Req. Reload)", rfSkinW),
        row(sRF.frame, "Grow Direction", rfGrowW)
    )

    local rfMaxW = GUI:CreateFormSlider(sRF.frame, nil, 1, 8, 1, "maxFrames", lootRollDB, RefreshRollPreview,
        { description = "Maximum number of roll frames shown at once. Extra rolls queue up behind this limit." })
    local rfSpaceW = GUI:CreateFormSlider(sRF.frame, nil, 0, 20, 1, "spacing", lootRollDB, RefreshRollPreview,
        { description = "Pixel gap between stacked roll frames." })
    sRF.AddRow(
        row(sRF.frame, "Max Visible Frames", rfMaxW),
        row(sRF.frame, "Frame Spacing", rfSpaceW)
    )
    L.closeSection(sRF)

    ---------------------------------------------------------------------------
    -- SKIN BLIZZARD FRAMES (28 checkboxes paired 2-per-row)
    ---------------------------------------------------------------------------
    if general.skinPowerBarAlt == nil then general.skinPowerBarAlt = true end
    if general.skinAlerts == nil then general.skinAlerts = true end
    if general.skinContextMenus == nil then general.skinContextMenus = true end
    if general.skinReadyCheck == nil then general.skinReadyCheck = true end
    if general.skinStaticPopups == nil then general.skinStaticPopups = true end
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
    if general.skinBank == nil then general.skinBank = false end
    if general.skinMerchant == nil then general.skinMerchant = false end
    if general.skinMail == nil then general.skinMail = false end
    if general.skinGuildBank == nil then general.skinGuildBank = false end
    if general.skinFriends == nil then general.skinFriends = false end
    if general.skinCommunities == nil then general.skinCommunities = false end
    if general.skinSpellBook == nil then general.skinSpellBook = false end
    if general.skinEncounterJournal == nil then general.skinEncounterJournal = false end
    if general.skinCollections == nil then general.skinCollections = false end
    if general.skinAchievement == nil then general.skinAchievement = false end
    if general.skinWorldMap == nil then general.skinWorldMap = false end
    if general.skinWeeklyRewards == nil then general.skinWeeklyRewards = false end

    L.headerAt("Skin Blizzard Frames")
    local sSBF = L.sectionAt()
    local blizFrames = {
        {key="skinAlerts",            label="Alert Frames (Req. Reload)",            dbT=general,         desc="Skin the achievement, loot, and level-up alert popups. Requires a reload."},
        {key="skinAchievement",       label="Achievement Frame (Req. Reload)",       dbT=general,         desc="Skin the Achievements window. Bespoke achievement-themed artwork is stripped — categories list parchment and watermark dragon are hidden. Requires a reload."},
        {key="skinAuctionHouse",      label="Auction House (Req. Reload)",           dbT=general,         desc="Skin the Auction House window and its tabs. Requires a reload."},
        {key="skinBank",              label="Bank (Req. Reload)",                    dbT=general,         desc="Skin the player Bank window. Requires a reload."},
        {key="skinCollections",       label="Collections Journal (Req. Reload)",     dbT=general,         desc="Skin the Mounts / Pets / Toys / Wardrobe / Heirlooms window. Requires a reload."},
        {key="skinCommunities",       label="Communities (Req. Reload)",             dbT=general,         desc="Skin the Guilds and Communities window. Requires a reload."},
        {key="skinContextMenus",      label="Context Menus (Req. Reload)",           dbT=general,         desc="Skin right-click context menus and dropdown menu panels. Requires a reload."},
        {key="skinCraftingOrders",    label="Crafting Orders (Req. Reload)",         dbT=general,         desc="Skin the Crafting Orders interface used by professions. Requires a reload."},
        {key="skinEncounterJournal",  label="Encounter Journal (Req. Reload)",       dbT=general,         desc="Skin the Adventure Guide / Encounter Journal window. Requires a reload."},
        {key="skinPowerBarAlt",       label="Encounter Power Bar (Req. Reload)",     dbT=general,         desc="Skin the alternate power bar some encounters use (e.g., boss add health bars). Requires a reload."},
        {key="skinFriends",           label="Friends List (Req. Reload)",            dbT=general,         desc="Skin the Friends / Ignore / Who window. Requires a reload."},
        {key="skinGuildBank",         label="Guild Bank (Req. Reload)",              dbT=general,         desc="Skin the Guild Bank window. Requires a reload."},
        {key="skinInspectFrame",      label="Inspect Frame (Req. Reload)",           dbT=general,         desc="Skin the Inspect window that opens when you /inspect another player. Requires a reload."},
        {key="skinInstanceFrames",    label="Instance Frames (Req. Reload)",         dbT=general,         desc="Skin the Group Finder, PvP, and Mythic+ instance windows. Requires a reload."},
        {key="skinKeystoneFrame",     label="Keystone Window (Req. Reload)",         dbT=general,         desc="Skin the Mythic+ Keystone insertion and selection window. Requires a reload."},
        {key="enabled",               label="Loot History (Req. Reload)",            dbT=db.lootResults,  desc="Skin the group loot history popup that summarizes recent drops. Requires a reload."},
        {key="skinMail",              label="Mail (Req. Reload)",                    dbT=general,         desc="Skin the in-game mail window. Requires a reload."},
        {key="skinMerchant",          label="Merchant (Req. Reload)",                dbT=general,         desc="Skin the vendor/merchant window. Requires a reload."},
        {key="skinOverrideActionBar", label="Override Action Bar (Req. Reload)",     dbT=general,         desc="Skin the temporary override bar shown during vehicles and special encounters. Requires a reload."},
        {key="skinProfessions",       label="Professions (Req. Reload)",             dbT=general,         desc="Skin the profession crafting and recipe window. Requires a reload."},
        {key="skinReadyCheck",        label="Ready Check Dialog (Req. Reload)",      dbT=general,         desc="Skin the ready check popup. Requires a reload."},
        {key="skinCharacterFrame",    label="Reputation/Currency (Req. Reload)",     dbT=general,         desc="Skin the reputation and currency tabs of the character pane. Requires a reload."},
        {key="skinSpellBook",         label="Spellbook / Talents (Req. Reload)",     dbT=general,         desc="Skin the combined Spellbook and Talents window (PlayerSpellsFrame). Requires a reload."},
        {key="skinStaticPopups",      label="Static Dialogs (Req. Reload)",          dbT=general,         desc="Skin StaticPopup confirmation dialogs. Requires a reload."},
        {key="skinStatusTrackingBars",label="Status Tracking Bars (Req. Reload)",    dbT=general,         desc="Skin the experience, reputation, and honor bars above the action bar. Requires a reload."},
        {key="skinWeeklyRewards",     label="Weekly Rewards / Great Vault (Req. Reload)", dbT=general,    desc="Skin the Great Vault window. Bespoke evergreen artwork is stripped. Requires a reload."},
        {key="skinWorldMap",          label="World Map (Req. Reload)",               dbT=general,         desc="Skin the World Map's PortraitFrame border (the map canvas itself is unchanged). Requires a reload."},
    }
    local sbfCells = {}
    for _, def in ipairs(blizFrames) do
        local w = GUI:CreateFormCheckbox(sSBF.frame, nil, def.key, def.dbT, ReloadConfirm,
            { description = def.desc })
        sbfCells[#sbfCells + 1] = row(sSBF.frame, def.label, w)
    end
    pairCells(sSBF, sbfCells)
    L.closeSection(sSBF)

    ---------------------------------------------------------------------------
    -- ALERT FRAMES (border color)
    ---------------------------------------------------------------------------
    if general.alertsBorderColorSource == nil then general.alertsBorderColorSource = "inherit" end
    if general.alertsBorderColor == nil then general.alertsBorderColor = {0, 0, 0, 1} end

    local function RefreshAlerts()
        if _G.QUI_RefreshAlertColors then _G.QUI_RefreshAlertColors() end
    end

    L.headerAt("Alert Frames Border")
    local sAF = L.sectionAt()
    local afBorderSourceW, afBorderColorW = ns.QUI_BorderControl.Attach(
        GUI, sAF.frame, general, "alerts", RefreshAlerts,
        { label = "Border Color Source", colorLabel = "Border Color" }
    )
    sAF.AddRow(
        row(sAF.frame, "Border Color Source", afBorderSourceW),
        row(sAF.frame, "Border Color", afBorderColorW)
    )
    L.closeSection(sAF)

    ---------------------------------------------------------------------------
    -- STATUS TRACKING BARS
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

    L.headerAt("Status Tracking Bars")
    local sSTB = L.sectionAt()
    local stbColorModeW = GUI:CreateFormDropdown(sSTB.frame, nil, {
        { text = "Skin accent", value = "accent" },
        { text = "Class color", value = "class" },
        { text = "Custom color", value = "custom" },
        { text = "Blizzard default", value = "blizzard" },
    }, "statusTrackingBarsBarColorMode", general, RefreshStatusTrackingBars,
        { description = "How the experience and reputation bars are filled. Accent uses the skin color, Class uses your class color, Custom uses the picker below, Blizzard keeps the default bar art." })
    local stbCustomW = GUI:CreateFormColorPicker(sSTB.frame, nil, "statusTrackingBarsBarColor", general, RefreshStatusTrackingBars, {},
        { description = "Custom fill color used when the bar fill mode is set to Custom color." })
    sSTB.AddRow(
        row(sSTB.frame, "Bar fill color", stbColorModeW),
        row(sSTB.frame, "Custom bar fill", stbCustomW)
    )

    local stbHeightW = GUI:CreateFormSlider(sSTB.frame, nil, 0, 24, 1, "statusTrackingBarsBarHeight", general, RefreshStatusTrackingBars,
        { description = "Pixel height of the tracking bar. Set to 0 to keep the default height." })
    local stbWidthW = GUI:CreateFormSlider(sSTB.frame, nil, 25, 100, 1, "statusTrackingBarsBarWidthPercent", general, RefreshStatusTrackingBars,
        { description = "Width of the tracking bar as a percentage of its default width." })
    sSTB.AddRow(
        row(sSTB.frame, "Bar height (0 = default)", stbHeightW),
        row(sSTB.frame, "Bar width %", stbWidthW)
    )

    local stbShowBorderW = GUI:CreateFormCheckbox(sSTB.frame, nil, "statusTrackingBarsShowBorder", general, RefreshStatusTrackingBars,
        { description = "Draw a 1px border around the tracking bars using the global skin border style." })
    local stbBorderThickW = GUI:CreateFormSlider(sSTB.frame, nil, 0, 8, 1, "statusTrackingBarsBorderThickness", general, RefreshStatusTrackingBars,
        { description = "Thickness of the tracking bar border in pixels. 0 uses the automatic pixel-perfect value." })
    sSTB.AddRow(
        row(sSTB.frame, "Show bar border", stbShowBorderW),
        row(sSTB.frame, "Border thickness (0 = auto)", stbBorderThickW)
    )

    local stbShowTextW = GUI:CreateFormCheckbox(sSTB.frame, nil, "statusTrackingBarsShowBarText", general, RefreshStatusTrackingBars,
        { description = "Show the XP, reputation, or honor numeric text on top of the bar." })
    local stbAlwaysW = GUI:CreateFormCheckbox(sSTB.frame, nil, "statusTrackingBarsBarTextAlways", general, RefreshStatusTrackingBars,
        { description = "Keep the bar text visible at all times, ignoring Blizzard's mouseover-only default behavior." })
    sSTB.AddRow(
        row(sSTB.frame, "Show bar text", stbShowTextW),
        row(sSTB.frame, "Always show text (ignore game toggle)", stbAlwaysW)
    )

    local stbAnchorW = GUI:CreateFormDropdown(sSTB.frame, nil, {
        { text = "Left", value = "LEFT" },
        { text = "Center", value = "CENTER" },
        { text = "Right", value = "RIGHT" },
    }, "statusTrackingBarsBarTextAnchor", general, RefreshStatusTrackingBars,
        { description = "Horizontal alignment of the bar text." })
    local stbTextColorW = GUI:CreateFormColorPicker(sSTB.frame, nil, "statusTrackingBarsBarTextColor", general, RefreshStatusTrackingBars, {},
        { description = "Color of the numeric text drawn on top of the tracking bar." })
    sSTB.AddRow(
        row(sSTB.frame, "Text position", stbAnchorW),
        row(sSTB.frame, "Text color", stbTextColorW)
    )

    local stbFontSizeW = GUI:CreateFormSlider(sSTB.frame, nil, 6, 24, 1, "statusTrackingBarsBarTextFontSize", general, RefreshStatusTrackingBars,
        { description = "Font size used for the bar text." })
    local stbOutlineW = GUI:CreateFormDropdown(sSTB.frame, nil, {
        { text = "Inherit (global outline)", value = "_inherit" },
        { text = "None", value = "_none" },
        { text = "Thin", value = "OUTLINE" },
        { text = "Thick", value = "THICKOUTLINE" },
    }, "statusTrackingBarsBarTextOutline", general, RefreshStatusTrackingBars,
        { description = "Outline style for the bar text. Inherit follows the global font outline; None removes it; Thin and Thick set explicit widths." })
    sSTB.AddRow(
        row(sSTB.frame, "Text font size", stbFontSizeW),
        row(sSTB.frame, "Text outline", stbOutlineW)
    )

    local stbOffXW = GUI:CreateFormSlider(sSTB.frame, nil, -40, 40, 1, "statusTrackingBarsBarTextOffsetX", general, RefreshStatusTrackingBars,
        { description = "Horizontal pixel offset of the text from its anchor." })
    local stbOffYW = GUI:CreateFormSlider(sSTB.frame, nil, -40, 40, 1, "statusTrackingBarsBarTextOffsetY", general, RefreshStatusTrackingBars,
        { description = "Vertical pixel offset of the text from its anchor." })
    sSTB.AddRow(
        row(sSTB.frame, "Text X offset", stbOffXW),
        row(sSTB.frame, "Text Y offset", stbOffYW)
    )

    AddBorderOverrides(sSTB, general, "statusTrackingBars")
    AddBgOverrides(sSTB, general, "statusTrackingBars")
    L.closeSection(sSTB)

    ---------------------------------------------------------------------------
    -- OBJECTIVE TRACKER
    ---------------------------------------------------------------------------
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

    L.headerAt("Objective Tracker")
    local sOT = L.sectionAt()
    local otSkinW = GUI:CreateFormCheckbox(sOT.frame, nil, "skinObjectiveTracker", general, ReloadConfirm, { description = "Apply the addon skin and font treatment to the quest/objective tracker. Requires a reload." })
    local otClickW = GUI:CreateFormCheckbox(sOT.frame, nil, "objectiveTrackerClickThrough", general, RefreshOT,
        { description = "Let mouse clicks pass through the tracker to the game world behind it. Useful if the tracker overlaps targetable mobs or nodes." })
    sOT.AddRow(
        row(sOT.frame, "Skin Objective Tracker", otSkinW),
        row(sOT.frame, "Click Through", otClickW)
    )

    local otHW = GUI:CreateFormSlider(sOT.frame, nil, 200, 1000, 10, "objectiveTrackerHeight", general, RefreshOT,
        { description = "Maximum pixel height of the tracker. Content past this height scrolls or collapses." })
    local otWW = GUI:CreateFormSlider(sOT.frame, nil, 150, 400, 10, "objectiveTrackerWidth", general, RefreshOT,
        { description = "Maximum pixel width of the tracker." })
    sOT.AddRow(
        row(sOT.frame, "Max Height", otHW),
        row(sOT.frame, "Max Width", otWW)
    )

    local otModuleFW = GUI:CreateFormSlider(sOT.frame, nil, 6, 18, 1, "objectiveTrackerModuleFontSize", general, RefreshOT,
        { description = "Font size of module headers like Quests, Campaign, and World Quests." })
    local otTitleFW = GUI:CreateFormSlider(sOT.frame, nil, 6, 18, 1, "objectiveTrackerTitleFontSize", general, RefreshOT,
        { description = "Font size of individual quest titles listed under each module." })
    sOT.AddRow(
        row(sOT.frame, "Module Header Font", otModuleFW),
        row(sOT.frame, "Quest Title Font", otTitleFW)
    )

    local otTextFW = GUI:CreateFormSlider(sOT.frame, nil, 6, 18, 1, "objectiveTrackerTextFontSize", general, RefreshOT,
        { description = "Font size of the objective/progress text shown beneath each quest title." })
    local otHideBorderW = GUI:CreateFormCheckbox(sOT.frame, nil, "hideObjectiveTrackerBorder", general, RefreshOT,
        { description = "Hide the border drawn around the skinned objective tracker." })
    sOT.AddRow(
        row(sOT.frame, "Objective Text Font", otTextFW),
        row(sOT.frame, "Hide Border", otHideBorderW)
    )

    local otModuleColorW = GUI:CreateFormColorPicker(sOT.frame, nil, "objectiveTrackerModuleColor", general, RefreshOT, nil,
        { description = "Color applied to module header text (Quests, Campaign, etc.)." })
    local otTitleColorW = GUI:CreateFormColorPicker(sOT.frame, nil, "objectiveTrackerTitleColor", general, RefreshOT, nil,
        { description = "Color applied to individual quest title text." })
    sOT.AddRow(
        row(sOT.frame, "Module Header Color", otModuleColorW),
        row(sOT.frame, "Quest Title Color", otTitleColorW)
    )

    local otTextColorW = GUI:CreateFormColorPicker(sOT.frame, nil, "objectiveTrackerTextColor", general, RefreshOT, nil,
        { description = "Color applied to objective/progress text beneath each quest title." })
    sOT.AddRow(row(sOT.frame, "Objective Text Color", otTextColorW))
    L.closeSection(sOT)

    L.finish()
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
        nav = { tileId = "appearance", subPageIndex = 4 },
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
