local _, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local CDMBars = {}
ns.CDMBars = CDMBars
local Sources = ns.CDMSources
local Renderers = ns.CDMRenderers

local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

local type = type
local ipairs = ipairs
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue

local MAX_RECYCLE_POOL_SIZE = 20
local STATUS_BAR_INTERPOLATION_IMMEDIATE = 0
local STATUS_BAR_TIMER_REMAINING = 1

local function setResolveCallerTag(tag)
    local R = ns.CDMResolvers
    if R and R.SetResolveCallerTag then R.SetResolveCallerTag(tag) end
end

local function SetStatusBarValue(statusBar, value)
    if Renderers and Renderers.SetStatusBarValue then
        return Renderers.SetStatusBarValue(statusBar, value, 0, 1)
    end
    if not statusBar then return false end
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(value)
    return true
end

local function SetStatusBarFull(statusBar)
    if Renderers and Renderers.SetStatusBarFull then
        return Renderers.SetStatusBarFull(statusBar)
    end
    return SetStatusBarValue(statusBar, 1)
end

local function ClearStatusBar(statusBar)
    if Renderers and Renderers.ClearStatusBar then
        return Renderers.ClearStatusBar(statusBar)
    end
    return SetStatusBarValue(statusBar, 0)
end

local function GetBorderSizePx(frame, settings)
    local borderSize = settings and settings.borderSize
    if type(borderSize) ~= "number" then
        borderSize = 2
    end
    if borderSize <= 0 then return 0 end
    if QUICore and QUICore.Pixels then
        return QUICore:Pixels(borderSize, frame)
    end
    if QUICore and QUICore.GetPixelSize then
        return borderSize * QUICore:GetPixelSize(frame)
    end
    return borderSize
end

local function SetStatusBarTimerDuration(statusBar, durObj)
    if Renderers and Renderers.SetStatusBarTimerDuration then
        return Renderers.SetStatusBarTimerDuration(statusBar, durObj, STATUS_BAR_TIMER_REMAINING)
    end
    if not statusBar or not durObj or not statusBar.SetTimerDuration then
        return false
    end
    statusBar:SetTimerDuration(durObj, STATUS_BAR_INTERPOLATION_IMMEDIATE, STATUS_BAR_TIMER_REMAINING)
    return true
end

local function RearmVisibleDurationBarTimer(bar, deferOneFrame)
    if not (bar and bar._active and not bar._hideDurationText) then
        return false
    end

    local durObj = bar._durObj
    if not durObj or type(durObj) == "number" then
        return false
    end

    local statusBar = bar.StatusBar
    if not (statusBar and statusBar.SetTimerDuration) then
        return false
    end

    local ok = SetStatusBarTimerDuration(statusBar, durObj)
    if ok then
        bar._cSideFill = true
        bar._preferDurObjFill = true
    end

    if deferOneFrame and C_Timer and C_Timer.After and not bar._timerShowRearmPending then
        bar._timerShowRearmPending = true
        C_Timer.After(0, function()
            bar._timerShowRearmPending = nil
            RearmVisibleDurationBarTimer(bar, false)
        end)
    end

    return ok
end

local function AuraInstanceListContains(list, auraInstanceID)
    if type(list) ~= "table" or auraInstanceID == nil then return false end
    for _, listedAuraInstanceID in ipairs(list) do
        if listedAuraInstanceID == auraInstanceID then
            return true
        end
    end
    return false
end

local function BarAuraUnitMatches(bar, unit)
    if not unit then return true end
    local barUnit = bar and (bar._auraUnit or bar._auraDataUnit)
    return barUnit == nil or barUnit == unit
end

function CDMBars.MarkBarAuraRefresh(bar, unit, updateInfo)
    if not (bar and bar._active and BarAuraUnitMatches(bar, unit)) then
        return false
    end

    local auraInstanceID = bar._auraInstanceID
    if updateInfo == nil or updateInfo.isFullUpdate == true then
        if auraInstanceID ~= nil or bar._durObj ~= nil then
            bar._forceTimerDurationRebind = true
            return true
        end
        return false
    end

    if auraInstanceID == nil then return false end
    if AuraInstanceListContains(updateInfo.updatedAuraInstanceIDs, auraInstanceID)
        or AuraInstanceListContains(updateInfo.removedAuraInstanceIDs, auraInstanceID) then
        bar._forceTimerDurationRebind = true
        return true
    end

    return false
end

local barPool = {}
local recyclePool = {}
local barTimerFrame = CreateFrame("Frame")
local barTimerGroup = barTimerFrame:CreateAnimationGroup()
local barTimerAnim = barTimerGroup:CreateAnimation()
barTimerAnim:SetDuration(0.1)
barTimerGroup:SetLooping("REPEAT")

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_barPool",      tbl = barPool }
    mp[#mp + 1] = { name = "CDM_barRecycle",   tbl = recyclePool }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local _lastContainer = nil
local _lastSettings = nil

local _pendingResize = nil

local function _flushPendingResizes()
    local q = _pendingResize
    _pendingResize = nil
    if not q then return end
    for container, dims in pairs(q) do
        if container.SetSize then
            container:SetSize(dims.w, dims.h)
        end
        if _G.QUI_SetCDMViewerBounds then
            _G.QUI_SetCDMViewerBounds(container, dims.w, dims.h)
        end
    end
end

local function ResizeContainer(container, w, h)
    if not container then return end
    if container._lastBarLayoutW == w and container._lastBarLayoutH == h then
        return
    end
    container._lastBarLayoutW = w
    container._lastBarLayoutH = h

    if (not InCombatLockdown()) or ns._inInitSafeWindow then
        container:SetSize(w, h)
        if _G.QUI_SetCDMViewerBounds then
            _G.QUI_SetCDMViewerBounds(container, w, h)
        end
        return
    end

    if not _pendingResize then
        _pendingResize = {}
        C_Timer.After(0, _flushPendingResizes)
    end
    local entry = _pendingResize[container]
    if entry then
        entry.w = w
        entry.h = h
    else
        _pendingResize[container] = { w = w, h = h }
    end
end

-- C_CurveUtil.EvaluateColorValueFromBoolean is a C-side helper that

local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(200, 25)

    local statusBar = CreateFrame("StatusBar", nil, bar)
    ClearStatusBar(statusBar)
    bar.StatusBar = statusBar

    local permanentFill = statusBar:CreateTexture(nil, "OVERLAY", nil, 1)
    permanentFill:SetAllPoints(statusBar)
    permanentFill:SetAlpha(0)
    bar.PermanentFill = permanentFill

    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 1)
    bar.Background = bg

    local iconContainer = CreateFrame("Frame", nil, bar)
    iconContainer:SetSize(25, 25)
    bar.IconContainer = iconContainer

    local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconContainer)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.IconTexture = iconTex

    local borderFrame = CreateFrame("Frame", nil, bar)
    borderFrame:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 5)
    borderFrame._top = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._top:SetColorTexture(0, 0, 0, 1)
    borderFrame._bottom = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._bottom:SetColorTexture(0, 0, 0, 1)
    borderFrame._left = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._left:SetColorTexture(0, 0, 0, 1)
    borderFrame._right = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._right:SetColorTexture(0, 0, 0, 1)
    bar.BorderContainer = borderFrame

    local textOverlay = CreateFrame("Frame", nil, statusBar)
    textOverlay:SetAllPoints(statusBar)
    textOverlay:SetFrameLevel((statusBar.GetFrameLevel and statusBar:GetFrameLevel() or 1) + 2)
    bar.TextOverlay = textOverlay

    local nameText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    CJKFont(nameText, GetGeneralFont(), 14, GetGeneralFontOutline())
    nameText:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)
    bar.NameText = nameText

    local durationText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    CJKFont(durationText, GetGeneralFont(), 14, GetGeneralFontOutline())
    durationText:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    durationText:SetJustifyH("RIGHT")
    durationText:SetTextColor(1, 1, 1, 1)
    durationText:SetShadowColor(0, 0, 0, 1)
    durationText:SetShadowOffset(1, -1)
    bar.DurationText = durationText

    bar._spellEntry = nil
    bar._spellID = nil
    bar._active = false
    bar._cSideFill = nil
    bar._preferDurObjFill = nil

    bar:Hide()
    return bar
end

local function GetBarSpellData(bar)
    local entry = bar and bar._spellEntry
    if not entry then return nil end
    local baseSpellID = entry.spellID or entry.id
    local overrideSpellID = entry.overrideSpellID
    local resolvedSpellID = overrideSpellID or baseSpellID
    if not resolvedSpellID and not entry.name then return nil end
    return {
        id = entry.id,
        spellID = resolvedSpellID,
        baseSpellID = baseSpellID or resolvedSpellID,
        overrideSpellID = overrideSpellID,
        linkedSpellID = entry.linkedSpellID,
        linkedSpellIDs = entry.linkedSpellIDs,
        name = entry.name,
        cooldownID = entry.cooldownID,
    }
