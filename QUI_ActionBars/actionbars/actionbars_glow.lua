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
    local action = GetSafeActionSlot(button)
    if not action then return nil end
    if not HasAction(action) then return nil end

    local ok, actionType, id, subType = ns.SafeCall("best-effort-style", GetActionInfo, action)
    if not ok then return nil end

    if actionType == "spell" then
        return id
    elseif actionType == "macro" then
        if subType == "spell" then
            return id
        end
        if GetMacroSpell then
            local macroOk, spellId = ns.SafeCall("best-effort-style", GetMacroSpell, id)
            if macroOk and spellId then return spellId end
        end
    end
    return nil
end

function ForEachSpellCandidate(spellId, callback)
    if not spellId or not callback then return end
    spellId = Helpers.SafeValue(spellId, nil)
    if not spellId then return end

    callback(spellId)

    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideId = ns.SafeCall("best-effort-style", C_Spell.GetOverrideSpell, spellId)
        overrideId = ok and Helpers.SafeValue(overrideId, nil) or nil
        if ok and overrideId and overrideId ~= spellId then
            callback(overrideId)
        end
    end
end

function ButtonFlyoutContainsSpell(button, spellId)
    local action = GetSafeActionSlot(button)
    if not action then return false end
    local ok, actionType, id = ns.SafeCall("best-effort-style", GetActionInfo, action)
    if not ok or actionType ~= "flyout" then return false end
    if FlyoutHasSpell then
        local fok, has = ns.SafeCall("best-effort-style", FlyoutHasSpell, id, spellId)
        if fok and has then return true end
    end
    return false
end

