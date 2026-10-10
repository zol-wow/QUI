local ADDON_NAME, ns = ...

local QUI = QUI
local GUI = QUI and QUI.GUI
local Settings = ns.Settings
local FullSurface = Settings and Settings.FullSurface
local ClearFrame = FullSurface and FullSurface.ClearFrame

local function ResolveModel(feature)
    local model = feature and feature.model or nil
    if type(model) == "function" then
        model = model()
    end
    if type(model) == "table" then
        return model
    end
    return ns.QUI_NameplatesSettingsModel
end

local function NormalizeTypeKey(typeKey)
    local model = ResolveModel()
    local normalize = model and model.NormalizeTypeKey
    if type(normalize) == "function" then
        return normalize(typeKey)
    end
    return typeKey
end

local State = {
    activeTab = "general",
    activeBody = nil,
    repaintTabs = nil,
    selectedType = nil,
    previewZoom = 3,
}

local TabModel
local EnsureTabModel

local function InvalidateTabBodies()
    if State.invalidateTabBodies then
        State.invalidateTabBodies()
    end
end

local function IsPerTypeTab(tabKey)
    local model = ResolveModel()
    local isPerTypeTab = model and model.IsPerTypeTab
    return type(isPerTypeTab) == "function" and isPerTypeTab(tabKey) == true
end

local function ResolveTabVariant(tabKey)
    if not IsPerTypeTab(tabKey) then return nil end
    return State.selectedType
end

local TypeSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "selectedType",
        normalize = NormalizeTypeKey,
        afterSet = function()
            if IsPerTypeTab(EnsureTabModel():GetActiveKey()) and State.repaintTabs then
                State.repaintTabs(false)
            end

            if ns.QUI_NameplatesPreviewDriver
                and ns.QUI_NameplatesPreviewDriver.SetSelectedType then
                ns.QUI_NameplatesPreviewDriver.SetSelectedType(State.selectedType)
            end
        end,
    })

local function SetSelectedType(key)
    if not TypeSelection then
        State.selectedType = NormalizeTypeKey(key)
        return
    end
    TypeSelection:Set(key)
end

local function GetSelectedType()
    if State.selectedType == nil then
        return NormalizeTypeKey(nil)
    end
    return State.selectedType
end

local function SetActiveTab(tabKey)
    if type(tabKey) ~= "string" or tabKey == "" then
        return false
    end

    local tabModel = EnsureTabModel()
    if not tabModel or type(tabModel.SetActiveKey) ~= "function" then
        return false
    end

    if type(tabModel.GetTabs) == "function" then
        local found = false
        for _, tab in ipairs(tabModel:GetTabs() or {}) do
            if type(tab) == "table" and tab.key == tabKey then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end

    local activeKey = type(tabModel.GetActiveKey) == "function" and tabModel:GetActiveKey() or nil
    if activeKey == tabKey then
        return true
    end

    tabModel:SetActiveKey(tabKey)
    if State.repaintTabs then
        State.repaintTabs()
    end
    return true
end

local function NavigateSearchEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local handled = false
    if type(entry.surfaceTypeKey) == "string" and entry.surfaceTypeKey ~= "" then
        SetSelectedType(entry.surfaceTypeKey)
        handled = true
    end
    if SetActiveTab(entry.surfaceTabKey) then
        handled = true
    end

    return handled
end

local function GetSearchRoot()
    return State.activeBody
end

EnsureTabModel = function(feature)
    if TabModel then
        return TabModel
    end

    local model = ResolveModel(feature)
    local getTabDefinitions = model and model.GetTabDefinitions
    local tabDefinitions = type(getTabDefinitions) == "function" and getTabDefinitions() or {}

    TabModel = FullSurface and FullSurface.CreateTabModel
        and FullSurface.CreateTabModel(State, {
            stateKey = "activeTab",
            defaultKey = "general",
            tabs = tabDefinitions,
        })

    return TabModel
end

local function BuildTabStrip(parent)
    return FullSurface.CreateTabStrip(parent)
end

local DROPDOWN_ROW_H = 30

local STRIP_CARD_ROW_H = 32
local STRIP_HEIGHT = (5 * STRIP_CARD_ROW_H) + 8 + 28 + 6

local function CurrentProfileNameplates()
    local Helpers = ns.Helpers
    local profile = Helpers and Helpers.GetProfile and Helpers.GetProfile()
    return (profile and profile.nameplates) or {}
end

