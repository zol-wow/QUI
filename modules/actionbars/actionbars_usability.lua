local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

do

_abUsabilityStats = { activeScans = 0, fallbackScans = 0, buttons = 0 }
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AB_usabilityActiveScans", counter = true, fn = function() return _abUsabilityStats.activeScans end }
    mp[#mp + 1] = { name = "AB_usabilityFallbackScans", counter = true, fn = function() return _abUsabilityStats.fallbackScans end }
    mp[#mp + 1] = { name = "AB_usabilityButtons", counter = true, fn = function() return _abUsabilityStats.buttons end }
end

-- Get or create a QUI-owned tint overlay for range/usability coloring.
-- Uses MOD (multiplicative) blend on ARTWORK sublevel 1, so it renders
-- above the icon (sublevel 0) but below OVERLAY borders/gloss.
-- Hidden by default — no overlay = no tint.
function GetTintOverlay(button)
    local state = GetFrameState(button)
    if not state.tintOverlay then
        local icon = GetButtonIconTexture(button)
        if not icon then return nil end
        local overlay = button:CreateTexture(nil, "ARTWORK", nil, 1)
        overlay:SetAllPoints(icon)
        overlay:SetBlendMode("MOD")
        overlay:SetColorTexture(1, 1, 1, 1)  -- White = no tint
        overlay:Hide()
        state.tintOverlay = overlay
    end
    return state.tintOverlay
end

-- Update range and usability indicators for a single button.
-- Uses a QUI-owned overlay texture instead of modifying Blizzard's icon
-- directly, which avoids tainting secret values during combat.
function UpdateButtonUsability(button, settings)
    if not settings then return end
    local state = GetFrameState(button)
    local action = GetSafeActionSlot(button)

    -- Skip buttons that are effectively invisible (faded bar or hidden empty
    -- slot).  MOD-blend textures ignore parent alpha inheritance and will
    -- darken the scene behind them even when the button is at alpha 0.
    if state.fadeHidden or state.hiddenEmpty then
        return
    end

    if not action or not SafeHasAction(action) then
        if state.tinted then
            if state.tintOverlay then state.tintOverlay:Hide() end
            state.tinted = nil
        end
        return
    end

    -- Reset state if both features disabled
    if not settings.rangeIndicator and not settings.usabilityIndicator then
        if state.tinted then
            if state.tintOverlay then state.tintOverlay:Hide() end
            state.tinted = nil
        end
        return
    end

    -- Compute new tint state BEFORE applying visuals — skip overlay
    -- updates when state hasn't changed.
    local newTint = nil  -- nil = normal/no tint

    -- Priority 1: Out of Range check (if enabled)
    if settings.rangeIndicator then
        local inRange = SafeIsActionInRange(action)
        if inRange == false then  -- false = out of range, nil = no range check needed
            newTint = "range"
        end
    end

    -- Priority 2: Usability check (if enabled, and not already range-tinted)
    if not newTint and settings.usabilityIndicator then
        local isUsable, notEnoughMana = SafeIsUsableAction(action)
        if notEnoughMana then
            newTint = "mana"
        elseif not isUsable then
            newTint = "unusable"
        end
    end

    -- State-change gate: skip overlay work if tint state unchanged
    if state.tinted == newTint then return end

    -- Apply the new tint state
    if newTint == "range" then
        local overlay = GetTintOverlay(button)
        if overlay then
            local c = settings.rangeColor
            overlay:SetColorTexture(c and c[1] or 0.8, c and c[2] or 0.1, c and c[3] or 0.1, c and c[4] or 1)
            overlay:Show()
        end
        state.tinted = "range"
    elseif newTint == "mana" then
        local overlay = GetTintOverlay(button)
        if overlay then
            local c = settings.manaColor
            overlay:SetColorTexture(c and c[1] or 0.5, c and c[2] or 0.5, c and c[3] or 1.0, c and c[4] or 1)
            overlay:Show()
        end
        state.tinted = "mana"
    elseif newTint == "unusable" then
        local overlay = GetTintOverlay(button)
        if overlay then
            local c = settings.usabilityColor
            overlay:SetColorTexture(c and c[1] or 0.4, c and c[2] or 0.4, c and c[3] or 0.4, c and c[4] or 1)
            overlay:Show()
        end
        state.tinted = "unusable"
    else
        -- Normal state - hide overlay
        if state.tintOverlay then state.tintOverlay:Hide() end
        state.tinted = nil
    end
end

-- Update all visible action buttons
function UpdateAllButtonUsability()
    local globalSettings = GetGlobalSettings()
    if not globalSettings then return end
    if not globalSettings.rangeIndicator and not globalSettings.usabilityIndicator then return end
    usabilityState.lastScanTime = GetTime()

    local activeStandardButtons = ActionBarsOwned._activeStandardButtons
    if activeStandardButtons and next(activeStandardButtons) ~= nil then
        _abUsabilityStats.activeScans = _abUsabilityStats.activeScans + 1
        for button in pairs(activeStandardButtons) do
            local barKey = button._quiBarKey or GetBarKeyFromButton(button)
            local fadeState = ActionBarsOwned.fadeState and ActionBarsOwned.fadeState[barKey]
            if (not fadeState or fadeState.currentAlpha > 0)
                and (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(button, barKey))
                and (not button.IsVisible or button:IsVisible()) then
                _abUsabilityStats.buttons = _abUsabilityStats.buttons + 1
                UpdateButtonUsability(button, globalSettings)
            elseif IsButtonInsideVisibleLayout and not IsButtonInsideVisibleLayout(button, barKey) then
                ActionBarsOwned._activeButtons[button] = nil
                activeStandardButtons[button] = nil
            end
        end
        return
    end

    -- Fallback before the first visual pass has populated _activeButtons.
    _abUsabilityStats.fallbackScans = _abUsabilityStats.fallbackScans + 1
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local fadeState = ActionBarsOwned.fadeState and ActionBarsOwned.fadeState[barKey]
        if not fadeState or fadeState.currentAlpha > 0 then
            for _, button in ipairs(GetBarButtons(barKey)) do
                if (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(button, barKey))
                    and (not button.IsVisible or button:IsVisible()) then
                    _abUsabilityStats.buttons = _abUsabilityStats.buttons + 1
                    UpdateButtonUsability(button, globalSettings)
                end
            end
        end
    end
end

ActionBarsOwned.UpdateAllButtonUsability = UpdateAllButtonUsability

env.__declared.usabilityUpdateFrame = true
function GetUsabilityScheduleDelay()
    local delay = usabilityState.EVENT_DEBOUNCE
    if InCombatLockdown and InCombatLockdown() then
        local lastScanTime = usabilityState.lastScanTime or 0
        if lastScanTime > 0 then
            local remaining = usabilityState.INTERVAL_COMBAT - (GetTime() - lastScanTime)
            if remaining > delay then
                delay = remaining
            end
        end
    end
    return delay
end

function UsabilityUpdateFrameOnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + (elapsed or 0)
    if self.elapsed < (self.delay or usabilityState.EVENT_DEBOUNCE) then return end
    local nextDelay = GetUsabilityScheduleDelay()
    if nextDelay > usabilityState.EVENT_DEBOUNCE then
        self.elapsed = 0
        self.delay = nextDelay
        return
    end

    self.elapsed = 0
    self.delay = usabilityState.EVENT_DEBOUNCE
    usabilityState.updatePending = false
    self:Hide()
    UpdateAllButtonUsability()
end

function EnsureUsabilityUpdateFrame()
    if usabilityUpdateFrame then return usabilityUpdateFrame end

    usabilityUpdateFrame = CreateFrame("Frame")
    usabilityUpdateFrame.elapsed = 0
    usabilityUpdateFrame:Hide()
    usabilityUpdateFrame:SetScript("OnUpdate", UsabilityUpdateFrameOnUpdate)
    ActionBarsOwned._usabilityUpdateFrame = usabilityUpdateFrame
    return usabilityUpdateFrame
end

function UsabilityCheckFrameOnEvent(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        usabilityState.inCombat = true
        self.elapsed = 0
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        usabilityState.inCombat = false
        ScheduleUsabilityUpdate()
        return
    end
    ScheduleUsabilityUpdate()
end

function UsabilityCheckFrameOnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    local interval = usabilityState.inCombat and usabilityState.INTERVAL_COMBAT or usabilityState.INTERVAL_IDLE
    if self.elapsed < interval then return end
    self.elapsed = 0
    UpdateAllButtonUsability()
end

-- Debounced event handler (prevents rapid-fire updates)
ScheduleUsabilityUpdate = function()
    if usabilityState.rangePollingActive and InCombatLockdown and InCombatLockdown() then
        return
    end
    if usabilityState.updatePending then return end
    usabilityState.updatePending = true
    local frame = EnsureUsabilityUpdateFrame()
    frame.elapsed = 0
    frame.delay = GetUsabilityScheduleDelay()
    frame:Show()
end
ActionBarsOwned.ScheduleUsabilityUpdate = ScheduleUsabilityUpdate

-- Reset all button tints
function ResetAllButtonTints()
    for i = 1, 8 do
        local barKey = "bar" .. i
        local buttons = GetBarButtons(barKey)
        for _, button in ipairs(buttons) do
            local state = GetFrameState(button)
            if state.tinted then
                if state.tintOverlay then state.tintOverlay:Hide() end
                state.tinted = nil
            end
        end
    end
end

-- Start/stop usability indicator system (event-driven + optional range polling)
function UpdateUsabilityPolling()
    local settings = GetGlobalSettings()
    local usabilityEnabled = settings and settings.usabilityIndicator
    local rangeEnabled = settings and settings.rangeIndicator

    -- Create frame if needed
    if not usabilityState.checkFrame then
        usabilityState.checkFrame = CreateFrame("Frame")
        usabilityState.checkFrame.elapsed = 0
    end

    local checkFrame = usabilityState.checkFrame

    -- Event-driven usability updates (very efficient)
    -- ACTIONBAR_UPDATE_USABLE and SPELL_UPDATE_USABLE are handled by
    -- OnOwnedEvent → ScheduleUsabilityUpdate() directly, so they are
    -- NOT registered here (avoids double dispatch).
    if usabilityEnabled or rangeEnabled then
        checkFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        checkFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        checkFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        checkFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        checkFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        checkFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        checkFrame:RegisterEvent("ZONE_CHANGED_INDOORS")

        checkFrame:SetScript("OnEvent", UsabilityCheckFrameOnEvent)

        -- Initial update
        ScheduleUsabilityUpdate()
    else
        checkFrame:UnregisterAllEvents()
        checkFrame:SetScript("OnEvent", nil)
    end

    -- Range requires polling (no "player moved" event exists).
    -- PERF: Relaxed to 500ms combat / 2s OOC.  State-change gating in
    -- UpdateButtonUsability skips overlay work when tint is unchanged,
    -- so less frequent polling has no visible impact.
    if rangeEnabled then
        usabilityState.rangePollingActive = true
        checkFrame:SetScript("OnUpdate", UsabilityCheckFrameOnUpdate)
        checkFrame:Show()
    else
        usabilityState.rangePollingActive = false
        checkFrame:SetScript("OnUpdate", nil)
        checkFrame.elapsed = 0
        -- Don't hide - events still need to work if usability is enabled
        if not usabilityEnabled then
            checkFrame:Hide()
            ResetAllButtonTints()
        end
    end
end

ActionBarsOwned.UpdateUsabilityPolling = UpdateUsabilityPolling

end

---------------------------------------------------------------------------
-- BUTTON SPACING OVERRIDE
---------------------------------------------------------------------------

-- Detect how many columns a bar has by comparing button Y positions.
-- Buttons in the same row share a similar top edge; a new row drops down.
-- Fallback for bars without Edit Mode API (pet, stance).
function DetectBarColumns(buttons)
    if #buttons < 2 then return #buttons end

    local firstTop = buttons[1]:GetTop()
    if not firstTop then return #buttons end

    local buttonHeight = buttons[1]:GetHeight() or 30
    local threshold = buttonHeight * 0.3
    local numCols = 1

    for i = 2, #buttons do
        local top = buttons[i]:GetTop()
        if not top or math.abs(top - firstTop) > threshold then
            break
        end
        numCols = numCols + 1
    end

    return numCols
end

-- Read the bar's grid layout from the Edit Mode API.
-- Returns numCols, numRows, isVertical.
-- Falls back to position-based detection for bars without the API (pet, stance).
function GetBarGridLayout(barFrame, buttons)
    local isVertical = false
    local numCols, numRows

    local EditModeSettings = Enum.EditModeActionBarSetting
    if barFrame.GetSettingValue and EditModeSettings then
        local okO, orientation = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.Orientation)
        local okR, editNumRows = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumRows)

        if okO and okR and editNumRows and editNumRows > 0 then
            isVertical = (orientation == 1)
            if isVertical then
                -- Vertical: Blizzard's "NumRows" is the number of visual columns
                numCols = editNumRows
                numRows = math.ceil(#buttons / numCols)
            else
                -- Horizontal: NumRows is actual rows
                numRows = editNumRows
                numCols = math.ceil(#buttons / numRows)
            end
        end
    end

    -- Fallback for bars without Edit Mode API
    if not numCols then
        numCols = DetectBarColumns(buttons)
        numRows = math.ceil(#buttons / numCols)
    end

    return numCols, numRows, isVertical
end

-- Reposition action bar buttons with custom spacing override.
-- WoW 12.0 wraps each button in a per-button container managed by an internal
-- LayoutFrame. We reposition the containers (not the buttons) to override
-- Blizzard's layout, then resize the bar frame to exactly fit the group.
-- Supports both horizontal and vertical bar orientations via Edit Mode API.
function ApplyButtonSpacing(barKey)
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingSpacing = true
        return
    end

    local settings = GetGlobalSettings()
    if not settings or settings.buttonSpacing == nil then return end

    local spacing = settings.buttonSpacing
    -- Only apply spacing to standard action bars (1-8) that DON'T use the
    -- owned layout system. Owned bars use LayoutNativeButtons instead.
    -- Pet/stance bars have variable visible button counts per class
    -- and resizing their bar frames breaks the frame anchoring chain
    -- (size-stable CENTER anchoring shifts visual content on resize).
    if barKey == "pet" or barKey == "stance" then return end
    local ownedLayout = ActionBarsOwned.containers and ActionBarsOwned.containers[barKey]
    if ownedLayout then return end

    local allButtons = GetBarButtons(barKey)
    if #allButtons < 2 then return end

    local barFrame = GetBarFrame(barKey)
    if not barFrame then return end

    -- Sort ALL buttons by layoutIndex BEFORE taking the NumIcons subset.
    -- This ensures the correct buttons are selected when the user configures
    -- fewer than 12 visible icons in Edit Mode.
    do
        local needsSort = false
        for _, btn in ipairs(allButtons) do
            local container = btn:GetParent()
            if container and container.layoutIndex then
                needsSort = true
                break
            end
        end
        if needsSort then
            local sorted = {}
            for i, btn in ipairs(allButtons) do
                sorted[i] = btn
            end
            table.sort(sorted, function(a, b)
                local indexA = a:GetParent() and a:GetParent().layoutIndex
                local indexB = b:GetParent() and b:GetParent().layoutIndex
                if indexA and indexB and indexA ~= indexB then
                    return indexA < indexB
                end
                -- Tiebreaker: preserve name-based order
                local numA = tonumber(a:GetName():match("%d+$")) or 0
                local numB = tonumber(b:GetName():match("%d+$")) or 0
                return numA < numB
            end)
            allButtons = sorted
        end
    end

    -- Read the visible icon count from Edit Mode API.
    -- Users can configure bars to show fewer than 12 buttons (e.g. 9 of 12).
    -- We must only layout the visible subset, otherwise the bar frame is sized
    -- for invisible buttons and the layout breaks.
    local buttons = allButtons
    local editModeNumIcons = nil
    local EditModeSettings = Enum.EditModeActionBarSetting
    if barFrame.GetSettingValue and EditModeSettings then
        local okN, numIcons = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumIcons)
        if okN and numIcons and numIcons > 0 then
            editModeNumIcons = numIcons
            if numIcons < #allButtons then
                local visible = {}
                for i = 1, numIcons do
                    visible[i] = allButtons[i]
                end
                buttons = visible
            end
            -- When numIcons == #allButtons, trust the API — use all buttons.
            -- Do NOT fall through to the IsShown fallback, which would filter
            -- out buttons that Blizzard hasn't re-shown yet (e.g. after the
            -- user increases the button count in Edit Mode).
        end
    end

    -- Fallback: filter to only shown buttons when the Edit Mode API is NOT
    -- available (should not happen for bars 1-8, but guards pet/stance bars
    -- if they ever reach here).
    -- When ALL buttons are hidden (e.g. no pet summoned), skip the bar entirely.
    if not editModeNumIcons and #buttons == #allButtons then
        local shown = {}
        for _, btn in ipairs(allButtons) do
            if btn:IsShown() then
                shown[#shown + 1] = btn
            end
        end
        if #shown > 0 and #shown < #buttons then
            buttons = shown
        end
    end

    if #buttons < 2 then return end

    local numCols, numRows, isVertical = GetBarGridLayout(barFrame, buttons)

    -- Read Blizzard's layout direction flags.
    -- addButtonsToTop=true: rows stack bottom-to-top (button 1 at bottom row)
    -- addButtonsToRight=true: columns stack left-to-right (button 1 at left column)
    local addToTop = barFrame.addButtonsToTop
    local addToRight = barFrame.addButtonsToRight

    -- Effective scales for coordinate space conversion
    local containerEffScale = buttons[1]:GetParent():GetEffectiveScale()
    local barEffScale = barFrame:GetEffectiveScale()
    if not containerEffScale or containerEffScale <= 0 or not barEffScale or barEffScale <= 0 then return end

    -- Group dimensions in container coordinate space (buttons are scale 1.0 inside containers)
    local btnWidth = buttons[1]:GetWidth()
    local btnHeight = buttons[1]:GetHeight()
    local groupWidth = numCols * btnWidth + math.max(0, numCols - 1) * spacing
    local groupHeight = numRows * btnHeight + math.max(0, numRows - 1) * spacing

    -- Resize bar frame to exactly fit the button group.
    -- Convert from container coordinate space to bar frame coordinate space.
    -- We intentionally do NOT adjust anchor offsets to preserve the bar's center
    -- position — that offset manipulation was the root cause of cumulative drift.
    -- The bar resizes from whatever anchor point Edit Mode assigned it.
    barFrame:SetSize(
        groupWidth * containerEffScale / barEffScale,
        groupHeight * containerEffScale / barEffScale
    )

    -- Reposition the CONTAINERS (button parents) instead of the buttons themselves.
    -- Blizzard's LayoutFrame positions containers; button-level anchors don't
    -- override the visual layout because the container is what renders.
    -- Respect Blizzard's addButtonsToTop/addButtonsToRight flags so QUI's
    -- layout matches Edit Mode's visual order.
    local container1 = buttons[1]:GetParent()
    container1:ClearAllPoints()
    container1:SetSize(btnWidth, btnHeight)

    if isVertical then
        -- Vertical: buttons flow top-to-bottom, then wrap to the next column.
        -- addButtonsToRight controls column stacking direction.
        local buttonsPerCol = numRows
        if addToRight == false then
            -- Columns stack right-to-left: first column at right edge
            container1:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
        else
            -- Columns stack left-to-right (default): first column at left edge
            container1:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        end

        for i = 2, #buttons do
            local container = buttons[i]:GetParent()
            local rowInCol = (i - 1) % buttonsPerCol  -- 0 = first in new column

            container:ClearAllPoints()
            if rowInCol == 0 then
                -- First button in a new column
                local prevColStart = i - buttonsPerCol
                if addToRight == false then
                    container:SetPoint("TOPRIGHT", buttons[prevColStart]:GetParent(), "TOPLEFT", -spacing, 0)
                else
                    container:SetPoint("TOPLEFT", buttons[prevColStart]:GetParent(), "TOPRIGHT", spacing, 0)
                end
            else
                -- Same column: anchor below previous button
                container:SetPoint("TOPLEFT", buttons[i - 1]:GetParent(), "BOTTOMLEFT", 0, -spacing)
            end
            container:SetSize(btnWidth, btnHeight)
        end
    else
        -- Horizontal: buttons flow left-to-right, then wrap to the next row.
        -- addButtonsToTop controls row stacking direction.
        if addToTop then
            -- Rows stack bottom-to-top: first row at bottom edge
            container1:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        else
            -- Rows stack top-to-bottom (default): first row at top edge
            container1:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        end

        for i = 2, #buttons do
            local container = buttons[i]:GetParent()
            local colIndex = ((i - 1) % numCols) + 1

            container:ClearAllPoints()
            if colIndex == 1 then
                -- First container in a new row
                local prevRowStart = buttons[i - numCols]:GetParent()
                if addToTop then
                    -- New row goes ABOVE previous row
                    container:SetPoint("BOTTOMLEFT", prevRowStart, "TOPLEFT", 0, spacing)
                else
                    -- New row goes BELOW previous row
                    container:SetPoint("TOPLEFT", prevRowStart, "BOTTOMLEFT", 0, -spacing)
                end
            else
                -- Same row: anchor to the right of the previous container
                local prevContainer = buttons[i - 1]:GetParent()
                container:SetPoint("LEFT", prevContainer, "RIGHT", spacing, 0)
            end
            container:SetSize(btnWidth, btnHeight)
        end
    end

    -- Re-anchor each button to fill its container (undo any previous cross-hierarchy anchors)
    for i = 1, #buttons do
        buttons[i]:ClearAllPoints()
        buttons[i]:SetAllPoints(buttons[i]:GetParent())
    end
end

-- Apply spacing override to all standard bars.
ApplyAllBarSpacing = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingSpacing = true
        return
    end

    for barKey, _ in pairs(BUTTON_PATTERNS) do
        ApplyButtonSpacing(barKey)
    end
end

-- Apply the user's flyoutDirection setting to each button on a standard bar.
-- "AUTO" clears the attribute so Blizzard's position-based auto-detect runs.
-- Writing secure attributes on tainted addon buttons during combat causes
-- taint, so defer to PLAYER_REGEN_ENABLED when locked down.
VALID_FLYOUT_DIRS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

ApplyFlyoutDirection = function(barKey)
    local buttons = ActionBarsOwned.nativeButtons and ActionBarsOwned.nativeButtons[barKey]
    if not buttons or #buttons == 0 then return end

    local db = GetDB()
    local barDB = db and db.bars and db.bars[barKey]
    local layout = barDB and barDB.ownedLayout
    if not layout then return end

    if InCombatLockdown() then
        ActionBarsOwned.pendingFlyoutDirection = true
        return
    end

    if HideOwnedFlyout then
        HideOwnedFlyout()
    end

    local dir = layout.flyoutDirection
    if not VALID_FLYOUT_DIRS[dir] then dir = nil end -- AUTO / unset

    for _, btn in ipairs(buttons) do
        if btn and btn.SetAttribute then
            btn:SetAttribute("flyoutDirection", dir)
            -- Explicitly sync popup direction: UpdateFlyout only calls
            -- SetPopupDirection when the value is non-nil, so switching
            -- back to AUTO would leave the old direction stuck.
            if btn.SetPopupDirection then btn:SetPopupDirection(dir) end
            if btn.UpdateFlyout then pcall(btn.UpdateFlyout, btn) end
        end
    end
end

ApplyAllFlyoutDirections = function()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        ApplyFlyoutDirection(barKey)
    end
end

ActionBarsOwned.SuppressButtonProcVisuals = SuppressButtonProcVisuals
ActionBarsOwned.DRAG_PREVIEW_ALPHA = DRAG_PREVIEW_ALPHA


