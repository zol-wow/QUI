--[[
    QUI Layout Mode Settings Providers — Group Frames
    Migrated from options/tabs/frames/groupframedesigner.lua
    Provides settings for partyFrames and raidFrames layout mode elements.
    Element-level settings (Health, Power, Name, etc.) are in the Composer popup.
]]

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- DROPDOWN OPTIONS
---------------------------------------------------------------------------
local LAYOUT_OPTIONS = {
    { value = "VERTICAL", text = "Vertical (columns)" },
    { value = "HORIZONTAL", text = "Horizontal (rows)" },
}

local SPOTLIGHT_FILTER_OPTIONS = {
    { value = "ROLE", text = "By Role" },
    { value = "NAME", text = "By Name" },
}

local SORT_OPTIONS = {
    { value = "INDEX", text = "Group Index" },
    { value = "NAME", text = "Name" },
}

local GROUP_BY_OPTIONS = {
    { value = "GROUP", text = "Group Number" },
    { value = "ROLE", text = "Role" },
    { value = "CLASS", text = "Class" },
    { value = "NONE", text = "None (Flat List)" },
}

local ANCHOR_SIDE_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}

local PET_ANCHOR_OPTIONS = {
    { value = "BOTTOM", text = "Below Group" },
    { value = "RIGHT", text = "Right of Group" },
    { value = "LEFT", text = "Left of Group" },
}

-- Keys that live under party/raid sub-tables
local VISUAL_DB_KEYS = {
    general = true, layout = true, health = true, power = true, name = true,
    absorbs = true, healPrediction = true, indicators = true,
    healer = true, classPower = true, range = true, auras = true,
    privateAuras = true, auraIndicators = true, castbar = true,
    portrait = true, pets = true, dimensions = true, spotlight = true,
}

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function GetGFDB()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    local db = core and core.db and core.db.profile
    return db and db.quiGroupFrames
end

local function RefreshGF()
    if _G.QUI_RefreshGroupFrames then
        _G.QUI_RefreshGroupFrames()
    end
end

local function NotifyProvider(providerKey, structural)
    local builders = ns.SettingsBuilders
    if builders and builders.NotifyProviderChanged then
        builders.NotifyProviderChanged(providerKey, {
            structural = structural == true,
        })
    end
end

