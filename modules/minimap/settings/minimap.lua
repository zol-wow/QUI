local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

local function RefreshMinimapSurface()
    if _G.QUI_RefreshMinimap then
        _G.QUI_RefreshMinimap()
    end
end

local function GetProfile()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    return core and core.db and core.db.profile or nil
end

local function SetActiveDatatextPanel(lookupKey)
    local selection = ns.QUI_DatatextPanelSelection
    if not selection or type(selection.setActivePanel) ~= "function" then
        return nil
    end
    return selection.setActivePanel(lookupKey, GetProfile())
end

local function RenderDatatextLayout(host, options)
    local U = ns.QUI_LayoutMode_Utils
    if not host or not U
        or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return 80
    end

    local providerKey = options and options.providerKey or "datatextPanel"
    local profile = GetProfile()
    local selection = ns.QUI_DatatextPanelSelection
    local positionKey, anchorOpts = "datatextPanel", nil

    if selection then
        if type(selection.setActivePanel) == "function" then
            selection.setActivePanel(providerKey, profile)
        end
        if type(selection.getPositionTarget) == "function" then
            positionKey, anchorOpts = selection.getPositionTarget(profile, providerKey)
        end
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    U.BuildPositionCollapsible(host, positionKey or "datatextPanel", anchorOpts, sections, relayout)
    U.BuildOpenFullSettingsLink(host, providerKey, sections, relayout)
    relayout()
    return host:GetHeight()
end

ProviderFeatures:Register({
    id = "minimap",
    moverKey = "minimap",
    category = "ui",
    nav = {
        tileId = "minimap",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.minimap
    end,
    apply = RefreshMinimapSurface,
    providerKey = "minimap",
})

ProviderFeatures:Register({
    id = "datatextPanel",
    moverKey = "datatextPanel",
    category = "ui",
    nav = {
        tileId = "minimap",
        subPageIndex = 2,
    },
    onNavigate = SetActiveDatatextPanel,
    getDB = function(profile)
        return profile and profile.datatext
    end,
    apply = RefreshMinimapSurface,
    providerKey = "datatextPanel",
    render = {
        layout = RenderDatatextLayout,
    },
})
