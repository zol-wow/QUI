local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

do

LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local _glowOpts = {}
local _glowThemeColor = {}
local function ActionBarGlowOpts(overrideColor)
    local db = GetDB()
    local g = db and db.global or nil
    _glowOpts.source    = (g and g.glowSource)    or "QUI"
    _glowOpts.style     = (g and g.glowStyle)     or "Button"
    local color = overrideColor
    if not color and g then
        if g.glowColorSource == "custom" then
            color = g.glowColor
        else
            local r, gg, b
            if Helpers and Helpers.GetSkinAccentColor then
                r, gg, b = Helpers.GetSkinAccentColor()
            end
            if r then
                _glowThemeColor[1], _glowThemeColor[2], _glowThemeColor[3], _glowThemeColor[4] = r, gg, b, 1
                color = _glowThemeColor
            else
                color = g.glowColor
            end
        end
    end
    _glowOpts.color     = color
    _glowOpts.lines     = g and g.glowLines or nil
    _glowOpts.frequency = g and g.glowFrequency or nil
    _glowOpts.length    = (g and g.glowLength and g.glowLength > 0) and g.glowLength or nil
    _glowOpts.thickness = g and g.glowThickness or nil
    _glowOpts.particles = g and g.glowParticles or nil
    _glowOpts.scale     = g and g.glowScale or nil
    return _glowOpts
end

function GetButtonSpellId(button)
    local action = GetSafeActionSlot(button, true)
    if not action then return nil end
    if not HasAction(action) then return nil end

    local ok, actionType, id, subType = ns.SafeCall("best-effort-style", GetActionInfo, action)
    if not ok then return nil end
    actionType = Helpers.SafeValue(actionType, nil)
    id = Helpers.SafeValue(id, nil)
    subType = Helpers.SafeValue(subType, nil)

    if actionType == "spell" then
        return type(id) == "number" and id or nil
    elseif actionType == "macro" then
        if subType == "spell" then
            return type(id) == "number" and id or nil
        end
        if GetMacroSpell and type(id) == "number" then
            local macroOk, spellId = ns.SafeCall("best-effort-style", GetMacroSpell, id)
            spellId = macroOk and Helpers.SafeValue(spellId, nil) or nil
            if type(spellId) == "number" then return spellId end
        end
    end
    return nil
end

function ButtonFlyoutContainsSpell(button, spellId)
    spellId = Helpers.SafeValue(spellId, nil)
    if type(spellId) ~= "number" then return false end
    local action = GetSafeActionSlot(button, true)
    if not action then return false end
    local ok, actionType, id = ns.SafeCall("best-effort-style", GetActionInfo, action)
    actionType = ok and Helpers.SafeValue(actionType, nil) or nil
    id = ok and Helpers.SafeValue(id, nil) or nil
    if actionType ~= "flyout" or type(id) ~= "number" then return false end
    if type(FlyoutHasSpell) == "function" then
        local fok, has = ns.SafeCall("best-effort-style", FlyoutHasSpell, id, spellId)
        has = fok and Helpers.SafeValue(has, false) or false
        if has then return true end
    end
    return false
end

local function ForEachStandardButton(callback)
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                callback(btn, barKey)
            end
        end
    end
end

local function IsSpellOverlayed(spellId)
    local query = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
        or _G.IsSpellOverlayed
    if not query or type(spellId) ~= "number" then return false end
    local ok, result = ns.SafeCall("best-effort-style", query, spellId)
    result = ok and Helpers.SafeValue(result, false) or false
    return result and true or false
end

local function IsButtonFlyoutOverlayed(button, ignoredSpellId)
    local action = GetSafeActionSlot(button, true)
    if not action then return false end
    local ok, actionType, flyoutId = ns.SafeCall("best-effort-style", GetActionInfo, action)
    actionType = ok and Helpers.SafeValue(actionType, nil) or nil
    flyoutId = ok and Helpers.SafeValue(flyoutId, nil) or nil
    if actionType ~= "flyout" or type(flyoutId) ~= "number" then return false end

    local infoOk, _, _, numSlots = ns.SafeCall("best-effort-style", GetFlyoutInfo, flyoutId)
    numSlots = infoOk and Helpers.SafeValue(numSlots, nil) or nil
    if type(numSlots) ~= "number" then return false end

    for slot = 1, numSlots do
        local slotOk, baseId, overrideId = ns.SafeCall("best-effort-style", GetFlyoutSlotInfo, flyoutId, slot)
        baseId = slotOk and Helpers.SafeValue(baseId, nil) or nil
        overrideId = slotOk and Helpers.SafeValue(overrideId, nil) or nil
        local currentId = type(overrideId) == "number" and overrideId or baseId
        if type(currentId) == "number"
            and (not ignoredSpellId or currentId ~= ignoredSpellId)
            and IsSpellOverlayed(currentId) then
            return true
        end
    end
    return false
