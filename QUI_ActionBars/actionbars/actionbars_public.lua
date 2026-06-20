local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

-- Clear OverrideActionBar.isShownExternal and re-run the untaint dance until
-- the field reads secure again. Edit Mode / Blizzard_ActionBar may have written
-- a tainted show flag; left in place it propagates through ActionBarController
-- on re-show. Shared by Initialize and the ADDON_LOADED handler, which ran this
-- identical loop.
local function PurgeOverrideBarShownExternal()
    local overrideBar = _G.OverrideActionBar
    if overrideBar and overrideBar.system then
        overrideBar.isShownExternal = nil
        local c = 42
        repeat
            if overrideBar[c] == nil then
                overrideBar[c] = nil
            end
            c = c + 1
        until issecurevariable(overrideBar, "isShownExternal")
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

function ActionBarsOwned:Initialize()
    if self.initialized then return end

    self.initialized = true

    -- Patch LibKeyBound Binder methods to work with unified frameState
    PatchLibKeyBoundForMidnight()

    -- Re-register events
    -- ACTIONBAR_SLOT_CHANGED not registered here — only registered during
    -- drag operations (ACTIONBAR_SHOWGRID).  Blizzard fires slot 0 constantly
    -- even while idle, and all non-drag scenarios are already covered by
    -- SPELLS_CHANGED, SafeSyncAction, UPDATE_SHAPESHIFT_FORM, etc.
    ownedEventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    ownedEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_USABLE")
    ownedEventFrame:RegisterEvent("UPDATE_STEALTH")
    ownedEventFrame:RegisterEvent("UPDATE_BINDINGS")
    ownedEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    ownedEventFrame:RegisterEvent("CURSOR_CHANGED")
    ownedEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ownedEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    ownedEventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    ownedEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ownedEventFrame:RegisterEvent("ZONE_CHANGED")
    ownedEventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    ownedEventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    ownedEventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
    ownedEventFrame:RegisterEvent("CHALLENGE_MODE_START")
    ownedEventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    ownedEventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
    ownedEventFrame:RegisterEvent("ENCOUNTER_START")
    ownedEventFrame:RegisterEvent("ENCOUNTER_END")
    ownedEventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    ownedEventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    ownedEventFrame:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    ownedEventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    ownedEventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
    ownedEventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    ownedEventFrame:RegisterEvent("ACTIONBAR_SHOWGRID")
    ownedEventFrame:RegisterEvent("ACTIONBAR_HIDEGRID")
    ownedEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    ownedEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    ownedEventFrame:RegisterEvent("SPELL_UPDATE_ICON")
    ownedEventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    ownedEventFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
    ownedEventFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    ownedEventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
    ownedEventFrame:RegisterEvent("PET_BATTLE_CLOSE")
    ownedEventFrame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    ownedEventFrame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    -- Spell activation overlay glow (proc abilities)
    ownedEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    ownedEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    -- Events that QUI handles centrally — per-button events are
    -- unregistered on QUI-created buttons.
    ownedEventFrame:RegisterEvent("SPELLS_CHANGED")
    ownedEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
    ownedEventFrame:RegisterEvent("SPELL_FLYOUT_UPDATE")
    ownedEventFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    ownedEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ownedEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    ownedEventFrame:RegisterEvent("START_AUTOREPEAT_SPELL")
    ownedEventFrame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    if IS_MIDNIGHT then
        ownedEventFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    end
    ownedEventFrame:Show()

    -- Build all managed bars (1-8 + pet/stance)
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        BuildBar(barKey)
    end

    -- Let Blizzard's OverrideActionBar display natively during vehicle /
    -- override / possess states.  QUI's bar1 is hidden during those states
    -- by a secure visibility state driver (see HideBar1DuringOverride
    -- below), so there's no visual conflict.  Keybinds pass through to
    -- Blizzard's native override bar because ApplyBarOverrideBindings bails
    -- for bar1 when IsVehicleBarActive() is true, leaving the default
    -- ACTIONBUTTON1..6 -> OverrideActionBarButton1..6 remap intact.
    --
    -- We still clean isShownExternal on OverrideActionBar to prevent
    -- Edit Mode from writing a tainted show flag that could propagate
    -- through ActionBarController on re-show.
    PurgeOverrideBarShownExternal()

    -- Suppress PossessActionBar (mind control bar) — can overlap QUI bars
    local possessBar = _G.PossessActionBar or _G.PossessBarFrame
    if possessBar then
        possessBar:UnregisterAllEvents()
        possessBar:SetParent(hiddenBarParent)
        possessBar:Hide()
    end

    -- Suppress NPE (New Player Experience) tutorials that reference
    -- original Blizzard action buttons.  Without this, the tutorial
    -- system tries to find ActionButton1 etc. which are suppressed.
    if _G.AddSpellToActionBar then
        _G.AddSpellToActionBar = noop
    end
    if _G.AddClassSpellToActionBar then
        _G.AddClassSpellToActionBar = noop
    end
    -- Enable the auto-push watcher so spells still go to bars
    if _G.AutoPushSpellWatcher and _G.AutoPushSpellWatcher.Start then
        pcall(_G.AutoPushSpellWatcher.Start, _G.AutoPushSpellWatcher)
    end

    -- Clear override bindings when entering player housing (housing has
    -- its own keybinds).  Restore when leaving.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("HouseEditor.StateUpdated", function(_, state)
            if InCombatLockdown() then
                if not state then
                    ActionBarsOwned.pendingBindings = true
                end
                return
            end
            if state then
                ActionBarsOwned._inHousing = true
                for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                    local cont = ActionBarsOwned.containers[barKey]
                    if cont then ClearOverrideBindings(cont) end
                end
            else
                ActionBarsOwned._inHousing = nil
                ApplyAllOverrideBindings()
            end
        end, "QUI_ActionBars")
    end

    -- Register pet/stance-specific events
    ownedEventFrame:RegisterEvent("PET_BAR_UPDATE")
    ownedEventFrame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    ownedEventFrame:RegisterEvent("PET_UI_UPDATE")
    ownedEventFrame:RegisterEvent("UNIT_PET")

    -- Update pet bar visibility based on current pet state
    UpdatePetBarVisibility()
    UpdateStanceBarLayout()

    -- Blizzard bars are fully disposed (hidden + events unregistered).
    -- QUI creates fresh buttons with SetOverrideBindingClick for keybinds.

    -- Spellbook hover highlight — show which action bar button has a spell
    -- when hovering that spell in the spellbook.
    if _G.UpdateOnBarHighlightMarksBySpell then
        hooksecurefunc("UpdateOnBarHighlightMarksBySpell", function(spellID)
            ActionBarsOwned.spellHighlight.type = "spell"
            ActionBarsOwned.spellHighlight.id = tonumber(spellID)
        end)
    end
    if _G.UpdateOnBarHighlightMarksByFlyout then
        hooksecurefunc("UpdateOnBarHighlightMarksByFlyout", function(flyoutID)
            ActionBarsOwned.spellHighlight.type = "flyout"
            ActionBarsOwned.spellHighlight.id = tonumber(flyoutID)
        end)
    end
    if _G.ClearOnBarHighlightMarks then
        hooksecurefunc("ClearOnBarHighlightMarks", function()
            ActionBarsOwned.spellHighlight.type = nil
            ActionBarsOwned.spellHighlight.id = nil
        end)
    end
    if _G.ActionBarController_UpdateAllSpellHighlights then
        hooksecurefunc("ActionBarController_UpdateAllSpellHighlights", ActionBarsOwned.UpdateAllSpellHighlights)
    end

    -- Assisted combat rotation (one-button rotation arrow overlay).
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function()
            local okSpell, newSpell = pcall(C_AssistedCombat.GetNextCastSpell, false)
            if not okSpell then newSpell = nil end
            -- Dedupe: Blizzard fires this every OnUpdate frame under soft
            -- targeting; if the rotation spell hasn't actually changed,
            -- skip entirely.
            if newSpell == ActionBarsOwned._lastAssistRotationSpell then return end
            ActionBarsOwned._lastAssistRotationSpell = newSpell
            if newSpell then ActionBarsOwned._assistedCombatEverActive = true end
            ActionBarsOwned.UpdateAllAssistedCombatRotation()
            -- The rotation button's icon needs to update too — SafeUpdate
            -- overrides the arrow texture with the recommended spell.
            -- Immediate flush: spell changes are low-frequency.
            ScheduleABVisualUpdate(false, true)
            -- Keybind overlays share this signal — they don't need their own
            -- callback since they react to the same recommendation change.
            -- (RotationAssistIcon self-registers in rotationassist.lua.)
            local kb = ns.Keybinds
            if kb and kb.UpdateAllRotationHelpers then pcall(kb.UpdateAllRotationHelpers) end
        end, "QUI_ActionBars_AssistedCombat")

        -- Assisted combat highlight (marching ants on the next-cast button).
        -- Process immediately in the callback — no dirty-flag deferral.
        -- Soft targeting causes constant nil→spell→nil→spell oscillation.
        -- Nil means "no recommendation right now" (target lost, soft-target
        -- gap) — NOT "rotation disabled".  Ignore nil to avoid flicker.
        -- Highlights refresh on HIDEGRID or PLAYER_REGEN_ENABLED.
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            local okHL, nextSpell = pcall(C_AssistedCombat.GetNextCastSpell, false)
            if not okHL then nextSpell = nil end
            if not nextSpell then return end
            if nextSpell == ActionBarsOwned._lastAssistHighlightSpell then return end
            ActionBarsOwned._lastAssistHighlightSpell = nextSpell
            UpdateAllAssistedHighlights()
        end, "QUI_ActionBars_AssistedHighlight")
    end

    -- Direct hook on AssistedCombatManager — catches the spell-change at
    -- the source even when no bar button hosts the assist slot (the
    -- EventRegistry event above doesn't reliably fire in that case).
    -- Drives the SafeUpdate texture-race refresh and keybind overlays.
    -- (RotationAssistIcon self-registers its own hook in rotationassist.lua.)
    if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function(_, spellID)
            if not spellID then return end
            local Helpers = ns.Helpers
            local isSecret = Helpers and Helpers.IsSecretValue(spellID)

            -- Resolve the talent-transformed display spell.  Blizzard may
            -- recommend a base spell ID while talents have replaced it with
            -- an override (or vice versa).  Resolve both directions so
            -- downstream matching works regardless of which ID the API returns.
            local resolvedID = spellID
            if not isSecret then
                -- Forward: base → current override (e.g., Thunder Clap → Thunder Blast)
                local okOvr, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
                if okOvr and overrideID and overrideID ~= spellID then
                    resolvedID = overrideID
                end
            end

            -- ForceUpdateAction → SafeUpdate races the C-side texture write:
            -- SafeUpdate reads GetActionTexture before the new value is
            -- committed, showing the PREVIOUS spell icon.  This hook fires
            -- AFTER the C-side completes, so schedule an immediate visual
            -- refresh to re-read the now-correct texture.
            ScheduleABVisualUpdate(false, true)
            -- Pass both the resolved override and the original base so the
            -- matcher can check either direction.  Secret values pass through
            -- safely — tonumber() returns nil for secrets, so no match = no
            -- overlay, no crash.
            local kb = ns.Keybinds
            if kb and kb.UpdateAllRotationHelpers then
                pcall(kb.UpdateAllRotationHelpers, resolvedID, spellID)
            end
        end)
    end

    -- No overlay scaling hooks needed — buttons stay at their natural 45x45
    -- size and the container's SetScale handles visual resize. Blizzard overlays
    -- work naturally because button dimensions match what they expect.

    -- Hook ActionButton_Update to refresh text/visibility (but NOT force re-skin).
    -- PERF: Removed skinKey = nil force-reset — the field-comparison dedup in
    -- SkinButton handles this naturally without string.format overhead.
    -- Actual artwork re-skinning is handled by per-button UpdateButtonArt hooks
    -- installed during BuildBar (fires less often, deferred via C_Timer).
    if ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(button)
            if InCombatLockdown() then return end
            if not ActionBarsOwned.skinnedButtons[button] then return end
            local bk = GetBarKeyFromButton(button)
            if not bk then return end
            local s = GetEffectiveSettings(bk)
            if s then
                SkinButton(button, s)
                UpdateButtonText(button, s)
                UpdateEmptySlotVisibility(button, s)
            end
        end)
    end

    -- Setup usability polling
    ActionBarsOwned.UpdateUsabilityPolling()

    -- Register Edit Mode callbacks
    local core = GetCore()
    if core and core.RegisterEditModeEnter then
        core:RegisterEditModeEnter(OnEditModeEnter)
        core:RegisterEditModeExit(OnEditModeExit)
    end

    -- Hook tooltip suppression for QUI action bar buttons.
    -- PERF: This fires on EVERY tooltip in the game.  Fast-exit via cached
    -- setting + O(1) skinnedButtons lookup instead of DB walk + string match.
    ActionBarsOwned._suppressTooltips = false
    function ActionBarsOwned:RefreshTooltipSuppressCache()
        local global = GetGlobalSettings()
        self._suppressTooltips = global and global.showTooltips == false
    end
    ActionBarsOwned:RefreshTooltipSuppressCache()

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not ActionBarsOwned._suppressTooltips then return end
        if not parent or not ActionBarsOwned.skinnedButtons[parent] then return end
        tooltip:Hide()
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:ClearLines()
    end)

    -- Hook spellbook visibility for the mouseover fade system. The player
    -- spells UI can be created lazily, so we also hook its toggle functions
    -- and retry once the panel is actually opening.
    ActionBarsOwned.EnsureSpellBookVisibilityHooks()
    ActionBarsOwned.HookSpellBookToggleFunction("ToggleSpellBook")
    ActionBarsOwned.HookSpellBookToggleFunction("TogglePlayerSpellsFrame")
    ActionBarsOwned.ScheduleSpellBookVisibilityRefresh()

    -- Initialize extra buttons
    inInitSafeWindow = true
    InitializeExtraButtons()
    inInitSafeWindow = false

    -- Apply page arrow visibility
    local db = GetDB()
    if db and db.bars and db.bars.bar1 then
        ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
    end

    -- Hide bars that are disabled in DB
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local barDB = GetBarSettings(barKey)
        if barDB and barDB.enabled == false then
            local container = self.containers[barKey]
            if container then
                container:SetAttribute("qui-user-shown", false)
                container:Hide()
            end
        end
    end

    -- Apply layout-mode hidden state during the addon-load safe window.
    -- The bar containers use SecureHandlerStateTemplate + RegisterStateDriver,
    -- which makes SetAttribute protected during combat. Layout Mode's
    -- EnforceGameplayVisibility runs at PLAYER_ENTERING_WORLD+3s — past the
    -- safe window — so applying hidden state from there triggers
    -- ADDON_ACTION_BLOCKED on a combat /reload. Apply it here while the
    -- safe window is open, and pre-mark _gameplayHidden so the later pass
    -- treats the work as already done and skips the redundant SetAttribute.
    local profile = Helpers.GetProfile()
    local hiddenHandles = profile and profile.layoutMode and profile.layoutMode.hiddenHandles
    if hiddenHandles then
        local LAYOUT_TO_CONTAINER = {
            bar1 = "bar1", bar2 = "bar2", bar3 = "bar3", bar4 = "bar4",
            bar5 = "bar5", bar6 = "bar6", bar7 = "bar7", bar8 = "bar8",
            petBar = "pet", stanceBar = "stance",
            microMenu = "microbar", bagBar = "bags",
        }
        local lm = ns.QUI_LayoutMode
        if lm then
            lm._gameplayHidden = lm._gameplayHidden or {}
        end
        for layoutKey, containerKey in pairs(LAYOUT_TO_CONTAINER) do
            if hiddenHandles[layoutKey] then
                local container = self.containers[containerKey]
                if container then
                    container:SetAttribute("qui-user-shown", false)
                    container:Hide()
                    if lm then
                        lm._gameplayHidden[layoutKey] = true
                    end
                end
            end
        end
    end
