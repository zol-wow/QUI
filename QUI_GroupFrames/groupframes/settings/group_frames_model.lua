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

local function BuildSchemaRender(methodName, label)
    return function(host, state)
        local contextMode = state and state.contextMode or nil
        RenderSchema(methodName, host, contextMode, label)
    end
end

local RenderGeneral = BuildSchemaRender("RenderGeneralTab", "General")
local RenderAppearance = BuildSchemaRender("RenderAppearanceTab", "Appearance")
local RenderLayout = BuildSchemaRender("RenderLayoutTab", "Layout")
local RenderSpotlight = BuildSchemaRender("RenderSpotlightTab", "Spotlight")
local RenderHealth = BuildSchemaRender("RenderHealthTab", "Health")
local RenderIndicators = BuildSchemaRender("RenderIndicatorsTab", "Indicators")
local RenderAuras = BuildSchemaRender("RenderAurasTab", "Auras")
local RenderDispelOverlay = BuildSchemaRender("RenderDispelOverlayTab", "Dispel Overlay")

-- Order only; the tab strip wraps these across rows responsively by window
-- width (group_frames_surface.lua uses wrapRows), so no explicit row field.
local TAB_DEFINITIONS = {
    { key = "general", label = "General", render = RenderGeneral },
    { key = "appearance", label = "Appearance", render = RenderAppearance },
    { key = "layout", label = "Layout", render = RenderLayout },
    { key = "spotlight", label = "Spotlight", visible = function(state) return state.contextMode == "raid" end, render = RenderSpotlight },
    { key = "health", label = "Health", render = RenderHealth },
    { key = "indicators", label = "Indicators", render = RenderIndicators },
    { key = "auras", label = "Auras", render = RenderAuras },
    { key = "dispelOverlay", label = "Dispel Overlay", render = RenderDispelOverlay },
}

function Model.GetTabDefinitions()
    return ModelKit.NormalizeTabDefinitions(TAB_DEFINITIONS)
end