---------------------------------------------------------------------------
-- SHARED BUILDER: frame-level collapsibles for a given context
---------------------------------------------------------------------------
local function BuildFrameSettings(content, contextMode, sections, relayout)
    local settingsPanel = ns.QUI_LayoutMode_Settings
    local GUI = QUI and QUI.GUI
    local U = ns.QUI_LayoutMode_Utils
    if not GUI or not U then return end

    local P = U.PlaceRow
    local FORM_ROW = U.FORM_ROW

    local gfdb = GetGFDB()
    if not gfdb then return end

    local isRaid = contextMode == "raid"
    local vdb = isRaid and gfdb.raid or gfdb.party
    if not vdb then return end

    local function onChange()
        -- RefreshGF calls QUI_RefreshGroupFrames which already triggers
        -- RefreshTestMode internally — don't call it again here to avoid
        -- a double rebuild that orphans layout mode handles.
        RefreshGF()
        -- Re-sync layout mode handles so child overlays re-parent to the
        -- new test container after RefreshTestMode destroys the old one.
        local syncKey = isRaid and "raidFrames" or "partyFrames"
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(syncKey)
        end
    end

    ---------------------------------------------------------------------------
    -- OPEN COMPOSER BUTTON
    ---------------------------------------------------------------------------
    local composerRow = CreateFrame("Frame", nil, content)
    composerRow:SetHeight(36)

    local composerBtn = GUI:CreateButton(composerRow, "Open Composer", 160, 28, function()
        local composer = ns.QUI_LayoutMode_Composer
        if composer then
            composer:Open(contextMode)
        end
    end)
    composerBtn:SetPoint("TOPLEFT", 0, -4)
    sections[#sections + 1] = composerRow

    ---------------------------------------------------------------------------
    -- PREVIEW SIZE (raid only — controls test frame count)
    ---------------------------------------------------------------------------
    if isRaid then
        if not gfdb.testMode then gfdb.testMode = {} end
        local testMode = gfdb.testMode

        U.CreateCollapsible(content, "Preview Size", FORM_ROW + 8, function(body)
            local sy = -4
            P(GUI:CreateFormSlider(body, "Raid Preview Size", 10, 40, 5, "raidCount", testMode, function()
                local editMode = ns.QUI_GroupFrameEditMode
                if editMode and editMode:IsTestMode() then editMode:RefreshTestMode() end
                if _G.QUI_LayoutModeSyncHandle then _G.QUI_LayoutModeSyncHandle("raidFrames") end
            end), body, sy)
        end, sections, relayout)
    end

    ---------------------------------------------------------------------------
    -- APPEARANCE
    ---------------------------------------------------------------------------
    local general = vdb.general
    if not general then vdb.general = {} general = vdb.general end

    U.CreateCollapsible(content, "Appearance", 1, function(body)
        local sy = -4

        sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 3, 1, "borderSize", general, onChange), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Texture", U.GetTextureList(), "texture", general, onChange), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Dark Mode", "darkMode", general, onChange), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", general, onChange), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", "defaultBgColor", general, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1, 0.05, "defaultBgOpacity", general, onChange, {precision = 2}), body, sy)

        sy = P(GUI:CreateFormColorPicker(body, "Dark Mode Health Color", "darkModeHealthColor", general, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Dark Mode Health Opacity", 0, 1, 0.05, "darkModeHealthOpacity", general, onChange, {precision = 2}), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Dark Mode BG Color", "darkModeBgColor", general, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Dark Mode BG Opacity", 0, 1, 0.05, "darkModeBgOpacity", general, onChange, {precision = 2}), body, sy)

        sy = P(GUI:CreateFormDropdown(body, "Font", U.GetFontList(), "font", general, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 20, 1, "fontSize", general, onChange), body, sy)

        sy = P(GUI:CreateFormCheckbox(body, "Show Tooltips on Hover", "showTooltips", general, onChange), body, sy)

        -- Portrait
        local portrait = vdb.portrait
        if not portrait then vdb.portrait = {} portrait = vdb.portrait end
        sy = P(GUI:CreateFormCheckbox(body, "Show Portrait", "showPortrait", portrait, onChange), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Portrait Side", ANCHOR_SIDE_OPTIONS, "portraitSide", portrait, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Portrait Size", 16, 60, 1, "portraitSize", portrait, onChange), body, sy)

        local totalHeight = math.abs(sy) + 4
        local section = body:GetParent()
        section._contentHeight = totalHeight
    end, sections, relayout)

    ---------------------------------------------------------------------------
    -- LAYOUT
    ---------------------------------------------------------------------------
    local layout = vdb.layout
    if not layout then vdb.layout = {} layout = vdb.layout end

    -- Derive orientation from legacy grow settings if not yet set
    if not layout.orientation then
        local grow = layout.growDirection or "DOWN"
        layout.orientation = (grow == "LEFT" or grow == "RIGHT") and "HORIZONTAL" or "VERTICAL"
    end

    local function onOrientationChange()
        if layout.orientation == "HORIZONTAL" then
            layout.growDirection = "RIGHT"
            layout.groupGrowDirection = "DOWN"
        else
            layout.growDirection = "DOWN"
            layout.groupGrowDirection = "RIGHT"
        end
        onChange()
    end

    U.CreateCollapsible(content, "Layout", 1, function(body)
        local sy = -4

        sy = P(GUI:CreateFormDropdown(body, "Layout", LAYOUT_OPTIONS, "orientation", layout, onOrientationChange), body, sy)

        sy = P(GUI:CreateFormSlider(body, "Frame Spacing", 0, 10, 1, "spacing", layout, onChange), body, sy)

        if isRaid then
            local groupBy = layout.groupBy or "GROUP"
            if groupBy ~= "NONE" then
                sy = P(GUI:CreateFormSlider(body, "Group Spacing", 0, 30, 1, "groupSpacing", layout, onChange), body, sy)
            end
        end

        if not isRaid then
            sy = P(GUI:CreateFormCheckbox(body, "Show Player in Group", "showPlayer", layout, onChange), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Player Frame When Solo", "showSolo", layout, onChange), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Always Show Self First", "partySelfFirst", gfdb, onChange), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Sort by Role (Tank > Healer > DPS)", "sortByRole", layout, onChange), body, sy)
        end

        if isRaid then
            local groupByDropdown = GUI:CreateFormDropdown(body, "Group By", GROUP_BY_OPTIONS, "groupBy", layout, onChange)
            if GUI.SetWidgetProviderSyncOptions then
                GUI:SetWidgetProviderSyncOptions(groupByDropdown, { auto = true, structural = true })
            end
            sy = P(groupByDropdown, body, sy)
            local groupBy = layout.groupBy or "GROUP"
            if groupBy == "NONE" then
                sy = P(GUI:CreateFormSlider(body, "Units Per Column", 1, 40, 1, "unitsPerFlat", layout, onChange), body, sy)
            end
            sy = P(GUI:CreateFormDropdown(body, "Sort Method", SORT_OPTIONS, "sortMethod", layout, onChange), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Always Show Self First", "raidSelfFirst", gfdb, onChange), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Sort by Role (Tank > Healer > DPS)", "sortByRole", layout, onChange), body, sy)
        end

        local totalHeight = math.abs(sy) + 4
        local section = body:GetParent()
        section._contentHeight = totalHeight
    end, sections, relayout)

    ---------------------------------------------------------------------------
    -- DIMENSIONS
    ---------------------------------------------------------------------------
    local dims = vdb.dimensions
    if not dims then vdb.dimensions = {} dims = vdb.dimensions end

    U.CreateCollapsible(content, "Dimensions", 1, function(body)
        local sy = -4

        if not isRaid then
            sy = P(GUI:CreateFormSlider(body, "Width", 80, 400, 1, "partyWidth", dims, onChange), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 16, 80, 1, "partyHeight", dims, onChange), body, sy)
        else
            local info = GUI:CreateLabel(body, "Small Raid (6-15 players)", 10, GUI.Colors.text)
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetJustifyH("LEFT")
            sy = sy - 18
            sy = P(GUI:CreateFormSlider(body, "Width", 60, 400, 1, "smallRaidWidth", dims, onChange), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 14, 100, 1, "smallRaidHeight", dims, onChange), body, sy)

            local info2 = GUI:CreateLabel(body, "Medium Raid (16-25 players)", 10, GUI.Colors.text)
            info2:SetPoint("TOPLEFT", 0, sy)
            info2:SetJustifyH("LEFT")
            sy = sy - 18
            sy = P(GUI:CreateFormSlider(body, "Width", 50, 300, 1, "mediumRaidWidth", dims, onChange), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 12, 100, 1, "mediumRaidHeight", dims, onChange), body, sy)

            local info3 = GUI:CreateLabel(body, "Large Raid (26-40 players)", 10, GUI.Colors.text)
            info3:SetPoint("TOPLEFT", 0, sy)
            info3:SetJustifyH("LEFT")
            sy = sy - 18
            sy = P(GUI:CreateFormSlider(body, "Width", 40, 250, 1, "largeRaidWidth", dims, onChange), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 10, 100, 1, "largeRaidHeight", dims, onChange), body, sy)
        end

        local totalHeight = math.abs(sy) + 4
        local section = body:GetParent()
        section._contentHeight = totalHeight
    end, sections, relayout)

    ---------------------------------------------------------------------------
    -- RANGE CHECK
    ---------------------------------------------------------------------------
    local range = vdb.range
    if not range then vdb.range = {} range = vdb.range end

    U.CreateCollapsible(content, "Range Check", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Enable Range Check", "enabled", range, onChange), body, sy)
        P(GUI:CreateFormSlider(body, "Out-of-Range Alpha", 0.1, 0.8, 0.05, "outOfRangeAlpha", range, onChange, {precision = 2}), body, sy)
    end, sections, relayout)

    ---------------------------------------------------------------------------
    -- PET FRAMES
    ---------------------------------------------------------------------------
    local pets = vdb.pets
    if not pets then vdb.pets = {} pets = vdb.pets end

    U.CreateCollapsible(content, "Pet Frames", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Enable Pet Frames", "enabled", pets, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Pet Frame Width", 40, 200, 1, "width", pets, onChange), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Pet Frame Height", 10, 40, 1, "height", pets, onChange), body, sy)
        P(GUI:CreateFormDropdown(body, "Pet Anchor", PET_ANCHOR_OPTIONS, "anchorTo", pets, onChange), body, sy)
    end, sections, relayout)

    ---------------------------------------------------------------------------
    -- SPOTLIGHT (raid only — just enable toggle, settings live on spotlight handle)
    ---------------------------------------------------------------------------
    if isRaid then
        local spot = vdb.spotlight
        if not spot then vdb.spotlight = {} spot = vdb.spotlight end

        local function onSpotlightToggle()
            -- Default to showing tanks on first enable
            if spot.enabled and not spot.filterTank and not spot.filterHealer and not spot.filterDamager then
                spot.filterTank = true
            end
            local um = ns.QUI_LayoutMode
            if um then
                um:SetElementEnabled("spotlightFrames", spot.enabled == true)
            end
            onChange()
        end

        U.CreateCollapsible(content, "Spotlight", FORM_ROW + 8, function(body)
            local sy = -4

            local desc = GUI:CreateLabel(body, "Creates a separate frame that pins raid members by role or name. Enable and configure via the Spotlight handle.", 10, GUI.Colors.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            sy = sy - 28

            P(GUI:CreateFormCheckbox(body, "Enable Spotlight", "enabled", spot, onSpotlightToggle), body, sy)
        end, sections, relayout)
    end

    ---------------------------------------------------------------------------
    -- COPY SETTINGS
    ---------------------------------------------------------------------------
    local srcLabel = isRaid and "Raid" or "Party"
    local dstLabel = isRaid and "Party" or "Raid"

    U.CreateCollapsible(content, "Copy Settings", FORM_ROW + 8, function(body)
        local copyBtn = GUI:CreateButton(body, "Copy All: " .. srcLabel .. " \226\134\146 " .. dstLabel, 220, 28, function()
            GUI:ShowConfirmation({
                title = "Copy All Settings",
                message = "This will overwrite ALL " .. dstLabel .. " visual settings with " .. srcLabel .. " settings. Continue?",
                acceptText = "Copy All",
                cancelText = "Cancel",
                isDestructive = true,
                onAccept = function()
                    local src = isRaid and gfdb.raid or gfdb.party
                    local dst = isRaid and gfdb.party or gfdb.raid
                    if not src or not dst then return end
                    local function deepCopy(s)
                        if type(s) ~= "table" then return s end
                        local copy = {}
                        for k, v in pairs(s) do copy[k] = deepCopy(v) end
                        return copy
                    end
                    for key in pairs(VISUAL_DB_KEYS) do
                        if src[key] then
                            dst[key] = deepCopy(src[key])
                        end
                    end
                    RefreshGF()
                    NotifyProvider("partyFrames", true)
                    NotifyProvider("raidFrames", true)
                end,
            })
        end)
        copyBtn:SetPoint("TOPLEFT", 0, -4)
    end, sections, relayout)
end

---------------------------------------------------------------------------
-- REGISTER PROVIDERS
---------------------------------------------------------------------------
local function RegisterGroupFrameProviders()
    local settingsPanel = ns.QUI_LayoutMode_Settings
    if not settingsPanel then return end

    local GUI = QUI and QUI.GUI
    if not GUI then return end

    local U = ns.QUI_LayoutMode_Utils
    if not U then return end

    ---------------------------------------------------------------------------
    -- PARTY FRAMES
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("partyFrames", { build = function(content, key, width)
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end

        BuildFrameSettings(content, "party", sections, relayout)

        U.BuildPositionCollapsible(content, "partyFrames", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- RAID FRAMES
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("raidFrames", { build = function(content, key, width)
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end

        BuildFrameSettings(content, "raid", sections, relayout)

        U.BuildPositionCollapsible(content, "raidFrames", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- SPOTLIGHT FRAMES
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("spotlightFrames", { build = function(content, key, width)
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end

        local P = U.PlaceRow
        local FORM_ROW = U.FORM_ROW or 28

        local gfdb = QUI.db and QUI.db.profile and QUI.db.profile.quiGroupFrames
        if not gfdb then relayout() return content:GetHeight() end
        if not gfdb.raid then gfdb.raid = {} end
        local spot = gfdb.raid.spotlight
        if not spot then gfdb.raid.spotlight = {} spot = gfdb.raid.spotlight end

        local function onChange()
            -- Recreate runtime header with new settings
            local GF = ns.QUI_GroupFrames
            if GF and GF.RecreateSpotlightHeader then
                GF:RecreateSpotlightHeader()
            end
            -- Recreate layout mode previews
            local GFEM = ns.QUI_GroupFrameEditMode
            if GFEM then
                GFEM:DestroySpotlightHeader()
                GFEM:CreateSpotlightHeader()
            end
            if _G.QUI_LayoutModeSyncHandle then
                _G.QUI_LayoutModeSyncHandle("spotlightFrames")
            end
        end

        -- Rebuild the settings panel to reflect changed conditionals
        local function onChangeRebuild()
            onChange()
            local sp = ns.QUI_LayoutMode_Settings
            if sp then
                sp._currentKey = nil
                sp:Show("spotlightFrames")
            end
            NotifyProvider("spotlightFrames", true)
        end

        -- Filter
        U.CreateCollapsible(content, "Filter", 1, function(body)
            local sy = -4

            local desc = GUI:CreateLabel(body, "Pin raid members by role or name to a separate group.", 10, GUI.Colors.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            sy = sy - 18

            -- Filter mode
            if not spot.filterMode then spot.filterMode = "ROLE" end
            sy = P(GUI:CreateFormDropdown(body, "Filter By", SPOTLIGHT_FILTER_OPTIONS, "filterMode", spot, onChangeRebuild), body, sy)

            -- Role filter checkboxes
            if spot.filterMode == "ROLE" then
                sy = P(GUI:CreateFormCheckbox(body, "Tanks", "filterTank", spot, onChange), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Healers", "filterHealer", spot, onChange), body, sy)
            end

            -- Name filter
            if spot.filterMode == "NAME" then
                sy = P(GUI:CreateFormEditBox(body, "Player Names", "nameList", spot, onChange, { commitOnEnter = true, commitOnFocusLost = true }), body, sy)

                local hint = GUI:CreateLabel(body, "Comma-separated (e.g. Player1, Player2)", 10, GUI.Colors.textMuted)
                hint:SetPoint("TOPLEFT", 180, sy)
                hint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                hint:SetJustifyH("LEFT")
                sy = sy - 14
            end

            local totalHeight = math.abs(sy) + 4
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Dimensions
        U.CreateCollapsible(content, "Dimensions", 1, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Width", 60, 300, 1, "frameWidth", spot, onChange), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 16, 80, 1, "frameHeight", spot, onChange), body, sy)

            local totalHeight = math.abs(sy) + 4
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Layout
        U.CreateCollapsible(content, "Layout", 1, function(body)
            local sy = -4

            if not spot.orientation then
                local sg = spot.growDirection or "DOWN"
                spot.orientation = (sg == "LEFT" or sg == "RIGHT") and "HORIZONTAL" or "VERTICAL"
            end
            local function onSpotOrientChange()
                spot.growDirection = spot.orientation == "HORIZONTAL" and "RIGHT" or "DOWN"
                onChange()
            end
            sy = P(GUI:CreateFormDropdown(body, "Layout", LAYOUT_OPTIONS, "orientation", spot, onSpotOrientChange), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Spacing", 0, 10, 1, "spacing", spot, onChange), body, sy)

            local totalHeight = math.abs(sy) + 4
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "spotlightFrames", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })
end

C_Timer.After(3.1, RegisterGroupFrameProviders)
