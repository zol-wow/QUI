local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

env.__declared.UpdatePetBarVisibility = true
env.__declared.UpdateStanceBarLayout = true

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
            if btn.StartFlash then btn:StartFlash() end
            local ct = btn:GetCheckedTexture()
            if ct then ct:SetAlpha(0.5) end
        else
            if btn.StopFlash then btn:StopFlash() end
            local ct = btn:GetCheckedTexture()
            if ct then ct:SetAlpha(1.0) end
        end
        btn:SetChecked(true)
    else
        if btn.StopFlash then btn:StopFlash() end
        btn:SetChecked(false)
    end
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
        if spellID and C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
            and C_SpellActivationOverlay.IsSpellOverlayed(spellID) then
            btn.SpellHighlightTexture:Show()
        else
            btn.SpellHighlightTexture:Hide()
        end
    end
    local cooldown = btn.cooldown
    if cooldown and GetPetActionCooldown then
        local start, duration, enable = GetPetActionCooldown(id)
        if CooldownFrame_Set then
            ns.SafeCall("sink-forward", CooldownFrame_Set, cooldown, start, duration, enable)
        end
    end
end

function ActionBarsOwned.UpdateAllPetButtons()
    local petBtns = ActionBarsOwned.nativeButtons["pet"]
    if not petBtns then return end
    for _, btn in ipairs(petBtns) do
        ActionBarsOwned.UpdatePetButton(btn)
    end
end

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
            ns.SafeCall("sink-forward", CooldownFrame_Set, cooldown, start, duration, enable)
        end
    end
end

function ActionBarsOwned.UpdateAllStanceButtons()
    local stanceBtns = ActionBarsOwned.nativeButtons["stance"]
    if not stanceBtns then return end
    for _, btn in ipairs(stanceBtns) do
        ActionBarsOwned.UpdateStanceButton(btn)
    end
end

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

    ActionBarsOwned.UpdateAllPetButtons()
    if not InCombatLockdown() then
        LayoutNativeButtons("pet")
    else
        ActionBarsOwned.pendingPetUpdate = true
    end
    SetupOwnedBarMouseover("pet")
    if _G.QUI_RefreshActionBarsVisibility then
        _G.QUI_RefreshActionBarsVisibility()
    end
    local isShown = container:IsShown()
    if wasShown ~= isShown and _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("petBar")
    end
end

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

    ActionBarsOwned.UpdateAllStanceButtons()

    local layout = barDB and barDB.ownedLayout
    if layout then
        local savedIconCount = layout.iconCount
        layout.iconCount = math.min(layout.iconCount or 10, numForms)
        LayoutNativeButtons("stance")
        layout.iconCount = savedIconCount
    else
        LayoutNativeButtons("stance")
    end

    SetupOwnedBarMouseover("stance")
    if _G.QUI_RefreshActionBarsVisibility then
        _G.QUI_RefreshActionBarsVisibility()
    end

    if not wasShown and _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("stanceBar")
    end
end

ownedEventFrame = CreateFrame("Frame")

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
    ApplyAllOverrideBindings()
end

env.__declared.InitializeExtraButtons = true
env.__declared.RefreshExtraButtons = true
env.__declared.ApplyPageArrowVisibility = true
