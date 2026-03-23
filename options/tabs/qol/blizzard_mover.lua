--[[
    QUI Options — Blizzard UI Mover (General & QoL sub-tab)
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

local function BuildBlizzardMoverTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()
    local BM = ns.QUI_BlizzardMover

    GUI:SetSearchContext({
        tabIndex = 2,
        tabName = "General & QoL",
        subTabIndex = 12,
        subTabName = "Blizzard Mover",
    })

    local function refreshMover()
        if not BM or not BM.functions then return end
        BM.functions.ApplyAll()
        if BM.functions.UpdateScaleWheelCaptureState then
            BM.functions.UpdateScaleWheelCaptureState()
        end
    end

    local bm = db and db.blizzardMover
    if not bm then
        local err = GUI:CreateLabel(tabContent, "Blizzard Mover settings are unavailable (database not ready).", 12, C.textMuted)
        err:SetPoint("TOPLEFT", PADDING, y)
        return
    end

    local intro = GUI:CreateLabel(tabContent,
        "Hold your move modifier (default Shift) and drag to reposition supported Blizzard windows. "
            .. "Optional: hold the scale modifier and use the mouse wheel on a panel to resize.",
        11, C.textMuted)
    intro:SetPoint("TOPLEFT", PADDING, y)
    intro:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    intro:SetJustifyH("LEFT")
    y = y - 44

    local globalHeader = GUI:CreateSectionHeader(tabContent, "General Settings")
    globalHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - globalHeader.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Blizzard UI Mover", "enabled", bm, refreshMover)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local scaleCheck = GUI:CreateFormCheckbox(tabContent, "Enable mouse-wheel scaling", "scaleEnabled", bm, refreshMover)
    scaleCheck:SetPoint("TOPLEFT", PADDING, y)
    scaleCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local modKeyOpts = {
        { value = "SHIFT", text = "Shift" },
        { value = "CTRL", text = "Ctrl" },
        { value = "ALT", text = "Alt" },
    }

    local scaleModDrop = GUI:CreateFormDropdown(tabContent, "Scale modifier", modKeyOpts, "scaleModifier", bm, function()
        if BM and BM.functions and BM.functions.UpdateScaleWheelCaptureState then
            BM.functions.UpdateScaleWheelCaptureState()
        end
    end)
    scaleModDrop:SetPoint("TOPLEFT", PADDING, y)
    scaleModDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local persistOpts = {
        { value = "close", text = "Until frame closes" },
        { value = "lockout", text = "Until logout (session only)" },
        { value = "reset", text = "Saved until reset" },
    }
    local persistDrop = GUI:CreateFormDropdown(tabContent, "Position persistence", persistOpts, "positionPersistence", bm, refreshMover)
    persistDrop:SetPoint("TOPLEFT", PADDING, y)
    persistDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local reqModCheck = GUI:CreateFormCheckbox(tabContent, "Require modifier to drag", "requireModifier", bm, nil)
    reqModCheck:SetPoint("TOPLEFT", PADDING, y)
    reqModCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local moveModDrop = GUI:CreateFormDropdown(tabContent, "Move modifier", modKeyOpts, "modifier", bm, nil)
    moveModDrop:SetPoint("TOPLEFT", PADDING, y)
    moveModDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    y = y - 12

    local COL_GAP = 10
    local GRID_ROW = FORM_ROW
    -- Form toggles use ~180px label offset + 40px track; keep each column at least this wide before adding another.
    local MIN_COL_W = 232

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

    local function NumColumnsForWidth(w)
        if not w or w < 40 then
            return 1
        end
        if w >= 3 * MIN_COL_W + 2 * COL_GAP then
            return 3
        end
        if w >= 2 * MIN_COL_W + COL_GAP then
            return 2
        end
        return 1
    end

    local function ReflowToggleGrid(container, toggles)
        local w = container:GetWidth()
        if not w or w < 40 then
            return
        end
        if #toggles == 0 then
            container:SetHeight(1)
            return
        end
        local n = NumColumnsForWidth(w)
        local inner = w - (n - 1) * COL_GAP
        local colW = inner / n
        local numRows = math.ceil(#toggles / n)
        for i, chk in ipairs(toggles) do
            local col = (i - 1) % n
            local row = math.floor((i - 1) / n)
            chk:ClearAllPoints()
            chk:SetPoint("TOPLEFT", container, "TOPLEFT", col * (colW + COL_GAP), -row * GRID_ROW)
            chk:SetWidth(colW)
        end
        container:SetHeight(numRows * GRID_ROW)
    end

    if BM and BM.functions and BM.functions.GetGroups then
        local gridReflowFns = {}

        local prevGroupBottom = moveModDrop
        local firstGroup = true
        for _, group in ipairs(BM.functions.GetGroups()) do
            local gh
            if group.id ~= "addons" then
                gh = GUI:CreateSectionHeader(tabContent, group.label or group.id)
                gh:SetPoint("TOPLEFT", prevGroupBottom, "BOTTOMLEFT", 0, firstGroup and -12 or -6)
            else
                GUI:SetSearchSection("Addons")
            end

            local gridPanel = CreateFrame("Frame", nil, tabContent)
            if gh then
                gridPanel:SetPoint("TOPLEFT", gh, "TOPLEFT", 0, -gh.gap)
            else
                gridPanel:SetPoint("TOPLEFT", prevGroupBottom, "BOTTOMLEFT", 0, firstGroup and -12 or -6)
            end
            gridPanel:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)

            local toggles = {}
            for _, entry in ipairs(BM.functions.GetEntriesForGroup(group.id)) do
                local row = ensureFrameRow(entry)
                local chk = GUI:CreateFormCheckbox(gridPanel, entry.label or entry.id, "enabled", row, function()
                    if BM.functions.RefreshEntry then
                        BM.functions.RefreshEntry(entry)
                    end
                end)
                toggles[#toggles + 1] = chk
            end

            local function ReflowGridPanel()
                ReflowToggleGrid(gridPanel, toggles)
            end
            gridReflowFns[#gridReflowFns + 1] = ReflowGridPanel
            gridPanel:SetScript("OnSizeChanged", ReflowGridPanel)

            prevGroupBottom = gridPanel
            firstGroup = false
        end

        -- Sub-tab content is often built while hidden → width 0; reflow after grids exist and when shown.
        local function ReflowAllGrids()
            for i = 1, #gridReflowFns do
                gridReflowFns[i]()
            end
        end

        tabContent:HookScript("OnShow", ReflowAllGrids)
        tabContent:HookScript("OnSizeChanged", ReflowAllGrids)
        C_Timer.After(0, ReflowAllGrids)
        C_Timer.After(0.05, ReflowAllGrids)
    else
        local pending = GUI:CreateLabel(tabContent, "Frame list loads after the addon finishes starting up. Reopen this tab if empty.", 11, C.textMuted)
        pending:SetPoint("TOPLEFT", PADDING, y)
        pending:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        pending:SetJustifyH("LEFT")
    end
end

ns.QUI_BlizzardMoverOptions = {
    BuildBlizzardMoverTab = BuildBlizzardMoverTab,
}
