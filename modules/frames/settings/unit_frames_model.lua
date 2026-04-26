local ADDON_NAME, ns = ...

local Model = ns.QUI_UnitFramesSettingsModel or {}
ns.QUI_UnitFramesSettingsModel = Model

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

local function RenderUnavailable(host, label)
    local message = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOPLEFT", 20, -20)
    message:SetText((label or "Settings") .. " unavailable.")
    message:SetTextColor(0.6, 0.6, 0.6, 1)
end

local function RenderSchema(methodName, host, unitKey, label)
    local schema = ns.QUI_UnitFramesSettingsSchema
    local render = schema and schema[methodName]
    if type(render) == "function" and render(host, unitKey) then
        return true
    end

    RenderUnavailable(host, label)
    return false
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

local TAB_DEFINITIONS = {
    { key = "general", label = "General", render = RenderGeneral },
    { key = "frame", label = "Frame", render = RenderFrame },
    { key = "bars", label = "Bars", render = RenderBars },
    { key = "text", label = "Text", render = RenderText },
    { key = "icons", label = "Icons", render = RenderIcons },
    { key = "indicators", label = "Indicators", render = RenderIndicators },
    { key = "portrait", label = "Portrait", render = RenderPortrait },
    { key = "privateAuras", label = "Priv. Auras", render = RenderPrivateAuras },
}

function Model.GetTabDefinitions()
    return TAB_DEFINITIONS
end
