local ADDON_NAME, ns = ...

local Settings = ns.Settings
local SurfaceFeatures = Settings and Settings.SurfaceFeatures
if not SurfaceFeatures or type(SurfaceFeatures.Register) ~= "function" then
    return
end

local PREVIEW_HEIGHT = 220
local LOOKUP_TO_UNIT = {
    playerFrame = "player",
    targetFrame = "target",
    totFrame = "targettarget",
    focusFrame = "focus",
    petFrame = "pet",
    bossFrames = "boss",
    playerCastbar = "player",
    targetCastbar = "target",
    focusCastbar = "focus",
    petCastbar = "pet",
    totCastbar = "targettarget",
}

local function GetSurface()
    return ns.QUI_UnitFramesSettingsSurface
end

local function GetModel()
    return ns.QUI_UnitFramesSettingsModel
end

local function ResolveUnitKey(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end
    return LOOKUP_TO_UNIT[lookupKey]
end

local function RenderLayoutRoute(host, options)
    local U = ns.QUI_LayoutMode_Utils
    if not host or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return 80
    end

    local routeKey = options and options.providerKey or "playerFrame"
    if type(routeKey) ~= "string" or routeKey == "" then
        routeKey = "playerFrame"
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    local anchorOpts
    if routeKey == "playerFrame" or routeKey == "targetFrame" then
        anchorOpts = {
            sliderRange = { -3000, 3000 },
            autoWidth = true,
            autoHeight = true,
        }
    elseif routeKey == "playerCastbar" or routeKey == "targetCastbar"
        or routeKey == "focusCastbar" or routeKey == "petCastbar"
        or routeKey == "totCastbar" then
        anchorOpts = {
            autoWidth = true,
        }
    else
        anchorOpts = {
            sliderRange = { -3000, 3000 },
        }
    end

    U.BuildPositionCollapsible(host, routeKey, anchorOpts, sections, relayout)
    U.BuildOpenFullSettingsLink(host, routeKey, sections, relayout)
    relayout()
    return host:GetHeight()
end

SurfaceFeatures:Register({
    id = "unitFramesPage",
    moverKey = "playerFrame",
    lookupKeys = {
        "playerFrame", "targetFrame", "totFrame",
        "focusFrame", "petFrame", "bossFrames",
        "playerCastbar", "targetCastbar", "focusCastbar",
        "petCastbar", "totCastbar",
    },
    category = "frames",
    nav = {
        tileId = "unit_frames",
        subPageIndex = 1,
    },
    surface = GetSurface,
    model = GetModel,
    render = {
        layout = RenderLayoutRoute,
    },
    previewHeight = PREVIEW_HEIGHT,
    navigate = {
        resolve = ResolveUnitKey,
        method = "SetSelectedUnit",
    },
    searchNavigate = function(entry, context)
        local surface = GetSurface()
        if surface and type(surface.NavigateSearchEntry) == "function" then
            local handled = surface.NavigateSearchEntry(entry)
            if handled
                and type(context) == "table"
                and type(context.opts) == "table"
                and type(surface.GetSearchRoot) == "function" then
                context.opts.searchRoot = surface.GetSearchRoot()
            end
            return handled
        end
        return false
    end,
})
