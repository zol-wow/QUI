local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

local _abCooldownStats

local function RefreshAllEmptySlotVisibility()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local buttons = ActionBarsOwned.nativeButtons[barKey]
        local settings = GetEffectiveSettings(barKey)
        if buttons and settings then
            for _, btn in ipairs(buttons) do
                UpdateEmptySlotVisibility(btn, settings)
            end
        end
    end
end

local function RefreshAllFlyouts()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                ns.SafeCallMethodIfPresent("best-effort-style", btn, "UpdateFlyout")
            end
        end
    end
    ApplyAllFlyoutDirections()
    if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end
end

local function RefreshContextVisibilityFade()
    if RefreshActionBarContextVisibility then
        RefreshActionBarContextVisibility()
    end
    if _G.QUI_RefreshActionBarFade then
        _G.QUI_RefreshActionBarFade()
    end
end

AB_CD_UPDATE_INTERVAL_COMBAT = 0.033
AB_CD_UPDATE_INTERVAL_IDLE   = 0.20
AB_STATE_UPDATE_INTERVAL     = 0.033
AB_VIS_UPDATE_INTERVAL       = 0.033

abUpdateFrame = CreateFrame("Frame")
abUpdateFrame:Hide()
abUpdateFrame._lastCd = 0
abUpdateFrame._lastState = 0
abUpdateFrame._lastVis = 0
abUpdateFrame._dirtyCooldowns = false
abUpdateFrame._dirtyStates = false
abUpdateFrame._dirtyVisuals = false
abUpdateFrame._dirtyCounts = false
abUpdateFrame._immediate = false
abUpdateFrame:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local inCombat = InCombatLockdown()
    local throttle = inCombat and not self._immediate
    local cdInterval = inCombat and AB_CD_UPDATE_INTERVAL_COMBAT or AB_CD_UPDATE_INTERVAL_IDLE
    self._immediate = false

    local doVis = self._dirtyVisuals
    local doState = self._dirtyStates
    local doCd  = self._dirtyCooldowns
    local doCount = self._dirtyCounts

    if doVis then
        if throttle and (now - self._lastVis < AB_VIS_UPDATE_INTERVAL) then return end
        self:Hide()
        self._lastVis = now
        self._lastCd = now
        self._lastState = now
        self._dirtyCooldowns = false
        self._dirtyStates = false
        self._dirtyVisuals = false
        self._dirtyCounts = false
        ActionBarsOwned.UpdateAllButtonVisuals()
    elseif doState then
        if throttle and (now - self._lastState < AB_STATE_UPDATE_INTERVAL) then return end
        self:Hide()
        self._lastState = now
        self._dirtyStates = false
        ActionBarsOwned.UpdateAllButtonStates()
        if doCd then
            if now - self._lastCd >= cdInterval then
                self._lastCd = now
                self._dirtyCooldowns = false
                ActionBarsOwned.UpdateAllCooldowns()
            else
                self:Show()
            end
        end
        if doCount then
            self._dirtyCounts = false
            ActionBarsOwned.UpdateAllButtonCounts()
        end
    elseif doCd then
        if now - self._lastCd < cdInterval then return end
        self:Hide()
        self._lastCd = now
        self._dirtyCooldowns = false
        ActionBarsOwned.UpdateAllCooldowns()
        if doCount then
            self._dirtyCounts = false
            ActionBarsOwned.UpdateAllButtonCounts()
        end
    elseif doCount then
        self:Hide()
        self._dirtyCounts = false
        ActionBarsOwned.UpdateAllButtonCounts()
    else
        self:Hide()
    end
end)

