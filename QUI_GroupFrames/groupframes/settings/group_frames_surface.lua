local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
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
    return ns.QUI_GroupFramesSettingsModel
end

local function NormalizeContextMode(contextMode)
    local model = ResolveModel()
    local normalize = model and model.NormalizeContextMode
    if type(normalize) == "function" then
        return normalize(contextMode)
    end
    return contextMode
end
local State = {
    contextMode = "party",
    activeTab   = "general",
    dropdown    = nil,
    previewHost = nil,
    activeBody  = nil,
    repaintTabs = nil,
    previewFilter = {
        threat = true, dispel = true, auras = true, indicators = true,
        targetedSpells = true, targetHighlight = true, pets = true, range = true,
    },
}

local TabModel
local EnsureTabModel

local function CurrentOptionsWindow()
    return (GUI and GUI.MainFrame) or _G.QUI_Options
end

local CurrentPreviewVDB

local previewObserverInstalled = false
local function InstallPreviewObserver()
    if previewObserverInstalled or not _G.QUI_SetGroupFramePreviewObserver then
        return
    end
    previewObserverInstalled = true
    _G.QUI_SetGroupFramePreviewObserver(function(_, wrapper)
        local p = State.previewPanel
        if not p then return end
        if p.RefreshControlStrip and CurrentPreviewVDB then
            p.RefreshControlStrip(CurrentPreviewVDB())
        end
        State.previewGen = (State.previewGen or 0) + 1
        local gen = State.previewGen
        local cell = wrapper and wrapper.previewCell
        local w, h = FullSurface.MeasureRenderedExtent(cell)
        if w <= 0 or h <= 0 then
            C_Timer.After(0, function()
                if State.previewGen ~= gen or not State.previewPanel then return end
                local w2, h2 = FullSurface.MeasureRenderedExtent(cell)
                if w2 > 0 and h2 > 0 then
                    State.previewPanel.Resize(w2, h2)
                end
            end)
            return
        end
        p.Resize(w, h)
    end)
end

local FILTER_DEFS = {
    { key = "threat",     label = ns.L["Threat"] },
    { key = "dispel",     label = ns.L["Dispel"] },
    { key = "auras",      label = ns.L["Auras"] },
    { key = "indicators", label = ns.L["Indicators"] },
    { key = "targetedSpells", label = ns.L["Targeted Spells"] },
    { key = "targetHighlight", label = ns.L["Target Highlight"] },
    { key = "pets",       label = ns.L["Pet Frames"] },
    { key = "range",      label = ns.L["Range Fade"] },
}

local STRIP_CARD_ROW_H = 32
local STRIP_HEIGHT = (4 * STRIP_CARD_ROW_H) + 8 + 28 + 6

function CurrentPreviewVDB()
    local Driver = ns.QUI_GroupFramesPreview
    if not Driver or not Driver._GetGFDB or not Driver._GetContextDB then return nil end
    local gfdb = Driver._GetGFDB()
    return Driver._GetContextDB(gfdb, State.contextMode), gfdb
end

local function ApplyFilterToDriver()
    if _G.QUI_SetGroupFramePreviewFilter then
        _G.QUI_SetGroupFramePreviewFilter(State.previewFilter)
    end
end

local function BuildControlStrip(panel)
    local strip = panel.controlStrip
    if not strip or strip._quiBuilt then return end
    strip._quiBuilt = true
    local Driver = ns.QUI_GroupFramesPreview
    local optionsAPI = ns.QUI_Options
    if not optionsAPI or not optionsAPI.CreateSettingsCardGroup or not optionsAPI.BuildSettingRow then
        return
    end
    local cells = {}

    local card = optionsAPI.CreateSettingsCardGroup(strip, 0)
    for _, def in ipairs(FILTER_DEFS) do
        local toggle = GUI:CreateFormToggle(card.frame, nil, def.key, State.previewFilter, function()
            ApplyFilterToDriver()
        end)
        cells[def.key] = optionsAPI.BuildSettingRow(card.frame, def.label, toggle)
    end
    card.AddRow(cells.threat, cells.dispel)
    card.AddRow(cells.auras, cells.indicators)
    card.AddRow(cells.targetedSpells, cells.targetHighlight)
    card.AddRow(cells.pets, cells.range)
    card.Finalize()

    local _, gfdb = CurrentPreviewVDB()
    local raidSlider = GUI:CreateFormSlider(strip, nil, 5, 40, 5, "raidCount",
        (gfdb and gfdb.testMode) or {}, function(value)
            local Drv = ns.QUI_GroupFramesPreview
            local snapped = (Drv and Drv._SnapRaidCount(value)) or value
            if gfdb and gfdb.testMode then gfdb.testMode.raidCount = snapped end
            if _G.QUI_RefreshGroupFramePreview then
                _G.QUI_RefreshGroupFramePreview("raid")
            end
        end)
    local raidRow = optionsAPI.BuildSettingRow(strip, ns.L["Raid Size"], raidSlider)
    raidRow:ClearAllPoints()
    raidRow:SetPoint("TOPLEFT", card.frame, "BOTTOMLEFT", 12, -8)
    raidRow:SetPoint("TOPRIGHT", card.frame, "BOTTOMRIGHT", -12, -8)

    panel.RefreshControlStrip = function(vdb)
        for _, def in ipairs(FILTER_DEFS) do
            local c = cells[def.key]
            local enabled = (Driver and Driver._ChipEnabledInConfig(vdb, def.key)) and true or false
            if c and c.SetEnabled then c:SetEnabled(enabled) end
        end
        if State.contextMode == "raid" then raidRow:Show() else raidRow:Hide() end
    end
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

    State.previewSession = State.previewSession or {}
    local panel = FullSurface.CreateDockedPreviewPanel({
        gui = GUI,
        title = ns.L["Preview"],
        idSuffix = "GroupFrames",
        window = win,
        controlStripHeight = STRIP_HEIGHT,
        minWidth = 240,
        sessionState = State.previewSession,
    })
    if not panel then return nil end

    State.previewPanel = panel
    InstallPreviewObserver()
    BuildControlStrip(panel)
    return panel