end

function ActionBarsOwned:Refresh()
    if not self.initialized then return end

    InvalidateEffectiveSettingsCache()

    if InCombatLockdown() then
        self.pendingRefresh = true
        return
    end

    if HideOwnedFlyout then
        HideOwnedFlyout()
    end

    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        BuildBar(barKey)
    end

    -- Patch LibKeyBound Binder methods to work without method injection on Midnight
    PatchLibKeyBoundForMidnight()

    -- Hook tooltip suppression for action buttons (once only — hooksecurefunc is permanent)
    -- NOTE: Synchronous — deferring causes tooltip flash before hide.
    if not ActionBarsOwned._refreshHooksInstalled then
        ActionBarsOwned._refreshHooksInstalled = true
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
            local global = GetGlobalSettings()
            if not global or global.showTooltips ~= false then return end
            local name = parent and parent.GetName and parent:GetName()
            if name and (name:match("^ActionButton") or name:match("^MultiBar") or name:match("^PetActionButton")
                or name:match("^StanceButton") or name:match("^OverrideActionBar") or name:match("^ExtraActionButton")) then
                tooltip:Hide()
                tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                tooltip:ClearLines()
            end
        end)

        -- Modern retail (post-rename): proc swirl is created lazily by
        -- ActionButtonSpellAlertManager:ShowAlert. Hook the manager so we
        -- catch the alert frame the moment it exists, both for the default
        -- alert and the AssistedCombatRotationFrame's separate alert.
        if ActionButtonSpellAlertManager and ActionButtonSpellAlertManager.ShowAlert then
            hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
                if not actionButton then return end
                if not ActionBarsOwned.skinnedButtons[actionButton] then return end
                ActionBarsOwned.SuppressButtonProcVisuals(actionButton)
                local acrf = actionButton.AssistedCombatRotationFrame
                if acrf and acrf.SpellActivationAlert then
                    SuppressProcVisualFrame(acrf.SpellActivationAlert)
                end
            end)
        end
        -- Legacy global path — kept as a fallback for clients that still
        -- expose ActionButton_ShowOverlayGlow before the SpellAlertManager
        -- refactor.
        if type(ActionButton_ShowOverlayGlow) == "function" then
            hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
                if ActionBarsOwned.skinnedButtons[button] then
                    ActionBarsOwned.SuppressButtonProcVisuals(button)
                end
            end)
        end
    end

    -- Initial skin pass
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        SkinBar(barKey)
    end
    ActionBarsOwned.HookSpellFlyoutSkinning()

    -- Apply bar layout settings (spacing, empty slot visibility)
    ApplyAllBarSpacing()
    ApplyAllFlyoutDirections()
    if SyncOwnedFlyoutInfoToHandler then
        SyncOwnedFlyoutInfoToHandler()
    end

    -- Hide bars that are disabled in DB
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local barDB = GetBarSettings(barKey)
        if barDB and barDB.enabled == false then
            local container = self.containers[barKey]
            if container then
                container:SetAttribute("qui-user-shown", false)
                container:Hide()
            end
        end
    end

    -- Refresh pet/stance conditional visibility
    UpdatePetBarVisibility()
    UpdateStanceBarLayout()

    ActionBarsOwned.UpdateUsabilityPolling()
    if self.RefreshTooltipSuppressCache then self:RefreshTooltipSuppressCache() end