spellIdToButtons = {}
flyoutButtons = {}
spellIdButtonListPool = {}
spellIdMapDirty = true
local spellIdMapStats
local function SetupDebugInstrumentation()
    spellIdMapStats = { rebuilds = 0, dirtyMarks = 0, ensures = 0 }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AB_spellIdToButtons", tbl = spellIdToButtons }
    mp[#mp + 1] = { name = "AB_flyoutButtons",    tbl = flyoutButtons }
    mp[#mp + 1] = { name = "AB_spellIdListPool",  tbl = spellIdButtonListPool }
    mp[#mp + 1] = { name = "AB_spellIdMapRebuilds", counter = true, fn = function() return spellIdMapStats.rebuilds end }
    mp[#mp + 1] = { name = "AB_spellIdMapDirtyMarks", counter = true, fn = function() return spellIdMapStats.dirtyMarks end }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

function AcquireSpellButtonList()
    return table.remove(spellIdButtonListPool) or {}
end

function ClearSpellIdMap()
    for _, list in pairs(spellIdToButtons) do
        wipe(list)
        if #spellIdButtonListPool < 160 then
            spellIdButtonListPool[#spellIdButtonListPool + 1] = list
        end
    end
    wipe(spellIdToButtons)
end

function RebuildSpellIdMap()
    ClearSpellIdMap()
    wipe(flyoutButtons)
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                    local spellId = GetButtonSpellId(btn)
                    if spellId then
                        ForEachSpellCandidate(spellId, function(candidateId)
                            local list = spellIdToButtons[candidateId]
                            if not list then
                                list = AcquireSpellButtonList()
                                spellIdToButtons[candidateId] = list
                            end
                            list[#list + 1] = btn
                        end)
                    else
                        local action = GetSafeActionSlot(btn)
                        if action and HasAction(action) then
                            local ok, actionType = ns.SafeCall("best-effort-style", GetActionInfo, action)
                            if ok and actionType == "flyout" then
                                flyoutButtons[#flyoutButtons + 1] = btn
                            end
                        end
                    end
                end
            end
        end
    end
    spellIdMapDirty = false
    if spellIdMapStats then spellIdMapStats.rebuilds = spellIdMapStats.rebuilds + 1 end
end

MarkSpellIdMapDirty = function()
    if not spellIdMapDirty then
        if spellIdMapStats then spellIdMapStats.dirtyMarks = spellIdMapStats.dirtyMarks + 1 end
    end
    spellIdMapDirty = true
end

function EnsureSpellIdMap()
    if spellIdMapStats then spellIdMapStats.ensures = spellIdMapStats.ensures + 1 end
    if spellIdMapDirty then
        RebuildSpellIdMap()
    end
end

function ShowActionButtonGlow(button)
    local IconGlow = ns.IconGlow
    if not IconGlow then return end
    local state = GetFrameState(button)
    if state.quiProcGlow then return end
    state.quiProcGlow = true
    IconGlow.Start(button, ActionBarGlowOpts(nil))
end

function HideActionButtonGlow(button)
    local IconGlow = ns.IconGlow
    if not IconGlow then return end
    local state = GetFrameState(button)
    if not state.quiProcGlow then return end
    state.quiProcGlow = false
    IconGlow.Stop(button)
end

function ActionBarsOwned.UpdateOverlayGlow(button)
    local spellId = GetButtonSpellId(button)
    if spellId then
        local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
            or _G.IsSpellOverlayed
        if IsSpellOverlayed then
            local overlayed = false
            ForEachSpellCandidate(spellId, function(candidateId)
                if overlayed then return end
                local ok, result = ns.SafeCall("best-effort-style", IsSpellOverlayed, candidateId)
                if ok and result then
                    overlayed = true
                end
            end)
            if overlayed then
                ShowActionButtonGlow(button)
                return
            end
        end
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
    local slotMap = ActionBarsOwned.slotMap
    if not slotMap then return end
    for _, slot in ipairs(slots) do
        local entry = slotMap[slot]
        if entry and entry.button then
            UpdateAssistedCombatRotationFrame(entry.button)
            if _assistRotationButton then return end
        end
    end
end

assistedHighlightButtons = {}
_assistHighlightScratch = {}
ASSISTED_HIGHLIGHT_COLOR = { 0.2, 0.82, 0.6, 1 }

function SetAssistedHighlightShown(button, show)
    local IconGlow = ns.IconGlow
    if not IconGlow then return end
    local state = GetFrameState(button)
    if show then
        if state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = true
        IconGlow.Start(button, ActionBarGlowOpts(ASSISTED_HIGHLIGHT_COLOR))
    else
        if not state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = false
        IconGlow.Stop(button)
    end
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
        local slots = C_ActionBar.FindSpellActionButtons(nextSpellID)
        if slots then
            local slotMap = ActionBarsOwned.slotMap
            if slotMap then
                for _, slot in ipairs(slots) do
                    local entry = slotMap[slot]
                    if entry and entry.button then
                        matchButtons[entry.button] = true
                    end
                end
            end
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
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                    ActionBarsOwned.UpdateOverlayGlow(btn)
                end
            end
        end
    end
end

spellGlowVisited = {}
function ForEachButtonForSpellGlow(spellId, callback)
    if not spellId or not callback then return false end
    EnsureSpellIdMap()

    local matched = false
    local visited = spellGlowVisited
    wipe(visited)
    local slotMap = ActionBarsOwned.slotMap

    local function VisitButton(button)
        if button and not visited[button] then
            visited[button] = true
            matched = true
            callback(button)
        end
    end

    ForEachSpellCandidate(spellId, function(candidateId)
        local btns = spellIdToButtons[candidateId]
        if btns then
            for _, btn in ipairs(btns) do
                VisitButton(btn)
            end
        end

        for _, btn in ipairs(flyoutButtons) do
            if ButtonFlyoutContainsSpell(btn, candidateId) then
                VisitButton(btn)
            end
        end

        if C_ActionBar and C_ActionBar.FindSpellActionButtons and slotMap then
            local ok, slots = ns.SafeCall("best-effort-style", C_ActionBar.FindSpellActionButtons, candidateId)
            if ok and slots then
                for _, slot in ipairs(slots) do
                    local entry = slotMap[slot]
                    if entry and entry.button then
                        VisitButton(entry.button)
                    end
                end
            end
        end
    end)

    wipe(visited)
    return matched
end

function ActionBarsOwned.OnSpellActivationGlowShow(spellId)
    if not spellId then return end
    if not ForEachButtonForSpellGlow(spellId, ShowActionButtonGlow) then
        ActionBarsOwned.UpdateAllOverlayGlows()
    end
end

function ActionBarsOwned.OnSpellActivationGlowHide(spellId)
    if not spellId then return end
    if not ForEachButtonForSpellGlow(spellId, HideActionButtonGlow) then
        ActionBarsOwned.UpdateAllOverlayGlows()
    end
end

ActionBarsOwned.RebuildSpellIdMap = RebuildSpellIdMap
ActionBarsOwned.MarkSpellIdMapDirty = MarkSpellIdMapDirty
ActionBarsOwned.EnsureSpellIdMap = EnsureSpellIdMap
ActionBarsOwned.GetSpellIdMapStats = function() return spellIdMapStats end
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

    if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
end

function ActionBarsOwned.ForceFullVisualRescan()
    _visualFirstRunDone = false
    if ResetAllChargeCapabilityCaches then
        ResetAllChargeCapabilityCaches()
    end
    if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
end