end

local function GetBarSpellHideDurationOverride(bar)
    local entry = bar and bar._spellEntry
    if not entry then return nil end
    local CDMSpellData = ns.CDMSpellData
    if not CDMSpellData or not entry.viewerType then return nil end
    local spellID = entry.spellID or entry.id
    if not spellID then return nil end
    local ov = CDMSpellData:GetSpellOverride(entry.viewerType, spellID)
    if ov and ov.hideDurationText == true then return true end
    return nil
end

---@type fun(...)
local DebugBarLabel = function() end

local function ReadBoolean(value)
    if issecretvalue and issecretvalue(value) then return nil end -- @secret-policy: reject-secret-value
    if type(value) == "boolean" then return value end
    return nil
end

local function ReadNumber(value, fallback)
    if issecretvalue and issecretvalue(value) then return fallback end
    local valueType = type(value)
    if valueType == "number" then return value end
    if valueType == "string" then return tonumber(value) end
    return fallback
end

local function WrapStackSuffix(stackValue)
    if C_StringUtil and C_StringUtil.WrapString then
        return C_StringUtil.WrapString(stackValue, " (", ")")
    end
    return stackValue
end

local function IsMissingOrKnownEmptyText(value)
    if issecretvalue and issecretvalue(value) then return false end -- @secret-policy: route-to-text-sink
    if value == nil then return true end
    return type(value) == "string" and value == ""
end

local function ValueIsPresent(value)
    if issecretvalue and issecretvalue(value) then return true end -- @secret-policy: opaque-value-present
    return value ~= nil
end

local function ApplyNameTextWithCount(fontString, name, count)
    if not fontString or not fontString.SetFormattedText or name == nil then
        return false, "missing-name"
    end

    if not count or ReadBoolean(count.shown) ~= true then
        fontString.SetFormattedText(fontString, "%s", name)
        return true, "name-only", nil, false
    end

    local countText = count.sinkText
    if not ValueIsPresent(countText) then
        countText = count.value
    end

    if IsMissingOrKnownEmptyText(countText) then
        fontString.SetFormattedText(fontString, "%s", name)
        return true, "name-only", nil, false
    end

    local wrappedStack = WrapStackSuffix(countText)
    if IsMissingOrKnownEmptyText(wrappedStack) then
        fontString.SetFormattedText(fontString, "%s", name)
        return true, "name-only", wrappedStack, false
    end

    fontString.SetFormattedText(fontString, "%s%s", name, wrappedStack)
    return true, "wrapped-count", wrappedStack, false
end

CDMBars.ApplyNameTextWithCount = ApplyNameTextWithCount

local function NormalizeTrackedBarRuntimeEntries(runtimeEntries)
    if type(runtimeEntries) ~= "table" or #runtimeEntries == 0 then
        return nil
    end

    local spellList = {}
    for i, entry in ipairs(runtimeEntries) do
        if type(entry) == "table" then
            local runtimeSpellID = entry.linkedSpellID or entry.overrideSpellID or entry.spellID or entry.baseSpellID
            local baseSpellID = entry.baseSpellID or entry.spellID or runtimeSpellID
            local id = runtimeSpellID or entry.cooldownID
            if id then
                local instanceID = entry.cooldownID or runtimeSpellID or entry.layoutIndex or i
                spellList[#spellList + 1] = {
                    id = id,
                    spellID = baseSpellID,
                    baseSpellID = baseSpellID,
                    overrideSpellID = entry.overrideSpellID,
                    linkedSpellID = entry.linkedSpellID,
                    linkedSpellIDs = entry.linkedSpellIDs,
                    name = entry.name or "",
                    type = "spell",
                    kind = "aura",
                    isAura = true,
                    viewerType = "trackedBar",
                    source = "blizzardCDM",
                    cooldownID = entry.cooldownID,
                    layoutIndex = entry.layoutIndex or i,
                    iconTexture = entry.iconTexture,
                    _instanceKey = "trackedBar:" .. tostring(instanceID),
                    _trackedBarRuntime = true,
                    _trackedBarActive = entry.isActive == true,
                    _blzFrame = entry.frame,
                }
            end
        end
    end

    if #spellList == 0 then
        return nil
    end
    return spellList
end

CDMBars._NormalizeTrackedBarRuntimeEntries = NormalizeTrackedBarRuntimeEntries

local function CopyTrackedEntry(entry)
    local out = {}
    if type(entry) ~= "table" then return out end
    for k, v in pairs(entry) do
        out[k] = v
    end
    return out
end

local function AddTrackedSpellIdentity(out, value)
    if value == nil then return end
    out[tostring(value)] = true
end

local function BuildTrackedSpellIdentitySet(entry, includeLinkedSpellIDs)
    local out = {}
    if type(entry) ~= "table" then return out end
    AddTrackedSpellIdentity(out, entry.id)
    AddTrackedSpellIdentity(out, entry.spellID)
    AddTrackedSpellIdentity(out, entry.baseSpellID)
    AddTrackedSpellIdentity(out, entry.overrideSpellID)
    AddTrackedSpellIdentity(out, entry.itemID)
    if includeLinkedSpellIDs and type(entry.linkedSpellIDs) == "table" then
        for _, linkedSpellID in ipairs(entry.linkedSpellIDs) do
            AddTrackedSpellIdentity(out, linkedSpellID)
        end
    end
    return out
end

local function TrackedEntriesMatch(configured, runtime)
    if type(configured) ~= "table" or type(runtime) ~= "table" then
        return false
    end

    local configuredIDs = BuildTrackedSpellIdentitySet(configured)
    if runtime.linkedSpellID ~= nil and not configuredIDs[tostring(runtime.linkedSpellID)] then
        local cfgPrimary = configured.overrideSpellID or configured.spellID or configured.id
        if cfgPrimary ~= nil and tostring(cfgPrimary) ~= tostring(runtime.spellID) then
            return false
        end
    end
    local runtimeIDs = BuildTrackedSpellIdentitySet(runtime, runtime.linkedSpellID == nil)
    for id in pairs(configuredIDs) do
        if runtimeIDs[id] then
            return true
        end
    end

    if configured.cooldownID ~= nil and runtime.cooldownID ~= nil then
        return tostring(configured.cooldownID) == tostring(runtime.cooldownID)
    end
    return false
end

local function FindTrackedRuntimeMatch(configured, runtimeSpellList, usedRuntime)
    if type(runtimeSpellList) ~= "table" then return nil end
    for i = 1, #runtimeSpellList do
        local runtime = runtimeSpellList[i]
        if not usedRuntime[i] and TrackedEntriesMatch(configured, runtime) then
            usedRuntime[i] = true
            return runtime
        end
    end
    return nil
end

local function FindTrackedRuntimeExactVariant(configured, runtimeSpellList, usedRuntime)
    if type(runtimeSpellList) ~= "table" or type(configured) ~= "table" then return nil end
    local configuredIDs = BuildTrackedSpellIdentitySet(configured)
    for i = 1, #runtimeSpellList do
        local runtime = runtimeSpellList[i]
        if not usedRuntime[i] and type(runtime) == "table"
            and runtime.linkedSpellID ~= nil
            and configuredIDs[tostring(runtime.linkedSpellID)] then
            usedRuntime[i] = true
            return runtime
        end
    end
    return nil
end

local function MergeTrackedRuntimeFields(configured, runtime)
    local out = CopyTrackedEntry(configured)
    if type(runtime) ~= "table" then
        return out
    end

    if out.spellID == nil then out.spellID = runtime.spellID end
    if out.baseSpellID == nil then out.baseSpellID = runtime.baseSpellID end
    if out.overrideSpellID == nil then out.overrideSpellID = runtime.overrideSpellID end
    out.linkedSpellID = runtime.linkedSpellID
    out.linkedSpellIDs = runtime.linkedSpellIDs or out.linkedSpellIDs
    if (out.name == nil or out.name == "") and runtime.name then out.name = runtime.name end
    if out.iconTexture == nil then out.iconTexture = runtime.iconTexture end
    out.cooldownID = runtime.cooldownID
    out.layoutIndex = runtime.layoutIndex
    out._instanceKey = runtime._instanceKey
    out._trackedBarRuntime = runtime._trackedBarRuntime == true
    out._trackedBarActive = runtime._trackedBarActive == true
    out._blzFrame = runtime._blzFrame
    return out
end