local STATE_DEFS = {
    {
        key = "isTarget",
        label = ns.L["Target"],
        enabled = function(s) return (s.highlight or {}).targetGlow ~= false
            or (s.colors or {}).targetEnabled == true end,
    },
    {
        key = "isFocus",
        label = ns.L["Focus"],
        enabled = function(s) return (s.highlight or {}).focusGlow == true
            or (s.colors or {}).focusEnabled == true end,
    },
    {
        key = "mouseover",
        label = ns.L["Mouseover"],
        enabled = function(s) return (s.highlight or {}).mouseover ~= false end,
    },
    {
        key = "casting",
        label = ns.L["Casting"],
        enabled = function(s) return (s.castbar or {}).enabled ~= false end,
    },
    {
        key = "uninterruptible",
        label = ns.L["Uninterruptible"],
        enabled = function(s) return (s.castbar or {}).enabled ~= false end,
    },
    {
        key = "inCombat",
        label = ns.L["In Combat"],
        enabled = function(s) return (s.colors or {}).oocDarken ~= false end,
    },
    {
        key = "execute",
        label = ns.L["Execute Range"],
        enabled = function(s) return (s.colors or {}).executeEnabled == true end,
    },
    {
        key = "aggro",
        label = ns.L["Has Aggro"],
        enabled = function(s) return (s.colors or {}).threatEnabled ~= false end,
    },
    {
        key = "quest",
        label = ns.L["Quest Unit"],
        enabled = function(s) return (s.colors or {}).questEnabled ~= false end,
    },
    {
        key = "player",
        label = ns.L["Enemy Player"],
        enabled = function(s) return (s.colors or {}).classColorEnemyPlayers ~= false end,
    },
}

local REACTION_OPTIONS = {
    { value = "hostile", text = ns.L["Hostile"] },
    { value = "neutral", text = ns.L["Neutral"] },
    { value = "tapped", text = ns.L["Tapped"] },
}

local function EnsurePreviewState()
    if State.previewState then return State.previewState end
    local defaults = ns.QUI_GetNameplatePreviewStateDefaults
        and ns.QUI_GetNameplatePreviewStateDefaults() or {}
    State.previewState = defaults
    if ns.QUI_SetNameplatePreviewState then
        ns.QUI_SetNameplatePreviewState(State.previewState)
    end
    return State.previewState
end

local function ApplyPreviewState()
    if ns.QUI_RefreshNameplatePreview then
        ns.QUI_RefreshNameplatePreview()
    end
end

local previewObserverInstalled = false
local function InstallPreviewObserver()
    if previewObserverInstalled or type(ns.QUI_SetNameplatePreviewObserver) ~= "function" then
        return
    end
    previewObserverInstalled = true
    ns.QUI_SetNameplatePreviewObserver(function(w, h)
        local p = State.previewPanel
        if not p or not w or not h or w <= 0 or h <= 0 then return end
        if p.frame:IsVisible() and p.contentHost:IsVisible() then p.Resize(w, h) end
    end)
end

local function BuildControlStrip(panel)
    local strip = panel.controlStrip
    if not strip or strip._quiBuilt then return end
    strip._quiBuilt = true

    local optionsAPI = ns.QUI_Options
    if not optionsAPI or not optionsAPI.CreateSettingsCardGroup or not optionsAPI.BuildSettingRow then
        return
    end

    local previewState = EnsurePreviewState()
    local cells = {}

    local card = optionsAPI.CreateSettingsCardGroup(strip, 0)
    for _, def in ipairs(STATE_DEFS) do
        local toggle = GUI:CreateFormToggle(card.frame, nil, def.key, previewState, function()
            ApplyPreviewState()
        end)
        cells[def.key] = optionsAPI.BuildSettingRow(card.frame, def.label, toggle)
    end
    card.AddRow(cells.isTarget, cells.isFocus)
    card.AddRow(cells.mouseover, cells.casting)
    card.AddRow(cells.uninterruptible, cells.inCombat)
    card.AddRow(cells.execute, cells.aggro)
    card.AddRow(cells.quest, cells.player)
    card.Finalize()

    local reactionDropdown = GUI:CreateFormDropdown(strip, nil, REACTION_OPTIONS,
        "reaction", previewState, function()
            ApplyPreviewState()
        end)
    local reactionRow = optionsAPI.BuildSettingRow(strip, ns.L["Reaction"], reactionDropdown)
    reactionRow:ClearAllPoints()
    reactionRow:SetPoint("TOPLEFT", card.frame, "BOTTOMLEFT", 12, -8)
    reactionRow:SetPoint("TOPRIGHT", card.frame, "BOTTOMRIGHT", -12, -8)
    strip:SetHeight(card.frame:GetHeight() + 8 + reactionRow:GetHeight() + 8)
    strip:HookScript("OnSizeChanged", function()
        panel.Resize(nil, panel.contentHost:GetHeight())
    end)

    panel.RefreshControlStrip = function()
        local s = CurrentProfileNameplates()
        for _, def in ipairs(STATE_DEFS) do
            local cell = cells[def.key]
            if cell and cell.SetEnabled then
                cell:SetEnabled(def.enabled(s) and true or false)
            end
        end
    end