end

local function RefreshActionButtonGlow(button)
    local IconGlow = ns.IconGlow
    if not IconGlow then return end
    local state = GetFrameState(button)
    if state.quiAssistedHighlight then
        IconGlow.Start(button, ActionBarGlowOpts(ASSISTED_HIGHLIGHT_COLOR))
    elseif state.quiProcGlow then
        IconGlow.Start(button, ActionBarGlowOpts(nil))
    else
        IconGlow.Stop(button)
    end
end

function ShowActionButtonGlow(button)
    local state = GetFrameState(button)
    state.quiProcGlow = true
    RefreshActionButtonGlow(button)
end

function HideActionButtonGlow(button)
    local state = GetFrameState(button)
    if not state.quiProcGlow then return end
    state.quiProcGlow = false
    RefreshActionButtonGlow(button)
end

function ActionBarsOwned.UpdateOverlayGlow(button)
    local spellId = GetButtonSpellId(button)
    if (spellId and IsSpellOverlayed(spellId)) or IsButtonFlyoutOverlayed(button) then
        ShowActionButtonGlow(button)
        return
    end
    HideActionButtonGlow(button)
end

ActionBarsOwned.spellHighlight = { type = nil, id = nil }

function UpdateSpellHighlight(button)
    local spellHighlight = ActionBarsOwned.spellHighlight
    local shown = false
    if spellHighlight.type == "spell" then
        local btnSpellId = GetButtonSpellId(button)
        if btnSpellId and btnSpellId == spellHighlight.id then
            shown = true
        end
    elseif spellHighlight.type == "flyout" then
        local action = GetSafeActionSlot(button)
        if action then
            local ok, actionType, actionId = ns.SafeCall("best-effort-style", GetActionInfo, action)
            if ok and actionType == "flyout" and actionId == spellHighlight.id then
                shown = true
            end
        end
    end

    if shown then
        if button.SpellHighlightTexture then
            button.SpellHighlightTexture:Show()
        end
        if button.SpellHighlightAnim then
            button.SpellHighlightAnim:Play()
        end
    else
        if button.SpellHighlightTexture then
            button.SpellHighlightTexture:Hide()
        end
        if button.SpellHighlightAnim then
            button.SpellHighlightAnim:Stop()
        end
    end
end

function UpdateAllSpellHighlights()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                UpdateSpellHighlight(btn)
            end
        end
    end
end

ActionBarsOwned._assistedCombatEverActive = false

_assistRotationButton = nil

local assistTicker, assistTickerRate

local function StopAssistTicker()
    if assistTicker then
        assistTicker:Cancel()
        assistTicker = nil
        assistTickerRate = nil
    end
end

local function AssistTickRate()
    local manager = _G.AssistedCombatManager
    local rate = manager and manager.GetUpdateRate and manager:GetUpdateRate()
    if type(rate) ~= "number" or rate <= 0 then return 0.2 end
    return rate
end

local function AssistTick()
    local button = _assistRotationButton
    if not button then
        StopAssistTicker()
        return
    end
    local slot = GetSafeActionSlot(button)
    if not slot then return end
    if C_ActionBar.ForceUpdateAction then
        C_ActionBar.ForceUpdateAction(slot, true)
    end
    ns.SafeCall("best-effort-style", ActionBarsOwned.SafeUpdate, button)
end

local function ArmAssistTicker()
    local rate = AssistTickRate()
    if assistTicker and assistTickerRate == rate then return end
    StopAssistTicker()
    assistTickerRate = rate
    assistTicker = C_Timer.NewTicker(rate, AssistTick)
end

