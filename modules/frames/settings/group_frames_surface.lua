--[[
    QUI Options V2 — Group Frames tile
    Pattern mirrors options/tiles/cooldown_manager.lua:
      - Preview block (Party/Raid dropdown + live composer preview)
        persists across inner tabs.
      - Inner tab strip promotes the composer's widget-bar elements to
        top-level tabs alongside the sliced provider sections. Frame-
        level tabs (Appearance, Layout, Dimensions, Range & Pet,
        Spotlight) render via WithOnlySections over BuildGroupFrameSettings;
        element tabs (Health, Power, Name, Buffs, Debuffs, Healer,
        Defensive, Aura Ind., Pinned, Priv. Auras, Indicators) invoke
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

local ACCENT_R, ACCENT_G, ACCENT_B = 0.2, 0.83, 0.6
if GUI and GUI.Colors and GUI.Colors.accent then
    ACCENT_R, ACCENT_G, ACCENT_B = GUI.Colors.accent[1], GUI.Colors.accent[2], GUI.Colors.accent[3]
end

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
-- Helpers
---------------------------------------------------------------------------
local ContextSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "contextMode",
        normalize = NormalizeContextMode,
        afterSet = function(key)
            EnsureTabModel():ApplyNormalized()

            if _G.QUI_RefreshGroupFramePreview then
                _G.QUI_RefreshGroupFramePreview(key)
            end

            if State.repaintTabs then
                State.repaintTabs()
            end
        end,
    })

local function SetContextMode(key)
    ContextSelection:Set(key)
end

---------------------------------------------------------------------------
-- PREVIEW BLOCK — Party/Raid dropdown + hoisted composer preview.
---------------------------------------------------------------------------
local function BuildPreviewBlock(pv)
    local model = ResolveModel()
    local getContextOptions = model and model.GetContextOptions

    State.contextMode = NormalizeContextMode(State.contextMode)
    FullSurface.BuildDropdownPreviewBlock(pv, {
        gui = GUI,
        state = State,
        selectedValue = State.contextMode,
        dropdownStateKey = "_contextMode",
        dropdownLabel = "Unit Group",
        dropdownOptions = type(getContextOptions) == "function" and getContextOptions() or {},
        dropdownMeta = {
            description = "Switch between Party and Raid frame settings. Spotlight is only available for Raid frames.",
        },
        clipPreviewChildren = true,
        onDropdownChanged = function(value)
            SetContextMode(value)
        end,
        onBuildPreviewHost = function(previewHost)
            State.previewHost = previewHost
            if _G.QUI_BuildGroupFramePreview then
                _G.QUI_BuildGroupFramePreview(previewHost, State.contextMode)
            end
        end,
    })
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
-- TAB STRIP — two-row layout so the wider tab set fits without clipping.
-- Matches cooldown_manager.lua styling (11pt labels, 2px accent bar under
-- the active tab).
---------------------------------------------------------------------------
local function BuildTabStrip(parent)
    return FullSurface.CreateTabStrip(parent, {
        accent = { ACCENT_R, ACCENT_G, ACCENT_B },
        wrapRows = true,
        rowSpacing = 2,
        fallbackWidth = 780,
    })
end

---------------------------------------------------------------------------
-- TILE BODY — tab strip + scroll-wrapped content host.
---------------------------------------------------------------------------
local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)
    return FullSurface.BuildScrollTabBody(body, {
        state = State,
        clearFrame = ClearFrame,
        createTabStrip = BuildTabStrip,
        initialize = function()
            State.activeTab = State.activeTab or "general"
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
        render = function(host)
            return tabModel:RenderKey(host)
        end,
        repaintOnSizeChanged = true,
        deferResizeRepaint = true,
        preventReentry = true,
    })
end

ns.QUI_GroupFramesSettingsSurface = {
    preview = {
        height = 240,
        build = BuildPreviewBlock,
    },
    SetContextMode = SetContextMode,
    RenderPage = BuildTileBody,
}