end


---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTION
---------------------------------------------------------------------------

_G.QUI_RefreshActionBars = function()
    if InCombatLockdown() then
        ActionBarsOwned.pendingRefresh = true
        return
    end
    ActionBarsOwned:Refresh()
    if ns.QUI_ActionBarsPreviewDriver and ns.QUI_ActionBarsPreviewDriver.Refresh then
        ns.QUI_ActionBarsPreviewDriver.Refresh()
    end
end

-- Apply the `useOnKeyDown` profile setting to all QUI action bar
-- buttons. SetAttribute on a secure frame is protected during combat,
-- so defer to PLAYER_REGEN_ENABLED when locked down. Empowered spells
-- are unaffected — pressAndHoldAction + typerelease="actionrelease"
-- handle the press/release flow independently of this attribute.
_G.QUI_ApplyUseOnKeyDown = function()
    if InCombatLockdown() then
        ActionBarsOwned.pendingUseOnKeyDownUpdate = true
        return
    end
    local db = GetDB()
    local value = db and db.global and db.global.useOnKeyDown == true
    for bar = 1, 8 do
        for i = 1, 12 do
            local btn = _G["QUI_Bar" .. bar .. "Button" .. i]
            if btn then
                btn:SetAttribute("useOnKeyDown", value)
                if btn.RunAttribute then
                    btn:RunAttribute("QUI_UpdateActionFlags")
                end
            end
        end
    end
    if EnsureOwnedFlyoutFrame then
        local flyout = EnsureOwnedFlyoutFrame()
        local count = (flyout and flyout.GetAttribute and flyout:GetAttribute("numFlyoutButtons")) or 0
        for i = 1, count do
            local btn = _G["QUI_SpellFlyoutButton" .. i]
            if btn then
                btn:SetAttribute("useOnKeyDown", value)
            end
        end
    end
