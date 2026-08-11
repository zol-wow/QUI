local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue

local type = type
local pcall = pcall
local ipairs = ipairs

local CastEngine = {}
ns.CastEngine = CastEngine

local function SafeToNumber(v)
    if IsSecretValue(v) then
        return nil -- @secret-policy: reject-secret-value — callers branch on nil
    end
    if v == nil then return nil end
    if type(v) == "number" then return v end
    local ok, n = pcall(tonumber, v)
    if ok and type(n) == "number" then return n end
    return nil
end

function CastEngine.GetCastInfo(unit)
    local spellName, text, texture, startTimeMS, endTimeMS, _, _, notInterruptible, unitSpellID = UnitCastingInfo(unit)
    local isChanneled = false
    local channelStages = 0
    local channelSpellID = nil

    if IsSecretValue(spellName) then
    elseif not spellName then
        spellName, text, texture, startTimeMS, endTimeMS, _, notInterruptible, channelSpellID, _, channelStages = UnitChannelInfo(unit)
        if IsSecretValue(spellName) then
            isChanneled = true -- @secret-policy: opaque-value-present — a secret channel name means a channel is in progress
        elseif spellName then
            isChanneled = true
            if IsSecretValue(channelSpellID) or IsSecretValue(unitSpellID) then
            elseif channelSpellID and not unitSpellID then
                unitSpellID = channelSpellID
            end
        end
    end
    local casting = false
    if IsSecretValue(spellName) then
        casting = true -- @secret-policy: opaque-value-present — a secret cast name means a cast is in progress
    elseif spellName ~= nil then
        casting = true
    end

    local durationObj = nil
    if casting then
        local getDurationFn = isChanneled and UnitChannelDuration or UnitCastingDuration
        if type(getDurationFn) == "function" then
            local ok, dur = pcall(getDurationFn, unit)
            if ok then durationObj = dur end
        end
    end

    local hasSecretTiming = false
    if casting then
        if IsSecretValue(startTimeMS) or IsSecretValue(endTimeMS) then
            hasSecretTiming = true
        elseif startTimeMS and endTimeMS then
            local ok = pcall(function() return startTimeMS + 0 end) -- @secret-safe: deliberate arithmetic probe under pcall; both operands probed non-secret above
            if not ok then hasSecretTiming = true end
        end
    end

    return spellName, text, texture, startTimeMS, endTimeMS, notInterruptible, unitSpellID, isChanneled, channelStages, durationObj, hasSecretTiming
end

function CastEngine.GetDurationSeconds(durationObj)
    if not durationObj then return nil end

    local getters = {
        "GetTotalDuration",
        "GetDuration",
        "GetMaxDuration",
        "GetRemainingDuration",
        "GetRemaining",
    }

    for _, methodName in ipairs(getters) do
        local getter = durationObj[methodName]
        if getter then
            local ok, value = pcall(getter, durationObj)
            if ok then
                value = SafeToNumber(value)
                if value and value > 0 then
                    return value
                end
            end
        end
    end
    return nil
end

function CastEngine.ResolveNonPlayerTiming(spellName, startTimeMS, endTimeMS, durationObj, statusBar, hasSecretTiming)
    if type(spellName) == "nil" then
        return false, false, nil, nil
    end

    local supportsTimerDriven = durationObj and statusBar and statusBar.SetTimerDuration

    if hasSecretTiming and supportsTimerDriven then
        return true, true, nil, nil
    end

    if not hasSecretTiming and startTimeMS and endTimeMS then
        local success, startTime, endTime = pcall(function()
            return startTimeMS / 1000, endTimeMS / 1000
        end)
        if success then
            return true, false, startTime, endTime
        end
    end

    if supportsTimerDriven then
        return true, true, nil, nil
    end

    return false, false, nil, nil
end

function CastEngine.ApplyTimerDriven(statusBar, durationObj, direction)
    if not (statusBar and statusBar.SetTimerDuration and durationObj) then
        return false
    end
    local ok = ns.SafeCallMethod("sink-forward", statusBar, "SetTimerDuration", durationObj, 0, direction or 0)
    if not ok then
        ok = ns.SafeCallMethod("sink-forward", statusBar, "SetTimerDuration", durationObj)
    end
    return ok
end

function CastEngine.UpdateTimerText(bar)
    if bar.timeText and bar.durationObj then
        local obj = bar.durationObj
        if bar._durationGetterObj ~= obj then
            bar._durationGetter = obj.GetRemainingDuration or obj.GetRemaining
            bar._durationGetterObj = obj
        end
        local getter = bar._durationGetter
        if getter then
            local ok, rem = pcall(getter, obj)
            if ok and rem ~= nil then
                bar.timeText:SetFormattedText("%.1f", rem)
            end
        end
    end
end
