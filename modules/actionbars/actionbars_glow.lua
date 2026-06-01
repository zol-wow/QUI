local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- SPELL ACTIVATION OVERLAY GLOW
---------------------------------------------------------------------------
-- Self-managed proc glow system.  Replaces the C-side glow that was
-- previously provided by SetActionUIButton registration.  Driven by
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events.  Uses LibCustomGlow
-- for the visual effect (same library used by CDM glows).
---------------------------------------------------------------------------
do -- spell glow / highlight / assisted rotation

LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Extract the spell ID from an action button's current action.
-- Returns nil for empty slots, items, or if GetActionInfo errors (combat).
function GetButtonSpellId(button)
    local action = button.action
    if not action then return nil end
    if not HasAction(action) then return nil end

    local ok, actionType, id, subType = pcall(GetActionInfo, action)
    if not ok then return nil end

    if actionType == "spell" then
        return id
    elseif actionType == "macro" then
        if subType == "spell" then
            return id
        end
        -- Fallback: GetMacroSpell for macros without spell subType
        if GetMacroSpell then
            local macroOk, spellId = pcall(GetMacroSpell, id)
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
        local ok, overrideId = pcall(C_Spell.GetOverrideSpell, spellId)
        overrideId = ok and Helpers.SafeValue(overrideId, nil) or nil
        if ok and overrideId and overrideId ~= spellId then
            callback(overrideId)
        end
    end
end

-- Check if the button's action is a flyout containing a specific spell.
function ButtonFlyoutContainsSpell(button, spellId)
    local action = button.action
    if not action then return false end
    local ok, actionType, id = pcall(GetActionInfo, action)
    if not ok or actionType ~= "flyout" then return false end
    if FlyoutHasSpell then
        local fok, has = pcall(FlyoutHasSpell, id, spellId)
        if fok and has then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- SPELL-TO-BUTTONS REVERSE LOOKUP
