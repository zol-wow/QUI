--[[
    QUI Tooltip Engine
    Hook-based tooltip system.
    Registers with TooltipProvider as the "default" engine.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Provider  -- resolved after provider loads
local TooltipInspect

-- Locals for performance
local GameTooltip = GameTooltip
local UIParent = UIParent
local WorldFrame = WorldFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local wipe = wipe
local debugprofilestop = debugprofilestop
local collectgarbage = collectgarbage

---------------------------------------------------------------------------
-- ENGINE TABLE
---------------------------------------------------------------------------
local TooltipEngine = {}

---------------------------------------------------------------------------
-- Tooltip Debug Sampler
---------------------------------------------------------------------------
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

    do local mp = ns._memprobes or {}; ns._memprobes = mp
        mp[#mp + 1] = { name = "Tooltip_debugCounters", tbl = debugCounters }
        mp[#mp + 1] = { name = "Tooltip_debugSlowLog", tbl = debugSlowLog }
    end

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
            pcall(UpdateAddOnMemoryUsage)
        end
        if GetAddOnMemoryUsage then
            local ok, mem = pcall(GetAddOnMemoryUsage, ADDON_NAME)
            if ok and type(mem) == "number" then
                return mem
            end
        end
        return nil
    end

    local function FrameLabel(frame)
        if not frame then return "nil" end
        if frame.GetName then
            local ok, name = pcall(frame.GetName, frame)
            if ok and name then return name end
        end
        return tostring(frame)
    end

    local function DescribeTooltipContext()
        if not GameTooltip then
            return "gt=nil"
        end
        local okShown, shown = pcall(GameTooltip.IsShown, GameTooltip)
        if not okShown or not shown then
            return "gt=hidden"
        end

        local owner
        if GameTooltip.GetOwner then
            local okOwner, result = pcall(GameTooltip.GetOwner, GameTooltip)
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
        AppendCounter(parts, "skin.refitNoOverflow", "refitOK")
        AppendCounter(parts, "skin.refitTinyOverflow", "refitTiny")
        AppendCounter(parts, "skin.refitVisibleExtend", "refitBIG")
        AppendCounter(parts, "skin.refitNoExtents", "refitNoExt")
        AppendCounter(parts, "skin.refitOwnerReset", "refitReset")
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
        if subcmd == "help" then
            print("|cff60A5FAQUI tooltipdebug:|r /qui tooltipdebug on [seconds], off, report, reset, slow [ms], bypass qol|skin|all|off")
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

---------------------------------------------------------------------------
-- Cursor Follow State (engine-local)
---------------------------------------------------------------------------
local cursorFollowActive = Helpers.CreateStateTable()
local cursorFollowHooked = Helpers.CreateStateTable()
local CURSOR_SAFETY_CHECK_INTERVAL = 0.2
local gtCursorSafetyElapsed = CURSOR_SAFETY_CHECK_INTERVAL

-- TAINT SAFETY: For GameTooltip, cursor follow uses a SEPARATE watcher
-- frame instead of HookScript. HookScript on GameTooltip permanently taints
-- its dispatch tables, causing ADDON_ACTION_BLOCKED when the world map's
-- secure context (secureexecuterange) uses GameTooltip for map pins.
local gtCursorWatcher

-- World quest / map tooltips can register a widget container on GameTooltip.
-- Re-anchoring or re-showing the tooltip from addon code while that container
-- is active can re-enter Blizzard's secure widget layout and trigger
-- LayoutFrame secret-value comparison errors.
local function HasActiveWidgetContainer(tooltip)
    if not tooltip or not tooltip.GetChildren or not tooltip.GetNumChildren then return false end
    TooltipDebugCount("qol.widgetScan")

    local okCount, numChildren = pcall(tooltip.GetNumChildren, tooltip)
    if not okCount or not numChildren then return false end

    for i = 1, numChildren do
        local child = select(i, tooltip:GetChildren())
        if child and (child.RegisterForWidgetSet or child.shownWidgetCount ~= nil or child.widgetSetID ~= nil) then
            local widgetSetID = child.widgetSetID
            if widgetSetID ~= nil then
                TooltipDebugCount("qol.widgetHit")
                return true
            end

            local shownWidgetCount = child.shownWidgetCount
            if shownWidgetCount ~= nil then
                if Helpers.IsSecretValue(shownWidgetCount) then
                    TooltipDebugCount("qol.widgetHit")
                    return true
                end
                shownWidgetCount = tonumber(shownWidgetCount)
                if shownWidgetCount and shownWidgetCount > 0 then
                    TooltipDebugCount("qol.widgetHit")
                    return true
                end
            end

            local numWidgetsShowing = child.numWidgetsShowing
            if numWidgetsShowing ~= nil then
                if Helpers.IsSecretValue(numWidgetsShowing) then
                    TooltipDebugCount("qol.widgetHit")
                    return true
                end
                numWidgetsShowing = tonumber(numWidgetsShowing)
                if numWidgetsShowing and numWidgetsShowing > 0 then
                    TooltipDebugCount("qol.widgetHit")
                    return true
                end
            end

            if child.IsShown then
                local okShown, shown = pcall(child.IsShown, child)
                if okShown and shown then
                    TooltipDebugCount("qol.widgetHit")
                    return true
                end
            end
        end
    end

    return false
end

-- Quest/world map reward tooltips can also attach Blizzard MoneyFrame children
-- to GameTooltip. Re-anchoring or forcing a re-show while those are active can
-- taint Blizzard's money width math and explode in MoneyFrame_Update.
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
                local okName, name = pcall(child.GetName, child)
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
        -- Use a separate watcher frame for GameTooltip to avoid taint
        if not gtCursorWatcher then
            gtCursorWatcher = CreateFrame("Frame")
            gtCursorWatcher:SetScript("OnUpdate", function(_, elapsed)
                TooltipDebugCount("qol.cursorFrame")
                if not cursorFollowActive[GameTooltip] then return end
                if not GameTooltip:IsShown() then
                    cursorFollowActive[GameTooltip] = nil
                    return
                end
                gtCursorSafetyElapsed = gtCursorSafetyElapsed + (elapsed or 0)
                if gtCursorSafetyElapsed >= CURSOR_SAFETY_CHECK_INTERVAL then
                    TooltipDebugCount("qol.cursorSafety")
                    gtCursorSafetyElapsed = 0
                    if HasActiveMoneyFrame(GameTooltip) then
                        cursorFollowActive[GameTooltip] = nil
                        return
                    end
                    if HasActiveWidgetContainer(GameTooltip) then
                        cursorFollowActive[GameTooltip] = nil
                        return
                    end
                end
                local settings = Provider:GetSettings()
                if not settings or not settings.enabled or not settings.anchorToCursor then
                    cursorFollowActive[GameTooltip] = nil
                    return
                end
                TooltipDebugCount("qol.cursorPosition")
                Provider:PositionTooltipAtCursor(GameTooltip, settings)
            end)
        end
        return
    end

    -- Non-GameTooltip frames can safely use HookScript
    tooltip:HookScript("OnUpdate", function(self)
        if not cursorFollowActive[self] then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.anchorToCursor then
            cursorFollowActive[self] = nil
            return
        end
        -- PositionTooltipAtCursor uses cached UIParent scale (updated on
        -- UI_SCALE_CHANGED) so arithmetic is safe during combat.
        -- GetCursorPosition returns screen coordinates, not combat-restricted data.
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
    EnsureCursorFollowHooks(tooltip)
    tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
    if tooltip == GameTooltip then
        gtCursorSafetyElapsed = CURSOR_SAFETY_CHECK_INTERVAL
    end
    cursorFollowActive[tooltip] = true
    Provider:PositionTooltipAtCursor(tooltip, settings or Provider:GetSettings())
    return true
end

---------------------------------------------------------------------------
-- DEBOUNCE STATE
---------------------------------------------------------------------------
local pendingSetUnitToken = 0
local tooltipPlayerItemLevelGUID = setmetatable({}, {__mode = "k"})
local DEFAULT_PLAYER_ILVL_BRACKETS = {
    white = 245,
    green = 255,
    blue = 265,
    purple = 275,
    orange = 285,
}

-- Tooltip Unit Info State (target, mount, M+ rating)
local tooltipUnitInfoState = setmetatable({}, {__mode = "k"})

-- Mount Name Cache
local mountNameCache = {}
local mountNameCacheTime = {}
local mountSpellNameCache = {}
local mountSpellNameCacheCount = 0
local mountNameCacheCount = 0
local mountNameCacheLastPrune = 0
local MOUNT_CACHE_TTL = 0.75
local MOUNT_CACHE_MAX_ENTRIES = 80
local MOUNT_SPELL_CACHE_MAX_ENTRIES = 512
local MOUNT_SCAN_AURAS_PER_PASS = 12

local ScheduleDeferredUnitInfo

do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "Tooltip_mountNameCache", tbl = mountNameCache }
    mp[#mp + 1] = { name = "Tooltip_mountSpellCache", tbl = mountSpellNameCache }
end

local function RefreshTooltipLayout(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    -- Re-layout of GameTooltip is unsafe while Blizzard widget containers are
    -- active. World quest/map tooltips use this path, and forcing a refresh from
    -- addon code can trip LayoutFrame secret-value comparisons on clear/hide.
    if tooltip == GameTooltip then
        if HasActiveMoneyFrame(tooltip) then
            return
        end
        if HasActiveWidgetContainer(tooltip) then
            return
        end
        if Helpers.HasTaintedWidgetContainer and Helpers.HasTaintedWidgetContainer(tooltip) then
            return
        end
    end

    -- Try the legacy resize hook (still present on some tooltip variants).
    -- Midnight's GameTooltip dropped Layout/MarkDirty/UpdateTooltipSize from
    -- the Lua API entirely, so for that path the chrome refit below is what
    -- actually fixes the short-chrome artifact.
    if type(tooltip.UpdateTooltipSize) == "function" then
        pcall(tooltip.UpdateTooltipSize, tooltip)
    end
    -- Only call Show() on hidden tooltips. Show() triggers Blizzard's internal
    -- NineSlice restyle which the skinning watcher can only catch one frame
    -- later, causing a visible flicker.
    local alreadyShown = tooltip.IsShown and tooltip:IsShown()
    if not alreadyShown then
        pcall(tooltip.Show, tooltip)
    end

    -- After AddLine/AddDoubleLine on a shown Midnight tooltip, the C-side
    -- renders the new FontStrings but tooltip:GetHeight() does not grow.
    -- The QUI chrome anchored via SetAllPoints tracks the stale height,
    -- exposing Blizzard's backdrop on the appended lines (Target / M+ Rating).
    -- The skinning module owns the chrome and re-anchors its bottom past
    -- the tooltip's reported bottom by the actual FontString overflow.
    local refit = ns.QUI_RefitTooltipChromeToContent
    if refit then
        pcall(refit, tooltip)
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

-- Identify owners that are themselves tooltip frames (addon detail panel
-- anchored to FriendsTooltip etc.). FriendsTooltip in WoW Midnight is a
-- styled Frame, not a SharedTooltipTemplate-derived tooltip — its
-- IsObjectType("GameTooltip") and NumLines/AddLine duck-typing both return
-- false. Name-based fallback catches it.
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
    -- Tooltip-frame owners: parent's transient fade-in alpha would trigger
    -- the faded-hide path every frame. Trust the parent's IsShown via
    -- ShouldKeepTooltipVisible's matching branch instead.
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

-- Sticky flag for the current GameTooltip show cycle: did this tooltip ever
-- carry a unit token (player, NPC, nameplate, mouseover) since it was last
-- shown? Set true the first tick we observe GetUnit returning a unit, reset
-- to false on the show→hide transition. Used to distinguish "world unit
-- tooltip whose mouseover just cleared" (where unit is now nil but we want to
-- hide) from "true world object tooltip" (mining node, etc., where unit was
-- always nil and we must keep the WorldFrame safety net).
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
        pcall(GameTooltip.SetAlpha, GameTooltip, 1)
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

local function IsTooltipOwnerHovered(owner)
    if not owner or not Provider then
        return false
    end

    local focus = Provider.GetTopMouseFrame and Provider:GetTopMouseFrame()
    if focus and IsChildOfFrame(focus, owner) then
        return true
    end

    if owner.IsMouseOver then
        local ok, isOver = pcall(owner.IsMouseOver, owner)
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
        -- Owner is itself a tooltip frame (addon detail panel anchored to
        -- FriendsTooltip etc.): cursor sits on the frame that owns the parent
        -- tooltip, never on this tooltip's rect, so IsTooltipOwnerHovered
        -- always returns false → hideDelay=0 fires Hide → addon's per-frame
        -- Show puts it back → 12 Hz flash. Track parent's IsShown instead.
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

    if Provider.IsFrameBlockingMouse and Provider:IsFrameBlockingMouse() then
        return true
    end

    -- World object tooltips (mining/herb nodes, summon stones, fishing schools,
    -- ground loot) have no unit slot and mouse focus on WorldFrame. The throttle
    -- can fire on the very first frame they show; without this safety net the
    -- check returns false and the tooltip is hidden before the user sees it.
    -- Gate on the "had a unit this cycle" flag: if the tooltip ever carried
    -- a unit during this show cycle (player, NPC, nameplate, mouseover), then
    -- a current `unit == nil` means mouseover just cleared and we should fall
    -- through to the hide path so hideDelay=0 actually takes effect.
    -- Only true world *objects* (unit was never set this cycle) get the
    -- WorldFrame safety net.
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
        return 1, 1, 1
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
            local ok, color = pcall(C_ClassColor.GetClassColor, classToken)
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
        return "Player"
    end

    if playerData.specName and playerData.specName ~= "" and playerData.className and playerData.className ~= "" then
        return string.format("%s %s", playerData.specName, playerData.className)
    end

    if playerData.className and playerData.className ~= "" then
        return playerData.className
    end

    return "Player"
end

local function AddPlayerItemLevelToTooltip(tooltip, unit, skipShow)
    TooltipDebugCount("qol.itemLevelAttempt")
    if not TooltipInspect or not unit or not tooltip then return false end
    if InCombatLockdown() then return false end

    local playerData = TooltipInspect:GetCachedPlayerData(unit)
    if not playerData or not playerData.itemLevel then
        if not InCombatLockdown() then
            TooltipDebugCount("qol.itemLevelQueued")
            TooltipInspect:QueueInspect(unit)
        end
        return false
    end

    local guid = UnitGUID(unit)
    if tooltipPlayerItemLevelGUID[tooltip] == guid then
        TooltipDebugCount("qol.itemLevelDuplicate")
        return false
    end

    if Helpers.IsSecretValue(playerData.itemLevel) then
        TooltipDebugCount("qol.itemLevelSecret")
        return false
    end

    local itemLevel = tonumber(playerData.itemLevel)
    if not itemLevel or itemLevel <= 0 then
        return false
    end

    local label = GetPlayerItemLevelLabel(playerData)
    local labelR, labelG, labelB = GetPlayerClassColor(playerData.classToken)
    local valueR, valueG, valueB = GetPlayerItemLevelColor(itemLevel)

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(label, string.format("%.1f", itemLevel), labelR, labelG, labelB, valueR, valueG, valueB)
    tooltipPlayerItemLevelGUID[tooltip] = guid
    TooltipDebugCount("qol.itemLevelAdded")

    if not skipShow then
        RefreshTooltipLayout(tooltip)
    end

    return true
end

---------------------------------------------------------------------------
-- Tooltip Unit Info Helper Functions (Target, Mount, M+ Rating)
---------------------------------------------------------------------------

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
    if not okName or not targetName or Helpers.IsSecretValue(targetName) then
        targetName = "Unknown"
    end

    local okClass, _, classToken = pcall(UnitClass, targetUnit)
    local valueR, valueG, valueB = 1, 1, 1
    if okClass and classToken and not Helpers.IsSecretValue(classToken) then
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

    -- Add the Target line once per tooltip state cycle. State resets when the
    -- mouseover GUID changes (via EnsureTooltipUnitInfoState), so a fresh hover
    -- always re-adds. Comparing names is unsafe because UnitName on a tainted
    -- target unit can return a secret string that taints == comparison even
    -- when forwarded through C-side AddDoubleLine cleanly.
    if state.targetAdded then return false end

    local targetInfo = ResolveTooltipTargetInfo(unit)
    if not targetInfo then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    tooltip:AddDoubleLine("Target:", targetInfo.name, 0.7, 0.82, 1, targetInfo.valueR, targetInfo.valueG, targetInfo.valueB)
    state.targetAdded = true
    TooltipDebugCount("qol.targetAdded")
    return true
end

local function SetMountSpellNameCache(spellID, mountName)
    if not spellID then return end
    if mountSpellNameCache[spellID] == nil then
        mountSpellNameCacheCount = mountSpellNameCacheCount + 1
    end
    mountSpellNameCache[spellID] = mountName or false

    if mountSpellNameCacheCount > MOUNT_SPELL_CACHE_MAX_ENTRIES then
        wipe(mountSpellNameCache)
        mountSpellNameCacheCount = 0
    end
end

local function GetMountNameFromSpellID(spellID)
    if not spellID then return nil end
    if Helpers.IsSecretValue(spellID) then return nil end
    if spellID == 0 then return nil end

    local cached = mountSpellNameCache[spellID]
    if cached ~= nil then
        TooltipDebugCount(cached and "qol.mountSpellCacheHit" or "qol.mountSpellCacheNegHit")
        return cached or nil
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

    local okInfo, mountName = pcall(C_MountJournal.GetMountInfoByID, mountID)
    if not okInfo or not mountName then
        SetMountSpellNameCache(spellID, false)
        return nil
    end

    SetMountSpellNameCache(spellID, mountName)
    return mountName
end

local function ClearCachedMountName(guid)
    if not guid then return end
    if mountNameCacheTime[guid] ~= nil then
        mountNameCacheCount = mountNameCacheCount - 1
    end
    mountNameCache[guid] = nil
    mountNameCacheTime[guid] = nil
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
    return cached or nil, true
end

local function SetCachedMountName(guid, mountName)
    if not guid then return end
    local now = GetTime()
    if mountNameCacheTime[guid] == nil then
        mountNameCacheCount = mountNameCacheCount + 1
    end
    mountNameCache[guid] = mountName or false
    mountNameCacheTime[guid] = now
    PruneMountNameCache(now, false)
end

local function GetMountedPlayerMountName(unit, state)
    if not unit or not UnitExists(unit) then return nil, true end
    TooltipDebugCount("qol.mountScanPass")
    if InCombatLockdown() then
        -- During combat, can't iterate auras, skip mount detection
        return nil, true
    end

    local guid = UnitGUID(unit)
    if not guid or Helpers.IsSecretValue(guid) then return nil, true end

    local cachedName, cacheHit = GetCachedMountName(guid)
    if cacheHit then
        TooltipDebugCount(cachedName and "qol.mountCacheHit" or "qol.mountCacheNegHit")
        return cachedName, true
    end
    TooltipDebugCount("qol.mountCacheMiss")

    local startIndex = (state and state.mountNextAuraIndex) or 1
    local endIndex = math.min(80, startIndex + MOUNT_SCAN_AURAS_PER_PASS - 1)

    -- Try C_UnitAuras (modern API, WoW 10.0+)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = startIndex, endIndex do
            TooltipDebugCount("qol.mountAuraScanned")
            local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not auraData then
                SetCachedMountName(guid, false)
                return nil, true
            end

            if auraData.spellId then
                local mountName = GetMountNameFromSpellID(auraData.spellId)
                if mountName then
                    SetCachedMountName(guid, mountName)
                    return mountName, true
                end
            end
        end
    else
        -- Fallback to legacy UnitAura API
        for i = startIndex, endIndex do
            TooltipDebugCount("qol.mountAuraScanned")
            local ok, name, _, _, _, _, _, _, _, spellID = pcall(UnitAura, unit, i, "HELPFUL")
            if not ok or not name then
                SetCachedMountName(guid, false)
                return nil, true
            end

            if spellID then
                local mountName = GetMountNameFromSpellID(spellID)
                if mountName then
                    SetCachedMountName(guid, mountName)
                    return mountName, true
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

    local mountName, resolved = GetMountedPlayerMountName(unit, state)
    if resolved then
        state.mountResolved = true
        state.mountName = mountName
    end
    if not mountName then return resolved and false or nil end

    -- Dedupe by name: skip if the same mount was already appended.
    -- Aura ticks (HoTs, raid buffs) fire OnUnitAuraChanged constantly while
    -- the tooltip is shown, and that handler clears mountResolved/mountName
    -- to force a re-scan. Without this guard each tick re-appended a fresh
    -- "Mount: X" line because Blizzard's tooltip API has no way to remove
    -- or edit existing lines.
    if state.lastMountName == mountName then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    tooltip:AddDoubleLine("Mount:", mountName, 0.65, 1, 0.65, 1, 1, 1)
    state.lastMountName = mountName
    TooltipDebugCount("qol.mountAdded")
    return true
end

local function GetPlayerMythicRating(unit)
    if not unit then return nil end

    -- Try RaiderIO addon first
    if _G.RaiderIO and _G.RaiderIO.GetProfile then
        local ok, profile = pcall(_G.RaiderIO.GetProfile, unit)
        if ok and profile and profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.currentScore then
            local score = Helpers.SafeToNumber(profile.mythicKeystoneProfile.currentScore, 0)
            if score and score > 0 then
                local color = _G.RaiderIO.GetScoreColor and _G.RaiderIO.GetScoreColor(score)
                if type(color) == "table" and color.r then
                    return math.floor(score), color.r, color.g, color.b
                end
                return math.floor(score), 1, 1, 1
            end
        end
    end

    -- Fall back to native C_PlayerInfo
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

local function AddUnitTooltipInfoToTooltip(tooltip, unit, settings)
    if not tooltip or not unit or not settings then return end
    if InCombatLockdown() then return end

    local guid = UnitGUID(unit)
    if not guid or Helpers.IsSecretValue(guid) then return end

    local state = EnsureTooltipUnitInfoState(tooltip, guid)
    if not state then return end

    -- Add target info
    if IsSettingEnabled(settings, "showTooltipTarget", true) then
        AddTooltipTargetInfo(tooltip, unit, state)
    end

    -- Add mount info
    if IsSettingEnabled(settings, "showPlayerMount", true) then
        AddTooltipMountInfo(tooltip, unit, state)
    end

    -- Add M+ rating
    if IsSettingEnabled(settings, "showPlayerMythicRating", true) and not state.ratingResolved then
        local rating, r, g, b = GetPlayerMythicRating(unit)
        state.ratingResolved = true
        if rating then
            EnsureTooltipInfoSpacer(tooltip, state)
            tooltip:AddDoubleLine("M+ Rating:", string.format("%.1f", rating), 0.7, 0.82, 1, r or 1, g or 1, b or 1)
            state.ratingAdded = true
            TooltipDebugCount("qol.ratingAdded")
        end
    end
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
    if not unitGUID or Helpers.IsSecretValue(unitGUID) or unitGUID ~= guid then
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

    if IsSettingEnabled(settings, "showTooltipTarget", true) then
        changed = AddTooltipTargetInfo(tooltip, unit, state) or changed
    end

    if IsSettingEnabled(settings, "showPlayerMount", true) and not state.mountResolved then
        local added = AddTooltipMountInfo(tooltip, unit, state)
        if added == nil then
            pending = true
        else
            changed = added or changed
        end
    end

    if IsSettingEnabled(settings, "showPlayerMythicRating", true) and not state.ratingResolved then
        local rating, r, g, b = GetPlayerMythicRating(unit)
        state.ratingResolved = true
        if rating then
            EnsureTooltipInfoSpacer(tooltip, state)
            tooltip:AddDoubleLine("M+ Rating:", string.format("%.1f", rating), 0.7, 0.82, 1, r or 1, g or 1, b or 1)
            state.ratingAdded = true
            TooltipDebugCount("qol.ratingAdded")
            changed = true
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
    if not guid or Helpers.IsSecretValue(guid) then return end
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

---------------------------------------------------------------------------
-- SETUP HOOKS
---------------------------------------------------------------------------
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

        InvalidatePendingSetUnit()

        -- Visibility/context checks call methods on Blizzard frames (GetName,
        -- GetAttribute, GetActionInfo) which can taint the execution context
        -- during combat. Skip them — combat hiding is handled by the SetUnit
        -- hook and OnCombatStateChanged instead.
        if not InCombatLockdown() then
            local context = Provider:GetTooltipContext(parent)
            if context and not Provider:ShouldShowTooltip(context) then
                tooltip:Hide()
                tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                tooltip:ClearLines()
                return
            end
        end

        -- Reposition immediately — ClearAllPoints/SetPoint are C-side and
        -- handle combat safely. Do NOT call SetOwner here; Blizzard already
        -- set it and re-calling mid-build disrupts the tooltip chain.
        if settings.anchorToCursor then
            EnsureCursorFollowHooks(tooltip)
            if tooltip == GameTooltip then
                gtCursorSafetyElapsed = CURSOR_SAFETY_CHECK_INTERVAL
            end
            cursorFollowActive[tooltip] = true
            Provider:PositionTooltipAtCursor(tooltip, settings)
        else
            cursorFollowActive[tooltip] = nil
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

    local function HandleUnitNamePost(tooltip, settings, unit)
        TooltipDebugCount("qol.unitNamePost")

        local hideServer = settings.hideServerName
        local hideTitle = settings.hidePlayerTitle
        if not hideServer and not hideTitle then return end

        if hideTitle then
            local nameLine = tooltip.GetLeftLine and tooltip:GetLeftLine(1) or GameTooltipTextLeft1
            if nameLine then
                local okText, lineText = pcall(nameLine.GetText, nameLine)
                if okText and lineText and not Helpers.IsSecretValue(lineText) then
                    local okName, bareName = pcall(UnitName, unit)
                    if okName and bareName and not Helpers.IsSecretValue(bareName) and lineText ~= bareName then
                        pcall(nameLine.SetText, nameLine, bareName)
                    end
                end
            end
        end

        if hideServer then
            local okRealm, _, unitRealm = pcall(UnitName, unit)
            if okRealm and unitRealm and unitRealm ~= "" and not Helpers.IsSecretValue(unitRealm) then
                for i = 2, 5 do
                    local line = tooltip.GetLeftLine and tooltip:GetLeftLine(i)
                        or _G["GameTooltipTextLeft" .. i]
                    if line then
                        local okLT, lt = pcall(line.GetText, line)
                        if okLT and lt and not Helpers.IsSecretValue(lt) then
                            if lt == unitRealm then
                                pcall(line.SetText, line, "")
                                pcall(line.Hide, line)
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    local function HandleUnitClassPost(tooltip, settings, unit)
        TooltipDebugCount("qol.unitClassPost")
        if not settings.classColorName then return end

        local okClass, _, class = pcall(UnitClass, unit)
        if not okClass or not class then return end

        local classColor
        if InCombatLockdown() then
            if C_ClassColor and C_ClassColor.GetClassColor then
                local okColor, color = pcall(C_ClassColor.GetClassColor, class)
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
                    pcall(nameLine.SetTextColor, nameLine, classColor.r, classColor.g, classColor.b)
                end
            end
        end
    end

    local function HandleUnitExtrasPost(tooltip, settings, unit)
        TooltipDebugCount("qol.unitExtrasPost")
        tooltipPlayerItemLevelGUID[tooltip] = nil
        ScheduleDeferredUnitInfo(tooltip, unit)
    end

    local function HandleUnitHealthPost(tooltip, settings)
        TooltipDebugCount("qol.unitHealthPost")
        if InCombatLockdown() then return end

        if settings.hideHealthBar then
            if GameTooltipStatusBar and not (GameTooltipStatusBar.IsForbidden and GameTooltipStatusBar:IsForbidden()) then
                pcall(GameTooltipStatusBar.SetShown, GameTooltipStatusBar, false)
                pcall(GameTooltipStatusBar.SetAlpha, GameTooltipStatusBar, 0)
            end
        end
    end

    -- TAINT SAFETY: Use TooltipDataProcessor instead of hooksecurefunc(GameTooltip, "SetUnit")
    -- to avoid tainting GameTooltip's dispatch tables.
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
        RunTrackedUnitStep("qol.unitClassPost", HandleUnitClassPost, tooltip, settings, unit)
        RunTrackedUnitStep("qol.unitExtrasPost", HandleUnitExtrasPost, tooltip, settings, unit)
    end)

    -- Spell ID tracking (per-tooltip dedupe signature)
    local tooltipSpellIDAdded = setmetatable({}, {__mode = "k"})

    -- TAINT SAFETY: Use a separate watcher frame to detect GameTooltip
    -- hide/clear instead of HookScript("OnHide"/"OnTooltipCleared").
    -- HookScript on GameTooltip permanently taints its dispatch tables.
    local gtSpellIDWatcher = CreateFrame("Frame")
    local gtSpellIDWasShown = false
    local gtVisibilityElapsed = 0
    -- Polled detection latency for "should this tooltip hide now?". Kept tight
    -- so hideDelay=0 reads as instant — total perceived hide latency is bounded
    -- by this interval plus the mouse-focus cache TTL.
    local TOOLTIP_VISIBILITY_CHECK_INTERVAL = 0.05
    gtSpellIDWatcher:SetScript("OnUpdate", function(_, elapsed)
        local shown = GameTooltip:IsShown()
        if shown then
            TooltipDebugCount("qol.visibilityFrame")
        end
        if shown and not gtSpellIDWasShown then
            gtVisibilityElapsed = TOOLTIP_VISIBILITY_CHECK_INTERVAL
            gtTooltipHadUnit = false
            ResetTooltipHideFade()
        end
        if gtSpellIDWasShown and not shown then
            gtVisibilityElapsed = 0
            gtTooltipHadUnit = false
            ResetTooltipHideFade()
            InvalidatePendingSetUnit()
            tooltipSpellIDAdded[GameTooltip] = nil
            tooltipPlayerItemLevelGUID[GameTooltip] = nil
            tooltipUnitInfoState[GameTooltip] = nil
        elseif shown then
            gtVisibilityElapsed = gtVisibilityElapsed + (elapsed or 0)
            if gtVisibilityElapsed >= TOOLTIP_VISIBILITY_CHECK_INTERVAL then
                gtVisibilityElapsed = 0
                TooltipDebugCount("qol.visibilityCheck")
                -- Latch the "had a unit this cycle" flag before evaluating
                -- visibility, so ShouldKeepTooltipVisible can distinguish a
                -- post-mouseoff unit tooltip (hide it) from a true world
                -- object tooltip (keep the WorldFrame safety net).
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

            if tooltipHideFadeState.active then
                tooltipHideFadeState.elapsed = tooltipHideFadeState.elapsed + (elapsed or 0)
                local duration = tooltipHideFadeState.duration
                local progress = (duration > 0) and (tooltipHideFadeState.elapsed / duration) or 1
                if progress >= 1 then
                    ResetTooltipHideFade()
                    GameTooltip:Hide()
                else
                    local nextAlpha = math.max(0, tooltipHideFadeState.startAlpha * (1 - progress))
                    pcall(GameTooltip.SetAlpha, GameTooltip, nextAlpha)
                end
            end
        end
        gtSpellIDWasShown = shown
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
        return settings and settings.enabled and settings.showSpellIDs
    end

    local function ShouldProcessTooltipIDs(tooltip)
        if not ShouldShowTooltipIDs() then
            TooltipDebugCount("qol.idPostSkipped")
            return false
        end
        if not tooltip or tooltip.IsForbidden and tooltip:IsForbidden() then
            TooltipDebugCount("qol.idPostSkipped")
            return false
        end
        if TooltipOwnerSkipsIDInjection(tooltip) then
            TooltipDebugCount("qol.idOwnerSkipped")
            return false
        end
        return true
    end

    local function ResolveSpellIDFromTooltipData(tooltip, data, allowTooltipFallback)
        if data then
            local fromID = data.id
            if type(fromID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromID)) then
                    TooltipDebugCount("qol.spellIDDataHit")
                    return fromID
                end
            end

            local fromSpellID = data.spellID
            if type(fromSpellID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromSpellID)) then
                    TooltipDebugCount("qol.spellIDDataHit")
                    return fromSpellID
                end
            end
        end

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
        if data then
            local fromID = data.id
            if type(fromID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromID)) then
                    TooltipDebugCount("qol.itemIDDataHit")
                    return fromID
                end
            end

            local fromItemID = data.itemID
            if type(fromItemID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromItemID)) then
                    TooltipDebugCount("qol.itemIDDataHit")
                    return fromItemID
                end
            end
        end

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
            local iconOk, result = pcall(C_Spell.GetSpellTexture, spellID)
            if iconOk and result and type(result) == "number" then
                iconID = result
            end
        end

        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("Spell ID:", tostring(spellID), 0.5, 0.8, 1, 1, 1, 1)
        if iconID then
            tooltip:AddDoubleLine("Icon ID:", tostring(iconID), 0.5, 0.8, 1, 1, 1, 1)
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
        tooltip:AddDoubleLine("Item ID:", tostring(itemID), 0.5, 0.8, 1, 1, 1, 1)

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

    local function TryAddAuraSpellIDFromTooltipData(tooltip, data)
        local spellID = ResolveSpellIDFromTooltipData(tooltip, data, true)
        if spellID then
            AddSpellIDToTooltip(tooltip, spellID, data, false)
        end
    end

    local function TryAddItemIDFromTooltipData(tooltip, data)
        local itemID = ResolveItemIDFromTooltipData(tooltip, data, true)
        if itemID then
            AddItemIDToTooltip(tooltip, itemID, data)
        end
    end

    AddTrackedTooltipPostCall(Enum.TooltipDataType.Spell, "qol.spellIDPost", function(tooltip, data)
        TooltipDebugCount("qol.spellPost")
        if InCombatLockdown() then return end
        if not ShouldProcessTooltipIDs(tooltip) then return end
        pcall(TryAddSpellIDFromTooltipData, tooltip, data)
    end)

    local auraTooltipType = Enum.TooltipDataType.UnitAura or Enum.TooltipDataType.Aura
    if auraTooltipType then
        AddTrackedTooltipPostCall(auraTooltipType, "qol.auraIDPost", function(tooltip, data)
            TooltipDebugCount("qol.auraPost")
            if InCombatLockdown() then return end
            if not ShouldProcessTooltipIDs(tooltip) then return end
            pcall(TryAddAuraSpellIDFromTooltipData, tooltip, data)
        end)
    end

    -- TAINT SAFETY: Aura spell ID display now uses TooltipDataProcessor
    -- instead of hooksecurefunc(GameTooltip, auraMethod). The Aura
    -- TooltipDataProcessor callback above already handles spell IDs for
    -- aura tooltips. The per-method hooks were redundant and tainted
    -- GameTooltip's dispatch tables.

    -- TAINT SAFETY: Suppress tooltips that bypass GameTooltip_SetDefaultAnchor.
    -- Uses TooltipDataProcessor instead of hooksecurefunc(GameTooltip, "SetSpellByID"/"SetItemByID")
    -- to avoid tainting GameTooltip's dispatch tables.
    AddTrackedTooltipPostCall(Enum.TooltipDataType.Spell, "qol.spellVisibilityPost", function(tooltip)
        TooltipDebugCount("qol.spellVisibilityPost")
        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end
        InvalidatePendingSetUnit()
        if ShouldHideOwnedTooltip(tooltip, "abilities") then
            tooltip:Hide()
        end
    end)

    AddTrackedTooltipPostCall(Enum.TooltipDataType.Item, "qol.itemPost", function(tooltip, data)
        TooltipDebugCount("qol.itemPost")
        if not InCombatLockdown() then
            if ShouldProcessTooltipIDs(tooltip) then
                pcall(TryAddItemIDFromTooltipData, tooltip, data)
            end
        end

        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end
        InvalidatePendingSetUnit()
        if ShouldHideOwnedTooltip(tooltip, "items") then
            tooltip:Hide()
        end
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
            if not unitGUID or Helpers.IsSecretValue(unitGUID) or Helpers.IsSecretValue(guid) then
                return
            end
            if Helpers.SafeCompare(unitGUID, guid) ~= true then return end

            AddPlayerItemLevelToTooltip(GameTooltip, unit, false)
        end)
    end

end

---------------------------------------------------------------------------
-- Modifier / Combat Event Handlers
---------------------------------------------------------------------------
local function OnUnitTargetChanged(changedUnit)
    if not GameTooltip:IsShown() then return end
    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit or unit ~= changedUnit then return end

    -- Tooltip is showing this unit and their target changed
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not IsSettingEnabled(settings, "showTooltipTarget", true) then return end

    local state = tooltipUnitInfoState[GameTooltip]
    if not state then return end

    -- Re-resolve target on next pass; AddTooltipTargetInfo dedupes by name,
    -- so a re-run only appends a new line when the target actually changed.
    RefreshTooltipLayout(GameTooltip)
end

local function OnUnitAuraChanged(changedUnit)
    if not GameTooltip:IsShown() then return end
    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit or unit ~= changedUnit then return end

    local guid = UnitGUID(unit)
    if guid and not Helpers.IsSecretValue(guid) then
        ClearCachedMountName(guid)
    end

    -- Tooltip is showing this unit and their auras changed (mount status)
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not IsSettingEnabled(settings, "showPlayerMount", true) then return end

    local state = tooltipUnitInfoState[GameTooltip]
    if not state then return end

    -- Mark mount as needing re-resolve. AddTooltipMountInfo dedupes by name
    -- (state.lastMountName), so a re-scan only appends a new line when the
    -- mount actually changed — aura ticks no longer stack duplicate lines.
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

---------------------------------------------------------------------------
-- ENGINE CONTRACT
---------------------------------------------------------------------------

function TooltipEngine:Initialize()
    Provider = ns.TooltipProvider
    TooltipInspect = ns.TooltipInspect

    SetupTooltipHook()

    -- Event handlers (UNIT_AURA handled by centralized dispatcher)
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

    -- Subscribe to centralized aura dispatcher (all units — tooltip needs any unit)
    if ns.AuraEvents then
        ns.AuraEvents:Subscribe("all", function(unit, updateInfo)
            OnUnitAuraChanged(unit)
        end)
    end
end

function TooltipEngine:Refresh()
    -- Settings apply on next tooltip show
end

function TooltipEngine:SetEnabled(enabled)
    -- Hooks are permanent once installed
end

---------------------------------------------------------------------------
-- REGISTER WITH PROVIDER
---------------------------------------------------------------------------
ns.TooltipProvider:RegisterEngine("default", TooltipEngine)
