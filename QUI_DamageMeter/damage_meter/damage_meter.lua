-- luacheck: globals CreateFrame C_DamageMeter C_DeathRecap UIParent RAID_CLASS_COLORS CLASS_ICON_TCOORDS _G SetCVar InCombatLockdown C_StringUtil GetTime Enum MenuUtil GameTooltip SlashCmdList GetTimePreciseSec C_Spell C_Timer AbbreviateNumbers BreakUpLargeNumbers CreateAbbreviateConfig Ambiguate UnitGUID OpenDeathRecapUI UnitAffectingCombat IsInGroup IsInRaid GetNumGroupMembers
local _, ns = ...

local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local QUI_DamageMeter = {}
ns.QUI_DamageMeter = QUI_DamageMeter

local Perf = {
    enabled  = false,
    _samples = { data = {}, window = {}, breakdown = {} },
}
QUI_DamageMeter.Perf = Perf

local PERF_BUFFER_SIZE = 200

function Perf:Record(kind, dt)
    local buf = self._samples[kind]
    if not buf then return end
    buf[#buf + 1] = dt
    if #buf > PERF_BUFFER_SIZE then table.remove(buf, 1) end
end

local function PerfStat(samples)
    if #samples == 0 then return 0, 0, 0 end
    local sum, mx = 0, 0
    local sorted = {}
    for i, v in ipairs(samples) do
        sorted[i] = v
        sum = sum + v
        if v > mx then mx = v end
    end
    table.sort(sorted)
    local p95Idx = math.max(1, math.ceil(#sorted * 0.95))
    return sum / #samples, sorted[p95Idx], mx
end

function Perf:Summary()
    local lines = {}
    for _, kind in ipairs({ "data", "window", "breakdown" }) do
        local samples = self._samples[kind] or {}
        local avg, p95, mx = PerfStat(samples)
        table.insert(lines, string.format("  %-9s n=%-3d avg=%.3fms p95=%.3fms max=%.3fms",
            kind, #samples, avg * 1000, p95 * 1000, mx * 1000))
    end
    return lines
end

function Perf:Reset()
    for k in pairs(self._samples) do self._samples[k] = {} end
end

local function PerfNow()
    if GetTimePreciseSec then return GetTimePreciseSec() end
    return 0
end

local function GetSettings()
    local QUI = _G.QUI
    if not (QUI and QUI.db and QUI.db.profile and QUI.db.profile.damageMeter) then
        return nil
    end
    return QUI.db.profile.damageMeter.native
end

local function ShortenName(name)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(name) then
        return name -- @secret-policy: sink-passthrough
    end
    if name == nil then return nil end
    local s = GetSettings()
    if s and s.shortenNames and Ambiguate then
        local short = Ambiguate(name, "short")
        if short ~= nil then return short end
        return name
    end
    return name
end
QUI_DamageMeter.ShortenName = ShortenName

local function SortByDescSafe(list, keyFn, isSecret)
    if isSecret then
        for i = 1, #list do
            if isSecret(keyFn(list[i])) then return end
        end
    end
    table.sort(list, function(a, b)
        return (keyFn(a) or 0) > (keyFn(b) or 0)
    end)
end
QUI_DamageMeter.SortByDescSafe = SortByDescSafe

local function SafeNumOrZero(v, isSecret)
    if isSecret and isSecret(v) then return 0 end -- @secret-policy: zero-degrade
    if v == nil then return 0 end
    return v
end

local function RankAndMaxAmount(list, isSecret)
    local maxAmount = 0
    for i, s in ipairs(list) do
        s.rank = i
        local v = s.totalAmount
        local vSecret = isSecret and isSecret(v)
        if not vSecret and v ~= nil and v > maxAmount then maxAmount = v end
    end
    return maxAmount
end

local Data = {}
QUI_DamageMeter.Data = Data

Data._dirty = {}
Data._allDirty = false
Data._inCombat = false
Data._clearRuntimeSessions = false
Data._sourceGUIDBySelector = {}

local HasCachedViewKey

local function MarkDirtyKey(selectorKey, damageMeterType)
    local bySelector = Data._dirty[selectorKey]
    if not bySelector then
        bySelector = {}
        Data._dirty[selectorKey] = bySelector
    end
    bySelector[damageMeterType] = true
    Data:WakeTicker()
end

local function MarkDirty(sessionType, damageMeterType)
    MarkDirtyKey(QUI_DamageMeter.SessionKey(sessionType, nil), damageMeterType)
end

local function MarkAllDirty()
    Data._allDirty = true
    Data:WakeTicker()
end

local function MarkCurrentDirty()
    local key = QUI_DamageMeter.SessionKey(1, nil)
    local bySelector = Data._cache[key]
    if not bySelector then return end
    for damageMeterType in pairs(bySelector) do
        MarkDirtyKey(key, damageMeterType)
    end
end

Data._combatStartTime = nil
Data._combatEndTime   = nil
Data._combatFrozen    = 0
Data._currentDurPin   = 0
Data._inEncounter     = false

local PARTY_UNITS = {}
local RAID_UNITS = {}
local GROUP_UNIT_TOKENS = { player = true }
for i = 1, 4 do
    local unit = "party" .. i
    PARTY_UNITS[i] = unit
    GROUP_UNIT_TOKENS[unit] = true
end
for i = 1, 40 do
    local unit = "raid" .. i
    RAID_UNITS[i] = unit
    GROUP_UNIT_TOKENS[unit] = true
end

local function IsGroupInCombat()
    if not UnitAffectingCombat then return Data._inCombat end
    if UnitAffectingCombat("player") then return true end
    if not (IsInGroup and IsInGroup()) then return false end
    local inRaid = IsInRaid and IsInRaid() or false
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if not inRaid then count = math.max(0, count - 1) end
    local units = inRaid and RAID_UNITS or PARTY_UNITS
    count = math.min(count, #units)
    for i = 1, count do
        if UnitAffectingCombat(units[i]) then return true end
    end
    return false
end
QUI_DamageMeter.IsGroupInCombat = IsGroupInCombat

local function GetCombatElapsed()
    if Data._combatStartTime then
        if Data._combatEndTime and Data._combatEndTime > Data._combatStartTime then
            return Data._combatFrozen
        end
        return GetTime() - Data._combatStartTime
    end
    return 0
end
Data.GetCombatElapsed = GetCombatElapsed

function Data:ResetCombatClock()
    if self._inCombat then
        self._combatStartTime = GetTime()
        self._combatEndTime   = nil
    else
        self._combatStartTime = nil
        self._combatEndTime   = nil
    end
    self._combatFrozen = 0
    self._currentDurPin = 0
end

function Data:BeginCombat(resetClock)
    local wasInCombat = self._inCombat
    if not wasInCombat then self:ClearLiveSourceGUIDCache() end
    self._inCombat = true
    if resetClock or not wasInCombat or not self._combatStartTime then
        self._combatStartTime = GetTime()
        self._combatEndTime   = nil
        self._combatFrozen    = 0
        self._currentDurPin   = 0
    end
    self:WakeTicker()
    if (not wasInCombat or resetClock) and self._onCombatStart then
        self:_onCombatStart()
    end
    if self._onChange then self:_onChange() end
end

function Data:EndCombat()
    if not self._inCombat then return end
    self._inCombat = false
    self._combatEndTime = GetTime()
    self._combatFrozen = (self._combatStartTime and (self._combatEndTime - self._combatStartTime)) or 0
    if C_Timer and C_Timer.After then C_Timer.After(0.5, MarkAllDirty) end
    if self._onChange then self:_onChange() end
end

local groupCombatScanQueued = false

local function RefreshGroupCombatState()
    groupCombatScanQueued = false
    local groupInCombat = IsGroupInCombat()
    if groupInCombat and not Data._inCombat then
        Data:BeginCombat(false)
    elseif not groupInCombat and Data._inCombat and not Data._inEncounter then
        Data:EndCombat()
    end
end

local function QueueGroupCombatScan()
    if groupCombatScanQueued then return end
    groupCombatScanQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshGroupCombatState)
    else
        RefreshGroupCombatState()
    end
end

local function ResolveCurrentViewDuration(inCombat, apiDuration, pinnedDuration, combatElapsed, isSecret)
    local function usable(d)
        if isSecret and isSecret(d) then return false end
        return type(d) == "number" and d > 0
    end
    if inCombat then
        if usable(apiDuration) then return apiDuration, apiDuration end
        if usable(pinnedDuration) then return pinnedDuration, pinnedDuration end
        if usable(combatElapsed) then return combatElapsed, pinnedDuration end
        return nil, pinnedDuration
    end
    if usable(pinnedDuration) then return pinnedDuration, pinnedDuration end
    if usable(apiDuration) then return apiDuration, pinnedDuration end
    if usable(combatElapsed) then return combatElapsed, pinnedDuration end
    return nil, pinnedDuration
end
QUI_DamageMeter.ResolveCurrentViewDuration = ResolveCurrentViewDuration

Data._eventFrame = CreateFrame("Frame")
Data._eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
Data._eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
Data._eventFrame:RegisterEvent("DAMAGE_METER_RESET")
Data._eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Data._eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
Data._eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
Data._eventFrame:RegisterEvent("UNIT_FLAGS")
Data._eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
Data._eventFrame:RegisterEvent("ENCOUNTER_START")
Data._eventFrame:RegisterEvent("ENCOUNTER_END")
Data._eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        for sessionType = 0, 2 do
            MarkDirty(sessionType, arg1)
        end
        local sessionID = arg2
        if sessionID ~= nil then
            local key = QUI_DamageMeter.SessionKey(nil, sessionID)
            if HasCachedViewKey(key, arg1) then
                MarkDirtyKey(key, arg1)
            end
        end
    elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        MarkCurrentDirty()
    elseif event == "DAMAGE_METER_RESET" then
        Data._clearRuntimeSessions = true
        Data:ResetCombatClock()
        Data:ClearSourceGUIDCache()
        MarkAllDirty()
    elseif event == "ENCOUNTER_START" then
        Data._inEncounter = true
        Data:BeginCombat(true)
    elseif event == "ENCOUNTER_END" then
        Data._inEncounter = false
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, RefreshGroupCombatState)
        else
            RefreshGroupCombatState()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Data:BeginCombat(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not Data._inEncounter and not IsGroupInCombat() then
            Data:EndCombat()
        end
    elseif event == "UNIT_FLAGS" then
        if not GROUP_UNIT_TOKENS[arg1] then return end
        QueueGroupCombatScan()
    elseif event == "GROUP_ROSTER_UPDATE" then
        Data:ClearSourceGUIDCache()
        QueueGroupCombatScan()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Data:ClearSourceGUIDCache()
        if IsGroupInCombat() then
            Data:BeginCombat(false)
        else
            Data:EndCombat()
            MarkAllDirty()
        end
    end
end)

Data._tickAccum = 0
Data._cadenceCombat = 0.5
Data._cadenceIdle = 2.0

function Data:RefreshCadence()
    local s = GetSettings()
    self._cadenceCombat = (s and s.refreshRateCombat) or 0.5
    self._cadenceIdle   = (s and s.refreshRateIdle)   or 2.0
end

Data._ticker = CreateFrame("Frame")
Data._ticker:SetScript("OnUpdate", function(_, elapsed)
    Data._tickAccum = Data._tickAccum + elapsed
    local cadence = Data._inCombat and Data._cadenceCombat or Data._cadenceIdle
    if Data._tickAccum < cadence then return end
    Data._tickAccum = 0
    Data:RefreshCadence()
    Data:Refresh()
    if not Data._inCombat and not Data._allDirty and not next(Data._dirty) then
        Data._ticker:Hide()
    end
end)

function Data:WakeTicker()
    local ticker = self._ticker
    if ticker and not ticker:IsShown() then
        self._tickAccum = 0
        self:RefreshCadence()
        ticker:Show()
    end
end

local function NormalizeSources(rawSources)
    local view = {}
    for i, src in ipairs(rawSources) do
        view[i] = {
            rank             = i,
            name             = src.name,
            classFilename    = src.classFilename,
            specIconID       = src.specIconID,
            totalAmount      = src.totalAmount,
            amountPerSecond  = src.amountPerSecond,
            isLocalPlayer    = src.isLocalPlayer or false,
            sourceGUID       = src.sourceGUID,
            sourceCreatureID = src.sourceCreatureID,
            deathRecapID     = src.deathRecapID,
        }
    end
    return view
end
Data._NormalizeSources = NormalizeSources

Data._cache = {}
Data._combinedHealingViews = {}
Data._generation = 0

local function SessionKey(sessionType, sessionID)
    if sessionID ~= nil then
        return "id:" .. tostring(sessionID)
    end
    return "type:" .. tostring(sessionType)
end
QUI_DamageMeter.SessionKey = SessionKey

local function IsSecretValue(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

function Data:ClearSourceGUIDCache()
    self._sourceGUIDBySelector = {}
end

function Data:ClearLiveSourceGUIDCache()
    for selectorKey in pairs(self._sourceGUIDBySelector) do
        if type(selectorKey) == "string" and selectorKey:match("^type:") then
            self._sourceGUIDBySelector[selectorKey] = nil
        end
    end
end

function Data:_CacheSourceGUIDs(selectorKey, sources)
    if self._inCombat then return end
    local bySpec = self._sourceGUIDBySelector[selectorKey]
    if not bySpec then
        bySpec = {}
        self._sourceGUIDBySelector[selectorKey] = bySpec
    end
    for _, source in ipairs(sources or {}) do
        local specIconID = source.specIconID
        local sourceGUID = source.sourceGUID
        if type(specIconID) == "number" and specIconID > 0
            and not IsSecretValue(sourceGUID) and type(sourceGUID) == "string"
            and sourceGUID:match("^Player%-") then
            local cached = bySpec[specIconID]
            if cached == nil then
                bySpec[specIconID] = sourceGUID
            elseif cached ~= sourceGUID then
                bySpec[specIconID] = false
            end
        end
    end
end

function Data:ResolveSourceSelector(source, sessionType, sessionID, inCombat)
    if type(source) ~= "table" then return nil, nil, "missing" end

    local sourceGUID = source.sourceGUID
    if not IsSecretValue(sourceGUID) and type(sourceGUID) == "string" and sourceGUID ~= "" then
        return sourceGUID, nil, "direct"
    end

    local sourceCreatureID = source.sourceCreatureID
    if not IsSecretValue(sourceCreatureID) and type(sourceCreatureID) == "number" then
        return nil, sourceCreatureID, "direct"
    end

    if inCombat then
        local specIconID = source.specIconID
        if not IsSecretValue(specIconID) and type(specIconID) == "number" and specIconID > 0 then
            local bySpec = self._sourceGUIDBySelector[SessionKey(sessionType, sessionID)]
            local cachedGUID = bySpec and bySpec[specIconID]
            if type(cachedGUID) == "string" then
                return cachedGUID, nil, "cache"
            end
        end
    end

    local isLocalPlayer = source.isLocalPlayer
    if not IsSecretValue(isLocalPlayer) and isLocalPlayer == true and UnitGUID then
        local playerGUID = Helpers.SafeValue(UnitGUID("player"), nil)
        if type(playerGUID) == "string" and playerGUID ~= "" then
            return playerGUID, nil, "local"
        end
    end

    return nil, nil, "restricted"
end

local function TableOrEmpty(v)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v) then
        return {} -- @secret-policy: empty-table-degrade
    end
    if type(v) ~= "table" then return {} end
    return v
end

local function AmountOrDefault(v, dflt)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v) then
        return v
    end
    if v == nil then return dflt end
    return v
end

local function NewView(sources, duration, maxAmount, totalAmount)
    Data._generation = Data._generation + 1
    return {
        duration    = AmountOrDefault(duration, 0),
        maxAmount   = AmountOrDefault(maxAmount, 0),
        totalAmount = AmountOrDefault(totalAmount, 0),
        sources     = TableOrEmpty(sources),
        generation  = Data._generation,
    }
end

local function CacheView(sessionType, sessionID, damageMeterType, view)
    local key = SessionKey(sessionType, sessionID)
    local bySelector = Data._cache[key]
    if not bySelector then
        bySelector = {}
        Data._cache[key] = bySelector
    end
    bySelector[damageMeterType] = view
end

local function GetCachedView(sessionType, sessionID, damageMeterType)
    local bySelector = Data._cache[SessionKey(sessionType, sessionID)]
    return bySelector and bySelector[damageMeterType] or nil
end

HasCachedViewKey = function(selectorKey, damageMeterType)
    local bySelector = Data._cache[selectorKey]
    return bySelector and bySelector[damageMeterType] ~= nil
end

local function FetchView(sessionType, damageMeterType, sessionID)
    if not C_DamageMeter then
        return NewView({}, 0, 0, 0)
    end

    local ok, session
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionFromID then
            return NewView({}, 0, 0, 0)
        end
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, damageMeterType)
    else
        if not C_DamageMeter.GetCombatSessionFromType then
            return NewView({}, 0, 0, 0)
        end
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, damageMeterType)
    end
    if not ok then
        return NewView({}, 0, 0, 0)
    end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(session) then
        return NewView({}, 0, 0, 0) -- @secret-policy: empty-view-degrade
    end
    if type(session) ~= "table" then
        return NewView({}, 0, 0, 0)
    end

    local sources = NormalizeSources(TableOrEmpty(session.combatSources))
    if not Data._inCombat then
        Data:_CacheSourceGUIDs(SessionKey(sessionType, sessionID), sources)
    end

    local S = Enum and Enum.DamageMeterSessionType
    local duration
    if sessionID ~= nil then
        duration = session.durationSeconds
    elseif sessionType == ((S and S.Expired) or 2) then
        duration = session.durationSeconds
    elseif sessionType == ((S and S.Current) or 1) then
        local IsSecret = Helpers and Helpers.IsSecretValue
        local apiDuration = C_DamageMeter.GetSessionDurationSeconds
            and C_DamageMeter.GetSessionDurationSeconds(sessionType)
        local dur, newPin = ResolveCurrentViewDuration(
            Data._inCombat and true or false, apiDuration,
            Data._currentDurPin, GetCombatElapsed(), IsSecret)
        Data._currentDurPin = newPin or 0
        duration = dur or 0
    else
        duration = GetCombatElapsed()
    end

    return NewView(sources, duration, session.maxAmount, session.totalAmount)
end

function Data:Refresh()
    local _t0 = Perf.enabled and PerfNow() or 0
    if self._allDirty then
        self._allDirty = false
        self:ClearCachedViews()
        if self._onChange then self:_onChange() end
        if Perf.enabled then Perf:Record("data", PerfNow() - _t0) end
        return
    end
    local anyChanged = false
    for selectorKey, byType in pairs(self._dirty) do
        local sessionType, sessionID
        local idText = selectorKey:match("^id:(.+)$")
        if idText then
            sessionID = tonumber(idText)
        else
            sessionType = tonumber(selectorKey:match("^type:(.+)$"))
        end
        for damageMeterType in pairs(byType) do
            CacheView(sessionType, sessionID, damageMeterType,
                FetchView(sessionType, damageMeterType, sessionID))
            anyChanged = true
        end
    end
    self._dirty = {}
    if anyChanged and self._onChange then self:_onChange() end
    if Perf.enabled then Perf:Record("data", PerfNow() - _t0) end
end

function Data:GetView(sessionType, damageMeterType, sessionID)
    local view = GetCachedView(sessionType, sessionID, damageMeterType)
    if view then return view end
    view = FetchView(sessionType, damageMeterType, sessionID)
    CacheView(sessionType, sessionID, damageMeterType, view)
    return view
end

function Data:ClearCachedViews()
    self._cache = {}
    self._combinedHealingViews = {}
    self._dirty = {}
end

local _spellInfoCache = {}

local function IsIndexableSpellID(spellID)
    if IsSecretValue(spellID) then return false end -- @secret-policy: reject-secret-ids
    return spellID ~= nil
end

local function ResolveSpellInfo(spellID)
    if not IsIndexableSpellID(spellID) then return nil end
    local cached = _spellInfoCache[spellID]
    if cached then return cached end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    if info then _spellInfoCache[spellID] = info end
    return info
end

local function NormalizeSpells(rawSpells, out, limit)
    out = out or {}
    local n = 0
    for i = 1, #rawSpells do
        local spell = rawSpells[i]
        if IsSecretValue(spell) then
            -- @secret-policy: reject-secret-value — an opaque entry carries
            spell = nil
        end
        if spell ~= nil then
            n = n + 1
            local info = ResolveSpellInfo(spell.spellID)
            local name = info and info.name
            if not IsSecretValue(name) and name == nil then
                name = spell.creatureName
            end
            local normalized = out[n] or {}
            normalized.rank = n
            normalized.spellID = spell.spellID
            normalized.name = name
            normalized.iconID = info and info.iconID
            normalized.totalAmount = spell.totalAmount
            normalized.amountPerSecond = spell.amountPerSecond
            normalized.hitCount = spell.hitCount
            normalized.critCount = spell.critCount
            normalized.criticalAmount = spell.criticalAmount
            out[n] = normalized
            if type(limit) == "number" and n >= limit then break end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end
Data._NormalizeSpells = NormalizeSpells

local function ResetBreakdownView(view)
    view = view or {}
    view.spells = NormalizeSpells({}, view.spells)
    view.maxAmount = 0
    view.totalAmount = 0
    return view
end

function Data:GetBreakdownView(sessionType, damageMeterType, sourceGUID, sourceCreatureID,
    sessionID, reuse, limit)
    if not C_DamageMeter then
        return ResetBreakdownView(reuse)
    end
    local ok, src
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then
            return ResetBreakdownView(reuse)
        end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, damageMeterType, sourceGUID, sourceCreatureID)
    else
        if not C_DamageMeter.GetCombatSessionSourceFromType then
            return ResetBreakdownView(reuse)
        end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            sessionType, damageMeterType, sourceGUID, sourceCreatureID)
    end
    if not ok then
        return ResetBreakdownView(reuse)
    end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(src) then
        return ResetBreakdownView(reuse) -- @secret-policy: empty-table-degrade
    end
    if type(src) ~= "table" then
        return ResetBreakdownView(reuse)
    end
    local view = reuse or {}
    view.spells = NormalizeSpells(TableOrEmpty(src.combatSpells), view.spells, limit)
    view.maxAmount = AmountOrDefault(src.maxAmount, 0)
    view.totalAmount = AmountOrDefault(src.totalAmount, 0)
    return view