---------------------------------------------------------------------------
-- Maps spellId → {btn1, btn2, ...} for O(1) glow event dispatch instead of
-- scanning all ~96 buttons on every proc event.  Rebuilt when action bar
-- content changes (visual update, slot change).
spellIdToButtons = {}
flyoutButtons = {}  -- buttons with flyout actions (checked as fallback)
spellIdButtonListPool = {}
spellIdMapDirty = true
spellIdMapStats = { rebuilds = 0, dirtyMarks = 0, ensures = 0 }
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AB_spellIdToButtons", tbl = spellIdToButtons }
    mp[#mp + 1] = { name = "AB_flyoutButtons",    tbl = flyoutButtons }
    mp[#mp + 1] = { name = "AB_spellIdListPool",  tbl = spellIdButtonListPool }
    mp[#mp + 1] = { name = "AB_spellIdMapRebuilds", counter = true, fn = function() return spellIdMapStats.rebuilds end }
    mp[#mp + 1] = { name = "AB_spellIdMapDirtyMarks", counter = true, fn = function() return spellIdMapStats.dirtyMarks end }
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
                        -- Check if this is a flyout button (rare but possible)
                        local action = btn.action
                        if action and HasAction(action) then
                            local ok, actionType = pcall(GetActionInfo, action)
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
    spellIdMapStats.rebuilds = spellIdMapStats.rebuilds + 1
end

MarkSpellIdMapDirty = function()
    if not spellIdMapDirty then
        spellIdMapStats.dirtyMarks = spellIdMapStats.dirtyMarks + 1
    end
    spellIdMapDirty = true
end

function EnsureSpellIdMap()
    spellIdMapStats.ensures = spellIdMapStats.ensures + 1
    if spellIdMapDirty then
        RebuildSpellIdMap()
    end
end

function ShowActionButtonGlow(button)
    if not LCG then return end
    local state = GetFrameState(button)
    if state.quiProcGlow then return end
    state.quiProcGlow = true
    LCG.ButtonGlow_Start(button)
end

function HideActionButtonGlow(button)
    if not LCG then return end
    local state = GetFrameState(button)
    if not state.quiProcGlow then return end
    state.quiProcGlow = false
    LCG.ButtonGlow_Stop(button)
end

-- Update the overlay glow on a single button based on current spell state.
function ActionBarsOwned.UpdateOverlayGlow(button)
    local spellId = GetButtonSpellId(button)
    if spellId then
        local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
            or _G.IsSpellOverlayed
        if IsSpellOverlayed then
            local overlayed = false
            ForEachSpellCandidate(spellId, function(candidateId)
                if overlayed then return end
                local ok, result = pcall(IsSpellOverlayed, candidateId)
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

---------------------------------------------------------------------------
-- SPELLBOOK HOVER HIGHLIGHT
-- When hovering a spell in the spellbook, highlight matching buttons.
---------------------------------------------------------------------------

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
        local action = button.action
        if action then
            local ok, actionType, actionId = pcall(GetActionInfo, action)
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

---------------------------------------------------------------------------
-- ASSISTED COMBAT ROTATION
-- Show arrow overlay on buttons with the one-button rotation action.
---------------------------------------------------------------------------

-- Tracks whether any button has ever shown an assisted combat rotation
-- frame.  Once true, SafeUpdate must check every button.  While false,
-- we can skip the per-button pcall entirely — a huge saving when the
-- feature isn't in use (majority of players).  Set to true by
-- OnSetActionSpell callback and by the first successful frame creation.
-- Stored on the module table so the EventRegistry callback (outside
-- this do block) can set it.
ActionBarsOwned._assistedCombatEverActive = false

-- The single button that currently hosts the AssistedCombatRotationFrame.
-- There is only ever one rotation slot, so rotation updates only need to
-- touch this one button instead of sweeping all 96.
_assistRotationButton = nil

UpdateAssistedCombatRotationFrame = function(button)
    if not (C_ActionBar and C_ActionBar.IsAssistedCombatAction) then return end
    -- Fast path: if assisted combat was never active AND this button has
    -- no rotation frame, skip entirely.
    local frame = button.AssistedCombatRotationFrame
    if not ActionBarsOwned._assistedCombatEverActive and not frame then return end

    local action = button.action
    local show = false
    local hasAction = action and HasAction(action)
    if hasAction then
        show = C_ActionBar.IsAssistedCombatAction(action)
    end

    -- Only create the template frame when needed (first time it should show).
    if show and not frame then
        ActionBarsOwned._assistedCombatEverActive = true
        frame = CreateFrame("Frame", nil, button, "ActionBarButtonAssistedCombatRotationTemplate")
        button.AssistedCombatRotationFrame = frame
        _assistRotationButton = button
        -- The template OnLoad sets frame level relative to MainActionBar's
        -- EndCaps, which QUI reparented to a hidden frame (low level).
        -- Override to sit above the button so it's visible over QUI's
        -- border/gloss overlays.
        frame:SetFrameLevel(button:GetFrameLevel() + 5)
    end
    -- Always delegate to UpdateState — the template manages its own
    -- show/hide and has internal event handlers that can re-show the
    -- frame if we only call Hide() manually.
    if frame then
        frame:UpdateState()
        -- Re-assert frame level: the template's OnEvent resets it
        -- relative to MainActionBar (reparented/hidden in QUI).
        frame:SetFrameLevel(button:GetFrameLevel() + 5)
    end
end

function UpdateAllAssistedCombatRotation()
    -- Fast path: one known rotation button, update just it.
    if _assistRotationButton then
        UpdateAssistedCombatRotationFrame(_assistRotationButton)
        return
    end

    -- Discovery pass: no rotation button known yet.  Look up the slot for
    -- the current recommendation and update that one button.  Once it
    -- creates a frame, _assistRotationButton gets set and subsequent
    -- updates take the fast path above.
    if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
        and C_ActionBar and C_ActionBar.FindSpellActionButtons) then
        return
    end
    local ok, spellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
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

---------------------------------------------------------------------------
-- ASSISTED COMBAT HIGHLIGHT
-- Shows marching-ants highlight on buttons matching the next recommended
-- spell from the rotation assistant (C_AssistedCombat).  Separate from
-- the rotation frame above, which marks the one-button rotation slot.
---------------------------------------------------------------------------

assistedHighlightButtons = {}  -- set of buttons currently highlighted (button → true)
_assistHighlightScratch = {}   -- reusable scratch table to avoid per-frame allocation
ASSISTED_HIGHLIGHT_COLOR = { 0.2, 0.82, 0.6, 1 }  -- Teal/mint, matches QUI accent

function SetAssistedHighlightShown(button, show)
    if not LCG then return end
    local state = GetFrameState(button)
    if show then
        if state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = true
        LCG.ButtonGlow_Start(button, ASSISTED_HIGHLIGHT_COLOR)
    else
        if not state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = false
        LCG.ButtonGlow_Stop(button)
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

    local okNext, nextSpellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
    if not okNext then nextSpellID = nil end

    -- Build match set into a reusable scratch table to avoid per-call
    -- allocation — this runs up to 10x/sec under soft targeting.
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

    -- Clear previously highlighted buttons that are no longer in the match set.
    for btn in pairs(assistedHighlightButtons) do
        if not matchButtons[btn] then
            SetAssistedHighlightShown(btn, false)
        end
    end

    -- Apply highlights to matching buttons.
    for btn in pairs(matchButtons) do
        SetAssistedHighlightShown(btn, true)
    end

    -- Swap: move scratch results into the live set, reuse the old live
    -- table as next call's scratch.  Zero allocation per frame.
    _assistHighlightScratch = assistedHighlightButtons
    wipe(_assistHighlightScratch)
    assistedHighlightButtons = matchButtons
end

-- Update overlay glows on all owned action buttons.
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

-- Handle SPELL_ACTIVATION_OVERLAY_GLOW_SHOW: O(1) lookup via reverse map,
-- flyout fallback for rare flyout-containing-spell case.
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
            local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, candidateId)
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
        -- Some proc events fire for spell IDs that do not appear directly on
        -- the button (base vs current override). Fall back to a cheap full
        -- rescan so the visible button still picks up the glow.
        ActionBarsOwned.UpdateAllOverlayGlows()
    end
end

-- Handle SPELL_ACTIVATION_OVERLAY_GLOW_HIDE: O(1) lookup via reverse map,
-- flyout fallback for rare flyout-containing-spell case.
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

end -- do (spell glow / highlight / assisted rotation)

-- Lean checked-state refresh: IsCurrentAction / IsAutoRepeatAction +
-- SetChecked. Used for ACTIONBAR_UPDATE_STATE which fires frequently in
-- combat (every autoattack toggle, every current-action change). Avoids
-- the 20-API-call full SafeUpdate path for events that only affect
-- the checked state. Mirrors LibActionButton's UpdateButtonState.
_lastStateUpdateTime = 0
function ActionBarsOwned.UpdateAllButtonStates()
    local now = GetTime()
    if now == _lastStateUpdateTime then return end
    _lastStateUpdateTime = now

    for btn in pairs(ActionBarsOwned._activeButtons) do
        local action = btn.action
        if action and action ~= 0 then
            if IsCurrentAction(action) or IsAutoRepeatAction(action) then
                btn:SetChecked(true)
            else
                btn:SetChecked(false)
            end
        end
    end
end

-- Lean count refresh: UpdateCount on active buttons only.
-- Used for UNIT_AURA which fires when aura-based resource overlays
-- (Soul Fragments, etc.) change.  Avoids full SafeUpdate.
_lastCountUpdateTime = 0
function ActionBarsOwned.UpdateAllButtonCounts()
    local now = GetTime()
    if now == _lastCountUpdateTime then return end
    _lastCountUpdateTime = now

    for btn in pairs(ActionBarsOwned._activeButtons) do
        if btn.UpdateCount then pcall(btn.UpdateCount, btn) end
    end
end

-- Full visual refresh for all owned action buttons via SafeUpdate.
-- Uses only truthiness tests on API returns — safe during combat.
_lastVisualUpdateTime = 0
_visualFirstRunDone = false
function ActionBarsOwned.UpdateAllButtonVisuals()
    -- Hard throttle: max once per frame
    local now = GetTime()
    if now == _lastVisualUpdateTime then return end
    _lastVisualUpdateTime = now

    -- First run needs a full scan: it's where _activeButtons gets populated
    -- for the first time (SafeUpdate sets the entries). All empty-slot
    -- visuals are also initialized here. Subsequent runs iterate only the
    -- active set (typical: 30-50 vs 96).
    --
    -- Full scans also run when SPELLS_CHANGED, PLAYER_ENTERING_WORLD, or
    -- similar "something big happened" events fire — those need to walk
    -- every button to catch mass action-table shuffles. Those events
    -- force _visualFirstRunDone = false via ForceFullVisualRescan.
    if not _visualFirstRunDone then
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                        local action = btn.action or 0
                        if HasAction(action) then
                            local state = GetFrameState(btn)
                            state.wasEmpty = false
                            pcall(ActionBarsOwned.SafeUpdate, btn)
                        else
                            local state = GetFrameState(btn)
                            if not state.wasEmpty then
                                state.wasEmpty = true
                                pcall(ActionBarsOwned.SafeUpdate, btn)
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
        -- Fast path: iterate only buttons with actions. Active→empty
        -- transitions are handled by SafeSyncAction/ACTIONBAR_SLOT_CHANGED
        -- paths calling SafeUpdate directly on the affected button.
        for btn in pairs(ActionBarsOwned._activeButtons) do
            local barKey = btn._quiBarKey
            if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                local state = GetFrameState(btn)
                state.wasEmpty = false
                pcall(ActionBarsOwned.SafeUpdate, btn)
            else
                ActionBarsOwned._activeButtons[btn] = nil
                ActionBarsOwned._activeStandardButtons[btn] = nil
            end
        end
    end

    -- Slot/icon state changed; rebuild the reverse lookup only if a glow
    -- event needs it.
    if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
end

-- Force the next UpdateAllButtonVisuals call to do a full scan (covers
-- mass action-table shuffles where individual slot events aren't reliable).
function ActionBarsOwned.ForceFullVisualRescan()
    _visualFirstRunDone = false
    if ResetAllChargeCapabilityCaches then
        ResetAllChargeCapabilityCaches()
    end
    if MarkSpellIdMapDirty then MarkSpellIdMapDirty() end
end

