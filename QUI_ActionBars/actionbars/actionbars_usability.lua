local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

do

local _abUsabilityStats
local function SetupDebugInstrumentation()
    _abUsabilityStats = { activeScans = 0, fallbackScans = 0, buttons = 0 }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AB_usabilityActiveScans", counter = true, fn = function() return _abUsabilityStats.activeScans end }
    mp[#mp + 1] = { name = "AB_usabilityFallbackScans", counter = true, fn = function() return _abUsabilityStats.fallbackScans end }
    mp[#mp + 1] = { name = "AB_usabilityButtons", counter = true, fn = function() return _abUsabilityStats.buttons end }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function ClearButtonTint(state)
    if state.tintOverlay then state.tintOverlay:Hide() end
    state.tinted = nil
    state._fhTint = nil
    state._fadeTint = nil
end

function GetTintOverlay(button)
    local state = GetFrameState(button)
    if not state.tintOverlay then
        local icon = GetButtonIconTexture(button)
        if not icon then return nil end
        local overlay = button:CreateTexture(nil, "ARTWORK", nil, 1)
        overlay:SetAllPoints(icon)
        overlay:SetBlendMode("MOD")
        overlay:SetColorTexture(1, 1, 1, 1)
        overlay:Hide()
        state.tintOverlay = overlay
    end
    return state.tintOverlay
end

function UpdateButtonUsability(button, settings, inRange, rangeKnown)
    if not settings then return end
    local state = GetFrameState(button)
    local action = GetSafeActionSlot(button)

    if not action or not SafeHasAction(action) then
        ClearButtonTint(state)
        return
    end

    if state.hiddenEmpty then
        return
    end

    if not settings.rangeIndicator and not settings.usabilityIndicator then
        ClearButtonTint(state)
        return
    end

    local newTint = nil

    if settings.rangeIndicator then
        local rangeState
        if rangeKnown then
            rangeState = inRange
        else
            rangeState = SafeIsActionInRange(action)
        end
        if rangeState == false then
            newTint = "range"
        end
    end

    if not newTint and settings.usabilityIndicator then
        local isUsable, notEnoughMana = SafeIsUsableAction(action)
        if notEnoughMana then
            newTint = "mana"
        elseif not isUsable then
            newTint = "unusable"
        end
    end

    if not newTint then
        ClearButtonTint(state)
        return
    end
    if state.tinted == newTint then return end

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
    end
end

function UpdateAllButtonUsability()
    local globalSettings = GetGlobalSettings()
    if not globalSettings then return end
    if not globalSettings.rangeIndicator and not globalSettings.usabilityIndicator then return end
    usabilityState.lastScanTime = GetTime()

    local activeStandardButtons = ActionBarsOwned._activeStandardButtons
    if activeStandardButtons and next(activeStandardButtons) ~= nil then
        if _abUsabilityStats then _abUsabilityStats.activeScans = _abUsabilityStats.activeScans + 1 end
        for button in pairs(activeStandardButtons) do
            local barKey = button._quiBarKey or GetBarKeyFromButton(button)
            local fadeState = ActionBarsOwned.fadeState and ActionBarsOwned.fadeState[barKey]
            if (not fadeState or fadeState.currentAlpha > 0)
                and (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(button, barKey))
                and (not button.IsVisible or button:IsVisible()) then
                if _abUsabilityStats then _abUsabilityStats.buttons = _abUsabilityStats.buttons + 1 end
                UpdateButtonUsability(button, globalSettings)
            elseif IsButtonInsideVisibleLayout and not IsButtonInsideVisibleLayout(button, barKey) then
                ActionBarsOwned._activeButtons[button] = nil
                activeStandardButtons[button] = nil
            end
        end
        return
    end

    if _abUsabilityStats then _abUsabilityStats.fallbackScans = _abUsabilityStats.fallbackScans + 1 end
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local fadeState = ActionBarsOwned.fadeState and ActionBarsOwned.fadeState[barKey]
        if not fadeState or fadeState.currentAlpha > 0 then
            for _, button in ipairs(GetBarButtons(barKey)) do
                if (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(button, barKey))
                    and (not button.IsVisible or button:IsVisible()) then
                    if _abUsabilityStats then _abUsabilityStats.buttons = _abUsabilityStats.buttons + 1 end
                    UpdateButtonUsability(button, globalSettings)
                end
            end
        end
    end
end

ActionBarsOwned.UpdateAllButtonUsability = UpdateAllButtonUsability

function RefreshUsabilityButtons()
    local settings = GetGlobalSettings()
    local enabled = settings and (settings.rangeIndicator or settings.usabilityIndicator)
    local buttonsBySlot = usabilityState.buttonsBySlot
    local buttonsBySlotPool = usabilityState.buttonsBySlotPool
    for _, buttons in pairs(buttonsBySlot) do
        wipe(buttons)
        buttonsBySlotPool[#buttonsBySlotPool + 1] = buttons
    end
    wipe(buttonsBySlot)

    if enabled then
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local barButtons = ActionBarsOwned.nativeButtons[barKey]
            if barButtons then
                for _, button in ipairs(barButtons) do
                    UpdateButtonUsability(button, settings)
                    if (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(button, barKey))
                        and (not button.IsVisible or button:IsVisible()) then
                        local action = GetSafeActionSlot(button)
                        if action and SafeHasAction(action) then
                            local buttons = buttonsBySlot[action]
                            if not buttons then
                                local poolIndex = #buttonsBySlotPool
                                buttons = buttonsBySlotPool[poolIndex] or {}
                                buttonsBySlotPool[poolIndex] = nil
                                buttonsBySlot[action] = buttons
                            end
                            buttons[button] = true
                        end
                    end
                end
            end
        end
    end

    local rangeSlots = usabilityState.rangeSlots
    local enableRangeCheck = C_ActionBar and C_ActionBar.EnableActionRangeCheck

    if type(enableRangeCheck) == "function" then
        for slot in pairs(rangeSlots) do
            if not settings or not settings.rangeIndicator or not buttonsBySlot[slot] then
                local ok = ns.SafeCall("best-effort-style", enableRangeCheck, slot, false)
                if ok then rangeSlots[slot] = nil end
            end
        end
        if settings and settings.rangeIndicator then
            for slot in pairs(buttonsBySlot) do
                if not rangeSlots[slot] then
                    local ok = ns.SafeCall("best-effort-style", enableRangeCheck, slot, true)
                    if ok then rangeSlots[slot] = true end
                end
            end
        end
    end
end

ActionBarsOwned.RefreshUsabilityButtons = RefreshUsabilityButtons

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
    if event == "ACTION_RANGE_CHECK_UPDATE" then
        local slot, inRange, checksRange = ...
        local settings = GetGlobalSettings()
        local buttons = usabilityState.buttonsBySlot and usabilityState.buttonsBySlot[slot]
        if settings and settings.rangeIndicator and buttons then
            local rangeState
            if checksRange then rangeState = inRange end
            for button in pairs(buttons) do
                UpdateButtonUsability(button, settings, rangeState, true)
            end
        end
        return
    elseif event == "ACTION_USABLE_CHANGED" then
        local changes = ...
        local settings = GetGlobalSettings()
        if settings and settings.usabilityIndicator and type(changes) == "table" then
            for _, change in ipairs(changes) do
                local buttons = change.slot and usabilityState.buttonsBySlot
                    and usabilityState.buttonsBySlot[change.slot]
                if buttons then
                    for button in pairs(buttons) do
                        UpdateButtonUsability(button, settings)
                    end
                end
            end
        end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
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

function ResetAllButtonTints()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local buttons = GetBarButtons(barKey)
        for _, button in ipairs(buttons) do
            local state = GetFrameState(button)
            ClearButtonTint(state)
        end
    end
end

function UpdateUsabilityPolling()
    local settings = GetGlobalSettings()
    local usabilityEnabled = settings and settings.usabilityIndicator
    local rangeEnabled = settings and settings.rangeIndicator

    if not usabilityState.checkFrame then
        usabilityState.checkFrame = CreateFrame("Frame")
        usabilityState.checkFrame.elapsed = 0
    end

    local checkFrame = usabilityState.checkFrame

    if usabilityEnabled or rangeEnabled then
        checkFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        checkFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        checkFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        checkFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        checkFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        checkFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        checkFrame:RegisterEvent("ZONE_CHANGED_INDOORS")

        if rangeEnabled then
            checkFrame:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
        else
            checkFrame:UnregisterEvent("ACTION_RANGE_CHECK_UPDATE")
        end
        if usabilityEnabled then
            checkFrame:RegisterEvent("ACTION_USABLE_CHANGED")
        else
            checkFrame:UnregisterEvent("ACTION_USABLE_CHANGED")
        end

        checkFrame:SetScript("OnEvent", UsabilityCheckFrameOnEvent)

        RefreshUsabilityButtons()
    else
        checkFrame:UnregisterAllEvents()
        checkFrame:SetScript("OnEvent", nil)
        RefreshUsabilityButtons()
    end

    if rangeEnabled then
        usabilityState.rangePollingActive = true
        checkFrame:SetScript("OnUpdate", UsabilityCheckFrameOnUpdate)
        checkFrame:Show()
    else
        usabilityState.rangePollingActive = false
        checkFrame:SetScript("OnUpdate", nil)
        checkFrame.elapsed = 0
        if not usabilityEnabled then
            checkFrame:Hide()
            ResetAllButtonTints()
        end
    end
end

ActionBarsOwned.UpdateUsabilityPolling = UpdateUsabilityPolling

end

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
                numCols = editNumRows
                numRows = math.ceil(#buttons / numCols)
            else
                numRows = editNumRows
                numCols = math.ceil(#buttons / numRows)
            end
        end
    end

    if not numCols then
        numCols = DetectBarColumns(buttons)
        numRows = math.ceil(#buttons / numCols)
    end

    return numCols, numRows, isVertical
end

function ApplyButtonSpacing(barKey)
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingSpacing = true
        return
    end

    local settings = GetGlobalSettings()
    if not settings or settings.buttonSpacing == nil then return end

    local spacing = settings.buttonSpacing
    if barKey == "pet" or barKey == "stance" then return end
    local ownedLayout = ActionBarsOwned.containers and ActionBarsOwned.containers[barKey]
    if ownedLayout then return end

    local allButtons = GetBarButtons(barKey)
    if #allButtons < 2 then return end

    local barFrame = GetBarFrame(barKey)
    if not barFrame then return end

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
                local numA = tonumber(a:GetName():match("%d+$")) or 0
                local numB = tonumber(b:GetName():match("%d+$")) or 0
                return numA < numB
            end)
            allButtons = sorted
        end
    end

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
        end
    end

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

    local addToTop = barFrame.addButtonsToTop
    local addToRight = barFrame.addButtonsToRight

    local containerEffScale = buttons[1]:GetParent():GetEffectiveScale()
    local barEffScale = barFrame:GetEffectiveScale()
    if not containerEffScale or containerEffScale <= 0 or not barEffScale or barEffScale <= 0 then return end

    local btnWidth = buttons[1]:GetWidth()
    local btnHeight = buttons[1]:GetHeight()
    local groupWidth = numCols * btnWidth + math.max(0, numCols - 1) * spacing
    local groupHeight = numRows * btnHeight + math.max(0, numRows - 1) * spacing

    barFrame:SetSize(
        groupWidth * containerEffScale / barEffScale,
        groupHeight * containerEffScale / barEffScale
    )

    local container1 = buttons[1]:GetParent()
    container1:ClearAllPoints()
    container1:SetSize(btnWidth, btnHeight)

    if isVertical then
        local buttonsPerCol = numRows
        if addToRight == false then
            container1:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
        else
            container1:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        end

        for i = 2, #buttons do
            local container = buttons[i]:GetParent()
            local rowInCol = (i - 1) % buttonsPerCol

            container:ClearAllPoints()
            if rowInCol == 0 then
                local prevColStart = i - buttonsPerCol
                if addToRight == false then
                    container:SetPoint("TOPRIGHT", buttons[prevColStart]:GetParent(), "TOPLEFT", -spacing, 0)
                else
                    container:SetPoint("TOPLEFT", buttons[prevColStart]:GetParent(), "TOPRIGHT", spacing, 0)
                end
            else
                container:SetPoint("TOPLEFT", buttons[i - 1]:GetParent(), "BOTTOMLEFT", 0, -spacing)
            end
            container:SetSize(btnWidth, btnHeight)
        end
    else
        if addToTop then
            container1:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        else
            container1:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        end

        for i = 2, #buttons do
            local container = buttons[i]:GetParent()
            local colIndex = ((i - 1) % numCols) + 1

            container:ClearAllPoints()
            if colIndex == 1 then
                local prevRowStart = buttons[i - numCols]:GetParent()
                if addToTop then
                    container:SetPoint("BOTTOMLEFT", prevRowStart, "TOPLEFT", 0, spacing)
                else
                    container:SetPoint("TOPLEFT", prevRowStart, "BOTTOMLEFT", 0, -spacing)
                end
            else
                local prevContainer = buttons[i - 1]:GetParent()
                container:SetPoint("LEFT", prevContainer, "RIGHT", spacing, 0)
            end
            container:SetSize(btnWidth, btnHeight)
        end
    end

    for i = 1, #buttons do
        buttons[i]:ClearAllPoints()
        buttons[i]:SetAllPoints(buttons[i]:GetParent())
    end
end

ApplyAllBarSpacing = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingSpacing = true
        return
    end

    for barKey, _ in pairs(BUTTON_PATTERNS) do
        ApplyButtonSpacing(barKey)
    end
end

ComputeAutoFlyoutDirection = function(btn, isVertical)
    local rawX, rawY = btn:GetCenter()
    local cx = Helpers.SafeNumberOrNil(rawX)
    local cy = Helpers.SafeNumberOrNil(rawY)
    if isVertical then
        if cx then return cx > (GetScreenWidth() / 2) and "LEFT" or "RIGHT" end
        return "RIGHT"
    end
    if cy then return cy < (GetScreenHeight() / 2) and "UP" or "DOWN" end
    return "UP"
end

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
    if not VALID_FLYOUT_DIRS[dir] then dir = nil end
    local isVertical = (GetOwnedLayout(barKey)) == "vertical"

    for _, btn in ipairs(buttons) do
        if btn and btn.SetAttribute then
            local effectiveDir = dir or ComputeAutoFlyoutDirection(btn, isVertical)
            btn:SetAttribute("flyoutDirection", effectiveDir)
            if btn.SetPopupDirection then btn:SetPopupDirection(effectiveDir) end
            ns.SafeCallMethodIfPresent("best-effort-style", btn, "UpdateFlyout")
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