end

local function AggregateSpellsByUnit(combatSpells, isSecret)
    local byName, list = {}, {}
    for _, spell in ipairs(combatSpells or {}) do
        if isSecret and isSecret(spell) then spell = nil end -- @secret-policy: reject-secret-value
        local det  = spell and spell.combatSpellDetails
        if isSecret and isSecret(det) then det = nil end -- @secret-policy: reject-secret-value
        local name = det and det.unitName
        local amt  = spell and spell.totalAmount
        local perSecond = spell and spell.amountPerSecond
        local nameSecret = isSecret and isSecret(name)
        local amtSecret  = isSecret and isSecret(amt)
        local perSecondSecret = isSecret and isSecret(perSecond)
        local nameOk = not nameSecret and name ~= nil
        local amtOk  = not amtSecret and amt ~= nil
        if nameOk and amtOk then
            local e = byName[name]
            if not e then
                e = { name = name, classFilename = det.unitClassFilename,
                      specIconID = det.specIconID, totalAmount = 0, amountPerSecond = 0 }
                byName[name] = e
                list[#list + 1] = e
            end
            e.totalAmount = e.totalAmount + amt
            if not perSecondSecret and type(perSecond) == "number" then
                e.amountPerSecond = e.amountPerSecond + perSecond
            end
        end
    end
    table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
    return list
end
Data._AggregateSpellsByUnit = AggregateSpellsByUnit

local function PivotPlayerTargets(perEnemy)
    local map = {}
    for _, e in ipairs(perEnemy or {}) do
        for _, p in ipairs(e.players or {}) do
            local bucket = map[p.name]
            if not bucket then bucket = {}; map[p.name] = bucket end
            bucket[#bucket + 1] = {
                name = e.enemyName,
                sourceGUID = e.sourceGUID,
                sourceCreatureID = e.sourceCreatureID,
                totalAmount = p.totalAmount,
                amountPerSecond = p.amountPerSecond,
            }
        end
    end
    for _, list in pairs(map) do
        table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
    end
    return map
end
Data._PivotPlayerTargets = PivotPlayerTargets

local function FetchSourceSpells(sessionType, meterType, sourceGUID, sourceCreatureID, sessionID)
    if not C_DamageMeter then return {} end
    local ok, src
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then return {} end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, meterType, sourceGUID, sourceCreatureID)
    else
        if not C_DamageMeter.GetCombatSessionSourceFromType then return {} end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            sessionType, meterType, sourceGUID, sourceCreatureID)
    end
    if not ok then return {} end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(src) then
        return {} -- @secret-policy: empty-table-degrade
    end
    if type(src) ~= "table" then return {} end
    return TableOrEmpty(src.combatSpells)
end

