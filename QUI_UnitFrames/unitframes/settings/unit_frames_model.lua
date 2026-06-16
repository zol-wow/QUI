local ADDON_NAME, ns = ...

local Model = ns.QUI_UnitFramesSettingsModel or {}
ns.QUI_UnitFramesSettingsModel = Model
local ModelKit = ns.Settings and ns.Settings.ModelKit

local UNIT_ORDER = { "player", "target", "focus", "targettarget", "pet", "boss" }
-- Shared unit -> display-name map (single source of truth lives in
-- unit_frames_schema.lua, which loads first). Fall back to a local copy so the
-- model still works if loaded without the schema present.
local UNIT_LABELS = ns.QUI_UnitFramesUnitDisplayNames or {
    player = ns.L["Player"],
    target = ns.L["Target"],
    focus = ns.L["Focus"],
    targettarget = ns.L["Target of Target"],
    pet = ns.L["Pet"],
    boss = ns.L["Boss"],
}

local PER_UNIT_TABS = {
    frame = true,
    bars = true,
    text = true,
    icons = true,
    indicators = true,
    portrait = true,
    privateAuras = true,
    castbar = true,
}

function Model.GetUnitOptions()
    local options = {}
    for _, key in ipairs(UNIT_ORDER) do
        options[#options + 1] = {
            value = key,
            text = UNIT_LABELS[key],
        }
    end
    return options
end

function Model.NormalizeUnitKey(unitKey)
    if type(unitKey) ~= "string" or unitKey == "" or not UNIT_LABELS[unitKey] then
        return UNIT_ORDER[1]
    end
    return unitKey
end

function Model.IsPerUnitTab(tabKey)
    return PER_UNIT_TABS[tabKey] == true
end

local function RenderSchema(methodName, host, unitKey, label)
    return ModelKit.RenderSchema(ns.QUI_UnitFramesSettingsSchema, methodName, host, unitKey, label)
end

local function RenderGeneral(host)
    RenderSchema("RenderGeneralTab", host, nil, ns.L["General"])
end

local function RenderFrame(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderFrameTab", host, unitKey, ns.L["Frame"])
end

local function RenderBars(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderBarsTab", host, unitKey, ns.L["Bars"])
end

local function RenderText(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderTextTab", host, unitKey, ns.L["Text"])
end

local function RenderIcons(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderIconsTab", host, unitKey, ns.L["Icons"])
end

local function RenderPortrait(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderPortraitTab", host, unitKey, ns.L["Portrait"])
end

local function RenderIndicators(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderIndicatorsTab", host, unitKey, ns.L["Indicators"])
end

local function RenderPrivateAuras(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderPrivateAurasTab", host, unitKey, ns.L["Priv. Auras"])
end

local function RenderCastbar(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderCastbarTab", host, unitKey, ns.L["Castbar"])
end

local TAB_DEFINITIONS = {
    { key = "general", label = ns.L["General"], render = RenderGeneral },
    { key = "frame", label = ns.L["Frame"], render = RenderFrame },
    { key = "bars", label = ns.L["Bars"], render = RenderBars },
    { key = "castbar", label = ns.L["Castbar"], render = RenderCastbar },
    { key = "text", label = ns.L["Text"], render = RenderText },
    { key = "icons", label = ns.L["Icons"], render = RenderIcons },
    { key = "indicators", label = ns.L["Indicators"], render = RenderIndicators },
    { key = "portrait", label = ns.L["Portrait"], render = RenderPortrait },
    { key = "privateAuras", label = ns.L["Priv. Auras"], render = RenderPrivateAuras },
}

function Model.GetTabDefinitions()
    return ModelKit.NormalizeTabDefinitions(TAB_DEFINITIONS)
end