end

local function BuildPreviewBlock(pv, opts)
    local model = ResolveModel()
    local getTypeOptions = model and model.GetTypeOptions
    local showDropdown = not opts or opts.showDropdown ~= false
    State.selectedType = NormalizeTypeKey(State.selectedType)
    local built = FullSurface.BuildDropdownPreviewBlock(pv, {
        gui = GUI,
        selectedValue = State.selectedType,
        dropdownStateKey = "_selectedType",
        dropdownLabel = ns.L["Nameplate Type"],
        dropdownOptions = type(getTypeOptions) == "function" and getTypeOptions() or {},
        dropdownConfig = { searchable = false, collapsible = false, compact = true },
        headerHeight = 22,
        headerTopOffset = -4,
        previewFillAlpha = 0,
        showDropdown = showDropdown,
        onDropdownChanged = SetSelectedType,
    })
    if not built then return end
    built.headerRow:ClearAllPoints()
    built.headerRow:SetPoint("TOPLEFT", pv, "TOPLEFT", 8, -4)
    built.headerRow:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -8, -4)
    local zoomState = { value = State.previewZoom }
    local zoom = GUI:CreateFormDropdown(built.headerRow, ns.L["Preview zoom"], {
        { value = 1, text = "1x" }, { value = 2, text = "2x" }, { value = 3, text = "3x" },
    }, "value", zoomState, function()
        State.previewZoom = zoomState.value
        local driver = ns.QUI_NameplatesPreviewDriver
        if driver and driver.SetZoom then driver.SetZoom(State.previewZoom) end
    end, nil, { searchable = false, collapsible = false, compact = true })
    zoom:SetPoint("LEFT", built.headerRow, "LEFT", showDropdown and 0 or 100, 0)
    pv._quiPreviewZoom = zoom
    local host = built.previewHost
    local contentHost = CreateFrame("Frame", nil, host)
    contentHost:SetPoint("TOP", host, "TOP", 0, 0)
    contentHost:SetSize(210, 80)
    local strip = CreateFrame("Frame", nil, host)
    strip:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -88)
    strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -88)
    strip:SetHeight(STRIP_HEIGHT)
    local panel = { frame = pv, contentHost = contentHost, controlStrip = strip }
    local refreshControls
    local controlsToggle = GUI:CreateButton(host, ns.L["Preview controls"], 0, 22, function()
        State.previewControlsExpanded = not State.previewControlsExpanded
        refreshControls(true)
    end, "ghost")
    controlsToggle.text:ClearAllPoints()
    controlsToggle.text:SetPoint("LEFT", controlsToggle, "LEFT", 22, 0)
    controlsToggle.text:SetPoint("RIGHT", controlsToggle, "RIGHT", -8, 0)
    controlsToggle.text:SetJustifyH("LEFT")
    local color = GUI.Colors.text
    controlsToggle.chevron = ns.UIKit.CreateChevronCaret(controlsToggle, {
        point = "LEFT", xPixels = 8, sizePixels = 8,
        expanded = State.previewControlsExpanded == true, collapsedDirection = "right",
        r = color[1], g = color[2], b = color[3],
    })
    pv._quiPreviewControlsToggle = controlsToggle
    panel.Resize = function(width, height)
        if not height or height <= 0 then return end
        if width and width > 0 then contentHost:SetWidth(width) end
        contentHost:SetHeight(height)
        controlsToggle:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(height + 8))
        controlsToggle:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -(height + 8))
        strip:SetPoint("TOPLEFT", controlsToggle, "BOTTOMLEFT", 0, -4)
        strip:SetPoint("TOPRIGHT", controlsToggle, "BOTTOMRIGHT", 0, -4)
        local controlsHeight = State.previewControlsExpanded and (4 + strip:GetHeight()) or 0
        local natural = pv._quiPreviewChromeHeight + height + 8 + controlsToggle:GetHeight() + controlsHeight
        if natural ~= (pv._quiPreviewNaturalHeight or pv:GetHeight()) then pv:SetHeight(natural) end
    end
    refreshControls = function(resetScroll)
        strip:SetShown(State.previewControlsExpanded == true)
        ns.UIKit.SetChevronCaretExpanded(controlsToggle.chevron, State.previewControlsExpanded == true)
        panel.Resize(nil, contentHost:GetHeight())
        local viewport = pv._quiPreviewViewport
        if resetScroll and viewport then
            local scroll = ns.UIKit.GetSmoothScroll(viewport)
            if scroll then scroll:ScrollTo(0, true) else viewport:SetVerticalScroll(0) end
        end
    end
    EnsurePreviewState()
    BuildControlStrip(panel)
    InstallPreviewObserver()
    refreshControls(false)
    local function Activate()
        if not host:IsVisible() then return end
        State.previewPanel = panel
        State.previewZoom = 3
        refreshControls(false)
        if built.dropdown then
            State.dropdown = built.dropdown
            built.dropdown.SetValue(GetSelectedType(), true)
        end
        if panel.RefreshControlStrip then panel.RefreshControlStrip() end
        if ns.QUI_NameplatesPreviewDriver then
            zoom.SetValue(State.previewZoom, true)
            ns.QUI_NameplatesPreviewDriver.SetZoom(State.previewZoom)
            ns.QUI_NameplatesPreviewDriver.SetSelectedType(GetSelectedType())
        end
        if ns.QUI_BuildNameplatePreview then ns.QUI_BuildNameplatePreview(contentHost) end
    end
    host:HookScript("OnShow", Activate)
    pv:HookScript("OnShow", Activate)
    pv:HookScript("OnHide", function()
        if State.previewPanel == panel then State.previewPanel = nil end
    end)
    Activate()