local function BuildTrackedBarSpellList(runtimeEntries, configuredSpellList, configuredOwnedInitialized)
    local runtimeSpellList = NormalizeTrackedBarRuntimeEntries(runtimeEntries)
    if not configuredOwnedInitialized then
        return runtimeSpellList
    end

    local out = {}
    local usedRuntime = {}
    if type(configuredSpellList) ~= "table" then
        return out
    end

    local exactMatches = {}
    for i = 1, #configuredSpellList do
        local configured = configuredSpellList[i]
        if type(configured) == "table" then
            exactMatches[i] = FindTrackedRuntimeExactVariant(configured, runtimeSpellList, usedRuntime)
        end
    end

    for i = 1, #configuredSpellList do
        local configured = configuredSpellList[i]
        if type(configured) == "table" then
            local runtime = exactMatches[i]
                or FindTrackedRuntimeMatch(configured, runtimeSpellList, usedRuntime)
            out[#out + 1] = MergeTrackedRuntimeFields(configured, runtime)
        end
    end
    return out
end

CDMBars._BuildTrackedBarSpellList = BuildTrackedBarSpellList

local function ContainerOwnedListInitialized(containerKey)
    local shared = ns.CDMShared
    local getDB = shared and shared.GetContainerDB
    local db = getDB and getDB(containerKey)
    return db and db.ownedSpells ~= nil or false
end

local function ShouldHideAuraDurationText(r)
    if not r or not r.isActive then return false end
    if r.isTotemInstance then return false end
    if r.hideDurationText or r.hasExpirationTime == false then return true end
    if not r.auraData then return false end
    if InCombatLockdown() then return false end

    local duration = ReadNumber(r.auraData.duration, nil)
    if duration == nil then
        return true
    end
    return duration <= 0
end

local function EnsureBarTimerRunning()
    if barTimerGroup and barTimerGroup.IsPlaying and barTimerGroup.Play
       and not barTimerGroup:IsPlaying() then
        barTimerGroup:Play()
    end
end

local CreateDurationTextBinding = C_DurationUtil and C_DurationUtil.CreateDurationTextBinding
local CreateSecondsFormatter = C_StringUtil and C_StringUtil.CreateSecondsFormatter

local barDurationFormatter
local function GetBarDurationFormatter()
    if barDurationFormatter ~= nil then
        return barDurationFormatter or nil
    end
    if not CreateSecondsFormatter then
        barDurationFormatter = false
        return nil
    end
    local ok, fmt = ns.SafeCall("best-effort-style", CreateSecondsFormatter)
    if not ok or not fmt then
        barDurationFormatter = false
        return nil
    end
    ns.SafeCallMethodIfPresent("best-effort-style", fmt, "SetMillisecondsThreshold", 10)
    if fmt.SetDefaultAbbreviation and Enum and Enum.SecondsFormatterAbbreviation then
        ns.SafeCallMethod("best-effort-style", fmt, "SetDefaultAbbreviation", Enum.SecondsFormatterAbbreviation.OneLetter)
    end
    if fmt.SetStripIntervalWhitespace and Enum and Enum.SecondsFormatterIntervalWhitespace then
        ns.SafeCallMethod("best-effort-style", fmt, "SetStripIntervalWhitespace", Enum.SecondsFormatterIntervalWhitespace.Strip)
    end
    barDurationFormatter = fmt
    return fmt
end

local function EnsureBarDurationBinding(bar)
    if not CreateDurationTextBinding then return nil end
    if bar._durTextBinding ~= nil then
        return bar._durTextBinding or nil
    end
    if not bar.DurationText then
        bar._durTextBinding = false
        return nil
    end
    local fmt = GetBarDurationFormatter()
    if not fmt then
        bar._durTextBinding = false
        return nil
    end
    local ok, binding = ns.SafeCall("best-effort-style", CreateDurationTextBinding)
    if not ok or not binding or not binding.SetFontString or not binding.SetFormatter then
        bar._durTextBinding = false
        return nil
    end
    local okBind = ns.SafeCallMethod("best-effort-style", binding, "SetFontString", bar.DurationText)
    if not okBind then
        bar._durTextBinding = false
        return nil
    end
    ns.SafeCallMethod("best-effort-style", binding, "SetFormatter", fmt)
    ns.SafeCallMethodIfPresent("best-effort-style", binding, "SetZeroDurationText", "")
    ns.SafeCallMethodIfPresent("best-effort-style", binding, "SetExpiredText", "")
    bar._durTextBinding = binding
    return binding
end

local function DisableBarDurationBinding(bar, clearText)
    local binding = bar and bar._durTextBinding
    ns.SafeCallMethodIfPresent("best-effort-style", binding, "SetEnabled", false)
    if bar then bar._boundDurObj = nil end
    if clearText and bar and bar.DurationText then
        bar.DurationText.SetText(bar.DurationText, "")
    end
end

local function WriteDurationTextFromDurationObject(bar, durObj)
    if not (bar and durObj and bar.DurationText and not bar._hideDurationText) then
        return false
    end

    local binding = EnsureBarDurationBinding(bar)
    if binding then
        if bar._boundDurObj ~= durObj then
            ns.SafeCallMethod("sink-forward", binding, "SetDuration", durObj)
            ns.SafeCallMethodIfPresent("best-effort-style", binding, "SetEnabled", true)
            bar._boundDurObj = durObj
        end
        return true
    end

    if not durObj.GetRemainingDuration then
        return false
    end
    local remaining = durObj.GetRemainingDuration(durObj)
    bar.DurationText.SetFormattedText(bar.DurationText, "%.1f", remaining)
    return true
end

local function GetTrackedBarOverrideColorFromEntry(settings, entry)
    local overrides = settings and settings.colorOverrides
    if type(overrides) ~= "table" or type(entry) ~= "table" then
        return nil
    end

    local function lookup(id)
        if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then
            return nil
        end
        local color = overrides[id]
        return type(color) == "table" and color or nil
    end

    local color = lookup(entry.id) or lookup(entry.spellID)
        or lookup(entry.overrideSpellID) or lookup(entry.baseSpellID)
        or lookup(entry.linkedSpellID) or lookup(entry.cooldownID)
    if color then return color end

    local linked = entry.linkedSpellIDs
    if type(linked) == "table" and not (issecretvalue and issecretvalue(linked)) then
        for i = 1, #linked do
            color = lookup(linked[i])
            if color then return color end
        end
    end

    return nil
end

local function GetTrackedBarOverrideColor(settings, spellData)
    return GetTrackedBarOverrideColorFromEntry(settings, spellData)
end

local function GetTrackedBarOverrideColorForEntry(settings, entry)
    return GetTrackedBarOverrideColorFromEntry(settings, entry)
end

local function ColorStateChanged(state, color)
    local r, g, b, a = 0, 0, 0, 0
    if type(color) == "table" then
        r = tonumber(color[1]) or 0
        g = tonumber(color[2]) or 0
        b = tonumber(color[3]) or 0
        a = tonumber(color[4]) or 0
    end
    local changed = state[1] ~= r or state[2] ~= g
        or state[3] ~= b or state[4] ~= a
    state[1], state[2], state[3], state[4] = r, g, b, a
    return changed
end

function CDMBars.ConfigureBar(bar, settings, overrideWidth, activeOverride)
    if not bar then return end

    bar._borderSettings = settings

    local barHeight = settings.barHeight or 25
    local barWidth = overrideWidth or settings.barWidth or 215
    local texture = settings.texture or "Quazii v5"
    local useClassColor = settings.useClassColor
    local barColor = settings.barColor or {0.376, 0.647, 0.980, 1}
    local barOpacity = settings.barOpacity or 1.0
    local borderSizePx = GetBorderSizePx(bar, settings)
    local bgColor = settings.bgColor or {0, 0, 0, 1}
    local bgOpacity = settings.bgOpacity or 0.5
    local textSize = settings.textSize or 14
    local hideIcon = settings.hideIcon
    local hideText = settings.hideText

    local inactiveMode = settings.inactiveMode or "hide"
    if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
        inactiveMode = "hide"
    end
    local inactiveAlpha = settings.inactiveAlpha or 0.3
    if inactiveAlpha < 0 then inactiveAlpha = 0 end
    if inactiveAlpha > 1 then inactiveAlpha = 1 end
    local desaturateInactive = (settings.desaturateInactive == true)

    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local fillDirection = settings.fillDirection or "up"
    local iconPosition = settings.iconPosition or "top"
    local showTextOnVertical = settings.showTextOnVertical or false

    local isActive = activeOverride
    if isActive == nil then isActive = bar._active end
    local spellData = GetBarSpellData(bar)
    local overrideColor = GetTrackedBarOverrideColor(settings, spellData)

    local frameWidth, frameHeight
    if isVertical then
        frameWidth = barHeight
        frameHeight = barWidth
    else
        frameWidth = barWidth
        frameHeight = barHeight
    end

    bar:SetSize(frameWidth, frameHeight)

    local statusBar = bar.StatusBar
    if statusBar then
        statusBar:SetSize(frameWidth, frameHeight)
        if statusBar.SetOrientation then
            statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        end
        if isVertical and statusBar.SetReverseFill then
            statusBar:SetReverseFill(fillDirection == "down")
        end
    end

    local iconContainer = bar.IconContainer
    if iconContainer then
        if hideIcon then
            iconContainer:Hide()
            iconContainer:SetAlpha(0)
        else
            iconContainer:Show()
            iconContainer:SetAlpha(1)
            local iconSize = isVertical and frameWidth or frameHeight
            iconContainer:SetSize(iconSize, iconSize)

            if bar.IconTexture and bar.IconTexture.SetDesaturated then
                bar.IconTexture:SetDesaturated((not isActive) and desaturateInactive and inactiveMode ~= "always")
            end
        end
    end

    if statusBar then
        statusBar:ClearAllPoints()
        if isVertical then
            if hideIcon or not iconContainer then
                statusBar:SetAllPoints(bar)
            else
                iconContainer:ClearAllPoints()
                if iconPosition == "bottom" then
                    iconContainer:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("BOTTOM", iconContainer, "TOP", 0, 0)
                else
                    iconContainer:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("TOP", iconContainer, "BOTTOM", 0, 0)
                end
            end
        else
            if hideIcon or not iconContainer then
                statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
            else
                iconContainer:ClearAllPoints()
                iconContainer:SetPoint("LEFT", bar, "LEFT", 0, 0)
                statusBar:SetPoint("LEFT", iconContainer, "RIGHT", 0, 0)
            end
            statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
            statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
            statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
    end

    local resolvedTexturePath
    if statusBar and statusBar.SetStatusBarTexture then
        resolvedTexturePath = LSM:Fetch("statusbar", texture) or LSM:Fetch("statusbar", "Quazii v5")
        if resolvedTexturePath then
            statusBar:SetStatusBarTexture(resolvedTexturePath)
        end
    end
    if bar.PermanentFill and resolvedTexturePath then
        bar.PermanentFill:SetTexture(resolvedTexturePath)
    end

    local resolvedR, resolvedG, resolvedB, resolvedA
    if statusBar and statusBar.SetStatusBarColor then
        local c = barColor
        if overrideColor then
            resolvedR, resolvedG, resolvedB, resolvedA =
                overrideColor[1] or 0.2, overrideColor[2] or 0.8, overrideColor[3] or 0.6, barOpacity
        elseif useClassColor then
            local _, class = UnitClass("player")
            -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
            if issecretvalue and issecretvalue(class) then class = nil end
            local color = class and RAID_CLASS_COLORS[class]
            if color then
                resolvedR, resolvedG, resolvedB, resolvedA = color.r, color.g, color.b, barOpacity
            else
                resolvedR, resolvedG, resolvedB, resolvedA =
                    c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity
            end
        else
            resolvedR, resolvedG, resolvedB, resolvedA =
                c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity
        end
        statusBar:SetStatusBarColor(resolvedR, resolvedG, resolvedB, resolvedA)
    end
    if bar.PermanentFill and resolvedR then
        bar.PermanentFill:SetVertexColor(resolvedR, resolvedG, resolvedB, resolvedA or 1)
    end

    local bg = bar.Background
    if bg then
        local bgR, bgG, bgB = bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0
        bg:SetColorTexture(bgR, bgG, bgB, 1)
        if statusBar then
            bg:ClearAllPoints()
            bg:SetAllPoints(statusBar)
        end
        bg:SetAlpha(bgOpacity)
        bg:Show()
    end

    local borderFrame = bar.BorderContainer
    if borderFrame then
        if borderSizePx > 0 then
            borderFrame:ClearAllPoints()
            borderFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSizePx, borderSizePx)
            borderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSizePx, -borderSizePx)

            borderFrame._top:ClearAllPoints()
            borderFrame._top:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._top:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._top:SetHeight(borderSizePx)

            borderFrame._bottom:ClearAllPoints()
            borderFrame._bottom:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._bottom:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._bottom:SetHeight(borderSizePx)

            borderFrame._left:ClearAllPoints()
            borderFrame._left:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._left:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._left:SetWidth(borderSizePx)

            borderFrame._right:ClearAllPoints()
            borderFrame._right:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._right:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._right:SetWidth(borderSizePx)

            local sbR, sbG, sbB, sbA = Helpers.GetSkinBorderColor(settings, "")
            borderFrame._top:SetColorTexture(sbR, sbG, sbB, sbA)
            borderFrame._bottom:SetColorTexture(sbR, sbG, sbB, sbA)
            borderFrame._left:SetColorTexture(sbR, sbG, sbB, sbA)
            borderFrame._right:SetColorTexture(sbR, sbG, sbB, sbA)

            borderFrame:Show()
        else
            borderFrame:Hide()
        end
    end

    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()
    local showText = not hideText and (not isVertical or showTextOnVertical)

    if bar.NameText then
        CJKFont(bar.NameText, generalFont, textSize, generalOutline)
        bar.NameText:SetAlpha(showText and 1 or 0)
    end
    if bar.DurationText then
        CJKFont(bar.DurationText, generalFont, textSize, generalOutline)
        local durationBaseAlpha = showText and 1 or 0
        bar.DurationText:SetAlpha(durationBaseAlpha)
        bar._durationTextBaseAlpha = durationBaseAlpha
    end

    local targetAlpha = 1
    if not isActive then
        if inactiveMode == "fade" then
            targetAlpha = inactiveAlpha
        elseif inactiveMode == "hide" then
            targetAlpha = 0
        end
    end
    bar:SetAlpha(targetAlpha)
