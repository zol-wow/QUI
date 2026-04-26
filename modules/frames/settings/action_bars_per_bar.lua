local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local Fields = Settings and Settings.Fields
local RenderAdapters = Settings and Settings.RenderAdapters
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or not Fields or type(Fields.Dropdown) ~= "function" then
    return
end

local Helpers = ns.Helpers

local BAR_OPTIONS = {
    { value = "bar1",      text = "Bar 1" },
    { value = "bar2",      text = "Bar 2" },
    { value = "bar3",      text = "Bar 3" },
    { value = "bar4",      text = "Bar 4" },
    { value = "bar5",      text = "Bar 5" },
    { value = "bar6",      text = "Bar 6" },
    { value = "bar7",      text = "Bar 7" },
    { value = "bar8",      text = "Bar 8" },
    { value = "stanceBar", text = "Stance Bar" },
    { value = "petBar",    text = "Pet Bar" },
    { value = "microMenu", text = "Micro Menu" },
    { value = "bagBar",    text = "Bag Bar" },
    { value = "totemBar",  text = "Totem Bar" },
}

local LOOKUP_KEYS = {
    "bar1", "bar2", "bar3", "bar4",
    "bar5", "bar6", "bar7", "bar8",
    "stanceBar", "petBar", "microMenu", "bagBar",
}

local VALID_BAR_KEYS = {}
for _, option in ipairs(BAR_OPTIONS) do
    VALID_BAR_KEYS[option.value] = true
end

local pendingSelectionKey = nil

local function NormalizeBarKey(barKey)
    if type(barKey) == "string" and VALID_BAR_KEYS[barKey] then
        return barKey
    end
    return "bar1"
end

local function GetBars()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    return core and core.db and core.db.profile
        and core.db.profile.actionBars and core.db.profile.actionBars.bars
end

local function RefreshActionBars()
    if _G.QUI_RefreshActionBars then
        _G.QUI_RefreshActionBars()
    end
end

local function SyncSelectedBar(barKey, origin)
    local previewAPI = ns.QUI_ActionBarsOptions
    if previewAPI and previewAPI.SetSelectedBar then
        previewAPI.SetSelectedBar(barKey, origin)
        return
    end

    if previewAPI and previewAPI.IsPreviewableBar and previewAPI.IsPreviewableBar(barKey)
        and previewAPI.SetPreviewBar then
        previewAPI.SetPreviewBar(barKey)
    end
end

local function CopyTableInto(destination, source)
    if type(destination) == "table" then
        for key in pairs(destination) do
            destination[key] = nil
        end
        for key, value in pairs(source) do
            destination[key] = value
        end
        return destination
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function CopySelectedBarToAll(selectionKey)
    local bars = GetBars()
    local source = bars and bars[selectionKey]
    if not source then
        return
    end

    for _, option in ipairs(BAR_OPTIONS) do
        local destinationKey = option.value
        if destinationKey ~= selectionKey and bars[destinationKey] then
            for key, value in pairs(source) do
                if key ~= "enabled" then
                    if type(value) == "table" then
                        bars[destinationKey][key] = CopyTableInto(bars[destinationKey][key], value)
                    else
                        bars[destinationKey][key] = value
                    end
                end
            end
        end
    end

    RefreshActionBars()
end

local function EnsureSelectionState(state)
    state.selection = state.selection or {}
    state.selection.key = NormalizeBarKey(state.selection.key)
    return state.selection
end

local function ResolveSelectionState(state)
    local selection = EnsureSelectionState(state)
    if pendingSelectionKey then
        selection.key = NormalizeBarKey(pendingSelectionKey)
        pendingSelectionKey = nil
    end
    return selection
end

local function ResolveInitialSelection()
    if pendingSelectionKey then
        return NormalizeBarKey(pendingSelectionKey)
    end

    local previewAPI = ns.QUI_ActionBarsOptions
    local selected = previewAPI and previewAPI.GetSelectedBar and previewAPI.GetSelectedBar() or "bar1"
    return NormalizeBarKey(selected)
end

local function RegisterSelectionListener(ctx)
    if ctx.state.selectionListenerRegistered then
        return
    end

    local previewAPI = ns.QUI_ActionBarsOptions
    if not previewAPI or type(previewAPI.RegisterSelectedBarListener) ~= "function" then
        return
    end

    previewAPI.RegisterSelectedBarListener(ctx.host, function(barKey)
        local normalized = NormalizeBarKey(barKey)
        local selection = ResolveSelectionState(ctx.state)
        if selection.key == normalized then
            return
        end

        selection.key = normalized
        local controls = ctx.state.controls
        if controls and controls.dropdown and controls.dropdown.SetValue then
            controls.dropdown.SetValue(normalized, true)
        end
        ctx:RerenderSection("settings")
    end)

    ctx.state.selectionListenerRegistered = true