local function FilterSpellsByUnit(combatSpells, unitName, isSecret)
    local filtered = {}
    if unitName == nil or (isSecret and isSecret(unitName)) then return filtered end
    for _, spell in ipairs(combatSpells or {}) do
        if isSecret and isSecret(spell) then spell = nil end
        local details = spell and spell.combatSpellDetails
        if isSecret and isSecret(details) then details = nil end
        local name = details and details.unitName
        if name ~= nil and not (isSecret and isSecret(name)) and name == unitName then
            filtered[#filtered + 1] = spell
        end
    end
    return filtered
end
Data._FilterSpellsByUnit = FilterSpellsByUnit

local function EnemyDamageTakenType()
    local T = Enum and Enum.DamageMeterType
    return T and T.EnemyDamageTaken
end

function Data:GetEnemyAttackers(sessionType, sourceGUID, sourceCreatureID, sessionID)
    local eType = EnemyDamageTakenType()
    if not eType then return {} end
    local IsSecret = Helpers and Helpers.IsSecretValue
    return AggregateSpellsByUnit(
        FetchSourceSpells(sessionType, eType, sourceGUID, sourceCreatureID, sessionID), IsSecret)
end

function Data:GetPlayerTargetsMap(sessionType, sessionID)
    local eType = EnemyDamageTakenType()
    if not eType then return {} end
    local enemyView = self:GetView(sessionType, eType, sessionID)
    local genKey = SessionKey(sessionType, sessionID) .. ":" .. tostring(enemyView.generation or 0)
    if self._targetsCacheKey == genKey and self._targetsCache then
        return self._targetsCache
    end
    local IsSecret = Helpers and Helpers.IsSecretValue
    local perEnemy = {}
    for _, enemy in ipairs(enemyView.sources or {}) do
        perEnemy[#perEnemy + 1] = {
            enemyName = enemy.name,
            sourceGUID = enemy.sourceGUID,
            sourceCreatureID = enemy.sourceCreatureID,
            players   = AggregateSpellsByUnit(
                FetchSourceSpells(sessionType, eType, enemy.sourceGUID, enemy.sourceCreatureID, sessionID),
                IsSecret),
        }
    end
    local map = PivotPlayerTargets(perEnemy)
    self._targetsCacheKey = genKey
    self._targetsCache    = map
    return map
end

function Data:GetPlayerTargets(sessionType, playerName, sessionID)
    local IsSecret = Helpers and Helpers.IsSecretValue
    if IsSecret and IsSecret(playerName) then return {} end -- @secret-policy: empty-table-degrade
    if playerName == nil then return {} end
    return self:GetPlayerTargetsMap(sessionType, sessionID)[playerName] or {}
end

function Data:GetPlayerTargetBreakdown(sessionType, playerName, targetGUID, targetCreatureID,
    sessionID, reuse, limit)
    local eType = EnemyDamageTakenType()
    if not eType then return ResetBreakdownView(reuse) end
    local isSecret = Helpers and Helpers.IsSecretValue
    if playerName == nil or (isSecret and isSecret(playerName)) then
        return ResetBreakdownView(reuse)
    end
    if isSecret and isSecret(targetGUID) then targetGUID = nil end
    if isSecret and isSecret(targetCreatureID) then targetCreatureID = nil end
    if targetGUID == nil and targetCreatureID == nil then return ResetBreakdownView(reuse) end
    local rawSpells = FetchSourceSpells(
        sessionType, eType, targetGUID, targetCreatureID, sessionID)
    local view = reuse or {}
    view.spells = NormalizeSpells(
        FilterSpellsByUnit(rawSpells, playerName, isSecret), view.spells, limit)
    view.maxAmount = 0
    view.totalAmount = 0
    for _, spell in ipairs(view.spells) do
        local amount = spell.totalAmount
        if not (isSecret and isSecret(amount)) and type(amount) == "number" then
            view.totalAmount = view.totalAmount + amount
            view.maxAmount = math.max(view.maxAmount, amount)
        end
    end
    return view
end

function Data:GetCombinedHealingView(sessionType, sessionID)
    local T = Enum and Enum.DamageMeterType
    local hType = T and T.HealingDone
    local aType = T and T.Absorbs
    if not (hType and aType) then
        return self:GetView(sessionType, hType or 2, sessionID)
    end
    local hView = self:GetView(sessionType, hType, sessionID)
    local aView = self:GetView(sessionType, aType, sessionID)
    if not (aView and aView.sources and #aView.sources > 0) then
        return hView
    end

    local selectorKey = SessionKey(sessionType, sessionID)
    local cached = self._combinedHealingViews[selectorKey]
    if cached and cached.healingGeneration == hView.generation
        and cached.absorbGeneration == aView.generation then
        return cached.view
    end

    local IsSecret = Helpers and Helpers.IsSecretValue
    local merged, byGuid = {}, {}
    local function isIndexableKey(v)
        if IsSecret and IsSecret(v) then return false end -- @secret-policy: reject-secret-ids
        return v ~= nil
    end
    for i, s in ipairs(hView.sources or {}) do
        local copy = {}
        for k, v in pairs(s) do copy[k] = v end
        merged[i] = copy
        if isIndexableKey(s.sourceGUID) then byGuid[s.sourceGUID] = copy end
    end
    for _, a in ipairs(aView.sources) do
        local existing = isIndexableKey(a.sourceGUID) and byGuid[a.sourceGUID]
        if existing then
            local totSecret = IsSecret and (IsSecret(existing.totalAmount) or IsSecret(a.totalAmount))
            if not totSecret and existing.totalAmount ~= nil and a.totalAmount ~= nil then
                existing.totalAmount = existing.totalAmount + a.totalAmount
            end
            local psSecret = IsSecret and (IsSecret(existing.amountPerSecond) or IsSecret(a.amountPerSecond))
            if not psSecret and existing.amountPerSecond ~= nil and a.amountPerSecond ~= nil then
                existing.amountPerSecond = existing.amountPerSecond + a.amountPerSecond
            end
        else
            local copy = {}
            for k, v in pairs(a) do copy[k] = v end
            table.insert(merged, copy)
            if isIndexableKey(a.sourceGUID) then byGuid[a.sourceGUID] = copy end
        end
    end
    SortByDescSafe(merged, function(s) return s.totalAmount end, IsSecret)
    local maxAmount = RankAndMaxAmount(merged, IsSecret)
    local view = {
        duration    = hView.duration,
        maxAmount   = maxAmount,
        totalAmount = SafeNumOrZero(hView.totalAmount, IsSecret) + SafeNumOrZero(aView.totalAmount, IsSecret),
        sources     = merged,
        generation  = math.max(hView.generation or 0, aView.generation or 0),
    }
    self._combinedHealingViews[selectorKey] = {
        healingGeneration = hView.generation,
        absorbGeneration = aView.generation,
        view = view,
    }
    return view
end

function Data:GetCombinedHealingBreakdown(sessionType, sourceGUID, sourceCreatureID, sessionID, reuse, limit)
    local T = Enum and Enum.DamageMeterType
    local hType = T and T.HealingDone
    local aType = T and T.Absorbs
    if not (hType and aType) then
        return self:GetBreakdownView(sessionType, hType or 2,
            sourceGUID, sourceCreatureID, sessionID, reuse, limit)
    end
    reuse = reuse or {}
    local hView = self:GetBreakdownView(sessionType, hType,
        sourceGUID, sourceCreatureID, sessionID, reuse._healing)
    local aView = self:GetBreakdownView(sessionType, aType,
        sourceGUID, sourceCreatureID, sessionID, reuse._absorbs)
    reuse._healing = hView
    reuse._absorbs = aView
    local IsSecret = Helpers and Helpers.IsSecretValue
    local merged = reuse._mergedSpells or {}
    local bySpell = reuse._bySpell or {}
    for key in pairs(bySpell) do bySpell[key] = nil end
    local count = 0
    for _, sp in ipairs(hView.spells or {}) do
        count = count + 1
        local copy = merged[count] or {}
        for key in pairs(copy) do copy[key] = nil end
        for k, v in pairs(sp) do copy[k] = v end
        merged[count] = copy
        if IsIndexableSpellID(sp.spellID) then bySpell[sp.spellID] = copy end
    end
    for _, sp in ipairs(aView.spells or {}) do
        local existing = IsIndexableSpellID(sp.spellID) and bySpell[sp.spellID] or nil
        if existing then
            local totSecret = IsSecret and (IsSecret(existing.totalAmount) or IsSecret(sp.totalAmount))
            if not totSecret and existing.totalAmount ~= nil and sp.totalAmount ~= nil then
                existing.totalAmount = existing.totalAmount + sp.totalAmount
            end
        else
            count = count + 1
            local copy = merged[count] or {}
            for key in pairs(copy) do copy[key] = nil end
            for k, v in pairs(sp) do copy[k] = v end
            merged[count] = copy
            if IsIndexableSpellID(sp.spellID) then bySpell[sp.spellID] = copy end
        end
    end
    for i = #merged, count + 1, -1 do merged[i] = nil end
    SortByDescSafe(merged, function(s) return s.totalAmount end, IsSecret)
    local maxAmount = RankAndMaxAmount(merged, IsSecret)
    local spells = reuse.spells or {}
    local visibleCount = math.min(#merged, type(limit) == "number" and limit or #merged)
    for i = 1, visibleCount do spells[i] = merged[i] end
    for i = #spells, visibleCount + 1, -1 do spells[i] = nil end
    reuse._mergedSpells = merged
    reuse.spells = spells
    reuse._bySpell = bySpell
    reuse.maxAmount = maxAmount
    reuse.totalAmount = SafeNumOrZero(hView.totalAmount, IsSecret)
        + SafeNumOrZero(aView.totalAmount, IsSecret)
    return reuse
end

local function IsHealingType(meterType)
    local T = Enum and Enum.DamageMeterType
    if not T then return false end
    return meterType == T.HealingDone or meterType == T.Hps
end

local function FormatDuration(seconds)
    local isSecret = Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(seconds)
    if not isSecret and (not seconds or seconds == 0) then return "" end
    return Helpers.FormatMMSS(seconds)
end

local function BuildPreviousSessionLabel(availableSession, separateDuration)
    availableSession = availableSession or {}
    local name = availableSession.name
    if IsSecretValue(name) then name = nil end
    if type(name) == "string" then
        name = name:gsub("^%s*%(!%)%s*", "")
    end
    if not name or name == "" then
        local sessionID = availableSession.sessionID
        if IsSecretValue(sessionID) then sessionID = nil end
        name = sessionID and ("Combat " .. tostring(sessionID)) or "Combat"
    end

    local durationText = FormatDuration(availableSession.durationSeconds)
    if separateDuration then return name, durationText end
    if durationText ~= "" then
        return name .. " [" .. durationText .. "]"
    end
    return name
end
QUI_DamageMeter.BuildPreviousSessionLabel = BuildPreviousSessionLabel

local function TakeTrailingSessions(sessions, limit)
    local result = {}
    if type(sessions) ~= "table" then return result end
    limit = math.max(0, math.floor(tonumber(limit) or 20))
    local first = math.max(1, #sessions - limit + 1)
    for i = first, #sessions do result[#result + 1] = sessions[i] end
    return result
end
QUI_DamageMeter.TakeTrailingSessions = TakeTrailingSessions

local _formatOpts = {
    compact = { config = CreateAbbreviateConfig({
        { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e4, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1e3, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,   abbreviation = "",  significandDivisor = 1,   fractionDivisor = 1,   abbreviationIsGlobal = false },
    }) },
    minimal = { config = CreateAbbreviateConfig({
        { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e9, fractionDivisor = 1, abbreviationIsGlobal = false },
        { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e6, fractionDivisor = 1, abbreviationIsGlobal = false },
        { breakpoint = 1e3, abbreviation = "K", significandDivisor = 1e3, fractionDivisor = 1, abbreviationIsGlobal = false },
        { breakpoint = 1,   abbreviation = "",  significandDivisor = 1,   fractionDivisor = 1, abbreviationIsGlobal = false },
    }) },
}

local function FormatNumber(amount, format)
    -- sink). -- @secret-policy: sink-passthrough
    if not IsSecretValue(amount) and amount == nil then return "" end
    if format == "complete" then
        return BreakUpLargeNumbers(amount)
    end
    return AbbreviateNumbers(amount, _formatOpts[format] or _formatOpts.compact)
end
local function BuildValueText(primaryVal, secondaryVal, numberFormat, isSecret, formatNumber)
    local primarySecret   = isSecret and isSecret(primaryVal)   or false
    local secondarySecret = isSecret and isSecret(secondaryVal) or false
    local primaryStr   = formatNumber(primaryVal,   numberFormat)
    local secondaryStr = formatNumber(secondaryVal, numberFormat)
    local primaryHas, secondaryHas
    if primarySecret then
        primaryHas = true
    else
        if primaryStr == "0" then primaryStr = "" end
        primaryHas = (primaryStr ~= "")
    end
    if secondarySecret then
        secondaryHas = true
    else
        if secondaryStr == "0" then secondaryStr = "" end
        secondaryHas = (secondaryStr ~= "")
    end
    if primaryHas and secondaryHas then
        if primarySecret or secondarySecret then
            local WrapString = C_StringUtil and C_StringUtil.WrapString
            if WrapString then
                local opened = WrapString(" (", primaryStr, nil)
                return WrapString(secondaryStr, opened, ")")
            end
            return primaryStr -- @secret-policy: drop-secondary-decoration
        end
        return primaryStr .. " (" .. secondaryStr .. ")"
    elseif primaryHas then
        return primaryStr
    elseif secondaryHas then
        return secondaryStr
    end
    return ""
end
QUI_DamageMeter.FormatDuration = FormatDuration
QUI_DamageMeter.FormatNumber   = FormatNumber
QUI_DamageMeter.BuildValueText = BuildValueText

local Window = {}
Window.__index = Window
QUI_DamageMeter.Window = Window

local Breakdown

local TYPE_LABEL_NAMES = {
    DamageDone           = ns.L["Damage Done"],
    Dps                  = ns.L["DPS"],
    HealingDone          = ns.L["Healing Done"],
    Hps                  = ns.L["HPS"],
    DamageTaken          = ns.L["Damage Taken"],
    AvoidableDamageTaken = ns.L["Avoidable Damage Taken"],
    EnemyDamageTaken     = ns.L["Enemy Damage Taken"],
    Absorbs              = ns.L["Absorbs"],
    Interrupts           = ns.L["Interrupts"],
    Dispels              = ns.L["Dispels"],
    Deaths               = ns.L["Deaths"],
}

local TYPE_LABELS = {}
do
    local T = Enum and Enum.DamageMeterType
    if T then
        for name, label in pairs(TYPE_LABEL_NAMES) do
            if T[name] ~= nil then
                TYPE_LABELS[T[name]] = label
            end
        end
    end
end

local function LabelForType(damageMeterType)
    return TYPE_LABELS[damageMeterType] or (ns.L["Type "] .. tostring(damageMeterType))
end
QUI_DamageMeter.LabelForType = LabelForType

local function TooltipLabelsForType(meterType)
    local T = Enum and Enum.DamageMeterType
    if T then
        if meterType == T.DamageDone or meterType == T.Dps then
            return ns.L["Total Damage"], ns.L["DPS"]
        elseif meterType == T.HealingDone or meterType == T.Hps then
            return ns.L["Total Healing"], ns.L["HPS"]
        elseif meterType == T.Absorbs then
            return ns.L["Total Absorbs"], nil
        elseif meterType == T.DamageTaken
            or meterType == T.AvoidableDamageTaken
            or meterType == T.EnemyDamageTaken then
            return ns.L["Total Damage Taken"], ns.L["DPS"]
        end
    end
    return LabelForType(meterType), nil
end

local function LabelForSession(sessionType)
    local S = Enum and Enum.DamageMeterSessionType
    if S then
        if sessionType == S.Current then return ns.L["Current"] end
        if sessionType == S.Overall then return ns.L["Overall"] end
        if sessionType == S.Expired then return ns.L["Expired"] end
    end
    if sessionType == 0 then return ns.L["Overall"] end
    if sessionType == 1 then return ns.L["Current"] end
    if sessionType == 2 then return ns.L["Expired"] end
    return ns.L["Session "] .. tostring(sessionType)
end
QUI_DamageMeter.LabelForSession = LabelForSession

local PER_SECOND_TYPES = {}
do
    local T = Enum and Enum.DamageMeterType
    if T then
        if T.Dps ~= nil then PER_SECOND_TYPES[T.Dps] = true end
        if T.Hps ~= nil then PER_SECOND_TYPES[T.Hps] = true end
    end
end

local function IsPerSecondType(meterType)
    return PER_SECOND_TYPES[meterType] == true
end

local DEATHS_TYPE = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths

local function CanOpenDetailInCombat(source, meterType, deathsType, inCombat, isSecret, hasSelector)
    if not inCombat then return true end
    if deathsType ~= nil and meterType == deathsType then return true end
    local isLocalPlayer = source and source.isLocalPlayer
    if isSecret and isSecret(isLocalPlayer) then return false end
    return isLocalPlayer == true or hasSelector == true
end
QUI_DamageMeter.CanOpenDetailInCombat = CanOpenDetailInCombat

local function ComputeBarFill(meterType, source, fillMax, deathsType, isSecret)
    if deathsType ~= nil and meterType == deathsType then
        return 0, 1, 1
    end
    local maxSecret = isSecret and isSecret(fillMax)
    if not maxSecret and (fillMax == nil or fillMax <= 0) then
        return 0, 1, 0
    end
    local fm = fillMax
    if not maxSecret and fm == nil then fm = 1 end
    local fv = source.totalAmount
    local fvSecret = isSecret and isSecret(fv)
    if not fvSecret and fv == nil then fv = 0 end
    return 0, fm, fv
end
QUI_DamageMeter.ComputeBarFill = ComputeBarFill

local BAR_POOL_SIZE = 40
local BAR_TEXTURE   = "Interface\\Buttons\\WHITE8X8"

local LSM = ns.LSM

local function ResolveBarTexture(name)
    if name and LSM and LSM.Fetch then
        local path = LSM:Fetch("statusbar", name)
        if path and path ~= "" then return path end
    end
    return BAR_TEXTURE
end

local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"

local function ResolveFontSlot(slot)
    slot = slot or {}
    local path
    if slot.name and LSM and LSM.Fetch then
        path = LSM:Fetch("font", slot.name)
    end
    if not path or path == "" then path = DEFAULT_FONT_PATH end
    local size = (slot.size and slot.size > 0) and slot.size or 11
    local outline = slot.outline or ""
    return path, size, outline
end

local function GetAccentColor()
    local QUI = _G.QUI
    if QUI and QUI.GetAddonAccentColor then
        return QUI:GetAddonAccentColor()
    end
    return 0.376, 0.647, 0.980, 1
end
QUI_DamageMeter.GetAccentColor = GetAccentColor

local function CopyColor(color)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], color[4] }
end

local function EnsureDamageMeterBorderSettings(app)
    if type(app) ~= "table" then return nil end

    app.colors = app.colors or {}
    local legacyBorder = app.colors.border

    if app.borderColorSource == nil then
        app.borderColorSource = type(legacyBorder) == "table" and "custom" or "inherit"
    end
    if type(app.borderColor) ~= "table" then
        app.borderColor = CopyColor(legacyBorder) or { 0, 0, 0, 1 }
    end

    return app
end
QUI_DamageMeter.EnsureBorderSettings = EnsureDamageMeterBorderSettings

local function WalkPath(root, ...)
    local n = select("#", ...)
    local node = root
    for i = 1, n do
        if type(node) ~= "table" then return nil end
        node = node[select(i, ...)]
    end
    return node
end

local function ResolveAppearance(windowID, ...)
    local s = GetSettings()
    if not (s and s.appearance) then return nil end
    if windowID and s.appearance.perWindow then
        local override = s.appearance.perWindow[windowID]
        if override then
            local v = WalkPath(override, ...)
            if v ~= nil then return v end
        end
    end
    return WalkPath(s.appearance.global, ...)
end
QUI_DamageMeter.ResolveAppearance = ResolveAppearance

local function WalkRawPath(root, ...)
    local n = select("#", ...)
    local node = root
    for i = 1, n do
        if type(node) ~= "table" then return nil end
        node = rawget(node, select(i, ...))
    end
    return node
end

local function ResolveExplicitAppearance(windowID, ...)
    local s = GetSettings()
    if not (s and s.appearance) then return nil end
    if windowID and type(s.appearance.perWindow) == "table" then
        local override = rawget(s.appearance.perWindow, windowID)
        local v = WalkRawPath(override, ...)
        if v ~= nil then return v end
    end
    return WalkRawPath(s.appearance.global, ...)
end

local function ResolveWindowBgAlpha(windowID, bg)
    local a = ResolveExplicitAppearance(windowID, "windowBgAlpha")
    if a ~= nil then return a end
    return (bg and bg[4] ~= nil) and bg[4] or 0.85
end

local function ApplyRowBackgroundVisibility(row, windowID)
    if not (row and row.BarBg) then return end
    row.BarBg:SetShown(ResolveAppearance(windowID, "showRowBackground") ~= false)
end
QUI_DamageMeter.ApplyRowBackgroundVisibility = ApplyRowBackgroundVisibility

local function FindLocalPlayerInSources(sources)
    if not sources then return nil end
    for i, src in ipairs(sources) do
        if src.isLocalPlayer then return i end
    end
    return nil
end

local function ComputeVisibleBindRange(scrollY, viewH, rowPitch, totalCount)
    if not totalCount or totalCount <= 0 then return 1, 0 end
    if not rowPitch or rowPitch <= 0 then return 1, totalCount end
    if not viewH or viewH <= 0 then return 1, totalCount end
    if not scrollY or scrollY < 0 then scrollY = 0 end
    local first = math.floor(scrollY / rowPitch) + 1
    local last  = math.ceil((scrollY + viewH) / rowPitch)
    if last > totalCount then last = totalCount end
    if first > totalCount then first = totalCount end
    if first < 1 then first = 1 end
    return first, last
end
QUI_DamageMeter.ComputeVisibleBindRange = ComputeVisibleBindRange

QUI_DamageMeter._appearanceRev = 1

function QUI_DamageMeter.BumpAppearanceRevision()
    QUI_DamageMeter._appearanceRev = QUI_DamageMeter._appearanceRev + 1
end

local function ShouldReapplyAppearance(appliedRev, currentRev)
    return appliedRev == nil or appliedRev ~= currentRev
end
QUI_DamageMeter.ShouldReapplyAppearance = ShouldReapplyAppearance

local function AttachRowVisuals(row, barH)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(barH, barH)
    row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.Bar = CreateFrame("StatusBar", nil, row)
    row.Bar:SetPoint("LEFT",  row.Icon, "RIGHT", 2, 0)
    row.Bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Bar:SetPoint("TOP", row, "TOP", 0, 0)
    row.Bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    row.Bar:SetStatusBarTexture(BAR_TEXTURE)
    row.Bar:SetMinMaxValues(0, 1)
    row.Bar:SetValue(0)

    row.BarBg = row.Bar:CreateTexture(nil, "BACKGROUND")
    row.BarBg:SetAllPoints(row.Bar)
    do
        local _r, _g, _b = 0.05, 0.05, 0.05
        if SkinBase and SkinBase.GetDepthColor then
            _r, _g, _b = SkinBase.GetDepthColor("ROW")
        end
        row.BarBg:SetColorTexture(_r or 0.05, _g or 0.05, _b or 0.05, 0.55)
    end

    row.Name = row.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT",  row.Bar, "LEFT",  4, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetText("")

    row.Value = row.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Value:SetPoint("RIGHT", row.Bar, "RIGHT", -4, 0)
    row.Value:SetJustifyH("RIGHT")
    row.Value:SetText("")
end
QUI_DamageMeter.AttachRowVisuals = AttachRowVisuals

local activeHoverRow
local activeHoverPreview

function Window:_ShowPlayerRowHover(rowSelf, withPreview)
    local s2 = GetSettings()
    if not (s2 and s2.showHoverTooltip) then return end
    if not rowSelf._source then return end
    local src = rowSelf._source
    activeHoverPreview = nil
    if withPreview and self:PreviewBreakdown(src, rowSelf) then
        activeHoverRow = rowSelf
        activeHoverPreview = self._breakdown
        return
    end
    if GameTooltip:IsForbidden() then return end
    activeHoverRow = rowSelf
    local inCombat = Data._inCombat or (InCombatLockdown and InCombatLockdown()) or false
    local sourceGUID, sourceCreatureID = Data:ResolveSourceSelector(
        src, self.sessionType, self.sessionID, inCombat)

    GameTooltip:SetOwner(rowSelf, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()

    local IsSecret = Helpers and Helpers.IsSecretValue

    local cr, cg, cb = 1, 1, 1
    if src.classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[src.classFilename] then
        local cc = Helpers.GetClassColorTable(src.classFilename)
        cr, cg, cb = cc.r, cc.g, cc.b
    end
    local headerName = ShortenName(src.name)
    if IsSecret and IsSecret(headerName) then
        headerName = "???" -- @secret-policy: placeholder-when-secret
    end
    GameTooltip:AddLine(headerName or "?", cr, cg, cb)

    if src.classFilename then
        GameTooltip:AddLine(src.classFilename, 0.7, 0.7, 0.7)
    end

    local addPlayerItemLevel = ns.QUI_AddPlayerItemLevelByGUIDToTooltip
    if addPlayerItemLevel then
        addPlayerItemLevel(GameTooltip, sourceGUID, true, true)
    end

    local totalLabel, rateLabel = TooltipLabelsForType(rowSelf._damageMeterType or 0)
    local totalSecret = IsSecret and IsSecret(src.totalAmount)
    if totalSecret then
        GameTooltip:AddDoubleLine(totalLabel .. ":", "???", 1, 1, 1, 1, 1, 1) -- @secret-policy: placeholder-when-secret
    else
        local amt = FormatNumber(src.totalAmount, "complete")
        if amt ~= "" then
            GameTooltip:AddDoubleLine(totalLabel .. ":", amt, 1, 1, 1, 1, 1, 1)
        end
    end

    local ps = src.amountPerSecond
    local psSecret = IsSecret and IsSecret(ps)
    if psSecret then
        GameTooltip:AddDoubleLine((rateLabel or ns.L["Per Second"]) .. ":", "???", 1, 1, 1, 1, 1, 1) -- @secret-policy: placeholder-when-secret
    elseif ps and ps ~= 0 then
        GameTooltip:AddDoubleLine((rateLabel or ns.L["Per Second"]) .. ":", FormatNumber(ps, "compact"), 1, 1, 1, 1, 1, 1)
    end

    local total = src.totalAmount
    local maxSec   = IsSecret and IsSecret(rowSelf._maxAmount)
    local totalSec = IsSecret and IsSecret(total)
    if not (maxSec or totalSec) and total ~= nil
        and rowSelf._maxAmount and rowSelf._maxAmount > 0 then
        local pct = (total / rowSelf._maxAmount) * 100
        GameTooltip:AddDoubleLine(ns.L["% of Top:"], string.format("%.1f%%", pct), 1, 1, 1, 1, 1, 1)
    end

    local hasSelector = sourceGUID ~= nil or sourceCreatureID ~= nil
    if not CanOpenDetailInCombat(src, rowSelf._damageMeterType, DEATHS_TYPE,
        inCombat, IsSecretValue, hasSelector) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.L["Spell breakdown is hidden during combat"], 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end

function Window:_HidePlayerRowHover(rowSelf, withPreview)
    if withPreview then self:ClosePreview(rowSelf) end
    if activeHoverRow == rowSelf then
        activeHoverRow = nil
        activeHoverPreview = nil
    end
    if GameTooltip:IsForbidden() then return end
    if not GameTooltip.GetOwner or GameTooltip:GetOwner() == rowSelf then GameTooltip:Hide() end
end

function Window:_AttachRowVisuals(row)
    local windowID = self.windowID
    local barH = ResolveAppearance(windowID, "barHeight") or 18

    AttachRowVisuals(row, barH)

    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("AnyUp") end
    row:SetScript("OnClick", function(rowSelf, button)
        if not rowSelf._source then return end
        if button == "RightButton" then
            if self._breakdown and self._breakdown.Close then self._breakdown:Close() end
            local manager = QUI_DamageMeter.WindowManager
            if manager and manager.CloseBreakout then manager:CloseBreakout() end
            return
        end
        self:OpenBreakdown(rowSelf._source, rowSelf)
    end)
    row:SetScript("OnEnter", function(rowSelf)
        self:_ShowPlayerRowHover(rowSelf, true)
    end)
    row:SetScript("OnLeave", function(rowSelf)
        self:_HidePlayerRowHover(rowSelf, true)
    end)
end

if ns.TooltipInspect and ns.TooltipInspect.RegisterRefreshCallback then
    ns.TooltipInspect:RegisterRefreshCallback(function(guid)
        local preview = activeHoverPreview
        if preview and preview.frame and preview.frame:IsShown()
            and Helpers.SafeCompare(preview.sourceGUID, guid) == true then
            preview:_UpdateTitle()
        end

        local row = activeHoverRow
        local source = row and row._source
        if not source or not GameTooltip:IsShown() then return end
        if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= row then return end
        if Helpers.SafeCompare(source.sourceGUID, guid) ~= true then return end

        local addPlayerItemLevel = ns.QUI_AddPlayerItemLevelByGUIDToTooltip
        if addPlayerItemLevel then
            addPlayerItemLevel(GameTooltip, guid, false)
        end
    end)
end

function Window:_BuildRow(index)
    local windowID = self.windowID
    local barH    = ResolveAppearance(windowID, "barHeight")    or 18
    local barGap  = ResolveAppearance(windowID, "barSpacing")   or 2

    local parent = self.scrollContent
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(barH)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if index == 1 then
        row:SetPoint("TOP", parent, "TOP", 0, 0)
    else
        row:SetPoint("TOP", self.rows[index - 1], "BOTTOM", 0, -barGap)
    end

    self:_AttachRowVisuals(row)
    row:Hide()
    return row
end

function Window:_BuildStickyRow()
    local windowID = self.windowID
    local barH = ResolveAppearance(windowID, "barHeight") or 18

    local row = CreateFrame("Button", nil, self.frame)
    row:SetHeight(barH)
    row:SetPoint("LEFT",   self.frame, "LEFT",   0, 0)
    row:SetPoint("RIGHT",  self.frame, "RIGHT",  0, 0)
    row:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 0)
    row:SetFrameLevel(self.scrollFrame:GetFrameLevel() + 5)

    self:_AttachRowVisuals(row)
    row:Hide()
    return row
end

function Window:_EnsureRowPool()
    if #self.rows >= BAR_POOL_SIZE then return end
    for i = #self.rows + 1, BAR_POOL_SIZE do
        self.rows[i] = self:_BuildRow(i)
    end
end

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function Window:_SetRowSource(row, source, maxAmount)
    local windowID = self.windowID

    ApplyRowBackgroundVisibility(row, windowID)

    local barTexName = ResolveAppearance(windowID, "textures", "bar")
    row.Bar:SetStatusBarTexture(ResolveBarTexture(barTexName))

    local iconStyle = ResolveAppearance(windowID, "iconStyle") or "spec"
    if iconStyle == "none" then
        row.Icon:SetTexture(nil)
    elseif iconStyle == "class" and source.classFilename and CLASS_ICON_TCOORDS then
        row.Icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        local coords = CLASS_ICON_TCOORDS[source.classFilename]
        if coords then
            row.Icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    else
        if source.specIconID and source.specIconID ~= 0 then
            row.Icon:SetTexture(source.specIconID)
            row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        elseif source.classFilename and CLASS_ICON_TCOORDS then
            row.Icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            local coords = CLASS_ICON_TCOORDS[source.classFilename]
            if coords then
                row.Icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        else
            row.Icon:SetTexture(FALLBACK_ICON)
            row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    local displayName = ShortenName(source.name)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(displayName) then
        row.Name:SetFormattedText("%d. %s", source.rank or 0, displayName) -- @secret-policy: sink-passthrough
    else
        row.Name:SetText((source.rank or 0) .. ". " .. (displayName or "?"))
    end

    local rnc = ResolveAppearance(windowID, "colors", "rowName") or { 1, 1, 1, 1 }
    local nameColor
    if ResolveAppearance(windowID, "useClassColorNames") and source.classFilename and RAID_CLASS_COLORS then
        nameColor = Helpers.GetClassColorTable(source.classFilename)
    end
    if nameColor then
        row.Name:SetTextColor(nameColor.r, nameColor.g, nameColor.b, rnc[4] or 1)
    else
        row.Name:SetTextColor(rnc[1] or 1, rnc[2] or 1, rnc[3] or 1, rnc[4] or 1)
    end

    local numberFormat = ResolveAppearance(windowID, "numberFormat") or "compact"
    local perSecondMode = IsPerSecondType(self.damageMeterType)
    local primaryVal, secondaryVal
    if perSecondMode then
        primaryVal, secondaryVal = source.amountPerSecond, source.totalAmount
    else
        primaryVal, secondaryVal = source.totalAmount, source.amountPerSecond
    end
    if ResolveAppearance(windowID, "showSecondaryValue") == false then
        secondaryVal = nil
    end
    local IsSecret = Helpers and Helpers.IsSecretValue
    row.Value:SetText(BuildValueText(primaryVal, secondaryVal, numberFormat, IsSecret, FormatNumber))

    local fillMin, fillMaxValue, fillValue =
        ComputeBarFill(self.damageMeterType, source, maxAmount, DEATHS_TYPE, IsSecret)
    row.Bar:SetMinMaxValues(fillMin, fillMaxValue)

    row.Bar:SetValue(fillValue)

    local alpha = ResolveAppearance(windowID, "barFillAlpha") or 1
    if ResolveAppearance(windowID, "useClassColor") and source.classFilename and RAID_CLASS_COLORS then
        local c = Helpers.GetClassColorTable(source.classFilename)
        if c then
            row.Bar:SetStatusBarColor(c.r, c.g, c.b, alpha)
        else
            row.Bar:SetStatusBarColor(0.5, 0.5, 0.5, alpha)
        end
    elseif ResolveAppearance(windowID, "barColorAccent") then
        local ar, ag, ab = GetAccentColor()
        row.Bar:SetStatusBarColor(ar, ag, ab, alpha)
    else
        local bc = ResolveAppearance(windowID, "barColor")
        if bc then
            row.Bar:SetStatusBarColor(bc[1] or 0.35, bc[2] or 0.55, bc[3] or 0.8, alpha)
        else
            row.Bar:SetStatusBarColor(0.35, 0.55, 0.8, alpha)
        end
    end

    row._source = source
    row._maxAmount = maxAmount
    row._damageMeterType = self.damageMeterType
end

function Window:_ApplyHeader()
    if not self.frame or not self.TypeLabel then return end
    local sessionLabel = self.sessionID ~= nil and (self.sessionLabel or ns.L["Previous"])
        or LabelForSession(self.sessionType)
    self.TypeLabel:SetText(LabelForType(self.damageMeterType))
    if self.SegmentButton then self.SegmentButton:SetText(sessionLabel) end
end

function Window:_ResolveBorderColor()
    local source = ResolveAppearance(self.windowID, "borderColorSource")
    if source ~= nil and Helpers and Helpers.GetSkinBorderColor then
        return Helpers.GetSkinBorderColor({
            borderColorSource = source,
            borderColor = ResolveAppearance(self.windowID, "borderColor"),
        })
    end

    local border = ResolveAppearance(self.windowID, "colors", "border")
    if border then
        return border[1] or 1, border[2] or 1, border[3] or 1, border[4] or 1
    end
    return GetAccentColor()
end

function Window:_ApplyColors()
    local windowID = self.windowID

    if self.backdropTex then
        local bg = ResolveAppearance(windowID, "colors", "bg")
        if not bg then
            local _r, _g, _b = 0, 0, 0
            if Helpers and Helpers.GetSkinBgColor then
                _r, _g, _b = Helpers.GetSkinBgColor()
            end
            bg = { _r or 0, _g or 0, _b or 0, 0.85 }
        end
        local a = ResolveWindowBgAlpha(windowID, bg)
        self.backdropTex:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, a)
    end

    if self.border and self.border.SetBackdropBorderColor then
        self.border:SetBackdropBorderColor(self:_ResolveBorderColor())
    end

    local headerText = ResolveAppearance(windowID, "colors", "headerText")
    local hr, hg, hb, ha
    if headerText then
        hr, hg, hb, ha = headerText[1] or 1, headerText[2] or 1, headerText[3] or 1, headerText[4] or 1
    else
        hr, hg, hb, ha = GetAccentColor()
    end
    if self.TypeLabel    then self.TypeLabel:SetTextColor(hr, hg, hb, ha)    end
    if self.SessionTimer then self.SessionTimer:SetTextColor(hr, hg, hb, ha) end

    if not self.rows then return end
    local rn = ResolveAppearance(windowID, "colors", "rowName")  or { 1, 1, 1, 1 }
    local rv = ResolveAppearance(windowID, "colors", "rowValue") or { 1, 1, 1, 1 }
    local classNames = ResolveAppearance(windowID, "useClassColorNames")
    local function nameRGBA(row)
        if classNames and row._source and row._source.classFilename then
            local nc = Helpers.GetClassColorTable(row._source.classFilename)
            if nc then return nc.r, nc.g, nc.b, rn[4] or 1 end
        end
        return rn[1] or 1, rn[2] or 1, rn[3] or 1, rn[4] or 1
    end
    for i = 1, #self.rows do
        local row = self.rows[i]
        if row then
            if row.Name  then row.Name:SetTextColor(nameRGBA(row)) end
            if row.Value then row.Value:SetTextColor(rv[1] or 1, rv[2] or 1, rv[3] or 1, rv[4] or 1) end
        end
    end
    if self.stickyRow then
        local r = self.stickyRow
        if r.Name  then r.Name:SetTextColor(nameRGBA(r)) end
        if r.Value then r.Value:SetTextColor(rv[1] or 1, rv[2] or 1, rv[3] or 1, rv[4] or 1) end
    end