ActionBarsOwned._perfProbesEnabled = false
if ns.QUI_ENABLE_ACTIONBAR_SPLIT_PERF_PROBES == true or _G.QUI_ENABLE_ACTIONBAR_SPLIT_PERF_PROBES == true then
    ActionBarsOwned._perfProbesEnabled = true
    local origAllCd    = ActionBarsOwned.UpdateAllCooldowns
    local origAllVis   = ActionBarsOwned.UpdateAllButtonVisuals
    local origAllState = ActionBarsOwned.UpdateAllButtonStates
    local cdProbeFrame    = CreateFrame("Frame")
    local visProbeFrame   = CreateFrame("Frame")
    local stateProbeFrame = CreateFrame("Frame")
    cdProbeFrame:SetScript("OnEvent",    function() origAllCd()    end)
    visProbeFrame:SetScript("OnEvent",   function() origAllVis()   end)
    stateProbeFrame:SetScript("OnEvent", function() origAllState() end)
    ActionBarsOwned.UpdateAllCooldowns     = function() cdProbeFrame:GetScript("OnEvent")()    end
    ActionBarsOwned.UpdateAllButtonVisuals = function() visProbeFrame:GetScript("OnEvent")()   end
    ActionBarsOwned.UpdateAllButtonStates  = function() stateProbeFrame:GetScript("OnEvent")() end
    local function SetupSplitPerfProbeRegistry()
        ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
        ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AB_Cooldowns", frame = cdProbeFrame,    scriptType = "OnEvent" }
        ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AB_States",    frame = stateProbeFrame, scriptType = "OnEvent" }
        ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AB_Visuals",   frame = visProbeFrame,   scriptType = "OnEvent" }
    end
    if ns.DebugRegister then
        ns.DebugRegister(SetupSplitPerfProbeRegistry)
    else
        SetupSplitPerfProbeRegistry()
    end
end

function ScheduleABCooldownUpdate(immediate)
    abUpdateFrame._dirtyCooldowns = true
    if immediate then abUpdateFrame._immediate = true end
    abUpdateFrame:Show()
end

function ScheduleABVisualUpdate(full, immediate)
    abUpdateFrame._dirtyVisuals = true
    if immediate then abUpdateFrame._immediate = true end
    if full then
        ActionBarsOwned.ForceFullVisualRescan()
    end
    abUpdateFrame:Show()
end

function ScheduleABStateUpdate(immediate)
    abUpdateFrame._dirtyStates = true
    if immediate then abUpdateFrame._immediate = true end
    abUpdateFrame:Show()
end

function ScheduleABCountUpdate()
    abUpdateFrame._dirtyCounts = true
    abUpdateFrame:Show()
end

abDirtySlots = {}
abSlotFrame = CreateFrame("Frame")
abSlotFrame:Hide()
_lastPagingTime = 0

abSlotFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    local slotMap = ActionBarsOwned.slotMap
    local inCombat = InCombatLockdown()
    for slot in pairs(abDirtySlots) do
        if slotMap then
            local entry = slotMap[slot]
            if entry then
                local btn, barKey = entry.button, entry.barKey
                if ResetButtonChargeCapabilityCache then
                    ResetButtonChargeCapabilityCache(btn)
                end
                ns.SafeCall("best-effort-style", ActionBarsOwned.SafeUpdate, btn)
                ActionBarsOwned.UpdateCooldown(btn)
                ActionBarsOwned.UpdateOverlayGlow(btn)
                if not inCombat then
                    local cont = ActionBarsOwned.containers and ActionBarsOwned.containers[barKey]
                    local refreshRef = btn.GetAttribute and btn:GetAttribute("qui-refresh-ref")
                    if cont and refreshRef then
                        cont:SetAttribute("qui-refresh-target", refreshRef)
                        cont:SetAttribute("qui-refresh-target", nil)
                    end
                end
                if not inCombat then
                    local settings = GetEffectiveSettings(barKey)
                    if settings then
                        local st = GetFrameState(btn)
                        st.sk_sz = nil
                        SkinButton(btn, settings)
                        UpdateButtonText(btn, settings)
                        UpdateEmptySlotVisibility(btn, settings)
                    end
                end
            end
        end
    end
    wipe(abDirtySlots)
    if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
    if SyncOwnedFlyoutInfoToHandler then
        SyncOwnedFlyoutInfoToHandler()
    end
    _assistRotationButton = nil
    UpdateAllAssistedHighlights()
    ActionBarsOwned.UpdateAllAssistedCombatRotation()
end)

function ScheduleSlotUpdate(slot)
    if not slot or slot < 1 then return end
    if GetTime() - _lastPagingTime < 0.5 then
        ScheduleABVisualUpdate(false, true)
        return
    end
    abDirtySlots[slot] = true
    abSlotFrame:Show()
end

