local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local mountedEditor

local function BuildAurasNameplateContent(host, ctx, section)
    mountedEditor = { host = host, ctx = ctx, section = section }
    local NP = ns.QUI_NameplatesSettingsSchema
    local NPSurface = ns.QUI_NameplatesSettingsSurface
    local NPModel = ns.QUI_NameplatesSettingsModel
    local FullSurface = Settings and Settings.FullSurface

    local typeKey = NPSurface and type(NPSurface.GetSelectedType) == "function"
        and NPSurface.GetSelectedType() or nil

    mountedEditor.key = typeKey

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
        NP.RenderAurasTab(editorHost, typeKey, true)
    end

    local total = y + ((editorHost.GetHeight and editorHost:GetHeight()) or 1)
    host:SetHeight(total)
    return total
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasNameplatePage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 5 },
    getSearchContexts = function()
        local model = ns.QUI_NameplatesSettingsModel
        return model and model.GetSearchContexts("auras") or {}
    end,
    getNavigationContext = function()
        local surface = ns.QUI_NameplatesSettingsSurface
        return surface and surface.GetNavigationContext() or {}
    end,
    searchNavigate = function(entry, context)
        local surface = ns.QUI_NameplatesSettingsSurface
        if not surface then return false end
        local key = entry and entry.surfaceTypeKey
        local model = ns.QUI_NameplatesSettingsModel
        if type(key) ~= "string" or not model or model.NormalizeTypeKey(key) ~= key then return false end
        local changed = surface.GetSelectedType() ~= key
        if changed then surface.SetSelectedType(key) end
        local mounted = mountedEditor
        if mounted and mounted.key ~= key and mounted.ctx and mounted.section
            and mounted.ctx.host._quiSettingsRuntime == mounted.ctx.runtime then
            mounted.ctx:RerenderSection(mounted.section.id)
        end
        if context and context.opts and mountedEditor then
            context.opts.searchRoot = mountedEditor.host
        end
        return true
    end,
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            getContextKey = function()
                local surface = ns.QUI_NameplatesSettingsSurface
                return surface and surface.GetSelectedType() or nil
            end,
            build = BuildAurasNameplateContent,
        }),
    },
}))