end

local function UpdatePreviewTitle()
    local p = State.previewPanel
    if not p then return end
    p.SetTitle(State.contextMode == "raid" and ns.L["Preview — Raid"] or ns.L["Preview — Party"])
end

local function RefreshPreviewPanel()
    local panel = EnsurePreviewPanel()
    if not panel then return end
    UpdatePreviewTitle()
    if panel.RefreshControlStrip then
        local vdb = CurrentPreviewVDB()
        panel.RefreshControlStrip(vdb)
    end
    if _G.QUI_BuildGroupFramePreview then
        _G.QUI_BuildGroupFramePreview(panel.contentHost, State.contextMode)
    end
end

local ContextSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "contextMode",
        normalize = NormalizeContextMode,
        afterSet = function(key)
            EnsureTabModel():ApplyNormalized()

            if _G.QUI_RefreshGroupFramePreview then
                _G.QUI_RefreshGroupFramePreview(key)
            end
            if State.previewPanel and State.previewPanel.RefreshControlStrip then
                local vdb = CurrentPreviewVDB()
                State.previewPanel.RefreshControlStrip(vdb)
            end
            if State.previewPanel then
                State.previewPanel.SetTitle(key == "raid" and ns.L["Preview — Raid"] or ns.L["Preview — Party"])
            end

            if State.repaintTabs then
                State.repaintTabs(false)
            end
        end,
    })

local function SetContextMode(key)
    ContextSelection:Set(key)
end

local function GetContextMode()
    return State.contextMode
end

local function SetActiveTab(tabKey)
    if type(tabKey) ~= "string" or tabKey == "" then
        return false
    end

    local tabModel = EnsureTabModel()
    if not tabModel or type(tabModel.GetTabs) ~= "function" or type(tabModel.SetActiveKey) ~= "function" then
        return false
    end

    local found = false
    for _, tab in ipairs(tabModel:GetTabs() or {}) do
        if tab.key == tabKey then
            found = true
            break
        end
    end
    if not found then
        return false
    end

    tabModel:SetActiveKey(tabKey)
    if type(tabModel.ApplyNormalized) == "function" then
        tabModel:ApplyNormalized()
    end

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
    if entry.providerKey == "raidFrames" or entry.providerKey == "spotlightFrames" then
        SetContextMode("raid")
        handled = true
    elseif entry.providerKey == "partyFrames" then
        SetContextMode("party")
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
    return FullSurface.CreateTabStrip(parent, {
        wrapRows = true,
        rowSpacing = 2,
        fallbackWidth = 780,
    })
end

local SECTION_NAV_TABS = {
    appearance = true,
    indicators = true,
    layout = true,
}

