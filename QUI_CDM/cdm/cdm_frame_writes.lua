local _, ns = ...

---------------------------------------------------------------------------
-- CDM Renderers
--
-- Small frame-write facade for owned cooldown visuals. Resolvers and
-- source adapters must not call these; renderers are the only boundary that
-- writes to cooldown frames.
--
-- Secret-safe Blizzard API policy lives in docs/blizzard/cdm-api-reference.md
-- and tests/api-docs/cdm_blizzard_reference.lua.
---------------------------------------------------------------------------

local CDMRenderers = {}
ns.CDMRenderers = CDMRenderers
local issecretvalue = issecretvalue

function CDMRenderers.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    if not cd or not durObj or not cd.SetCooldownFromDurationObject then
        return false
    end

    if clearWhenZero == nil then
        clearWhenZero = true
    end

    cd.SetCooldownFromDurationObject(cd, durObj, clearWhenZero)
    if reverse ~= nil and cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
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

    if cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    cd.SetCooldown(cd, startTime, duration)
    return true
end


function CDMRenderers.ClearCooldown(cd, reverse)
    if not cd then return end
    if reverse ~= nil and cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    if cd.Clear then
        cd.Clear(cd)
    end
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
    if not statusBar or not durObj or not statusBar.SetTimerDuration then
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
