local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

-- Local alias for _abCooldownStats (defined as a GLOBAL by actionbars_cooldowns.lua).
-- Assigned in SetupDebugInstrumentation at the bottom of this file; nil until QUI_Debug
-- activates instrumentation (debug gate).
local _abCooldownStats

-- Re-apply empty-slot visibility across every standard bar using each bar's
-- effective settings. Shared by the page-change / window-update / spell-change
-- event branches, which each ran this identical per-bar loop.
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

-- Refresh flyout arrows on every standard bar button, then re-apply flyout
-- directions and resync flyout info to the secure handler. Shared by the
-- SPELLS_CHANGED and SPELL_FLYOUT_UPDATE branches.
local function RefreshAllFlyouts()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                if btn.UpdateFlyout then pcall(btn.UpdateFlyout, btn) end
            end
        end
    end
    ApplyAllFlyoutDirections()
    if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end
end

---------------------------------------------------------------------------
-- EVENT COALESCING (elapsed-time gated Show/Hide)
---------------------------------------------------------------------------
-- Events activate the frame via Show().  OnUpdate checks elapsed time
-- and only runs the update after a minimum interval.  Multiple events
-- in the same frame are coalesced (Show on shown = no-op).  If the
-- interval hasn't elapsed, the frame stays shown and retries next frame.
-- Zero closure allocation.
--
-- Out of combat visual/state updates flush immediately (next frame) for
-- zero-latency visual changes. Cooldown-only updates are coalesced lightly
-- out of combat to reduce short-lived allocation churn from C_ActionBar
-- structured queries. In combat, high-frequency events
-- (ACTIONBAR_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_STATE) are coalesced behind
-- these interval gates (~30Hz).
-- Low-frequency events (SPELL_UPDATE_ICON, PLAYER_ENTER/LEAVE_COMBAT) set the
-- _immediate flag to bypass the combat throttle for that tick.
AB_CD_UPDATE_INTERVAL_COMBAT = 0.033  -- 33ms in-combat cooldown gate (~30Hz)
AB_CD_UPDATE_INTERVAL_IDLE   = 0.20   -- 200ms out-of-combat cooldown gate
AB_STATE_UPDATE_INTERVAL     = 0.033  -- 33ms in-combat checked-state gate
AB_VIS_UPDATE_INTERVAL       = 0.033  -- 33ms in-combat visual gate

-- Unified update frame: merges cooldown, state and visual update into a
-- single OnUpdate handler with dirty flags. When visuals are dirty,
-- SafeUpdate already covers checked state + cooldown internally, so those
-- flags are subsumed. When only state is dirty (common in combat from
-- ACTIONBAR_UPDATE_STATE), a lean per-button SetChecked pass runs instead
-- of the 20-API-call SafeUpdate chain.
abUpdateFrame = CreateFrame("Frame")
abUpdateFrame:Hide()
abUpdateFrame._lastCd = 0
abUpdateFrame._lastState = 0
abUpdateFrame._lastVis = 0
abUpdateFrame._dirtyCooldowns = false
abUpdateFrame._dirtyStates = false
abUpdateFrame._dirtyVisuals = false
abUpdateFrame._dirtyCounts = false
abUpdateFrame._immediate = false  -- bypass combat throttle for this tick
abUpdateFrame:SetScript("OnUpdate", function(self)
    local now = GetTime()
    -- Out of combat: flush visual/state immediately; lightly coalesce
    -- cooldown-only scans. In combat: coalesce high-frequency events behind
    -- interval gates.
    -- _immediate flag lets low-frequency events (icon change, form swap)
    -- bypass the combat throttle for a single tick.
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
        -- SafeUpdate includes cooldown + checked state + count internally
        ActionBarsOwned.UpdateAllButtonVisuals()
    elseif doState then
        if throttle and (now - self._lastState < AB_STATE_UPDATE_INTERVAL) then return end
        -- State is lean; if cooldowns or counts are also dirty, run them
        -- in the same tick to avoid a second OnUpdate wake-up.
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
        -- Piggyback counts if dirty — same frame, avoid extra wake-up.
        if doCount then
            self._dirtyCounts = false
            ActionBarsOwned.UpdateAllButtonCounts()
        end
    elseif doCount then
        -- Counts are lightweight — no combat throttle needed, just
        -- once-per-frame dedup via _lastCountUpdateTime inside the fn.
        self:Hide()
        self._dirtyCounts = false
        ActionBarsOwned.UpdateAllButtonCounts()
    else
        self:Hide()
    end
end)

