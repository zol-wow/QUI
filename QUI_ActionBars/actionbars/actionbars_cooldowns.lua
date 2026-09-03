local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

-- cooldown display via SetCooldownFromDurationObject — the only remaining

local _abCooldownStats
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
        lossOfControlInfoHits = 0,
        lossOfControlDurationQueries = 0,
    }
    _G._abCooldownStats = _abCooldownStats
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
    mp[#mp + 1] = { name = "AB_lossOfControlInfoHits", counter = true, fn = function() return _abCooldownStats.lossOfControlInfoHits end }
    mp[#mp + 1] = { name = "AB_lossOfControlDurationQueries", counter = true, fn = function() return _abCooldownStats.lossOfControlDurationQueries end }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

do
    local USE_DURATION_OBJECTS = IS_MIDNIGHT
        and C_ActionBar ~= nil
        and C_ActionBar.GetActionCooldownDuration ~= nil
        and (tonumber((select(2, GetBuildInfo()))) or 0) >= 66562

    local DEFAULT_CD_INFO  = { startTime = 0, duration = 0, isEnabled = false, isActive = false, modRate = 0 }
    local DEFAULT_LOC_INFO = { startTime = 0, duration = 0, modRate = 0, isActive = false, shouldReplaceNormalCooldown = false }
    local DEFAULT_CHARGE_INFO = { currentCharges = 0, maxCharges = 0, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 0, isActive = false }

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

    local function GetLoCCooldown(button)
        return button.lossOfControlCooldown or button._quiLoCCooldown
    end

    local function GetOrCreateLoCCooldown(button)
        local existing = GetLoCCooldown(button)
        if existing then return existing end
        local parent = button.cooldown or button
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetHideCountdownNumbers(true)
        cd:SetAllPoints(parent)
        cd:SetFrameLevel(button:GetFrameLevel() + 1)
        cd:SetSwipeColor(0.17, 0, 0, 0.8)
        button._quiLoCCooldown = cd
        return cd
    end

    local _locGateAt, _locGateResult
    local function PlayerMayHaveLossOfControl()
        if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then
            return false
        end
        local now = GetTime()
        if _locGateAt == now then return _locGateResult end
        _locGateAt = now
        local count = C_LossOfControl.GetActiveLossOfControlDataCount()
        _locGateResult = (tonumber(count) or 0) > 0
        return _locGateResult
    end

    local function CanMutateCooldown(cooldown)
        return not Helpers.CanMutateCooldown or Helpers.CanMutateCooldown(cooldown)
    end

    local function ClearCooldown(cooldown)
        if not cooldown then return end
        if not CanMutateCooldown(cooldown) then
            ActionBarsOwned.pendingCooldownRefresh = true
            return
        end
        if Helpers.ClearCooldown then
            Helpers.ClearCooldown(cooldown)
        else
            cooldown:Clear()
        end
    end

    local function SetOrClearCooldown(cooldown, shouldShow, durationObject)
        if not cooldown then return end
        if not CanMutateCooldown(cooldown) then
            ActionBarsOwned.pendingCooldownRefresh = true
            return
        end
        if not shouldShow or not durationObject then
            ClearCooldown(cooldown)
            return
        end
        cooldown:SetCooldownFromDurationObject(durationObject)
    end

    local _buttonWasActive = setmetatable({}, { __mode = "k" })
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
    local _batchLoCInfoSeen = {}
    local _batchLoCInfo = {}
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
    if ns.DebugRegister then
        ns.DebugRegister(SetupChargeCacheProbe)
    else
        SetupChargeCacheProbe()
    end

    ResetButtonChargeCapabilityCache = function(button)
        _buttonChargeAction[button] = nil
        _buttonMayHaveCharges[button] = nil
    end

    FlushChargeCapabilityVerdicts = function()
        wipe(_buttonMayHaveCharges)
    end

    ResetAllChargeCapabilityCaches = function()
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
        wipe(_batchLoCInfoSeen)
        wipe(_batchLoCInfo)
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
            wipe(_batchLoCInfoSeen)
            wipe(_batchLoCInfo)
        end
        _cooldownBatchActive = true
    end

    local function EndCooldownBatch()
        _cooldownBatchActive = false
    end

    local function GetActionCooldownInfo(action)
        if not C_ActionBar.GetActionCooldown then return DEFAULT_CD_INFO end
        if _cooldownBatchActive
            and _batchCooldownInfoSeen[action] == _cooldownBatchToken then
            if _abCooldownStats then _abCooldownStats.actionCooldownHits = _abCooldownStats.actionCooldownHits + 1 end
            return _batchCooldownInfo[action]
        end

        if _abCooldownStats then _abCooldownStats.actionCooldownQueries = _abCooldownStats.actionCooldownQueries + 1 end
        local cdInfo = C_ActionBar.GetActionCooldown(action)
        if type(cdInfo) ~= "table" then cdInfo = DEFAULT_CD_INFO end
        if _cooldownBatchActive then
            _batchCooldownInfoSeen[action] = _cooldownBatchToken
            _batchCooldownInfo[action] = cdInfo
        end
        return cdInfo
    end

    local function GetActionCooldownDurationObject(action)
        if not C_ActionBar.GetActionCooldownDuration then return nil end
        if _cooldownBatchActive
            and _batchCooldownDurationSeen[action] == _cooldownBatchToken then
            if _abCooldownStats then _abCooldownStats.actionDurationHits = _abCooldownStats.actionDurationHits + 1 end
            return _batchCooldownDurationObject[action]
        end

        if _abCooldownStats then _abCooldownStats.actionDurationQueries = _abCooldownStats.actionDurationQueries + 1 end
        local durationObject = C_ActionBar.GetActionCooldownDuration(action)
        if _cooldownBatchActive then
            _batchCooldownDurationSeen[action] = _cooldownBatchToken
            _batchCooldownDurationObject[action] = durationObject
        end
        return durationObject
    end

    local function GetActionCooldownState(button, action)
        local cdInfo = GetActionCooldownInfo(action)
        local cdActive = cdInfo.isActive
        local durationObject = cdActive ~= false and GetActionCooldownDurationObject(action) or nil
        return cdInfo, durationObject, cdActive
    end

    local function GetActionChargeActive(button, action)
        if not C_ActionBar.GetActionCharges then return nil end
        if _cooldownBatchActive
            and _batchChargeInfoSeen[action] == _cooldownBatchToken then
            if _batchChargeMayHaveCharges[action] == false then
                if _abCooldownStats then _abCooldownStats.chargeInfoSkips = _abCooldownStats.chargeInfoSkips + 1 end
            end
            return _batchChargeActive[action]
        end

        if _buttonChargeAction[button] == action
            and _buttonMayHaveCharges[button] == false then
            if _abCooldownStats then _abCooldownStats.chargeInfoSkips = _abCooldownStats.chargeInfoSkips + 1 end
            return nil
        end

        if _abCooldownStats then _abCooldownStats.chargeInfoQueries = _abCooldownStats.chargeInfoQueries + 1 end
        local chargeInfo = C_ActionBar.GetActionCharges(action)
        if type(chargeInfo) ~= "table" then chargeInfo = DEFAULT_CHARGE_INFO end
        local mayHaveCharges = chargeInfo.maxCharges > 1
        _buttonChargeAction[button] = action
        _buttonMayHaveCharges[button] = mayHaveCharges
        if _cooldownBatchActive then
            _batchChargeInfoSeen[action] = _cooldownBatchToken
            _batchChargeMayHaveCharges[action] = mayHaveCharges
        end
        local chargeActive = chargeInfo.isActive
        if mayHaveCharges and chargeActive ~= false then
            if _abCooldownStats then _abCooldownStats.chargeInfoActive = _abCooldownStats.chargeInfoActive + 1 end
            if _cooldownBatchActive then
                _batchChargeActive[action] = true
            end
            return true
        end
        if _cooldownBatchActive then
            _batchChargeActive[action] = nil
        end
        return nil
    end

    local function GetActionChargeDurationObject(action)
        if not C_ActionBar.GetActionChargeDuration then return nil end
        if _cooldownBatchActive
            and _batchChargeDurationSeen[action] == _cooldownBatchToken then
            return _batchChargeDurationObject[action]
        end

        if _abCooldownStats then _abCooldownStats.chargeDurationQueries = _abCooldownStats.chargeDurationQueries + 1 end
        local durationObject = C_ActionBar.GetActionChargeDuration(action)
        if _cooldownBatchActive then
            _batchChargeDurationSeen[action] = _cooldownBatchToken
            _batchChargeDurationObject[action] = durationObject
        end
        if durationObject then
            if _abCooldownStats then _abCooldownStats.chargeDurationActive = _abCooldownStats.chargeDurationActive + 1 end
        end
        return durationObject
    end

    local function GetActionLoCInfo(action)
        if not C_ActionBar.GetActionLossOfControlCooldownInfo then return DEFAULT_LOC_INFO end
        if _cooldownBatchActive
            and _batchLoCInfoSeen[action] == _cooldownBatchToken then
            if _abCooldownStats then _abCooldownStats.lossOfControlInfoHits = _abCooldownStats.lossOfControlInfoHits + 1 end
            return _batchLoCInfo[action]
        end

        if _abCooldownStats then _abCooldownStats.lossOfControlInfoQueries = _abCooldownStats.lossOfControlInfoQueries + 1 end
        local locInfo = C_ActionBar.GetActionLossOfControlCooldownInfo(action)
        if type(locInfo) ~= "table" then locInfo = DEFAULT_LOC_INFO end
        if _cooldownBatchActive then
            _batchLoCInfoSeen[action] = _cooldownBatchToken
            _batchLoCInfo[action] = locInfo
        end
        return locInfo
    end

    function ActionBarsOwned.UpdateCooldown(button)
        if _abCooldownStats then _abCooldownStats.buttons = _abCooldownStats.buttons + 1 end
        local action = GetSafeActionSlot(button)
        if not action then return end

        local cooldown = button.cooldown or button.Cooldown
        if not cooldown then return end

        if USE_DURATION_OBJECTS then
            local _, cdDurationObject, cdActive = GetActionCooldownState(button, action)
            local chActive = GetActionChargeActive(button, action)
            local chargeDurObj = chActive == true and GetActionChargeDurationObject(action) or nil
            if cdActive == false and chActive ~= true and not PlayerMayHaveLossOfControl() then
                if _buttonWasActive[button] then
                    _buttonWasActive[button] = nil
                    ClearCooldown(cooldown)
                    ClearCooldown(button.chargeCooldown)
                    local loc = GetLoCCooldown(button)
                    ClearCooldown(loc)
                end
                return
            end
            _buttonWasActive[button] = true

            local locInfo = GetActionLoCInfo(action)

            local locActive = locInfo.isActive
            local locReplacesNormal = locInfo.shouldReplaceNormalCooldown
            local showLoC    = locActive ~= false
            local showCharge = locReplacesNormal ~= true and chActive == true
            local showNormal = locReplacesNormal ~= true and cdActive ~= false

            if showNormal then
                SetOrClearCooldown(cooldown, true, cdDurationObject)
            else
                ClearCooldown(cooldown)
            end

            if showCharge then
                SetOrClearCooldown(GetOrCreateChargeCooldown(button), true, chargeDurObj)
            elseif button.chargeCooldown then
                ClearCooldown(button.chargeCooldown)
            end

            if showLoC then
                if _abCooldownStats then _abCooldownStats.lossOfControlDurationQueries = _abCooldownStats.lossOfControlDurationQueries + 1 end
                SetOrClearCooldown(GetOrCreateLoCCooldown(button), true, C_ActionBar.GetActionLossOfControlCooldownDuration(action))
            else
                local loc = GetLoCCooldown(button)
                ClearCooldown(loc)
            end
        else
            if ActionButton_UpdateCooldown then
                ns.SafeCall("compat", ActionButton_UpdateCooldown, button)
            end
        end
    end

    local _lastCdUpdateTime = 0
    function ActionBarsOwned.UpdateAllCooldowns()
        local now = GetTime()
        if now == _lastCdUpdateTime then return end
        _lastCdUpdateTime = now
        if _abCooldownStats then _abCooldownStats.batches = _abCooldownStats.batches + 1 end

        local activeButtons = ActionBarsOwned._activeButtons
        BeginCooldownBatch()
        if next(activeButtons) ~= nil then
            for btn in pairs(activeButtons) do
                local barKey = btn._quiBarKey
                if not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey) then
                    ns.SafeCall("best-effort-style", ActionBarsOwned.UpdateCooldown, btn)
                else
                    activeButtons[btn] = nil
                    ActionBarsOwned._activeStandardButtons[btn] = nil
                end
            end
            EndCooldownBatch()
            return
        end

        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local buttons = ActionBarsOwned.nativeButtons[barKey]
            if buttons then
                for _, btn in ipairs(buttons) do
                    local action = GetSafeActionSlot(btn)
                    if action
                        and (not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(btn, barKey))
                        and HasAction(action) then
                        ns.SafeCall("best-effort-style", ActionBarsOwned.UpdateCooldown, btn)
                    end
                end
            end
        end
        EndCooldownBatch()
    end

end