function OnOwnedEvent(self, event, ...)
    if not ActionBarsOwned.initialized then return end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        local slot = ...
        ScheduleSlotUpdate(slot)

    elseif event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "UPDATE_SHAPESHIFT_FORMS"
        or event == "UPDATE_STEALTH" then
        _lastPagingTime = GetTime()
        _assistRotationButton = nil
        if HideOwnedFlyout then
            HideOwnedFlyout()
        end
        local buttons = ActionBarsOwned.nativeButtons["bar1"]
        local slotMap = ActionBarsOwned.slotMap
        if slotMap then
            for slot, entry in pairs(slotMap) do
                if entry.barKey == "bar1" then
                    slotMap[slot] = nil
                end
            end
            if buttons then
                for _, btn in ipairs(buttons) do
                    local action = btn.action
                    if action and action > 0 then
                        slotMap[action] = { button = btn, barKey = "bar1" }
                        if ResetButtonChargeCapabilityCache then
                            ResetButtonChargeCapabilityCache(btn)
                        end
                    end
                end
            end
        end
        local settings = GetEffectiveSettings("bar1")
        if buttons and settings then
            for _, btn in ipairs(buttons) do
                UpdateEmptySlotVisibility(btn, settings)
            end
        end
        if buttons then
            for _, btn in ipairs(buttons) do
                ActionBarsOwned.UpdateCooldown(btn)
                ActionBarsOwned.UpdateOverlayGlow(btn)
            end
        end
        ScheduleABVisualUpdate(false, true)
        if not InCombatLockdown() then
            UpdateStanceBarLayout()
        else
            ActionBarsOwned.pendingStanceUpdate = true
        end
        ApplyBar1OverrideBindings()

    elseif event == "UPDATE_SHAPESHIFT_COOLDOWN" or event == "UPDATE_SHAPESHIFT_USABLE" then
        ActionBarsOwned.UpdateAllStanceButtons()

    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit == "player" then
            ApplyBar1OverrideBindings()
            if event == "UNIT_EXITED_VEHICLE" then
                C_Timer.After(0.2, function()
                    if not ActionBarsOwned.initialized then return end
                    if InCombatLockdown() then
                        ActionBarsOwned.pendingMicroReclaim = true
                        ActionBarsOwned.pendingBagsReclaim = true
                        return
                    end
                    ReclaimBarButtons("microbar")
                    ReclaimBarButtons("bags")
                end)
            end
        end

    elseif event == "UPDATE_BINDINGS" or event == "GAME_PAD_ACTIVE_CHANGED" then
        C_Timer.After(0.1, RefreshNativeKeybinds)

    elseif event == "CURSOR_CHANGED" then
        local settings = GetGlobalSettings()
        if settings and settings.hideEmptySlots then
            local shouldPreview = CursorHasPlaceableAction()
            if shouldPreview ~= (ActionBarsOwned.dragPreviewActive or false) then
                ActionBarsOwned.dragPreviewActive = shouldPreview or nil
                RefreshAllEmptySlotVisibility()
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        ScheduleABVisualUpdate(false, true)
        FinishBlockedOverrideBarExit()
        if ActionBarsOwned.pendingExtraButtonInit then
            ActionBarsOwned.pendingExtraButtonInit = false
            InitializeExtraButtons()
        end
        if ActionBarsOwned.pendingExtraButtonRefresh then
            ActionBarsOwned.pendingExtraButtonRefresh = false
            RefreshExtraButtons()
        end
        if ActionBarsOwned.pendingRefresh then
            ActionBarsOwned.pendingRefresh = false
            ActionBarsOwned:Refresh()
        end
        if ActionBarsOwned.pendingUseOnKeyDownUpdate then
            ActionBarsOwned.pendingUseOnKeyDownUpdate = false
            if _G.QUI_ApplyUseOnKeyDown then _G.QUI_ApplyUseOnKeyDown() end
        end
        if ActionBarsOwned.pendingBindings then
            ActionBarsOwned.pendingBindings = false
            ApplyAllOverrideBindings()
        end
        if ActionBarsOwned.pendingPetUpdate then
            ActionBarsOwned.pendingPetUpdate = false
            UpdatePetBarVisibility()
        end
        if ActionBarsOwned.pendingStanceUpdate then
            ActionBarsOwned.pendingStanceUpdate = false
            UpdateStanceBarLayout()
        end
        if ActionBarsOwned.pendingMicroReclaim then
            ActionBarsOwned.pendingMicroReclaim = false
            ReclaimBarButtons("microbar")
        end
        if ActionBarsOwned.pendingBagsReclaim then
            ActionBarsOwned.pendingBagsReclaim = false
            ReclaimBarButtons("bags")
        end
        if ActionBarsOwned.pendingSpacing then
            ActionBarsOwned.pendingSpacing = false
            ApplyAllBarSpacing()
        end
        if ActionBarsOwned.pendingFlyoutDirection then
            ActionBarsOwned.pendingFlyoutDirection = false
            if ApplyAllFlyoutDirections then ApplyAllFlyoutDirections() end
        end
        if ActionBarsOwned.pendingFlyoutSkin then
            ActionBarsOwned.pendingFlyoutSkin = false
            if SkinSpellFlyoutButtons then SkinSpellFlyoutButtons() end
        end
        if ActionBarsOwned.pendingOwnedFlyoutSync then
            ActionBarsOwned.pendingOwnedFlyoutSync = false
            if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end
        end

    elseif event == "PET_BAR_UPDATE" or event == "PET_BAR_UPDATE_COOLDOWN" then
        ActionBarsOwned.UpdateAllPetButtons()
        UpdatePetBarVisibility()

    elseif event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        local unit = ...
        if event == "UNIT_PET" and unit ~= "player" then return end
        C_Timer.After(0.1, function()
            if not ActionBarsOwned.initialized then return end
            UpdatePetBarVisibility()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        inInitSafeWindow = true
        ns._inInitSafeWindow = true
        if isReload then
            ApplyAllBarSpacing()
            ActionBarsOwned.pendingSpacing = true
        end
        if ns.QUI_Anchoring and ns.QUI_Anchoring.ApplyAllFrameAnchors then
            ns.QUI_Anchoring:ApplyAllFrameAnchors(true)
        end
        for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
            LayoutNativeButtons(barKey)
            RestoreContainerPosition(barKey)
        end
        RefreshAllNativeVisuals()
        ActionBarsOwned.UpdateAllButtonVisuals()
        ActionBarsOwned.UpdateAllCooldowns()
        UpdatePetBarVisibility()
        UpdateStanceBarLayout()
        ApplyAllFlyoutDirections()
        if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end
        RefreshContextVisibilityFade()
        inInitSafeWindow = false
        ns._inInitSafeWindow = false
        C_Timer.After(0.2, function()
            if InCombatLockdown() then
                ActionBarsOwned.pendingRefresh = true
                ActionBarsOwned.pendingPetUpdate = true
                ActionBarsOwned.pendingStanceUpdate = true
                return
            end
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                LayoutNativeButtons(barKey)
                RestoreContainerPosition(barKey)
            end
            RefreshAllNativeVisuals()
            ActionBarsOwned.ForceFullVisualRescan()
            ActionBarsOwned.UpdateAllButtonVisuals()
            ActionBarsOwned.UpdateAllCooldowns()
            UpdatePetBarVisibility()
            UpdateStanceBarLayout()
            ApplyAllFlyoutDirections()
            if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end
            RefreshContextVisibilityFade()
        end)
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            C_Timer.After(0.1, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
            C_Timer.After(0.6, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        local fadeSettings = GetFadeSettings()
        if fadeSettings and fadeSettings.enabled and fadeSettings.alwaysShowInCombat then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local state = GetOwnedBarFadeState(barKey)
                CancelOwnedBarFadeTimers(state)
                StartOwnedBarFade(barKey, 1)
            end
        end

    elseif event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
        or event == "PLAYER_DIFFICULTY_CHANGED"
        or event == "UPDATE_INSTANCE_INFO"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET" then
        RefreshContextVisibilityFade()

    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName, difficultyID = ...
        if SetActionBarEncounterVisibilityContext then
            SetActionBarEncounterVisibilityContext(encounterID, encounterName, difficultyID)
        end
        RefreshContextVisibilityFade()

    elseif event == "ENCOUNTER_END" then
        local encounterID = ...
        if ClearActionBarEncounterVisibilityContext then
            ClearActionBarEncounterVisibilityContext(encounterID)
        end
        RefreshContextVisibilityFade()

    elseif event == "PLAYER_LEVEL_UP" then
        if UpdateLevelSuppressionState() then
            if type(_G.QUI_RefreshActionBars) == "function" then
                _G.QUI_RefreshActionBars()
            end
        end

    elseif event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE" then
        if _abCooldownStats then _abCooldownStats.events = _abCooldownStats.events + 1 end
        ScheduleABCooldownUpdate()

    elseif event == "SPELL_UPDATE_COOLDOWN"
        or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if _abCooldownStats then _abCooldownStats.events = _abCooldownStats.events + 1 end
        if FlushCooldownTimingCaches then
            FlushCooldownTimingCaches()
        end
        ScheduleABCooldownUpdate()

    elseif event == "ACTIONBAR_UPDATE_STATE" then
        ScheduleABStateUpdate()

    elseif event == "SPELL_UPDATE_ICON" then
        ScheduleABVisualUpdate(false, true)

    elseif event == "MODIFIER_STATE_CHANGED" then
        ScheduleABVisualUpdate(false, true)

    elseif event == "ACTIONBAR_UPDATE_USABLE" then
        ScheduleUsabilityUpdate()

    elseif event == "SPELL_UPDATE_CHARGES" then
        if FlushChargeCapabilityVerdicts then
            FlushChargeCapabilityVerdicts()
        end
        ScheduleABCountUpdate()
        ScheduleABCooldownUpdate()

    elseif event == "UNIT_AURA" then
        ScheduleABCountUpdate()

    elseif event == "ACTIONBAR_SHOWGRID" then
        ActionBarsOwned._showGrid = true
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    btn:SetAlpha(1)
                end
            end
        end

    elseif event == "ACTIONBAR_HIDEGRID" then
        ActionBarsOwned._showGrid = nil
        ScheduleABVisualUpdate(true)
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllAssistedCombatRotation()
        UpdateAllAssistedHighlights()
        RefreshAllEmptySlotVisibility()
        if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
        if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end

    elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
        ScheduleABVisualUpdate(false, true)

    elseif event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
        ScheduleABVisualUpdate(false, true)

    elseif event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        ScheduleABVisualUpdate(true)
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllOverlayGlows()
        RefreshAllFlyouts()
        RefreshAllEmptySlotVisibility()
        RefreshExtraButtons()

    elseif event == "SPELL_FLYOUT_UPDATE" then
        RefreshAllFlyouts()

    elseif event == "SPELL_UPDATE_USABLE" then
        ScheduleUsabilityUpdate()

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellId = ...
        ActionBarsOwned.OnSpellActivationGlowShow(spellId)

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellId = ...
        ActionBarsOwned.OnSpellActivationGlowHide(spellId)

    elseif event == "UPDATE_VEHICLE_ACTIONBAR" then
        ScheduleABVisualUpdate(true)
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllOverlayGlows()
        ApplyBar1OverrideBindings()

    elseif event == "UPDATE_EXTRA_ACTIONBAR" then
        RefreshExtraButtons()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            ScheduleABVisualUpdate(true)
            ScheduleABCooldownUpdate()
        end

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        ScheduleABVisualUpdate()

    elseif event == "PET_BATTLE_OPENING_START" then
        if not InCombatLockdown() then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local cont = ActionBarsOwned.containers[barKey]
                if cont then
                    ClearOverrideBindings(cont)
                    cont:Hide()
                end
            end
        end

    elseif event == "PET_BATTLE_CLOSE" then
        if not InCombatLockdown() then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local cont = ActionBarsOwned.containers[barKey]
                if cont then cont:Show() end
            end
            ApplyAllOverrideBindings()
            UpdatePetBarVisibility()
            UpdateStanceBarLayout()
        else
            ActionBarsOwned.pendingBindings = true
            ActionBarsOwned.pendingRefresh = true
        end
    end
end

ownedEventFrame:SetScript("OnEvent", OnOwnedEvent)

local function SetupDebugInstrumentation()
    _abCooldownStats = _G._abCooldownStats
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "ActionBars", frame = ownedEventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