local function InstallSectionRegistry(host)
    if type(host._quiNavSections) == "table" then
        wipe(host._quiNavSections)
    else
        host._quiNavSections = {}
    end
    if not host.RegisterSection then
        function host:RegisterSection(id, label, frame)
            if type(id) ~= "string" or id == "" or not frame then
                return
            end
            local resolved = (type(label) == "string" and label ~= "") and label or id
            local list = self._quiNavSections
            for i, existing in ipairs(list) do
                if existing.id == id then
                    list[i] = { id = id, label = resolved, frame = frame }
                    return
                end
            end
            list[#list + 1] = { id = id, label = resolved, frame = frame }
        end
    end
end

local function ResetTabScrollAnchors(cached)
    local sf = cached and cached.scrollFrame
    if not sf or not cached.container then
        return
    end
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", cached.container, "TOPLEFT", 5, -5)
    sf:SetPoint("BOTTOMRIGHT", cached.container, "BOTTOMRIGHT", -28, 5)
end

local function BuildTabSectionNav(host, cached)
    if not host or not cached or not cached.scrollFrame then
        return
    end

    if cached._sectionNav then
        if cached._sectionNav.destroy then
            cached._sectionNav.destroy()
        end
        cached._sectionNav = nil
    end
    ResetTabScrollAnchors(cached)

    local sections = host._quiNavSections
    if type(sections) ~= "table" or #sections < 2 then
        return
    end

    local function tryBuild()
        if cached._sectionNav then
            return
        end
        local bodyH = host.GetHeight and host:GetHeight() or 0
        local viewH = cached.scrollFrame.GetHeight and cached.scrollFrame:GetHeight() or 0
        if bodyH > viewH and viewH > 0 then
            cached._sectionNav = GUI:RenderSectionNav(cached.scrollFrame, host, sections)
        end
    end
    tryBuild()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, tryBuild)
    end
end

local function ActivatePreviewBody(body)
    if not body then return end

    local getContextMode = body._gfPreviewContextGetter
    if type(getContextMode) == "function" then
        local contextMode = NormalizeContextMode(getContextMode())
        if contextMode and contextMode ~= State.contextMode then
            SetContextMode(contextMode)
        end
    end

    if State.previewPanel then State.previewPanel.Show() end
    RefreshPreviewPanel()
end

local function BindPreviewBody(body, getContextMode)
    if not body then return end
    body._gfPreviewContextGetter = getContextMode
    EnsurePreviewPanel()
    if not body._gfPreviewHooked then
        body._gfPreviewHooked = true
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

local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)
    local DROPDOWN_ROW_H = 30
    local contextDropdown

    local result = FullSurface.BuildScrollTabBody(body, {
        cacheTabBodies = true,
        state = State,
        clearFrame = ClearFrame,
        createTabStrip = BuildTabStrip,
        resolveVariantKey = function() return State.contextMode end,
        tabTopOffset = -(DROPDOWN_ROW_H + 8),
        initialize = function()
            State.activeTab = State.activeTab or "general"
            local model = ResolveModel(feature)
            local getContextOptions = model and model.GetContextOptions
            State.contextMode = NormalizeContextMode(State.contextMode)
            contextDropdown = FullSurface.BuildContextDropdownRow(body, {
                gui = GUI,
                label = ns.L["Unit Group"],
                stateKey = "_contextMode",
                selectedValue = State.contextMode,
                options = type(getContextOptions) == "function" and getContextOptions() or {},
                meta = {
                    description = ns.L["Switch between Party and Raid frame settings. Spotlight is only available for Raid frames."],
                },
                height = DROPDOWN_ROW_H,
                onChanged = function(value)
                    SetContextMode(value)
                end,
            })
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
        render = function(host, activeTab, cached)
            local navTab = SECTION_NAV_TABS[activeTab] and cached ~= nil
            if navTab then
                InstallSectionRegistry(host)
            end
            local result = tabModel:RenderKey(host, activeTab)
            if navTab then
                BuildTabSectionNav(host, cached)
                if not cached._navSizeHooked then
                    cached._navSizeHooked = true
                    host:HookScript("OnSizeChanged", function()
                        if cached._navRebuildPending then
                            return
                        end
                        cached._navRebuildPending = true
                        local function rebuild()
                            cached._navRebuildPending = false
                            BuildTabSectionNav(host, cached)
                        end
                        if C_Timer and C_Timer.After then
                            C_Timer.After(0, rebuild)
                        else
                            rebuild()
                        end
                    end)
                end
            end
            return result
        end,
        repaintOnSizeChanged = true,
        deferResizeRepaint = true,
        preventReentry = true,
    })

    BindPreviewBody(body, function()
        local db = contextDropdown and contextDropdown.dropdownDB
        return (db and db._contextMode) or State.contextMode
    end)

    return result
end

local function ShowPreviewOn(body, getContextMode)
    BindPreviewBody(body, getContextMode)
end

local function HidePreview()
    if State.previewPanel then State.previewPanel.Hide() end
end

local function InvalidateTabBodies()
    if State.invalidateTabBodies then
        State.invalidateTabBodies()
    end
end

ns.QUI_GroupFramesSettingsSurface = {
    InvalidateTabBodies = InvalidateTabBodies,
    SetContextMode = SetContextMode,
    GetContextMode = GetContextMode,
    SetActiveTab = SetActiveTab,
    NavigateSearchEntry = NavigateSearchEntry,
    GetSearchRoot = GetSearchRoot,
    RenderPage = BuildTileBody,
    ShowPreviewOn = ShowPreviewOn,
    HidePreview = HidePreview,
}
