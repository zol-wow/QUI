local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- OWNED COOLDOWN UPDATE (12.0.5+ DurationObject path)
---------------------------------------------------------------------------
-- Replaces Blizzard's ActionButton_UpdateCooldown which can no longer call
-- SetCooldown with secret values from tainted code.  Uses the new
-- C_ActionBar structured APIs (isActive boolean, DurationObjects) to drive
-- cooldown display via SetCooldownFromDurationObject — the only remaining
-- secret-safe cooldown setter.
--
-- All helpers are scoped inside a do...end block to stay within Lua's
-- 200 file-scope local variable limit.  Public functions are stored as
-- ActionBarsOwned fields.

-- Local upvalue for do-block increment guards (luacheck-clean).
-- Also written to the same-named GLOBAL so actionbars_events.lua can
-- increment _abCooldownStats.events without a cross-file require.
-- Nil until QUI_Debug activates instrumentation (debug gate).
local _abCooldownStats -- debug counters
local function SetupDebugInstrumentation()
    _abCooldownStats = {
        events = 0,
        batches = 0,
        buttons = 0,
        actionCooldownQueries = 0,
        actionCooldownHits = 0,
        actionCooldownActiveHits = 0,
        actionCooldownInactiveSkips = 0,
        actionDurationQueries = 0,
        actionDurationHits = 0,
        actionDurationActiveHits = 0,
        chargeInfoQueries = 0,
        chargeInfoSkips = 0,
        chargeInfoActive = 0,
        chargeDurationQueries = 0,
        chargeDurationActive = 0,
        lossOfControlInfoQueries = 0,
        lossOfControlDurationQueries = 0,
    }
    _G._abCooldownStats = _abCooldownStats -- global alias for actionbars_events.lua (loads after this file per actionbars.xml; picks the alias up in its own gated setup)
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AB_cooldownEvents",  counter = true, fn = function() return _abCooldownStats.events  end }
    mp[#mp + 1] = { name = "AB_cooldownBatches", counter = true, fn = function() return _abCooldownStats.batches end }
    mp[#mp + 1] = { name = "AB_cooldownButtons", counter = true, fn = function() return _abCooldownStats.buttons end }
    mp[#mp + 1] = { name = "AB_actionCooldownQueries", counter = true, fn = function() return _abCooldownStats.actionCooldownQueries end }
    mp[#mp + 1] = { name = "AB_actionCooldownHits", counter = true, fn = function() return _abCooldownStats.actionCooldownHits end }
    mp[#mp + 1] = { name = "AB_actionCooldownActiveHits", counter = true, fn = function() return _abCooldownStats.actionCooldownActiveHits end }
    mp[#mp + 1] = { name = "AB_actionCooldownInactiveSkips", counter = true, fn = function() return _abCooldownStats.actionCooldownInactiveSkips end }
    mp[#mp + 1] = { name = "AB_actionDurationQueries", counter = true, fn = function() return _abCooldownStats.actionDurationQueries end }
    mp[#mp + 1] = { name = "AB_actionDurationHits", counter = true, fn = function() return _abCooldownStats.actionDurationHits end }
    mp[#mp + 1] = { name = "AB_actionDurationActiveHits", counter = true, fn = function() return _abCooldownStats.actionDurationActiveHits end }
    mp[#mp + 1] = { name = "AB_chargeInfoQueries", counter = true, fn = function() return _abCooldownStats.chargeInfoQueries end }
    mp[#mp + 1] = { name = "AB_chargeInfoSkips", counter = true, fn = function() return _abCooldownStats.chargeInfoSkips end }
    mp[#mp + 1] = { name = "AB_chargeInfoActive", counter = true, fn = function() return _abCooldownStats.chargeInfoActive end }
    mp[#mp + 1] = { name = "AB_chargeDurationQueries", counter = true, fn = function() return _abCooldownStats.chargeDurationQueries end }
    mp[#mp + 1] = { name = "AB_chargeDurationActive", counter = true, fn = function() return _abCooldownStats.chargeDurationActive end }
    mp[#mp + 1] = { name = "AB_lossOfControlInfoQueries", counter = true, fn = function() return _abCooldownStats.lossOfControlInfoQueries end }
    mp[#mp + 1] = { name = "AB_lossOfControlDurationQueries", counter = true, fn = function() return _abCooldownStats.lossOfControlDurationQueries end }
    -- AB_chargeCapabilityCache probe is registered inside the do-block below
    -- (after the gate registration below it) because _buttonChargeAction is
    -- declared there; the probe fn closes over it safely at that point.
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

do
    -- Build 66562+ removed the secure delegate from ActionButton_ApplyCooldown
    -- and blocked SetCooldown from accepting secret values in tainted context.
    local USE_DURATION_OBJECTS = IS_MIDNIGHT
        and C_ActionBar ~= nil
        and C_ActionBar.GetActionCooldownDuration ~= nil
        and (tonumber((select(2, GetBuildInfo()))) or 0) >= 66562

    local DEFAULT_CD_INFO  = { startTime = 0, duration = 0, isEnabled = false, isActive = false, modRate = 0 }
    local DEFAULT_LOC_INFO = { startTime = 0, duration = 0, modRate = 0, isActive = false, shouldReplaceNormalCooldown = false }
    local ACTIVE_COOLDOWN_CACHE_MAX_DURATION = 2.5
    local ACTIVE_COOLDOWN_CACHE_LONG_REFRESH_TTL = 1.0
    local ACTIVE_COOLDOWN_CACHE_FALLBACK_TTL = 0.20
    local INACTIVE_COOLDOWN_CACHE_TTL = 0.25

    local function GetOrCreateChargeCooldown(button)
        if button.chargeCooldown then return button.chargeCooldown end
        local parent = button.cooldown or button
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(false)
        cd:SetAllPoints(parent)
        cd:SetFrameLevel(button:GetFrameLevel())
        button.chargeCooldown = cd
        return cd
    end

    local function GetOrCreateLoCCooldown(button)
        if button.lossOfControlCooldown then return button.lossOfControlCooldown end
        local parent = button.cooldown or button
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetHideCountdownNumbers(true)
        cd:SetAllPoints(parent)
        cd:SetFrameLevel(button:GetFrameLevel() + 1)
        cd:SetSwipeColor(0.17, 0, 0, 0.8)
        button.lossOfControlCooldown = cd
        return cd
    end

    local function SetOrClearCooldown(cooldown, shouldShow, durationObject)
        if not cooldown then return end
        if not shouldShow or not durationObject then
            cooldown:Clear()
            return
        end
        cooldown:SetCooldownFromDurationObject(durationObject)
    end

    local function DecodePotentialSecretBoolean(value)
        if Helpers.IsSecretValue(value) then
            return nil
        end
        if value == true then return true end
        if value == false then return false end
        return nil
    end

    -- Per-button "was on cooldown last scan" cache. Skips redundant Clear()
    -- calls on idle buttons (the common case — ~90 of 96 buttons are usually
    -- off cooldown at any given moment). In raid combat, SPELL_UPDATE_COOLDOWN
    -- fires ~20-30/sec and we scan all 96 buttons on each tick; without this
    -- cache we hit Clear() 270 times per tick (cooldown + charge + LoC frames)
    -- for buttons that are already cleared.
    local _buttonWasActive = setmetatable({}, { __mode = "k" })
    local _buttonCooldownAction = setmetatable({}, { __mode = "k" })
    local _buttonCooldownInfo = setmetatable({}, { __mode = "k" })
    local _buttonCooldownDurationObject = setmetatable({}, { __mode = "k" })
    local _buttonCooldownExpiresAt = setmetatable({}, { __mode = "k" })
    local _buttonCooldownInactiveAt = setmetatable({}, { __mode = "k" })
    local _buttonChargeAction = setmetatable({}, { __mode = "k" })
    local _buttonMayHaveCharges = setmetatable({}, { __mode = "k" })
    local _cooldownBatchToken = 0
    local _cooldownBatchActive = false
    local _batchCooldownInfoSeen = {}
    local _batchCooldownInfo = {}
    local _batchCooldownDurationSeen = {}
    local _batchCooldownDurationObject = {}
    local _batchChargeInfoSeen = {}
    local _batchChargeActive = {}
    local _batchChargeMayHaveCharges = {}
    local _batchChargeDurationSeen = {}
    local _batchChargeDurationObject = {}
    -- AB_chargeCapabilityCache probe: registered here because _buttonChargeAction
    -- is declared in this do-block, via its own gate registration (the file's
    -- main SetupDebugInstrumentation can't see this local).
    local function SetupChargeCacheProbe()
        local mp = ns._memprobes or {}; ns._memprobes = mp
        mp[#mp + 1] = {
            name = "AB_chargeCapabilityCache",
            fn = function()
                local count = 0
                for _ in pairs(_buttonChargeAction) do count = count + 1 end
                return count, 0
            end,
        }
    end
    if ns.DebugRegister then -- gate contract: core/debug_gate.lua
        ns.DebugRegister(SetupChargeCacheProbe)
    else
        SetupChargeCacheProbe() -- standalone test harness: no gate, run eagerly
    end

    local function ResetButtonCooldownRuntimeCache(button)
        _buttonCooldownAction[button] = nil
        _buttonCooldownInfo[button] = nil
        _buttonCooldownDurationObject[button] = nil
        _buttonCooldownExpiresAt[button] = nil
        _buttonCooldownInactiveAt[button] = nil
    end

    ResetButtonChargeCapabilityCache = function(button)
        ResetButtonCooldownRuntimeCache(button)
        _buttonChargeAction[button] = nil
        _buttonMayHaveCharges[button] = nil
    end

    ResetAllChargeCapabilityCaches = function()
        wipe(_buttonCooldownAction)
        wipe(_buttonCooldownInfo)
        wipe(_buttonCooldownDurationObject)
        wipe(_buttonCooldownExpiresAt)
        wipe(_buttonCooldownInactiveAt)
        wipe(_buttonChargeAction)
        wipe(_buttonMayHaveCharges)
        wipe(_batchCooldownInfoSeen)
        wipe(_batchCooldownInfo)
        wipe(_batchCooldownDurationSeen)
        wipe(_batchCooldownDurationObject)
        wipe(_batchChargeInfoSeen)
        wipe(_batchChargeActive)
        wipe(_batchChargeMayHaveCharges)
        wipe(_batchChargeDurationSeen)
        wipe(_batchChargeDurationObject)
    end

    local function BeginCooldownBatch()
        _cooldownBatchToken = _cooldownBatchToken + 1
        if _cooldownBatchToken > 1000000000 then
            _cooldownBatchToken = 1
            wipe(_batchCooldownInfoSeen)
            wipe(_batchCooldownInfo)
            wipe(_batchCooldownDurationSeen)
            wipe(_batchCooldownDurationObject)
            wipe(_batchChargeInfoSeen)
            wipe(_batchChargeActive)
            wipe(_batchChargeMayHaveCharges)
            wipe(_batchChargeDurationSeen)
            wipe(_batchChargeDurationObject)
        end
        _cooldownBatchActive = true
    end

    local function EndCooldownBatch()
        _cooldownBatchActive = false
    end

    local function GetSafeCooldownTiming(cdInfo)
        if not cdInfo then return nil, nil end
        local start = cdInfo.startTime
        if start == nil then
            start = cdInfo.start
        end
        local duration = cdInfo.duration
        if Helpers.IsSecretValue(start) or Helpers.IsSecretValue(duration) then
            return nil, nil
        end
        if type(start) ~= "number" or type(duration) ~= "number" then
            return nil, nil
        end
        if start <= 0 or duration <= 0 then
            return nil, nil
        end
        return start + duration, duration
    end

    local function GetActionCooldownInfo(action)
        if not C_ActionBar.GetActionCooldown then return DEFAULT_CD_INFO end
        local actionCanBeCached = not Helpers.IsSecretValue(action)
        if actionCanBeCached
            and _cooldownBatchActive
            and _batchCooldownInfoSeen[action] == _cooldownBatchToken then
            if _abCooldownStats then _abCooldownStats.actionCooldownHits = _abCooldownStats.actionCooldownHits + 1 end
            return _batchCooldownInfo[action] or DEFAULT_CD_INFO
        end

        if _abCooldownStats then _abCooldownStats.actionCooldownQueries = _abCooldownStats.actionCooldownQueries + 1 end
        local cdInfo = C_ActionBar.GetActionCooldown(action) or DEFAULT_CD_INFO
        if actionCanBeCached and _cooldownBatchActive then
            _batchCooldownInfoSeen[action] = _cooldownBatchToken
            _batchCooldownInfo[action] = cdInfo
        end
        return cdInfo
    end

    local function GetActionCooldownDurationObject(action)
        if not C_ActionBar.GetActionCooldownDuration then return nil end
        local actionCanBeCached = not Helpers.IsSecretValue(action)
        if actionCanBeCached
            and _cooldownBatchActive
            and _batchCooldownDurationSeen[action] == _cooldownBatchToken then
            if _abCooldownStats then _abCooldownStats.actionDurationHits = _abCooldownStats.actionDurationHits + 1 end
            return _batchCooldownDurationObject[action]
        end

        if _abCooldownStats then _abCooldownStats.actionDurationQueries = _abCooldownStats.actionDurationQueries + 1 end
        local durationObject = C_ActionBar.GetActionCooldownDuration(action)
        if actionCanBeCached and _cooldownBatchActive then
            _batchCooldownDurationSeen[action] = _cooldownBatchToken
            _batchCooldownDurationObject[action] = durationObject
        end
        return durationObject
    end

    local function GetActionCooldownState(button, action)
        local actionCanBeCached = not Helpers.IsSecretValue(action)
        if actionCanBeCached and _buttonCooldownAction[button] == action then
            local expiresAt = _buttonCooldownExpiresAt[button]
            if type(expiresAt) == "number" and GetTime() < expiresAt - 0.05 then
                local durationObject = _buttonCooldownDurationObject[button]
                if durationObject then
                    if _abCooldownStats then
                        _abCooldownStats.actionCooldownHits = _abCooldownStats.actionCooldownHits + 1
                        _abCooldownStats.actionCooldownActiveHits = _abCooldownStats.actionCooldownActiveHits + 1
                        _abCooldownStats.actionDurationHits = _abCooldownStats.actionDurationHits + 1
                        _abCooldownStats.actionDurationActiveHits = _abCooldownStats.actionDurationActiveHits + 1
                    end
                    return _buttonCooldownInfo[button] or DEFAULT_CD_INFO, durationObject, true
                end
            end

            local inactiveAt = _buttonCooldownInactiveAt[button]
            if type(inactiveAt) == "number"
                and GetTime() - inactiveAt < INACTIVE_COOLDOWN_CACHE_TTL then
                if _abCooldownStats then
                    _abCooldownStats.actionCooldownHits = _abCooldownStats.actionCooldownHits + 1
                    _abCooldownStats.actionCooldownInactiveSkips = _abCooldownStats.actionCooldownInactiveSkips + 1
                end
                return DEFAULT_CD_INFO, nil, false
            end
        end

        local cdInfo = GetActionCooldownInfo(action)
        local cdActive = DecodePotentialSecretBoolean(cdInfo.isActive)
        local durationObject = cdActive and GetActionCooldownDurationObject(action) or nil
        if actionCanBeCached then
            if cdActive == true and durationObject then
                local expiresAt, duration = GetSafeCooldownTiming(cdInfo)
                if expiresAt and duration <= ACTIVE_COOLDOWN_CACHE_MAX_DURATION then
                    _buttonCooldownAction[button] = action
                    _buttonCooldownInfo[button] = cdInfo
                    _buttonCooldownDurationObject[button] = durationObject
                    _buttonCooldownExpiresAt[button] = expiresAt
                    _buttonCooldownInactiveAt[button] = nil
                elseif expiresAt then
                    _buttonCooldownAction[button] = action
                    _buttonCooldownInfo[button] = cdInfo
                    _buttonCooldownDurationObject[button] = durationObject
                    _buttonCooldownExpiresAt[button] = math.min(expiresAt, GetTime() + ACTIVE_COOLDOWN_CACHE_LONG_REFRESH_TTL)
                    _buttonCooldownInactiveAt[button] = nil
                elseif not expiresAt then
                    _buttonCooldownAction[button] = action
                    _buttonCooldownInfo[button] = cdInfo
                    _buttonCooldownDurationObject[button] = durationObject
                    _buttonCooldownExpiresAt[button] = GetTime() + ACTIVE_COOLDOWN_CACHE_FALLBACK_TTL
                    _buttonCooldownInactiveAt[button] = nil
                end
            elseif cdActive == false then
                _buttonCooldownAction[button] = action
                _buttonCooldownInfo[button] = nil
                _buttonCooldownDurationObject[button] = nil
                _buttonCooldownExpiresAt[button] = nil
                _buttonCooldownInactiveAt[button] = GetTime()
            else
                ResetButtonCooldownRuntimeCache(button)
            end
        end
        return cdInfo, durationObject, cdActive
    end

    local function ChargeInfoMayHaveCharges(chargeInfo)
        if not chargeInfo then return false end
        local maxCharges = chargeInfo.maxCharges
        if Helpers.IsSecretValue(maxCharges) then
            return true
        end
        maxCharges = Helpers.SafeToNumber(maxCharges, 0) or 0
        return maxCharges > 1
    end

    local function GetActionChargeActive(button, action)
        if not C_ActionBar.GetActionCharges then return nil end
        local actionCanBeCached = not Helpers.IsSecretValue(action)
        if actionCanBeCached
            and _cooldownBatchActive
            and _batchChargeInfoSeen[action] == _cooldownBatchToken then
            if _batchChargeMayHaveCharges[action] == false then
                if _abCooldownStats then _abCooldownStats.chargeInfoSkips = _abCooldownStats.chargeInfoSkips + 1 end
            end
            return _batchChargeActive[action]
        end

        if actionCanBeCached
            and _buttonChargeAction[button] == action
            and _buttonMayHaveCharges[button] == false then
            if _abCooldownStats then _abCooldownStats.chargeInfoSkips = _abCooldownStats.chargeInfoSkips + 1 end
            return nil
        end

        if _abCooldownStats then _abCooldownStats.chargeInfoQueries = _abCooldownStats.chargeInfoQueries + 1 end
        local chargeInfo = C_ActionBar.GetActionCharges(action)
        local mayHaveCharges = ChargeInfoMayHaveCharges(chargeInfo)
        if actionCanBeCached then
            _buttonChargeAction[button] = action
            _buttonMayHaveCharges[button] = mayHaveCharges
            if _cooldownBatchActive then
                _batchChargeInfoSeen[action] = _cooldownBatchToken
                _batchChargeMayHaveCharges[action] = mayHaveCharges
            end
        end
        local chargeActive = chargeInfo and DecodePotentialSecretBoolean(chargeInfo.isActive)
        if mayHaveCharges and chargeActive == true then
            if _abCooldownStats then _abCooldownStats.chargeInfoActive = _abCooldownStats.chargeInfoActive + 1 end
            if actionCanBeCached and _cooldownBatchActive then
                _batchChargeActive[action] = true
            end
            return true
        end
        if actionCanBeCached and _cooldownBatchActive then
            _batchChargeActive[action] = nil
        end
        return nil
    end

    local function GetActionChargeDurationObject(action)
        if not C_ActionBar.GetActionChargeDuration then return nil end
        local actionCanBeCached = not Helpers.IsSecretValue(action)
        if actionCanBeCached
            and _cooldownBatchActive
            and _batchChargeDurationSeen[action] == _cooldownBatchToken then
            return _batchChargeDurationObject[action]
        end

        if _abCooldownStats then _abCooldownStats.chargeDurationQueries = _abCooldownStats.chargeDurationQueries + 1 end
        local durationObject = C_ActionBar.GetActionChargeDuration(action)
        if actionCanBeCached and _cooldownBatchActive then
            _batchChargeDurationSeen[action] = _cooldownBatchToken
            _batchChargeDurationObject[action] = durationObject
        end
        if durationObject then
            if _abCooldownStats then _abCooldownStats.chargeDurationActive = _abCooldownStats.chargeDurationActive + 1 end
        end
        return durationObject
    end

    function ActionBarsOwned.UpdateCooldown(button)
        -- Hot path: called every ~100ms for all active buttons. Every
        -- saved Lua op compounds to measurable ms/sec in raid combat.
        -- `button.action` is always set by SafeSyncAction/state driver,
        -- so the GetAttribute fallback is dead code and has been removed.
        if _abCooldownStats then _abCooldownStats.buttons = _abCooldownStats.buttons + 1 end
        local action = button.action
        if not action or action == 0 then return end

        local cooldown = button.cooldown or button.Cooldown
        if not cooldown then return end

        if USE_DURATION_OBJECTS then
            -- Fast path: check primary cooldown first, then read only the
            -- non-secret charge capability/active fields. Never read
            -- currentCharges in combat; fetch the DurationObject only when
            -- isActive says a charge is recharging.
            local _, cdDurationObject, cdActive = GetActionCooldownState(button, action)
            local chActive = GetActionChargeActive(button, action)
            local chargeDurObj = chActive == true and GetActionChargeDurationObject(action) or nil
            if cdActive ~= true and chActive ~= true then
                -- Idle button: only clear the frames on the active→inactive
                -- transition. Subsequent idle scans skip the Clear() churn.
                if _buttonWasActive[button] then
                    _buttonWasActive[button] = nil
                    cooldown:Clear()
                    if button.chargeCooldown then button.chargeCooldown:Clear() end
                    if button.lossOfControlCooldown then button.lossOfControlCooldown:Clear() end
                end
                return
            end
            _buttonWasActive[button] = true

            -- Button is on cooldown and/or recharging a charge — LoC is the
            -- remaining query.
            if _abCooldownStats then _abCooldownStats.lossOfControlInfoQueries = _abCooldownStats.lossOfControlInfoQueries + 1 end
            local locInfo = C_ActionBar.GetActionLossOfControlCooldownInfo(action) or DEFAULT_LOC_INFO

            local locActive = DecodePotentialSecretBoolean(locInfo.isActive)
            local locReplacesNormal = DecodePotentialSecretBoolean(locInfo.shouldReplaceNormalCooldown)
            local showLoC    = locActive == true
            local showCharge = locReplacesNormal ~= true and chActive == true
            local showNormal = locReplacesNormal ~= true and cdActive == true

            -- Normal cooldown (only fetch DurationObject when needed)
            if showNormal then
                SetOrClearCooldown(cooldown, true, cdDurationObject)
            else
                cooldown:Clear()
            end

            -- Charge cooldown (lazy-create frame)
            if showCharge then
                SetOrClearCooldown(GetOrCreateChargeCooldown(button), true, chargeDurObj)
            elseif button.chargeCooldown then
                button.chargeCooldown:Clear()
            end

            -- Loss of control cooldown (lazy-create frame)
            if showLoC then
                if _abCooldownStats then _abCooldownStats.lossOfControlDurationQueries = _abCooldownStats.lossOfControlDurationQueries + 1 end
                SetOrClearCooldown(GetOrCreateLoCCooldown(button), true, C_ActionBar.GetActionLossOfControlCooldownDuration(action))
            elseif button.lossOfControlCooldown then
                button.lossOfControlCooldown:Clear()
            end
        else
            -- Pre-12.0.5 fallback: delegate to Blizzard's handler (pcall for safety)
            if ActionButton_UpdateCooldown then
                pcall(ActionButton_UpdateCooldown, button)
            end
        end
    end

    local _lastCdUpdateTime = 0
    function ActionBarsOwned.UpdateAllCooldowns()
        -- Hard throttle: max once per frame (prevents duplicate work when
        -- multiple code paths trigger cooldown updates in the same frame)
        local now = GetTime()
        if now == _lastCdUpdateTime then return end
        _lastCdUpdateTime = now
        if _abCooldownStats then _abCooldownStats.batches = _abCooldownStats.batches + 1 end

        -- Fast path: iterate only buttons with actions (LibActionButton
        -- pattern). Typical raid: ~30-50 active of 96 total.
        local activeButtons = ActionBarsOwned._activeButtons
        BeginCooldownBatch()
        if next(activeButtons) ~= nil then
            for btn in pairs(activeButtons) do
                local barKey = btn._quiBarKey
                if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                    ActionBarsOwned.UpdateCooldown(btn)
                else
                    activeButtons[btn] = nil
                    ActionBarsOwned._activeStandardButtons[btn] = nil
                end
            end
            EndCooldownBatch()
            return
        end

        -- Fallback: full scan before the first SafeUpdate pass has
        -- populated _activeButtons (fresh login, brief window before
        -- PLAYER_ENTERING_WORLD-driven refresh).
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local buttons = ActionBarsOwned.nativeButtons[barKey]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey))
                        and HasAction(btn.action or 0) then
                        ActionBarsOwned.UpdateCooldown(btn)
                    end
                end
            end
        end
        EndCooldownBatch()
    end

end -- do block (cooldown ownership)