end

local function BuildControlsSection()
    return Schema.Section({
        id = "controls",
        kind = "controls",
        height = 38,
        fields = {
            Fields.Dropdown({
                label = "Bar",
                options = BAR_OPTIONS,
                state = function(ctx)
                    return ResolveSelectionState(ctx.state)
                end,
                stateKey = "key",
                width = 320,
                onChange = function(ctx, value)
                    local selection = ResolveSelectionState(ctx.state)
                    selection.key = NormalizeBarKey(value)
                    SyncSelectedBar(selection.key, "perbar")
                    ctx:RerenderSection("settings")
                end,
                afterCreate = function(ctx, widget)
                    local controls = ctx.state.controls or {}
                    controls.dropdown = widget
                    ctx.state.controls = controls
                end,
            }),
            Fields.Button({
                text = "Apply to All Bars",
                width = 160,
                height = 26,
                spacing = 30,
                onClick = function(ctx)
                    local selection = ResolveSelectionState(ctx.state)
                    CopySelectedBarToAll(selection.key)
                    ctx:RerenderSection("settings")
                end,
            }),
        },
    })
end

local function GetPerBarBuilder()
    local builders = ns.QUI_ActionBarsPerBarBuilders
    local build = builders and builders.BuildBarSettings
    if type(build) == "function" then
        return build
    end

    local ensure = builders and builders.EnsureInitialized
    if type(ensure) == "function" then
        build = ensure()
        if type(build) == "function" then
            return build
        end
    end

    return nil
end

local function RenderSettingsSection(sectionHost, ctx, includePosition)
    local build = GetPerBarBuilder()
    if type(build) ~= "function" then
        return 80
    end

    RegisterSelectionListener(ctx)

    local width = math.max(300, (ctx.width or 0) - ((ctx.surface.padding or 10) * 2))
    local barKey = ResolveSelectionState(ctx.state).key
    local render = function()
        return build(sectionHost, barKey, width)
    end
    local renderWithTileChrome = function()
        if RenderAdapters and type(RenderAdapters.RenderWithTileChrome) == "function" then
            return RenderAdapters.RenderWithTileChrome(render) or 80
        end
        return render()
    end

    if includePosition == false and RenderAdapters and type(RenderAdapters.WithSuppressedPosition) == "function" then
        return RenderAdapters.WithSuppressedPosition(false, renderWithTileChrome) or 80
    end

    return renderWithTileChrome() or 80
end

local function RenderLayout(host, options)
    local build = GetPerBarBuilder()
    if type(build) ~= "function" then
        return 80
    end

    local barKey = NormalizeBarKey(options and options.providerKey or ResolveInitialSelection())
    return build(host, barKey, options and options.width) or 80
end

local feature = Schema.Feature({
    id = "actionBarsPerBar",
    category = "frames",
    nav = {
        tileId = "action_bars",
        subPageIndex = 3,
    },
    lookupKeys = LOOKUP_KEYS,
    onNavigate = function(lookupKey)
        pendingSelectionKey = NormalizeBarKey(lookupKey)
        SyncSelectedBar(pendingSelectionKey, "lookup-nav")
    end,
    getDB = function(profile)
        return profile and profile.actionBars
    end,
    apply = RefreshActionBars,
    createState = function()
        local selectedBar = ResolveInitialSelection()
        SyncSelectedBar(selectedBar, "perbar-init")
        return {
            selection = { key = selectedBar },
        }
    end,
    surfaces = {
        tile = {
            sections = { "controls", "settings" },
            padding = 10,
            sectionGap = 8,
            topPadding = 10,
            bottomPadding = 10,
        },
        full = {
            sections = { "controls", "settings" },
            padding = 10,
            sectionGap = 8,
            topPadding = 10,
            bottomPadding = 10,
        },
    },
    render = {
        layout = RenderLayout,
    },
    sections = {
        BuildControlsSection(),
        Schema.Section({
            id = "settings",
            kind = "custom",
            minHeight = 80,
            render = function(sectionHost, ctx)
                return RenderSettingsSection(sectionHost, ctx, false)
            end,
        }),
    },
})

Registry:RegisterFeature(feature)
