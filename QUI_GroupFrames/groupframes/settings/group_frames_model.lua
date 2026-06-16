local ADDON_NAME, ns = ...

local Model = ns.QUI_GroupFramesSettingsModel or {}
ns.QUI_GroupFramesSettingsModel = Model
local ModelKit = ns.Settings and ns.Settings.ModelKit

local CONTEXT_ORDER = { "party", "raid" }
local CONTEXT_LABELS = {
    party = ns.L["Party"],
    raid = ns.L["Raid"],
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
    return ModelKit.RenderSchema(ns.QUI_GroupFramesSettingsSchema, methodName, host, contextMode, label, ns.L[" settings unavailable (module not loaded)."])
end

local function BuildSchemaRender(methodName, label)
    return function(host, state)
        local contextMode = state and state.contextMode or nil
        RenderSchema(methodName, host, contextMode, label)
    end
end

local RenderGeneral = BuildSchemaRender("RenderGeneralTab", ns.L["General"])
local RenderAppearance = BuildSchemaRender("RenderAppearanceTab", ns.L["Appearance"])
local RenderLayout = BuildSchemaRender("RenderLayoutTab", ns.L["Layout"])
local RenderHealth = BuildSchemaRender("RenderHealthTab", ns.L["Health"])
local RenderIndicators = BuildSchemaRender("RenderIndicatorsTab", ns.L["Indicators"])
local RenderAuras = BuildSchemaRender("RenderAurasTab", ns.L["Auras"])

-- Order only; the tab strip wraps these across rows responsively by window
-- width (group_frames_surface.lua uses wrapRows), so no explicit row field.
-- Spotlight was folded into Layout (raid only) and Dispel Overlay into
-- Appearance, so neither is a standalone tab any more.
local TAB_DEFINITIONS = {
    { key = "general", label = ns.L["General"], render = RenderGeneral },
    { key = "appearance", label = ns.L["Appearance"], render = RenderAppearance },
    { key = "layout", label = ns.L["Layout"], render = RenderLayout },
    { key = "health", label = ns.L["Health"], render = RenderHealth },
    { key = "indicators", label = ns.L["Indicators"], render = RenderIndicators },
    { key = "auras", label = ns.L["Auras"], render = RenderAuras },
}

function Model.GetTabDefinitions()
    return ModelKit.NormalizeTabDefinitions(TAB_DEFINITIONS)
end
