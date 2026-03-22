--[[
    QUI Options - Skinning Tab
    BuildSkinningTab for Autohide & Skinning page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options
local Helpers = ns.Helpers

local GetCore = Helpers.GetCore

local function BuildSkinningTab(tabContent)
    local PAD = 10
    local FORM_ROW = 32
    local P = Helpers.PlaceRow
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 7, tabName = "Skinning & Autohide", subTabIndex = 2, subTabName = "Skinning"})

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
    if general.skinThirdParty == nil then general.skinThirdParty = true end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

    -- Helper to refresh all skinned frames
    local function RefreshAllSkinning()
        if ns.Registry then
            ns.Registry:RefreshAll("skinning")
        end
    end

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

        sy = P(GUI:CreateFormCheckbox(body, "Override Global Border", overrideKey, settings, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Border", hideKey, settings, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Color Border", useClassKey, settings, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Border Color", colorKey, settings, RefreshAllSkinning, { noAlpha = true }), body, sy)
        return sy
    end

    -- Background override controls builder (returns new sy)
    local function AddBgOverrides(body, sy, settings, prefix)
        local kp = type(prefix) == "string" and prefix or ""
        local overrideKey = kp ~= "" and (kp .. "BgOverride") or "bgOverride"
        local hideKey = kp ~= "" and (kp .. "HideBackground") or "hideBackground"
        local colorKey = kp ~= "" and (kp .. "BackgroundColor") or "backgroundColor"

        sy = P(GUI:CreateFormCheckbox(body, "Override Global Background", overrideKey, settings, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Background", hideKey, settings, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", colorKey, settings, RefreshAllSkinning), body, sy)
        return sy
    end

    local function ReloadConfirm()
        GUI:ShowConfirmation({
            title = "Reload UI?", message = "Skinning changes require a reload to take effect.",
            acceptText = "Reload", cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end

    ---------------------------------------------------------------------------
    -- Choose Default Color
    ---------------------------------------------------------------------------
    if general.skinBgColor == nil then general.skinBgColor = {0.05, 0.05, 0.05, 0.95} end

    CreateCollapsible("Choose Default Color", 7 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Colors", "skinUseClassColor", general, function()
            if general.skinUseClassColor then
                local _, class = UnitClass("player")
                local color = RAID_CLASS_COLORS[class]
                if color and GUI.ApplyAccentColor then GUI:ApplyAccentColor(color.r, color.g, color.b) end
            else
                local c = general.addonAccentColor or {0.376, 0.647, 0.980, 1}
                if GUI.ApplyAccentColor then GUI:ApplyAccentColor(c[1], c[2], c[3]) end
            end
            RefreshAllSkinning()
            if GUI.RefreshAccentColor then GUI:RefreshAccentColor() end
        end), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Accent Color", "addonAccentColor", general, function(r, g, b)
            if GUI.ApplyAccentColor then GUI:ApplyAccentColor(r, g, b) end
            RefreshAllSkinning()
            if not GUI._accentPickerWatcher then
                local watcher = CreateFrame("Frame")
                GUI._accentPickerWatcher = watcher
                watcher:SetScript("OnUpdate", function(self)
                    if not ColorPickerFrame:IsShown() then
                        self:SetScript("OnUpdate", nil); GUI._accentPickerWatcher = nil
                        if GUI.RefreshAccentColor then GUI:RefreshAccentColor() end
                    end
                end)
            end
        end, { noAlpha = true }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", "skinBgColor", general, RefreshAllSkinning, { hasAlpha = true }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Borders", "hideSkinBorders", general, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Borders", "skinBorderUseClassColor", general, RefreshAllSkinning), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Border Color", "skinBorderColor", general, RefreshAllSkinning, { noAlpha = true }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Game Menu
    ---------------------------------------------------------------------------
    if general.skinGameMenu == nil then general.skinGameMenu = false end
    if general.addQUIButton == nil then general.addQUIButton = false end
    if general.gameMenuFontSize == nil then general.gameMenuFontSize = 12 end
    if general.gameMenuDim == nil then general.gameMenuDim = true end

    CreateCollapsible("Game Menu", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Skin Game Menu (Req. Reload)", "skinGameMenu", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Add QUI Button (Req. Reload)", "addQUIButton", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Button Font Size", 8, 18, 1, "gameMenuFontSize", general, function()
            if _G.QUI_RefreshGameMenuFontSize then _G.QUI_RefreshGameMenuFontSize() end
        end), body, sy)
        P(GUI:CreateFormCheckbox(body, "Dim Background", "gameMenuDim", general, function()
            if _G.QUI_RefreshGameMenuDim then _G.QUI_RefreshGameMenuDim() end
        end), body, sy)
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
        sy = P(GUI:CreateFormCheckbox(body, "Skin Loot Window (Req. Reload)", "enabled", lootDB, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Loot Under Mouse", "lootUnderMouse", lootDB), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Loot Cursor X Offset", -200, 200, 1, "lootUnderMouseOffsetX", lootDB), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Loot Cursor Y Offset", -200, 200, 1, "lootUnderMouseOffsetY", lootDB), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Transmog Markers", "showTransmogMarker", lootDB), body, sy)
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
        sy = P(GUI:CreateFormCheckbox(body, "Skin Roll Frames (Req. Reload)", "enabled", lootRollDB, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Grow Direction", {
            {value = "DOWN", text = "Down"}, {value = "UP", text = "Up"},
        }, "growDirection", lootRollDB, RefreshRollPreview), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Max Visible Frames", 1, 8, 1, "maxFrames", lootRollDB, RefreshRollPreview), body, sy)
        P(GUI:CreateFormSlider(body, "Frame Spacing", 0, 20, 1, "spacing", lootRollDB, RefreshRollPreview), body, sy)
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

    CreateCollapsible("Skin Blizzard Frames", 12 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Alert Frames (Req. Reload)", "skinAlerts", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Auction House (Req. Reload)", "skinAuctionHouse", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Crafting Orders (Req. Reload)", "skinCraftingOrders", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Encounter Power Bar (Req. Reload)", "skinPowerBarAlt", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Inspect Frame (Req. Reload)", "skinInspectFrame", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Instance Frames (Req. Reload)", "skinInstanceFrames", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Keystone Window (Req. Reload)", "skinKeystoneFrame", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Loot History (Req. Reload)", "enabled", db.lootResults, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Override Action Bar (Req. Reload)", "skinOverrideActionBar", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Professions (Req. Reload)", "skinProfessions", general, ReloadConfirm), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Reputation/Currency (Req. Reload)", "skinCharacterFrame", general, ReloadConfirm), body, sy)
        P(GUI:CreateFormCheckbox(body, "Suppress White Backdrops & NineSlice Borders", "skinThirdParty", general, RefreshAllSkinning), body, sy)
    end)

    relayout()
end

-- Export
ns.QUI_SkinningOptions = {
    BuildSkinningTab = BuildSkinningTab
}