end

function Window:_ApplyFonts()
    local windowID = self.windowID

    local function applyFont(fs, p, s, o)
        if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
            ns.Helpers.ApplyFontWithFallback(fs, p, s, o)
        else
            fs:SetFont(p, s, o)
        end
    end

    do
        local slot = ResolveAppearance(windowID, "fonts", "header")
        local path, size, outline = ResolveFontSlot(slot)
        if self.TypeLabel    then applyFont(self.TypeLabel, path, size, outline)    end
        if self.SessionTimer then applyFont(self.SessionTimer, path, size, outline) end
        if self.SegmentButton and self.SegmentButton.text then
            applyFont(self.SegmentButton.text, path, size, outline)
        end
    end

    if not self.rows then return end
    local nSlot = ResolveAppearance(windowID, "fonts", "rowName")
    local vSlot = ResolveAppearance(windowID, "fonts", "rowValue")
    local nPath, nSize, nOutline = ResolveFontSlot(nSlot)
    local vPath, vSize, vOutline = ResolveFontSlot(vSlot)
    for i = 1, #self.rows do
        local row = self.rows[i]
        if row then
            if row.Name  then applyFont(row.Name, nPath, nSize, nOutline)  end
            if row.Value then applyFont(row.Value, vPath, vSize, vOutline) end
        end
    end
    if self.stickyRow then
        local r = self.stickyRow
        if r.Name  then applyFont(r.Name, nPath, nSize, nOutline)  end
        if r.Value then applyFont(r.Value, vPath, vSize, vOutline) end
    end
end

local METER_TYPES = {}
do
    local T = Enum and Enum.DamageMeterType
    if T then
        local order = {
            "DamageDone", "Dps",
            "HealingDone", "Hps", "Absorbs",
            "DamageTaken", "AvoidableDamageTaken", "EnemyDamageTaken",
            "Interrupts", "Dispels", "Deaths",
        }
        for _, name in ipairs(order) do
            if T[name] ~= nil then table.insert(METER_TYPES, T[name]) end
        end
    end
end
QUI_DamageMeter.MeterTypes = METER_TYPES

local function PrepareSourcesForRender(view)
    local sources = view.sources
    local first = sources[1]
    local fillMax = first and first.totalAmount
    if not IsSecretValue(fillMax) and fillMax == nil then fillMax = 0 end
    return sources, fillMax
end

function Window:SetDamageMeterType(damageMeterType)
    local s = GetSettings()
    local windowState = s and s.windows and s.windows[self.windowID]
    if not windowState then return end
    self.damageMeterType = damageMeterType
    windowState.damageMeterType = damageMeterType
    self._lastGeneration = -1
    if self._breakdown and self._breakdown.Close then self._breakdown:Close() end
    QUI_DamageMeter.WindowManager:RefreshAll()
end

function Window:_SelectSession(sessionType, sessionID, sessionLabel)
    local manager = QUI_DamageMeter.WindowManager
    if manager and manager.ApplySessionSelection then
        manager:ApplySessionSelection(self, sessionType, sessionID, sessionLabel)
    end
end

function Window:_PopulateSessionMenu(root)
    root:CreateTitle(ns.L["Session"])
    local S = Enum and Enum.DamageMeterSessionType
    local currentSession = (S and S.Current) or 1
    local overallSession = (S and S.Overall) or 0

    local sessions
    if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
        local ok, availableSessions = ns.SafeCall("best-effort-style", C_DamageMeter.GetAvailableCombatSessions)
        if ok and type(availableSessions) == "table" then
            sessions = availableSessions
        end
    end

    sessions = TakeTrailingSessions(sessions, 20)
    if #sessions == 0 then
        local none = root:CreateButton(ns.L["No previous sessions"], function() end)
        none:SetEnabled(false)
    else
        for _, availableSession in ipairs(sessions) do
            local sessionID = availableSession.sessionID
            local sessionLabel = BuildPreviousSessionLabel(availableSession)
            root:CreateRadio(sessionLabel,
                function() return self.sessionID == sessionID end,
                function() self:_SelectSession(nil, sessionID, sessionLabel) end)
        end
    end
    root:CreateDivider()
    root:CreateRadio(ns.L["Current"],
        function() return self.sessionID == nil and self.sessionType == currentSession end,
        function() self:_SelectSession(currentSession, nil) end)
    root:CreateRadio(ns.L["Overall"],
        function() return self.sessionID == nil and self.sessionType == overallSession end,
        function() self:_SelectSession(overallSession, nil) end)
end

function Window:_OpenSessionMenu()
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    MenuUtil.CreateContextMenu(self.SegmentButton or self.header or self.frame, function(_, root)
        self:_PopulateSessionMenu(root)
    end)
end

local function ResolveWindowAutoSwap(windowState, settings)
    local value = rawget(windowState, "autoSwapChallengeSessions")
    if value == nil then value = settings and settings.autoSwapChallengeSessions end
    return value == true
end