UpdateAssistedCombatRotationFrame = function(button)
    if not (C_ActionBar and C_ActionBar.IsAssistedCombatAction) then return end
    local frame = button.AssistedCombatRotationFrame
    if not ActionBarsOwned._assistedCombatEverActive and not frame then return end

    local action = GetSafeActionSlot(button)
    local show = false
    local hasAction = action and HasAction(action)
    if hasAction then
        show = C_ActionBar.IsAssistedCombatAction(action)
    end

    if show and not frame then
        ActionBarsOwned._assistedCombatEverActive = true
        frame = CreateFrame("Frame", nil, button, "ActionBarButtonAssistedCombatRotationTemplate")
        button.AssistedCombatRotationFrame = frame
        frame:SetFrameLevel(button:GetFrameLevel() + 5)
    end
    if frame then
        if frame:GetScript("OnUpdate") then
            frame:SetScript("OnUpdate", nil)
        end
        frame:UpdateState()
        frame:SetFrameLevel(button:GetFrameLevel() + 5)
    end
    if show then
        _assistRotationButton = button
        ArmAssistTicker()
    elseif button == _assistRotationButton then
        _assistRotationButton = nil
        StopAssistTicker()
    end
    return show
end

function UpdateAllAssistedCombatRotation()
    if _assistRotationButton then
        UpdateAssistedCombatRotationFrame(_assistRotationButton)
        return
    end

    if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
        and C_ActionBar and C_ActionBar.FindSpellActionButtons) then
        return
    end
    local ok, spellID = ns.SafeCall("best-effort-style", C_AssistedCombat.GetNextCastSpell, false)
    if not ok or not spellID then return end
    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if not slots then return end
    for _, slot in ipairs(slots) do
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local buttons = ActionBarsOwned.nativeButtons[barKey]
            if buttons then
                for _, button in ipairs(buttons) do
                    if GetSafeActionSlot(button) == slot then
                        UpdateAssistedCombatRotationFrame(button)
                        if _assistRotationButton then return end
                    end
                end
            end
        end
    end
end

assistedHighlightButtons = {}
_assistHighlightScratch = {}
_assistSlotScratch = {}
ASSISTED_HIGHLIGHT_COLOR = { 0.2, 0.82, 0.6, 1 }

function SetAssistedHighlightShown(button, show)
    local state = GetFrameState(button)
    if show then
        if state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = true
    else
        if not state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = false
    end
    RefreshActionButtonGlow(button)
end

UpdateAllAssistedHighlights = function()
    if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return end
    if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return end

    local db = GetDB()
    if not (db and db.global and db.global.assistedHighlight) then
        for btn in pairs(assistedHighlightButtons) do
            SetAssistedHighlightShown(btn, false)
        end
        wipe(assistedHighlightButtons)
        return
    end

    local okNext, nextSpellID = ns.SafeCall("best-effort-style", C_AssistedCombat.GetNextCastSpell, false)
    if not okNext then nextSpellID = nil end

    local matchButtons = _assistHighlightScratch
    wipe(matchButtons)
    if nextSpellID then
        local okSlots, slots = ns.SafeCall("best-effort-style", C_ActionBar.FindSpellActionButtons, nextSpellID)
        slots = okSlots and slots or nil
        if slots then
            local slotSet = _assistSlotScratch
            wipe(slotSet)
            for _, slot in ipairs(slots) do
                slot = Helpers.SafeValue(slot, nil)
                if type(slot) == "number" then slotSet[slot] = true end
            end
            for _, barKey in ipairs(STANDARD_BAR_KEYS) do
                local buttons = ActionBarsOwned.nativeButtons[barKey]
                if buttons then
                    for _, button in ipairs(buttons) do
                        local slot = GetSafeActionSlot(button)
                        if slot and slotSet[slot] then
                            matchButtons[button] = true
                        end
                    end
                end
            end
            wipe(slotSet)
        end
    end

    for btn in pairs(assistedHighlightButtons) do
        if not matchButtons[btn] then
            SetAssistedHighlightShown(btn, false)
        end
    end

    for btn in pairs(matchButtons) do
        SetAssistedHighlightShown(btn, true)
    end

    _assistHighlightScratch = assistedHighlightButtons
    wipe(_assistHighlightScratch)
    assistedHighlightButtons = matchButtons
end

function ActionBarsOwned.UpdateAllOverlayGlows()
    ForEachStandardButton(ActionBarsOwned.UpdateOverlayGlow)
