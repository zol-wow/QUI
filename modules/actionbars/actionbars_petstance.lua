local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- PET/STANCE BAR HELPERS
---------------------------------------------------------------------------

-- Forward declarations (defined here, referenced in event handler and Initialize)
env.__declared.UpdatePetBarVisibility = true
env.__declared.UpdateStanceBarLayout = true

-- Update a single QUI pet button's icon and state.
-- PetActionBarMixin:Update() on the original bar is suppressed (bar is hidden
-- with events unregistered), so QUI must drive pet button visuals directly.
-- Stored on ActionBarsOwned to avoid consuming a file-level local slot.
function ActionBarsOwned.UpdatePetButton(btn)
    local id = btn:GetID()
    if not id or id < 1 then return end
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(id)
    local icon = btn.icon
    if icon then
        if texture then
            icon:SetTexture(isToken and _G[texture] or texture)
            if GetPetActionSlotUsable and GetPetActionSlotUsable(id) then
                icon:SetVertexColor(1, 1, 1)
            else
                icon:SetVertexColor(0.4, 0.4, 0.4)
            end
            icon:Show()
        else
            icon:Hide()
        end
    end
    if isActive then
        if IsPetAttackAction and IsPetAttackAction(id) then
            -- Pet Attack: flash + subtle checked highlight
            if btn.StartFlash then btn:StartFlash() end
            local ct = btn:GetCheckedTexture()
            if ct then ct:SetAlpha(0.5) end
        else
            -- Stance/ability active: full checked highlight
            if btn.StopFlash then btn:StopFlash() end
            local ct = btn:GetCheckedTexture()
            if ct then ct:SetAlpha(1.0) end
        end
        btn:SetChecked(true)
    else
        if btn.StopFlash then btn:StopFlash() end
        btn:SetChecked(false)
    end
    -- Orange active-stance border (Assist/Defensive/Passive indicator)
    local isPetAttack = IsPetAttackAction and IsPetAttackAction(id)
    local showOrangeBorder = isActive and not isPetAttack
    if showOrangeBorder then
        if not btn.QUI_ActiveBorder then
            btn.QUI_ActiveBorder = btn:CreateTexture(nil, "OVERLAY", nil, 3)
            btn.QUI_ActiveBorder:SetTexture(TEXTURES.normal)
            btn.QUI_ActiveBorder:SetAllPoints(btn)
        end
        btn.QUI_ActiveBorder:SetVertexColor(1.0, 0.6, 0.0, 1.0)
        btn.QUI_ActiveBorder:Show()
    elseif btn.QUI_ActiveBorder then
        btn.QUI_ActiveBorder:Hide()
    end
    if btn.AutoCastOverlay then
        btn.AutoCastOverlay:SetShown(autoCastAllowed and true or false)
        btn.AutoCastOverlay:ShowAutoCastEnabled(autoCastEnabled and true or false)
    end
    if btn.SpellHighlightTexture then
        if spellID and C_Spell and C_Spell.IsSpellOverlayed and C_Spell.IsSpellOverlayed(spellID) then
            btn.SpellHighlightTexture:Show()
        else
            btn.SpellHighlightTexture:Hide()
        end
    end
    -- Cooldown (also bar-driven in Blizzard code).  GetPetActionCooldown values
    -- flow directly to the C-side; pcall guards against secret-value rejection.
    local cooldown = btn.cooldown
    if cooldown and GetPetActionCooldown then
        local start, duration, enable = GetPetActionCooldown(id)
        if CooldownFrame_Set then
            pcall(CooldownFrame_Set, cooldown, start, duration, enable)
        end
    end
end

-- Update all QUI pet buttons' visuals.
function ActionBarsOwned.UpdateAllPetButtons()
    local petBtns = ActionBarsOwned.nativeButtons["pet"]
    if not petBtns then return end
    for _, btn in ipairs(petBtns) do
        ActionBarsOwned.UpdatePetButton(btn)
    end
end

