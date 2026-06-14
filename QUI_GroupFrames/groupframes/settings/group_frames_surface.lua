--[[
    QUI Options V2 — Group Frames tile
    Pattern mirrors options/tiles/cooldown_manager.lua, with the live
    preview detached into a docked side panel (CreateDockedPreviewPanel,
    anchored to the right edge of the options window) and a compact
    Party/Raid dropdown row above the inner tabs.
      - Inner tab strip promotes the composer's widget-bar elements to
        top-level tabs alongside the frame-level sections. Frame-
        level tabs (Appearance, Layout, Dimensions, Range & Pet,
        Spotlight) render through the shared schema surface;
        element tabs (Health, Power, Name, Buffs, Debuffs, Healer,
        Defensives, Auras, Pinned Auras, Private Auras, Indicators) invoke
        the composer's element builders through QUI_BuildGroupFrameElement.
      - General tab hosts the Enable toggle + Copy Settings.
      - Spotlight tab is gated to raid context (not supported for party).
      - Click-Cast stays on the Global tile per spec §6.3.
]]

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
-- Module state shared between the preview dropdown and the tabbed page body.
---------------------------------------------------------------------------
local State = {
    contextMode = "party",
    activeTab   = "general",
    dropdown    = nil,
    previewHost = nil,
    activeBody  = nil,
    repaintTabs = nil,
}

local TabModel
local EnsureTabModel

---------------------------------------------------------------------------
-- DOCKED PREVIEW PANEL — detached, anchored to the options window's right
-- edge. Lazily created; re-measured/resized after every composer rebuild
-- via the QUI_SetGroupFramePreviewObserver seam.
---------------------------------------------------------------------------
local function CurrentOptionsWindow()
    -- Prefer GUI.MainFrame, NOT the _G.QUI_Options global. GUI:RefreshAccentColor
    -- (theme change) recreates the options window and updates GUI.MainFrame, but
    -- leaves _G.QUI_Options pointing at the old, torn-down, hidden window —
    -- anchoring to the stale global parents the panel to a dead frame.
    return (GUI and GUI.MainFrame) or _G.QUI_Options
end

-- Install the composer resize observer exactly once. It reads State.previewPanel
-- dynamically, so it keeps working across panel rebuilds (see EnsurePreviewPanel).
local previewObserverInstalled = false
local function InstallPreviewObserver()
    if previewObserverInstalled or not ns.QUI_SetGroupFramePreviewObserver then
        return
    end
    previewObserverInstalled = true
    ns.QUI_SetGroupFramePreviewObserver(function(_, wrapper)
        local p = State.previewPanel
        if not p then return end
        -- Generation guard: a later rebuild (e.g. rapid Party/Raid toggle)
        -- reparents this cell's children away, so a deferred measure of the
        -- now-stale cell would shrink the panel to a stub. Skip if superseded.
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

local function EnsurePreviewPanel()
    local win = CurrentOptionsWindow()
    if not win then return nil end

    -- QUI_Options is torn down and rebuilt wholesale on theme change
    -- (GUI:RefreshAccentColor) — TeardownFrameTree does SetParent(nil) on this
    -- panel, and the rebuilt QUI_Options frame may be REUSED or REPLACED, so
    -- window identity is not a reliable signal. The robust check: the panel is
    -- valid only while still parented to the live window. After a teardown its
    -- parent is no longer the live window, so rebuild (and neutralize the orphan
    -- so it stops participating in the framework's refresh passes).
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

    local panel = FullSurface.CreateDockedPreviewPanel({
        gui = GUI,
        title = "Preview",
        idSuffix = "GroupFrames",
        window = win,
    })
    if not panel then return nil end

    State.previewPanel = panel
    InstallPreviewObserver()
    return panel
end

local function UpdatePreviewTitle()
    local p = State.previewPanel
    if not p then return end
    p.SetTitle(State.contextMode == "raid" and "Preview — Raid" or "Preview — Party")
end

local function RefreshPreviewPanel()
    local panel = EnsurePreviewPanel()
    if not panel then return end
    UpdatePreviewTitle()
    if _G.QUI_BuildGroupFramePreview then
        _G.QUI_BuildGroupFramePreview(panel.contentHost, State.contextMode)
    end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local ContextSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "contextMode",
        normalize = NormalizeContextMode,
        afterSet = function(key)
            EnsureTabModel():ApplyNormalized()
            if State.invalidateTabBodies then
                State.invalidateTabBodies()
            end

            if _G.QUI_RefreshGroupFramePreview then
                _G.QUI_RefreshGroupFramePreview(key)
            end
            if State.previewPanel then
                State.previewPanel.SetTitle(key == "raid" and "Preview — Raid" or "Preview — Party")
            end

            if State.repaintTabs then
                State.repaintTabs()
            end
        end,
    })

