--[[
    QUI Options - Damage Meter
    Builds the Appearance > Damage Meter sub-page.
    Owns: Skin master toggle, Behavior controls (relocated from
    skinning_content.lua), Textures, Fonts.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local DAMAGE_METER_SUBPAGE_INDEX = 10  -- assigned in options/tiles/appearance.lua

-- Build a (value, text) options table from LSM, sorted alphabetically.
local function BuildLSMOptions(lsmType)
    local options = {}
    if not LSM or type(LSM.HashTable) ~= "function" then return options end
    for name in pairs(LSM:HashTable(lsmType)) do
        options[#options + 1] = { value = name, text = name }
    end
    table.sort(options, function(a, b) return a.text < b.text end)
    return options
end

local function BuildDamageMeterTab(tabContent)
    local PAD = 10
    local FORM_ROW = 32
    local P = Helpers.PlaceRow
    local db = Shared.GetDB()
    if not db then return end

    GUI:SetSearchContext({
        tileId = "appearance",
        tabName = "Appearance",
        subPageIndex = DAMAGE_METER_SUBPAGE_INDEX,
        subTabName = "Damage Meter",
        featureId = "damageMeterPage",
        category = "appearance",
    })

    if not db.general then db.general = {} end
    local general = db.general
    if general.skinDamageMeter == nil then general.skinDamageMeter = true end

    if not db.damageMeter then db.damageMeter = {} end
    local dm = db.damageMeter

    local function RefreshSkin()
        if _G.QUI_RefreshDamageMeterSkin then _G.QUI_RefreshDamageMeterSkin() end
    end
    local function WriteDM()
        if _G.QUI_DamageMeter_ApplyToBlizzard then _G.QUI_DamageMeter_ApplyToBlizzard() end
    end

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

    ---------------------------------------------------------------------------
    -- Master toggle (relocated from skinning_content.lua:500-502)
    ---------------------------------------------------------------------------
    CreateCollapsible("Skin Damage Meter", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        P(GUI:CreateFormCheckbox(body, "Skin Damage Meter", "skinDamageMeter", general, RefreshSkin,
            { description = "Skin Blizzard's built-in damage meter (Midnight 12.0+) when enabled in WoW's Gameplay Enhancements options." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Behavior (relocated from skinning_content.lua:596-632)
    ---------------------------------------------------------------------------
    CreateCollapsible("Behavior", 11 * FORM_ROW + 8, function(body)
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

    ---------------------------------------------------------------------------
    -- Textures
    ---------------------------------------------------------------------------
    if not dm.appearance then dm.appearance = { global = {} } end
    if not dm.appearance.global then dm.appearance.global = {} end
    if not dm.appearance.global.textures then
        dm.appearance.global.textures = { bar = nil, background = nil, border = nil }
    end
    local textures = dm.appearance.global.textures

    local statusbarOptions  = BuildLSMOptions("statusbar")
    local backgroundOptions = BuildLSMOptions("background")
    local borderOptions     = BuildLSMOptions("border")

    CreateCollapsible("Textures", 3 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormDropdown(body, "Bar Texture", statusbarOptions, "bar", textures, RefreshSkin,
            { description = "Texture used for the bar fill on each row." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Background Texture", backgroundOptions, "background", textures, RefreshSkin,
            { description = "Texture used for the row background fill behind each bar." }), body, sy)
        P(GUI:CreateFormDropdown(body, "Border Texture", borderOptions, "border", textures, RefreshSkin,
            { description = "Texture used for the 1px border around each row." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- Fonts
    ---------------------------------------------------------------------------
    if not dm.appearance.global.fonts then
        dm.appearance.global.fonts = {
            rowName  = { name = nil, size = 0, outline = "_inherit" },
            rowValue = { name = nil, size = 0, outline = "_inherit" },
            header   = { name = nil, size = 0, outline = "_inherit" },
        }
    end
    local fonts = dm.appearance.global.fonts

    local fontOptions = BuildLSMOptions("font")
    local outlineOptions = {
        { value = "_inherit",     text = "Inherit (global outline)" },
        { value = "_none",        text = "None" },
        { value = "OUTLINE",      text = "Thin" },
        { value = "THICKOUTLINE", text = "Thick" },
    }

    -- Each font picker = 3 rows (font, size, outline). Three pickers = 9 rows.
    -- Plus a row of section headers for clarity = 12 rows.
    CreateCollapsible("Fonts", 12 * FORM_ROW + 8, function(body)
        local sy = -4

        -- Row Name
        sy = P(GUI:CreateFormDropdown(body, "Row Name Font", fontOptions, "name", fonts.rowName, RefreshSkin,
            { description = "Font used for player names on each row." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Row Name Size (0 = default)", 0, 24, 1, "size", fonts.rowName, RefreshSkin, nil,
            { description = "Font size for player names. 0 preserves the default size." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Row Name Outline", outlineOptions, "outline", fonts.rowName, RefreshSkin,
            { description = "Outline style for player names. Inherit follows the global font outline." }), body, sy)

        -- Row Value
        sy = P(GUI:CreateFormDropdown(body, "Row Value Font", fontOptions, "name", fonts.rowValue, RefreshSkin,
            { description = "Font used for damage/healing values on each row." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Row Value Size (0 = default)", 0, 24, 1, "size", fonts.rowValue, RefreshSkin, nil,
            { description = "Font size for row values. 0 preserves the default size." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Row Value Outline", outlineOptions, "outline", fonts.rowValue, RefreshSkin,
            { description = "Outline style for row values. Inherit follows the global font outline." }), body, sy)

        -- Header
        sy = P(GUI:CreateFormDropdown(body, "Header Font", fontOptions, "name", fonts.header, RefreshSkin,
            { description = "Font used for the session window header." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Header Size (0 = default)", 0, 24, 1, "size", fonts.header, RefreshSkin, nil,
            { description = "Font size for the header. 0 preserves the default size." }), body, sy)
        P(GUI:CreateFormDropdown(body, "Header Outline", outlineOptions, "outline", fonts.header, RefreshSkin,
            { description = "Outline style for the header. Inherit follows the global font outline." }), body, sy)
    end)

    relayout()
end

ns.QUI_DamageMeterOptions = {
    BuildDamageMeterTab = BuildDamageMeterTab,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "damageMeterPage",
        moverKey = "damageMeter",
        lookupKeys = { "damageMeter", "meter", "skinDamageMeter" },
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = DAMAGE_METER_SUBPAGE_INDEX },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildDamageMeterTab,
            }),
        },
    }))
end