-- Update a single QUI stance button's icon and state.
-- Same pattern as pet: the bar-level Update is suppressed, so QUI
-- drives stance button visuals directly via GetShapeshiftFormInfo.
function ActionBarsOwned.UpdateStanceButton(btn)
    local id = btn:GetID()
    if not id or id < 1 then return end
    local texture, isActive, isCastable, spellID = GetShapeshiftFormInfo(id)
    local icon = btn.icon
    if icon then
        if texture then
            icon:SetTexture(texture)
            if isCastable then
                icon:SetVertexColor(1, 1, 1)
            else
                icon:SetVertexColor(0.4, 0.4, 0.4)
            end
            icon:Show()
        else
            icon:Hide()
        end
    end
    if isActive then
        btn:SetChecked(true)
    else
        btn:SetChecked(false)
    end
    local cooldown = btn.cooldown
    if cooldown and GetShapeshiftFormCooldown then
        local start, duration, enable = GetShapeshiftFormCooldown(id)
        if CooldownFrame_Set then
            pcall(CooldownFrame_Set, cooldown, start, duration, enable)
        end
    end
end

-- Update all QUI stance buttons' visuals.
function ActionBarsOwned.UpdateAllStanceButtons()
    local stanceBtns = ActionBarsOwned.nativeButtons["stance"]
    if not stanceBtns then return end
    for _, btn in ipairs(stanceBtns) do
        ActionBarsOwned.UpdateStanceButton(btn)
    end
end

-- Update pet bar container visibility based on whether the player has an active pet bar.
-- PetActionBar events are unregistered (we took ownership), so we drive visibility ourselves.
UpdatePetBarVisibility = function()
    local container = ActionBarsOwned.containers["pet"]
    if not container then return end

    local wasShown = container:IsShown()

    local barDB = GetBarSettings("pet")
    if barDB and barDB.enabled == false then
        SetBarContainerShown(container, false)
        if _G.QUI_UpdateFramesAnchoredTo then _G.QUI_UpdateFramesAnchoredTo("petBar") end
        return
    end

    -- The pet container's state driver includes [nopet], so the secure
    -- snippet flips Show/Hide automatically as pet status changes (works
    -- in combat without any tainted Lua). qui-user-shown is set to true
    -- at container creation and only flipped when the bar is disabled
    -- via SetBarContainerShown (above), so no SetAttribute is needed
    -- here — which is critical because SetAttribute on a frame with a
    -- registered state driver is protected during combat.
    --
    -- Populate pet button icons/state (PetActionBarMixin:Update on the
    -- original bar is suppressed, so QUI drives visuals directly).
    ActionBarsOwned.UpdateAllPetButtons()
    -- Re-layout buttons only out of combat. SecureLayoutBar writes to the
    -- shared QUI_ActionBarLayoutHandler, whose SetAttribute is protected
    -- during combat (it has an _onattributechanged secure snippet). The
    -- layout from the previous PLAYER_ENTERING_WORLD pass still applies
    -- when the [nopet] driver shows the container mid-combat — buttons
    -- are positioned and sized correctly without re-running layout.
    if not InCombatLockdown() then
        LayoutNativeButtons("pet")
    else
        ActionBarsOwned.pendingPetUpdate = true
    end
    -- Re-evaluate mouseover fade so alwaysShow / fade alpha are correct
    SetupOwnedBarMouseover("pet")
    -- Let the HUD visibility system re-assert its fade state so mounting
    -- / flying / vehicle hide rules take precedence over the mouseover
    -- fade alpha that SetupOwnedBarMouseover just applied.
    if _G.QUI_RefreshActionBarsVisibility then
        _G.QUI_RefreshActionBarsVisibility()
    end
    -- Notify anchoring system when visibility changed so dependents re-anchor.
    -- The [nopet] state driver may flip Show/Hide asynchronously after this
    -- call, so also schedule a deferred check to catch that transition.
    local isShown = container:IsShown()
    if wasShown ~= isShown and _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("petBar")
    end
