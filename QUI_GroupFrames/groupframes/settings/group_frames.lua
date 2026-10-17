local ADDON_NAME, ns = ...

local Settings = ns.Settings
local SurfaceFeatures = Settings and Settings.SurfaceFeatures
local Renderer = Settings and Settings.Renderer
if not SurfaceFeatures or type(SurfaceFeatures.Register) ~= "function" then
    return
end

local LOOKUP_TO_CONTEXT = {
    partyFrames = "party",
    raidFrames = "raid",
    spotlightFrames = "raid",
}

local function GetSurface()
    return ns.QUI_GroupFramesSettingsSurface
end

local function GetModel()
    return ns.QUI_GroupFramesSettingsModel
end

local function ResolveContextMode(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end
    return LOOKUP_TO_CONTEXT[lookupKey]
end

local function AppendLayoutRouteControls(host, topOffset, routeKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function"
        or type(routeKey) ~= "string" or routeKey == "" then
        return 0
    end

    local generation = host._quiLayoutGeneration
    local routeHost = CreateFrame("Frame", nil, host)
    routeHost._quiCompactLayout = host._quiCompactLayout
    routeHost._quiLayoutGeneration = generation
    routeHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -topOffset)
    routeHost:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -topOffset)

    local sections = {}
    local function relayout()
        if host._quiLayoutGeneration ~= generation then return end
        U.StandardRelayout(routeHost, sections)
        host:SetHeight(topOffset + routeHost:GetHeight())
    end

    U.BuildPositionCollapsible(routeHost, routeKey, nil, sections, relayout)
    U.BuildOpenFullSettingsLink(routeHost, routeKey, sections, relayout)
    relayout()

    local height = routeHost.GetHeight and routeHost:GetHeight() or 0
    if type(height) ~= "number" or height <= 0 then
        height = 1
    end
    routeHost:SetHeight(height)
    return height
end

local function RenderLayoutRoute(host, options)
    if not host then
        return 80
    end

    local routeKey = options and options.providerKey or "partyFrames"
    if type(routeKey) ~= "string" or routeKey == "" then
        routeKey = "partyFrames"
    end

    local totalHeight = AppendLayoutRouteControls(host, 0, routeKey)
    return math.max(totalHeight, 80)
end

SurfaceFeatures:Register({
    id = "groupFramesPage",
    moverKey = "partyFrames",
    lookupKeys = { "partyFrames", "raidFrames", "spotlightFrames" },
    layoutPositionOnly = true,
    category = "frames",
    nav = {
        tileId = "group_frames",
        subPageIndex = 1,
    },
    render = {
        layout = RenderLayoutRoute,
    },
    surface = GetSurface,
    model = GetModel,
    navigate = {
        resolve = ResolveContextMode,
        method = "SetContextMode",
    },
})