local function SetContextMode(key)
    ContextSelection:Set(key)
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

---------------------------------------------------------------------------
-- TAB STRIP — width-responsive wrapping: tabs pack onto one row when the
-- window is wide enough and wrap to additional rows as it narrows. Repaints
-- on size change (repaintOnSizeChanged below). Matches cooldown_manager.lua
-- styling (11pt labels, 2px accent bar under the active tab).
---------------------------------------------------------------------------
local function BuildTabStrip(parent)
    return FullSurface.CreateTabStrip(parent, {
        wrapRows = true,
        rowSpacing = 2,
        fallbackWidth = 780,
    })
end

---------------------------------------------------------------------------
-- TILE BODY — compact Party/Raid dropdown row (injected at body top via
-- initialize + tabTopOffset) + tab strip + scroll-wrapped content host.
-- Also docks the detached preview panel and ties its visibility to this
-- page's show/hide (covers tile-switch and window-close).
---------------------------------------------------------------------------
local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)
    local DROPDOWN_ROW_H = 30

    local result = FullSurface.BuildScrollTabBody(body, {
        cacheTabBodies = true,
        state = State,
        clearFrame = ClearFrame,
        createTabStrip = BuildTabStrip,
        tabTopOffset = -(DROPDOWN_ROW_H + 8),
        initialize = function()
            State.activeTab = State.activeTab or "general"
            local model = ResolveModel(feature)
            local getContextOptions = model and model.GetContextOptions
            State.contextMode = NormalizeContextMode(State.contextMode)
            FullSurface.BuildContextDropdownRow(body, {
                gui = GUI,
                label = "Unit Group",
                stateKey = "_contextMode",
                selectedValue = State.contextMode,
                options = type(getContextOptions) == "function" and getContextOptions() or {},
                meta = {
                    description = "Switch between Party and Raid frame settings. Spotlight is only available for Raid frames.",
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
        render = function(host, activeTab)
            return tabModel:RenderKey(host, activeTab)
        end,
        repaintOnSizeChanged = true,
        deferResizeRepaint = true,
        preventReentry = true,
    })

    -- Dock + show the detached preview panel; tie its visibility to this page.
    EnsurePreviewPanel()
    if not body._gfPreviewHooked then
        body._gfPreviewHooked = true
        body:HookScript("OnShow", function()
            if State.previewPanel then State.previewPanel.Show() end
            RefreshPreviewPanel()
        end)
        body:HookScript("OnHide", function()
            if State.previewPanel then State.previewPanel.Hide() end
        end)
    end
    if State.previewPanel and body:IsShown() then
        State.previewPanel.Show()
        RefreshPreviewPanel()
    end

    return result
end

ns.QUI_GroupFramesSettingsSurface = {
    SetContextMode = SetContextMode,
    SetActiveTab = SetActiveTab,
    NavigateSearchEntry = NavigateSearchEntry,
    GetSearchRoot = GetSearchRoot,
    RenderPage = BuildTileBody,
}