end

_G.QUI_ReapplyActionBarBindings = function()
    if InCombatLockdown() then
        ActionBarsOwned.pendingBindings = true
        return
    end
    RefreshNativeKeybinds()
end

-- Lightweight refresh: only re-evaluate mouseover fade state for all bars.
-- Used by fade/alwaysShow settings that don't need a full bar rebuild.
_G.QUI_RefreshActionBarFade = function()
    if not ActionBarsOwned.initialized then return end
    if RefreshActionBarContextVisibility then
        RefreshActionBarContextVisibility()
    end
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local state = GetOwnedBarFadeState(barKey)
        state.isFading = false
        CancelOwnedBarFadeTimers(state)
        SetupOwnedBarMouseover(barKey)
    end
    for _, barKey in ipairs({"extraActionButton", "zoneAbility"}) do
        local state = GetBarFadeState(barKey)
        state.isFading = false
        CancelBarFadeTimers(state)
        SetupBarMouseover(barKey)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == ADDON_NAME then
        if not GetDB() then return end
        ActionBarsOwned:Initialize()
    elseif addonName == "Blizzard_ActionBar" then
        ActionBarsOwned.HookSpellFlyoutSkinning()
        C_Timer.After(0, SkinSpellFlyoutButtons)
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            C_Timer.After(0, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
        end
        -- OverrideActionBar is intentionally left visible so Blizzard can
        -- display vehicle/override abilities natively; QUI bar1 hides
        -- during those states via its qui_overridevisibility state driver.
        -- Clean isShownExternal here (Blizzard_ActionBar may have just
        -- created it) so Edit Mode writes don't taint ActionBarController.
        PurgeOverrideBarShownExternal()
    elseif ActionBarsOwned.HandleSpellBookAddonLoaded then
        ActionBarsOwned.HandleSpellBookAddonLoaded(addonName)
    end
end)