function Window:_OpenConfigMenu()
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    local s = GetSettings()
    local windowState = s and s.windows and s.windows[self.windowID]
    if not windowState then return end

    MenuUtil.CreateContextMenu(self.header or self.frame, function(_, root)
        root:CreateTitle(ns.L["Meter Type"])
        for _, t in ipairs(METER_TYPES) do
            local typeVal = t
            root:CreateRadio(LabelForType(typeVal),
                function() return self.damageMeterType == typeVal end,
                function() self:SetDamageMeterType(typeVal) end)
        end
        root:CreateDivider()
        self:_PopulateSessionMenu(root)
        root:CreateDivider()
        root:CreateTitle(ns.L["Window Behavior"])
        root:CreateCheckbox(ns.L["Hide Timer"],
            function() return windowState.hideTimer == true end,
            function()
                windowState.hideTimer = not windowState.hideTimer
                self.SessionTimer:SetShown(not windowState.hideTimer)
            end)
        root:CreateCheckbox(ns.L["Auto Swap Current/Overall"],
            function() return ResolveWindowAutoSwap(windowState, s) end,
            function()
                windowState.autoSwapChallengeSessions = not ResolveWindowAutoSwap(windowState, s)
            end)
        root:CreateCheckbox(ns.L["Auto Current on Combat"],
            function() return windowState.autoCurrentOnCombat == true end,
            function() windowState.autoCurrentOnCombat = not windowState.autoCurrentOnCombat end)
        root:CreateCheckbox(ns.L["Sync Segment Selection"],
            function() return windowState.syncSegments == true end,
            function() windowState.syncSegments = not windowState.syncSegments end)
        local mythicDefault = root:CreateButton(ns.L["Default on M+ Start"])
        mythicDefault:CreateRadio(ns.L["Off"],
            function() return not windowState.mythicStartDMType end,
            function() windowState.mythicStartDMType = false end)
        for _, t in ipairs(METER_TYPES) do
            local typeVal = t
            mythicDefault:CreateRadio(LabelForType(typeVal),
                function() return windowState.mythicStartDMType == typeVal end,
                function() windowState.mythicStartDMType = typeVal end)
        end
        root:CreateDivider()
        root:CreateTitle(ns.L["Data"])
        root:CreateButton(ns.L["Reset Data"], function()
            if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                C_DamageMeter.ResetAllCombatSessions()
                Data:ResetCombatClock()
                Data:ClearCachedViews()
                Data:ClearSourceGUIDCache()
                if QUI_DamageMeter.WindowManager.ClearRuntimeSessionIDs then
                    QUI_DamageMeter.WindowManager:ClearRuntimeSessionIDs()
                end
                QUI_DamageMeter.WindowManager:RefreshAll()
            end
        end)

        root:CreateDivider()
        root:CreateTitle(ns.L["Window"])
        local newWindow = root:CreateButton(ns.L["New Window"], function()
            if QUI_DamageMeter.WindowManager:SpawnNew() == nil then
                print(ns.L["|cff30D1FF[QUI]|r At the 5-window cap; delete one first."])
            end
        end)
        newWindow:SetEnabled(QUI_DamageMeter.WindowManager:CanSpawnNew())

        local deleteWindow = root:CreateButton(ns.L["Delete Window"], function()
            QUI_DamageMeter.WindowManager:DeleteWindow(self.windowID)
        end)
        deleteWindow:SetEnabled(QUI_DamageMeter.WindowManager:Count() > 1)
    end)
end

function Window:_UpdateScrollThumb()
    local scrollBar     = self.scrollBar
    local scrollFrame   = self.scrollFrame
    local scrollContent = self.scrollContent
    if not (scrollBar and scrollFrame and scrollContent) then return end
    if self._bodyHidden then
        scrollBar:Hide()
        return
    end

    local contentH = scrollContent:GetHeight()
    local viewH    = scrollFrame:GetHeight()
    if contentH <= viewH or viewH <= 0 then
        scrollBar:Hide()
        return
    end
    scrollBar:Show()

    local trackH = scrollBar:GetHeight()
    if trackH <= 0 then return end

    local thumbH = math.max(20, (viewH / contentH) * trackH)
    scrollBar.thumb:SetHeight(thumbH)

    local maxScroll = contentH - viewH
    local cur = scrollFrame:GetVerticalScroll() or 0
    if cur > maxScroll then
        cur = maxScroll
        scrollFrame:SetVerticalScroll(cur)
    end
    local ratio = (maxScroll > 0) and (cur / maxScroll) or 0
    local yOff = -ratio * (trackH - thumbH)
    scrollBar.thumb:ClearAllPoints()
    scrollBar.thumb:SetPoint("TOP", scrollBar, "TOP", 0, yOff)
end

function Window:_SetBodyShown(shown)
    self._bodyHidden = not shown
    if self.scrollFrame then self.scrollFrame:SetShown(shown) end
    if not shown then
        if self.scrollBar then self.scrollBar:Hide() end
        if self.stickyRow then self.stickyRow:Hide() end
        if self.stickySeparator then self.stickySeparator:Hide() end
        return
    end
    self:_UpdateStickyVisibility()
    self:_UpdateScrollThumb()
end

function Window:_UpdateStickyVisibility()
    local sources = self._renderSources
    local sticky  = self.stickyRow
    local sep     = self.stickySeparator
    local sf      = self.scrollFrame
    if not (sticky and sep and sf) then return end
    if self._bodyHidden then return end

    local function setHidden()
        if sticky:IsShown() then sticky:Hide() end
        if sep:IsShown()    then sep:Hide()    end
        if self._stickyShown then
            local headerH = ResolveAppearance(self.windowID, "headerHeight") or 22
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT",     self.frame, "TOPLEFT",     0, -headerH)
            sf:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0,  0)
            self._stickyShown = false
            self:_UpdateScrollThumb()
        end
    end

    local s = GetSettings()
    local pinnedSelf = s and s.showPinnedSelf
    if not (pinnedSelf and sources and #sources > 0) then setHidden(); return end

    local localIdx = FindLocalPlayerInSources(sources)
    if not localIdx then setHidden(); return end

    local barH    = ResolveAppearance(self.windowID, "barHeight")  or 18
    local barGap  = ResolveAppearance(self.windowID, "barSpacing") or 2
    local rowPitch = barH + barGap
    local scrollY = sf:GetVerticalScroll() or 0
    local viewH   = sf:GetHeight()
    local firstVisible = math.floor(scrollY / rowPitch) + 1
    local lastVisible  = firstVisible + math.floor(viewH / rowPitch) - 1
    if localIdx >= firstVisible and localIdx <= lastVisible then
        setHidden(); return
    end

    self:_SetRowSource(sticky, sources[localIdx], self._renderFillMax)
    sticky:Show()
    sep:Show()
    if not self._stickyShown then
        local headerH = ResolveAppearance(self.windowID, "headerHeight") or 22
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     self.frame, "TOPLEFT",  0, -headerH)
        sf:SetPoint("BOTTOMRIGHT", sep,        "TOPRIGHT", 0,  0)
        self._stickyShown = true

        local contentH = self.scrollContent and self.scrollContent:GetHeight() or 0
        local newViewH = sf:GetHeight()
        local maxScroll = math.max(0, contentH - newViewH)
        if scrollY > maxScroll then sf:SetVerticalScroll(maxScroll) end
        self:_UpdateScrollThumb()
    end
end

function Window:_BindVisibleRows()
    local sources = self._renderSources
    if not sources then return end
    local sf = self.scrollFrame
    local barH   = ResolveAppearance(self.windowID, "barHeight")  or 18
    local barGap = ResolveAppearance(self.windowID, "barSpacing") or 2
    local scrollY = (sf and sf:GetVerticalScroll()) or 0
    local viewH   = (sf and sf:GetHeight()) or 0
    local renderCount = math.min(#sources, BAR_POOL_SIZE)
    local first, last = ComputeVisibleBindRange(scrollY, viewH, barH + barGap, renderCount)

    local gen = self._lastGeneration
    if gen == self._boundGeneration
        and first == self._boundFirst and last == self._boundLast then
        return
    end
    local sameData = gen == self._boundGeneration
    local oldFirst = self._boundFirst or 0
    local oldLast  = self._boundLast  or -1
    for i = 1, #self.rows do
        local row = self.rows[i]
        local visible = i >= first and i <= last
        if visible and not (sameData and i >= oldFirst and i <= oldLast) then
            self:_SetRowSource(row, sources[i], self._renderFillMax)
        end
        row:SetShown(visible)
    end
    self._boundGeneration, self._boundFirst, self._boundLast = gen, first, last
end

function Window:Refresh()
    if not self.frame then return end

    local s = GetSettings()
    local ws = s and s.windows and s.windows[self.windowID]
    if self.SessionTimer then self.SessionTimer:SetShown(not (ws and ws.hideTimer)) end
    local visibility = s and s.visibility
    if (ws and ws.hidden)
        or visibility == "hidden"
        or (visibility == "inCombat" and not Data._inCombat) then
        self.frame:Hide()
        return
    elseif not self.frame:IsShown() then
        self.frame:Show()
    end

    local _t0 = Perf.enabled and PerfNow() or 0
    local rev = QUI_DamageMeter._appearanceRev
    if ShouldReapplyAppearance(self._appliedAppearanceRev, rev) then
        self:_ApplyHeader()
        self:_ApplyFonts()
        self:_ApplyColors()
        self._appliedAppearanceRev = rev
    end

    local view
    local s_combo = GetSettings()
    if IsHealingType(self.damageMeterType)
        and s_combo and s_combo.combineAbsorbsIntoHealing then
        view = Data:GetCombinedHealingView(self.sessionType, self.sessionID)
    else
        view = Data:GetView(self.sessionType, self.damageMeterType, self.sessionID)
    end
    if view.generation == self._lastGeneration then
        self:_BindVisibleRows()
        return
    end
    self._lastGeneration = view.generation

    local d = view.duration
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(d) then
        self.SessionTimer:SetText(FormatDuration(d))
    elseif d and d > 0 then
        self.SessionTimer:SetText("[" .. FormatDuration(d) .. "]")
    else
        self.SessionTimer:SetText("")
    end

    self:_EnsureRowPool()
    local sources, fillMax = PrepareSourcesForRender(view)
    local renderCount = math.min(#sources, BAR_POOL_SIZE)

    self._renderSources = sources
    self._renderFillMax = fillMax
    self._boundGeneration = nil

    local barH   = ResolveAppearance(self.windowID, "barHeight")  or 18
    local barGap = ResolveAppearance(self.windowID, "barSpacing") or 2
    local rowPitch = barH + barGap
    if self.scrollContent then
        local contentH = renderCount > 0 and (renderCount * rowPitch - barGap) or 0
        self.scrollContent:SetHeight(math.max(1, contentH))
    end
    self:_UpdateScrollThumb()

    self:_UpdateStickyVisibility()

    self:_BindVisibleRows()

    self:RefreshBreakdown()
    if Perf.enabled then Perf:Record("window", PerfNow() - _t0) end
end

local function LayoutKey(windowID) return "damageMeter_window_" .. windowID end

local WINDOW_LAYOUT_FEATURE_ID = "damageMeterWindowLayout"

local WINDOW_SIZE_MIN_W, WINDOW_SIZE_MAX_W = 120, 1200
local WINDOW_SIZE_MIN_H, WINDOW_SIZE_MAX_H = 60, 1000

local RESIZE_CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

local function GetAccentRGB()
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    local accent = GUI and GUI.Colors and GUI.Colors.accent
    if accent then
        return accent[1], accent[2], accent[3]
    end
    return 0.376, 0.647, 0.980
end

local function AttachWindowResizeOverlay(overlay, frame, window, windowID)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(frame)

    if overlay._dmResizeGrips then return end
    overlay._dmResizeGrips = {}

    local r, g, b = GetAccentRGB()

    for _, corner in ipairs(RESIZE_CORNERS) do
        local grip = CreateFrame("Button", nil, overlay)
        grip:SetSize(20, 20)
        grip:SetFrameLevel(overlay:GetFrameLevel() + 10)
        grip:EnableMouse(true)

        local insetX = (corner == "TOPLEFT" or corner == "BOTTOMLEFT") and 2 or -2
        local insetY = (corner == "TOPLEFT" or corner == "TOPRIGHT") and -2 or 2
        grip:ClearAllPoints()
        grip:SetPoint(corner, overlay, corner, insetX, insetY)

        local barH = grip:CreateTexture(nil, "OVERLAY")
        barH:SetColorTexture(r, g, b, 0.9)
        barH:SetSize(18, 3)
        barH:SetPoint(corner, 0, 0)

        local barV = grip:CreateTexture(nil, "OVERLAY")
        barV:SetColorTexture(r, g, b, 0.9)
        barV:SetSize(3, 18)
        barV:SetPoint(corner, 0, 0)

        local hl = grip:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(1, 1, 1, 0.35)
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")

        local tooltipAnchor = (corner == "TOPLEFT" or corner == "BOTTOMLEFT")
            and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT"

        grip:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, tooltipAnchor)
                local LM = ns.QUI_LayoutMode
                if LM and LM.IsElementAnchored and LM:IsElementAnchored(overlay._barKey) then
                    GameTooltip:SetText(ns.L["Hold Shift to resize (anchored)"])
                else
                    GameTooltip:SetText(ns.L["Drag to resize meter window"])
                end
                GameTooltip:Show()
            end
        end)
        grip:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        grip:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            if InCombatLockdown and InCombatLockdown() then return end
            local LM = ns.QUI_LayoutMode
            local key = overlay._barKey
            if LM and key and LM.IsElementAnchored and LM:IsElementAnchored(key) then
                if not IsShiftKeyDown() then
                    if LM.FlashLockedHandle then LM:FlashLockedHandle(key) end
                    return
                end
                if LM.DetachElementAnchor then LM:DetachElementAnchor(key) end
            end
            if frame.SetResizable then frame:SetResizable(true) end
            frame:StartSizing(corner)
        end)
        grip:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then return end
            frame:StopMovingOrSizing()

            local s = GetSettings()
            local ws = s and s.windows and s.windows[windowID]
            if ws then
                ws.size = ws.size or {}
                ws.size.w = math.floor((frame:GetWidth()  or 0) + 0.5)
                ws.size.h = math.floor((frame:GetHeight() or 0) + 0.5)
            end

            local LM = ns.QUI_LayoutMode
            if LM and LM.RecordFreeElementPosition then
                LM:RecordFreeElementPosition(overlay._barKey, frame)
            end

            ns.SafeCallMethodIfPresent("best-effort-style", window, "Refresh")

            local U = ns.QUI_LayoutMode_Utils
            if U and U.RefreshActiveSizeSliders then
                U.RefreshActiveSizeSliders()
            end
        end)

        overlay._dmResizeGrips[corner] = grip
    end
end

local function RegisterWithLayoutMode(window)
    local windowID = window.windowID
    local key      = LayoutKey(windowID)
    local label    = ns.L["Damage Meter"] .. " " .. windowID

    if ns.QUI_LayoutMode and type(ns.QUI_LayoutMode.RegisterElement) == "function" then
        ns.QUI_LayoutMode:RegisterElement({
            key      = key,
            label    = label,
            group    = ns.L["Display"],
            order    = 60,
            isOwned  = true,
            getFrame = function() return window.frame end,
            getSize = function()
                if not window.frame then return nil end
                return window.frame:GetWidth(), window.frame:GetHeight()
            end,
            isEnabled = function()
                local s = GetSettings()
                return s and (QUI_DamageMeter.WindowManager:Get(windowID) ~= nil)
            end,
            setGameplayHidden = function(hide)
                if hide then window:Hide() else window:Show() end
            end,
            setupOverlay = function(overlay, frame)
                AttachWindowResizeOverlay(overlay, frame, window, windowID)
            end,
        })
    end

    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(key, {
            resolver    = function() return window.frame end,
            displayName = label,
            category    = "Display",
            order       = 60,
        })
    end

    local Registry = ns.Settings and ns.Settings.Registry
    if Registry and type(Registry.RegisterLookupKey) == "function" then
        Registry:RegisterLookupKey(WINDOW_LAYOUT_FEATURE_ID, key)
    end

    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(key)
    end
end

do
    local Settings       = ns.Settings
    local Registry       = Settings and Settings.Registry
    local Schema         = Settings and Settings.Schema
    local RenderAdapters = Settings and Settings.RenderAdapters
    if Registry and Schema and RenderAdapters
        and type(Registry.RegisterFeature) == "function"
        and type(Schema.Feature) == "function"
        and type(RenderAdapters.RenderPositionOnly) == "function" then
        Registry:RegisterFeature(Schema.Feature({
            id     = WINDOW_LAYOUT_FEATURE_ID,
            render = {
                layout = function(host, options)
                    local providerKey = options and options.providerKey
                    if type(providerKey) ~= "string" or providerKey == "" then
                        return 80
                    end

                    local U = ns.QUI_LayoutMode_Utils
                    local windowID = tonumber(providerKey:match("^damageMeter_window_(%d+)$"))
                    local window = windowID
                        and QUI_DamageMeter.WindowManager
                        and QUI_DamageMeter.WindowManager:Get(windowID)

                    if not window or not window.frame or not U
                        or type(U.BuildPositionCollapsible) ~= "function"
                        or type(U.BuildSizeCollapsible) ~= "function"
                        or type(U.StandardRelayout) ~= "function" then
                        return RenderAdapters.RenderPositionOnly(host, providerKey)
                    end

                    local function getSize()
                        local f = window.frame
                        return f:GetWidth(), f:GetHeight()
                    end

                    local function setSize(w, h)
                        if InCombatLockdown and InCombatLockdown() then return end
                        local f = window.frame
                        if not f then return end
                        w = math.max(WINDOW_SIZE_MIN_W, math.min(WINDOW_SIZE_MAX_W, math.floor(w + 0.5)))
                        h = math.max(WINDOW_SIZE_MIN_H, math.min(WINDOW_SIZE_MAX_H, math.floor(h + 0.5)))
                        f:SetSize(w, h)
                        local s = GetSettings()
                        local ws = s and s.windows and s.windows[windowID]
                        if ws then
                            ws.size = ws.size or {}
                            ws.size.w = w
                            ws.size.h = h
                        end
                        if _G.QUI_ReassertAnchorAfterResize then
                            _G.QUI_ReassertAnchorAfterResize(providerKey)
                        end
                        ns.SafeCallMethodIfPresent("best-effort-style", window, "Refresh")
                    end

                    local prevPosOnly = U._layoutModePositionOnly
                    U._layoutModePositionOnly = false
                    local sections = {}
                    local function relayout() U.StandardRelayout(host, sections) end
                    local ok, err = xpcall(function()
                        U.BuildPositionCollapsible(host, providerKey, nil, sections, relayout)
                        U.BuildSizeCollapsible(host, {
                            getSize = getSize,
                            setSize = setSize,
                            minW = WINDOW_SIZE_MIN_W, maxW = WINDOW_SIZE_MAX_W,
                            minH = WINDOW_SIZE_MIN_H, maxH = WINDOW_SIZE_MAX_H,
                            widthDescription  = ns.L["Damage meter window width in pixels."],
                            heightDescription = ns.L["Damage meter window height in pixels."],
                        }, sections, relayout)
                        relayout()
                    end, function(msg) return msg end)
                    U._layoutModePositionOnly = prevPosOnly
                    if not ok and geterrorhandler then geterrorhandler()(err) end
                    return host:GetHeight()
                end,
            },
        }))
    end