end

-- Update stance bar layout: show only the buttons matching GetNumShapeshiftForms().
UpdateStanceBarLayout = function()
    local container = ActionBarsOwned.containers["stance"]
    if not container then return end

    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingStanceUpdate = true
        return
    end

    local barDB = GetBarSettings("stance")
    if barDB and barDB.enabled == false then
        container:SetAttribute("qui-user-shown", false)
        if ActionBarsOwned.HideOwnedFlyout then
            ActionBarsOwned.HideOwnedFlyout()
        end
        container:Hide()
        if _G.QUI_UpdateFramesAnchoredTo then _G.QUI_UpdateFramesAnchoredTo("stanceBar") end
        return
    end

    local wasShown = container:IsShown()
    local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    local buttons = ActionBarsOwned.nativeButtons["stance"]
    if not buttons then return end

    if numForms == 0 then
        if inInitSafeWindow and InCombatLockdown() then
            -- During a combat reload, shapeshift data may not be available
            -- yet at PEW time. Don't hide — defer to PLAYER_REGEN_ENABLED.
            ActionBarsOwned.pendingStanceUpdate = true
            return
        end
        container:SetAttribute("qui-user-shown", false)
        if ActionBarsOwned.HideOwnedFlyout then
            ActionBarsOwned.HideOwnedFlyout()
        end
        container:Hide()
        if wasShown and _G.QUI_UpdateFramesAnchoredTo then
            _G.QUI_UpdateFramesAnchoredTo("stanceBar")
        end
        return
    end

    container:SetAttribute("qui-user-shown", true)
    container:Show()

    -- Populate stance button icons/state (bar-level Update is suppressed).
    ActionBarsOwned.UpdateAllStanceButtons()

    -- Clamp ownedLayout.iconCount to actual form count for layout
    local layout = barDB and barDB.ownedLayout
    if layout then
        -- Temporarily clamp iconCount for the layout pass
        local savedIconCount = layout.iconCount
        layout.iconCount = math.min(layout.iconCount or 10, numForms)
        LayoutNativeButtons("stance")
        layout.iconCount = savedIconCount
    else
        LayoutNativeButtons("stance")
    end

    -- Re-evaluate mouseover fade so alwaysShow / fade alpha are correct
    SetupOwnedBarMouseover("stance")
    -- Let the HUD visibility system re-assert its fade state so mounting
    -- / flying / vehicle hide rules take precedence over the mouseover
    -- fade alpha that SetupOwnedBarMouseover just applied.
    if _G.QUI_RefreshActionBarsVisibility then
        _G.QUI_RefreshActionBarsVisibility()
    end

    -- Notify anchoring system when visibility changed
    if not wasShown and _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("stanceBar")
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

ownedEventFrame = CreateFrame("Frame")

-- Refresh empty slot visibility and skinning for all native buttons
function RefreshAllNativeVisuals()
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local buttons = ActionBarsOwned.nativeButtons[barKey]
        local settings = GetEffectiveSettings(barKey)
        if buttons and settings and SKINNABLE_BAR_KEYS[barKey] then
            for _, btn in ipairs(buttons) do
                SkinButton(btn, settings)
                UpdateButtonText(btn, settings)
                UpdateEmptySlotVisibility(btn, settings)
            end
        end
    end
end

-- Refresh keybind text on all native buttons
function RefreshNativeKeybinds()
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local buttons = ActionBarsOwned.nativeButtons[barKey]
        local settings = GetEffectiveSettings(barKey)
        if buttons and settings then
            for _, btn in ipairs(buttons) do
                UpdateKeybindText(btn, settings)
            end
        end
    end
    -- Refresh all override bindings
    ApplyAllOverrideBindings()
end

-- Forward declaration for extra button functions used in event handler
env.__declared.InitializeExtraButtons = true
env.__declared.RefreshExtraButtons = true
env.__declared.ApplyPageArrowVisibility = true

