local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local CompatRender = Settings and Settings.CompatRender
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function ClearFrame(frame)
    if not frame then
        return
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.Hide then child:Hide() end
            if child.ClearAllPoints then child:ClearAllPoints() end
            if child.SetParent then child:SetParent(nil) end
        end
    end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end
end

local function RenderOwnerPage(host, ownerName, fnName, opts)
    if CompatRender and type(CompatRender.RenderOwnerPage) == "function" then
        return CompatRender.RenderOwnerPage(host, ownerName, fnName, opts)
    end

    local owner = ns[ownerName]
    local render = owner and owner[fnName]
    if type(render) ~= "function" then
        return nil
    end
    ClearFrame(host)
    local result = render(host)
    if type(result) == "number" then
        return result
    end
    return host and host.GetHeight and host:GetHeight() or nil
end

local function RenderLayoutRoute(host, routeKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or type(routeKey) ~= "string" or routeKey == ""
        or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
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

local function RenderPositionOnly(host, frameKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or type(frameKey) ~= "string" or frameKey == ""
        or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return 80
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    U.BuildPositionCollapsible(host, frameKey, nil, sections, relayout)
    relayout()
    return host:GetHeight()
end

local function RenderThirdPartyLayout(host, routeKey)
    local owner = ns.QUI_ThirdPartyAnchoringOptions
    local render = owner and owner.BuildLayoutContainerSettings
    if type(render) ~= "function" then
        return 80
    end
    return render(host, routeKey)
end

local featureSpecs = {
    {
        id = "crosshair",
        moverKey = "crosshair",
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 4 },
        ownerName = "QUI_CrosshairOptions",
        fnName = "BuildCrosshairTab",
        tileLayout = true,
        layoutRouteOnly = true,
    },
    {
        id = "characterPane",
        moverKey = "characterPane",
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 5 },
        ownerName = "QUI_CharacterOptions",
        fnName = "BuildCharacterPaneTab",
        tileLayout = true,
    },
    {
        id = "preyTrackerPage",
        moverKey = "preyTracker",
        lookupKeys = { "preyTracker" },
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 8 },
        ownerName = "QUI_PreyTrackerOptions",
        fnName = "CreatePreyTrackerPage",
        tileLayout = true,
        noScroll = true,
        layoutRouteOnly = true,
    },
    {
        id = "topCenterWidgets",
        moverKey = "topCenterWidgets",
        positionOnly = true,
    },
    {
        id = "belowMinimapWidgets",
        moverKey = "belowMinimapWidgets",
        positionOnly = true,
    },
    {
        id = "rangeCheck",
        moverKey = "rangeCheck",
        positionOnly = true,
    },
    {
        id = "lootFrame",
        moverKey = "lootFrame",
        positionOnly = true,
    },
    {
        id = "lootRollAnchor",
        moverKey = "lootRollAnchor",
        positionOnly = true,
    },
    {
        id = "alertAnchor",
        moverKey = "alertAnchor",
        positionOnly = true,
    },
    {
        id = "toastAnchor",
        moverKey = "toastAnchor",
        positionOnly = true,
    },
    {
        id = "bnetToastAnchor",
        moverKey = "bnetToastAnchor",
        positionOnly = true,
    },
    {
        id = "powerBarAlt",
        moverKey = "powerBarAlt",
        positionOnly = true,
    },
    {
        id = "profilesPage",
        moverKey = "profiles",
        category = "global",
        nav = { tileId = "global", subPageIndex = 1 },
        ownerName = "QUI_ProfilesOptions",
        fnName = "CreateSpecProfilesPage",
        noScroll = true,
    },
    {
        id = "importExportPage",
        moverKey = "importExport",
        category = "global",
        nav = { tileId = "global", subPageIndex = 2 },
        ownerName = "QUI_ImportOptions",
        fnName = "CreateImportExportPage",
        noScroll = true,
    },
    {
        id = "thirdPartyAnchoring",
        moverKey = "thirdPartyAnchoring",
        lookupKeys = { "dandersParty", "dandersRaid", "dandersPinned1", "dandersPinned2" },
        category = "global",
        nav = { tileId = "global", subPageIndex = 3 },
        ownerName = "QUI_ThirdPartyAnchoringOptions",
        fnName = "BuildThirdPartyTab",
        layoutRender = RenderThirdPartyLayout,
    },
    {
        id = "clickCastPage",
        moverKey = "clickCast",
        category = "global",
        nav = { tileId = "global", subPageIndex = 4 },
        ownerName = "QUI_GroupFramesOptions",
        fnName = "CreateClickCastPage",
        noScroll = true,
    },
    {
        id = "skinningPage",
        moverKey = "skinning",
        lookupKeys = { "objectiveTracker" },
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 3 },
        ownerName = "QUI_SkinningOptions",
        fnName = "BuildSkinningTab",
        tileLayout = true,
        layoutRouteOnly = true,
    },
    {
        id = "autohidePage",
        moverKey = "autohide",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 4 },
        ownerName = "QUI_AutohideOptions",
        fnName = "BuildAutohideTab",
        tileLayout = true,
    },
    {
        id = "barHidingPage",
        moverKey = "barHiding",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 5 },
        ownerName = "QUI_ActionBarsOptions",
        fnName = "BuildMouseoverHideTab",
        tileLayout = true,
    },
    {
        id = "hudVisibilityPage",
        moverKey = "hudVisibility",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 6 },
        ownerName = "QUI_HUDVisibilityOptions",
        fnName = "BuildHUDVisibilityTab",
        tileLayout = true,
    },
    {
        id = "frameLevelsPage",
        moverKey = "hudLayering",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 7 },
        ownerName = "QUI_HUDLayeringOptions",
        fnName = "CreateHUDLayeringPage",
        tileLayout = true,
        noScroll = true,
    },
    {
        id = "blizzardMoverPage",
        moverKey = "blizzardMover",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 8 },
        ownerName = "QUI_BlizzardMoverOptions",
        fnName = "BuildBlizzardMoverTab",
    },
}

