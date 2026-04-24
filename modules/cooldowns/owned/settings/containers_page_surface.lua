--[[
    QUI Options V2 — Cooldown Manager tile
    Two sub-pages: Containers (dropdown-driven per-container editor with
    dynamic tabs) and Defaults (global toggles).

    Layout:

        [Container ▼]         [+ New]  [Delete]
        ────────────────────────────────────────
        LIVE PREVIEW
        ────────────────────────────────────────
        Entries │ Layout │ Filters │ Per-Spec │ Effects │ Position
        ────────────────────────────────────────
        (active tab renders here)

    The dropdown + buttons live INSIDE the tile-level preview block so
    they stay visible while the user switches sub-tabs. The sub-page
    body only owns the tab strip + content host.

    Filters / Per-Spec tabs only surface for custom containers; built-ins
    get a trimmed Entries / Layout / Effects / Position strip.
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
    return ns.QUI_CooldownManagerSettingsModel
end

---------------------------------------------------------------------------
-- Module state — shared between the tile-level preview (which owns the
-- dropdown + buttons) and the sub-page body (which owns the tab strip +
-- content host). Set at Register time; read/written from callbacks on
-- both surfaces.
---------------------------------------------------------------------------
local State = {
    activeContainer = nil,
    activeTab = "entries",
    dropdown = nil,         -- widget (preview header)
    deleteBtn = nil,        -- widget (preview header)
    activeBody = nil,       -- current tab body frame
    repaintTabs = nil,      -- set by BuildTileBody; refreshes the tab strip + active body
}

local TabModel
local EnsureTabModel

---------------------------------------------------------------------------
-- Container enumeration & labels
---------------------------------------------------------------------------
local function GetContainerOptions()
    local model = ResolveModel()
    local getOptions = model and model.GetContainerOptions
    if type(getOptions) == "function" then
        return getOptions()
    end
    return {}
end

local function IsBuiltIn(containerKey)
    local model = ResolveModel()
    local isBuiltIn = model and model.IsBuiltIn
    return type(isBuiltIn) == "function" and isBuiltIn(containerKey) == true
end

local function HasContainer(containerKey)
    local model = ResolveModel()
    local hasContainer = model and model.HasContainer
    return type(hasContainer) == "function" and hasContainer(containerKey) == true
end

local function NormalizeContainerKey(containerKey)
    local model = ResolveModel()
    local normalize = model and model.NormalizeContainerKey
    if type(normalize) == "function" then
        return normalize(containerKey)
    end
    return containerKey
end

local ResetBody

---------------------------------------------------------------------------
-- SetActiveContainer — fires everywhere: updates dropdown widget, tab
-- strip (if bound), tab content (if bound), hoisted preview. The state
-- module hands out no-ops until the sub-page wires its callbacks.
---------------------------------------------------------------------------
local ContainerSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "activeContainer",
        normalize = NormalizeContainerKey,
        afterSet = function(key)
            if State.deleteBtn then
                if IsBuiltIn(key) then State.deleteBtn:Hide() else State.deleteBtn:Show() end
            end

            EnsureTabModel():ApplyNormalized()

            if State.repaintTabs then
                State.repaintTabs()
            end

            if _G.QUI_RefreshCDMPreview then
                _G.QUI_RefreshCDMPreview(key)
            end
        end,
    })

local function SetActiveContainer(key)
    ContainerSelection:Set(key)
end

---------------------------------------------------------------------------
-- ClearFrame helper — wipes a frame's children + regions. Also scrubs
-- any composer-layout cache flag so the composer rebuilds when the
-- Entries tab is reshown.
---------------------------------------------------------------------------
function ResetBody(frame)
    if ClearFrame then
        ClearFrame(frame)
    end
    frame._composerLayout = nil
    frame._hideComposerNav = nil
end