end

function Window.New(windowID)
    local s = GetSettings()
    local windowState = s and s.windows and s.windows[windowID]
    if not windowState then
        windowState = {
            damageMeterType = 0, sessionType = 1,
            size     = { w = 240, h = 180 },
            hidden = false,
            autoCurrentOnCombat = false,
            syncSegments = false,
            autoSwapChallengeSessions = false,
            mythicStartDMType = false,
            hideTimer = false,
        }
    end

    local self = setmetatable({
        windowID        = windowID,
        damageMeterType = windowState.damageMeterType,
        sessionType     = windowState.sessionType,
        rows            = {},
        _lastGeneration = 0,
    }, Window)
    self.sessionID = nil

    local frame = CreateFrame("Frame", "QUI_DamageMeterWindow" .. windowID, UIParent)
    frame:SetSize(windowState.size.w, windowState.size.h)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(WINDOW_SIZE_MIN_W, WINDOW_SIZE_MIN_H, WINDOW_SIZE_MAX_W, WINDOW_SIZE_MAX_H)
    end
    self.frame = frame

    local backdrop = CreateFrame("Frame", nil, frame)
    backdrop:SetAllPoints(frame)
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(backdrop)
    local appBg = ResolveAppearance(windowID, "colors", "bg")
    if not appBg then
        local _r, _g, _b = 0, 0, 0
        if Helpers and Helpers.GetSkinBgColor then
            _r, _g, _b = Helpers.GetSkinBgColor()
        end
        appBg = { _r or 0, _g or 0, _b or 0, 0.85 }
    end
    local appA = ResolveWindowBgAlpha(windowID, appBg)
    bgTex:SetColorTexture(appBg[1], appBg[2], appBg[3], appA)
    self.backdrop = backdrop
    self.backdropTex = bgTex

    if ns.UIKit and ns.UIKit.CreateBackdropBorder then
        self.border = ns.UIKit.CreateBackdropBorder(frame, 1, self:_ResolveBorderColor())
    end

    local headerH = ResolveAppearance(windowID, "headerHeight") or 22
    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(headerH)
    self.header = header

    local typeLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("LEFT", header, "LEFT", 6, 0)
    typeLabel:SetText(ns.L["Damage Done"])
    self.TypeLabel = typeLabel

    self.SegmentButton = SkinBase.CreateButton(header, {
        text = ns.L["Current"],
        width = 58,
        height = headerH - 4,
        onClick = function() self:_OpenSessionMenu() end,
    })
    self.SegmentButton:SetPoint("RIGHT", header, "RIGHT", -2, 0)

    local sessionTimer = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionTimer:SetPoint("RIGHT", self.SegmentButton, "LEFT", -4, 0)
    sessionTimer:SetText("")
    sessionTimer:SetShown(not windowState.hideTimer)
    self.SessionTimer = sessionTimer
    typeLabel:SetPoint("RIGHT", sessionTimer, "LEFT", -4, 0)
    typeLabel:SetWordWrap(false)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(headerH - 6, headerH - 6)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    closeBtn:Hide()
    self.CloseButton = closeBtn

    header:EnableMouse(true)
    if header.RegisterForClicks then header:RegisterForClicks("RightButtonUp") end
    header:SetScript("OnClick", function(_, button)
        if button == "RightButton" then self:_OpenConfigMenu() end
    end)
    header:SetScript("OnEnter", function(hdr)
        if GameTooltip:IsForbidden() then return end
        GameTooltip:SetOwner(hdr, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(ns.L["Right-click for options"], 1, 1, 1)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        if GameTooltip:IsForbidden() then return end
        GameTooltip:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -headerH)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  0)
    scrollFrame:EnableMouseWheel(true)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollContent)

    scrollFrame:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then scrollContent:SetWidth(w) end
        if self._UpdateScrollThumb then self:_UpdateScrollThumb() end
        if self._BindVisibleRows then self:_BindVisibleRows() end
    end)

    scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
        local barH   = ResolveAppearance(windowID, "barHeight")  or 18
        local barGap = ResolveAppearance(windowID, "barSpacing") or 2
        local step   = (barH + barGap) * 2
        local cur    = sf:GetVerticalScroll() or 0
        local contentH = scrollContent:GetHeight()
        local viewH    = sf:GetHeight()
        local maxScroll = math.max(0, contentH - viewH)
        local newVal = math.max(0, math.min(maxScroll, cur - delta * step))
        sf:SetVerticalScroll(newVal)
        if self._UpdateStickyVisibility then self:_UpdateStickyVisibility() end
        if self._UpdateScrollThumb     then self:_UpdateScrollThumb()     end
        if self._BindVisibleRows       then self:_BindVisibleRows()       end
    end)

    local SCROLLBAR_WIDTH = 6
    local scrollBar = CreateFrame("Frame", nil, frame)
    scrollBar:SetWidth(SCROLLBAR_WIDTH)
    scrollBar:SetPoint("TOPRIGHT",    scrollFrame, "TOPRIGHT",    -1, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -1,  2)
    scrollBar:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    scrollBar:Hide()

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLLBAR_WIDTH)
    local ar, ag, ab = GetAccentColor()
    thumb:SetColorTexture(ar, ag, ab, 0.5)
    scrollBar.thumb = thumb

    self.scrollBar = scrollBar

    self.scrollFrame   = scrollFrame
    self.scrollContent = scrollContent

    self.stickyRow = self:_BuildStickyRow()

    local separator = self.frame:CreateTexture(nil, "OVERLAY")
    separator:SetHeight(1)
    separator:SetPoint("LEFT",   self.stickyRow, "TOPLEFT",  0, 0)
    separator:SetPoint("RIGHT",  self.stickyRow, "TOPRIGHT", 0, 0)
    separator:SetColorTexture(0, 0, 0, 1)
    separator:Hide()
    self.stickySeparator = separator

    self:_EnsureRowPool()
    self._breakdown = Breakdown.New(self)

    RegisterWithLayoutMode(self)

    return self
end

function Window:Hide() if self.frame then self.frame:Hide() end end
function Window:Show() if self.frame then self.frame:Show() end end
function Window:Destroy()
    local manager = QUI_DamageMeter.WindowManager
    if manager and manager.CloseBreakoutForOwner then manager:CloseBreakoutForOwner(self) end
    if self._breakdown and self._breakdown.Destroy then self._breakdown:Destroy() end
    if self.frame then self.frame:Hide(); self.frame:SetParent(nil) end
    self.frame, self.backdrop, self.header, self.rows = nil, nil, nil, {}
end

function Window:OpenBreakdown(source, anchorRow, isPreview)
    if not source then return false end
    isPreview = isPreview == true
    local inCombat = Data._inCombat or (InCombatLockdown and InCombatLockdown()) or false
    local isDeathRecap = DEATHS_TYPE ~= nil and self.damageMeterType == DEATHS_TYPE
    local deathRecapID = source.deathRecapID
    if isDeathRecap and (IsSecretValue(deathRecapID)
        or type(deathRecapID) ~= "number" or deathRecapID <= 0) then return false end

    local sourceGUID, sourceCreatureID
    if isDeathRecap then
        sourceGUID = nil
        sourceCreatureID = nil
    else
        sourceGUID, sourceCreatureID = Data:ResolveSourceSelector(
            source, self.sessionType, self.sessionID, inCombat)
    end
    local restricted = not isDeathRecap and sourceGUID == nil and sourceCreatureID == nil
    local opened
    if isPreview then
        if not self._breakdown then return false end
        opened = self._breakdown:Open(source, anchorRow, sourceGUID, sourceCreatureID, true, restricted)
    else
        local manager = QUI_DamageMeter.WindowManager
        opened = manager and manager.OpenBreakout
            and manager:OpenBreakout(self, source, sourceGUID, sourceCreatureID, restricted) or false
    end
    if not opened and isDeathRecap and not isPreview and type(OpenDeathRecapUI) == "function" then
        OpenDeathRecapUI(deathRecapID)
    end
    return opened
end

function Window:PreviewBreakdown(source, anchorRow)
    return self:OpenBreakdown(source, anchorRow, true)
end

function Window:ClosePreview(anchorRow)
    local breakdown = self._breakdown
    if not (breakdown and breakdown.isPreview and breakdown.anchorRow == anchorRow) then return end
    local function CloseIfOutside()
        if self._breakdown ~= breakdown or not breakdown.isPreview
            or breakdown.anchorRow ~= anchorRow then return end
        local anchorHovered = anchorRow and anchorRow.IsMouseOver and anchorRow:IsMouseOver()
        local frame = breakdown.frame
        local previewHovered = frame and frame.IsMouseOver and frame:IsMouseOver()
        if not anchorHovered and not previewHovered then breakdown:Close() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, CloseIfOutside)
    else
        CloseIfOutside()
    end
end

function Window:RefreshBreakdown()
end

Breakdown = {}
Breakdown.__index = Breakdown
QUI_DamageMeter.Breakdown = Breakdown
local BREAKDOWN_POOL_SIZE = 40
local PREVIEW_SPELL_LIMIT = 15
local PREVIEW_COMPACT_LIMIT = 8
local PREVIEW_TARGET_LIMIT = 3
local BREAKDOWN_MAX_HEIGHT = 420
local TARGET_POOL_SIZE    = 10
local TARGETS_LABEL_H     = 16

local function GetPreviewSpellLimit()
    local s = GetSettings()
    return s and s.showAllBreakdownSpells == false and PREVIEW_COMPACT_LIMIT or PREVIEW_SPELL_LIMIT
end
QUI_DamageMeter.GetPreviewSpellLimit = GetPreviewSpellLimit

local function GetDeathRecapRows(recapID)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return {}, 1 end
    local ok, rawEvents = ns.SafeCall("best-effort-style", C_DeathRecap.GetRecapEvents, recapID)
    if not ok or IsSecretValue(rawEvents) or type(rawEvents) ~= "table" then return {}, 1 end

    local maxHealth = 1
    if C_DeathRecap.GetRecapMaxHealth then
        local healthOK, health = ns.SafeCall("best-effort-style", C_DeathRecap.GetRecapMaxHealth, recapID)
        if healthOK and (IsSecretValue(health) or type(health) ~= "nil") then maxHealth = health end
    end
    if not IsSecretValue(maxHealth)
        and (type(maxHealth) ~= "number" or maxHealth <= 0) then maxHealth = 1 end

    local events = {}
    for i = #rawEvents, 1, -1 do
        local event = rawEvents[i]
        if not IsSecretValue(event) and type(event) == "table" then
            events[#events + 1] = event
        end
    end
    return events, maxHealth
end
QUI_DamageMeter.GetDeathRecapRows = GetDeathRecapRows

local function AnchorBreakdownTo(popup, row, anchorMode)
    popup.frame:ClearAllPoints()
    if anchorMode == "center" or not row then
        popup.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    local parentFrame = popup.parentWindow and popup.parentWindow.frame
    if anchorMode == "left" and parentFrame then
        popup.frame:SetPoint("TOPRIGHT", parentFrame, "TOPLEFT", -6, 0)
        return
    elseif anchorMode == "right" and parentFrame then
        popup.frame:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", 6, 0)
        return
    end
    popup.frame:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 0)
end

function Breakdown:_BuildRow(index)
    local barH = ResolveAppearance(self.parentWindowID, "barHeight") or 18
    local barGap = ResolveAppearance(self.parentWindowID, "barSpacing") or 2

    local row = CreateFrame("Button", nil, self.scrollContent)
    row:SetHeight(barH)
    row:SetPoint("LEFT",  self.scrollContent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", self.scrollContent, "RIGHT", 0, 0)
    if index == 1 then
        row:SetPoint("TOP", self.scrollContent, "TOP", 0, 0)
    else
        row:SetPoint("TOP", self.rows[index - 1], "BOTTOM", 0, -barGap)
    end

    AttachRowVisuals(row, barH)
    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("AnyUp") end
    row:SetScript("OnClick", function()
        if not self.isPreview then self:Close() end
    end)
    row:SetScript("OnEnter", function(rowSelf)
        local s = GetSettings()
        if s and s.showSpellTooltips == false then return end
        local spellID = rowSelf._spellID
        if IsSecretValue(spellID) or type(spellID) ~= "number" or spellID <= 0 then return end
        local info = ResolveSpellInfo(spellID)
        if not info or IsSecretValue(info.name) or GameTooltip:IsForbidden() then return end
        GameTooltip:SetOwner(rowSelf, "ANCHOR_LEFT")
        GameTooltip:SetSpellByID(spellID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(rowSelf)
        if not GameTooltip:IsForbidden()
            and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == rowSelf) then
            GameTooltip:Hide()
        end
    end)
    row:Hide()
    return row
end

function Breakdown:_BuildTargetRow(index)
    local barH = ResolveAppearance(self.parentWindowID, "barHeight") or 18
    local barGap = ResolveAppearance(self.parentWindowID, "barSpacing") or 2

    local row = CreateFrame("Button", nil, self.scrollContent)
    row:SetHeight(barH)
    row:SetPoint("LEFT",  self.scrollContent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", self.scrollContent, "RIGHT", 0, 0)
    if index == 1 then
        row:SetPoint("TOP", self.TargetsLabel, "BOTTOM", 0, -barGap)
    else
        row:SetPoint("TOP", self.targetRows[index - 1], "BOTTOM", 0, -barGap)
    end

    AttachRowVisuals(row, barH)
    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("AnyUp") end
    row:SetScript("OnClick", function()
        if not self.isPreview then self:Close() end
    end)
    row:Hide()
    return row
end

function Breakdown.New(parentWindow)
    local self = setmetatable({
        parentWindow    = parentWindow,
        parentWindowID  = parentWindow.windowID,
        source          = nil,
        rows            = {},
        _lastGeneration = -1,
    }, Breakdown)

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(240, 180)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function()
        if not self.isPreview then self:Close() end
    end)
    frame:SetScript("OnLeave", function()
        if self.isPreview then self.parentWindow:ClosePreview(self.anchorRow) end
    end)
    frame:Hide()
    self.frame = frame

    local bgTex = frame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(frame)
    local bg = ResolveAppearance(self.parentWindowID, "colors", "bg")
    if not bg then
        local _r, _g, _b = 0, 0, 0
        if Helpers and Helpers.GetSkinBgColor then
            _r, _g, _b = Helpers.GetSkinBgColor()
        end
        bg = { _r or 0, _g or 0, _b or 0, 0.85 }
    end
    local bdA = ResolveWindowBgAlpha(self.parentWindowID, bg)
    bgTex:SetColorTexture(bg[1], bg[2], bg[3], bdA)
    self.backdropTex = bgTex

    local headerH = ResolveAppearance(self.parentWindowID, "headerHeight") or 22
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(headerH)
    self.header = header

    self.TitleLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.TitleLabel:SetPoint("LEFT", header, "LEFT", 6, 0)
    self.TitleLabel:SetPoint("RIGHT", header, "RIGHT", -72, 0)
    self.TitleLabel:SetJustifyH("LEFT")
    self.TitleLabel:SetText("")

    self.ItemLevelLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.ItemLevelLabel:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    self.ItemLevelLabel:SetJustifyH("RIGHT")
    self.ItemLevelLabel:SetTextColor(0.75, 0.75, 0.75)
    self.ItemLevelLabel:SetText("")

    self.scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    self.scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    self.scrollFrame:EnableMouseWheel(true)

    self.scrollContent = CreateFrame("Frame", nil, self.scrollFrame)
    self.scrollContent:SetSize(frame:GetWidth(), 1)
    self.scrollFrame:SetScrollChild(self.scrollContent)
    self.scrollFrame:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then self.scrollContent:SetWidth(width) end
        self:_UpdateScrollRange()
    end)
    self.scrollFrame:SetScript("OnMouseWheel", function(scrollFrame, delta)
        local barH = ResolveAppearance(self.parentWindowID, "barHeight") or 18
        local barGap = ResolveAppearance(self.parentWindowID, "barSpacing") or 2
        local current = scrollFrame:GetVerticalScroll() or 0
        local nextOffset = math.max(0, math.min(self._maxScroll or 0,
            current - delta * (barH + barGap) * 2))
        scrollFrame:SetVerticalScroll(nextOffset)
    end)

    for i = 1, BREAKDOWN_POOL_SIZE do
        self.rows[i] = self:_BuildRow(i)
    end

    self.TargetsLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.TargetsLabel:SetJustifyH("LEFT")
    self.TargetsLabel:SetHeight(TARGETS_LABEL_H)
    self.TargetsLabel:SetText("")
    self.TargetsLabel:Hide()
    self.EmptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.EmptyLabel:SetPoint("TOP", self.scrollContent, "TOP", 0, -14)
    self.EmptyLabel:SetText(ns.L["No death recap available"])
    self.EmptyLabel:Hide()
    self.targetRows = {}
    for i = 1, TARGET_POOL_SIZE do
        self.targetRows[i] = self:_BuildTargetRow(i)
    end

    return self