-- Optional profiler split for cooldown/state/visual paths. The default module
-- profiler entry below still covers the event frame; these extra wrappers are
-- only installed when explicitly requested because they add an extra Lua call
-- to every actionbar refresh.
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
    if ns.DebugRegister then -- gate contract: core/debug_gate.lua
        ns.DebugRegister(SetupSplitPerfProbeRegistry)
    else
        SetupSplitPerfProbeRegistry() -- standalone test harness: no gate, run eagerly
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
        -- Mass action-table shuffles (shapeshift, vehicle swap, fresh world,
        -- spell learn/unlearn) need a full scan because the old _activeButtons
        -- set is stale — the same button handle may now point at a different
        -- action and some active→empty transitions aren't event-signalled.
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

-- ACTIONBAR_SLOT_CHANGED: only needed for drag/drop (specific slot > 0).
-- Slot 0 ("all changed") is ignored — already covered by SPELLS_CHANGED,
-- SafeSyncAction, PLAYER_ENTERING_WORLD, etc.
-- Specific slots during paging are also suppressed: UPDATE_SHAPESHIFT_FORM
-- and SafeSyncAction already handle those buttons.
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
                pcall(ActionBarsOwned.SafeUpdate, btn)
                ActionBarsOwned.UpdateCooldown(btn)
                ActionBarsOwned.UpdateOverlayGlow(btn)
                -- Slot content can change without the button's action slot
                -- changing (drag/drop within the same slot), so bounce the
                -- secure release-state recompute through the bar container
                -- instead of mutating button attributes from insecure Lua.
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
    -- Slot content changed; rebuild the spell lookup lazily on the next glow.
    if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
    if SyncOwnedFlyoutInfoToHandler then
        SyncOwnedFlyoutInfoToHandler()
    end
    -- Slot contents changed — the rotation action may have moved to a
    -- different button.  Invalidate the cached rotation button so the
    -- next UpdateAllAssistedCombatRotation re-discovers it from the
    -- current recommendation.
    _assistRotationButton = nil
    -- Refresh assisted combat highlights and rotation frames.
    UpdateAllAssistedHighlights()
    ActionBarsOwned.UpdateAllAssistedCombatRotation()
end)

function ScheduleSlotUpdate(slot)
    -- Ignore slot 0 (full refresh) — redundant with companion events
    if not slot or slot < 1 then return end
    -- Suppress during paging window (form changes, stealth, vehicle).
    -- UPDATE_SHAPESHIFT_FORM + SafeSyncAction already refresh these buttons.
    if GetTime() - _lastPagingTime < 0.5 then return end
    abDirtySlots[slot] = true
    abSlotFrame:Show()
end

