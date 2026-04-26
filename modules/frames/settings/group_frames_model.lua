local ADDON_NAME, ns = ...

local Model = ns.QUI_GroupFramesSettingsModel or {}
ns.QUI_GroupFramesSettingsModel = Model

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

local function RenderUnavailable(host, label)
    local message = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOPLEFT", 20, -20)
    message:SetText((label or "Settings") .. " settings unavailable (module not loaded).")
end

local function RenderSchema(methodName, host, contextMode, label)
    local schema = ns.QUI_GroupFramesSettingsSchema
    local render = schema and schema[methodName]
    if type(render) == "function" and render(host, contextMode) then
        return true
    end

    RenderUnavailable(host, label)
    return false
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
local RenderAuraIndicators = BuildSchemaRender("RenderAuraIndicatorsTab", "Aura Ind.")
local RenderPinnedAuras = BuildSchemaRender("RenderPinnedAurasTab", "Pinned")
local RenderPrivateAuras = BuildSchemaRender("RenderPrivateAurasTab", "Priv. Auras")
local RenderHealer = BuildSchemaRender("RenderHealerTab", "Healer")
local RenderDefensive = BuildSchemaRender("RenderDefensiveTab", "Defensive")

local TAB_DEFINITIONS = {
    { key = "general", label = "General", render = RenderGeneral },
    { key = "appearance", label = "Appearance", render = RenderAppearance },
    { key = "layout", label = "Layout", render = RenderLayout },
    { key = "dimensions", label = "Dimensions", render = RenderDimensions },
    { key = "rangepet", label = "Range & Pet", render = RenderRangePet },
    { key = "spotlight", label = "Spotlight", visible = function(state) return state.contextMode == "raid" end, render = RenderSpotlight },
    { key = "health", label = "Health", render = RenderHealth },
    { key = "power", label = "Power", render = RenderPower },
    { key = "name", label = "Name", render = RenderName },
    { key = "buffs", label = "Buffs", render = RenderBuffs },
    { key = "debuffs", label = "Debuffs", render = RenderDebuffs },
    { key = "indicators", label = "Indicators", render = RenderIndicators },
    { key = "auraIndicators", label = "Aura Ind.", render = RenderAuraIndicators },
    { key = "pinnedAuras", label = "Pinned", render = RenderPinnedAuras },
    { key = "privateAuras", label = "Priv. Auras", render = RenderPrivateAuras },
    { key = "healer", label = "Healer", render = RenderHealer },
    { key = "defensive", label = "Defensive", render = RenderDefensive },
}

function Model.GetTabDefinitions()
    return TAB_DEFINITIONS
end
