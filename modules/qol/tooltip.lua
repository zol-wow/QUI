local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Provider
local TooltipInspect

local GameTooltip = GameTooltip
local UIParent = UIParent
local WorldFrame = WorldFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local wipe = wipe
local debugprofilestop = debugprofilestop
local collectgarbage = collectgarbage

local TooltipEngine = {}

local _dbgCounters, _dbgSlowLog
local TooltipDebug = ns.QUI_TooltipDebug
if not TooltipDebug then
    local debugCounters = {}
    local debugSlowLog = {}
    local debugSlowLogMax = 8
    local debugAutoFrame

    TooltipDebug = {
        enabled = false,
        interval = 5,
        elapsed = 0,
        slowThreshold = 1.5,
        counters = debugCounters,
        slowLog = debugSlowLog,
        lastMemoryKB = nil,
        lastHeapKB = nil,
        lastAddonKB = nil,
        lastReportTime = nil,
    }
    ns.QUI_TooltipDebug = TooltipDebug
    _dbgCounters = debugCounters
    _dbgSlowLog  = debugSlowLog

    local function DebugNowMS()
        if debugprofilestop then
            return debugprofilestop()
        end
        return (GetTime and GetTime() or 0) * 1000
    end

    local function FormatKB(kb)
        if type(kb) ~= "number" then
            return "?"
        end
        if math.abs(kb) >= 1024 then
            return string.format("%.1f MB", kb / 1024)
        end
        return string.format("%.0f KB", kb)
    end

    local function GetAddonMemoryKB()
        if UpdateAddOnMemoryUsage then
            ns.SafeCall("best-effort-style", UpdateAddOnMemoryUsage)
        end
        if GetAddOnMemoryUsage then
            local ok, mem = ns.SafeCall("chain-next", GetAddOnMemoryUsage, ADDON_NAME)
            if ok and type(mem) == "number" then
                return mem
            end
        end
        return nil
    end

    local function FrameLabel(frame)
        if not frame then return "nil" end
        if frame.GetName then
            local ok, name = ns.SafeCallMethod("chain-next", frame, "GetName")
            if ok and name then return name end
        end
        return tostring(frame)
    end

    local function DescribeTooltipContext()
        if not GameTooltip then
            return "gt=nil"
        end
        local okShown, shown = ns.SafeCallMethod("chain-next", GameTooltip, "IsShown")
        if not okShown or not shown then
            return "gt=hidden"
        end

        local owner
        if GameTooltip.GetOwner then
            local okOwner, result = ns.SafeCallMethod("chain-next", GameTooltip, "GetOwner")
            if okOwner then owner = result end
        end

        local unit
        if GameTooltip.GetUnit then
            local okUnit, _, result = pcall(GameTooltip.GetUnit, GameTooltip)
            if okUnit and result and not Helpers.IsSecretValue(result) then
                unit = result
            end
        end

        return string.format("gt=shown owner=%s unit=%s", FrameLabel(owner), tostring(unit or "nil"))
    end

    function TooltipDebug:Count(name, amount)
        if not self.enabled or not name then return end
        debugCounters[name] = (debugCounters[name] or 0) + (amount or 1)
    end

    function TooltipDebug:Begin()
        if not self.enabled then return nil end
        return DebugNowMS(), collectgarbage("count")
    end

    function TooltipDebug:End(name, startMS, detail, startHeapKB)
        if not self.enabled or not name or not startMS then return end
        local ms = DebugNowMS() - startMS
        self:Count(name .. ".calls", 1)
        self:Count(name .. ".ms", ms)

        if startHeapKB then
            local allocKB = collectgarbage("count") - startHeapKB
            if allocKB > 0 then
                self:Count(name .. ".allocKB", allocKB)
            end
        end

        if ms >= self.slowThreshold then
            debugSlowLog[#debugSlowLog + 1] = {
                name = name,
                ms = ms,
                detail = detail,
            }
            while #debugSlowLog > debugSlowLogMax do
                table.remove(debugSlowLog, 1)
            end
        end
    end

    function TooltipDebug:ResetWindow()
        wipe(debugCounters)
        wipe(debugSlowLog)
        local heapKB = collectgarbage("count")
        local addonKB = GetAddonMemoryKB()
        self.lastMemoryKB = heapKB
        self.lastHeapKB = heapKB
        self.lastAddonKB = addonKB
        self.lastReportTime = GetTime()
    end

    local function AppendCounter(parts, key, label)
        local value = debugCounters[key]
        if value and value ~= 0 then
            parts[#parts + 1] = string.format("%s=%d", label or key, value)
        end
    end

    local function BuildTopTiming()
        local rows = {}
        for key, ms in pairs(debugCounters) do
            local base = key:match("^(.*)%.ms$")
            if base and ms > 0 then
                local calls = debugCounters[base .. ".calls"] or 0
                if calls > 0 then
                    rows[#rows + 1] = {
                        name = base,
                        ms = ms,
                        calls = calls,
                        avg = ms / calls,
                    }
                end
            end
        end
        table.sort(rows, function(a, b) return a.ms > b.ms end)
        return rows
    end

    local function BuildTopAlloc()
        local rows = {}
        for key, kb in pairs(debugCounters) do
            local base = key:match("^(.*)%.allocKB$")
            if base and kb > 0 then
                local calls = debugCounters[base .. ".calls"] or 0
                rows[#rows + 1] = {
                    name = base,
                    kb = kb,
                    calls = calls,
                    avg = calls > 0 and (kb / calls) or kb,
                }
            end
        end
        table.sort(rows, function(a, b) return a.kb > b.kb end)
        return rows
    end

    function TooltipDebug:Report(resetAfter)
        local now = GetTime()
        local heapKB = collectgarbage("count")
        local addonKB = GetAddonMemoryKB()
        local lastHeapKB = self.lastHeapKB or self.lastMemoryKB or heapKB
        local lastAddonKB = self.lastAddonKB or addonKB
        local lastTime = self.lastReportTime or now
        local dt = math.max(now - lastTime, 0.001)
        local heapDelta = heapKB - lastHeapKB
        local addonDelta = addonKB and lastAddonKB and (addonKB - lastAddonKB) or nil

        local parts = {}
        AppendCounter(parts, "qol.unitPost", "unitPost")
        AppendCounter(parts, "qol.bypassed", "qolBypass")
        AppendCounter(parts, "qol.unitNoUnit", "unitNoUnit")
        AppendCounter(parts, "qol.unitNonPlayer", "unitNPC")
        AppendCounter(parts, "qol.unitPlayer", "unitPlayer")
        AppendCounter(parts, "qol.deferredScheduled", "deferQ")
        AppendCounter(parts, "qol.deferredCoalesced", "deferCo")
        AppendCounter(parts, "qol.deferredTick", "deferTick")
        AppendCounter(parts, "qol.unitCheckCoalesced", "unitCheckCo")
        AppendCounter(parts, "qol.mountAuraScanned", "mountAura")
        AppendCounter(parts, "qol.itemPost", "itemPost")
        AppendCounter(parts, "qol.spellPost", "spellPost")
        AppendCounter(parts, "qol.idPostSkipped", "idSkip")
        AppendCounter(parts, "qol.idOwnerSkipped", "idOwnerSkip")
        AppendCounter(parts, "qol.spellIDDataHit", "spellData")
        AppendCounter(parts, "qol.spellIDFallbackHit", "spellFallback")
        AppendCounter(parts, "qol.itemIDDataHit", "itemData")
        AppendCounter(parts, "qol.itemIDFallbackHit", "itemFallback")
        AppendCounter(parts, "skin.bypassed", "skinBypass")
        AppendCounter(parts, "skin.postCall", "skinPost")
        AppendCounter(parts, "skin.postGameTooltip", "postGame")
        AppendCounter(parts, "skin.setOwnerDeferred", "ownerDef")
        AppendCounter(parts, "skin.protectedTooltipSkipped", "protSkip")
        AppendCounter(parts, "skin.restyleQueued", "restyleQ")
        AppendCounter(parts, "skin.restyleCoalesced", "restyleCo")
        AppendCounter(parts, "skin.restyleRun", "restyleRun")
        AppendCounter(parts, "skin.fontQueued", "fontQ")
        AppendCounter(parts, "skin.chromeSkip", "chromeSkip")
        AppendCounter(parts, "skin.postStableSkip", "postStable")
        AppendCounter(parts, "skin.backdropStableSkip", "backdropStable")
        AppendCounter(parts, "skin.moneyScan", "moneyScan")
        AppendCounter(parts, "skin.widgetScan", "widgetScan")
        AppendCounter(parts, "skin.refit", "refit")
        AppendCounter(parts, "skin.refitApplied", "refitApply")
        AppendCounter(parts, "skin.refitCacheSkip", "refitCache")
        AppendCounter(parts, "skin.refitNoRequest", "refitNoReq")
        AppendCounter(parts, "skin.refitStaleRequest", "refitStale")
        AppendCounter(parts, "skin.refitShowReset", "refitReset")
        AppendCounter(parts, "skin.refitNoExtents", "refitNoExt")
        AppendCounter(parts, "skin.refitMonotonicY", "monoY")
        AppendCounter(parts, "skin.refitMonotonicX", "monoX")

        print(string.format(
            "|cff60A5FA[tooltipdebug]|r %.1fs heap %s (delta %s, %.1f KB/s) QUI %s%s | %s%s",
            dt,
            FormatKB(heapKB),
            FormatKB(heapDelta),
            heapDelta / dt,
            FormatKB(addonKB),
            addonDelta and string.format(" (delta %s)", FormatKB(addonDelta)) or "",
            DescribeTooltipContext(),
            #parts > 0 and (" | " .. table.concat(parts, " ")) or " | no QUI tooltip activity"))

        local timings = BuildTopTiming()
        if #timings > 0 then
            local timingParts = {}
            for i = 1, math.min(4, #timings) do
                local row = timings[i]
                timingParts[#timingParts + 1] = string.format(
                    "%s %.2fms/%d avg %.2f",
                    row.name,
                    row.ms,
                    row.calls,
                    row.avg)
            end
            print("  |cffAAAAAAtime:|r " .. table.concat(timingParts, " | "))
        end

        local allocs = BuildTopAlloc()
        if #allocs > 0 then
            local allocParts = {}
            for i = 1, math.min(4, #allocs) do
                local row = allocs[i]
                allocParts[#allocParts + 1] = string.format(
                    "%s %s/%d avg %s",
                    row.name,
                    FormatKB(row.kb),
                    row.calls,
                    FormatKB(row.avg))
            end
            print("  |cffAAAAAAalloc:|r " .. table.concat(allocParts, " | "))
        end

        if #debugSlowLog > 0 then
            local startIndex = math.max(1, #debugSlowLog - 2)
            for i = startIndex, #debugSlowLog do
                local row = debugSlowLog[i]
                print(string.format(
                    "  |cffFF8844slow:|r %s %.2fms %s",
                    row.name or "?",
                    row.ms or 0,
                    row.detail or ""))
            end
        end

        if resetAfter then
            self:ResetWindow()
        end
    end

    function TooltipDebug:Start(interval)
        self.enabled = true
        self.interval = math.max(1, tonumber(interval) or self.interval or 5)
        self.elapsed = 0
        self:ResetWindow()

        if not debugAutoFrame then
            debugAutoFrame = CreateFrame("Frame")
            debugAutoFrame:SetScript("OnUpdate", function(_, elapsed)
                if not TooltipDebug.enabled then return end
                TooltipDebug.elapsed = TooltipDebug.elapsed + (elapsed or 0)
                if TooltipDebug.elapsed < TooltipDebug.interval then return end
                TooltipDebug.elapsed = 0
                TooltipDebug:Report(true)
            end)
        end
        debugAutoFrame:Show()
        print(string.format("|cff60A5FAQUI tooltipdebug:|r on - reporting every %ds", self.interval))
    end

    function TooltipDebug:Stop()
        self.enabled = false
        if debugAutoFrame then
            debugAutoFrame:Hide()
        end
        print("|cff60A5FAQUI tooltipdebug:|r off")
    end

    function TooltipDebug:Command(subcmd, arg)
        subcmd = subcmd or "report"
        if subcmd == "on" or subcmd == "auto" then
            self:Start(arg)
            return
        end
        if subcmd == "off" or subcmd == "stop" then
            self:Stop()
            return
        end
        if subcmd == "reset" then
            self:ResetWindow()
            print("|cff60A5FAQUI tooltipdebug:|r reset")
            return
        end
        if subcmd == "slow" then
            self.slowThreshold = math.max(0.1, tonumber(arg) or self.slowThreshold or 1.5)
            print(string.format("|cff60A5FAQUI tooltipdebug:|r slow threshold %.1fms", self.slowThreshold))
            return
        end
        if subcmd == "bypass" then
            arg = arg or "off"
            if arg == "qol" then
                self.bypassQOL = true
                self.bypassSkin = false
            elseif arg == "skin" then
                self.bypassQOL = false
                self.bypassSkin = true
            elseif arg == "all" then
                self.bypassQOL = true
                self.bypassSkin = true
            elseif arg == "off" or arg == "none" then
                self.bypassQOL = false
                self.bypassSkin = false
            else
                print("|cff60A5FAQUI tooltipdebug:|r bypass expects qol, skin, all, or off")
                return
            end
            print(string.format(
                "|cff60A5FAQUI tooltipdebug:|r bypass qol=%s skin=%s",
                tostring(self.bypassQOL == true),
                tostring(self.bypassSkin == true)))
            return
        end
        if subcmd == "auratip" then
            local statusFn = ns.QUI_GetAuraTooltipProbeStatus
            if type(statusFn) ~= "function" then
                print("|cff60A5FAQUI tooltipdebug:|r auratip status skin=false supported=false reason=module-unavailable")
                return
            end
            local ok, status = pcall(statusFn)
            if not ok or type(status) ~= "table" then
                print("|cff60A5FAQUI tooltipdebug:|r auratip status unavailable")
                return
            end
            print(string.format(
                "|cff60A5FAQUI tooltipdebug:|r auratip status skin=%s supported=%s reason=%s",
                tostring(status.skinningLoaded == true),
                tostring(status.supported == true),
                tostring(status.reason or "unknown")))
            return
        end
        if subcmd == "help" then
            print("|cff60A5FAQUI tooltipdebug:|r /qui tooltipdebug on [seconds], off, report, reset, slow [ms], bypass qol|skin|all|off, auratip status")
            return
        end
        self:Report(false)
    end

    _G.QUI_TooltipDebug = function(subcmd, arg)
        TooltipDebug:Command(subcmd, arg)
    end
end

local function TooltipDebugCount(name, amount)
    local dbg = ns.QUI_TooltipDebug
    if dbg and dbg.enabled then
        dbg:Count(name, amount)
    end
end

local function TooltipDebugBypassQOL()
    local dbg = ns.QUI_TooltipDebug
    return dbg and dbg.bypassQOL == true
end

local function TooltipDebugBegin()
    local dbg = ns.QUI_TooltipDebug
    if dbg and dbg.enabled then
        local startMS, startHeapKB = dbg:Begin()
        return dbg, startMS, startHeapKB
    end
    return nil, nil, nil
end

local function TooltipDebugEnd(dbg, name, startMS, detail, startHeapKB)
    if dbg and startMS then
        dbg:End(name, startMS, detail, startHeapKB)
    end
end

local cursorFollowActive = Helpers.CreateStateTable()
local cursorFollowHooked = Helpers.CreateStateTable()
local CURSOR_SAFETY_CHECK_INTERVAL = 0.2
local gtCursorSafetyElapsed = CURSOR_SAFETY_CHECK_INTERVAL

local gtCursorWatcher
local gtCursorLastX, gtCursorLastY

local function SetCursorFollowActive(tooltip, active)
    cursorFollowActive[tooltip] = active or nil
    if tooltip == GameTooltip and gtCursorWatcher then
        if active then
            gtCursorLastX, gtCursorLastY = nil, nil
            gtCursorWatcher:Show()
        else
            gtCursorWatcher:Hide()
        end
    end
end

local function HasActiveWidgetContainer(tooltip)
    TooltipDebugCount("qol.widgetScan")
    local active = Helpers.HasTaintedWidgetContainer(tooltip)
    if active then TooltipDebugCount("qol.widgetHit") end
    return active
end

local function HasActiveMoneyFrame(tooltip)
    if not tooltip or not tooltip.GetChildren or not tooltip.GetNumChildren then return false end
    TooltipDebugCount("qol.moneyScan")

    local okCount, numChildren = pcall(tooltip.GetNumChildren, tooltip)
    if not okCount or not numChildren then return false end

    for i = 1, numChildren do
        local child = select(i, tooltip:GetChildren())
        if child then
            local childName
            if child.GetName then
                local okName, name = ns.SafeCallMethod("chain-next", child, "GetName")
                if okName then childName = name end
            end
            if child.moneyType ~= nil or child.staticMoney ~= nil or child.lastArgMoney ~= nil or
                (type(childName) == "string" and childName:find("MoneyFrame")) then
                if child.IsShown then
                    local okShown, shown = pcall(child.IsShown, child)
                    if not okShown or shown then
                        TooltipDebugCount("qol.moneyHit")
                        return true
                    end
                else
                    TooltipDebugCount("qol.moneyHit")
                    return true
                end
            end
        end
    end

    return false
end

local function EnsureCursorFollowHooks(tooltip)
    if not tooltip or cursorFollowHooked[tooltip] then return end
    cursorFollowHooked[tooltip] = true

    if tooltip == GameTooltip then
        if not gtCursorWatcher then
            gtCursorWatcher = CreateFrame("Frame")
            gtCursorWatcher:Hide()
            gtCursorWatcher:SetScript("OnUpdate", function(self, elapsed)
                TooltipDebugCount("qol.cursorFrame")
                if not cursorFollowActive[GameTooltip] then
                    self:Hide()
                    return
                end
                if not GameTooltip:IsShown() then
                    SetCursorFollowActive(GameTooltip, false)
                    return
                end
                gtCursorSafetyElapsed = gtCursorSafetyElapsed + (elapsed or 0)
                if gtCursorSafetyElapsed >= CURSOR_SAFETY_CHECK_INTERVAL then
                    TooltipDebugCount("qol.cursorSafety")
                    gtCursorSafetyElapsed = 0
                    if HasActiveMoneyFrame(GameTooltip) then
                        SetCursorFollowActive(GameTooltip, false)
                        return
                    end
                    if HasActiveWidgetContainer(GameTooltip) then
                        SetCursorFollowActive(GameTooltip, false)
                        return
                    end
                end
                local settings = Provider:GetSettings()
                if not settings or not settings.enabled or not settings.anchorToCursor then
                    SetCursorFollowActive(GameTooltip, false)
                    return
                end
                local cx, cy = GetCursorPosition()
                if cx == gtCursorLastX and cy == gtCursorLastY then return end
                gtCursorLastX, gtCursorLastY = cx, cy
                TooltipDebugCount("qol.cursorPosition")
                Provider:PositionTooltipAtCursor(GameTooltip, settings)
            end)
        end
        return
    end

    tooltip:HookScript("OnUpdate", function(self)
        if not cursorFollowActive[self] then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.anchorToCursor then
            cursorFollowActive[self] = nil
            return
        end
        Provider:PositionTooltipAtCursor(self, settings)
    end)

    tooltip:HookScript("OnHide", function(self)
        cursorFollowActive[self] = nil
    end)
end

local function AnchorTooltipToCursor(tooltip, parent, settings)
    if not tooltip then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    if tooltip == GameTooltip and HasActiveMoneyFrame(tooltip) then return false end
    if tooltip == GameTooltip and HasActiveWidgetContainer(tooltip) then return false end
    EnsureCursorFollowHooks(tooltip)
    tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
    if tooltip == GameTooltip then
        gtCursorSafetyElapsed = CURSOR_SAFETY_CHECK_INTERVAL
    end
    SetCursorFollowActive(tooltip, true)
    Provider:PositionTooltipAtCursor(tooltip, settings or Provider:GetSettings())
    return true
end

local pendingSetUnitToken = 0
local tooltipPlayerItemLevelGUID = setmetatable({}, {__mode = "k"})
local DEFAULT_PLAYER_ILVL_BRACKETS = {
    white = 245,
    green = 255,
    blue = 265,
    purple = 275,
    orange = 285,
}

local tooltipUnitInfoState = setmetatable({}, {__mode = "k"})

local mountNameCache = {}
local mountNameCacheTime = {}
local mountIDCache = {}
local mountSpellNameCache = {}
local mountSpellIDCache = {}
local mountSpellNameCacheCount = 0
local mountNameCacheCount = 0
local mountNameCacheLastPrune = 0
local MOUNT_CACHE_TTL = 0.75
local MOUNT_CACHE_MAX_ENTRIES = 80
local MOUNT_SPELL_CACHE_MAX_ENTRIES = 512
local MOUNT_SCAN_AURAS_PER_PASS = 12

local ScheduleDeferredUnitInfo

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    if _dbgCounters   then mp[#mp + 1] = { name = "Tooltip_debugCounters", tbl = _dbgCounters } end
    if _dbgSlowLog    then mp[#mp + 1] = { name = "Tooltip_debugSlowLog",  tbl = _dbgSlowLog  } end
    mp[#mp + 1] = { name = "Tooltip_mountNameCache",  tbl = mountNameCache }
    mp[#mp + 1] = { name = "Tooltip_mountSpellCache", tbl = mountSpellNameCache }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local tooltipRefreshInProgress = false

local function RefreshTooltipLayout(tooltip)
    if not tooltip then return end
    if tooltipRefreshInProgress then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    if tooltip == GameTooltip then
        if HasActiveMoneyFrame(tooltip) then
            return
        end
        if HasActiveWidgetContainer(tooltip) then
            return
        end
    end

    if type(tooltip.UpdateTooltipSize) == "function" then
        ns.SafeCallMethod("best-effort-style", tooltip, "UpdateTooltipSize")
    end
    local alreadyShown = tooltip.IsShown and tooltip:IsShown()
    if tooltip == GameTooltip or not alreadyShown then
        tooltipRefreshInProgress = true
        ns.SafeCallMethod("best-effort-style", tooltip, "Show")
        tooltipRefreshInProgress = false
    end
end

local function InvalidatePendingSetUnit()
    pendingSetUnitToken = pendingSetUnitToken + 1
end

local function ResolveTooltipUnit(tooltip)
    if not tooltip then return nil end

    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not unit then return nil end

    if Helpers.IsSecretValue(unit) then
        unit = UnitExists("mouseover") and "mouseover" or nil
    end

    return unit
end

local function ResolveTooltipVisibilityContext(tooltip, fallbackContext)
    if not tooltip or not Provider then
        return fallbackContext
    end

    local owner = tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner then
        local context = Provider:GetTooltipContext(owner)
        if context then
            return context
        end
    end

    local unit = ResolveTooltipUnit(tooltip)
    if unit and UnitExists(unit) then
        if owner and not Provider:IsTransientTooltipOwner(owner) then
            return "frames"
        end
        return "npcs"
    end

    return fallbackContext
end

local function IsTooltipFrameOwner(owner)
    if not owner then return false end
    if type(owner.NumLines) == "function" and type(owner.AddLine) == "function" then
        return true
    end
    if owner.GetName then
        local ok, name = pcall(owner.GetName, owner)
        if ok and type(name) == "string" and name:find("Tooltip") then
            return true
        end
    end
    return false
end

local function ShouldHideOwnedTooltip(tooltip, fallbackContext)
    if not tooltip or not Provider then
        return false
    end

    local owner = tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner and not Provider:IsTransientTooltipOwner(owner) and not IsTooltipFrameOwner(owner) and Provider:IsOwnerFadedOut(owner) then
        return true
    end

    if InCombatLockdown() then
        return false
    end

    local context = ResolveTooltipVisibilityContext(tooltip, fallbackContext)
    if context and not Provider:ShouldShowTooltip(context) then
        return true
    end

    return false
end

local gtTooltipHadUnit = false

local tooltipHideFadeState = {
    active = false,
    duration = 0,
    elapsed = 0,
    startAlpha = 1,
}

local function ResetTooltipHideFade()
    tooltipHideFadeState.active = false
    tooltipHideFadeState.duration = 0
    tooltipHideFadeState.elapsed = 0
    tooltipHideFadeState.startAlpha = 1
    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
        ns.SafeCallMethod("sink-forward", GameTooltip, "SetAlpha", 1)
    end
end

local function StartTooltipHideFade(duration)
    duration = tonumber(duration) or 0
    if not GameTooltip or not (GameTooltip.IsShown and GameTooltip:IsShown()) then
        ResetTooltipHideFade()
        return
    end

    if duration <= 0 then
        ResetTooltipHideFade()
        GameTooltip:Hide()
        return
    end

    local okAlpha, currentAlpha = pcall(GameTooltip.GetAlpha, GameTooltip)
    tooltipHideFadeState.active = true
    tooltipHideFadeState.duration = duration
    tooltipHideFadeState.elapsed = 0
    tooltipHideFadeState.startAlpha = (okAlpha and type(currentAlpha) == "number" and currentAlpha) or 1
end

local function IsChildOfFrame(frame, ancestor)
    if not frame or not ancestor then
        return false
    end

    local depth = 0
    while frame and depth < 12 do
        if frame == ancestor then
            return true
        end
        if frame == UIParent then
            break
        end
        if not frame.GetParent then
            break
        end
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok or not parent then
            break
        end
        frame = parent
        depth = depth + 1
    end

    return false
end

local function IsInternalEmbeddedItemRoot(root, tooltip)
    if not root or not tooltip then return false end
    if tooltip == root or tooltip == root.Tooltip or tooltip == root.FollowerTooltip then
        return true
    end
    if tooltip.GetParent then
        local ok, parent = pcall(tooltip.GetParent, tooltip)
        if ok and parent == root then
            return true
        end
    end
    return false
end

local function IsInternalEmbeddedItemTooltipFrame(tooltip)
    if IsInternalEmbeddedItemRoot(GameTooltip and GameTooltip.ItemTooltip, tooltip) then
        return true
    end
    if IsInternalEmbeddedItemRoot(EmbeddedItemTooltip and EmbeddedItemTooltip.ItemTooltip, tooltip) then
        return true
    end
    return false
end

local function IsFrameObject(object)
    if not object or not object.IsObjectType then
        return false
    end

    local ok, isFrame = pcall(object.IsObjectType, object, "Frame")
    return ok and isFrame
end

local function GetRegionOwnerParent(owner)
    if not owner or IsFrameObject(owner) or not owner.GetParent then
        return nil
    end

    local ok, parent = pcall(owner.GetParent, owner)
    if ok and parent and parent ~= owner then
        return parent
    end

    return nil
end

local function IsTooltipOwnerHovered(owner)
    if not owner or not Provider then
        return false
    end

    local focus = Provider.GetTopMouseFrame and Provider:GetTopMouseFrame()
    if focus and IsChildOfFrame(focus, owner) then
        return true
    end

    local regionOwnerParent = GetRegionOwnerParent(owner)
    if regionOwnerParent and focus and IsChildOfFrame(focus, regionOwnerParent) then
        return true
    end

    if owner.IsMouseOver then
        local ok, isOver = pcall(owner.IsMouseOver, owner)
        if ok and isOver then
            return true
        end
    end

    if regionOwnerParent and regionOwnerParent.IsMouseOver then
        local ok, isOver = pcall(regionOwnerParent.IsMouseOver, regionOwnerParent)
        if ok and isOver then
            return true
        end
    end

    return false
end

local function ShouldKeepTooltipVisible(tooltip)
    if not tooltip or not Provider then
        return false
    end

    local owner = tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner and not Provider:IsTransientTooltipOwner(owner) then
        if IsTooltipFrameOwner(owner) then
            local okShown, shown = pcall(owner.IsShown, owner)
            return okShown and shown
        end
        return IsTooltipOwnerHovered(owner)
    end

    local unit = ResolveTooltipUnit(tooltip)
    if unit and UnitExists(unit) then
        return true
    end

    if UnitExists("mouseover") then
        return true
    end

    if Provider.IsFrameBlockingMouse and Provider:IsFrameBlockingMouse(tooltip) then
        return true
    end

    if not gtTooltipHadUnit then
        local focus = Provider.GetTopMouseFrame and Provider:GetTopMouseFrame()
        if focus == WorldFrame then
            return true
        end
    end

    return false
end

local function GetPlayerItemLevelColor(itemLevel)
    if Helpers.IsSecretValue(itemLevel) then
        return 1, 1, 1 -- @secret-policy: neutral-color-degrade
    end

    itemLevel = tonumber(itemLevel)
    if not itemLevel then
        return 1, 1, 1
    end

    local settings = Provider and Provider:GetSettings()
    if not settings or settings.colorPlayerItemLevel == false then
        return 1, 1, 1
    end

    local brackets = settings.itemLevelBrackets or DEFAULT_PLAYER_ILVL_BRACKETS
    local white = tonumber(brackets.white) or DEFAULT_PLAYER_ILVL_BRACKETS.white
    local green = tonumber(brackets.green) or DEFAULT_PLAYER_ILVL_BRACKETS.green
    local blue = tonumber(brackets.blue) or DEFAULT_PLAYER_ILVL_BRACKETS.blue
    local purple = tonumber(brackets.purple) or DEFAULT_PLAYER_ILVL_BRACKETS.purple
    local orange = tonumber(brackets.orange) or DEFAULT_PLAYER_ILVL_BRACKETS.orange

    if itemLevel >= orange then
        return 1, 0.5, 0
    elseif itemLevel >= purple then
        return 0.64, 0.21, 0.93
    elseif itemLevel >= blue then
        return 0, 0.44, 0.87
    elseif itemLevel >= green then
        return 0, 1, 0
    elseif itemLevel >= white then
        return 1, 1, 1
    end

    return 0.62, 0.62, 0.62
end

local function GetPlayerClassColor(classToken)
    if not classToken then
        return 1, 1, 1
    end

    local classColor
    if InCombatLockdown() then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local ok, color = ns.SafeCall("chain-next", C_ClassColor.GetClassColor, classToken)
            if ok and color then
                classColor = color
            end
        end
    else
        classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    end

    if classColor then
        return classColor.r, classColor.g, classColor.b
    end

    return 1, 1, 1
end

local function GetPlayerItemLevelLabel(playerData)
    if not playerData then
        return ns.L["Player"]
    end

    if playerData.specName and playerData.specName ~= "" and playerData.className and playerData.className ~= "" then
        return string.format("%s %s", playerData.specName, playerData.className)
    end

    if playerData.className and playerData.className ~= "" then
        return playerData.className
    end

    return ns.L["Player"]
end

local function TooltipColorByte(value)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(value) then
        return 255 -- @secret-policy: neutral-color-degrade
    end
    local n = tonumber(value) or 1
    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    return math.floor((n * 255) + 0.5)
end

local function TooltipColorText(text, r, g, b)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then
        return nil -- @secret-policy: reject-secret-value
    end
    return string.format(
        "|cff%02x%02x%02x%s|r",
        TooltipColorByte(r),
        TooltipColorByte(g),
        TooltipColorByte(b),
        tostring(text or ""))
end

local function AddTooltipInfoLine(tooltip, label, value, labelR, labelG, labelB, valueR, valueG, valueB)
    if not tooltip then return false end
    if Helpers.IsSecretValue and (Helpers.IsSecretValue(label) or Helpers.IsSecretValue(value)) then
        return false
    end
    if value == nil then return false end

    local labelText = tostring(label or "")
    if labelText == "" then return false end
    if labelText:sub(-1) ~= ":" then
        labelText = labelText .. ":"
    end

    local coloredLabel = TooltipColorText(labelText, labelR, labelG, labelB)
    local coloredValue = TooltipColorText(value, valueR, valueG, valueB)
    if not coloredLabel or not coloredValue then return false end

    tooltip:AddLine(coloredLabel .. " " .. coloredValue, 1, 1, 1, true)
    return true
end

local function AddPlayerItemLevelDataToTooltip(tooltip, guid, playerData, skipShow)
    if not tooltip or not playerData or not playerData.itemLevel then return false end
    if Helpers.IsSecretValue(guid) then return false end -- @secret-policy: reject-secret-ids
    if tooltipPlayerItemLevelGUID[tooltip] == guid then
        TooltipDebugCount("qol.itemLevelDuplicate")
        return false
    end

    if Helpers.IsSecretValue(playerData.itemLevel) then
        TooltipDebugCount("qol.itemLevelSecret")
        return false -- @secret-policy: reject-secret-value
    end

    local itemLevel = tonumber(playerData.itemLevel)
    if not itemLevel or itemLevel <= 0 then
        return false
    end

    local label = GetPlayerItemLevelLabel(playerData)
    local labelR, labelG, labelB = GetPlayerClassColor(playerData.classToken)
    local valueR, valueG, valueB = GetPlayerItemLevelColor(itemLevel)

    tooltip:AddLine(" ")
    AddTooltipInfoLine(tooltip, label, string.format("%.1f", itemLevel), labelR, labelG, labelB, valueR, valueG, valueB)
    tooltipPlayerItemLevelGUID[tooltip] = guid
    TooltipDebugCount("qol.itemLevelAdded")

    if not skipShow then
        RefreshTooltipLayout(tooltip)
    end

    return true
end

local function AddPlayerItemLevelToTooltip(tooltip, unit, skipShow)
    TooltipDebugCount("qol.itemLevelAttempt")
    if not TooltipInspect or not unit or not tooltip then return false end
    if InCombatLockdown() then return false end

    local playerData = TooltipInspect:GetCachedPlayerData(unit)
    if not playerData or not playerData.itemLevel then
        TooltipDebugCount("qol.itemLevelQueued")
        TooltipInspect:QueueInspect(unit)
        return false
    end

    return AddPlayerItemLevelDataToTooltip(tooltip, UnitGUID(unit), playerData, skipShow)
end

local function AddPlayerItemLevelByGUIDToTooltip(tooltip, guid, skipShow, reset)
    TooltipDebugCount("qol.itemLevelAttempt")
    local inspect = TooltipInspect or ns.TooltipInspect
    if not inspect or not inspect.GetPlayerDataByGUID or not tooltip then return false end
    if Helpers.IsSecretValue(guid) or guid == nil then return false end -- @secret-policy: reject-secret-ids
    if reset then tooltipPlayerItemLevelGUID[tooltip] = nil end

    local playerData = inspect:GetPlayerDataByGUID(guid)
    if not playerData then return false end
    return AddPlayerItemLevelDataToTooltip(tooltip, guid, playerData, skipShow)
end

ns.QUI_AddPlayerItemLevelByGUIDToTooltip = AddPlayerItemLevelByGUIDToTooltip

local function IsSettingEnabled(settings, key, defaultValue)
    if not settings then
        return defaultValue == true
    end
    local value = settings[key]
    if value == nil then
        return defaultValue == true
    end
    return value == true
end

local function EnsureTooltipUnitInfoState(tooltip, guid)
    if not tooltip or not guid then
        return nil
    end
    local state = tooltipUnitInfoState[tooltip]
    if not state or state.guid ~= guid then
        state = {
            guid = guid,
            targetAdded = false,
            targetedByAdded = false,
            mountResolved = false,
            mountName = nil,
            mountNextAuraIndex = 1,
            lastMountName = nil,
            ratingResolved = false,
            ratingAdded = false,
            itemLevelAttempted = false,
        }
        tooltipUnitInfoState[tooltip] = state
    end
    return state
end

local function EnsureTooltipInfoSpacer(tooltip, state)
    if not tooltip or not state then return end
    if state.spacerAdded then return end
    tooltip:AddLine(" ")
    state.spacerAdded = true
end

local function ResolveTooltipTargetInfo(unit)
    if not unit then
        return nil
    end
    local targetUnit = unit .. "target"
    local ok, exists = pcall(UnitExists, targetUnit)
    if not ok or not exists or Helpers.IsSecretValue(exists) then
        return {
            name = "Unknown",
            valueR = 1,
            valueG = 1,
            valueB = 1,
        }
    end

    local okName, targetName = pcall(UnitName, targetUnit)
    if Helpers.IsSecretValue(targetName) then
        targetName = "Unknown"
    elseif not okName or not targetName then
        targetName = "Unknown"
    end

    local okClass, _, classToken = pcall(UnitClass, targetUnit)
    if not okClass then classToken = nil end
    if Helpers.IsSecretValue(classToken) then classToken = nil end
    local valueR, valueG, valueB = 1, 1, 1
    if classToken then
        valueR, valueG, valueB = GetPlayerClassColor(classToken)
    end

    return {
        name = targetName,
        valueR = valueR,
        valueG = valueG,
        valueB = valueB,
    }
end

local function AddTooltipTargetInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end

    if state.targetAdded then return false end

    local targetInfo = ResolveTooltipTargetInfo(unit)
    if not targetInfo then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    AddTooltipInfoLine(tooltip, ns.L["Target"], targetInfo.name, 0.7, 0.82, 1, targetInfo.valueR, targetInfo.valueG, targetInfo.valueB)
    state.targetAdded = true
    TooltipDebugCount("qol.targetAdded")
    return true
end

local TARGETED_BY_MAX_NAMES = 10

local function GetTargetingMemberName(groupUnit, mouseoverUnit)
    local okExists, exists = pcall(UnitExists, groupUnit)
    if not okExists or not exists or Helpers.IsSecretValue(exists) then return nil end
    local okSelf, isSelf = pcall(UnitIsUnit, groupUnit, mouseoverUnit)
    if not okSelf or Helpers.IsSecretValue(isSelf) or isSelf then return nil end
    local okTarget, targetsUnit = pcall(UnitIsUnit, groupUnit .. "target", mouseoverUnit)
    if not okTarget then return nil end
    if Helpers.IsSecretValue(targetsUnit) then return nil end -- @secret-policy: reject-secret-value
    if not targetsUnit then return nil end
    local okName, name = pcall(UnitName, groupUnit)
    if not okName then return nil end
    if Helpers.IsSecretValue(name) then return nil end -- @secret-policy: reject-secret-ids
    if not name or name == "" then return nil end
    return name
end

local function ResolveTooltipTargetedBy(unit)
    if not unit then return nil end
    if InCombatLockdown() then return nil end
    if not IsInGroup() and not IsInRaid() then return nil end

    local names
    local count = 0

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if count >= TARGETED_BY_MAX_NAMES then break end
            local name = GetTargetingMemberName("raid" .. i, unit)
            if name then
                names = names and (names .. ", " .. name) or name
                count = count + 1
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            if count >= TARGETED_BY_MAX_NAMES then break end
            local name = GetTargetingMemberName("party" .. i, unit)
            if name then
                names = names and (names .. ", " .. name) or name
                count = count + 1
            end
        end
        if count < TARGETED_BY_MAX_NAMES then
            local name = GetTargetingMemberName("player", unit)
            if name then
                names = names and (names .. ", " .. name) or name
            end
        end
    end

    return names
end

local function AddTooltipTargetedByInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end
    if state.targetedByAdded then return false end
    if InCombatLockdown() then return false end

    local names = ResolveTooltipTargetedBy(unit)
    state.targetedByAdded = true
    if not names then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    AddTooltipInfoLine(tooltip, ns.L["Targeted By"], names, 0.7, 0.82, 1, 1, 1, 1)
    TooltipDebugCount("qol.targetedByAdded")
    return true
end

local function SetMountSpellNameCache(spellID, mountName, mountID)
    if not spellID then return end
    if mountSpellNameCache[spellID] == nil then
        mountSpellNameCacheCount = mountSpellNameCacheCount + 1
    end
    mountSpellNameCache[spellID] = mountName or false
    mountSpellIDCache[spellID] = mountID or false

    if mountSpellNameCacheCount > MOUNT_SPELL_CACHE_MAX_ENTRIES then
        wipe(mountSpellNameCache)
        wipe(mountSpellIDCache)
        mountSpellNameCacheCount = 0
    end
end

local function GetMountNameFromSpellID(spellID)
    if Helpers.IsSecretValue(spellID) then return nil end -- @secret-policy: reject-secret-ids
    if not spellID then return nil end
    if spellID == 0 then return nil end

    local cached = mountSpellNameCache[spellID]
    if cached ~= nil then
        TooltipDebugCount(cached and "qol.mountSpellCacheHit" or "qol.mountSpellCacheNegHit")
        return cached or nil, mountSpellIDCache[spellID] or nil
    end
    TooltipDebugCount("qol.mountSpellCacheMiss")

    if not C_MountJournal or not C_MountJournal.GetMountFromSpell then return nil end

    local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
    if not ok or not mountID or mountID == 0 or Helpers.IsSecretValue(mountID) then
        SetMountSpellNameCache(spellID, false)
        return nil
    end

    if not C_MountJournal.GetMountInfoByID then
        SetMountSpellNameCache(spellID, false)
        return nil
    end

    local okInfo, mountName = ns.SafeCall("chain-next", C_MountJournal.GetMountInfoByID, mountID)
    if not okInfo or not mountName then
        SetMountSpellNameCache(spellID, false)
        return nil
    end

    SetMountSpellNameCache(spellID, mountName, mountID)
    return mountName, mountID
end

local function ClearCachedMountName(guid)
    if not guid then return end
    if mountNameCacheTime[guid] ~= nil then
        mountNameCacheCount = mountNameCacheCount - 1
    end
    mountNameCache[guid] = nil
    mountNameCacheTime[guid] = nil
    mountIDCache[guid] = nil
end

local function PruneMountNameCache(now, force)
    now = now or GetTime()
    if not force and mountNameCacheCount <= MOUNT_CACHE_MAX_ENTRIES and (now - mountNameCacheLastPrune) < 1 then
        return
    end
    mountNameCacheLastPrune = now

    local oldestGuid
    local oldestTime = now
    for guid, timestamp in pairs(mountNameCacheTime) do
        if (now - timestamp) > MOUNT_CACHE_TTL then
            mountNameCache[guid] = nil
            mountNameCacheTime[guid] = nil
            mountIDCache[guid] = nil
            mountNameCacheCount = mountNameCacheCount - 1
        elseif timestamp < oldestTime then
            oldestTime = timestamp
            oldestGuid = guid
        end
    end

    while mountNameCacheCount > MOUNT_CACHE_MAX_ENTRIES and oldestGuid do
        ClearCachedMountName(oldestGuid)
        oldestGuid = nil
        oldestTime = now
        for guid, timestamp in pairs(mountNameCacheTime) do
            if timestamp < oldestTime then
                oldestTime = timestamp
                oldestGuid = guid
            end
        end
    end
end

local function GetCachedMountName(guid)
    if not guid then return nil, false end
    local timestamp = mountNameCacheTime[guid]
    if not timestamp then return nil, false end

    local age = GetTime() - timestamp
    if age > MOUNT_CACHE_TTL then
        ClearCachedMountName(guid)
        return nil, false
    end

    local cached = mountNameCache[guid]
    return cached or nil, true, mountIDCache[guid] or nil
end

local function SetCachedMountName(guid, mountName, mountID)
    if not guid then return end
    local now = GetTime()
    if mountNameCacheTime[guid] == nil then
        mountNameCacheCount = mountNameCacheCount + 1
    end
    mountNameCache[guid] = mountName or false
    mountIDCache[guid] = mountID or false
    mountNameCacheTime[guid] = now
    PruneMountNameCache(now, false)
end

local function GetMountedPlayerMountName(unit, state)
    if not unit or not UnitExists(unit) then return nil, true end
    TooltipDebugCount("qol.mountScanPass")
    if InCombatLockdown() then
        return nil, true
    end

    local guid = UnitGUID(unit)
    if Helpers.IsSecretValue(guid) then return nil, true end -- @secret-policy: reject-secret-ids
    if not guid then return nil, true end

    local cachedName, cacheHit, cachedMountID = GetCachedMountName(guid)
    if cacheHit then
        TooltipDebugCount(cachedName and "qol.mountCacheHit" or "qol.mountCacheNegHit")
        return cachedName, true, cachedMountID
    end
    TooltipDebugCount("qol.mountCacheMiss")

    local startIndex = (state and state.mountNextAuraIndex) or 1
    local endIndex = math.min(80, startIndex + MOUNT_SCAN_AURAS_PER_PASS - 1)

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = startIndex, endIndex do
            TooltipDebugCount("qol.mountAuraScanned")
            local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if Helpers.IsSecretValue(auraData) then
                SetCachedMountName(guid, false)
                return nil, true -- @secret-policy: reject-secret-value
            end
            if not ok or not auraData then
                SetCachedMountName(guid, false)
                return nil, true
            end

            local auraSpellId = auraData.spellId
            if not Helpers.IsSecretValue(auraSpellId) and auraSpellId then
                local mountName, mountID = GetMountNameFromSpellID(auraSpellId)
                if mountName then
                    SetCachedMountName(guid, mountName, mountID)
                    return mountName, true, mountID
                end
            end
        end
    else
        for i = startIndex, endIndex do
            TooltipDebugCount("qol.mountAuraScanned")
            local ok, name, _, _, _, _, _, _, _, spellID = pcall(UnitAura, unit, i, "HELPFUL")
            if not ok or not name then
                SetCachedMountName(guid, false)
                return nil, true
            end

            if spellID then
                local mountName, mountID = GetMountNameFromSpellID(spellID)
                if mountName then
                    SetCachedMountName(guid, mountName, mountID)
                    return mountName, true, mountID
                end
            end
        end
    end

    if endIndex >= 80 then
        SetCachedMountName(guid, false)
        return nil, true
    end

    if state then
        state.mountNextAuraIndex = endIndex + 1
    end
    return nil, false
end

local function AddTooltipMountInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end
    if state.mountResolved and not state.mountName then return false end

    local mountName, resolved, mountID = GetMountedPlayerMountName(unit, state)
    if resolved then
        state.mountResolved = true
        state.mountName = mountName
    end
    if not mountName then return resolved and false or nil end

    if state.lastMountName == mountName then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    local mountValue = mountName
    if mountID and not Helpers.IsSecretValue(mountID)
        and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local settings = Provider:GetSettings()
        if settings and IsSettingEnabled(settings, "showMountCollected", true) then
            local okC, _, _, _, _, _, _, _, _, _, _, isCollected =
                pcall(C_MountJournal.GetMountInfoByID, mountID)
            if okC and isCollected ~= nil and not Helpers.IsSecretValue(isCollected) then
                mountValue = mountName .. " " ..
                    (isCollected and "|cff20ff20\226\156\147|r" or "|cffff4040\226\156\151|r")
            end
        end
    end
    AddTooltipInfoLine(tooltip, ns.L["Mount"], mountValue, 0.65, 1, 0.65, 1, 1, 1)
    state.lastMountName = mountName
    TooltipDebugCount("qol.mountAdded")
    return true
end

local function GetPlayerMythicRating(unit)
    if not unit then return nil end

    local provider = rawget(_G, string.char(82, 97, 105, 100, 101, 114, 73, 79))
    if type(provider) == "table" and type(provider.GetProfile) == "function" then
        local ok, profile = pcall(provider.GetProfile, unit)
        if ok and profile and profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.currentScore then
            local score = tonumber(profile.mythicKeystoneProfile.currentScore) or 0
            if score > 0 then
                local color = provider.GetScoreColor and provider.GetScoreColor(score)
                if type(color) == "table" and color.r then
                    return math.floor(score), color.r, color.g, color.b
                end
                return math.floor(score), 1, 1, 1
            end
        end
    end

    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, ratingInfo = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
        if ok and ratingInfo and ratingInfo.currentSeasonScore then
            local score = Helpers.SafeToNumber(ratingInfo.currentSeasonScore, 0)
            if score and score > 0 then
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then
                    return math.floor(score), color.r, color.g, color.b
                end
                return math.floor(score), 1, 0.82, 0
            end
        end
    end

    return nil
end

-- <<< QUI_TEST_EXTRACT npc_id
local function NpcIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if (unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet") and npcID then
        return tonumber(npcID)
    end
    return nil
end
-- <<< QUI_TEST_EXTRACT npc_id

local function AddUnitTooltipInfoToTooltip(tooltip, unit, settings)
    if not tooltip or not unit or not settings then return false end
    if InCombatLockdown() then return false end

    local guid = UnitGUID(unit)
    if Helpers.IsSecretValue(guid) then return false end -- @secret-policy: reject-secret-ids
    if not guid then return false end

    local state = EnsureTooltipUnitInfoState(tooltip, guid)
    if not state then return false end

    local changed = false

    if IsSettingEnabled(settings, "showTooltipTarget", true) then
        changed = AddTooltipTargetInfo(tooltip, unit, state) or changed
    end

    if IsSettingEnabled(settings, "showTargetedBy", true) then
        changed = AddTooltipTargetedByInfo(tooltip, unit, state) or changed
    end

    if IsSettingEnabled(settings, "showPlayerMythicRating", true) and not state.ratingResolved then
        local rating, r, g, b = GetPlayerMythicRating(unit)
        state.ratingResolved = true
        if rating then
            EnsureTooltipInfoSpacer(tooltip, state)
            AddTooltipInfoLine(tooltip, ns.L["M+ Rating"], string.format("%d", rating), 0.7, 0.82, 1, r or 1, g or 1, b or 1)
            state.ratingAdded = true
            TooltipDebugCount("qol.ratingAdded")
            changed = true
        end
    end

    if IsSettingEnabled(settings, "showNpcID", false) and not state.npcIDResolved then
        state.npcIDResolved = true
        local npcID = NpcIDFromGUID(guid)
        if npcID then
            EnsureTooltipInfoSpacer(tooltip, state)
            AddTooltipInfoLine(tooltip, ns.L["NPC ID"], tostring(npcID), 0.7, 0.82, 1, 0.8, 0.8, 0.8)
            changed = true
        end
    end

    return changed
end

local deferredUnitFrame = CreateFrame("Frame")
local deferredUnitTooltip = nil
local deferredUnitGUID = nil
local deferredUnitElapsed = 0
local DEFERRED_UNIT_INFO_DELAY = 0.04

local function DeferredUnitInfoOnUpdate(self, elapsed)
    deferredUnitElapsed = deferredUnitElapsed + (elapsed or 0)
    if deferredUnitElapsed < DEFERRED_UNIT_INFO_DELAY then return end
    deferredUnitElapsed = 0
    TooltipDebugCount("qol.deferredTick")
    local dbg, dbgStart, dbgHeap = TooltipDebugBegin()

    local tooltip = deferredUnitTooltip
    local guid = deferredUnitGUID
    if not tooltip or not guid or tooltip.IsForbidden and tooltip:IsForbidden() then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "missing-tooltip", dbgHeap)
        return
    end
    if not tooltip:IsShown() then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "hidden", dbgHeap)
        return
    end

    local unit = ResolveTooltipUnit(tooltip)
    if not unit then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "no-unit", dbgHeap)
        return
    end

    local unitGUID = UnitGUID(unit)
    local guidStale
    if Helpers.IsSecretValue(unitGUID) then
        guidStale = true
    else
        guidStale = not unitGUID or unitGUID ~= guid
    end
    if guidStale then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "guid-mismatch", dbgHeap)
        return
    end

    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or InCombatLockdown() then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "disabled", dbgHeap)
        return
    end

    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if not okPlayer or not isPlayer then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "not-player", dbgHeap)
        return
    end

    local state = EnsureTooltipUnitInfoState(tooltip, guid)
    if not state then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugEnd(dbg, "qol.deferred", dbgStart, "no-state", dbgHeap)
        return
    end

    local changed = false
    local pending = false

    changed = AddUnitTooltipInfoToTooltip(tooltip, unit, settings) or changed

    if IsSettingEnabled(settings, "showPlayerMount", true) and not state.mountResolved then
        local added = AddTooltipMountInfo(tooltip, unit, state)
        if added == nil then
            pending = true
        else
            changed = added or changed
        end
    end

    if not state.itemLevelAttempted and settings.showPlayerItemLevel and not InCombatLockdown() then
        state.itemLevelAttempted = true
        changed = AddPlayerItemLevelToTooltip(tooltip, unit, true) or changed
    end

    if changed then
        TooltipDebugCount("qol.deferredChanged")
        RefreshTooltipLayout(tooltip)
    end

    if not pending then
        self:SetScript("OnUpdate", nil)
        deferredUnitTooltip = nil
        deferredUnitGUID = nil
        TooltipDebugCount("qol.deferredDone")
    else
        TooltipDebugCount("qol.deferredPending")
    end
    TooltipDebugEnd(dbg, "qol.deferred", dbgStart, pending and "pending" or "done", dbgHeap)
end

ScheduleDeferredUnitInfo = function(tooltip, unit)
    if not tooltip or not unit then return end
    local guid = UnitGUID(unit)
    if Helpers.IsSecretValue(guid) then return end -- @secret-policy: reject-secret-ids
    if not guid then return end
    if deferredUnitTooltip == tooltip and deferredUnitGUID == guid then
        TooltipDebugCount("qol.deferredCoalesced")
        return
    end
    TooltipDebugCount("qol.deferredScheduled")
    deferredUnitTooltip = tooltip
    deferredUnitGUID = guid
    deferredUnitElapsed = 0
    deferredUnitFrame:SetScript("OnUpdate", DeferredUnitInfoOnUpdate)
end

local function SetupTooltipHook()
    ns.QUI_AnchorTooltipToCursor = AnchorTooltipToCursor

    local pendingUnitCheckFrame = CreateFrame("Frame")
    local pendingUnitCheckTooltip = nil
    local pendingUnitCheckOwner = nil
    local pendingUnitCheckToken = 0
    local pendingUnitCheckElapsed = 0
    local PENDING_UNIT_CHECK_DELAY = 0.1

    local function PendingUnitCheckOnUpdate(self, elapsed)
        pendingUnitCheckElapsed = pendingUnitCheckElapsed + (elapsed or 0)
        if pendingUnitCheckElapsed < PENDING_UNIT_CHECK_DELAY then return end
        self:SetScript("OnUpdate", nil)

        local tooltip = pendingUnitCheckTooltip
        local owner = pendingUnitCheckOwner
        local token = pendingUnitCheckToken
        pendingUnitCheckTooltip = nil
        pendingUnitCheckOwner = nil

        if token ~= pendingSetUnitToken then return end
        if not tooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        if not tooltip:IsShown() then return end
        if tooltip:GetOwner() ~= owner then return end
        if owner ~= UIParent then return end
        local unit = ResolveTooltipUnit(tooltip)
        if unit and UnitExists(unit) then return end
        if UnitExists("mouseover") then return end
        if Provider:IsFrameBlockingMouse() then
            tooltip:Hide()
        end
    end

    local function SchedulePendingUnitCheck(tooltip, owner)
        if pendingUnitCheckTooltip == tooltip and pendingUnitCheckOwner == owner then
            TooltipDebugCount("qol.unitCheckCoalesced")
            return
        end
        local token = pendingSetUnitToken + 1
        pendingSetUnitToken = token
        pendingUnitCheckTooltip = tooltip
        pendingUnitCheckOwner = owner
        pendingUnitCheckToken = token
        pendingUnitCheckElapsed = 0
        pendingUnitCheckFrame:SetScript("OnUpdate", PendingUnitCheckOnUpdate)
    end

    local function AddTrackedTooltipPostCall(dataType, debugName, callback)
        TooltipDataProcessor.AddTooltipPostCall(dataType, function(...)
            if TooltipDebugBypassQOL() then
                TooltipDebugCount("qol.bypassed")
                return
            end
            local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
            callback(...)
            TooltipDebugEnd(dbg, debugName, dbgStart, nil, dbgHeap)
        end)
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if TooltipDebugBypassQOL() then
            TooltipDebugCount("qol.bypassed")
            return
        end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        if parent and parent.IsForbidden and parent:IsForbidden() then return end

        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        local userScale = tonumber(settings.scale) or 1
        if userScale <= 0 then userScale = 1 end
        ns.SafeCallMethod("sink-forward", tooltip, "SetScale", userScale)

        InvalidatePendingSetUnit()

        if not InCombatLockdown() then
            local context = Provider:GetTooltipContext(parent)
            if context and not Provider:ShouldShowTooltip(context) then
                tooltip:Hide()
                tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                tooltip:ClearLines()
                return
            end
        end

        if tooltip == GameTooltip and HasActiveWidgetContainer(tooltip) then
            SetCursorFollowActive(tooltip, false)
            return
        end

        if settings.anchorToCursor then
            EnsureCursorFollowHooks(tooltip)
            if tooltip == GameTooltip then
                gtCursorSafetyElapsed = CURSOR_SAFETY_CHECK_INTERVAL
            end
            SetCursorFollowActive(tooltip, true)
            Provider:PositionTooltipAtCursor(tooltip, settings)
        else
            SetCursorFollowActive(tooltip, false)
            Provider:PositionTooltipAtAnchor(tooltip, settings)
        end
    end)

    local function RunTrackedUnitStep(debugName, callback, ...)
        local dbg, dbgStart, dbgHeap = TooltipDebugBegin()
        local result = callback(...)
        TooltipDebugEnd(dbg, debugName, dbgStart, nil, dbgHeap)
        return result
    end

    local function HandleUnitVisibilityPost(tooltip, settings)
        TooltipDebugCount("qol.unitVisibilityPost")

        if settings.hideInCombat and InCombatLockdown() then
            if not settings.combatKey or settings.combatKey == "NONE" or not Provider:IsModifierActive(settings.combatKey) then
                tooltip:Hide()
                return true
            end
        end

        if ShouldHideOwnedTooltip(tooltip) then
            tooltip:Hide()
            return true
        end

        local owner = tooltip:GetOwner()
        SchedulePendingUnitCheck(tooltip, owner)
        return false
    end

    local function HideTooltipLineMatching(tooltip, matches, maxLine)
        for i = 2, maxLine or 5 do
            local line = tooltip.GetLeftLine and tooltip:GetLeftLine(i)
                or _G["GameTooltipTextLeft" .. i]
            if line then
                local okLT, lt = pcall(line.GetText, line)
                if okLT and lt and not Helpers.IsSecretValue(lt) then
                    if matches(lt) then
                        ns.SafeCallMethod("sink-forward", line, "SetText", "")
                        ns.SafeCallMethod("best-effort-style", line, "Hide")
                        break
                    end
                end
            end
        end
    end

    local connectedRealmSet
    local function NormalizeRealmName(name)
        return Helpers.FoldUTF8((name:gsub("[%s%-']", "")))
    end
    local function IsConnectedRealm(realm)
        if not connectedRealmSet then
            connectedRealmSet = {}
            if C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms then
                local okRealms, realms = ns.SafeCall("best-effort-style", C_AutoComplete.GetAutoCompleteRealms)
                if okRealms and type(realms) == "table" then
                    for _, r in ipairs(realms) do
                        if type(r) == "string" then
                            connectedRealmSet[NormalizeRealmName(r)] = true
                        end
                    end
                end
            end
        end
        return connectedRealmSet[NormalizeRealmName(realm)] == true
    end

    local function HandleUnitNamePost(tooltip, settings, unit)
        TooltipDebugCount("qol.unitNamePost")

        local hideServer = settings.hideServerName
        local hideTitle = settings.hidePlayerTitle
        local hideGuild = settings.hideGuildName
        local hideFaction = settings.hideFactionText
        local hidePvp = settings.hidePvpText
        local showConnected = settings.showConnectedRealm
        if not hideServer and not hideTitle and not hideGuild
            and not hideFaction and not hidePvp and not showConnected then return end

        if hideTitle then
            local nameLine = tooltip.GetLeftLine and tooltip:GetLeftLine(1) or GameTooltipTextLeft1
            if nameLine then
                local okText, lineText = pcall(nameLine.GetText, nameLine)
                if okText and lineText and not Helpers.IsSecretValue(lineText) then
                    local okName, bareName = pcall(UnitName, unit)
                    bareName = Helpers.SafeValue(bareName)
                    if okName and bareName and lineText ~= bareName then
                        ns.SafeCallMethod("sink-forward", nameLine, "SetText", bareName)
                    end
                end
            end
        end

        if hideServer then
            local okRealm, _, unitRealm = pcall(UnitName, unit)
            unitRealm = Helpers.SafeValue(unitRealm)
            if okRealm and unitRealm and unitRealm ~= "" then
                HideTooltipLineMatching(tooltip, function(lt)
                    return Helpers.SafeCompare(lt, unitRealm) == true
                end)
            end
        end

        if hideGuild then
            local okGuild, guildName = pcall(GetGuildInfo, unit)
            if okGuild and Helpers.IsSecretValue(guildName) then guildName = nil end
            if okGuild and guildName and guildName ~= "" then
                local bracketed = "<" .. guildName .. ">"
                HideTooltipLineMatching(tooltip, function(lt)
                    return lt == guildName or lt == bracketed
                end)
            end
        end

        if hideFaction then
            HideTooltipLineMatching(tooltip, function(lt)
                return (FACTION_ALLIANCE and lt == FACTION_ALLIANCE)
                    or (FACTION_HORDE and lt == FACTION_HORDE)
                    or (FACTION_NEUTRAL and lt == FACTION_NEUTRAL)
            end, 8)
        end
        if hidePvp then
            HideTooltipLineMatching(tooltip, function(lt)
                return (PVP_ENABLED and lt == PVP_ENABLED) or (PVP and lt == PVP)
            end, 8)
        end

        if showConnected and not hideServer then
            local okRealm, _, unitRealm = pcall(UnitName, unit)
            unitRealm = Helpers.SafeValue(unitRealm)
            if okRealm and unitRealm and unitRealm ~= ""
                and IsConnectedRealm(unitRealm) then
                for i = 2, 5 do
                    local line = tooltip.GetLeftLine and tooltip:GetLeftLine(i)
                        or _G["GameTooltipTextLeft" .. i]
                    if line then
                        local okLT, lt = pcall(line.GetText, line)
                        lt = Helpers.SafeValue(lt)
                        if okLT and lt and lt == unitRealm then
                            ns.SafeCallMethod("sink-forward", line, "SetText", lt .. " |cff80ff80(" .. ns.L["Connected"] .. ")|r")
                            break
                        end
                    end
                end
            end
        end
    end

    local GUILD_COLOR_MINE  = { r = 0.25, g = 1.0,  b = 0.25 }
    local GUILD_COLOR_OTHER = { r = 0.0,  g = 0.75, b = 1.0 }
    local function HandleUnitGuildPost(tooltip, settings, unit)
        if settings.hideGuildName then return end
        local wantRank = settings.showGuildRank
        local wantColor = settings.colorGuildNames
        if not wantRank and not wantColor then return end

        local okGuild, guildName, guildRankName = pcall(GetGuildInfo, unit)
        if okGuild and Helpers.IsSecretValue(guildName) then guildName = nil end
        if okGuild and Helpers.IsSecretValue(guildRankName) then guildRankName = nil end
        if not okGuild or not guildName or guildName == "" then return end

        local bracketed = "<" .. guildName .. ">"
        for i = 2, 5 do
            local line = tooltip.GetLeftLine and tooltip:GetLeftLine(i)
                or _G["GameTooltipTextLeft" .. i]
            if line then
                local okLT, lt = pcall(line.GetText, line)
                if okLT and lt and not Helpers.IsSecretValue(lt)
                    and (lt == guildName or lt == bracketed) then
                    if wantRank and guildRankName and guildRankName ~= ""
                        and not Helpers.IsSecretValue(guildRankName) then
                        ns.SafeCallMethod("sink-forward", line, "SetText", lt .. " (" .. guildRankName .. ")")
                    end
                    if wantColor then
                        local mine = false
                        local okMine, isMine = pcall(UnitIsInMyGuild, unit)
                        if okMine and isMine and not Helpers.IsSecretValue(isMine) then
                            mine = true
                        end
                        local c = mine and GUILD_COLOR_MINE or GUILD_COLOR_OTHER
                        ns.SafeCallMethod("sink-forward", line, "SetTextColor", c.r, c.g, c.b)
                    end
                    break
                end
            end
        end
    end

    local function HandleUnitClassPost(tooltip, settings, unit)
        TooltipDebugCount("qol.unitClassPost")
        if not settings.classColorName then return end

        local okClass, _, class = pcall(UnitClass, unit)
        if not okClass then class = nil end
        if Helpers.IsSecretValue(class) then class = nil end
        if not class then return end

        local classColor
        if InCombatLockdown() then
            if C_ClassColor and C_ClassColor.GetClassColor then
                local okColor, color = ns.SafeCall("chain-next", C_ClassColor.GetClassColor, class)
                if okColor and color then classColor = color end
            end
        else
            classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        end

        if classColor then
            local nameLine = tooltip.GetLeftLine and tooltip:GetLeftLine(1) or GameTooltipTextLeft1
            if nameLine then
                local okText, text = pcall(nameLine.GetText, nameLine)
                if okText and text and not Helpers.IsSecretValue(text) then
                    ns.SafeCallMethod("sink-forward", nameLine, "SetTextColor", classColor.r, classColor.g, classColor.b)
                end
            end
        end
    end

    local function HandleUnitExtrasPost(tooltip, settings, unit)
        TooltipDebugCount("qol.unitExtrasPost")
        tooltipPlayerItemLevelGUID[tooltip] = nil
        AddUnitTooltipInfoToTooltip(tooltip, unit, settings)
        ScheduleDeferredUnitInfo(tooltip, unit)
    end

    local function HandleUnitHealthPost(tooltip, settings)
        TooltipDebugCount("qol.unitHealthPost")
        if InCombatLockdown() then return end

        if settings.hideHealthBar then
            if GameTooltipStatusBar and not (GameTooltipStatusBar.IsForbidden and GameTooltipStatusBar:IsForbidden()) then
                ns.SafeCallMethod("best-effort-style", GameTooltipStatusBar, "SetShown", false)
                ns.SafeCallMethod("sink-forward", GameTooltipStatusBar, "SetAlpha", 0)
            end
            local attachedBar = tooltip and tooltip.StatusBar
            if attachedBar and not (attachedBar.IsForbidden and attachedBar:IsForbidden()) then
                ns.SafeCallMethod("best-effort-style", attachedBar, "SetShown", false)
                ns.SafeCallMethod("sink-forward", attachedBar, "SetAlpha", 0)
            end
            local pool = tooltip and tooltip.StatusBarPool
            if pool and pool.EnumerateActive then
                local okIter, iter, state = ns.SafeCallMethod("best-effort-style", pool, "EnumerateActive")
                if okIter and type(iter) == "function" then
                    for pooledBar in iter, state do
                        ns.SafeCallMethod("best-effort-style", pooledBar, "SetShown", false)
                        ns.SafeCallMethod("sink-forward", pooledBar, "SetAlpha", 0)
                    end
                end
            end
        end
    end

    AddTrackedTooltipPostCall(Enum.TooltipDataType.Unit, "qol.unitProcessor", function(tooltip)
        TooltipDebugCount("qol.unitPost")
        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        local hidden = RunTrackedUnitStep("qol.unitVisibilityPost", HandleUnitVisibilityPost, tooltip, settings)
        if hidden then return end

        RunTrackedUnitStep("qol.unitHealthPost", HandleUnitHealthPost, tooltip, settings)

        local unit = ResolveTooltipUnit(tooltip)
        if not unit then
            TooltipDebugCount("qol.unitNoUnit")
            return
        end

        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then
            TooltipDebugCount("qol.unitNonPlayer")
            return
        end
        TooltipDebugCount("qol.unitPlayer")

        RunTrackedUnitStep("qol.unitNamePost", HandleUnitNamePost, tooltip, settings, unit)
        RunTrackedUnitStep("qol.unitGuildPost", HandleUnitGuildPost, tooltip, settings, unit)
        RunTrackedUnitStep("qol.unitClassPost", HandleUnitClassPost, tooltip, settings, unit)
        RunTrackedUnitStep("qol.unitExtrasPost", HandleUnitExtrasPost, tooltip, settings, unit)
    end)

    local tooltipSpellIDAdded = setmetatable({}, {__mode = "k"})
    local tooltipMaxStackAdded = setmetatable({}, {__mode = "k"})

    local gtSpellIDWatcher = CreateFrame("Frame")
    local gtSpellIDWasShown = false
    local gtVisibilityElapsed = 0
    local TOOLTIP_VISIBILITY_CHECK_INTERVAL = 0.05
    gtSpellIDWatcher:SetScript("OnUpdate", function(_, elapsed)
        gtVisibilityElapsed = gtVisibilityElapsed + (elapsed or 0)
        if gtVisibilityElapsed >= TOOLTIP_VISIBILITY_CHECK_INTERVAL then
            gtVisibilityElapsed = 0

            local shown = GameTooltip:IsShown()
            if shown then
                TooltipDebugCount("qol.visibilityFrame")
            end
            if shown and not gtSpellIDWasShown then
                gtTooltipHadUnit = false
                ResetTooltipHideFade()
            end
            if gtSpellIDWasShown and not shown then
                gtTooltipHadUnit = false
                ResetTooltipHideFade()
                InvalidatePendingSetUnit()
                tooltipSpellIDAdded[GameTooltip] = nil
                tooltipMaxStackAdded[GameTooltip] = nil
                tooltipPlayerItemLevelGUID[GameTooltip] = nil
                tooltipUnitInfoState[GameTooltip] = nil
            elseif shown then
                TooltipDebugCount("qol.visibilityCheck")
                if not gtTooltipHadUnit then
                    local gtUnit = ResolveTooltipUnit(GameTooltip)
                    if gtUnit then
                        gtTooltipHadUnit = true
                    end
                end
                local settings = Provider:GetSettings()
                if not settings or not settings.enabled then
                    ResetTooltipHideFade()
                elseif ShouldHideOwnedTooltip(GameTooltip) then
                    ResetTooltipHideFade()
                    GameTooltip:Hide()
                elseif ShouldKeepTooltipVisible(GameTooltip) then
                    if tooltipHideFadeState.active then
                        ResetTooltipHideFade()
                    end
                else
                    if not tooltipHideFadeState.active then
                        StartTooltipHideFade(settings.hideDelay)
                    end
                end
            end
            gtSpellIDWasShown = shown
        end

        if tooltipHideFadeState.active then
            tooltipHideFadeState.elapsed = tooltipHideFadeState.elapsed + (elapsed or 0)
            local duration = tooltipHideFadeState.duration
            local progress = (duration > 0) and (tooltipHideFadeState.elapsed / duration) or 1
            if progress >= 1 then
                ResetTooltipHideFade()
                GameTooltip:Hide()
            else
                local nextAlpha = math.max(0, tooltipHideFadeState.startAlpha * (1 - progress))
                ns.SafeCallMethod("sink-forward", GameTooltip, "SetAlpha", nextAlpha)
            end
        end
    end)

    local idOwnerSkipPrefixes = {
        "GroupFinderFrame",
        "LFGList",
        "PVEFrame",
        "EncounterJournal",
    }

    local function FrameNameStartsWithAny(name, prefixes)
        if type(name) ~= "string" then return false end
        for i = 1, #prefixes do
            local prefix = prefixes[i]
            if string.sub(name, 1, #prefix) == prefix then
                return true
            end
        end
        return false
    end

    local function GetFrameNameSafe(frame)
        if not frame or not frame.GetName then return nil end
        local ok, name = pcall(frame.GetName, frame)
        if ok and name and not Helpers.IsSecretValue(name) then
            return name
        end
        return nil
    end

    local function TooltipOwnerSkipsIDInjection(tooltip)
        if not tooltip or not tooltip.GetOwner then return false end
        local okOwner, owner = pcall(tooltip.GetOwner, tooltip)
        if not okOwner or not owner then return false end

        local depth = 0
        while owner and depth < 6 do
            local ownerName = GetFrameNameSafe(owner)
            if FrameNameStartsWithAny(ownerName, idOwnerSkipPrefixes) then
                return true
            end

            if not owner.GetParent then
                return false
            end
            local okParent, parent = pcall(owner.GetParent, owner)
            if not okParent or parent == owner then
                return false
            end
            owner = parent
            depth = depth + 1
        end

        return false
    end

    local function ShouldShowTooltipIDs()
        local settings = Provider:GetSettings()
        return settings and settings.enabled and (settings.showSpellIDs or settings.showItemMaxStackSize)
    end

    local function ShouldProcessTooltipIDs(tooltip)
        if tooltipRefreshInProgress then
            TooltipDebugCount("qol.idPostSkipped")
            return false
        end
        if not ShouldShowTooltipIDs() then
            TooltipDebugCount("qol.idPostSkipped")
            return false
        end
        if not tooltip or tooltip.IsForbidden and tooltip:IsForbidden() then
            TooltipDebugCount("qol.idPostSkipped")
            return false
        end
        if IsInternalEmbeddedItemTooltipFrame(tooltip) then
            TooltipDebugCount("qol.idPostSkipped")
            return false
        end
        if TooltipOwnerSkipsIDInjection(tooltip) then
            TooltipDebugCount("qol.idOwnerSkipped")
            return false
        end
        return true
    end

    local function ResolveIDFromDataFields(data, secondaryKey, dataCounter)
        if not data then return nil end
        local fromID = data.id
        if type(fromID) == "number" then
            if not (type(issecretvalue) == "function" and issecretvalue(fromID)) then
                TooltipDebugCount(dataCounter)
                return fromID
            end
        end

        local fromSecondary = data[secondaryKey]
        if type(fromSecondary) == "number" then
            if not (type(issecretvalue) == "function" and issecretvalue(fromSecondary)) then
                TooltipDebugCount(dataCounter)
                return fromSecondary
            end
        end
        return nil
    end

    local function ResolveSpellIDFromTooltipData(tooltip, data, allowTooltipFallback)
        local fromData = ResolveIDFromDataFields(data, "spellID", "qol.spellIDDataHit")
        if fromData then return fromData end

        if allowTooltipFallback and tooltip and tooltip.GetSpell then
            local ok, a, b, c, d = pcall(tooltip.GetSpell, tooltip)
            if ok then
                if type(d) == "number" then TooltipDebugCount("qol.spellIDFallbackHit"); return d end
                if type(c) == "number" then TooltipDebugCount("qol.spellIDFallbackHit"); return c end
                if type(b) == "number" then TooltipDebugCount("qol.spellIDFallbackHit"); return b end
                if type(a) == "number" then TooltipDebugCount("qol.spellIDFallbackHit"); return a end
            end
        end

        return nil
    end

    local function BuildSpellIDDedupeKey(data, spellID)
        if not data or type(data.dataInstanceID) ~= "number" then
            return "spell:" .. tostring(spellID)
        end
        return tostring(data.dataInstanceID) .. ":" .. tostring(spellID)
    end

    local function ResolveItemIDFromTooltipData(tooltip, data, allowTooltipFallback)
        local fromData = ResolveIDFromDataFields(data, "itemID", "qol.itemIDDataHit")
        if fromData then return fromData end

        if allowTooltipFallback and tooltip and tooltip.GetItem then
            local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
            if ok and type(itemLink) == "string" then
                local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                if itemID then
                    TooltipDebugCount("qol.itemIDFallbackHit")
                    return itemID
                end
            end
        end

        return nil
    end

    local function BuildItemIDDedupeKey(data, itemID)
        if not data or type(data.dataInstanceID) ~= "number" then
            return "item:" .. tostring(itemID)
        end
        return tostring(data.dataInstanceID) .. ":item:" .. tostring(itemID)
    end

    local function AddSpellIDToTooltip(tooltip, spellID, data, skipShow)
        if not spellID then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.showSpellIDs then return end
        if type(spellID) ~= "number" then return end
        if type(issecretvalue) == "function" and issecretvalue(spellID) then return end
        local dedupeKey = BuildSpellIDDedupeKey(data, spellID)
        if tooltipSpellIDAdded[tooltip] == dedupeKey then return end
        tooltipSpellIDAdded[tooltip] = dedupeKey

        local iconID = nil
        if C_Spell and C_Spell.GetSpellTexture then
            local result = C_Spell.GetSpellTexture(spellID)
            if result and type(result) == "number" then
                iconID = result
            end
        end

        tooltip:AddLine(" ")
        AddTooltipInfoLine(tooltip, ns.L["Spell ID"], tostring(spellID), 0.5, 0.8, 1, 1, 1, 1)
        if iconID then
            AddTooltipInfoLine(tooltip, ns.L["Icon ID"], tostring(iconID), 0.5, 0.8, 1, 1, 1, 1)
        end

        if not skipShow then
            RefreshTooltipLayout(tooltip)
        end
    end

    local function AddItemIDToTooltip(tooltip, itemID, data, skipShow)
        if not itemID then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.showSpellIDs then return end
        if type(itemID) ~= "number" then return end
        if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
        local dedupeKey = BuildItemIDDedupeKey(data, itemID)
        if tooltipSpellIDAdded[tooltip] == dedupeKey then return end
        tooltipSpellIDAdded[tooltip] = dedupeKey

        tooltip:AddLine(" ")
        AddTooltipInfoLine(tooltip, ns.L["Item ID"], tostring(itemID), 0.5, 0.8, 1, 1, 1, 1)

        if not skipShow then
            RefreshTooltipLayout(tooltip)
        end
    end

    local function AddItemMaxStackSizeToTooltip(tooltip, itemID, data, skipShow)
        if not itemID then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.showItemMaxStackSize then return end
        if type(itemID) ~= "number" then return end
        if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
        if not C_Item or not C_Item.GetItemMaxStackSizeByID then return end

        local stackSize = C_Item.GetItemMaxStackSizeByID(itemID)
        if type(stackSize) ~= "number" or stackSize <= 1 then return end

        local dedupeKey = BuildItemIDDedupeKey(data, itemID)
        if tooltipMaxStackAdded[tooltip] == dedupeKey then return end
        tooltipMaxStackAdded[tooltip] = dedupeKey

        tooltip:AddLine(" ")
        AddTooltipInfoLine(tooltip, ns.L["Max Stack"], tostring(stackSize), 0.5, 0.8, 1, 1, 1, 1)

        if not skipShow then
            RefreshTooltipLayout(tooltip)
        end
    end

    local function TryAddSpellIDFromTooltipData(tooltip, data)
        local spellID = ResolveSpellIDFromTooltipData(tooltip, data, true)
        if spellID then
            AddSpellIDToTooltip(tooltip, spellID, data)
        end
    end

    local function TryAddItemIDFromTooltipData(tooltip, data)
        local itemID = ResolveItemIDFromTooltipData(tooltip, data, true)
        if itemID then
            AddItemIDToTooltip(tooltip, itemID, data)
        end
    end

    local function TryAddItemMaxStackSizeFromTooltipData(tooltip, data)
        local itemID = ResolveItemIDFromTooltipData(tooltip, data, true)
        if itemID then
            AddItemMaxStackSizeToTooltip(tooltip, itemID, data)
        end
    end

    AddTrackedTooltipPostCall(Enum.TooltipDataType.Spell, "qol.spellIDPost", function(tooltip, data)
        TooltipDebugCount("qol.spellPost")
        if not ShouldProcessTooltipIDs(tooltip) then return end
        ns.SafeCall("bulkhead", TryAddSpellIDFromTooltipData, tooltip, data)
    end)

    local auraTooltipType = Enum.TooltipDataType.UnitAura or Enum.TooltipDataType.Aura
    if auraTooltipType then
        AddTrackedTooltipPostCall(auraTooltipType, "qol.auraIDPost", function(tooltip, data)
            TooltipDebugCount("qol.auraPost")
            if InCombatLockdown() then return end
            if not ShouldProcessTooltipIDs(tooltip) then return end
            ns.SafeCall("bulkhead", TryAddSpellIDFromTooltipData, tooltip, data)
        end)
    end

    local function ApplyOwnedTooltipHide(tooltip, context)
        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end
        InvalidatePendingSetUnit()
        if ShouldHideOwnedTooltip(tooltip, context) then
            tooltip:Hide()
        end
    end

    AddTrackedTooltipPostCall(Enum.TooltipDataType.Spell, "qol.spellVisibilityPost", function(tooltip)
        TooltipDebugCount("qol.spellVisibilityPost")
        ApplyOwnedTooltipHide(tooltip, "abilities")
    end)

    AddTrackedTooltipPostCall(Enum.TooltipDataType.Item, "qol.itemPost", function(tooltip, data)
        TooltipDebugCount("qol.itemPost")
        if ShouldProcessTooltipIDs(tooltip) then
            ns.SafeCall("bulkhead", TryAddItemIDFromTooltipData, tooltip, data)
            ns.SafeCall("bulkhead", TryAddItemMaxStackSizeFromTooltipData, tooltip, data)
        end

        ApplyOwnedTooltipHide(tooltip, "items")
    end)

    if TooltipInspect and TooltipInspect.RegisterRefreshCallback then
        TooltipInspect:RegisterRefreshCallback(function(guid)
            if not GameTooltip or not GameTooltip:IsShown() then return end
            if InCombatLockdown() then return end

            local settings = Provider:GetSettings()
            if not settings or not settings.enabled or not settings.showPlayerItemLevel then return end

            local unit = ResolveTooltipUnit(GameTooltip)
            if not unit then return end

            local unitGUID = UnitGUID(unit)
            if Helpers.IsSecretValue(unitGUID) or Helpers.IsSecretValue(guid) then
                return -- @secret-policy: reject-secret-ids
            end
            if not unitGUID then return end
            if Helpers.SafeCompare(unitGUID, guid) ~= true then return end

            AddPlayerItemLevelToTooltip(GameTooltip, unit, false)
        end)
    end

end

local function OnUnitTargetChanged(changedUnit)
    if not GameTooltip:IsShown() then return end
    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit or unit ~= changedUnit then return end

    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not IsSettingEnabled(settings, "showTooltipTarget", true) then return end

    local state = tooltipUnitInfoState[GameTooltip]
    if not state then return end

    RefreshTooltipLayout(GameTooltip)
end

local function OnUnitAuraChanged(changedUnit)
    if InCombatLockdown() then return end
    if not GameTooltip:IsShown() then return end
    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit or unit ~= changedUnit then return end

    local guid = UnitGUID(unit)
    if not Helpers.IsSecretValue(guid) and guid then
        ClearCachedMountName(guid)
    end

    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not IsSettingEnabled(settings, "showPlayerMount", true) then return end

    local state = tooltipUnitInfoState[GameTooltip]
    if not state then return end

    state.mountResolved = false
    state.mountName = nil
    state.mountNextAuraIndex = 1
    ScheduleDeferredUnitInfo(GameTooltip, unit)
    RefreshTooltipLayout(GameTooltip)
end

local function OnModifierStateChanged()
    if not GameTooltip:IsShown() then return end
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled then return end
    local context = ResolveTooltipVisibilityContext(GameTooltip)
    if context and not Provider:ShouldShowTooltip(context) then
        GameTooltip:Hide()
    end
end

local function OnCombatStateChanged(inCombat)
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not settings.hideInCombat then return end
    if inCombat then
        if not settings.combatKey or settings.combatKey == "NONE" or not Provider:IsModifierActive(settings.combatKey) then
            GameTooltip:Hide()
        end
    end
end

function TooltipEngine:Initialize()
    Provider = ns.TooltipProvider
    TooltipInspect = ns.TooltipInspect

    SetupTooltipHook()

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("UNIT_TARGET")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "MODIFIER_STATE_CHANGED" then
            OnModifierStateChanged()
        elseif event == "PLAYER_REGEN_DISABLED" then
            OnCombatStateChanged(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            OnCombatStateChanged(false)
        elseif event == "UNIT_TARGET" then
            OnUnitTargetChanged(arg1)
        end
    end)

    if ns.AuraEvents then
        ns.AuraEvents:Subscribe("all", OnUnitAuraChanged)
    end
end

function TooltipEngine:Refresh()
end

function TooltipEngine:SetEnabled(enabled)
end

ns.TooltipProvider:RegisterEngine("default", TooltipEngine)