for _, spec in ipairs(featureSpecs) do
    local feature = {
        id = spec.id,
        moverKey = spec.moverKey,
        lookupKeys = spec.lookupKeys,
        category = spec.category,
        nav = spec.nav,
        noScroll = spec.noScroll,
    }

    if spec.ownerName and spec.fnName then
        feature.render = feature.render or {}

        if spec.noScroll then
            feature.render.tile = function(host)
                return RenderOwnerPage(host, spec.ownerName, spec.fnName, {
                    tileLayout = spec.tileLayout,
                })
            end
            feature.render.full = feature.render.tile
        else
            feature.sections = {
                Schema.Section({
                    id = "settings",
                    kind = "custom",
                    minHeight = 80,
                    render = function(host)
                        return RenderOwnerPage(host, spec.ownerName, spec.fnName, {
                            tileLayout = spec.tileLayout,
                        })
                    end,
                }),
            }
        end
    end

    if spec.layoutRouteOnly or spec.positionOnly or spec.layoutRender then
        feature.render = feature.render or {}
    end

    if type(spec.layoutRender) == "function" then
        feature.render.layout = function(host, options)
            local routeKey = options and options.providerKey or spec.moverKey
            return spec.layoutRender(host, routeKey, options, spec)
        end
    elseif spec.layoutRouteOnly then
        feature.render.layout = function(host, options)
            local routeKey = options and options.providerKey or spec.moverKey
            return RenderLayoutRoute(host, routeKey)
        end
    elseif spec.positionOnly then
        feature.render.layout = function(host, options)
            local frameKey = options and options.providerKey or spec.moverKey
            return RenderPositionOnly(host, frameKey)
        end
    end

    Registry:RegisterFeature(Schema.Feature(feature))
end