end

local function BuildTypeDropdown(body, feature)
    local model = ResolveModel(feature)
    local getTypeOptions = model and model.GetTypeOptions
    local typeOptions = type(getTypeOptions) == "function" and getTypeOptions() or {}
    local typeAvailable = #typeOptions > 0
    local dropdownOptions = typeAvailable and typeOptions or {
        {
            value = "",
            text = ns.L["Nameplate Type"] .. ns.L[" settings unavailable (module not loaded)."],
        },
    }

    local dropdownRow = FullSurface.BuildContextDropdownRow(body, {
        gui = GUI,
        label = ns.L["Nameplate Type"],
        stateKey = "_selectedType",
        selectedValue = typeAvailable and State.selectedType or "",
        options = dropdownOptions,
        meta = {
            description = ns.L["Settings in the tabs below apply to the chosen type; Behavior is shared by every type."],
        },
        height = DROPDOWN_ROW_H,
        onChanged = function(value)
            SetSelectedType(value)
        end,
    })

    State.dropdown = dropdownRow and dropdownRow.dropdown or nil

    if dropdownRow and dropdownRow.dropdown and dropdownRow.dropdown.SetEnabled then
        dropdownRow.dropdown:SetEnabled(typeAvailable)
    end

    return dropdownRow, typeAvailable
end

local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)

    local result = FullSurface.BuildScrollTabBody(body, {
        cacheTabBodies = true,
        state = State,
        clearFrame = ClearFrame,
        createTabStrip = BuildTabStrip,
        resolveVariantKey = ResolveTabVariant,
        initialize = function()
            State.activeTab = State.activeTab or "general"
            SetSelectedType(State.selectedType)
        end,
        getTabs = function()
            return tabModel:GetTabs()
        end,
        getActiveTab = function()
            return tabModel:GetActiveKey()
        end,
        setActiveTab = function(tabKey)
            tabModel:SetActiveKey(tabKey)
        end,
        render = function(host, activeTab)
            return tabModel:RenderKey(host, activeTab)
        end,
    })

    return result
end

local function RepaintActiveTab()
    InvalidateTabBodies()
    if State.repaintTabs then
        State.repaintTabs()
    end
end

ns.QUI_NameplatesSettingsSurface = {
    SetActiveTab = SetActiveTab,
    SetSelectedType = SetSelectedType,
    GetSelectedType = GetSelectedType,
    InvalidateTabBodies = InvalidateTabBodies,
    RepaintActiveTab = RepaintActiveTab,
    NavigateSearchEntry = NavigateSearchEntry,
    GetSearchRoot = GetSearchRoot,
    RenderPage = BuildTileBody,
    BuildTypeDropdown = BuildTypeDropdown,
    preview = { height = 360, build = BuildPreviewBlock },
}
