local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function GetActionBarsDB()
    local QUI = _G.QUI
    local profile = QUI and QUI.db and QUI.db.profile
    return profile and profile.actionBars or nil
end

local function NotifyActionBarsModuleChanged()
    if ns.QUI_Modules then
        ns.QUI_Modules:NotifyChanged("actionBarsGeneral")
        ns.QUI_Modules:NotifyChanged("actionBars")
    end
end

local function ShowActionBarsReloadPrompt()
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    if GUI and GUI.ShowConfirmation then
        GUI:ShowConfirmation({
            title = "Reload UI?",
            message = "Enabling or disabling action bars requires a UI reload to take effect.",
            acceptText = "Reload",
            cancelText = "Later",
            onAccept = function()
                if QUI and QUI.SafeReload then
                    QUI:SafeReload()
                end
            end,
        })
    end
end

local function SetActionBarsModuleEnabled(val)
    local db = GetActionBarsDB()
    if not db then return end

    local enabled = val ~= false
    local old = db.enabled ~= false
    db.enabled = enabled

    NotifyActionBarsModuleChanged()
    if enabled ~= old then
        ShowActionBarsReloadPrompt()
    end
end

local ActionBarsModuleEntry = {
    group = "Action Bars",
    label = "Action Bars",
    caption = "Master toggle for QUI's action bar system.",
    order = -1,
    combatLocked = true,
    isEnabled = function()
        local db = GetActionBarsDB()
        return db and db.enabled ~= false
    end,
    setEnabled = SetActionBarsModuleEnabled,
}

local function RenderBuilder(host, ownerName, fnName)
    local owner = ns[ownerName]
    local render = owner and owner[fnName]
    if type(render) ~= "function" then
        return nil
    end
    local result = render(host)
    if type(result) == "number" then
        return result
    end
    return host and host.GetHeight and host:GetHeight() or nil
end

local function RenderLayoutRoute(host, options, fallbackKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return 80
    end

    local routeKey = options and options.providerKey or fallbackKey
    if type(routeKey) ~= "string" or routeKey == "" then
        routeKey = fallbackKey
    end
    if type(routeKey) ~= "string" or routeKey == "" then
        return 80
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    U.BuildPositionCollapsible(host, routeKey, nil, sections, relayout)
    U.BuildOpenFullSettingsLink(host, routeKey, sections, relayout)
    relayout()
    return host:GetHeight()
end

Registry:RegisterFeature(Schema.Feature({
    id = "actionBarsGeneral",
    moverKey = "bar1",
    lookupKeys = { "extraActionButton", "zoneAbility", "totemBar" },
    category = "frames",
    moduleEntry = ActionBarsModuleEntry,
    nav = {
        tileId = "action_bars",
        subPageIndex = 1,
    },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = function(host)
                return RenderBuilder(host, "QUI_ActionBarsOptions", "BuildMasterSettingsTab")
            end,
        }),
    },
    render = {
        layout = function(host, options)
            return RenderLayoutRoute(host, options, "extraActionButton")
        end,
    },
}))

Registry:RegisterFeature(Schema.Feature({
    id = "actionBarsBuffDebuff",
    moverKey = "buffDebuff",
    lookupKeys = { "buffFrame", "debuffFrame" },
    category = "frames",
    nav = {
        tileId = "action_bars",
        subPageIndex = 2,
    },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = function(host)
                return RenderBuilder(host, "QUI_BuffDebuffOptions", "BuildBuffDebuffTab")
            end,
        }),
    },
    render = {
        layout = function(host, options)
            return RenderLayoutRoute(host, options, "buffFrame")
        end,
    },
}))