function OnOwnedEvent(self, event, ...)
    if not ActionBarsOwned.initialized then return end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        -- Debounced: collect dirty slots, process in one batch after 50ms.
        -- Talent swaps fire 96 events, bar paging fires 12, zone transitions
        -- fire slot 0 — all coalesced into a single update pass.
        local slot = ...
        ScheduleSlotUpdate(slot)

    elseif event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "UPDATE_SHAPESHIFT_FORMS"
        or event == "UPDATE_STEALTH" then
        -- Mark paging window so ScheduleSlotUpdate suppresses the redundant
        -- ACTIONBAR_SLOT_CHANGED burst that Blizzard fires after paging.
        _lastPagingTime = GetTime()
        -- Page swap may remap which button holds the rotation action.
        _assistRotationButton = nil
        if HideOwnedFlyout then
            HideOwnedFlyout()
        end
        -- Paging is handled by state driver: _childupdate-offset sets the
        -- action attribute and calls CallMethod("SafeSyncAction") which
        -- syncs self.action and refreshes visuals on each button.
        -- Remaining work: empty slot visibility, cooldowns, proc glows,
        -- and bar1 bindings.
        local buttons = ActionBarsOwned.nativeButtons["bar1"]
        local settings = GetEffectiveSettings("bar1")
        if buttons and settings then
            for _, btn in ipairs(buttons) do
                UpdateEmptySlotVisibility(btn, settings)
            end
        end
        -- Refresh cooldowns and proc glows for the new page's actions
        if buttons then
            for _, btn in ipairs(buttons) do
                ActionBarsOwned.UpdateCooldown(btn)
                ActionBarsOwned.UpdateOverlayGlow(btn)
            end
        end
        -- Stance bar may need re-layout when shapeshift forms change
        if not InCombatLockdown() then
            UpdateStanceBarLayout()
        else
            ActionBarsOwned.pendingStanceUpdate = true
        end
        ApplyBar1OverrideBindings()

    elseif event == "UPDATE_SHAPESHIFT_COOLDOWN" or event == "UPDATE_SHAPESHIFT_USABLE" then
        -- Refresh stance button visuals (cooldowns, usability coloring)
        ActionBarsOwned.UpdateAllStanceButtons()

    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit == "player" then
            ApplyBar1OverrideBindings()
            -- Blizzard may reclaim micro buttons during vehicle transitions
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

    elseif event == "UPDATE_BINDINGS" then
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
        -- SafeUpdate keeps all visuals live during combat (icon, cooldown,
        -- glow, usability, count, checked state).  Skinning state does not
        -- drift in combat, so no post-combat re-skin pass is needed.

    elseif event == "PET_BAR_UPDATE" or event == "PET_BAR_UPDATE_COOLDOWN" then
        -- PetActionBarMixin:Update on the suppressed bar won't fire, so QUI
        -- drives pet button visuals (icons, active state, autocast) directly.
        ActionBarsOwned.UpdateAllPetButtons()
        -- UpdatePetBarVisibility is combat-safe (Show/Hide drive through the
        -- container's secure attribute snippet, layout via SecureLayoutBar).
        UpdatePetBarVisibility()

    elseif event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        local unit = ...
        if event == "UNIT_PET" and unit ~= "player" then return end
        -- Pet summoned/dismissed/swapped — update container visibility
        C_Timer.After(0.1, function()
            if not ActionBarsOwned.initialized then return end
            UpdatePetBarVisibility()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        -- Safe period: InCombatLockdown() is true during combat reload but
        -- protected calls are still allowed. Set the flag so all sub-functions
        -- bypass their combat guards.
        inInitSafeWindow = true
        -- Also set the namespace-level flag so the anchoring system can
        -- reposition bar containers during this safe window. During
        -- ADDON_LOADED the containers may not have existed yet, so the
        -- anchoring system resolved the Blizzard frames instead.
        ns._inInitSafeWindow = true
        if isReload then
            ApplyAllBarSpacing()
            -- Safety net: Blizzard's Layout() may fire after safe window
            -- closes. Mark pending so PLAYER_REGEN_ENABLED reapplies.
            ActionBarsOwned.pendingSpacing = true
        end
        -- Re-apply frame anchoring now that containers exist. The
        -- ADDON_LOADED pass may have missed them (created after the
        -- core init safe window closed).
        if ns.QUI_Anchoring and ns.QUI_Anchoring.ApplyAllFrameAnchors then
            ns.QUI_Anchoring:ApplyAllFrameAnchors(true)
        end
        -- Do layout immediately during the safe period so the UI is correct
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
        inInitSafeWindow = false
        ns._inInitSafeWindow = false
        -- Second pass after Blizzard frames settle; defer if safe period ended
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
            -- PEW covers zone/arena/BG entry — action set may differ,
            -- force a full scan so the active button set rebuilds.
            ActionBarsOwned.ForceFullVisualRescan()
            ActionBarsOwned.UpdateAllButtonVisuals()
            ActionBarsOwned.UpdateAllCooldowns()
            UpdatePetBarVisibility()
            UpdateStanceBarLayout()
            ApplyAllFlyoutDirections()
            if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end
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

    elseif event == "PLAYER_LEVEL_UP" then
        if UpdateLevelSuppressionState() then
            if type(_G.QUI_RefreshActionBars) == "function" then
                _G.QUI_RefreshActionBars()
            end
        end

    elseif event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE" then
        -- Centralized cooldown update for all owned action buttons.
        -- Per-button OnEvent is suppressed (addon-created frames are
        -- tainted).  DurationObject path is secret-safe.
        -- Coalesced: fires 20+/sec in combat, throttled to ~30Hz.
        if _abCooldownStats then _abCooldownStats.events = _abCooldownStats.events + 1 end
        ScheduleABCooldownUpdate()

    elseif event == "ACTIONBAR_UPDATE_STATE" then
        -- Checked state only (autoattack, toggle abilities, current action).
        -- This event fires very frequently in combat — dispatch via the
        -- lean SetChecked-only pass instead of the full SafeUpdate chain.
        ScheduleABStateUpdate()

    elseif event == "SPELL_UPDATE_ICON" then
        -- Icon texture changed (rare — spell morphs, glyphs, etc).
        -- Needs full SafeUpdate to refresh the icon texture.
        -- Immediate: infrequent but visually jarring when delayed.
        ScheduleABVisualUpdate(false, true)

    elseif event == "MODIFIER_STATE_CHANGED" then
        -- Modifier pressed/released — macro conditionals like [mod:shift]
        -- may resolve to a different spell, changing the icon texture.
        -- Immediate: user expects instant visual feedback on key press.
        ScheduleABVisualUpdate(false, true)

    elseif event == "ACTIONBAR_UPDATE_USABLE" then
        -- Usability only — the dedicated usability overlay system handles
        -- tinting (range/mana/unusable).  No need for a full SafeUpdate
        -- which redundantly sets vertex colors on all 96 buttons.
        ScheduleUsabilityUpdate()

    elseif event == "SPELL_UPDATE_CHARGES" then
        -- Charge count changed (e.g. Arcane Charges, Chi).
        ScheduleABCountUpdate()

    elseif event == "UNIT_AURA" then
        -- Aura-based resource overlays (Soul Fragments, etc.) update
        -- the action display count when auras change.  Only react to
        -- player auras — party/target aura churn is irrelevant.
        local unit = ...
        if unit == "player" then
            ScheduleABCountUpdate()
        end

    elseif event == "ACTIONBAR_SHOWGRID" then
        -- Dragging from spellbook — show empty slot grid.
        -- Temporarily register ACTIONBAR_SLOT_CHANGED so we catch the
        -- specific slot the player drops onto.
        ActionBarsOwned._showGrid = true
        self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    btn:SetAlpha(1)
                end
            end
        end

    elseif event == "ACTIONBAR_HIDEGRID" then
        -- Drag ended — restore empty slot visibility and unregister
        -- ACTIONBAR_SLOT_CHANGED (fires constantly even while idle).
        ActionBarsOwned._showGrid = nil
        self:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
        -- Full post-drag refresh: the drag may have moved spells (including
        -- the one-button rotation action) between slots.  Some action types
        -- don't fire per-slot ACTIONBAR_SLOT_CHANGED, so we refresh
        -- everything here to guarantee correctness.  Force a full scan so
        -- newly-populated empty slots are caught immediately.
        ScheduleABVisualUpdate(true)
        ScheduleABCooldownUpdate()
        -- Assisted combat rotation and highlights must also refresh — the
        -- rotation action may have moved to a new button.
        ActionBarsOwned.UpdateAllAssistedCombatRotation()
        UpdateAllAssistedHighlights()
        -- Restore empty slot visibility (alpha was forced to 1 during grid)
        RefreshAllEmptySlotVisibility()
        -- Slot contents may have changed; rebuild the lookup lazily.
        if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
        if SyncOwnedFlyoutInfoToHandler then SyncOwnedFlyoutInfoToHandler() end

    elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
        -- Auto-attack flash state changes (SafeUpdate handles flash now)
        -- Immediate: discrete one-shot events, not combat spam.
        ScheduleABVisualUpdate(false, true)

    elseif event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
        -- Auto-shot/wand toggle — refresh flash state on all buttons
        -- Immediate: discrete one-shot events.
        ScheduleABVisualUpdate(false, true)

    elseif event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- Talent swap, respec, new spell learned — full refresh of icons,
        -- usability, cooldowns, flyouts, and empty slot visibility.
        -- Coalesced: SPELLS_CHANGED fires more often than expected in 12.0+.
        ScheduleABVisualUpdate(true)  -- force full scan: action table reshuffled
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllOverlayGlows()
        -- Update flyout data on all buttons
        RefreshAllFlyouts()
        RefreshAllEmptySlotVisibility()
        -- Zone/extra abilities may have changed — recapture frames.
        RefreshExtraButtons()

    elseif event == "SPELL_FLYOUT_UPDATE" then
        -- Flyout data changed — refresh flyout arrows on all buttons
        RefreshAllFlyouts()

    elseif event == "SPELL_UPDATE_USABLE" then
        -- Spell usability changed (e.g. resource gained/spent, GCD ended).
        -- Routed to the dedicated usability overlay system — avoids
        -- redundant full SafeUpdate on all 96 buttons just for tinting.
        ScheduleUsabilityUpdate()

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellId = ...
        ActionBarsOwned.OnSpellActivationGlowShow(spellId)

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellId = ...
        ActionBarsOwned.OnSpellActivationGlowHide(spellId)

    elseif event == "UPDATE_VEHICLE_ACTIONBAR" then
        -- Vehicle action bar data changed — full refresh (coalesced)
        ScheduleABVisualUpdate(true)  -- force full scan: vehicle swaps whole action set
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllOverlayGlows()
        ApplyBar1OverrideBindings()

    elseif event == "UPDATE_EXTRA_ACTIONBAR" then
        -- Extra action bar appeared/disappeared — recapture frames.
        RefreshExtraButtons()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        -- Equipment changed — items on action bars may need icon/cooldown refresh
        local unit = ...
        if unit == "player" then
            ScheduleABVisualUpdate(true)  -- force full scan: item slots may have gained/lost actions
            ScheduleABCooldownUpdate()
        end

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- Mount display changed — icon refresh for mount abilities
        ScheduleABVisualUpdate()

    elseif event == "PET_BATTLE_OPENING_START" then
        -- Clear all override bindings so the pet battle UI gets keys.
        -- Hide action bar containers (pet battle has its own UI).
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
        -- Restore bars and bindings after pet battle ends
        if not InCombatLockdown() then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local cont = ActionBarsOwned.containers[barKey]
                if cont then cont:Show() end
            end
            ApplyAllOverrideBindings()
            -- Restore pet/stance visibility (may have been hidden)
            UpdatePetBarVisibility()
            UpdateStanceBarLayout()
        else
            ActionBarsOwned.pendingBindings = true
            ActionBarsOwned.pendingRefresh = true
        end
    end
end

-- Event handler is set here; events are registered in Initialize().
ownedEventFrame:SetScript("OnEvent", OnOwnedEvent)

local function SetupDebugInstrumentation()
    -- Pick up the global published by actionbars_cooldowns.lua's setup closure.
    -- Ordering: the debug gate drains FIFO in registration (= file load) order,
    -- and actionbars.xml loads cooldowns before this file, so the global is
    -- already set here. If that ordering breaks, this stays nil and the
    -- events counter silently stops counting.
    _abCooldownStats = _G._abCooldownStats
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "ActionBars", frame = ownedEventFrame }
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