-- Explicit bg + 4 border textures (SetBackdrop hits a Blizzard recursion
-- bug at small button sizes + non-integer scales).
local function SetSimpleBackdrop(frame, r, g, b, a, er, eg, eb, ea)
    local bg = frame._bg
    if not bg then
        bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        frame._bg = bg
    end
    bg:SetColorTexture(r, g, b, a)

    local border = frame._border
    if not border then
        border = {}
        for i = 1, 4 do border[i] = frame:CreateTexture(nil, "BORDER") end
        border[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border[1]:SetHeight(1)
        border[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        border[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        border[2]:SetHeight(1)
        border[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        border[3]:SetWidth(1)
        border[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        border[4]:SetWidth(1)
        frame._border = border
    end
    for i = 1, 4 do border[i]:SetColorTexture(er, eg, eb, ea) end
end

---------------------------------------------------------------------------
-- PREVIEW BLOCK — header row (dropdown + buttons) + visual preview.
-- Called by framework_v2 via tile.config.preview.build. The preview
-- frame is anchored above the sub-page tabs so dropdown + preview
-- persist across sub-tab switches.
---------------------------------------------------------------------------
local function BuildPreviewBlock(pv)
    State.activeContainer = NormalizeContainerKey(State.activeContainer)
    FullSurface.BuildDropdownPreviewBlock(pv, {
        gui = GUI,
        state = State,
        selectedValue = State.activeContainer,
        dropdownStateKey = "_activeContainer",
        dropdownLabel = "Container",
        dropdownOptions = GetContainerOptions(),
        dropdownMeta = {
            description = "Select which cooldown container to configure. Built-in containers have a reduced tab set; custom containers expose Filters and Per-Spec options.",
        },
        dropdownConfig = {
            searchable = true,
            collapsible = false,
        },
        previewFillAlpha = 0,
        headerActions = {
            {
                key = "new",
                text = "+ New",
                width = 90,
                height = 24,
                style = "primary",
                onClick = function()
                    if _G.QUI_ShowCDMNewContainerPopup then
                        _G.QUI_ShowCDMNewContainerPopup(function(newKey)
                            if State.dropdown and State.dropdown.SetOptions then
                                State.dropdown:SetOptions(GetContainerOptions())
                            end
                            SetActiveContainer(newKey)
                        end)
                    end
                end,
            },
            {
                key = "delete",
                text = "Delete",
                width = 90,
                height = 24,
                style = "ghost",
                stateField = "deleteBtn",
                onClick = function()
                    local key = State.activeContainer
                    if not key or IsBuiltIn(key) then
                        return
                    end
                    if ns.CDMContainers and ns.CDMContainers.DeleteContainer then
                        ns.CDMContainers.DeleteContainer(key)
                        if State.dropdown and State.dropdown.SetOptions then
                            State.dropdown:SetOptions(GetContainerOptions())
                        end
                        SetActiveContainer(NormalizeContainerKey(nil))
                    end
                end,
            },
        },
        onDropdownChanged = function(value)
            SetActiveContainer(value)
        end,
        onBuildPreviewHost = function(previewHost)
            if State.deleteBtn and IsBuiltIn(State.activeContainer) then
                State.deleteBtn:Hide()
            end
            if _G.QUI_BuildCDMPreview then
                _G.QUI_BuildCDMPreview(previewHost, State.activeContainer)
            end
        end,
    })
end

---------------------------------------------------------------------------
-- TILE BODY BUILDER — tab strip + content host.
--
-- Rendered inside tile.config.buildFunc (no framework sub-pages). We own
-- the full body which means full control over dynamic tab visibility
-- (Filters / Per-Spec hidden for built-ins) and no surprises when the
-- framework's sub-page tab strip eventually merges back into V1.
---------------------------------------------------------------------------

-- Horizontal scroll-free tab strip matching the framework's style:
-- plain labels, 11pt, 2px accent underline on the active tab. See
-- framework_v2.lua's RenderSubPageTabs for the reference look.
local function BuildTabStrip(parent)
    return FullSurface.CreateTabStrip(parent, {
        accent = { ACCENT_R, ACCENT_G, ACCENT_B },
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
            defaultKey = "entries",
            defaultHostKey = "scroll",
            tabs = tabDefinitions,
        })

    return TabModel
end

local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)
    return FullSurface.BuildMultiHostTabBody(body, {
        state = State,
        clearFrame = ResetBody,
        createTabStrip = BuildTabStrip,
        initialize = function()
            State.activeTab = State.activeTab or "entries"
        end,
        hosts = {
            composer = {
                kind = "plain",
                clearFrame = ResetBody,
            },
            scroll = {
                kind = "scroll",
                clearFrame = ResetBody,
            },
        },
        defaultHostKey = "scroll",
        resolveHostKey = function(activeTab)
            return tabModel:GetHostKey(activeTab)
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
end

ns.QUI_CooldownManagerSettingsSurface = {
    preview = {
        height = 230,
        build = BuildPreviewBlock,
    },
    SetActiveContainer = SetActiveContainer,
    RenderPage = BuildTileBody,
}
