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

local PREVIEW_SCALE_MAX = 3

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

local function CurrentOptionsWindow()
    return (GUI and GUI.MainFrame) or _G.QUI_Options
end

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
        p.Resize(w, h)
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

local function LifeSizeScale(win)
    local Helpers = ns.Helpers
    local SafeToNumber = Helpers and Helpers.SafeToNumber
    if not SafeToNumber or not UIParent or not win
        or type(win.GetEffectiveScale) ~= "function" then
        return 1
    end
    local uiScale = SafeToNumber(UIParent:GetEffectiveScale(), 0)
    local winScale = SafeToNumber(win:GetEffectiveScale(), 0)
    if uiScale <= 0 or winScale <= 0 then return 1 end
    return uiScale / winScale
end

local function EnsurePreviewPanel()
    local win = CurrentOptionsWindow()
    if not win then return nil end

    local cached = State.previewPanel
    if cached and cached.frame and cached.frame:GetParent() == win then
        return cached
    end

    if cached then
        State.previewPanel = nil
        if cached.frame then
            cached.frame:Hide()
            cached.frame:ClearAllPoints()
        end
    end

    if not FullSurface or type(FullSurface.CreateDockedPreviewPanel) ~= "function" then
        return nil
    end
    if not ns.QUI_BuildNameplatePreview then
        return nil
    end

    State.previewSession = State.previewSession or {}
    local panel = FullSurface.CreateDockedPreviewPanel({
        gui = GUI,
        title = ns.L["Preview"],
        idSuffix = "Nameplates",
        window = win,
        minWidth = 240,
        controlStripHeight = STRIP_HEIGHT,
        scaleMax = PREVIEW_SCALE_MAX,
        defaultScale = LifeSizeScale(win),
        sessionState = State.previewSession,
    })
    if not panel then return nil end

    State.previewPanel = panel
    InstallPreviewObserver()
    BuildControlStrip(panel)
    return panel
end

local function RefreshPreviewPanel()
    local panel = EnsurePreviewPanel()
    if not panel then return end
    if panel.RefreshControlStrip then
        panel.RefreshControlStrip()
    end
    if ns.QUI_BuildNameplatePreview then
        ns.QUI_BuildNameplatePreview(panel.contentHost)
    end
end

local function ActivatePreviewBody(body)
    if not body then return end
    local panel = EnsurePreviewPanel()
    if panel then panel.Show() end
    RefreshPreviewPanel()
end

local function BindPreviewBody(body)
    if not body then return end
    EnsurePreviewPanel()
    if not body._npPreviewHooked then
        body._npPreviewHooked = true
        body:HookScript("OnShow", function()
            ActivatePreviewBody(body)
        end)
        body:HookScript("OnHide", function()
            if State.previewPanel then State.previewPanel.Hide() end
        end)
    end
    if State.previewPanel and body:IsShown() then
        ActivatePreviewBody(body)
    end
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
        tabTopOffset = -(DROPDOWN_ROW_H + 8),
        initialize = function()
            State.activeTab = State.activeTab or "general"
            SetSelectedType(State.selectedType)
            BuildTypeDropdown(body, feature)
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

    BindPreviewBody(body)

    return result
end

local function ShowPreviewOn(body)
    BindPreviewBody(body)
end

local function HidePreview()
    if State.previewPanel then State.previewPanel.Hide() end
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
    ShowPreviewOn = ShowPreviewOn,
    HidePreview = HidePreview,
}