end

function Breakdown:_UpdateScrollRange()
    local contentH = self.scrollContent:GetHeight() or 0
    local viewH = self.scrollFrame:GetHeight() or 0
    self._maxScroll = math.max(0, contentH - math.max(0, viewH))
    local scrollOffset = self.scrollFrame:GetVerticalScroll() or 0
    if scrollOffset > self._maxScroll then self.scrollFrame:SetVerticalScroll(self._maxScroll) end
end

function Breakdown:_SetSpellRow(row, spell, maxAmount, totalAmount)
    ApplyRowBackgroundVisibility(row, self.parentWindowID)
    row._spellID = spell.spellID

    if IsSecretValue(spell.spellID) and C_Spell and C_Spell.GetSpellTexture then
        row.Icon:SetTexture((C_Spell.GetSpellTexture(spell.spellID)))
    elseif spell.iconID and spell.iconID ~= 0 then
        row.Icon:SetTexture(spell.iconID)
    else
        row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local spellName = spell.name
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(spellName) then
        row.Name:SetFormattedText("%d. %s", spell.rank or 0, spellName) -- @secret-policy: sink-passthrough
    else
        row.Name:SetText((spell.rank or 0) .. ". " .. (spellName or "?"))
    end
    local IsSecret = Helpers and Helpers.IsSecretValue
    local numberFormat = ResolveAppearance(self.parentWindowID, "numberFormat") or "compact"
    local valueText = FormatNumber(spell.totalAmount, numberFormat)
    if not (IsSecret and (IsSecret(spell.totalAmount) or IsSecret(totalAmount)))
        and type(spell.totalAmount) == "number" and type(totalAmount) == "number"
        and totalAmount > 0 then
        valueText = string.format("%s  %.1f%%", valueText, spell.totalAmount / totalAmount * 100)
    end
    row.Value:SetText(valueText)

    local fillMin, fillMaxValue, fillValue = ComputeBarFill(nil, spell, maxAmount, nil, IsSecret)
    row.Bar:SetMinMaxValues(fillMin, fillMaxValue)
    row.Bar:SetValue(fillValue)

    local alpha = ResolveAppearance(self.parentWindowID, "barFillAlpha") or 1
    if ResolveAppearance(self.parentWindowID, "barColorAccent") then
        local ar, ag, ab = GetAccentColor()
        row.Bar:SetStatusBarColor(ar, ag, ab, alpha)
    else
        local bc = ResolveAppearance(self.parentWindowID, "barColor") or { 0.35, 0.55, 0.8, 1 }
        row.Bar:SetStatusBarColor(bc[1] or 0.35, bc[2] or 0.55, bc[3] or 0.8, alpha)
    end
end

local ENVIRONMENTAL_DEATH_ICONS = {
    DROWNING = "Interface\\Icons\\spell_shadow_demonbreath",
    FALLING = "Interface\\Icons\\ability_rogue_quickrecovery",
    FIRE = "Interface\\Icons\\spell_fire_fire",
    LAVA = "Interface\\Icons\\spell_fire_fire",
    SLIME = "Interface\\Icons\\inv_misc_slime_01",
    FATIGUE = "Interface\\Icons\\ability_creature_cursed_05",
}
local DEFAULT_ENVIRONMENTAL_DEATH_ICON = "Interface\\Icons\\ability_creature_cursed_05"

local function ResolveDeathEventInfo(event)
    local eventType = event.event
    if not IsSecretValue(eventType) and eventType == "SWING_DAMAGE" then
        local spellID = 88163
        local iconID = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
        return spellID, _G.ACTION_SWING or "Melee", iconID
    end
    if not IsSecretValue(eventType) and eventType == "ENVIRONMENTAL_DAMAGE" then
        local environmentalType = event.environmentalType
        if IsSecretValue(environmentalType) or type(environmentalType) ~= "string" then
            return nil, "Environmental", DEFAULT_ENVIRONMENTAL_DEATH_ICON
        end
        environmentalType = string.upper(environmentalType)
        return nil, _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. environmentalType] or environmentalType,
            ENVIRONMENTAL_DEATH_ICONS[environmentalType] or DEFAULT_ENVIRONMENTAL_DEATH_ICON
    end
    return event.spellId, event.spellName
end

function Breakdown:_SetDeathRow(row, event, maxHealth, deathTime)
    ApplyRowBackgroundVisibility(row, self.parentWindowID)

    local spellID, spellName, iconID = ResolveDeathEventInfo(event)
    row._spellID = spellID
    local info
    if not iconID then
        if IsSecretValue(spellID) and C_Spell and C_Spell.GetSpellTexture then
            iconID = C_Spell.GetSpellTexture(spellID)
        elseif type(spellID) == "number" and spellID > 0 then
            info = ResolveSpellInfo(spellID)
            iconID = info and info.iconID
        end
    end
    row.Icon:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local eventType = event.event
    local eventTypeSecret = IsSecretValue(eventType)
    local isHeal = false
    if not eventTypeSecret then
        isHeal = eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL"
    end

    if not IsSecretValue(spellName)
        and (type(spellName) ~= "string" or spellName == "") then
        if isHeal then
            spellName = "Heal"
        else
            spellName = (info and info.name) or "Unknown"
        end
    end

    local timestamp = event.timestamp
    local timeBeforeDeath
    if not IsSecretValue(timestamp) and not IsSecretValue(deathTime)
        and type(timestamp) == "number" and type(deathTime) == "number" then
        timeBeforeDeath = deathTime - timestamp
    end
    if timeBeforeDeath ~= nil then
        row.Name:SetFormattedText("-%.1fs %s", timeBeforeDeath, spellName)
    else
        row.Name:SetFormattedText("%s", spellName)
    end

    local currentHP = event.currentHP
    if not IsSecretValue(currentHP) and type(currentHP) ~= "number" then currentHP = 0 end
    local hpPercent
    if not IsSecretValue(currentHP) and not IsSecretValue(maxHealth)
        and type(currentHP) == "number" and type(maxHealth) == "number" and maxHealth > 0 then
        hpPercent = math.max(0, math.min(1, currentHP / maxHealth))
    end
    if hpPercent ~= nil then
        row.Bar:SetMinMaxValues(0, 1)
        row.Bar:SetValue(hpPercent)
    else
        row.Bar:SetMinMaxValues(0, maxHealth)
        row.Bar:SetValue(currentHP)
    end

    local amount = event.amount
    if not IsSecretValue(amount) and type(amount) ~= "number" then amount = 0 end
    local numberFormat = ResolveAppearance(self.parentWindowID, "numberFormat") or "compact"
    local amountText = FormatNumber(amount, numberFormat)
    if IsSecretValue(amount) then
        if hpPercent ~= nil then
            row.Value:SetFormattedText("%s (%.0f%%)", amountText, hpPercent * 100)
        else
            row.Value:SetText(amountText)
        end
    else
        amountText = (isHeal and "+" or "-") .. FormatNumber(math.abs(amount), numberFormat)
        local overkill = event.overkill
        if not isHeal and not IsSecretValue(overkill)
            and type(overkill) == "number" and overkill > 0 then
            amountText = amountText .. " (" .. FormatNumber(overkill, numberFormat) .. " overkill)"
        end
        if hpPercent ~= nil then amountText = amountText .. string.format(" (%.0f%%)", hpPercent * 100) end
        row.Value:SetText(amountText)
    end

    local alpha = ResolveAppearance(self.parentWindowID, "barFillAlpha") or 1
    if isHeal then
        row.Bar:SetStatusBarColor(0.10, 0.50, 0.10, alpha)
    else
        row.Bar:SetStatusBarColor(0.60, 0.08, 0.08, alpha)
    end
end

function Breakdown:_SetTargetRow(row, target, maxAmount)
    ApplyRowBackgroundVisibility(row, self.parentWindowID)
    row._target = target

    if target.specIconID and target.specIconID ~= 0 then
        row.Icon:SetTexture(target.specIconID)
        row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif target.classFilename and CLASS_ICON_TCOORDS then
        row.Icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        local coords = CLASS_ICON_TCOORDS[target.classFilename]
        if coords then
            row.Icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    else
        row.Icon:SetTexture(nil)
    end

    local IsSecret = Helpers and Helpers.IsSecretValue
    local targetName = ShortenName(target.name)
    if IsSecret and IsSecret(targetName) then
        row.Name:SetText(targetName) -- @secret-policy: sink-passthrough
    else
        row.Name:SetText(targetName or "?")
    end
    local numberFormat = ResolveAppearance(self.parentWindowID, "numberFormat") or "compact"
    local primaryVal, secondaryVal
    if IsPerSecondType(self.parentWindow.damageMeterType) then
        primaryVal, secondaryVal = target.amountPerSecond, target.totalAmount
    else
        primaryVal, secondaryVal = target.totalAmount, target.amountPerSecond
    end
    if ResolveAppearance(self.parentWindowID, "showSecondaryValue") == false then
        secondaryVal = nil
    end
    row.Value:SetText(BuildValueText(primaryVal, secondaryVal, numberFormat,
        Helpers and Helpers.IsSecretValue, FormatNumber))

    local fillMin, fillMaxValue, fillValue = ComputeBarFill(nil, target, maxAmount, nil, IsSecret)
    row.Bar:SetMinMaxValues(fillMin, fillMaxValue)
    row.Bar:SetValue(fillValue)

    local alpha = ResolveAppearance(self.parentWindowID, "barFillAlpha") or 1
    if target.classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[target.classFilename] then
        local c = Helpers.GetClassColorTable(target.classFilename)
        row.Bar:SetStatusBarColor(c.r, c.g, c.b, alpha)
    elseif ResolveAppearance(self.parentWindowID, "barColorAccent") then
        local ar, ag, ab = GetAccentColor()
        row.Bar:SetStatusBarColor(ar, ag, ab, alpha)
    else
        local bc = ResolveAppearance(self.parentWindowID, "barColor") or { 0.35, 0.55, 0.8, 1 }
        row.Bar:SetStatusBarColor(bc[1] or 0.35, bc[2] or 0.55, bc[3] or 0.8, alpha)
    end
end

function Breakdown:_UpdateTitle()
    local label = LabelForType(self.parentWindow.damageMeterType)
    local titleName = ShortenName(self.source.name)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(titleName) then
        self.TitleLabel:SetFormattedText("%s by %s", label, titleName) -- @secret-policy: sink-passthrough
    else
        self.TitleLabel:SetText(label .. " by " .. (titleName or "?"))
    end

    local itemLevel
    local inspect = self.isPreview and ns.TooltipInspect
    if inspect and inspect.GetPlayerDataByGUID and self.sourceGUID ~= nil
        and not IsSecretValue(self.sourceGUID) then
        local playerData = inspect:GetPlayerDataByGUID(self.sourceGUID)
        local value = playerData and playerData.itemLevel
        if not IsSecretValue(value) then itemLevel = tonumber(value) end
    end
    self.ItemLevelLabel:SetText(itemLevel and string.format(
        "%s %.1f", _G.ITEM_LEVEL_ABBR or "iLvl", itemLevel) or "")
end

function Breakdown:_ResolveTargets(meterType)
    local T = Enum and Enum.DamageMeterType
    if not (T and self.source) then return nil, nil end
    if InCombatLockdown and InCombatLockdown() then return nil, nil end
    local st = self.parentWindow.sessionType
    local sid = self.parentWindow.sessionID
    if meterType == T.EnemyDamageTaken then
        return Data:GetEnemyAttackers(st, self.sourceGUID, self.sourceCreatureID, sid), ns.L["Attacked By"]
    elseif meterType == T.DamageDone or meterType == T.Dps then
        return Data:GetPlayerTargets(st, self.source.name, sid), ns.L["Targets"]
    end
    return nil, nil
end

