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
local C = GUI.Colors
local Settings = ns.Settings
local FullSurface = Settings and Settings.FullSurface
local ClearFrame = FullSurface and FullSurface.ClearFrame

-- File-scoped snapshot of db.profile.ncdm.perLoadoutSpec used to detect
-- the false→true transition in the toggle onChange handler. The framework
-- writes dbTable[dbKey] = newValue BEFORE calling onChange, so reading the
-- DB inside onChange gives the NEW value. This upvalue captures the OLD
-- value by being set at BuildPreviewBlock entry and updated at the end of
-- every onChange call.
local _lastPerLoadoutSpecValue = false

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

local function SetActiveTab(tabKey)
    if type(tabKey) ~= "string" or tabKey == "" then
        return
    end

    local tabModel = EnsureTabModel()
    if not tabModel or type(tabModel.SetActiveKey) ~= "function" then
        return
    end

    tabModel:SetActiveKey(tabKey)
    if type(tabModel.ApplyNormalized) == "function" then
        tabModel:ApplyNormalized()
    end
    if State.repaintTabs then
        State.repaintTabs()
    end
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
-- PREVIEW BLOCK — top row (per-loadout toggle + context label) +
-- preview area (dropdown + buttons + visual preview).
-- Called by framework_v2 via tile.config.preview.build. The preview
-- frame is anchored above the sub-page tabs so dropdown + preview
-- persist across sub-tab switches.
--
-- Layout:
--   [☐ Per-Loadout Entries                                         ]
--   [Editing entries for: Spec — Loadout                           ]
--   [Container ▼]                                  [+ New] [Delete]
--   ────────────────────────────────────────────────────────────────
--                          LIVE PREVIEW
---------------------------------------------------------------------------

-- Fixed-size box at TOP-LEFT of the preview area holding the per-loadout
-- toggle (above) and the active-context label (below). NOT full-height —
-- the preview frame reclaims the full pv width BELOW this column via
-- post-build re-anchoring of the framework's previewHost.
--
-- WIDTH NOTE: GUI:CreateFormToggle hard-codes the switch widget at
-- container.LEFT + 180 (label width 170 + 10px gap), and the switch
-- itself is 26px wide. So the toggle's content extends to LEFT+206.
-- LEFT_COL_WIDTH must be at least 206 + 2*LEFT_COL_PAD = 222 or the
-- switch widget paints past leftCol's right edge into the dropdown row.
-- 240 leaves a comfortable margin and reads cleanly in-game.
local LEFT_COL_WIDTH = 240
local LEFT_COL_HEIGHT = 50
local LEFT_COL_PAD = 8

