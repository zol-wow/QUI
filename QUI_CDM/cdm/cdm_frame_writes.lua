local _, ns = ...

-- and tests/api-docs/cdm_blizzard_reference.lua.

local CDMRenderers = {}
ns.CDMRenderers = CDMRenderers
local issecretvalue = issecretvalue
local Helpers = ns.Helpers

local function CanMutateCooldown(cd)
    return not Helpers or not Helpers.CanMutateCooldown or Helpers.CanMutateCooldown(cd)
end

function CDMRenderers.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    if not cd or type(durObj) == "nil" or not cd.SetCooldownFromDurationObject then
        return false
    end
    if not CanMutateCooldown(cd) then return false end

    if clearWhenZero == nil then
        clearWhenZero = true
    end

    local setOk, setErr = pcall(cd.SetCooldownFromDurationObject, cd, durObj, clearWhenZero)
    if not setOk then
        CDMRenderers._lastCooldownSetError = setErr
        return false
    end
    CDMRenderers._lastCooldownSetError = nil
    if reverse ~= nil and cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    if cd.GetCooldownDuration then
        local ok, applied = pcall(cd.GetCooldownDuration, cd)
        if ok then
            if issecretvalue and issecretvalue(applied) then
                return true -- @secret-policy: opaque-value-present
            end
            if type(applied) == "number" and applied <= 0 then
                return false
            end
        end
    end
    return true
end

function CDMRenderers.ApplyNumericCooldown(cd, startTime, duration, reverse)
    if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
        return false
    end
    if not cd or not cd.SetCooldown or not startTime or not duration then
        return false
    end
    if not CanMutateCooldown(cd) then return false end

    if cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    cd.SetCooldown(cd, startTime, duration)
    return true
end

function CDMRenderers.ClearCooldown(cd, reverse)
    if not cd then return end
    if not CanMutateCooldown(cd) then return false end
    if reverse ~= nil and cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    if cd.Clear then
        cd.Clear(cd)
    end
    return true
end

function CDMRenderers.SetStatusBarValue(statusBar, value, minValue, maxValue)
    if not statusBar then return false end
    if statusBar.SetMinMaxValues then
        statusBar.SetMinMaxValues(statusBar, minValue or 0, maxValue or 1)
    end
    if statusBar.SetValue then
        statusBar.SetValue(statusBar, value)
    end
    return true
end

function CDMRenderers.SetStatusBarFull(statusBar)
    return CDMRenderers.SetStatusBarValue(statusBar, 1, 0, 1)
end

function CDMRenderers.ClearStatusBar(statusBar)
    return CDMRenderers.SetStatusBarValue(statusBar, 0, 0, 1)
end

local STATUS_BAR_INTERPOLATION_IMMEDIATE = 0
local STATUS_BAR_TIMER_REMAINING = 1

function CDMRenderers.SetStatusBarTimerDuration(statusBar, durObj, direction)
    if not statusBar or type(durObj) == "nil" or not statusBar.SetTimerDuration then
        return false
    end
    local ok = pcall(
        statusBar.SetTimerDuration,
        statusBar,
        durObj,
        STATUS_BAR_INTERPOLATION_IMMEDIATE,
        direction or STATUS_BAR_TIMER_REMAINING
    )
    return ok and true or false
end
