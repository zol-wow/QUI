local ADDON_NAME, ns = ...

local Model = ns.QUI_NameplatesSettingsModel or {}
ns.QUI_NameplatesSettingsModel = Model
local ModelKit = ns.Settings and ns.Settings.ModelKit

local function ResolvePlateType()
    local NP = ns.QUI_Nameplates
    return NP and NP.PlateType or nil
end

local function ResolveTypeOrder()
    local plateType = ResolvePlateType()
    local order = plateType and plateType.ORDER
    if type(order) == "table" then
        return order
    end
    return nil
end

local TYPE_LABELS = {
    petMinion    = ns.L["Pets & Minions"],
    friendly     = ns.L["Friendly"],
    bossElite    = ns.L["Bosses & Elites"],
    minorTrivial = ns.L["Minor & Trivial"],
    enemyPlayer  = ns.L["Enemy Players"],
    enemyNPC     = ns.L["Enemy NPCs"],
}

local PER_TYPE_TABS = {
    frame = true,
    text = true,
    indicators = true,
    auras = true,
    castbars = true,
    colors = true,
}

function Model.GetTypeOptions()
    local order = ResolveTypeOrder()
    if not order then
        return {}
    end
    local options = {}
    for _, key in ipairs(order) do
        options[#options + 1] = { value = key, text = TYPE_LABELS[key] or key }
    end
    return options
end

function Model.NormalizeTypeKey(typeKey)
    if type(typeKey) == "string" and TYPE_LABELS[typeKey] then
        return typeKey
    end
    local order = ResolveTypeOrder()
    if not order then return nil end
    local default = ResolvePlateType().DEFAULT_KEY
    for _, key in ipairs(order) do
        if key == default then return default end
    end
    return order[1]
end

function Model.IsPerTypeTab(tabKey)
    return PER_TYPE_TABS[tabKey] == true
end

local function RenderSchema(methodName, host, typeKey, label)
    return ModelKit.RenderSchema(ns.QUI_NameplatesSettingsSchema, methodName, host, typeKey, label, ns.L[" settings unavailable (module not loaded)."])
end

local function BuildSchemaRender(methodName, label)
    return function(host)
        RenderSchema(methodName, host, nil, label)
    end
end

local function BuildPerTypeSchemaRender(methodName, label)
    return function(host, state)
        local typeKey = state and state.selectedType or nil
        RenderSchema(methodName, host, typeKey, label)
    end
end

local RenderGeneral = BuildSchemaRender("RenderGeneralTab", ns.L["General"])
local RenderVisibility = BuildSchemaRender("RenderVisibilityTab", ns.L["Visibility"])
local RenderFrame = BuildPerTypeSchemaRender("RenderFrameTab", ns.L["Frame"])
local RenderText = BuildPerTypeSchemaRender("RenderTextTab", ns.L["Text"])
local RenderIndicators = BuildPerTypeSchemaRender("RenderIndicatorsTab", ns.L["Indicators"])
local RenderAuras = BuildPerTypeSchemaRender("RenderAurasTab", ns.L["Auras"])
local RenderCastbars = BuildPerTypeSchemaRender("RenderCastbarsTab", ns.L["Castbar"])
local RenderColors = BuildPerTypeSchemaRender("RenderColorsTab", ns.L["Colors"])

local TAB_DEFINITIONS = {
    { key = "general", label = ns.L["General"], render = RenderGeneral },
    { key = "visibility", label = ns.L["Visibility"], render = RenderVisibility },
    { key = "frame", label = ns.L["Frame"], render = RenderFrame },
    { key = "text", label = ns.L["Text"], render = RenderText },
    { key = "indicators", label = ns.L["Indicators"], render = RenderIndicators },
    { key = "auras", label = ns.L["Auras"], render = RenderAuras },
    { key = "castbars", label = ns.L["Castbar"], render = RenderCastbars },
    { key = "colors", label = ns.L["Colors"], render = RenderColors },
}

function Model.GetTabDefinitions()
    return ModelKit.NormalizeTabDefinitions(TAB_DEFINITIONS)
end