function Breakdown:Refresh()
    if not self.source or not self.frame:IsShown() then return false end
    local _t0 = Perf.enabled and PerfNow() or 0
    local sessionType   = self.parentWindow.sessionType
    local sessionID = self.parentWindow.sessionID
    local damageMeterType = self.parentWindow.damageMeterType

    self:_UpdateTitle()

    local visibleCount = 0
    local targetCount = 0
    local barH    = ResolveAppearance(self.parentWindowID, "barHeight") or 18
    local barGap  = ResolveAppearance(self.parentWindowID, "barSpacing") or 2
    local headerH = ResolveAppearance(self.parentWindowID, "headerHeight") or 22
    local isDeathRecap = DEATHS_TYPE ~= nil and damageMeterType == DEATHS_TYPE
    local enemyType = EnemyDamageTakenType()
    local isEnemyAttackers = enemyType ~= nil and damageMeterType == enemyType
    local primaryLimit = self.isPreview and GetPreviewSpellLimit() or BREAKDOWN_POOL_SIZE
    self.EmptyLabel:Hide()

    if self.restricted then
        self.EmptyLabel:SetText(ns.L["Breakdown unavailable during combat"])
        self.EmptyLabel:Show()
        self.scrollContent:SetHeight(40)
        for i = 1, #self.rows do self.rows[i]:Hide() end
        self.TargetsLabel:Hide()
        for i = 1, #self.targetRows do self.targetRows[i]:Hide() end
        if self.isPreview then self.frame:SetHeight(headerH + 40) end
        self:_UpdateScrollRange()
        return true
    end

    if isDeathRecap then
        local events, maxHealth = GetDeathRecapRows(self.source.deathRecapID)
        visibleCount = math.min(#events, primaryLimit)
        local deathEvent = events[#events]
        local deathTime = deathEvent and deathEvent.timestamp
        local firstEvent = self.isPreview and math.max(1, #events - visibleCount + 1) or 1
        for i = 1, visibleCount do
            self:_SetDeathRow(self.rows[i], events[firstEvent + i - 1], maxHealth, deathTime)
            self.rows[i]:Show()
        end
    elseif isEnemyAttackers then
        local attackers = Data:GetEnemyAttackers(sessionType,
            self.sourceGUID, self.sourceCreatureID, sessionID)
        visibleCount = math.min(#attackers, primaryLimit)
        local maxAmount = visibleCount > 0 and attackers[1].totalAmount or 1
        for i = 1, visibleCount do
            self.rows[i]._spellID = nil
            self:_SetTargetRow(self.rows[i], attackers[i], maxAmount)
            self.rows[i]:Show()
        end
    else
        local view
        local s_combo = GetSettings()
        if IsHealingType(damageMeterType)
            and s_combo and s_combo.combineAbsorbsIntoHealing then
            view = Data:GetCombinedHealingBreakdown(sessionType,
                self.sourceGUID, self.sourceCreatureID, sessionID)
        else
            view = Data:GetBreakdownView(sessionType, damageMeterType,
                self.sourceGUID, self.sourceCreatureID, sessionID)
        end

        visibleCount = math.min(#view.spells, primaryLimit)
        for i = 1, visibleCount do
            self:_SetSpellRow(self.rows[i], view.spells[i], view.maxAmount, view.totalAmount)
            self.rows[i]:Show()
        end

        local targets, targetsLabel = self:_ResolveTargets(damageMeterType)
        if targets and #targets > 0 and targetsLabel then
            local targetLimit = self.isPreview and PREVIEW_TARGET_LIMIT
                or math.min(TARGET_POOL_SIZE, math.max(0, BREAKDOWN_POOL_SIZE - visibleCount))
            targetCount = math.min(#targets, targetLimit)
        end
        if targetCount > 0 then
            self.TargetsLabel:ClearAllPoints()
            if visibleCount > 0 then
                self.TargetsLabel:SetPoint("TOPLEFT", self.rows[visibleCount], "BOTTOMLEFT", 6, -barGap)
            else
                self.TargetsLabel:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 6, 0)
            end
            self.TargetsLabel:SetText(targetsLabel)
            self.TargetsLabel:Show()
            local tMax = targets[1].totalAmount
            for i = 1, targetCount do
                self:_SetTargetRow(self.targetRows[i], targets[i], tMax)
                self.targetRows[i]:Show()
            end
            for i = targetCount + 1, #self.targetRows do self.targetRows[i]:Hide() end
        end
    end
    for i = visibleCount + 1, #self.rows do
        self.rows[i]._spellID = nil
        self.rows[i]:Hide()
    end

    if isDeathRecap or isEnemyAttackers or targetCount == 0 then
        self.TargetsLabel:Hide()
        for i = 1, #self.targetRows do self.targetRows[i]:Hide() end
    end

    local emptyDeathPreview = isDeathRecap and self.isPreview and visibleCount == 0
    if emptyDeathPreview then self.EmptyLabel:Show() end
    local spellBlock  = visibleCount > 0 and (visibleCount * barH + (visibleCount - 1) * barGap)
        or (emptyDeathPreview and 40 or 0)
    local targetBlock = targetCount > 0
        and (TARGETS_LABEL_H + barGap + targetCount * barH + (targetCount - 1) * barGap) or 0
    local contentH = 0
    if visibleCount > 0 and targetCount > 0 then
        contentH = spellBlock + barGap + targetBlock + barGap
    elseif visibleCount > 0 or emptyDeathPreview then
        contentH = spellBlock + barGap
    elseif targetCount > 0 then
        contentH = targetBlock + barGap
    end
    self.scrollContent:SetHeight(math.max(1, contentH))
    if self.isPreview then
        local totalH = math.min(headerH + contentH, BREAKDOWN_MAX_HEIGHT)
        self.frame:SetHeight(math.max(headerH, totalH))
    end
    self:_UpdateScrollRange()

    if Perf.enabled then Perf:Record("breakdown", PerfNow() - _t0) end
    return visibleCount > 0 or targetCount > 0 or emptyDeathPreview
end

function Breakdown:Open(source, anchorRow, sourceGUID, sourceCreatureID, isPreview, restricted)
    self.source = source
    self.sourceGUID = sourceGUID
    self.sourceCreatureID = sourceCreatureID
    self.isPreview = isPreview == true
    self.restricted = restricted == true
    self.anchorRow = anchorRow
    self.scrollFrame:SetVerticalScroll(0)
    local settings = GetSettings()
    local anchorMode = (settings and settings.breakdownAnchor) or "row"
    local scale = math.max(0.5, math.min(1.5,
        (tonumber(settings and settings.hoverTooltipScale) or 100) / 100))
    self.frame:SetScale(scale)
    self.header:Show()
    self.backdropTex:Show()
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, 0)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
    self.frame:SetParent(UIParent)
    self.frame:SetFrameStrata("HIGH")
    self.frame:SetWidth(240)
    AnchorBreakdownTo(self, anchorRow, anchorMode)
    self.frame:Show()
    local hasContent = self:Refresh()
    local isDeathRecap = DEATHS_TYPE ~= nil
        and self.parentWindow.damageMeterType == DEATHS_TYPE
    if not hasContent and (self.isPreview or isDeathRecap) then
        self:Close()
        return false
    end
    return true
end

function Breakdown:Close()
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if owner then
        for i = 1, #self.rows do
            if owner == self.rows[i] then
                if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
                break
            end
        end
    end
    self.frame:Hide()
    self.source = nil
    self.sourceGUID = nil
    self.sourceCreatureID = nil
    self.isPreview = nil
    self.restricted = nil
    self.anchorRow = nil
    self._maxScroll = 0
end

function Breakdown:Destroy()
    self:Close()
    self.frame:SetParent(nil)
    self.frame = nil
end

function Breakdown:IsOpen()
    return self.frame and self.frame:IsShown() or false
end

local WindowManager = {
    windows = {},
    nextID  = 1,
}
QUI_DamageMeter.WindowManager = WindowManager

function WindowManager:Get(windowID)
    return self.windows[windowID]
end

function WindowManager:Enumerate(fn)
    for windowID, w in pairs(self.windows) do
        fn(windowID, w)
    end
end

local function ApplySessionToWindow(window, windowState, sessionType, sessionID, sessionLabel)
    if sessionID ~= nil then
        window.sessionType = nil
    else
        window.sessionType = sessionType
        windowState.sessionType = sessionType
    end
    window.sessionID = sessionID
    window.sessionLabel = sessionID ~= nil and sessionLabel or nil
    window._lastGeneration = -1
    if window._breakdown and window._breakdown.Close then window._breakdown:Close() end
end

function WindowManager:ApplySessionSelection(window, sessionType, sessionID, sessionLabel)
    local s = GetSettings()
    local windows = s and s.windows
    local windowState = windows and window and windows[window.windowID]
    if not windowState then return end
    if windowState.syncSegments then
        self:Enumerate(function(windowID, candidate)
            local candidateState = windows[windowID]
            if candidateState and candidateState.syncSegments then
                ApplySessionToWindow(candidate, candidateState, sessionType, sessionID, sessionLabel)
            end
        end)
    else
        ApplySessionToWindow(window, windowState, sessionType, sessionID, sessionLabel)
    end
    self:RefreshAll()
end

function WindowManager:AutoCurrentOnCombat()
    local s = GetSettings()
    local windows = s and s.windows
    if not windows then return end
    local S = Enum and Enum.DamageMeterSessionType
    local currentSession = (S and S.Current) or 1
    local changed = false
    self:Enumerate(function(windowID, window)
        local windowState = windows[windowID]
        if window.sessionID ~= nil and windowState and windowState.autoCurrentOnCombat then
            ApplySessionToWindow(window, windowState, currentSession, nil)
            changed = true
        end
    end)
    if changed then self:RefreshAll() end
end

function WindowManager:Spawn(windowID)
    if self.windows[windowID] then return self.windows[windowID] end
    if not Window.New then return nil end
    local instance = Window.New(windowID)
    self.windows[windowID] = instance
    if windowID >= self.nextID then self.nextID = windowID + 1 end
    return instance
end

function WindowManager:Despawn(windowID)
    local instance = self.windows[windowID]
    if not instance then return end
    if self.CloseBreakoutForOwner then self:CloseBreakoutForOwner(instance) end
    if instance.Hide then instance:Hide() end
    if instance.Destroy then instance:Destroy() end
    self.windows[windowID] = nil

    local key = LayoutKey(windowID)
    if ns.QUI_LayoutMode and ns.QUI_LayoutMode.UnregisterElement then
        ns.QUI_LayoutMode.UnregisterElement(ns.QUI_LayoutMode, key)
    end
    if _G.QUI_UnregisterFrameResolver then
        _G.QUI_UnregisterFrameResolver(key)
    end
    local Registry = ns.Settings and ns.Settings.Registry
    if Registry and type(Registry.UnregisterLookupKey) == "function" then
        Registry:UnregisterLookupKey(WINDOW_LAYOUT_FEATURE_ID, key)
    end
end

function WindowManager:DespawnAll()
    if self.CloseBreakout then self:CloseBreakout() end
    local ids = {}
    for windowID in pairs(self.windows) do
        ids[#ids + 1] = windowID
    end
    for _, windowID in ipairs(ids) do
        self:Despawn(windowID)
    end
end

function WindowManager:ClearRuntimeSessionIDs()
    QUI_DamageMeter.BumpAppearanceRevision()
    local s = GetSettings()
    if self.CloseBreakout then self:CloseBreakout() end
    self:Enumerate(function(_windowID, w)
        if w then
            w.sessionID = nil
            if w.sessionType == nil then
                local windowState = s and s.windows and s.windows[w.windowID]
                w.sessionType = (windowState and windowState.sessionType) or 1
            end
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then
                w._breakdown:Close()
            end
        end
    end)
end

local MAX_WINDOWS = 5

function WindowManager:Count()
    local n = 0
    for _ in pairs(self.windows) do n = n + 1 end
    return n
end

function WindowManager:CanSpawnNew()
    return self:Count() < MAX_WINDOWS
end

function WindowManager:SpawnNew()
    if self:Count() >= MAX_WINDOWS then return nil end
    local s = GetSettings()
    if not s then return nil end
    s.windows = s.windows or {}
    local newID = 2
    while s.windows[newID] do newID = newID + 1 end
    s.windows[newID] = {
        damageMeterType = 0,
        sessionType     = 1,
        size            = { w = 240, h = 180 },
        hidden          = false,
        name            = "",
        autoCurrentOnCombat = false,
        syncSegments = false,
        autoSwapChallengeSessions = false,
        mythicStartDMType = false,
        hideTimer = false,
    }
    s.windowCount = (s.windowCount or 0) + 1

    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    local profile = core and core.db and core.db.profile
    if profile then
        if type(profile.frameAnchoring) ~= "table" then
            profile.frameAnchoring = {}
        end
        local key = LayoutKey(newID)
        if not profile.frameAnchoring[key] then
            profile.frameAnchoring[key] = {
                parent   = "screen",
                point    = "CENTER",
                relative = "CENTER",
                offsetX  = 20 * newID,
                offsetY  = -20 * newID,
            }
        end
    end

    local w = self:Spawn(newID)
    if w and w.Refresh then w:Refresh() end
    return newID
end

function WindowManager:DeleteWindow(windowID)
    self:Despawn(windowID)
    local s = GetSettings()
    if s and s.windows then
        s.windows[windowID] = nil
        s.windowCount = math.max(0, (s.windowCount or 1) - 1)
    end
    local app = s and s.appearance
    if app and app.perWindow then
        app.perWindow[windowID] = nil
    end
end

function WindowManager:LoadSavedWindows()
    local s = GetSettings()
    if not (s and s.windows) then return 0 end
    local spawned = 0
    for windowID in pairs(s.windows) do
        if type(windowID) == "number" then
            local w = self:Spawn(windowID)
            if w then
                if w.Refresh then w:Refresh() end
                spawned = spawned + 1
            end
        end
    end
    return spawned
end

function WindowManager:RefreshAll()
    QUI_DamageMeter.BumpAppearanceRevision()
    for _, w in pairs(self.windows) do
        if w then
            w._lastGeneration = -1
            if w.Refresh then w:Refresh() end
        end
    end
    if self.RefreshBreakout then self:RefreshBreakout() end
end

local function ResetAllDamageMeterSessions()
    if not (C_DamageMeter and C_DamageMeter.ResetAllCombatSessions) then return false end
    C_DamageMeter.ResetAllCombatSessions()
    Data:ResetCombatClock()
    Data:ClearCachedViews()
    Data:ClearSourceGUIDCache()
    if WindowManager.ClearRuntimeSessionIDs then
        WindowManager:ClearRuntimeSessionIDs()
    end
    WindowManager:RefreshAll()
    return true
end

function WindowManager:ApplyChallengeModeStart()
    local s = GetSettings()
    if not s then return end

    if s.autoResetOnChallengeStart ~= false then
        ResetAllDamageMeterSessions()
    end

    local S = Enum and Enum.DamageMeterSessionType
    local currentSession = (S and S.Current) or 1
    local overallSession = (S and S.Overall) or 0
    local changed = false

    self:Enumerate(function(_windowID, w)
        local windowState = w and s.windows and s.windows[w.windowID]
        if not windowState then return end
        local autoSwap = ResolveWindowAutoSwap(windowState, s)
        if autoSwap and w.sessionID == nil and w.sessionType == overallSession then
            w.sessionType = currentSession
            windowState.sessionType = currentSession
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then
                w._breakdown:Close()
            end
            changed = true
        end
        if windowState.mythicStartDMType then
            w.damageMeterType = windowState.mythicStartDMType
            windowState.damageMeterType = windowState.mythicStartDMType
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then w._breakdown:Close() end
            changed = true
        end
    end)
    if changed then self:RefreshAll() end
end

function WindowManager:ApplyChallengeModeCompleted()
    local s = GetSettings()
    if not s then return end
    local S = Enum and Enum.DamageMeterSessionType
    local currentSession = (S and S.Current) or 1
    local overallSession = (S and S.Overall) or 0
    local changed = false

    self:Enumerate(function(_windowID, w)
        local windowState = w and s.windows and s.windows[w.windowID]
        if not windowState then return end
        local autoSwap = ResolveWindowAutoSwap(windowState, s)
        if autoSwap and w.sessionID == nil and w.sessionType == currentSession then
            w.sessionType = overallSession
            windowState.sessionType = overallSession
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then
                w._breakdown:Close()
            end
            changed = true
        end
    end)
    if changed then self:RefreshAll() end
end

function WindowManager:ApplyChallengeModeReset()
    self:ApplyChallengeModeCompleted()
end

local challengeModeFrame = CreateFrame("Frame")
challengeModeFrame:RegisterEvent("CHALLENGE_MODE_START")
challengeModeFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
challengeModeFrame:RegisterEvent("CHALLENGE_MODE_RESET")
challengeModeFrame:SetScript("OnEvent", function(_, event)
    if event == "CHALLENGE_MODE_START" then
        WindowManager:ApplyChallengeModeStart()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        WindowManager:ApplyChallengeModeCompleted()
    elseif event == "CHALLENGE_MODE_RESET" then
        WindowManager:ApplyChallengeModeReset()
    end
end)

Data._onChange = function(self)
    local clearRuntimeSessions = self._clearRuntimeSessions
    self._clearRuntimeSessions = false
    if clearRuntimeSessions and WindowManager.ClearRuntimeSessionIDs then
        WindowManager:ClearRuntimeSessionIDs()
    end
    WindowManager:Enumerate(function(_id, w)
        if w.Refresh then w:Refresh() end
    end)
    if WindowManager.RefreshBreakout then WindowManager:RefreshBreakout() end
end

Data._onCombatStart = function()
    WindowManager:AutoCurrentOnCombat()
end

local pendingCombatWrites = {}

local function QueueOrRun(fn)
    if InCombatLockdown and InCombatLockdown() then
        pendingCombatWrites[#pendingCombatWrites + 1] = fn
    else
        fn()
    end
end

local lockdownFrame = CreateFrame("Frame")
lockdownFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
lockdownFrame:SetScript("OnEvent", function()
    if #pendingCombatWrites == 0 then return end
    local q = pendingCombatWrites
    pendingCombatWrites = {}
    for _, fn in ipairs(q) do fn() end
end)
QUI_DamageMeter._QueueOrRun = QueueOrRun

local function ApplyBlizzardSuppression(enabled)
    if SetCVar then
        SetCVar("damageMeterEnabled", enabled and "0" or "1")
    end
    if enabled and _G.DamageMeter and _G.DamageMeter.Hide then
        _G.DamageMeter:Hide()
    end
end
QUI_DamageMeter.ApplyBlizzardSuppression = ApplyBlizzardSuppression

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        local s = GetSettings()
        if not s then return end
        ApplyBlizzardSuppression(true)
        QueueOrRun(function()
            WindowManager:LoadSavedWindows()
        end)
    end)
end

_G.BINDING_HEADER_QUI_DAMAGEMETER = ns.L["QUI Damage Meter"]
_G["BINDING_NAME_CLICK QUI_DM_ResetBindingTarget:LeftButton"] = ns.L["Reset All Sessions"]

local resetBindBtn = CreateFrame("Button", "QUI_DM_ResetBindingTarget", UIParent, "SecureActionButtonTemplate")
resetBindBtn:Hide()
resetBindBtn:SetAttribute("type", "macro")
resetBindBtn:SetAttribute("macrotext",
    "/run if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then C_DamageMeter.ResetAllCombatSessions() end")
QUI_DamageMeter._ResetBindButton = resetBindBtn

_G.SLASH_QUI_DM_RESET1 = "/quidmreset"
_G.SlashCmdList["QUI_DM_RESET"] = function()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
        print(ns.L["|cff30D1FF[QUI]|r Damage meter sessions reset."])
    end
end

_G.SLASH_QUI_DM_PERF1 = "/quidmperf"
_G.SlashCmdList["QUI_DM_PERF"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "on" then
        Perf.enabled = true
        Perf:Reset()
        print(ns.L["|cff30D1FF[QUI]|r Damage meter perf instrumentation: |cff00ff00ON|r"])
    elseif msg == "off" then
        Perf.enabled = false
        print(ns.L["|cff30D1FF[QUI]|r Damage meter perf instrumentation: |cffff6060OFF|r"])
    elseif msg == "reset" then
        Perf:Reset()
        print(ns.L["|cff30D1FF[QUI]|r Damage meter perf buffers reset."])
    else
        if not Perf.enabled then
            print(ns.L["|cff30D1FF[QUI]|r Perf is OFF. Run |cffffffff/quidmperf on|r to enable, then re-run to see the summary."])
            return
        end
        print(ns.L["|cff30D1FF[QUI]|r Damage meter perf summary:"])
        for _, line in ipairs(Perf:Summary()) do print(line) end
    end
end

if ns.Registry then
    ns.Registry:Register("damageMeterSkin", {
        refresh = function()
            if WindowManager and WindowManager.RefreshAll then
                WindowManager:RefreshAll()
            end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme", "damageMeter" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "damageMeter",
        label = ns.L["Damage Meter"],
        category = "HUD",
        prefix = "",
        db = function(p)
            local native = p and p.damageMeter and p.damageMeter.native
            local app = native and native.appearance and native.appearance.global
            return EnsureDamageMeterBorderSettings(app)
        end,
        refresh = function()
            if WindowManager and WindowManager.RefreshAll then
                WindowManager:RefreshAll()
            end
        end,
        legacy = {},
    })
end
