local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Schema = Settings.Schema or {}
Settings.Schema = Schema
local RenderAdapters = Settings.RenderAdapters

local function CloneTable(source)
    local util = Settings.Util
    if util and type(util.ShallowCopy) == "function" then
        return util.ShallowCopy(source)
    end
    return {}
end

local function MergeOptions(base, extra)
    local merged = {}
    if type(base) == "table" then
        for key, value in pairs(base) do
            merged[key] = value
        end
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            merged[key] = value
        end
    end
    return merged
end

local function ResolveValue(value, ctx, section)
    if type(value) == "function" then
        return value(ctx, section)
    end
    return value
end

local function CleanupFrame(frame)
    if not frame then return end

    local gui = _G.QUI and _G.QUI.GUI
    if gui and type(gui.TeardownFrameTree) == "function" then
        gui:TeardownFrameTree(frame)
        return
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.Hide then child:Hide() end
            if child.SetParent then child:SetParent(nil) end
            if child.ClearAllPoints then child:ClearAllPoints() end
        end
    end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end
end

local function NormalizeSections(feature)
    local sections = {}
    local sectionOrder = {}
    local source = feature and feature.sections
    if type(source) ~= "table" then
        return sections, sectionOrder
    end

    for _, definition in ipairs(source) do
        if type(definition) == "table" and type(definition.id) == "string" and definition.id ~= "" then
            local section = CloneTable(definition)
            sections[section.id] = section
            sectionOrder[#sectionOrder + 1] = section.id
        end
    end

    return sections, sectionOrder
end

function Schema.Section(definition)
    return CloneTable(definition)
end

function Schema.Feature(definition)
    local feature = CloneTable(definition)
    feature.sectionsById, feature.sectionOrder = NormalizeSections(feature)
    return feature
end

function Schema:ResolveSurface(feature, surfaceName)
    if type(surfaceName) ~= "string" or surfaceName == "" then
        surfaceName = "tile"
    end

    local sharedSurfaces = Settings.Surfaces
    local baseSurface = sharedSurfaces
        and type(sharedSurfaces.Get) == "function"
        and sharedSurfaces:Get(surfaceName)
        or { name = surfaceName }

    local surfaces = feature and feature.surfaces
    if type(surfaces) ~= "table" then
        return baseSurface
    end

    local surface = surfaces[surfaceName] or surfaces.tile
    if type(surface) ~= "table" then
        return baseSurface
    end

    return MergeOptions(baseSurface, surface)
end

function Schema:CanRenderFeature(feature, surfaceName)
    if type(feature) ~= "table" then
        return false
    end
    if type(feature.sectionsById) ~= "table" or type(feature.sectionOrder) ~= "table" then
        return false
    end
    return self:ResolveSurface(feature, surfaceName) ~= nil
end

local function CleanupRuntime(runtime)
    if type(runtime) ~= "table" then
        return
    end

    if type(runtime.sectionHosts) == "table" then
        for _, sectionHost in pairs(runtime.sectionHosts) do
            if sectionHost then
                CleanupFrame(sectionHost)
                if sectionHost.Hide then sectionHost:Hide() end
                if sectionHost.ClearAllPoints then sectionHost:ClearAllPoints() end
            end
        end
    end

    if type(runtime.sectionHeights) == "table" then
        for sectionId in pairs(runtime.sectionHeights) do
            runtime.sectionHeights[sectionId] = nil
        end
    end
end

local function GetStateStore(host)
    if not host then return nil end
    local store = rawget(host, "_quiSettingsFeatureStates")
    if type(store) ~= "table" then
        store = {}
        host._quiSettingsFeatureStates = store
    end
    return store
end

function Schema:GetFeatureState(feature, host, options)
    local store = GetStateStore(host)
    if not store or not feature or not feature.id then
        return {}
    end

    local state = store[feature.id]
    if type(state) ~= "table" then
        if type(feature.createState) == "function" then
            state = feature.createState(host, options, feature)
        end
        if type(state) ~= "table" then
            state = {}
        end
        store[feature.id] = state
    end

    return state
end

local function RenderControlsSection(sectionHost, ctx, section)
    local Fields = Settings.Fields
    if not Fields or type(Fields.Render) ~= "function" then
        return section.height or 38
    end

    local previous
    local topOffset = section.topOffset or -4
    for index, field in ipairs(section.fields or {}) do
        local widget = Fields.Render(field, ctx, sectionHost)
        if widget then
            widget:ClearAllPoints()
            if index == 1 then
                widget:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", field.offsetX or 0, field.offsetY or topOffset)
                C_Timer.After(0, function()
                    if widget:GetParent() == sectionHost then
                        widget:ClearAllPoints()
                        widget:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", field.offsetX or 0, field.offsetY or topOffset)
                    end
                end)
            else
                widget:SetPoint(
                    field.point or "LEFT",
                    previous,
                    field.relativePoint or "RIGHT",
                    field.spacing or 24,
                    field.offsetY or 0
                )
            end
            previous = widget
        end
    end

    return section.height or 38
end

local function RenderProviderSection(sectionHost, ctx, section)
    if not RenderAdapters or type(RenderAdapters.BuildProvider) ~= "function" then
        return section.emptyHeight or 80
    end

    local providerKey = ResolveValue(section.providerKey, ctx, section)
    if type(providerKey) ~= "string" or providerKey == "" then
        return section.emptyHeight or 80
    end

    local width = math.max(300, (ctx.width or 0) - ((ctx.surface.padding or 10) * 2))
    local providerOptions = MergeOptions({
        providerPage = ctx.options and ctx.options.providerPage,
        includePosition = ctx.options and ctx.options.includePosition,
        tileLayout = ctx.options and ctx.options.tileLayout,
        layoutModePositionOnly = ctx.options and ctx.options.layoutModePositionOnly,
        useMinimalDrawerChrome = ctx.options and ctx.options.useMinimalDrawerChrome,
    }, ResolveValue(section.providerOptions, ctx, section))
    if providerOptions.includePosition == nil then
        providerOptions.includePosition = ctx.surface and ctx.surface.includePosition
    end

    local function RenderProvider()
        return RenderAdapters.BuildProvider(providerKey, sectionHost, width, providerOptions)
    end

    return RenderProvider()
end

local function RenderPageSection(sectionHost, ctx, section)
    local build = section.build or section.render
    if type(build) ~= "function" then
        return section.height or section.minHeight or 80
    end

    local function RenderPage()
        return build(sectionHost, ctx, section)
    end

    local height
    local useTileChrome = not (section.tileChrome == false
        or (ctx and ctx.options and ctx.options.tileLayout == false))

    if useTileChrome and RenderAdapters and type(RenderAdapters.RenderWithTileChrome) == "function" then
        height = RenderAdapters.RenderWithTileChrome(RenderPage)
    else
        local ok, result = xpcall(RenderPage, geterrorhandler())
        if not ok then
            return section.errorHeight or section.minHeight or 80
        end
        height = result
    end

    return height
end

local SECTION_RENDERERS = {
    controls = RenderControlsSection,
    page = RenderPageSection,
    provider = RenderProviderSection,
    custom = function(sectionHost, ctx, section)
        if type(section.render) ~= "function" then
            return section.height or 1
        end
        return section.render(sectionHost, ctx, section)
    end,
}

local function LayoutSections(runtime)
    runtime._layingOut = true
    local surface = runtime.surface or {}
    local pad = surface.padding or 10
    local gap = surface.sectionGap or 8
    local topPad = surface.topPadding or 10
    local bottomPad = surface.bottomPadding or 10
    local y = -topPad
    local previousHost, previousGap

    for _, sectionId in ipairs(runtime.sectionOrder) do
        local sectionHost = runtime.sectionHosts[sectionId]
        if sectionHost then
            local section = runtime.sectionsById[sectionId]
            local height = math.max(runtime.sectionHeights[sectionId] or section.minHeight or 1, 1)
            sectionHost:ClearAllPoints()
            if previousHost then
                sectionHost:SetPoint("TOPLEFT", previousHost, "BOTTOMLEFT", 0, -previousGap)
            else
                sectionHost:SetPoint("TOPLEFT", runtime.host, "TOPLEFT", pad, -topPad)
            end
            if sectionHost._quiRecoveredBounds then
                sectionHost:SetWidth(math.max(1, runtime.host:GetWidth() - pad * 2))
            else
                sectionHost:SetPoint("RIGHT", runtime.host, "RIGHT", -pad, 0)
            end
            sectionHost:SetHeight(height)
            previousHost, previousGap = sectionHost, section and section.gapAfter or gap
            y = y - height - previousGap
        end
    end

    local total = math.abs(y) + bottomPad
    if runtime.host.SetHeight then
        runtime.host:SetHeight(total)
    end
    runtime._layingOut = nil
    return total
end

local function RenderSection(runtime, sectionId)
    local section = runtime.sectionsById[sectionId]
    if not section then
        return nil
    end

    local renderer = SECTION_RENDERERS[section.kind]
    if type(renderer) ~= "function" then
        return nil
    end

    local sectionHost = runtime.sectionHosts[sectionId]
    if not sectionHost then
        sectionHost = CreateFrame("Frame", nil, runtime.host)
        runtime.sectionHosts[sectionId] = sectionHost
    else
        sectionHost:SetParent(runtime.host)
    end
    if sectionHost:GetWidth() <= 0 then
        sectionHost:SetWidth(math.max(300, runtime.host:GetWidth() - ((runtime.surface.padding or 10) * 2)))
    end
    runtime._rendering = true
    sectionHost._quiSettingsSectionId = sectionId
    local layoutShared = ns.QUI_SettingsLayoutShared
    if layoutShared and layoutShared.VerifyInitialBounds then
        layoutShared.VerifyInitialBounds(sectionHost, runtime.host, function(self)
            self._quiRecoveredBounds = true
            LayoutSections(runtime)
        end)
    end
    if sectionHost.HookScript and not sectionHost._quiSettingsHeightHook then
        sectionHost._quiSettingsHeightHook = true
        sectionHost:HookScript("OnSizeChanged", function(self)
            local owner = self:GetParent()
            local active = owner and owner._quiSettingsRuntime
            local id = self._quiSettingsSectionId
            if active and not active._rendering and not active._layingOut
                and active.sectionHosts[id] == self then
                local height = self:GetHeight()
                if height > 0 and height ~= active.sectionHeights[id] then
                    Schema:ResizeSection(active, id, height)
                end
            end
        end)
    end
    sectionHost:Show()

    CleanupFrame(sectionHost)

    local height = renderer(sectionHost, runtime.ctx, section)
    if type(height) ~= "number" then
        if type(height) == "table" and type(height.GetHeight) == "function" then
            local ok, measuredHeight = pcall(height.GetHeight, height)
            if ok and type(measuredHeight) == "number" then
                height = measuredHeight
            end
        end
    end
    if type(height) ~= "number" and sectionHost and type(sectionHost.GetHeight) == "function" then
        local ok, measuredHeight = pcall(sectionHost.GetHeight, sectionHost)
        if ok and type(measuredHeight) == "number" then
            height = measuredHeight
        end
    end

    runtime.sectionHeights[sectionId] = math.max(
        (type(height) == "number" and height) or section.minHeight or 1,
        1
    )
    runtime._rendering = nil
    return runtime.sectionHeights[sectionId]
end

function Schema:RerenderSection(runtime, sectionId)
    if type(runtime) ~= "table" or type(sectionId) ~= "string" then
        return nil
    end

    local height = RenderSection(runtime, sectionId)
    if not height then
        return nil
    end

    return LayoutSections(runtime)
end

function Schema:ResizeSection(runtime, sectionId, height)
    if type(runtime) ~= "table" or type(sectionId) ~= "string" or type(height) ~= "number" then
        return nil
    end
    if not (runtime.sectionsById and runtime.sectionsById[sectionId])
        or not (runtime.sectionHosts and runtime.sectionHosts[sectionId]) then
        return nil
    end

    runtime.sectionHeights[sectionId] = math.max(height, 1)
    return LayoutSections(runtime)
end

function Schema:RerenderFeature(runtime)
    if type(runtime) ~= "table" then
        return nil
    end

    for _, sectionId in ipairs(runtime.sectionOrder or {}) do
        RenderSection(runtime, sectionId)
    end

    return LayoutSections(runtime)
end

function Schema:RenderFeature(feature, host, options)
    if type(feature) ~= "table" or not host then
        return nil
    end

    options = options or {}
    local surfaceName = options.surface or "tile"
    local surface = self:ResolveSurface(feature, surfaceName)
    if type(surface) ~= "table" then
        return nil
    end

    local previousRuntime = rawget(host, "_quiSettingsRuntime")
    if previousRuntime then
        CleanupRuntime(previousRuntime)
    end

    local state = self:GetFeatureState(feature, host, options)
    local sectionOrder = surface.sections or feature.sectionOrder or {}
    local sectionHosts = rawget(host, "_quiSettingsSectionHosts")
    if type(sectionHosts) ~= "table" then
        sectionHosts = {}
        host._quiSettingsSectionHosts = sectionHosts
    end
    local runtime = {
        feature = feature,
        host = host,
        options = options,
        surfaceName = surfaceName,
        surface = surface,
        state = state,
        width = options.width or (host.GetWidth and host:GetWidth()) or 760,
        sectionOrder = sectionOrder,
        sectionsById = feature.sectionsById or {},
        sectionHosts = sectionHosts,
        sectionHeights = {},
    }

    local ctx = {
        feature = feature,
        host = host,
        options = options,
        surfaceName = surfaceName,
        surface = surface,
        state = state,
        width = runtime.width,
        runtime = runtime,
    }
    runtime.ctx = ctx

    function ctx:RerenderSection(sectionId)
        return Schema:RerenderSection(runtime, sectionId)
    end

    function ctx:ResizeSection(sectionId, height)
        return Schema:ResizeSection(runtime, sectionId, height)
    end

    function ctx:RerenderFeature()
        return Schema:RerenderFeature(runtime)
    end

    host._quiSettingsRuntime = runtime
    if host.HookScript and not host._quiSettingsWidthHook then
        host._quiSettingsWidthHook = true
        host:HookScript("OnSizeChanged", function(self)
            local active = self._quiSettingsRuntime
            if active and not active._rendering and not active._layingOut then LayoutSections(active) end
        end)
    end
    return self:RerenderFeature(runtime)
end