---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local BAR_ELEMENTS = {
            { key = "bar1", label = ns.L["Action Bar 1"], order = 1 },
            { key = "bar2", label = ns.L["Action Bar 2"], order = 2 },
            { key = "bar3", label = ns.L["Action Bar 3"], order = 3 },
            { key = "bar4", label = ns.L["Action Bar 4"], order = 4 },
            { key = "bar5", label = ns.L["Action Bar 5"], order = 5 },
            { key = "bar6", label = ns.L["Action Bar 6"], order = 6 },
            { key = "bar7", label = ns.L["Action Bar 7"], order = 7 },
            { key = "bar8", label = ns.L["Action Bar 8"], order = 8 },
            { key = "petBar",    label = ns.L["Pet Bar"],     order = 9 },
            { key = "stanceBar", label = ns.L["Stance Bar"],  order = 10 },
            { key = "microMenu", label = ns.L["Micro Menu"],  order = 11 },
            { key = "bagBar",    label = ns.L["Bag Bar"],     order = 12 },
        }

        local DB_KEY_MAP = {
            petBar = "pet", stanceBar = "stance",
            microMenu = "microbar", bagBar = "bags",
        }

        -- Master action bars element — module on/off lives in Module Addons
        -- (addon state); positioning only here
        um:RegisterElement({
            key = "actionBars",
            label = ns.L["Action Bars"],
            group = ns.L["Action Bars"],
            order = -1,
            isOwned = true,
            noHandle = true,
            getFrame = function()
                return ActionBarsOwned.containers and ActionBarsOwned.containers["bar1"]
            end,
        })

        -- Leave Vehicle button — standalone proxy mover (not part of the bar loop)
        um:RegisterElement({
            key = "leaveVehicle",
            label = ns.L["Leave Vehicle"],
            group = ns.L["Action Bars"],
            order = 13,
            getFrame = function()
                return _G.MainMenuBarVehicleLeaveButton
            end,
        })

        for _, info in ipairs(BAR_ELEMENTS) do
            local dbKey = DB_KEY_MAP[info.key] or info.key
            local containerKey = dbKey
            um:RegisterElement({
                key = info.key,
                label = info.label,
                group = ns.L["Action Bars"],
                order = info.order,
                isOwned = true,
                isEnabled = function()
                    local barDB = GetBarSettings(dbKey)
                    return barDB and barDB.enabled ~= false
                end,
                setEnabled = function(val)
                    local barDB = GetBarSettings(dbKey)
                    if not barDB then return end
                    local old = barDB.enabled ~= false
                    barDB.enabled = val
                    local container = ActionBarsOwned.containers and ActionBarsOwned.containers[containerKey]
                    if container then
                        container:SetAttribute("qui-user-shown", val and true or false)
                        if val then
                            container:Show()
                        else
                            if ActionBarsOwned.HideOwnedFlyout then
                                ActionBarsOwned.HideOwnedFlyout()
                            end
                            container:Hide()
                        end
                    end
                    if (val ~= false) ~= old then
                        local QUI = _G.QUI
                        local GUI = QUI and QUI.GUI
                        if GUI and GUI.ShowConfirmation then
                            GUI:ShowConfirmation({
                                title = ns.L["Reload UI?"],
                                message = ns.L["Enabling or disabling an action bar requires a UI reload to fully take effect."],
                                acceptText = ns.L["Reload"],
                                cancelText = ns.L["Later"],
                                onAccept = function() QUI:SafeReload() end,
                            })
                        end
                    end
                end,
                getFrame = function()
                    local owned = ActionBarsOwned.containers and ActionBarsOwned.containers[containerKey]
                    if owned then return owned end
                    local BLIZZARD_FRAMES = {
                        bar1 = "MainActionBar", bar2 = "MultiBarBottomLeft",
                        bar3 = "MultiBarBottomRight", bar4 = "MultiBarRight",
                        bar5 = "MultiBarLeft", bar6 = "MultiBar5",
                        bar7 = "MultiBar6", bar8 = "MultiBar7",
                        petBar = "PetActionBar", stanceBar = "StanceBar",
                        microMenu = "MicroMenuContainer", bagBar = "BagsBar",
                    }
                    return _G[BLIZZARD_FRAMES[info.key]]
                end,
                setGameplayHidden = function(hide)
                    local container = ActionBarsOwned.containers and ActionBarsOwned.containers[containerKey]
                    if not container then return end
                    container:SetAttribute("qui-user-shown", (not hide) and true or false)
                    if hide then
                        if ActionBarsOwned.HideOwnedFlyout then
                            ActionBarsOwned.HideOwnedFlyout()
                        end
                        container:Hide()
                    else
                        container:Show()
                    end
                end,
                onOpen = function()
                    SetEditOverlayVisible(containerKey, true)
                end,
                onClose = function()
                    SetEditOverlayVisible(containerKey, false)
                end,
            })
        end
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end
