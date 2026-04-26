--[[
    QUI Options — Blizzard UI Mover (Appearance tile sub-page)
    Migrated to V3 body pattern (CreateAccentDotLabel + CreateSettingsCardGroup
    + BuildSettingRow).
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local MOD_KEY_OPTIONS = {
    { value = "SHIFT", text = "Shift" },
    { value = "CTRL",  text = "Ctrl"  },
    { value = "ALT",   text = "Alt"   },
}

local PERSIST_OPTIONS = {
    { value = "close",   text = "Until frame closes" },
    { value = "lockout", text = "Until logout (session only)" },
    { value = "reset",   text = "Saved until reset" },
}

local function BuildBlizzardMoverTab(tabContent)
    local PAD = Shared.PADDING
    local SECTION_GAP = 14
    local BM = ns.QUI_BlizzardMover
    local db = Shared.GetDB()

    GUI:SetSearchContext({
        tabIndex = 2,
        tabName = "General & QoL",
        subTabIndex = 12,
        subTabName = "Blizzard Mover",
    })

    local bm = db and db.blizzardMover
    if not bm then
        local err = GUI:CreateLabel(tabContent, "Blizzard Mover settings are unavailable (database not ready).", 12, C.textMuted)
        err:SetPoint("TOPLEFT", PAD, -10)
        return
    end

    local function refreshMover()
        if not BM or not BM.functions then return end
        BM.functions.ApplyAll()
        if BM.functions.UpdateScaleWheelCaptureState then
            BM.functions.UpdateScaleWheelCaptureState()
        end
    end

    local y = -10

    -- Intro paragraph — muted label, full width, describes the feature
    -- before the user starts configuring.
    local intro = GUI:CreateLabel(
        tabContent,
        "Hold your move modifier (default Shift) and drag to reposition supported Blizzard windows. "
            .. "Optional: hold the scale modifier and use the mouse wheel on a panel to resize.",
        11,
        C.textMuted
    )
    intro:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
    intro:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    y = y - 44

    ---------------------------------------------------------------------------
    -- GENERAL SETTINGS
    ---------------------------------------------------------------------------
    Shared.CreateAccentDotLabel(tabContent, "General Settings", y); y = y - 22
    local genCard = Shared.CreateSettingsCardGroup(tabContent, y)

    -- Row: Enable + Require modifier (toggles)
    local enableW = GUI:CreateFormCheckbox(genCard.frame, nil, "enabled", bm, refreshMover,
        { description = "Master toggle for the Blizzard UI Mover. Disable to stop every supported Blizzard window from being draggable or scalable." })
    local reqModW = GUI:CreateFormCheckbox(genCard.frame, nil, "requireModifier", bm, nil,
        { description = "When on, dragging only works while holding the move modifier. When off, any plain left-click drag repositions supported windows." })
    genCard.AddRow(
        Shared.BuildSettingRow(genCard.frame, "Enable Blizzard UI Mover", enableW),
        Shared.BuildSettingRow(genCard.frame, "Require modifier to drag", reqModW)
    )

    -- Row: Move modifier + Scale modifier (dropdowns)
    local moveModW = GUI:CreateFormDropdown(genCard.frame, nil, MOD_KEY_OPTIONS, "modifier", bm, nil,
        { description = "Modifier key that must be held to drag supported Blizzard windows to a new position." })
    local scaleModW = GUI:CreateFormDropdown(genCard.frame, nil, MOD_KEY_OPTIONS, "scaleModifier", bm, function()
        if BM and BM.functions and BM.functions.UpdateScaleWheelCaptureState then
            BM.functions.UpdateScaleWheelCaptureState()
        end
    end, { description = "Modifier key that must be held while using the mouse wheel to resize a panel." })
    genCard.AddRow(
        Shared.BuildSettingRow(genCard.frame, "Move modifier", moveModW),
        Shared.BuildSettingRow(genCard.frame, "Scale modifier", scaleModW)
    )

    -- Row: Mouse-wheel scaling toggle (full-width — paired with nothing
    -- since the remaining slot is already-dropdown-heavy).
    local scaleOnW = GUI:CreateFormCheckbox(genCard.frame, nil, "scaleEnabled", bm, refreshMover,
        { description = "Allow resizing supported Blizzard windows by holding the scale modifier and spinning the mouse wheel over them." })
    genCard.AddRow(Shared.BuildSettingRow(genCard.frame, "Enable mouse-wheel scaling", scaleOnW))

    -- Row: Position persistence (full-width dropdown with long labels)
    local persistW = GUI:CreateFormDropdown(genCard.frame, nil, PERSIST_OPTIONS, "positionPersistence", bm, refreshMover,
        { description = "How long a moved window keeps its custom position. Until frame closes resets immediately, Until logout keeps it for the session, and Saved until reset persists across reloads." })
    genCard.AddRow(Shared.BuildSettingRow(genCard.frame, "Position persistence", persistW))

    genCard.Finalize()
    y = y - genCard.frame:GetHeight() - SECTION_GAP

    ---------------------------------------------------------------------------
    -- PER-GROUP FRAME TOGGLES — dynamically populated from the Blizzard
    -- Mover module's group list. Each group gets its own accent-dot label
    -- + card group; entries within pair 2-per-row.
    ---------------------------------------------------------------------------
    local function ensureFrameRow(entry)
        bm.frames = bm.frames or {}
        local row = bm.frames[entry.id]
        if not row then
            row = {}
            bm.frames[entry.id] = row
        end
        if row.enabled == nil then
            row.enabled = entry.defaultEnabled ~= false
        end
        return row
    end

    if BM and BM.functions and BM.functions.GetGroups then
        for _, group in ipairs(BM.functions.GetGroups()) do
            local entries = BM.functions.GetEntriesForGroup(group.id) or {}
            if #entries > 0 then
                -- The "addons" group uses a search-friendly label tagged
                -- separately; every other group gets an accent-dot label.
                if group.id == "addons" then
                    GUI:SetSearchSection("Addons")
                end
                Shared.CreateAccentDotLabel(tabContent, group.label or group.id, y); y = y - 22

                local card = Shared.CreateSettingsCardGroup(tabContent, y)

                -- Pair entries 2-per-row; unpaired trailing entry gets full width.
                local i = 1
                while i <= #entries do
                    local leftEntry = entries[i]
                    local rightEntry = entries[i + 1]

                    local leftRow = ensureFrameRow(leftEntry)
                    local leftLabel = leftEntry.label or leftEntry.id
                    local leftToggle = GUI:CreateFormCheckbox(card.frame, nil, "enabled", leftRow, function()
                        if BM.functions.RefreshEntry then BM.functions.RefreshEntry(leftEntry) end
                    end, { description = "Allow the Blizzard UI Mover to handle the " .. leftLabel .. " window. Turn off to leave this frame at its stock position." })
                    local leftCell = Shared.BuildSettingRow(card.frame, leftLabel, leftToggle)

                    if rightEntry then
                        local rightRow = ensureFrameRow(rightEntry)
                        local rightLabel = rightEntry.label or rightEntry.id
                        local rightToggle = GUI:CreateFormCheckbox(card.frame, nil, "enabled", rightRow, function()
                            if BM.functions.RefreshEntry then BM.functions.RefreshEntry(rightEntry) end
                        end, { description = "Allow the Blizzard UI Mover to handle the " .. rightLabel .. " window. Turn off to leave this frame at its stock position." })
                        local rightCell = Shared.BuildSettingRow(card.frame, rightLabel, rightToggle)
                        card.AddRow(leftCell, rightCell)
                        i = i + 2
                    else
                        card.AddRow(leftCell)
                        i = i + 1
                    end
                end

                card.Finalize()
                y = y - card.frame:GetHeight() - SECTION_GAP
            end
        end
    else
        local pending = GUI:CreateLabel(
            tabContent,
            "Frame list loads after the addon finishes starting up. Reopen this tab if empty.",
            11,
            C.textMuted
        )
        pending:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        pending:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        pending:SetJustifyH("LEFT")
        y = y - 20
    end

    tabContent:SetHeight(math.abs(y) + 10)
end

ns.QUI_BlizzardMoverOptions = {
    BuildBlizzardMoverTab = BuildBlizzardMoverTab,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "blizzardMoverPage",
        moverKey = "blizzardMover",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 8 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildBlizzardMoverTab,
            }),
        },
    }))
end
