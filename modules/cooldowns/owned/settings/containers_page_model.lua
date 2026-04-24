local ADDON_NAME, ns = ...

local QUI = QUI

local Model = ns.QUI_CooldownManagerSettingsModel or {}
ns.QUI_CooldownManagerSettingsModel = Model

local BUILTIN_ORDER = { "essential", "utility", "buff", "trackedBar" }
local BUILTIN_LABELS = {
    essential = "Essential",
    utility = "Utility",
    buff = "Buff Icons",
    trackedBar = "Buff Bars",
}

function Model.GetContainerOptions()
    local options = {}
    local seen = {}
    for _, key in ipairs(BUILTIN_ORDER) do
        if not seen[key] then
            options[#options + 1] = {
                value = key,
                text = BUILTIN_LABELS[key],
            }
            seen[key] = true
        end
    end

    local ncdm = QUI and QUI.db and QUI.db.profile and QUI.db.profile.ncdm
    if ncdm and ncdm.containers then
        local customKeys = {}
        for key in pairs(ncdm.containers) do
            if not BUILTIN_LABELS[key] and not seen[key] then
                customKeys[#customKeys + 1] = key
                seen[key] = true
            end
        end
        table.sort(customKeys)
        for _, key in ipairs(customKeys) do
            local settings = ncdm.containers[key]
            options[#options + 1] = {
                value = key,
                text = (settings and settings.name) or key,
            }
        end
    end

    return options
end

function Model.IsBuiltIn(containerKey)
    for _, key in ipairs(BUILTIN_ORDER) do
        if key == containerKey then
            return true
        end
    end
    return false
end

function Model.HasContainer(containerKey)
    if Model.IsBuiltIn(containerKey) then
        return true
    end

    local ncdm = QUI and QUI.db and QUI.db.profile and QUI.db.profile.ncdm
    return ncdm and ncdm.containers and ncdm.containers[containerKey] ~= nil
end

function Model.NormalizeContainerKey(containerKey)
    if type(containerKey) == "string" and containerKey ~= "" and Model.HasContainer(containerKey) then
        return containerKey
    end
    return BUILTIN_ORDER[1]
end

local function RenderUnavailable(host, label)
    local message = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOPLEFT", 20, -20)
    message:SetText((label or "Settings") .. " settings unavailable (module not loaded).")
end

local function SetSearchContext(label)
    local gui = QUI and QUI.GUI
    if gui and type(gui.SetSearchContext) == "function" then
        gui:SetSearchContext({
            tabIndex = 4,
            tabName = "Cooldown Manager",
            subTabIndex = 0,
            subTabName = label or "Containers",
        })
    end
end

local function RenderSchema(methodName, host, containerKey, label)
    local schema = ns.QUI_CooldownManagerSettingsSchema
    local render = schema and schema[methodName]
    if type(render) == "function" and render(host, containerKey) then
        return true
    end

    RenderUnavailable(host, label)
    return false
end

local function BuildSchemaRender(methodName, label)
    return function(host, state)
        local containerKey = state and state.activeContainer or nil
        RenderSchema(methodName, host, containerKey, label)
    end
end

local function RenderEntriesTab(host, state)
    SetSearchContext("Entries")

    local containerKey = state and state.activeContainer or nil
    if type(containerKey) ~= "string" or containerKey == "" or not _G.QUI_EmbedCDMComposer then
        RenderUnavailable(host, "Entries")
        return false
    end

    host._hideComposerNav = true
    _G.QUI_EmbedCDMComposer(host, containerKey)
    return true
end

local TAB_DEFINITIONS = {
    { key = "entries", label = "Entries", hostKey = "composer", render = RenderEntriesTab },
    { key = "layout", label = "Appearance", hostKey = "scroll", render = BuildSchemaRender("RenderLayoutTab", "Appearance") },
    { key = "filters", label = "Filters", hostKey = "scroll", visible = function(state) return not Model.IsBuiltIn(state.activeContainer) end, render = BuildSchemaRender("RenderFiltersTab", "Filters") },
    { key = "perspec", label = "Per-Spec", hostKey = "scroll", visible = function(state) return not Model.IsBuiltIn(state.activeContainer) end, render = BuildSchemaRender("RenderPerSpecTab", "Per-Spec") },
    { key = "effects", label = "Effects", hostKey = "scroll", render = BuildSchemaRender("RenderEffectsTab", "Effects") },
    { key = "keybinds", label = "Keybinds", hostKey = "scroll", render = BuildSchemaRender("RenderKeybindsTab", "Keybinds") },
}

function Model.GetTabDefinitions()
    return TAB_DEFINITIONS
end