end

function CDMBars.CreateForPreview(parent)
    return CreateBar(parent)
end

local function AcquireBar(parent)
    local bar
    if #recyclePool > 0 then
        bar = table.remove(recyclePool)
        bar:SetParent(parent)
    else
        bar = CreateBar(parent)
    end
    bar:Show()
    barPool[#barPool + 1] = bar
    return bar
end

local function ReleaseBar(bar)
    if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearFrame then
        ns.CDMRuntimeStore.ClearFrame(bar)
    end
    bar:Hide()
    bar:ClearAllPoints()
    bar._spellEntry = nil
    bar._spellID = nil
    bar._instanceKey = nil
    bar._active = false
    bar._auraUnit = nil
    bar._auraInstanceID = nil
    bar._blzChild = nil
    bar._blzCooldownID = nil
    bar._blzChildMissAt = nil
    bar._cSideFill = nil
    bar._preferDurObjFill = nil
    bar._forceTimerDurationRebind = nil
    bar._timerShowRearmPending = nil
    bar._lastPosKey = nil
    bar._lastAnchor = nil
    bar._cfgFingerprint = nil
    bar._cfgActive = nil
    bar._lastFrameLevel = nil
    bar._desiredTexture = nil
    bar._isTotemInstance = nil
    bar._totemSlot = nil
    bar._totemIconCache = nil
    bar._totemNameCache = nil
    bar._hideDurationText = nil
    bar._hasAuraExpirationTime = nil
    DisableBarDurationBinding(bar)
    bar.NameText:SetText("")
    bar.DurationText:SetText("")
    bar.IconTexture:SetTexture(nil)
    ClearStatusBar(bar.StatusBar)
    if bar.PermanentFill then
        bar.PermanentFill:SetAlpha(0)
    end
    bar.DurationText:SetAlpha(bar._durationTextBaseAlpha or 1)

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        recyclePool[#recyclePool + 1] = bar
    end
end

function CDMBars:ClearPool()
    for i = #barPool, 1, -1 do
        ReleaseBar(barPool[i])
        barPool[i] = nil
    end
end

function CDMBars:GetActiveBars()
    return barPool
end

function CDMBars:MarkAuraRefresh(unit, updateInfo)
    local marked = false
    for _, bar in ipairs(barPool) do
        if CDMBars.MarkBarAuraRefresh(bar, unit, updateInfo) then
            marked = true
        end
    end
    return marked
end

function CDMBars:ClearPerBarCaches()
    for i = 1, #barPool do
        local bar = barPool[i]
        if bar then
            bar._totemIconCache = nil
            bar._totemNameCache = nil
        end
    end
end

function CDMBars:GetCacheStats()
    return {
        activeBars = #barPool,
    }
end

function CDMBars:BuildBarsFromOwned(container, spellList)
    if not container then return end
    if not spellList or #spellList == 0 then
        self:ClearPool()
        return
    end

    local needsRebuild = (#spellList ~= #barPool)
    if not needsRebuild then
        for i, bar in ipairs(barPool) do
            local entry = spellList[i]
            local entrySpellID = entry.overrideSpellID or entry.spellID or entry.id
            if bar._spellID ~= entrySpellID or bar._instanceKey ~= entry._instanceKey then
                needsRebuild = true
                break
            end
        end
    end

    if not needsRebuild and #barPool > 0 then
        local firstParent = barPool[1]:GetParent()
        if firstParent ~= container then
            needsRebuild = true
        end
    end

    if not needsRebuild then
        for i, bar in ipairs(barPool) do
            local entry = spellList[i]
            if bar._isOwnedBar and bar._spellID then
                if entry then
                    bar._spellEntry = entry
                    bar._instanceKey = entry._instanceKey
                    bar._isTotemInstance = entry._isTotemInstance and true or false
                    bar._totemSlot = entry._totemSlot
                    bar._spellID = entry.overrideSpellID or entry.spellID or entry.id
                    bar._blzChild = entry._blzFrame or bar._blzChild
                    bar._blzCooldownID = entry._blzFrame and entry.cooldownID or bar._blzCooldownID
                    if entry._blzFrame then bar._blzChildMissAt = nil end
                end
                self:UpdateOwnedBarAura(bar)
            end
        end
        return
    end

    self:ClearPool()

    for _, entry in ipairs(spellList) do
        local bar = AcquireBar(container)
        bar._spellEntry = entry
        bar._isOwnedBar = true
        bar._instanceKey = entry._instanceKey
        bar._isTotemInstance = entry._isTotemInstance and true or false
        bar._totemSlot = entry._totemSlot

        local spellID = entry.overrideSpellID or entry.spellID or entry.id
        bar._spellID = spellID

        bar._blzChild = entry._blzFrame
        bar._blzCooldownID = entry._blzFrame and entry.cooldownID or nil
        bar._blzChildMissAt = nil

        if bar.IconTexture and spellID and not bar._isTotemInstance then
            local texID = entry.iconTexture
            if not texID and (entry.type == "item" or entry.type == "slot") then
                if entry.type == "slot" then
                    texID = Sources and Sources.QueryInventoryItemTexture
                        and Sources.QueryInventoryItemTexture("player", entry.id)
                else
                    local _, _, _, _, icon
                    if Sources and Sources.QueryItemInfoInstant then
                        _, _, _, _, icon = Sources.QueryItemInfoInstant(spellID)
                    end
                    texID = icon
                end
            elseif not texID and entry.type == "spell" then
                local iconSid
                if entry.isAura then
                    iconSid = entry.overrideSpellID or entry.spellID or entry.id or spellID
                else
                    iconSid = entry.overrideSpellID or entry.id or spellID
                end
                local info
                if Sources and Sources.QuerySpellInfo then
                    info = Sources.QuerySpellInfo(iconSid)
                end
                texID = info and info.iconID
            end
            if texID then
                bar.IconTexture.SetTexture(bar.IconTexture, texID)
                bar._desiredTexture = texID
            end
        end

        if bar.NameText and not bar._isTotemInstance then
            local displayName = entry and entry.name
                or (ns.CDMSpellData and ns.CDMSpellData:ResolveDisplayName(entry))
            if displayName then
                bar.NameText:SetText(displayName)
            end
        end

        self:UpdateOwnedBarAura(bar)
    end
end

local BuildBarCooldownStateContext

local function StoreBarRuntimeState(bar, mode, active, extra)
    if not (ns.CDMRuntimeStore and ns.CDMRuntimeStore.SetBarState) then return end
    local state = {
        mode = mode,
        active = active and true or false,
        spellID = bar and bar._spellID,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            state[k] = v
        end
    end
    ns.CDMRuntimeStore.SetBarState(bar, state)
end

local function ApplyResolvedItemBarDurationObject(bar, itemID, r)
    local durObj = r and r.durObj
    if not durObj or type(durObj) == "number" then
        return false
    end
    if not (bar and bar.StatusBar and bar.StatusBar.SetTimerDuration) then
        return false
    end

    local ok = SetStatusBarTimerDuration(bar.StatusBar, durObj)
    if not ok then
        return false
    end

    bar._active = true
    bar._hideDurationText = nil
    bar._hasAuraExpirationTime = r.hasExpirationTime
    bar._durObj = durObj
    bar._cSideFill = true
    bar._preferDurObjFill = true

    local startTime
    local duration
    if r.numericCooldownActive == true
       and type(r.start) == "number"
       and type(r.duration) == "number" then
        startTime = r.start
        duration = r.duration
        bar._totalDuration = duration
        bar._expirationTime = startTime + duration
    else
        bar._totalDuration = nil
        bar._expirationTime = nil
    end

    WriteDurationTextFromDurationObject(bar, durObj)
    EnsureBarTimerRunning()
    StoreBarRuntimeState(bar, r.mode or "item-cooldown", true, {
        itemID = itemID,
        spellID = r.spellID,
        durObj = durObj,
        start = startTime,
        duration = duration,
        isOnCooldown = r.isOnCooldown == true,
        rechargeActive = r.rechargeActive == true,
        hasCharges = r.hasCharges == true,
        hasChargesRemaining = r.hasChargesRemaining == true,
        hasExpirationTime = r.hasExpirationTime,
    })
    return true
end

local function ClearItemBarInactive(bar, itemID)
    bar._active = false
    bar._hideDurationText = nil
    bar._hasAuraExpirationTime = nil
    bar._durObj = nil
    bar._cSideFill = nil
    bar._preferDurObjFill = nil
    bar._totalDuration = nil
    bar._expirationTime = nil
    ClearStatusBar(bar.StatusBar)
    DisableBarDurationBinding(bar, true)
    StoreBarRuntimeState(bar, "inactive", false, { itemID = itemID })
end

local function UpdateItemBarCooldown(bar, entry)
    local itemID
    if entry.type == "slot" or entry.type == "trinket" then
        itemID = Sources and Sources.QueryInventoryItemID
            and Sources.QueryInventoryItemID("player", entry.id)
    else
        itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
    end

    if bar.IconTexture and itemID then
        local tex = Sources and Sources.QueryItemIconByID
            and Sources.QueryItemIconByID(itemID)
        if tex then
            bar.IconTexture.SetTexture(bar.IconTexture, tex)
            bar._desiredTexture = tex
        end
    end

    if bar.NameText and itemID then
        local n = Sources and Sources.QueryItemNameByID
            and Sources.QueryItemNameByID(itemID)
        if n then bar.NameText.SetText(bar.NameText, n) end
    end

    local scanner = _G.QUI and _G.QUI.SpellScanner
    local isActive, auraDur, auraRemaining
    if Sources and Sources.QueryScannedItemAuraInfo and itemID then
        local scanned = Sources.QueryScannedItemAuraInfo(itemID)
        if scanned and scanned.active == true then
            local readableDuration = ReadNumber(scanned.duration, nil)
            local readableExpiration = ReadNumber(scanned.expiration, nil)
            if readableDuration and readableDuration > 0 then
                isActive = true
                auraDur = readableDuration
                if readableExpiration then
                    auraRemaining = readableExpiration - GetTime()
                end
            end
        end
    end
    if not isActive and scanner and scanner.IsItemActive and itemID then
        local active, expiration, duration = scanner.IsItemActive(itemID)
        local readableDuration = ReadNumber(duration, nil)
        local readableExpiration = ReadNumber(expiration, nil)
        if active and readableDuration and readableDuration > 0 then
            isActive = true
            auraDur = readableDuration
            if readableExpiration then
                auraRemaining = readableExpiration - GetTime()
            end
        end
    end

    if isActive and auraRemaining and auraRemaining > 0 then
        bar._active = true
        bar._hideDurationText = GetBarSpellHideDurationOverride(bar)
        bar._hasAuraExpirationTime = nil
        bar._durObj = nil
        bar._cSideFill = nil
        bar._preferDurObjFill = nil
        bar._totalDuration = auraDur
        bar._expirationTime = GetTime() + auraRemaining
        SetStatusBarValue(bar.StatusBar, auraRemaining / auraDur)
        StoreBarRuntimeState(bar, "item-aura", true, {
            itemID = itemID,
            duration = auraDur,
            remaining = auraRemaining,
        })
        return
    end

    local isAuraKind = entry and entry.kind == "aura"
    local containerDB
    if ns.CDMShared and ns.CDMShared.GetContainerDB then
        containerDB = ns.CDMShared.GetContainerDB(entry and entry.viewerType)
    end
    local isCustom = ns.CDMShared and ns.CDMShared.IsCustomBarContainer
        and ns.CDMShared.IsCustomBarContainer(containerDB) or false
    local isAuraOnlyOverride = isCustom
        and entry and entry.displayMode == "auraOnly"
        and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")

    if isAuraKind or isAuraOnlyOverride then
        ClearItemBarInactive(bar, itemID)
        return
    end

    local resolver = ns.CDMResolvers and ns.CDMResolvers.ResolveCooldownState
    local context = resolver and BuildBarCooldownStateContext(bar, entry, bar._spellID)
    setResolveCallerTag("ownedBar")
    local r = context and resolver(context)
    setResolveCallerTag(nil)
    local startTime = r and r.start
    local duration = r and r.duration

    if r and (r.isActive == true or r.isOnCooldown == true)
       and ApplyResolvedItemBarDurationObject(bar, itemID, r) then
        return
    end

    if r and r.mode == "item-cooldown"
       and r.isOnCooldown == true
       and r.numericCooldownActive == true
       and type(startTime) == "number"
       and type(duration) == "number"
       and not (issecretvalue and issecretvalue(startTime))
       and not (issecretvalue and issecretvalue(duration)) then
        local remaining = (startTime + duration) - GetTime()
        if remaining > 0 then
            bar._active = true
            bar._hideDurationText = GetBarSpellHideDurationOverride(bar)
            bar._hasAuraExpirationTime = nil
            bar._durObj = nil
            bar._cSideFill = nil
            bar._preferDurObjFill = nil
            bar._totalDuration = duration
            bar._expirationTime = startTime + duration
            SetStatusBarValue(bar.StatusBar, remaining / duration)
            StoreBarRuntimeState(bar, "item-cooldown", true, {
                itemID = itemID,
                spellID = r.spellID,
                start = startTime,
                duration = duration,
                remaining = remaining,
                isOnCooldown = r.isOnCooldown == true,
                rechargeActive = r.rechargeActive == true,
                hasCharges = r.hasCharges == true,
                hasChargesRemaining = r.hasChargesRemaining == true,
            })
            return
        end
    end

    ClearItemBarInactive(bar, itemID)
end

local IsSpellCooldownEntry

local _barCooldownStateContextOptions = {
    fallbackContainerKey = "trackedBar",
}

function BuildBarCooldownStateContext(bar, entry, spellID)
    local resolvers = ns.CDMResolvers
    local builder = resolvers and resolvers.BuildCooldownStateContext
    if not builder then return nil end

    local options = _barCooldownStateContextOptions
    options.containerKey = entry and entry.viewerType
    options.totemSlot = bar and bar._totemSlot
    options.useBuffSwipe = not IsSpellCooldownEntry(entry)
    options.skipAuraPhase = nil
    return builder(bar, entry, spellID, options)
end

function IsSpellCooldownEntry(entry)
    if not entry then return false end
    local entryType = entry.type
    if entryType
        and entryType ~= "spell"
        and entryType ~= "cooldown" then
        return false
    end
    return entry.kind == "cooldown" or entryType == "cooldown"
end

local function FindBlzChildByCooldownID(cooldownID)
    local viewer = _G.BuffBarCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return nil end
    for child in pool:EnumerateActive() do
        if child.Bar then
            local cid = child.cooldownID
            if not (issecretvalue and issecretvalue(cid)) and cid == cooldownID then
                return child
            end
        end
    end
    return nil
end

local BLZ_CHILD_MISS_RETRY = 0.25

local function GetPairedBlzChild(bar)
    local wantCid = bar._blzCooldownID
    if not wantCid then return nil end
    local blz = bar._blzChild
    if blz then
        local cid = blz.cooldownID
        if not (issecretvalue and issecretvalue(cid)) and cid == wantCid then
            return blz
        end
    end
    local now = GetTime()
    local missAt = bar._blzChildMissAt
    if missAt and (now - missAt) < BLZ_CHILD_MISS_RETRY then
        return nil
    end
    local found = FindBlzChildByCooldownID(wantCid)
    bar._blzChild = found
    bar._blzChildMissAt = not found and now or nil
    return found
end

local function ReadPairedBarActive(blz)
    if blz.IsActive then
        local ok, active = pcall(blz.IsActive, blz)
        if ok then
            if issecretvalue and issecretvalue(active) then return true end -- @secret-policy: keep-visible-when-unknown
            return active and true or false
        end
        return true
    end
    if blz.IsShown then
        local ok, shown = pcall(blz.IsShown, blz)
        return ok and shown and true or false
    end
    return false
end

local barFillInterpolation = Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut

local function MirrorPairedBarVisuals(bar, blz)
    local nativeBar = blz.Bar
    if not nativeBar or not nativeBar.GetValue then return end
    local sb = bar.StatusBar
    if sb then
        sb.SetMinMaxValues(sb, nativeBar:GetMinMaxValues())
        local smooth = bar._mirrorWasShown and barFillInterpolation
        if smooth then
            sb.SetValue(sb, nativeBar:GetValue(), smooth)
        else
            sb.SetValue(sb, nativeBar:GetValue())
        end
        bar._mirrorWasShown = true
    end
    if bar.DurationText then
        if bar._hideDurationText then
            bar.DurationText.SetText(bar.DurationText, "")
        else
            local durationFS = nativeBar.Duration
            if durationFS and durationFS.GetText then
                bar.DurationText.SetText(bar.DurationText, durationFS:GetText())
            end
        end
    end
    if bar.NameText then
        local nameFS = nativeBar.Name
        if nameFS and nameFS.GetText then
            bar.NameText.SetText(bar.NameText, nameFS:GetText())
        end
    end
    if bar.IconTexture then
        local iconRegion = blz.Icon
        local iconTex = iconRegion and (iconRegion.Icon or iconRegion.icon or iconRegion.texture)
        if iconTex and iconTex.GetTexture then
            bar.IconTexture.SetTexture(bar.IconTexture, iconTex:GetTexture())
        end
    end
end

local UpdatePairedBarState
local pairedMirrorFrame = CreateFrame("Frame")
if pairedMirrorFrame.Hide then pairedMirrorFrame:Hide() end
local pairedMirrorAccum = 0
pairedMirrorFrame:SetScript("OnUpdate", function(self, elapsed)
    pairedMirrorAccum = pairedMirrorAccum + elapsed
    if pairedMirrorAccum < 0.016 then return end
    pairedMirrorAccum = 0
    local anyPaired = false
    local activeChanged = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._blzCooldownID then
            anyPaired = true
            local blz = GetPairedBlzChild(bar)
            if blz then
                if ReadPairedBarActive(blz) ~= bar._active then
                    UpdatePairedBarState(bar, blz)
                    activeChanged = true
                end
                MirrorPairedBarVisuals(bar, blz)
            end
        end
    end
    if not anyPaired then
        self:Hide()
    end
    if activeChanged and _lastContainer and _lastSettings then
        CDMBars:LayoutBars(_lastContainer, _lastSettings)
    end
end)

UpdatePairedBarState = function(bar, blz)
    local active = ReadPairedBarActive(blz)
    bar._active = active
    bar._hideDurationText = GetBarSpellHideDurationOverride(bar)
    if bar._boundDurObj then DisableBarDurationBinding(bar) end
    bar._durObj = nil
    bar._cSideFill = nil
    bar._preferDurObjFill = nil
    if bar.PermanentFill then
        bar.PermanentFill.SetAlpha(bar.PermanentFill, 0)
    end
    if not active then
        bar._mirrorWasShown = nil
    end
    StoreBarRuntimeState(bar, active and "aura" or "inactive", active, nil)
    if pairedMirrorFrame.Show then
        pairedMirrorFrame:Show()
    end
end

function CDMBars:UpdateOwnedBarAura(bar)
    if not bar or not bar._spellID then return end
    local spellID = bar._spellID
    local entry = bar._spellEntry
    if not ns.CDMSpellData then return end

    local blz = GetPairedBlzChild(bar)
    if blz then
        UpdatePairedBarState(bar, blz)
        return
    end
    if bar._blzCooldownID then return end

    if entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot") then
        UpdateItemBarCooldown(bar, entry)
        return
    end
    if entry and entry.viewerType == "trackedBar" and entry.kind == "aura"
       and not bar._isTotemInstance then return end

    local resolver = ns.CDMResolvers and ns.CDMResolvers.ResolveCooldownState
    if not resolver then return end
    local context = BuildBarCooldownStateContext(bar, entry, spellID)
    if not context then return end
    setResolveCallerTag("ownedBar")
    local r = resolver(context)
    setResolveCallerTag(nil)
    if not r then return end
    local count = r.count
    StoreBarRuntimeState(bar, r.mode or (r.isActive and "aura" or "inactive"), r.isActive, {
        durObj = r.durObj,
        auraUnit = r.auraUnit,
        countShown = count and count.shown == true,
        countValue = count and count.value or nil,
        countSource = count and count.source or nil,
        hasExpirationTime = r.hasExpirationTime,
    })

    local _bname = entry and entry.name

    if r.isActive then
        bar._active = true
        bar._auraDataUnit = r.auraUnit
        bar._auraUnit = r.auraUnit
        bar._auraInstanceID = r.auraInstanceID
        bar._hasAuraExpirationTime = r.hasExpirationTime
        bar._hideDurationText = ShouldHideAuraDurationText(r)
            or GetBarSpellHideDurationOverride(bar)

        if not bar._hideDurationText and not r.durObj and r.auraData
            and not InCombatLockdown() then
            local readableDur = ReadNumber(r.auraData.duration, 0)
            if readableDur <= 0 then
                bar._hideDurationText = true
            end
        end

        if bar._hideDurationText then
            bar._durObj = nil
            bar._cSideFill = nil
            bar._preferDurObjFill = nil
            bar._forceTimerDurationRebind = nil
            bar._totalDuration = nil
            bar._expirationTime = nil
            SetStatusBarFull(bar.StatusBar)
            if bar.PermanentFill then
                bar.PermanentFill.SetAlpha(bar.PermanentFill, 0)
            end
            DisableBarDurationBinding(bar)
            if bar.DurationText then
                bar.DurationText.SetText(bar.DurationText, "")
                bar.DurationText.SetAlpha(bar.DurationText, bar._durationTextBaseAlpha or 1)
            end
        end

        if r.auraData and not bar._hideDurationText
            and not InCombatLockdown() then
            local rawDur = ReadNumber(r.auraData.duration, nil)
            if rawDur and rawDur > 0 then
                bar._totalDuration = rawDur
            end
        end

        local durObj = r.durObj
        if durObj and not bar._hideDurationText then
            local prevDurObj = bar._durObj
            local forceRebind = bar._forceTimerDurationRebind == true
            bar._durObj = durObj
            local canUseTimerDuration = bar.StatusBar and bar.StatusBar.SetTimerDuration
            bar._preferDurObjFill = canUseTimerDuration and true or nil
            if bar._cSideFill then
                if forceRebind or durObj ~= prevDurObj then
                    if canUseTimerDuration then
                        local ok = SetStatusBarTimerDuration(bar.StatusBar, durObj)
                        if not ok then
                            bar._preferDurObjFill = nil
                            bar._cSideFill = nil
                        end
                        bar._forceTimerDurationRebind = nil
                    end
                end
            elseif bar.StatusBar then
                if canUseTimerDuration then
                    local ok = SetStatusBarTimerDuration(bar.StatusBar, durObj)
                    if ok then
                        bar._cSideFill = true
                    else
                        bar._preferDurObjFill = nil
                        bar._cSideFill = nil
                    end
                    bar._forceTimerDurationRebind = nil
                end
            end

            if durObj.IsZero
               and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local isZero = durObj.IsZero(durObj)
                if bar.PermanentFill then
                    local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 1, 0)
                    bar.PermanentFill.SetAlpha(bar.PermanentFill, alpha)
                end
                if bar.DurationText and (bar._durationTextBaseAlpha or 1) ~= 0 then
                    local textAlpha = C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 0, 1)
                    bar.DurationText.SetAlpha(bar.DurationText, textAlpha)
                end
            end
            WriteDurationTextFromDurationObject(bar, durObj)
            EnsureBarTimerRunning()
        end

        if bar.IconTexture then
            if bar._isTotemInstance then
                if r.totemIcon ~= nil then
                    bar._totemIconCache = r.totemIcon
                end
                if bar._totemIconCache ~= nil then
                    bar.IconTexture.SetTexture(bar.IconTexture, bar._totemIconCache)
                end
            else
                local runtimeTex
                if r.auraData then
                    runtimeTex = r.auraData.icon
                end
                if not runtimeTex and entry and entry.isAura then
                    local sid = entry.overrideSpellID or entry.spellID or entry.id
                    if sid then
                        local tex = Sources and Sources.QuerySpellTexture
                            and Sources.QuerySpellTexture(sid)
                        if tex then runtimeTex = tex end
                    end
                end
                if runtimeTex then
                    bar.IconTexture.SetTexture(bar.IconTexture, runtimeTex)
                elseif bar._desiredTexture ~= nil then
                    bar.IconTexture.SetTexture(bar.IconTexture, bar._desiredTexture)
                end
            end
        end

        if bar.NameText then
            local name
            if bar._isTotemInstance then
                if r.totemName ~= nil then
                    bar._totemNameCache = r.totemName
                end
                name = bar._totemNameCache
            elseif entry and entry.isAura then
                name = entry.name or ns.CDMSpellData:ResolveDisplayName(entry)
            else
                name = ns.CDMSpellData:ResolveDisplayName(entry)
            end
            if name ~= nil then
                local setOk, countMethod, countText, countSecret =
                    ApplyNameTextWithCount(bar.NameText, name, r.count)
                if _G.QUI_CDM_BAR_DEBUG then
                    local resolvedCount = r.count
                    local countShown = resolvedCount and resolvedCount.shown == true
                    DebugBarLabel(
                        entry, spellID,
                        "label",
                        "name=", tostring(name),
                        "countShown=", tostring(countShown),
                        "countSecret=", tostring(countSecret == true),
                        "countSource=", tostring(resolvedCount and resolvedCount.source or nil),
                        "countMethod=", countMethod,
                        "countOk=", tostring(setOk),
                        "countText=", countSecret and "<secret>" or tostring(countText),
                        "setOk=", tostring(setOk),
                        "setErr=", "nil")
                end
            end
        end
    else
        bar._active = false
        bar._auraUnit = nil
        bar._auraInstanceID = nil
        bar._durObj = nil
        bar._cSideFill = nil
        bar._preferDurObjFill = nil
        bar._forceTimerDurationRebind = nil
        bar._totalDuration = nil
        bar._expirationTime = nil
        bar._hideDurationText = nil
        bar._hasAuraExpirationTime = nil
        ClearStatusBar(bar.StatusBar)
        if bar.PermanentFill then
            bar.PermanentFill.SetAlpha(bar.PermanentFill, 0)
        end
        DisableBarDurationBinding(bar)
        if bar.DurationText then
            bar.DurationText:SetText("")
            bar.DurationText.SetAlpha(bar.DurationText, bar._durationTextBaseAlpha or 1)
        end

        if bar.NameText and entry and entry.name and entry.name ~= ""
            and not bar._isTotemInstance then
            bar.NameText.SetText(bar.NameText, entry.name)
        end
    end

end

function CDMBars:LayoutBars(container, settings)
    if not container then return end
    if not settings then return end

    local barHeight = settings.barHeight or 25
    local barWidth = settings.barWidth or 215

    local count = #barPool

    if count == 0 then
        local orientation = settings.orientation or "horizontal"
        local w, h
        if orientation == "vertical" then
            w, h = barHeight, barWidth
        else
            w, h = barWidth, barHeight
        end
        ResizeContainer(container, w, h)
        return
    end

    local stylingEnabled = settings.enabled
    local spacing = settings.spacing or 2
    local growFromBottom = (settings.growUp ~= false)
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local inactiveMode = settings.inactiveMode or "hide"
    local reserveSlotWhenInactive = (settings.reserveSlotWhenInactive == true)

    local effectiveBarWidth, effectiveBarHeight
    if isVertical then
        effectiveBarWidth = barHeight
        effectiveBarHeight = barWidth
    else
        effectiveBarWidth = barWidth
        effectiveBarHeight = barHeight
    end

    local layoutActive = Helpers.IsLayoutModeActive()
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.buffBar or 5
    local frameLevel = 200
    if QUICore and QUICore.GetHUDFrameLevel then
        frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
    end
    if not layoutActive then
        container:SetFrameStrata("MEDIUM")
        container:SetFrameLevel(frameLevel)
    end

    local editModeActive = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    local visibleIndex = 0
    for _, bar in ipairs(barPool) do
        local fingerprint = bar._cfgFingerprint
        if not fingerprint then
            fingerprint = { border = {}, bar = {}, override = {} }
            bar._cfgFingerprint = fingerprint
        end
        if editModeActive then
            SetStatusBarValue(bar.StatusBar, 0.65)
            DisableBarDurationBinding(bar)
            if bar.DurationText then
                bar.DurationText:SetText("0:32")
            end
        end

        local configChanged = fingerprint.barHeight ~= (settings.barHeight or 0)
            or fingerprint.barWidth ~= (barWidth or 0)
            or fingerprint.borderSize ~= (settings.borderSize or 0)
            or fingerprint.textSize ~= (settings.textSize or 0)
            or fingerprint.barOpacity ~= (settings.barOpacity or 1)
            or fingerprint.useClassColor ~= (settings.useClassColor and 1 or 0)
            or fingerprint.borderSource ~= settings.borderColorSource
        local displayActive = editModeActive or bar._active
        fingerprint.barHeight = settings.barHeight or 0
        fingerprint.barWidth = barWidth or 0
        fingerprint.borderSize = settings.borderSize or 0
        fingerprint.textSize = settings.textSize or 0
        fingerprint.barOpacity = settings.barOpacity or 1
        fingerprint.useClassColor = settings.useClassColor and 1 or 0
        fingerprint.borderSource = settings.borderColorSource
        configChanged = ColorStateChanged(fingerprint.border, settings.borderColor) or configChanged
        configChanged = ColorStateChanged(fingerprint.bar, settings.barColor) or configChanged
        configChanged = ColorStateChanged(fingerprint.override,
            GetTrackedBarOverrideColorForEntry(settings, bar._spellEntry)) or configChanged
        if configChanged or bar._cfgActive ~= displayActive then
            bar._cfgActive = displayActive
            CDMBars.ConfigureBar(bar, settings, barWidth, displayActive)
        end

        if bar._lastFrameLevel ~= frameLevel then
            bar._lastFrameLevel = frameLevel
            bar:SetFrameStrata("MEDIUM")
            bar:SetFrameLevel(frameLevel)
            if bar.StatusBar then
                bar.StatusBar:SetFrameStrata("MEDIUM")
                bar.StatusBar:SetFrameLevel(frameLevel + 1)
            end
            if bar.TextOverlay then
                bar.TextOverlay:SetFrameStrata("MEDIUM")
                bar.TextOverlay:SetFrameLevel(frameLevel + 3)
            end
            if bar.IconContainer then
                bar.IconContainer:SetFrameStrata("MEDIUM")
                bar.IconContainer:SetFrameLevel(frameLevel + 1)
            end
        end

        local shouldShow = true

        if not editModeActive then
            local displayMode = settings.iconDisplayMode or "always"
            local effectiveDisplayMode = displayMode
            if effectiveDisplayMode == "combat" then
                effectiveDisplayMode = InCombatLockdown() and "always" or "active"
            end

            if effectiveDisplayMode == "active" then
                if not bar._active then
                    shouldShow = false
                end
            else
                if not bar._active then
                    if inactiveMode == "hide" and not reserveSlotWhenInactive then
                        shouldShow = false
                    end
                end
            end
        end

        if shouldShow then
            local wasShown = bar:IsShown()
            local offsetIndex = visibleIndex

            local anchor, relAnchor, offsetX, offsetY
            if isVertical then
                if growFromBottom then
                    anchor, relAnchor = "LEFT", "LEFT"
                    offsetX = QUICore:PixelRound(offsetIndex * (effectiveBarWidth + spacing))
                    offsetY = 0
                else
                    anchor, relAnchor = "RIGHT", "RIGHT"
                    offsetX = QUICore:PixelRound(-offsetIndex * (effectiveBarWidth + spacing))
                    offsetY = 0
                end
            else
                if growFromBottom then
                    anchor, relAnchor = "BOTTOM", "BOTTOM"
                    offsetX = 0
                    offsetY = QUICore:PixelRound(offsetIndex * (effectiveBarHeight + spacing))
                else
                    anchor, relAnchor = "TOP", "TOP"
                    offsetX = 0
                    offsetY = QUICore:PixelRound(-offsetIndex * (effectiveBarHeight + spacing))
                end
            end

            local posKey = offsetIndex
            if bar._lastPosKey ~= posKey or bar._lastAnchor ~= anchor
                or not bar:IsShown() then
                bar._lastPosKey = posKey
                bar._lastAnchor = anchor
                bar:ClearAllPoints()
                bar:SetPoint(anchor, container, relAnchor, offsetX, offsetY)
            end

            bar:Show()
            if not wasShown then
                RearmVisibleDurationBarTimer(bar, true)
            end
            visibleIndex = visibleIndex + 1
        else
            if bar:IsShown() then
                bar._lastPosKey = nil
                bar._lastAnchor = nil
                bar:Hide()
            end
        end
    end

    local totalW, totalH
    if visibleIndex == 0 then
        totalW = effectiveBarWidth
        totalH = effectiveBarHeight
    elseif isVertical then
        totalW = (visibleIndex * effectiveBarWidth) + ((visibleIndex - 1) * spacing)
        totalH = effectiveBarHeight
    else
        totalW = effectiveBarWidth
        totalH = (visibleIndex * effectiveBarHeight) + ((visibleIndex - 1) * spacing)
    end
    totalW = QUICore:PixelRound(totalW)
    totalH = QUICore:PixelRound(totalH)

    ResizeContainer(container, totalW, totalH)
end

function CDMBars:Refresh(container, settings, overrideWidth, containerKey, runtimeEntries)
    if not container then return end
    if not settings then return end

    if overrideWidth then
        settings = setmetatable({ barWidth = overrideWidth }, { __index = settings })
    end

    _lastContainer = container
    _lastSettings = settings

    local spellList
    if containerKey == "trackedBar" then
        local configuredOwnedInitialized = ContainerOwnedListInitialized(containerKey)
        local configuredSpellList
        if configuredOwnedInitialized and ns.CDMSpellData then
            configuredSpellList = ns.CDMSpellData:GetSpellList(containerKey)
        end
        spellList = BuildTrackedBarSpellList(runtimeEntries, configuredSpellList, configuredOwnedInitialized)
    end
    if not spellList and ns.CDMSpellData then
        spellList = ns.CDMSpellData:GetSpellList(containerKey or "trackedBar")
    end
    if spellList then
        self:BuildBarsFromOwned(container, spellList)
    else
        self:ClearPool()
    end
    self:LayoutBars(container, settings)
end

function CDMBars:UpdateOwnedBars()
    local anyChanged = false
    local anyActive = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._spellID then
            local wasPreviouslyActive = bar._active
            self:UpdateOwnedBarAura(bar)
            if bar._active ~= wasPreviouslyActive then
                anyChanged = true
            end
            if bar._active then anyActive = true end
        end
    end
    if anyActive and not barTimerGroup:IsPlaying() then
        barTimerGroup:Play()
    end
    if anyChanged and _lastContainer and _lastSettings then
        self:LayoutBars(_lastContainer, _lastSettings)
    end
end

barTimerGroup:SetScript("OnLoop", function()
    local Helpers = ns.Helpers
    local anyActive = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._active and bar:IsShown() then
            if GetPairedBlzChild(bar) then
                anyActive = true
            elseif bar._hideDurationText then
                anyActive = true
                if bar._boundDurObj then DisableBarDurationBinding(bar) end
                if bar.DurationText then
                    bar.DurationText.SetText(bar.DurationText, "")
                end
                SetStatusBarFull(bar.StatusBar)
            else
                local durObj = bar._durObj
                if durObj and type(durObj) == "number" then
                    bar._durObj = nil
                    durObj = nil
                end
                if durObj and durObj.GetRemainingDuration then
                    anyActive = true
                    WriteDurationTextFromDurationObject(bar, durObj)
                    if not bar._cSideFill and bar.StatusBar then
                        SetStatusBarFull(bar.StatusBar)
                    end
                end
            end
        end
    end
    if not anyActive then
        barTimerGroup:Stop()
    end
end)

ns.CDMBars = ns.CDMBars or CDMBars
function ns.CDMBars._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        DebugBarLabel = d.Bar or DebugBarLabel
    end
end

function CDMBars:RefreshSkinColors()
    local H = ns.Helpers
    if not (H and H.GetSkinBorderColor) then return end
    for _, bar in ipairs(self:GetActiveBars() or {}) do
        local bc = bar and bar.BorderContainer
        if bc and bc._top and bc._top.SetColorTexture then
            local r, g, b, a = H.GetSkinBorderColor(bar._borderSettings, "")
            bc._top:SetColorTexture(r, g, b, a)
            bc._bottom:SetColorTexture(r, g, b, a)
            bc._left:SetColorTexture(r, g, b, a)
            bc._right:SetColorTexture(r, g, b, a)
        end
    end
end

if ns.Registry then
    ns.Registry:Register("cdmBarsSkin", {
        refresh = function()
            if ns.CDMBars and ns.CDMBars.RefreshSkinColors then
                ns.CDMBars:RefreshSkinColors()
            end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
