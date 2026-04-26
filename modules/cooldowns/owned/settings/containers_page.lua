local ADDON_NAME, ns = ...

local Settings = ns.Settings
local SurfaceFeatures = Settings and Settings.SurfaceFeatures
local Renderer = Settings and Settings.Renderer
if not SurfaceFeatures or type(SurfaceFeatures.Register) ~= "function" then
    return
end

local PREVIEW_HEIGHT = 230
local FEATURE_ID = "cooldownManagerContainersPage"
local LOOKUP_TO_CONTAINER = {
    cdmEssential = "essential",
    cdmUtility = "utility",
    buffIcon = "buff",
    buffBar = "trackedBar",
}

local function GetSurface()
    return ns.QUI_CooldownManagerSettingsSurface
end

local function GetModel()
    return ns.QUI_CooldownManagerSettingsModel
end

local function ResolveContainerKey(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end

    if LOOKUP_TO_CONTAINER[lookupKey] then
        return LOOKUP_TO_CONTAINER[lookupKey]
    end

    if lookupKey:find("^cdmCustom_") then
        return lookupKey:sub(11)
    end

    return nil
end

local function AppendDrawerSection(host, topOffset, render)
    if not host or type(render) ~= "function" then
        return 0
    end

    local sectionHost = CreateFrame("Frame", nil, host)
    sectionHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -topOffset)
    sectionHost:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -topOffset)
    sectionHost:SetHeight(1)

    local height = render(sectionHost)
    if type(height) ~= "number" or height <= 0 then
        height = sectionHost.GetHeight and sectionHost:GetHeight() or 1
    end
    height = math.max(1, height)
    sectionHost:SetHeight(height)
    return height
end

local function AppendLayoutRouteControls(host, topOffset, routeKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function"
        or type(routeKey) ~= "string" or routeKey == "" then
        return 0
    end

    local routeHost = CreateFrame("Frame", nil, host)
    routeHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -topOffset)
    routeHost:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -topOffset)

    local sections = {}
    local function relayout()
        U.StandardRelayout(routeHost, sections)
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

    local routeKey = options and options.providerKey or "cdmEssential"
    if type(routeKey) ~= "string" or routeKey == "" then
        routeKey = "cdmEssential"
    end

    local totalHeight = AppendLayoutRouteControls(host, 0, routeKey)
    return math.max(totalHeight, 80)
end

local feature = SurfaceFeatures:Register({
    id = FEATURE_ID,
    moverKey = "cdmEssential",
    lookupKeys = { "cdmEssential", "cdmUtility", "buffIcon", "buffBar" },
    layoutPositionOnly = true,
    category = "cooldowns",
    nav = {
        tileId = "cooldown_manager",
        subPageIndex = 1,
    },
    render = {
        layout = RenderLayoutRoute,
    },
    surface = GetSurface,
    model = GetModel,
    previewHeight = PREVIEW_HEIGHT,
    navigate = {
        resolve = ResolveContainerKey,
        method = "SetActiveContainer",
    },
})

local CDMContainers = ns.CDMContainers
if feature and CDMContainers and type(CDMContainers.SyncSettingsFeatureLookups) == "function" then
    CDMContainers.SyncSettingsFeatureLookups(FEATURE_ID)
end