end

function ActionBarsOwned.OnSpellActivationGlowShow(spellId)
    spellId = Helpers.SafeValue(spellId, nil)
    if type(spellId) ~= "number" then
        ActionBarsOwned.UpdateAllOverlayGlows()
        return
    end
    ForEachStandardButton(function(button)
        if GetButtonSpellId(button) == spellId or ButtonFlyoutContainsSpell(button, spellId) then
            ShowActionButtonGlow(button)
        end
    end)
end

function ActionBarsOwned.OnSpellActivationGlowHide(spellId)
    spellId = Helpers.SafeValue(spellId, nil)
    if type(spellId) ~= "number" then
        ActionBarsOwned.UpdateAllOverlayGlows()
        return
    end
    ForEachStandardButton(function(button)
        if GetButtonSpellId(button) == spellId then
            HideActionButtonGlow(button)
        elseif ButtonFlyoutContainsSpell(button, spellId) then
            if IsButtonFlyoutOverlayed(button, spellId) then
                ShowActionButtonGlow(button)
            else
                HideActionButtonGlow(button)
            end
        elseif GetFrameState(button).quiProcGlow then
            ActionBarsOwned.UpdateOverlayGlow(button)
        end
    end)
end

ActionBarsOwned.UpdateAllSpellHighlights = UpdateAllSpellHighlights
ActionBarsOwned.ShowActionButtonGlow = ShowActionButtonGlow
ActionBarsOwned.HideActionButtonGlow = HideActionButtonGlow
ActionBarsOwned.UpdateAllAssistedCombatRotation = UpdateAllAssistedCombatRotation
ActionBarsOwned.UpdateAllAssistedHighlights = function() UpdateAllAssistedHighlights() end

end

_lastStateUpdateTime = 0
function ActionBarsOwned.UpdateAllButtonStates()
    local now = GetTime()
    if now == _lastStateUpdateTime then return end
    _lastStateUpdateTime = now

    for btn in pairs(ActionBarsOwned._activeButtons) do
        local action = GetSafeActionSlot(btn)
        if action then
            if IsCurrentAction(action) or IsAutoRepeatAction(action) then
                btn:SetChecked(true)
            else
                btn:SetChecked(false)
            end
        end
    end
end

_lastCountUpdateTime = 0
function ActionBarsOwned.UpdateAllButtonCounts()
    local now = GetTime()
    if now == _lastCountUpdateTime then return end
    _lastCountUpdateTime = now

    for btn in pairs(ActionBarsOwned._activeButtons) do
        ns.SafeCallMethodIfPresent("best-effort-style", btn, "UpdateCount")
    end
end

_lastVisualUpdateTime = 0
_visualFirstRunDone = false
function ActionBarsOwned.UpdateAllButtonVisuals()
    local now = GetTime()
    if now == _lastVisualUpdateTime then return end
    _lastVisualUpdateTime = now

    if not _visualFirstRunDone then
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                        local action = GetSafeActionSlot(btn)
                        if action and HasAction(action) then
                            local state = GetFrameState(btn)
                            state.wasEmpty = false
                            ns.SafeCall("best-effort-style", ActionBarsOwned.SafeUpdate, btn)
                        else
                            local state = GetFrameState(btn)
                            if not state.wasEmpty then
                                state.wasEmpty = true
                                ns.SafeCall("best-effort-style", ActionBarsOwned.SafeUpdate, btn)
                            end
                        end
                    else
                        ActionBarsOwned._activeButtons[btn] = nil
                        ActionBarsOwned._activeStandardButtons[btn] = nil
                    end
                end
            end
        end
        _visualFirstRunDone = true
    else
        for btn in pairs(ActionBarsOwned._activeButtons) do
            local barKey = btn._quiBarKey
            if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                local state = GetFrameState(btn)
                state.wasEmpty = false
                ns.SafeCall("best-effort-style", ActionBarsOwned.SafeUpdate, btn)
            else
                ActionBarsOwned._activeButtons[btn] = nil
                ActionBarsOwned._activeStandardButtons[btn] = nil
            end
        end
    end

end

function ActionBarsOwned.ForceFullVisualRescan()
    _visualFirstRunDone = false
    if ResetAllChargeCapabilityCaches then
        ResetAllChargeCapabilityCaches()
    end
end
