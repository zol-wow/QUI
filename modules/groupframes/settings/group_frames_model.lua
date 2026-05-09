local ADDON_NAME, ns = ...

local Model = ns.QUI_GroupFramesSettingsModel or {}
ns.QUI_GroupFramesSettingsModel = Model
local ModelKit = ns.Settings and ns.Settings.ModelKit

local CONTEXT_ORDER = { "party", "raid" }
local CONTEXT_LABELS = {
    party = "Party",
    raid = "Raid",
}

function Model.GetContextOptions()
    local options = {}
    for _, key in ipairs(CONTEXT_ORDER) do
        options[#options + 1] = {
            value = key,
            text = CONTEXT_LABELS[key],
        }
    end
    return options
end

function Model.NormalizeContextMode(contextMode)
    if type(contextMode) ~= "string" or contextMode == "" or not CONTEXT_LABELS[contextMode] then
        return CONTEXT_ORDER[1]
    end
    return contextMode
end

local function RenderSchema(methodName, host, contextMode, label)
    return ModelKit.RenderSchema(ns.QUI_GroupFramesSettingsSchema, methodName, host, contextMode, label, " settings unavailable (module not loaded).")
end

local function RenderGeneral(host, state)
    local contextMode = state and state.contextMode or nil
    RenderSchema("RenderGeneralTab", host, contextMode, "General")
end

local function BuildSchemaRender(methodName, label)
    return function(host, state)
        local contextMode = state and state.contextMode or nil
        RenderSchema(methodName, host, contextMode, label)
    end
end

local RenderAppearance = BuildSchemaRender("RenderAppearanceTab", "Appearance")
local RenderLayout = BuildSchemaRender("RenderLayoutTab", "Layout")
local RenderDimensions = BuildSchemaRender("RenderDimensionsTab", "Dimensions")
local RenderRangePet = BuildSchemaRender("RenderRangePetTab", "Range & Pet")
local RenderSpotlight = BuildSchemaRender("RenderSpotlightTab", "Spotlight")
local RenderHealth = BuildSchemaRender("RenderHealthTab", "Health")
local RenderPower = BuildSchemaRender("RenderPowerTab", "Power")
local RenderName = BuildSchemaRender("RenderNameTab", "Name")
local RenderBuffs = BuildSchemaRender("RenderBuffsTab", "Buffs")
local RenderDebuffs = BuildSchemaRender("RenderDebuffsTab", "Debuffs")
local RenderIndicators = BuildSchemaRender("RenderIndicatorsTab", "Indicators")
local RenderAuraIndicators = BuildSchemaRender("RenderAuraIndicatorsTab", "Auras")
local RenderPinnedAuras = BuildSchemaRender("RenderPinnedAurasTab", "Pinned Auras")
local RenderPrivateAuras = BuildSchemaRender("RenderPrivateAurasTab", "Private Auras")
local RenderHealer = BuildSchemaRender("RenderHealerTab", "Healer")
local RenderDefensive = BuildSchemaRender("RenderDefensiveTab", "Defensives")
local RenderDispelOverlay = BuildSchemaRender("RenderDispelOverlayTab", "Dispel Overlay")

local TAB_DEFINITIONS = {
    { key = "general", label = "General", row = 1, render = RenderGeneral },
    { key = "appearance", label = "Appearance", row = 1, render = RenderAppearance },
    { key = "layout", label = "Layout", row = 1, render = RenderLayout },
    { key = "dimensions", label = "Dimensions", row = 1, render = RenderDimensions },
    { key = "rangepet", label = "Range & Pet", row = 1, render = RenderRangePet },
    { key = "spotlight", label = "Spotlight", row = 1, visible = function(state) return state.contextMode == "raid" end, render = RenderSpotlight },
    { key = "health", label = "Health", row = 1, render = RenderHealth },
    { key = "power", label = "Power", row = 1, render = RenderPower },
    { key = "name", label = "Name", row = 1, render = RenderName },
    { key = "indicators", label = "Indicators", row = 1, render = RenderIndicators },
    { key = "healer", label = "Healer", row = 1, render = RenderHealer },
    { key = "auraIndicators", label = "Auras", row = 2, render = RenderAuraIndicators },
    { key = "privateAuras", label = "Private Auras", row = 2, render = RenderPrivateAuras },
    { key = "defensive", label = "Defensives", row = 2, render = RenderDefensive },
    { key = "dispelOverlay", label = "Dispel Overlay", row = 2, render = RenderDispelOverlay },
    { key = "debuffs", label = "Debuffs", row = 2, render = RenderDebuffs },
    { key = "buffs", label = "Buffs", row = 2, render = RenderBuffs },
    { key = "pinnedAuras", label = "Pinned Auras", row = 2, render = RenderPinnedAuras },
}

function Model.GetTabDefinitions()
    return ModelKit.NormalizeTabDefinitions(TAB_DEFINITIONS)
end
