local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local HUB_ROUTE = {
    tabIndex = 21,
    tabName = ns.L["Auras"],
    subTabIndex = 5,
    subTabName = ns.L["Nameplates"],
    tileId = "auras",
    subPageIndex = 5,
    featureId = "aurasNameplatePage",
}

local function BuildAurasNameplateContent(host, ctx, section)
    local NP = ns.QUI_NameplatesSettingsSchema
    local NPSurface = ns.QUI_NameplatesSettingsSurface
    local NPModel = ns.QUI_NameplatesSettingsModel
    local FullSurface = Settings and Settings.FullSurface
    local SearchRoute = Settings and Settings.SearchRoute

    local typeKey = NPSurface and type(NPSurface.GetSelectedType) == "function"
        and NPSurface.GetSelectedType() or nil

    local y = 0
    local typeOptions = (NPModel and type(NPModel.GetTypeOptions) == "function"
        and NPModel.GetTypeOptions()) or {}
    if typeKey and #typeOptions > 0 and FullSurface
        and type(FullSurface.BuildContextDropdownRow) == "function" then
        local built = FullSurface.BuildContextDropdownRow(host, {
            label = ns.L["Nameplate Type"],
            stateKey = "_selectedType",
            selectedValue = typeKey,
            options = typeOptions,
            meta = { description = ns.L["Select which nameplate type's aura icons to configure."] },
            height = 30,
            onChanged = function(value)
                if NPSurface and type(NPSurface.SetSelectedType) == "function" then
                    NPSurface.SetSelectedType(value)
                end
                if section and ctx and type(ctx.RerenderSection) == "function" then
                    ctx:RerenderSection(section.id)
                end
            end,
        })
        if built then
            local rowHeight = (built.row and built.row.GetHeight and built.row:GetHeight()) or 30
            y = rowHeight + 8
        end
    end

    local editorHost = CreateFrame("Frame", nil, host)
    editorHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    editorHost:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    editorHost:SetHeight(1)

    if NP and type(NP.RenderAurasTab) == "function" then
        if SearchRoute and type(SearchRoute.With) == "function" then
            SearchRoute.With(HUB_ROUTE, NP.RenderAurasTab, editorHost, typeKey, true)
        else
            NP.RenderAurasTab(editorHost, typeKey, true)
        end
    end

    local previewHost = (ctx and ctx.host) or host
    if NPSurface and type(NPSurface.ShowPreviewOn) == "function" then
        NPSurface.ShowPreviewOn(previewHost)
    end

    local total = y + ((editorHost.GetHeight and editorHost:GetHeight()) or 1)
    host:SetHeight(total)
    return total
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasNameplatePage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 5 },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasNameplateContent,
        }),
    },
}))