local function BuildPreviewBlock(pv)
    State.activeContainer = NormalizeContainerKey(State.activeContainer)

    -- Seed _lastPerLoadoutSpecValue from the current DB state so the
    -- onChange handler can detect the false→true transition correctly.
    local ncdm = QUI and QUI.db and QUI.db.profile and QUI.db.profile.ncdm
    _lastPerLoadoutSpecValue = ncdm and ncdm.perLoadoutSpec or false

    ---------------------------------------------------------------------------
    -- Left column — fixed-size 200x50 box at top-left holding the toggle
    -- (above) and the active-context label (below). Doesn't span pv's full
    -- height, so the preview frame can reclaim full width below it.
    ---------------------------------------------------------------------------
    local leftCol = CreateFrame("Frame", nil, pv)
    leftCol:SetPoint("TOPLEFT", pv, "TOPLEFT", 0, 0)
    leftCol:SetSize(LEFT_COL_WIDTH, LEFT_COL_HEIGHT)

    -- Active-context label (accent-color; visible only when perLoadoutSpec=true).
    -- Declared before UpdateLoadoutLabel so the closure can reference it.
    -- Final SetPoint anchors are applied AFTER the toggle widget is created
    -- so the label can sit immediately below it.
    local loadoutLabel = GUI:CreateLabel(leftCol, "", 11, C.accent)
    loadoutLabel:SetJustifyH("LEFT")
    loadoutLabel:Hide()

    -- UpdateLoadoutLabel — resolves the current spec + loadout name and
    -- updates the accent-color label below the toggle.
    -- Mirrors click_cast_content.lua:660-702 (D-04). Uses only
    -- GetLastSelectedSavedConfigID (never GetActiveConfigID) per LDST-04.
    local function UpdateLoadoutLabel()
        local db = QUI and QUI.db and QUI.db.profile and QUI.db.profile.ncdm
        if db and db.perLoadoutSpec then
            local specIndex = GetSpecialization and GetSpecialization()
            if specIndex then
                local _, specName = GetSpecializationInfo and GetSpecializationInfo(specIndex)
                    or nil, nil
                if specName then
                    local labelText = "Editing entries for: " .. specName
                    if C_ClassTalents then
                        local specID = GetSpecializationInfo(specIndex)
                        local savedID = specID and C_ClassTalents.GetLastSelectedSavedConfigID
                            and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                        local builds = specID and C_ClassTalents.GetConfigIDsBySpecID
                            and C_ClassTalents.GetConfigIDsBySpecID(specID)
                        local ordinal
                        local lookupID = savedID
                        if lookupID and builds then
                            for idx, cid in ipairs(builds) do
                                if cid == lookupID then
                                    ordinal = idx
                                    break
                                end
                            end
                        end
                        local configInfo = lookupID and C_Traits and C_Traits.GetConfigInfo
                            and C_Traits.GetConfigInfo(lookupID)
                        local customName = configInfo and configInfo.name
                        -- Use custom name only when it differs from the spec name
                        -- (Blizzard defaults to spec name for unnamed loadouts).
                        if customName and customName ~= specName then
                            labelText = labelText .. " \226\128\148 " .. customName
                        elseif ordinal then
                            labelText = labelText .. " \226\128\148 Loadout " .. ordinal
                        end
                    end
                    loadoutLabel:SetText(labelText)
                    loadoutLabel:Show()
                    return
                end
            end
        end
        loadoutLabel:Hide()
    end

    -- Trigger a full CDM repaint after the toggle changes routing.
    -- Toggle clicks cannot happen in combat (Blizzard UI is inaccessible
    -- then), so no InCombatLockdown guard is needed here.
    local function refreshCDM()
        if ns.CDMContainers and ns.CDMContainers.RefreshAll then
            ns.CDMContainers.RefreshAll()
        end
    end

    -- Toggle onChange handler. The framework has already written
    -- dbTable[dbKey] = newValue before calling us, so reading ncdm.perLoadoutSpec
    -- inside this callback gives the NEW value. The old value is captured in
    -- _lastPerLoadoutSpecValue which was set at BuildPreviewBlock entry and is
    -- updated at the end of every onChange call (D-07 / RESEARCH Q2).
    local function onPerLoadoutToggle(newValue)
        local oldValue = _lastPerLoadoutSpecValue

        -- false→true transition: seed the active loadout slot from slot 0
        -- once, if the active slot is empty and slot 0 has data (D-05).
        -- SeedActiveLoadoutFromSharedSlot is internally gated on both
        -- conditions; we just need to provide the current spec and loadout IDs
        -- via the public helper which resolves them internally.
        if oldValue == false and newValue == true then
            if ns.CDMContainers and ns.CDMContainers.SeedActiveLoadoutFromSharedSlot then
                ns.CDMContainers.SeedActiveLoadoutFromSharedSlot()
            end
        end
        -- true→false: routing-only change (GetEffectiveLoadoutID returns 0).
        -- No SavedVariables data is destroyed (D-05b / LDUX-05).

        -- Keep the snapshot current for the next onChange call.
        _lastPerLoadoutSpecValue = newValue

        UpdateLoadoutLabel()
        refreshCDM()
    end

    -- Always visible in v1 — the LDUX-02 per-spec-disable gate is vestigial
    -- for CDM (all built-in containers are always spec-scoped). Future
    -- per-spec-disable work would replace the constant below (D-03).
    local _isSpecScoped = true  -- luacheck: ignore (reserved for future use)

    local perLoadoutToggle = GUI:CreateFormCheckbox(
        leftCol,
        "Per-Loadout Entries",
        "perLoadoutSpec",
        ncdm,
        onPerLoadoutToggle,
        {
            description = "Maintain a separate spell list per saved talent loadout within each spec. Entries swap automatically when you change loadout. Toggle off preserves your per-loadout data.",
        }
    )
    perLoadoutToggle:SetPoint("TOPLEFT", leftCol, "TOPLEFT", LEFT_COL_PAD, -2)
    perLoadoutToggle:SetPoint("RIGHT", leftCol, "RIGHT", -LEFT_COL_PAD, 0)

    -- Position the accent label immediately below the toggle, inside leftCol.
    loadoutLabel:SetPoint("TOPLEFT", perLoadoutToggle, "BOTTOMLEFT", 0, -2)
    loadoutLabel:SetPoint("TOPRIGHT", perLoadoutToggle, "BOTTOMRIGHT", 0, -2)

    -- Perform the initial label render now that both the toggle and label exist.
    UpdateLoadoutLabel()

    -- Subscribe to loadout-change events so the label refreshes live when
    -- the player switches loadout in-game or a profile switch changes the
    -- perLoadoutSpec value (D-06).
    if ns.CDMContainers and ns.CDMContainers.RegisterLoadoutChangeCallback then
        ns.CDMContainers.RegisterLoadoutChangeCallback(function()
            -- Re-sync _lastPerLoadoutSpecValue on every confirmed loadout swap
            -- so the next toggle click detects the transition correctly,
            -- including after a profile switch that changed perLoadoutSpec.
            local db2 = QUI and QUI.db and QUI.db.profile and QUI.db.profile.ncdm
            _lastPerLoadoutSpecValue = db2 and db2.perLoadoutSpec or false
            UpdateLoadoutLabel()
        end)
    end

    ---------------------------------------------------------------------------
    -- Dropdown row + live preview. Pass `pv` directly so the preview frame
    -- (returned by the framework as `block.previewHost`) can reclaim the
    -- full pv width via post-build re-anchoring below leftCol. The dropdown
    -- header row is then nudged past leftCol's right edge so it doesn't
    -- overlap the toggle widget.
    ---------------------------------------------------------------------------
    local block = FullSurface.BuildDropdownPreviewBlock(pv, {
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

    -- Re-anchor the framework-built widgets so the toggle doesn't overlap
    -- the dropdown AND the preview reclaims full width below leftCol.
    -- Calling SetPoint with the same anchor name ("TOPLEFT") REPLACES the
    -- framework's existing TOPLEFT anchor while leaving TOPRIGHT / BOTTOMRIGHT
    -- intact, so the widgets still stretch to pv's right edge as before.
    if block and block.headerRow then
        -- 8px gap between leftCol and the dropdown row. The "Container"
        -- label inside the dropdown widget is also re-anchored below so
        -- it sits next to the actual dropdown selection (not at the row's
        -- left edge), which gives the toggle and label plenty of visual
        -- separation regardless of this gap value.
        block.headerRow:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", LEFT_COL_PAD, 0)
    end
    if block and block.previewHost then
        block.previewHost:SetPoint("TOPLEFT", leftCol, "BOTTOMLEFT", 0, -4)
    end

    -- Re-anchor the framework's internal "Container" FontString from the
    -- container's LEFT edge to RIGHT-of-dropdown-button so the label sits
    -- adjacent to the dropdown selection instead of floating at the row's
    -- left edge. The framework exposes the outer container as block.dropdown
    -- but doesn't surface the label or button directly — walk the container's
    -- regions/children to find them.
    if block and block.dropdown then
        local container = block.dropdown
        local labelText, dropdownButton
        for _, region in ipairs({ container:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                labelText = region
                break
            end
        end
        for _, child in ipairs({ container:GetChildren() }) do
            if child.GetObjectType and child:GetObjectType() == "Button" then
                dropdownButton = child
                break
            end
        end
        if labelText and dropdownButton then
            labelText:ClearAllPoints()
            labelText:SetPoint("RIGHT", dropdownButton, "LEFT", -8, 0)
        end
    end
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
    return FullSurface.CreateTabStrip(parent)
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
    SetActiveTab = SetActiveTab,
    RenderPage = BuildTileBody,
}
