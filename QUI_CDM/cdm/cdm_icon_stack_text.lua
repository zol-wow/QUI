local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Stack Text
--
-- Taint-aware stack/count text sink for icon FontStrings. CDMIconStackPolicy
-- decides what value should be shown; this module owns the write/clear
-- mechanics.
---------------------------------------------------------------------------

local CDMIconStackText = {}
ns.CDMIconStackText = CDMIconStackText

local type = type

local issecretvalue = issecretvalue or function() return false end

local function ApplyVisibilityGate(fontString, gate)
    if not (fontString and fontString.SetAlpha) then return end
    if issecretvalue(gate) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(gate, 1, 0)
            fontString.SetAlpha(fontString, alpha)
        end
        return
    end
    if gate == false then
        fontString.SetAlpha(fontString, 0)
    else
        fontString.SetAlpha(fontString, 1)
    end
end

function CDMIconStackText.TextHasDisplay(text)
    if issecretvalue(text) then
        return true
    end
    if type(text) == "string" then
        return text ~= ""
    end
    return text ~= nil
end

function CDMIconStackText.ValueIsPresent(value)
    if issecretvalue(value) then
        return true
    end
    return value ~= nil
end

function CDMIconStackText.ValueIsMissing(value)
    return not CDMIconStackText.ValueIsPresent(value)
end

function CDMIconStackText.Clear(icon)
    if not icon or not icon.StackText then return end
    if icon.StackText.SetText then
        icon.StackText.SetText(icon.StackText, "")
    end
    if icon.StackText.Hide then
        icon.StackText.Hide(icon.StackText)
    end
    icon._stackTextSource = nil
end

function CDMIconStackText.Show(icon, value, source, visibilityGate)
    if not icon or not icon.StackText then return false end
    local setOk = true
    local setErr = icon.StackText.SetText(icon.StackText, value)
    if not setOk and icon.StackText.SetFormattedText then
        setOk = true
        setErr = icon.StackText.SetFormattedText(icon.StackText, "%s", value)
    end

    local showOk = false
    local showErr
    if setOk then
        showOk = true
        showErr = icon.StackText.Show(icon.StackText)
    end

    local gate = visibilityGate
    if not issecretvalue(gate) and gate == nil and source == "ChargeCount" then
        gate = icon.cooldownChargesShown
        if not issecretvalue(gate) and gate == nil then
            gate = icon.chargeCountFrameShown
        end
    end
    ApplyVisibilityGate(icon.StackText, gate)

    if source ~= nil then
        icon._stackTextSource = source
    end

    return setOk, setErr, showOk, showErr
end
