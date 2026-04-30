local ADDON_NAME, ns = ...

local Model = ns.QUI_UnitFramesSettingsModel or {}
ns.QUI_UnitFramesSettingsModel = Model
local ModelKit = ns.Settings and ns.Settings.ModelKit

local UNIT_ORDER = { "player", "target", "focus", "targettarget", "pet", "boss" }
local UNIT_LABELS = {
    player = "Player",
    target = "Target",
    focus = "Focus",
    targettarget = "Target of Target",
    pet = "Pet",
    boss = "Boss",
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
    RenderSchema("RenderGeneralTab", host, nil, "General")
end

local function RenderFrame(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderFrameTab", host, unitKey, "Frame")
end

local function RenderBars(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderBarsTab", host, unitKey, "Bars")
end

local function RenderText(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderTextTab", host, unitKey, "Text")
end

local function RenderIcons(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderIconsTab", host, unitKey, "Icons")
end

local function RenderPortrait(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderPortraitTab", host, unitKey, "Portrait")
end

local function RenderIndicators(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderIndicatorsTab", host, unitKey, "Indicators")
end

local function RenderPrivateAuras(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderPrivateAurasTab", host, unitKey, "Priv. Auras")
end

local function RenderCastbar(host, state)
    local unitKey = state and state.selectedUnit or nil
    RenderSchema("RenderCastbarTab", host, unitKey, "Castbar")
end

local TAB_DEFINITIONS = {
    { key = "general", label = "General", render = RenderGeneral },
    { key = "frame", label = "Frame", render = RenderFrame },
    { key = "bars", label = "Bars", render = RenderBars },
    { key = "castbar", label = "Castbar", render = RenderCastbar },
    { key = "text", label = "Text", render = RenderText },
    { key = "icons", label = "Icons", render = RenderIcons },
    { key = "indicators", label = "Indicators", render = RenderIndicators },
    { key = "portrait", label = "Portrait", render = RenderPortrait },
    { key = "privateAuras", label = "Priv. Auras", render = RenderPrivateAuras },
}

function Model.GetTabDefinitions()
    return ModelKit.NormalizeTabDefinitions(TAB_DEFINITIONS)
end
