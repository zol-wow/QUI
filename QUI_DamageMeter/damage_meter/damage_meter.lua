--[[
    QUI Damage Meter — native module (Phases 1–8).

    Phase 1 establishes the core: data subscription, throttled ticker,
    a single hard-coded window (DamageDone / Current), Layout Mode
    integration, and Blizzard meter suppression. Subsequent phases add
    appearance settings + meter types (Phase 2), multi-window (Phase 3),
    breakdown popup (Phase 4), then retire the skinner (Phase 5) and
    add spell history / standalone timer / animations (Phases 6–8).

    Design: docs/superpowers/specs/2026-05-22-damage-meter-design.md
    Phase 1 plan: docs/superpowers/plans/2026-05-22-damage-meter-phase-1.md
]]

-- luacheck: globals CreateFrame C_DamageMeter UIParent RAID_CLASS_COLORS CLASS_ICON_TCOORDS _G SetCVar InCombatLockdown C_StringUtil GetTime Enum MenuUtil GameTooltip SlashCmdList GetTimePreciseSec C_Spell C_Timer AbbreviateNumbers BreakUpLargeNumbers CreateAbbreviateConfig Ambiguate
local _, ns = ...

-- ns.Helpers is provided by core/utils.lua (loaded before this module via QUI.toc).
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local QUI_DamageMeter = {}
ns.QUI_DamageMeter = QUI_DamageMeter

-- ==== Perf instrumentation (Follow-up D) ====
-- Disabled by default — wrapping every Refresh in GetTimePreciseSec calls is
-- cheap but not free. Toggle via /quidmperf on (and /quidmperf for the
-- summary). Samples land in a fixed-size ring buffer per kind.
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

-- Returns avg, p95, max (all in seconds; caller converts to ms for display).
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

-- Cheap "is timing available?" probe. GetTimePreciseSec is the high-res
-- timer; falls back to debugprofilestop on older clients.
local function PerfNow()
    if GetTimePreciseSec then return GetTimePreciseSec() end
    return 0
end

-- ==== Settings ====
-- Phase 1 read accessors only. Defaults live in core/defaults.lua (T3).
local function GetSettings()
    local QUI = _G.QUI
    if not (QUI and QUI.db and QUI.db.profile and QUI.db.profile.damageMeter) then
        return nil
    end
    return QUI.db.profile.damageMeter.native
end

-- Strip the "-Realm" suffix from a unit name when the shortenNames setting is
-- on (e.g. "Anya-Stormrage" -> "Anya"). Ambiguate is a C function that's safe
-- to call on a secret-tagged name (the API marks source.name ConditionalSecret)
-- — it passes through anything it can't read, and the value still goes straight
-- to a FontString. We never compare or concatenate the result against a secret
-- here, so the only Lua-side touch is the C call. Returns nil for nil input so
-- callers keep their own "?" / "Unknown" fallback.
local function ShortenName(name)
    if name == nil then return nil end
    local s = GetSettings()
    if s and s.shortenNames and Ambiguate then
        return Ambiguate(name, "short") or name
    end
    return name
end
QUI_DamageMeter.ShortenName = ShortenName

-- Sort `list` in place, descending by the key returned from `keyFn` — but ONLY
-- when every key is comparable. table.sort must never be handed a comparator
-- that can return false for *every* pair: under such a degenerate comparator
-- Lua's quicksort reorders the array instead of leaving it untouched, which
-- scrambles an already-sorted list (high values land mid-list or at the
-- bottom). During combat the C_DamageMeter amounts are secret-tagged, so the
-- old "return false when secret" comparators degenerated exactly that way and
-- the meter rendered out of order. The API already returns combatSources sorted
-- by amount on the C side (where secrets are readable), so when any key is
-- secret we skip the Lua sort and keep that order. `isSecret` is injected so
-- this stays unit-testable under plain Lua.
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

-- `or 0` only short-circuits on nil; a secret-tagged number is truthy and
-- would taint the `+`. Substitute 0 when the value is secret so the returned
-- total stays a plain number (per-source bars carry secrets through for
-- display). Shared by GetCombinedHealingView / GetCombinedHealingBreakdown.
local function SafeNumOrZero(v, isSecret)
    if v == nil then return 0 end
    if isSecret and isSecret(v) then return 0 end
    return v
end

-- Re-rank a merged list in place and return the max plain (non-secret)
-- totalAmount. Shared post-merge step of the combined-healing functions.
local function RankAndMaxAmount(list, isSecret)
    local maxAmount = 0
    for i, s in ipairs(list) do
        s.rank = i
        local v = s.totalAmount
        if v and not (isSecret and isSecret(v)) and v > maxAmount then maxAmount = v end
    end
    return maxAmount
end

-- ==== Data ====
local Data = {}
QUI_DamageMeter.Data = Data

-- Dirty flags: Data._dirty[selectorKey][damageMeterType] = true means the
-- cached view for that selector/type is stale and the next ticker pass
-- should re-fetch via C_DamageMeter (T6). Event handlers only set flags;
-- they never call C_DamageMeter inline.
Data._dirty = {}
Data._allDirty = false   -- set by DAMAGE_METER_RESET; ticker treats as "everything"
Data._inCombat = false   -- toggled by PLAYER_REGEN_*; ticker uses for cadence
Data._clearRuntimeSessions = false

local HasCachedViewKey

local function MarkDirtyKey(selectorKey, damageMeterType)
    local bySelector = Data._dirty[selectorKey]
    if not bySelector then
        bySelector = {}
        Data._dirty[selectorKey] = bySelector
    end
    bySelector[damageMeterType] = true
end

local function MarkDirty(sessionType, damageMeterType)
    MarkDirtyKey(QUI_DamageMeter.SessionKey(sessionType, nil), damageMeterType)
end

local function MarkAllDirty()
    Data._allDirty = true
end

local function MarkCurrentDirty()
    -- Enum.DamageMeterSessionType.Current = 1
    -- Mark every meter type dirty. Iterating Enum.DamageMeterType picks up
    -- whatever Blizzard exposes today (verified to include integers up to at
    -- least 9 = Deaths) so we don't miss dirty marks on types beyond a
    -- hardcoded range.
    if Enum and Enum.DamageMeterType then
        for _, v in pairs(Enum.DamageMeterType) do MarkDirty(1, v) end
    else
        for t = 0, 10 do MarkDirty(1, t) end
    end
end

-- Combat-elapsed timer. We track our own GetTime delta from PLAYER_REGEN_DISABLED
-- to PLAYER_REGEN_ENABLED rather than rely on C_DamageMeter session.durationSeconds,
-- which is secret-tagged during combat and faults on Lua-side comparison. The
-- API duration is only safe for HISTORICAL (past) sessions; for the live
-- session we use this timer.
Data._combatStartTime = nil   -- GetTime() at last PLAYER_REGEN_DISABLED
Data._combatEndTime   = nil   -- GetTime() at last PLAYER_REGEN_ENABLED
Data._combatFrozen    = 0     -- elapsed seconds frozen at end-of-combat for post-combat display

local function GetCombatElapsed()
    if Data._combatStartTime then
        if Data._combatEndTime and Data._combatEndTime > Data._combatStartTime then
            -- Combat just ended; show the final elapsed frozen value
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
end

Data._eventFrame = CreateFrame("Frame")
Data._eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
Data._eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
Data._eventFrame:RegisterEvent("DAMAGE_METER_RESET")
Data._eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Data._eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
Data._eventFrame:SetScript("OnEvent", function(_, event, arg1, _arg2)
    if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        for sessionType = 0, 2 do
            MarkDirty(sessionType, arg1)
        end
        local sessionID = _arg2
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
        MarkAllDirty()
    elseif event == "PLAYER_REGEN_DISABLED" then
        Data._inCombat = true
        Data._combatStartTime = GetTime()
        Data._combatEndTime   = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        Data._inCombat = false
        Data._combatEndTime   = GetTime()
        Data._combatFrozen    = (Data._combatStartTime and (Data._combatEndTime - Data._combatStartTime)) or 0
        -- The API briefly returns secret-tagged source GUIDs after combat
        -- ends, which makes GetCombatSessionSourceFromType return an empty
        -- combatSpells. Re-mark dirty after a short delay so the next tick
        -- re-fetches once GUIDs have been declassified.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, MarkAllDirty)
        end
    end
end)

-- Throttled ticker. Reads cadence from settings each tick so live slider
-- adjustments take effect immediately. Cadence is per-mode: combat vs
-- idle. T6 will fill the body of Data:Refresh; T5 only establishes the
-- ticker contract.
Data._tickAccum = 0
Data._ticker = CreateFrame("Frame")
Data._ticker:SetScript("OnUpdate", function(_, elapsed)
    Data._tickAccum = Data._tickAccum + elapsed
    local s = GetSettings()
    local cadence = 0.5
    if s then
        cadence = Data._inCombat
            and (s.refreshRateCombat or 0.5)
            or  (s.refreshRateIdle   or 2.0)
    end
    if Data._tickAccum < cadence then return end
    Data._tickAccum = 0
    Data:Refresh()
end)

-- Pure helper: takes a raw C_DamageMeter combatSources array and returns a
-- normalized view. Fields use Blizzard's actual API names (totalAmount,
-- amountPerSecond). No sort is performed — Blizzard returns combatSources
-- already sorted by amount desc, which the stock meter relies on too.
-- Duration handling moved to FetchView; this function is duration-agnostic.
local function NormalizeSources(rawSources)
    local view = {}
    for i, src in ipairs(rawSources) do
        -- totalAmount may be secret-tagged during combat. Keep as-is; the
        -- renderer is responsible for IsSecretValue-guarding any arithmetic
        -- it does on these values. Sort is NOT performed here — Blizzard
        -- returns combatSources already sorted by amount desc, which the
        -- stock meter (DamageMeterSessionWindow.lua) relies on too.
        view[i] = {
            rank             = i,
            name             = src.name,
            classFilename    = src.classFilename,
            specIconID       = src.specIconID,
            totalAmount      = src.totalAmount,        -- may be secret; do not compare in Lua
            amountPerSecond  = src.amountPerSecond,    -- may be secret; do not compare in Lua
            isLocalPlayer    = src.isLocalPlayer or false,
            sourceGUID       = src.sourceGUID,
            sourceCreatureID = src.sourceCreatureID,
            deathRecapID     = src.deathRecapID,        -- Phase 6 future-use
        }
    end
    return view
end
Data._NormalizeSources = NormalizeSources  -- for T6/T7

Data._cache = {}        -- _cache[selectorKey][damageMeterType] = view
Data._generation = 0

local function SessionKey(sessionType, sessionID)
    if sessionID ~= nil then
        return "id:" .. tostring(sessionID)
    end
    return "type:" .. tostring(sessionType)
end
QUI_DamageMeter.SessionKey = SessionKey

local function NewView(sources, duration, maxAmount, totalAmount)
    Data._generation = Data._generation + 1
    return {
        duration    = duration or 0,
        maxAmount   = maxAmount or 0,
        totalAmount = totalAmount or 0,
        sources     = sources or {},
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

-- DerivePerSecond: recompute a row's per-second rate as totalAmount / duration
-- rather than trust the API's amountPerSecond. Per DamageMeterDocumentation a
-- combat source/spell's amountPerSecond is SecretWhenInCombat and is derived
-- from the live session duration; after combat it declassifies to a garbage
-- value (the report: a DPS row read "4" and an HPS row "7.04e-15" instead of
-- ~405K). GetSessionDurationSeconds is AllowedWhenUntainted and — unlike
-- GetCombatSessionFromType — NOT SecretWhenInCombat, so it hands us a usable,
-- non-secret duration for the session in and out of combat.
--
-- We can only divide once totalAmount is non-secret (post-combat / idle /
-- historical). Mid-combat totalAmount stays secret, so we return nil and the
-- caller keeps the API amountPerSecond (rendered secret-safe downstream — the
-- C side can read it). The secret check runs BEFORE any comparison: comparing
-- or dividing a secret in Lua faults under combat restrictions. Pure helper —
-- isSecret is injected so it unit-tests under plain Lua.
local function DerivePerSecond(totalAmount, duration, isSecret)
    if totalAmount == nil then return nil end
    if isSecret and (isSecret(totalAmount) or isSecret(duration)) then return nil end
    if type(duration) ~= "number" or duration <= 0 then return nil end
    return totalAmount / duration
end
QUI_DamageMeter.DerivePerSecond = DerivePerSecond

-- ResolveRateDuration: pick the divisor DerivePerSecond uses for a session's
-- rows. GetSessionDurationSeconds is Nilable (DamageMeterDocumentation) and for
-- the live Current session frequently returns nil; when that happened the rows
-- kept the API's amountPerSecond, which declassifies to garbage post-combat (a
-- DPS row read 0.0576, an HPS row 0.0000933 instead of ~5K). So:
--   * Current (live): prefer our own combat timer (GetCombatElapsed — the same
--     value the [m:ss] header shows) so the rate stays consistent with the
--     visible clock; fall back to the API duration. The API Current duration is
--     unreliable (the reference distrusts it too), hence timer-first.
--   * Expired (historical): the session's own recorded durationSeconds is
--     authoritative; fall back to the API duration.
--   * Overall (cumulative across past combats): only the API knows that span,
--     so prefer it; fall back to the live timer if it's nil.
-- A duration is "usable" only if it's a positive, non-secret number — dividing
-- by a secret or comparing it faults under combat restrictions. Pure helper:
-- the durations and isSecret are injected so it unit-tests under plain Lua.
local function ResolveRateDuration(sessionType, apiDuration, combatElapsed, historicalDuration, isSecret, currentType, expiredType)
    local function usable(d)
        return type(d) == "number" and not (isSecret and isSecret(d)) and d > 0
    end
    if expiredType ~= nil and sessionType == expiredType then
        if usable(historicalDuration) then return historicalDuration end
        if usable(apiDuration) then return apiDuration end
        return nil
    end
    if currentType ~= nil and sessionType == currentType then
        if usable(combatElapsed) then return combatElapsed end
        if usable(apiDuration) then return apiDuration end
        return nil
    end
    if usable(apiDuration) then return apiDuration end
    if usable(combatElapsed) then return combatElapsed end
    return nil
end
QUI_DamageMeter.ResolveRateDuration = ResolveRateDuration

local function FetchView(sessionType, damageMeterType, sessionID)
    if not C_DamageMeter then
        return NewView({}, 0, 0, 0)
    end

    -- pcall: defends against the API itself faulting under taint, which
    -- can happen in restricted callsites. The session table fields may
    -- still be secret-tagged; downstream code handles that.
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
    if not ok or type(session) ~= "table" then
        return NewView({}, 0, 0, 0)
    end

    local sources = NormalizeSources(session.combatSources or {})

    -- Duration: prefer our own elapsed timer for live sessions to sidestep
    -- the secret-tagged session.durationSeconds. For historical sessions
    -- (Expired session type = 2 per Enum.DamageMeterSessionType.Expired),
    -- the API duration is safe.
    local duration
    if sessionID ~= nil then
        duration = session.durationSeconds
    elseif sessionType == (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Expired or 2) then
        duration = session.durationSeconds  -- historical: API value is safe
    else
        duration = GetCombatElapsed()
    end

    -- Replace the API's per-source amountPerSecond (SecretWhenInCombat, derived
    -- from the live duration and garbage once it declassifies) with a rate we
    -- compute from the session's own non-secret duration. See DerivePerSecond:
    -- it returns nil while totalAmount is still secret (mid-combat), leaving the
    -- API value in place for the secret-safe render path. ResolveRateDuration
    -- picks the divisor: the API session duration is Nilable and nil for the
    -- live Current session, so we fall back to our own combat timer there.
    local IsSecret = Helpers and Helpers.IsSecretValue
    local S = Enum and Enum.DamageMeterSessionType
    local rateDuration
    if sessionID ~= nil then
        rateDuration = session.durationSeconds
    else
        local apiDuration = C_DamageMeter.GetSessionDurationSeconds
            and C_DamageMeter.GetSessionDurationSeconds(sessionType)
        rateDuration = ResolveRateDuration(
            sessionType, apiDuration, GetCombatElapsed(), session.durationSeconds,
            IsSecret, (S and S.Current) or 1, (S and S.Expired) or 2)
    end
    for _, s in ipairs(sources) do
        local rate = DerivePerSecond(s.totalAmount, rateDuration, IsSecret)
        if rate ~= nil then s.amountPerSecond = rate end
    end

    return NewView(sources, duration, session.maxAmount, session.totalAmount)
end

function Data:Refresh()
    local _t0 = Perf.enabled and PerfNow() or 0
    -- Walk dirty flags; refetch each. _allDirty drops selector caches so
    -- windows lazily rebuild against their current runtime selector.
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
    self._dirty = {}
end

-- ===== Breakdown (Phase 4) =====
-- Per-source spell breakdown. Lazy: only fetched when an open Breakdown popup
-- asks for it; not cached aggressively (lives only on the Breakdown frame).
--
-- Pure helper: normalize a combatSpells array (from Blizzard's
-- combatSessionSource) into a render-ready spell view. No sort — Blizzard
-- returns combatSpells already sorted by amount desc, same as combatSources.
--
-- The combatSpells entries only carry spellID + amount/hit fields; name and
-- icon must be resolved via C_Spell. Cached per spellID (spell metadata is
-- immutable for the session, so a process-lifetime cache is safe).
local _spellInfoCache = {}
local function ResolveSpellInfo(spellID)
    if not spellID then return nil end
    local cached = _spellInfoCache[spellID]
    if cached then return cached end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    if info then _spellInfoCache[spellID] = info end
    return info
end

local function NormalizeSpells(rawSpells)
    local out = {}
    for i, spell in ipairs(rawSpells) do
        local info = ResolveSpellInfo(spell.spellID)
        out[i] = {
            rank             = i,
            spellID          = spell.spellID,
            name             = (info and info.name) or spell.creatureName,
            iconID           = info and info.iconID,
            totalAmount      = spell.totalAmount,
            amountPerSecond  = spell.amountPerSecond,
            hitCount         = spell.hitCount,
            critCount        = spell.critCount,
            criticalAmount   = spell.criticalAmount,
        }
    end
    return out
end
Data._NormalizeSpells = NormalizeSpells

-- Returns a one-tick view of a source's spell breakdown. Caller is responsible
-- for re-calling on the next tick to get live updates while the popup is open.
function Data:GetBreakdownView(sessionType, damageMeterType, sourceGUID, sourceCreatureID, sessionID)
    if not C_DamageMeter then
        return { spells = {}, maxAmount = 0, totalAmount = 0 }
    end
    local ok, src
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then
            return { spells = {}, maxAmount = 0, totalAmount = 0 }
        end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, damageMeterType, sourceGUID, sourceCreatureID)
    else
        if not C_DamageMeter.GetCombatSessionSourceFromType then
            return { spells = {}, maxAmount = 0, totalAmount = 0 }
        end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            sessionType, damageMeterType, sourceGUID, sourceCreatureID)
    end
    if not ok or type(src) ~= "table" then
        return { spells = {}, maxAmount = 0, totalAmount = 0 }
    end
    return {
        spells      = NormalizeSpells(src.combatSpells or {}),
        maxAmount   = src.maxAmount or 0,
        totalAmount = src.totalAmount or 0,
    }
end

-- ===== Target breakdown (who damaged whom) =====
-- The breakdown popup also shows damage-to-targets, reconstructed from the
-- EnemyDamageTaken meter where the roles invert: each enemy source's
-- combatSpells carry a combatSpellDetails whose unitName is the *attacking
-- player*. Player names stay readable even when enemy names are secret (M+), so
-- this is the secret-safe way to get per-target totals. Two directions:
--   * enemy source  -> AggregateSpellsByUnit lists the players who hit it.
--   * player source -> pivot every enemy's player-totals to get the enemies a
--     given player hit (PivotPlayerTargets).
-- combatSpellDetails fields used: unitName, unitClassFilename, specIconID.

-- Pure: aggregate a combatSpells array by combatSpellDetails.unitName into a
-- sorted (desc) list of { name, classFilename, specIconID, totalAmount }.
-- Entries whose unit name OR amount is secret are skipped — a secret can't be a
-- table key or a summand. The accumulated totals are plain Lua numbers, so the
-- final sort comparator is never degenerate (see SortByDescSafe note). isSecret
-- is injected for unit testing.
local function AggregateSpellsByUnit(combatSpells, isSecret)
    local byName, list = {}, {}
    for _, spell in ipairs(combatSpells or {}) do
        local det  = spell.combatSpellDetails
        local name = det and det.unitName
        local amt  = spell.totalAmount
        local nameOk = name ~= nil and not (isSecret and isSecret(name))
        local amtOk  = amt  ~= nil and not (isSecret and isSecret(amt))
        if nameOk and amtOk then
            local e = byName[name]
            if not e then
                e = { name = name, classFilename = det.unitClassFilename,
                      specIconID = det.specIconID, totalAmount = 0 }
                byName[name] = e
                list[#list + 1] = e
            end
            e.totalAmount = e.totalAmount + amt
        end
    end
    table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
    return list
end
Data._AggregateSpellsByUnit = AggregateSpellsByUnit

-- Pure: pivot per-enemy player breakdowns into a per-player target map.
-- `perEnemy` is a list of { enemyName = <cstring, may be secret>, players =
-- <AggregateSpellsByUnit result> }. Returns map[playerName] = sorted (desc)
-- list of { name = enemyName, totalAmount }. Player names key the map (never
-- secret); enemy names are stored as values only (a secret enemy name renders
-- fine in a FontString, it just can't be a key).
local function PivotPlayerTargets(perEnemy)
    local map = {}
    for _, e in ipairs(perEnemy or {}) do
        for _, p in ipairs(e.players or {}) do
            local bucket = map[p.name]
            if not bucket then bucket = {}; map[p.name] = bucket end
            bucket[#bucket + 1] = { name = e.enemyName, totalAmount = p.totalAmount }
        end
    end
    for _, list in pairs(map) do
        table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
    end
    return map
end
Data._PivotPlayerTargets = PivotPlayerTargets

-- Raw combatSpells for a source — no C_Spell name/icon resolution (target
-- aggregation only needs combatSpellDetails + totalAmount). pcall-guarded like
-- GetBreakdownView.
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
    if not ok or type(src) ~= "table" then return {} end
    return src.combatSpells or {}
end

local function EnemyDamageTakenType()
    local T = Enum and Enum.DamageMeterType
    return T and T.EnemyDamageTaken
end

-- Players who damaged a single enemy source (window meter type =
-- EnemyDamageTaken, user clicks an enemy row).
function Data:GetEnemyAttackers(sessionType, sourceGUID, sourceCreatureID, sessionID)
    local eType = EnemyDamageTakenType()
    if not eType then return {} end
    local IsSecret = Helpers and Helpers.IsSecretValue
    return AggregateSpellsByUnit(
        FetchSourceSpells(sessionType, eType, sourceGUID, sourceCreatureID, sessionID), IsSecret)
end

-- playerName -> sorted enemy-target list, built by cross-referencing every
-- enemy source in EnemyDamageTaken. Cached per selector key + enemy-view
-- generation: the key changes whenever the EnemyDamageTaken view is re-fetched
-- (the dirty/ticker path bumps its generation), so it stays fresh without its
-- own event hooks.
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
    if playerName == nil then return {} end
    local IsSecret = Helpers and Helpers.IsSecretValue
    if IsSecret and IsSecret(playerName) then return {} end
    return self:GetPlayerTargetsMap(sessionType, sessionID)[playerName] or {}
end

-- ==== Combined healing (Healing Done + Absorbs) ====
-- Blizzard's C_DamageMeter exposes HealingDone and Absorbs as separate meter
-- types, but most healers think of their contribution as heals+shields
-- combined. When settings.combineAbsorbsIntoHealing is true (default), the
-- HealingDone / HPS views and their breakdown popups use the merged data
-- below. Toggle off for pure C_DamageMeter HealingDone.

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

    local IsSecret = Helpers and Helpers.IsSecretValue
    local merged, byGuid = {}, {}
    -- Lua tables in 12.0+ reject secret-tagged values as keys. During combat
    -- the local player's sourceGUID is secret until declassification, so a
    -- guarded write to byGuid is required. Secret-GUID sources still go into
    -- `merged` (they need to render); they just can't participate in the
    -- HealingDone+Absorbs merge this tick. The 0.5s post-combat re-dirty
    -- (see PLAYER_REGEN_ENABLED handler) re-runs this merge after GUIDs
    -- become indexable, so the duplicate-row state is transient.
    local function isIndexableKey(v)
        return v and not (IsSecret and IsSecret(v))
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
            if existing.totalAmount and a.totalAmount
                and not (IsSecret and (IsSecret(existing.totalAmount) or IsSecret(a.totalAmount))) then
                existing.totalAmount = existing.totalAmount + a.totalAmount
            end
            if existing.amountPerSecond and a.amountPerSecond
                and not (IsSecret and (IsSecret(existing.amountPerSecond) or IsSecret(a.amountPerSecond))) then
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
    return {
        duration    = hView.duration,
        maxAmount   = maxAmount,
        totalAmount = SafeNumOrZero(hView.totalAmount, IsSecret) + SafeNumOrZero(aView.totalAmount, IsSecret),
        sources     = merged,
        generation  = math.max(hView.generation or 0, aView.generation or 0),
    }
end

function Data:GetCombinedHealingBreakdown(sessionType, sourceGUID, sourceCreatureID, sessionID)
    local T = Enum and Enum.DamageMeterType
    local hType = T and T.HealingDone
    local aType = T and T.Absorbs
    if not (hType and aType) then
        return self:GetBreakdownView(sessionType, hType or 2, sourceGUID, sourceCreatureID, sessionID)
    end
    local hView = self:GetBreakdownView(sessionType, hType, sourceGUID, sourceCreatureID, sessionID)
    local aView = self:GetBreakdownView(sessionType, aType, sourceGUID, sourceCreatureID, sessionID)
    if not (aView and aView.spells and #aView.spells > 0) then
        return hView
    end
    local IsSecret = Helpers and Helpers.IsSecretValue
    local merged, bySpell = {}, {}
    for i, sp in ipairs(hView.spells or {}) do
        local copy = {}
        for k, v in pairs(sp) do copy[k] = v end
        merged[i] = copy
        if sp.spellID then bySpell[sp.spellID] = copy end
    end
    for _, sp in ipairs(aView.spells) do
        local existing = sp.spellID and bySpell[sp.spellID]
        if existing then
            if existing.totalAmount and sp.totalAmount
                and not (IsSecret and (IsSecret(existing.totalAmount) or IsSecret(sp.totalAmount))) then
                existing.totalAmount = existing.totalAmount + sp.totalAmount
            end
        else
            local copy = {}
            for k, v in pairs(sp) do copy[k] = v end
            table.insert(merged, copy)
            if sp.spellID then bySpell[sp.spellID] = copy end
        end
    end
    SortByDescSafe(merged, function(s) return s.totalAmount end, IsSecret)
    local maxAmount = RankAndMaxAmount(merged, IsSecret)
    return {
        spells      = merged,
        maxAmount   = maxAmount,
        totalAmount = SafeNumOrZero(hView.totalAmount, IsSecret) + SafeNumOrZero(aView.totalAmount, IsSecret),
    }
end

-- Helper: is this meter type one that should auto-include absorbs?
local function IsHealingType(meterType)
    local T = Enum and Enum.DamageMeterType
    if not T then return false end
    return meterType == T.HealingDone or meterType == T.Hps
end

-- T12 will set Data._onChange to a function that fans out to Window:Refresh
-- on every live window. Phase 3 will scope this per-window instead of fan-out.

-- ==== Formatters ====
-- FormatDuration(seconds) → "M:SS" string, "" when nil/0.
-- Handles ConditionalSecret values: routes through C_StringUtil when tainted.
local function FormatDuration(seconds)
    if not seconds then return "" end
    -- Secret-value path: arithmetic on secret numbers under taint faults.
    -- Route through C_StringUtil helpers which Blizzard tags
    -- SecretArguments=AllowedWhenTainted. Worst case we render raw seconds
    -- as "Ns" instead of M:SS; that's the documented trade-off.
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(seconds) then
        if C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
            local s = C_StringUtil.TruncateWhenZero(seconds)
            return C_StringUtil.WrapString(s, "", "s")
        end
        return ""
    end
    -- Non-secret pure-Lua path:
    if seconds == 0 then return "" end
    local s = math.floor(seconds)
    local m = math.floor(s / 60)
    local r = s % 60
    return string.format("%d:%02d", m, r)
end

local function BuildPreviousSessionLabel(availableSession)
    availableSession = availableSession or {}
    local name = availableSession.name
    if type(name) == "string" then
        name = name:gsub("^%s*%(!%)%s*", "")
    end
    if not name or name == "" then
        local sessionID = availableSession.sessionID
        name = sessionID and ("Combat " .. tostring(sessionID)) or "Combat"
    end

    local durationText = FormatDuration(availableSession.durationSeconds)
    if durationText ~= "" then
        return name .. " [" .. durationText .. "]"
    end
    return name
end
QUI_DamageMeter.BuildPreviousSessionLabel = BuildPreviousSessionLabel

-- FormatNumber(amount, format) → string per format style.
--   "minimal"  → "1K"    / "2M"        (no fractional digit)
--   "compact"  → "1.5K"  / "2.4M"      (one fractional digit; default)
--   "complete" → "1,500" / "2,400,000" (thousands separator)
--
-- Both AbbreviateNumbers and BreakUpLargeNumbers are flagged
-- SecretArguments=AllowedWhenTainted, so the same call site is safe before
-- and during combat — no taint-branch needed and the user's chosen format
-- survives into combat.
local _formatOpts = {
    -- Pair pattern per Blizzard docs: lower entry uses fractionDivisor=10 to
    -- emit "1.5K", higher entry one order up uses fractionDivisor=1 to emit
    -- "12K" instead of "12.3K". CreateAbbreviateConfig caches the parsed
    -- breakpoint table for repeat calls. abbreviationIsGlobal=false uses the
    -- literal "K"/"M"/"B" instead of resolving via GlobalStrings.
    compact = { config = CreateAbbreviateConfig({
        { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e4, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1e3, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,   abbreviation = "",  significandDivisor = 1,   fractionDivisor = 1,   abbreviationIsGlobal = false },
    }) },
    -- minimal: fractionDivisor=1 across the board strips fractional digits.
    minimal = { config = CreateAbbreviateConfig({
        { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e9, fractionDivisor = 1, abbreviationIsGlobal = false },
        { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e6, fractionDivisor = 1, abbreviationIsGlobal = false },
        { breakpoint = 1e3, abbreviation = "K", significandDivisor = 1e3, fractionDivisor = 1, abbreviationIsGlobal = false },
        { breakpoint = 1,   abbreviation = "",  significandDivisor = 1,   fractionDivisor = 1, abbreviationIsGlobal = false },
    }) },
}

local function FormatNumber(amount, format)
    if amount == nil then return "" end
    if format == "complete" then
        return BreakUpLargeNumbers(amount)
    end
    return AbbreviateNumbers(amount, _formatOpts[format] or _formatOpts.compact)
end
-- BuildValueText: render the per-row value cell from a (primary, secondary)
-- pair, applying the "0" → "" suppression on the non-secret path. Pure
-- helper — isSecret/formatNumber are passed in so it can be unit-tested with
-- stub deps.
--
-- Why string-level suppression: AbbreviateNumbers/BreakUpLargeNumbers always
-- return a printable digit string (never "" for 0), so suppression has to
-- happen here. Secret-tagged strings skip the comparison because `== "0"`
-- against a secret-tagged value taints execution under Patch 12.0+ combat
-- restrictions — they're rendered as-is.
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

-- ==== Window ====
local Window = {}
Window.__index = Window

-- Forward declaration: Breakdown is defined later in the file (after Window)
-- but Window:OpenBreakdown captures it as an upvalue. Without this declaration,
-- the reference would parse-time-bind to a global named "Breakdown" (= nil).
local Breakdown

-- Display labels for each Enum.DamageMeterType value. We key by NAME first then
-- resolve to integer via Enum.DamageMeterType[name] at module load — this avoids
-- the bug where Phase-1-era hardcoded integers (0=DamageDone, 1=HealingDone, ...)
-- did NOT match Blizzard's actual enum order (verified: HealingDone=2, Dps=1,
-- Deaths=9). Future reorderings of the enum stay safe too.
--
-- If Enum.DamageMeterType isn't populated at load (defensive — it should be), the
-- table is empty and LabelForType falls back to "Type <N>".
local TYPE_LABEL_NAMES = {
    DamageDone           = "Damage Done",
    Dps                  = "DPS",
    HealingDone          = "Healing Done",
    Hps                  = "HPS",
    DamageTaken          = "Damage Taken",
    AvoidableDamageTaken = "Avoidable Damage Taken",
    EnemyDamageTaken     = "Enemy Damage Taken",
    Absorbs              = "Absorbs",
    Interrupts           = "Interrupts",
    Dispels              = "Dispels",
    Deaths               = "Deaths",
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
    return TYPE_LABELS[damageMeterType] or ("Type " .. tostring(damageMeterType))
end

-- Tooltip labels for the per-row hover popup. Total/rate are domain-specific
-- ("Total Damage" / "DPS" reads better than "Damage Done" / "Per Second").
-- Returns (totalLabel, rateLabel); rateLabel may be nil when per-second isn't
-- meaningful (e.g. Interrupts, Dispels, Deaths) — caller falls back.
local function TooltipLabelsForType(meterType)
    local T = Enum and Enum.DamageMeterType
    if T then
        if meterType == T.DamageDone or meterType == T.Dps then
            return "Total Damage", "DPS"
        elseif meterType == T.HealingDone or meterType == T.Hps then
            return "Total Healing", "HPS"
        elseif meterType == T.Absorbs then
            return "Total Absorbs", nil
        elseif meterType == T.DamageTaken
            or meterType == T.AvoidableDamageTaken
            or meterType == T.EnemyDamageTaken then
            return "Total Damage Taken", "DPS"
        end
    end
    return LabelForType(meterType), nil
end

-- Enum.DamageMeterSessionType: 0 = Overall, 1 = Current, 2 = Expired. Used in
-- the window header so users see which session their numbers come from.
local function LabelForSession(sessionType)
    local S = Enum and Enum.DamageMeterSessionType
    if S then
        if sessionType == S.Current then return "Current" end
        if sessionType == S.Overall then return "Overall" end
        if sessionType == S.Expired then return "Expired" end
    end
    if sessionType == 0 then return "Overall" end
    if sessionType == 1 then return "Current" end
    if sessionType == 2 then return "Expired" end
    return "Session " .. tostring(sessionType)
end

-- Per-second meter types (Dps, Hps) display amountPerSecond as the primary
-- row value and rank sources by amountPerSecond. All other types use
-- totalAmount as primary and trust Blizzard's source order (sorted by total).
-- Both modes show the OTHER metric in parens as secondary, so users always
-- see both numbers at a glance.
--
-- Matches Blizzard's stock meter: DamageMeterSessionWindow.lua keeps a
-- DAMAGE_METER_TYPE_VALUE_PER_SECOND_AS_PRIMARY table with these two types.
--
-- Hoisted above Window:_SetRowSource (which calls IsPerSecondType): if this
-- block sits later in the file, the call site captures IsPerSecondType as a
-- global (nil) instead of the upvalue, and the meter throws "attempt to call
-- a nil value" on every row render.
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

-- Deaths has no magnitude to scale a bar against (it's a list of who died),
-- so its rows render as a full bar, matching the stock meter. Resolved from
-- the enum at load; nil if the enum isn't populated (then ComputeBarFill just
-- skips the Deaths branch and treats it like any other type).
local DEATHS_TYPE = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths

-- Decide the StatusBar (min, max, value) for a row's fill. Returns RAW values
-- for the widget to consume and deliberately does NOT gate on secret-ness.
-- The StatusBar computes the fill ratio on the C side, where reading secret
-- combat values is permitted; doing the division in Lua faults on secret
-- values, which is why the fill previously stalled at zero width (bars looked
-- colorless) until combat ended and values declassified. `isSecret` is
-- injected so this stays a pure, unit-testable function.
--
-- Bars are total-based for every meter type — per-second views show the rate
-- in their value text, but the bar length tracks totalAmount, because the
-- per-second metric has no secret-safe maximum to divide against mid-combat.
local function ComputeBarFill(meterType, source, fillMax, deathsType, isSecret)
    if deathsType ~= nil and meterType == deathsType then
        return 0, 1, 1
    end
    -- Check secret BEFORE any nil/<= comparison: comparing a secret value
    -- against nil or a number faults under combat restrictions.
    local maxSecret = isSecret and isSecret(fillMax)
    if not maxSecret and (fillMax == nil or fillMax <= 0) then
        return 0, 1, 0
    end
    return 0, (fillMax or 1), (source.totalAmount or 0)
end
QUI_DamageMeter.ComputeBarFill = ComputeBarFill

local BAR_POOL_SIZE = 40
local BAR_TEXTURE   = "Interface\\Buttons\\WHITE8X8"

-- LibSharedMedia handle. Phase 2+ resolves textures and fonts via
-- ns.LSM:Fetch(mediaType, name); nil-name falls back to the Phase 1
-- hardcoded default (WHITE8X8 for bars). Defends against ns.LSM being
-- nil — a minimal QUI install may not include LibSharedMedia.
local LSM = ns.LSM

local function ResolveBarTexture(name)
    if name and LSM and LSM.Fetch then
        local path = LSM:Fetch("statusbar", name)
        if path and path ~= "" then return path end
    end
    return BAR_TEXTURE
end

-- Resolve a font slot ({ name, size, outline }) into (path, size, outlineFlags).
-- name=nil falls back to Friz Quadrata (Blizzard's default UI font); size=0
-- falls back to 11pt (matches GameFontHighlightSmall, the Phase 1 default).
-- outline="" means no outline.
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

-- QUI accent color lookup. core/main.lua publishes QUI:GetAddonAccentColor()
-- which already handles theme presets + the sky-blue fallback. We thin-wrap
-- so callers can pcall against missing-QUI at module-load.
local function GetAccentColor()
    local QUI = _G.QUI
    if QUI and QUI.GetAddonAccentColor then
        return QUI:GetAddonAccentColor()
    end
    return 0.376, 0.647, 0.980, 1   -- sky blue fallback
end

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

-- Resolve a deep path through the appearance schema with per-window override
-- precedence. Walks db.profile.damageMeter.native.appearance.perWindow[windowID]
-- first; if the leaf is nil (or any intermediate node), falls back to the
-- corresponding path in appearance.global. Returns nil only when BOTH paths
-- are missing.
--
-- Usage:
--   ResolveAppearance(self.windowID, "barHeight")
--   ResolveAppearance(self.windowID, "fonts", "rowName", "size")
--   ResolveAppearance(self.windowID, "colors", "bg")
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

local function ApplyRowBackgroundVisibility(row, windowID)
    if not (row and row.BarBg) then return end
    row.BarBg:SetShown(ResolveAppearance(windowID, "showRowBackground") ~= false)
end
QUI_DamageMeter.ApplyRowBackgroundVisibility = ApplyRowBackgroundVisibility

-- Pure helper: returns the index of the local-player source in `sources`,
-- or nil if not present. Used by pinned-self logic in Window:Refresh.
local function FindLocalPlayerInSources(sources)
    if not sources then return nil end
    for i, src in ipairs(sources) do
        if src.isLocalPlayer then return i end
    end
    return nil
end

-- Attach the icon, bar, name/value text, click handler, and hover tooltip
-- to a row that has already been created and anchored. Shared between the
-- pooled rows in _BuildRow (chain-anchored in the scroll viewport) and the
-- standalone sticky row in _BuildStickyRow (anchored to the window bottom).
function Window:_AttachRowVisuals(row)
    local windowID = self.windowID
    local barH = ResolveAppearance(windowID, "barHeight") or 18

    -- Icon (left)
    local iconSize = barH
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(iconSize, iconSize)
    row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim Blizzard icon border

    -- Bar (fills remaining width)
    row.Bar = CreateFrame("StatusBar", nil, row)
    row.Bar:SetPoint("LEFT",  row.Icon, "RIGHT", 2, 0)
    row.Bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Bar:SetPoint("TOP", row, "TOP", 0, 0)
    row.Bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    row.Bar:SetStatusBarTexture(BAR_TEXTURE)
    row.Bar:SetMinMaxValues(0, 1)
    row.Bar:SetValue(0)

    -- Bar bg (dark behind the fill)
    row.BarBg = row.Bar:CreateTexture(nil, "BACKGROUND")
    row.BarBg:SetAllPoints(row.Bar)
    do
        local _r, _g, _b = 0.05, 0.05, 0.05
        if SkinBase and SkinBase.GetDepthColor then
            _r, _g, _b = SkinBase.GetDepthColor("ROW")
        end
        row.BarBg:SetColorTexture(_r or 0.05, _g or 0.05, _b or 0.05, 0.55)
    end

    -- Name (left-justified, over the bar)
    row.Name = row.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT",  row.Bar, "LEFT",  4, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetText("")

    -- Value (right-justified, over the bar)
    row.Value = row.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Value:SetPoint("RIGHT", row.Bar, "RIGHT", -4, 0)
    row.Value:SetJustifyH("RIGHT")
    row.Value:SetText("")

    -- Hover tooltip (Phase 2) + breakdown popup (Phase 4). _SetRowSource stashes
    -- source / maxAmount / type onto the row each tick; OnEnter reads from the
    -- closure-captured row.
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")
    row:SetScript("OnClick", function(rowSelf)
        if not rowSelf._source then return end
        -- Per-source combatSpells are secret-tagged during active combat, so
        -- C_DamageMeter.GetCombatSessionSourceFromType returns no iterable
        -- spell rows and the popup would render as an empty header. Block the
        -- click instead; OnEnter shows a hint line explaining why. The
        -- PLAYER_REGEN_ENABLED handler in the Data layer re-dirties views
        -- 0.5s after combat ends, so the next click populates normally.
        if InCombatLockdown and InCombatLockdown() then return end
        self:OpenBreakdown(rowSelf._source, rowSelf)
    end)
    row:SetScript("OnEnter", function(rowSelf)
        local s2 = GetSettings()
        if not (s2 and s2.showHoverTooltip) then return end
        if not rowSelf._source then return end
        if GameTooltip:IsForbidden() then return end

        local src = rowSelf._source

        -- Spec: "Anchored TOP to row's BOTTOM" → tooltip appears BELOW the row.
        GameTooltip:SetOwner(rowSelf, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()

        -- Header colored by class
        local cr, cg, cb = 1, 1, 1
        if src.classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[src.classFilename] then
            local cc = Helpers.GetClassColorTable(src.classFilename)
            cr, cg, cb = cc.r, cc.g, cc.b
        end
        GameTooltip:AddLine(ShortenName(src.name) or "?", cr, cg, cb)

        if src.classFilename then
            GameTooltip:AddLine(src.classFilename, 0.7, 0.7, 0.7)
        end

        local totalLabel, rateLabel = TooltipLabelsForType(rowSelf._damageMeterType or 0)
        -- Capture secret state BEFORE any equality comparison: comparing a
        -- secret-tagged string against "" taints execution. AbbreviateNumbers
        -- propagates the secret tag, so secret amounts must be rendered as-is
        -- without the "is it empty?" gate.
        local IsSecret = Helpers and Helpers.IsSecretValue
        local totalSecret = src.totalAmount and IsSecret and IsSecret(src.totalAmount)
        local amt = FormatNumber(src.totalAmount, "complete")
        if totalSecret or (amt ~= "") then
            GameTooltip:AddDoubleLine(totalLabel .. ":", amt, 1, 1, 1, 1, 1, 1)
        end

        local ps = src.amountPerSecond
        local psSecret = ps and IsSecret and IsSecret(ps)
        if ps and (psSecret or ps ~= 0) then
            GameTooltip:AddDoubleLine((rateLabel or "Per Second") .. ":", FormatNumber(ps, "compact"), 1, 1, 1, 1, 1, 1)
        end

        -- % of top: the bar is total-based for every meter type, so the
        -- percentage matches it (totalAmount over the rank-1 total stashed in
        -- _maxAmount). Check secret-ness before any comparison — dividing or
        -- comparing a secret value faults under combat restrictions.
        local total = src.totalAmount
        local maxSec   = IsSecret and IsSecret(rowSelf._maxAmount)
        local totalSec = IsSecret and IsSecret(total)
        if not (maxSec or totalSec) and total ~= nil
            and rowSelf._maxAmount and rowSelf._maxAmount > 0 then
            local pct = (total / rowSelf._maxAmount) * 100
            GameTooltip:AddDoubleLine("% of Top:", string.format("%.1f%%", pct), 1, 1, 1, 1, 1, 1)
        end

        -- Combat hint: pairs with the OnClick guard above. Spell breakdown
        -- data is unavailable mid-combat, so the click does nothing — tell
        -- the user why instead of leaving them to guess.
        if InCombatLockdown and InCombatLockdown() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Spell breakdown is hidden during combat", 0.7, 0.7, 0.7)
        end

        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip:IsForbidden() then return end
        GameTooltip:Hide()
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

-- Standalone "sticky" row anchored to the window's bottom edge, outside the
-- scrolling viewport. Used by the showPinnedSelf feature so the local player
-- remains visible when scrolled out of the viewport. Constructed once in
-- Window:New; populated via _SetRowSource and shown/hidden by Refresh.
function Window:_BuildStickyRow()
    local windowID = self.windowID
    local barH = ResolveAppearance(windowID, "barHeight") or 18

    local row = CreateFrame("Button", nil, self.frame)
    row:SetHeight(barH)
    row:SetPoint("LEFT",   self.frame, "LEFT",   0, 0)
    row:SetPoint("RIGHT",  self.frame, "RIGHT",  0, 0)
    row:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 0)
    -- Sit above the scrollFrame so its texture isn't clipped by the viewport.
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

    -- Bar texture: pick LSM media if user set one, else stick with the
    -- Phase 1 WHITE8X8 default. Applied here (per-source) rather than at
    -- pool build time so a settings change is picked up on the next
    -- RefreshAll() without a /reload.
    local barTexName = ResolveAppearance(windowID, "textures", "bar")
    row.Bar:SetStatusBarTexture(ResolveBarTexture(barTexName))

    -- Icon: dispatch on iconStyle setting ("spec" | "class" | "none").
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
        -- "spec" (default) or fallback when class data is missing
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

    row.Name:SetText((source.rank or 0) .. ". " .. (ShortenName(source.name) or "?"))

    -- Value: primary metric per the meter type, with the OTHER metric in
    -- parens as secondary. For Dps/Hps types, primary = amountPerSecond and
    -- secondary = totalAmount; for everything else, primary = totalAmount
    -- and secondary = amountPerSecond. numberFormat is per-window-overridable
    -- and applies to the primary; secondary always uses "compact" for brevity.
    -- showSecondaryValue=false ("short value" option) drops the parenthetical
    -- entirely: nil secondary renders primary-only in BuildValueText, and the
    -- possibly-secret secondary is never inspected — just not passed.
    local numberFormat = ResolveAppearance(windowID, "numberFormat") or "compact"
    local perSecondMode = IsPerSecondType(self.damageMeterType)
    local primaryVal   = perSecondMode and source.amountPerSecond or source.totalAmount
    local secondaryVal = perSecondMode and source.totalAmount     or source.amountPerSecond
    if ResolveAppearance(windowID, "showSecondaryValue") == false then
        secondaryVal = nil
    end
    local IsSecret = Helpers and Helpers.IsSecretValue
    row.Value:SetText(BuildValueText(primaryVal, secondaryVal, numberFormat, IsSecret, FormatNumber))

    -- Bar fill: hand the StatusBar widget the raw totalAmount against the
    -- rank-1 total (maxAmount) as its range, and let it compute the fill on
    -- the C side. Both values can be secret-tagged during combat; computing
    -- the ratio in Lua (the old behavior) faulted on secret values, so the
    -- fill stalled at zero width and the bars looked colorless until combat
    -- ended. The widget reads secret values directly, so bars fill live now.
    -- primaryVal above still drives the value TEXT; the bar length is always
    -- total-based (see ComputeBarFill).
    local fillMin, fillMaxValue, fillValue =
        ComputeBarFill(self.damageMeterType, source, maxAmount, DEATHS_TYPE, IsSecret)
    row.Bar:SetMinMaxValues(fillMin, fillMaxValue)

    -- Push the raw value straight to the widget and let the C side compute the
    -- fill (it reads secret combat values fine). The bar is never blended in
    -- Lua: interpolating the fill would mean arithmetic on the value, which
    -- faults on secret combat values.
    row.Bar:SetValue(fillValue or 0)

    -- Bar color: priority is useClassColor → barColorAccent → custom barColor.
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

    -- Stash source + maxAmount + type on the row so OnEnter can build the
    -- tooltip without closure-capturing the bind-time locals.
    row._source = source
    row._maxAmount = maxAmount
    row._damageMeterType = self.damageMeterType
end

function Window:_ApplyHeader()
    if not self.frame or not self.TypeLabel then return end
    local sessionLabel = self.sessionID ~= nil and "Previous" or LabelForSession(self.sessionType)
    self.TypeLabel:SetText(LabelForType(self.damageMeterType)
        .. " | " .. sessionLabel)
end

-- Window border color first honors the shared borderColorSource/borderColor
-- keys used by the Border Coloring page. Older colors.border values remain a
-- fallback so existing native damage-meter profiles keep their look.
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

    -- Window bg
    if self.backdropTex then
        local bg = ResolveAppearance(windowID, "colors", "bg")
        if not bg then
            local _r, _g, _b = 0, 0, 0
            if Helpers and Helpers.GetSkinBgColor then
                _r, _g, _b = Helpers.GetSkinBgColor()
            end
            bg = { _r or 0, _g or 0, _b or 0, 0.85 }
        end
        self.backdropTex:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.85)
    end

    -- Window border (nil = accent). The 1px border frame is built in Window:New;
    -- recolor it live here so the Appearance -> Colors -> Border picker applies
    -- without a /reload (RefreshAll -> Refresh -> _ApplyColors).
    if self.border and self.border.SetBackdropBorderColor then
        self.border:SetBackdropBorderColor(self:_ResolveBorderColor())
    end

    -- Header text color (TypeLabel + SessionTimer). nil = accent.
    local headerText = ResolveAppearance(windowID, "colors", "headerText")
    local hr, hg, hb, ha
    if headerText then
        hr, hg, hb, ha = headerText[1] or 1, headerText[2] or 1, headerText[3] or 1, headerText[4] or 1
    else
        hr, hg, hb, ha = GetAccentColor()
    end
    if self.TypeLabel    then self.TypeLabel:SetTextColor(hr, hg, hb, ha)    end
    if self.SessionTimer then self.SessionTimer:SetTextColor(hr, hg, hb, ha) end

    -- Row text colors (rowName + rowValue)
    if not self.rows then return end
    local rn = ResolveAppearance(windowID, "colors", "rowName")  or { 1, 1, 1, 1 }
    local rv = ResolveAppearance(windowID, "colors", "rowValue") or { 1, 1, 1, 1 }
    for i = 1, #self.rows do
        local row = self.rows[i]
        if row then
            if row.Name  then row.Name:SetTextColor(rn[1] or 1, rn[2] or 1, rn[3] or 1, rn[4] or 1)  end
            if row.Value then row.Value:SetTextColor(rv[1] or 1, rv[2] or 1, rv[3] or 1, rv[4] or 1) end
        end
    end
    -- Also style the sticky self-row when present.
    if self.stickyRow then
        local r = self.stickyRow
        if r.Name  then r.Name:SetTextColor(rn[1] or 1, rn[2] or 1, rn[3] or 1, rn[4] or 1)  end
        if r.Value then r.Value:SetTextColor(rv[1] or 1, rv[2] or 1, rv[3] or 1, rv[4] or 1) end
    end
end

function Window:_ApplyFonts()
    local windowID = self.windowID

    -- Header font (TypeLabel + SessionTimer share)
    do
        local slot = ResolveAppearance(windowID, "fonts", "header")
        local path, size, outline = ResolveFontSlot(slot)
        if self.TypeLabel    then self.TypeLabel:SetFont(path, size, outline)    end
        if self.SessionTimer then self.SessionTimer:SetFont(path, size, outline) end
    end

    -- Row fonts (rowName + rowValue)
    if not self.rows then return end
    local nSlot = ResolveAppearance(windowID, "fonts", "rowName")
    local vSlot = ResolveAppearance(windowID, "fonts", "rowValue")
    local nPath, nSize, nOutline = ResolveFontSlot(nSlot)
    local vPath, vSize, vOutline = ResolveFontSlot(vSlot)
    for i = 1, #self.rows do
        local row = self.rows[i]
        if row then
            if row.Name  then row.Name:SetFont(nPath, nSize, nOutline)  end
            if row.Value then row.Value:SetFont(vPath, vSize, vOutline) end
        end
    end
    -- Also style the sticky self-row when present.
    if self.stickyRow then
        local r = self.stickyRow
        if r.Name  then r.Name:SetFont(nPath, nSize, nOutline)  end
        if r.Value then r.Value:SetFont(vPath, vSize, vOutline) end
    end
end

-- Damage meter types exposed in the gear-menu radio list, in display order.
-- Built from Enum.DamageMeterType names at module load — see TYPE_LABEL_NAMES
-- comment above for why we resolve from names not hardcoded integers.
-- Covers all 11 enum entries (every type Blizzard's API surfaces). Grouped
-- by metric family: damage, healing, taken/avoidable/enemy, absorbs, actions.
-- Per-second views (Dps, Hps) sort BY per-second rather than total, which is
-- a meaningfully different ranking from DamageDone / HealingDone on uneven
-- combats (a late-joining DPS ranks low by total but high by per-second).
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

-- Returns the source array to render against + the matching max value for bar
-- fill ratios. One path for every meter type: trust the API's order. C_DamageMeter
-- returns combatSources sorted by amount on the C side (where secret combat
-- values are readable) — and that is also the correct order for the per-second
-- views, because QUI derives amountPerSecond as totalAmount/duration (a constant
-- divisor across all sources), so rate-order == total-order == API order. There
-- is nothing to re-sort: doing so in Lua could only scramble that order, since
-- table.sort degenerates on the secret-tagged amounts during combat.
local function PrepareSourcesForRender(view)
    local sources = view.sources
    -- Bar-fill max: the rank-1 source's totalAmount, returned RAW (it may be
    -- secret during combat). _SetRowSource hands it to the StatusBar widget,
    -- which divides on the C side. Bars are total-based even for per-second
    -- views — the rate has no secret-safe Lua maximum to divide against while
    -- combat values are still secret.
    local fillMax = sources[1] and sources[1].totalAmount or 0
    return sources, fillMax
end

function Window:_OpenConfigMenu()
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    local s = GetSettings()
    local windowState = s and s.windows and s.windows[self.windowID]
    if not windowState then return end

    local owner = self.header or self.frame
    local function SelectSession(sessionType, sessionID)
        if sessionID ~= nil then
            self.sessionType = nil
        else
            self.sessionType = sessionType
        end
        self.sessionID = sessionID
        if sessionID == nil and sessionType ~= nil then
            windowState.sessionType = sessionType
        end
        self._lastGeneration = -1
        if self._breakdown and self._breakdown.Close then
            self._breakdown:Close()
        end
        QUI_DamageMeter.WindowManager:RefreshAll()
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Meter Type")
        for _, t in ipairs(METER_TYPES) do
            local typeVal = t
            root:CreateRadio(LabelForType(typeVal),
                function() return self.damageMeterType == typeVal end,
                function()
                    self.damageMeterType = typeVal
                    windowState.damageMeterType = typeVal
                    QUI_DamageMeter.WindowManager:RefreshAll()
                end)
        end
        root:CreateDivider()
        root:CreateTitle("Session")
        local S = Enum and Enum.DamageMeterSessionType
        local currentSession = (S and S.Current) or 1
        local overallSession = (S and S.Overall) or 0

        root:CreateRadio("Current",
            function() return self.sessionID == nil and self.sessionType == currentSession end,
            function() SelectSession(currentSession, nil) end)

        root:CreateRadio("Overall",
            function() return self.sessionID == nil and self.sessionType == overallSession end,
            function() SelectSession(overallSession, nil) end)

        local previousMenu = root:CreateButton("Previous")
        local sessions
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local ok, availableSessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
            if ok and type(availableSessions) == "table" then
                sessions = availableSessions
            end
        end

        if not sessions or #sessions == 0 then
            local none = previousMenu:CreateButton("No previous sessions", function() end)
            none:SetEnabled(false)
        else
            for _, availableSession in ipairs(sessions) do
                local sessionID = availableSession.sessionID
                previousMenu:CreateButton(BuildPreviousSessionLabel(availableSession),
                    function() SelectSession(nil, sessionID) end)
            end
        end
        root:CreateDivider()
        root:CreateTitle("Data")
        -- ResetAllCombatSessions is Blizzard's only reset entry point and clears
        -- every session/window globally. It fires DAMAGE_METER_RESET, which the
        -- data layer turns into a full re-fetch; RefreshAll repaints immediately
        -- in case the event lags a frame.
        root:CreateButton("Reset Data", function()
            if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                C_DamageMeter.ResetAllCombatSessions()
                Data:ResetCombatClock()
                Data:ClearCachedViews()
                if QUI_DamageMeter.WindowManager.ClearRuntimeSessionIDs then
                    QUI_DamageMeter.WindowManager:ClearRuntimeSessionIDs()
                end
                QUI_DamageMeter.WindowManager:RefreshAll()
            end
        end)
    end)
end

-- Resize and position the thumb based on current scroll state. Hides the
-- scrollbar entirely when content fits inside the viewport. Mirrors
-- CreateDropdownScrollBody:UpdateThumb in QUI_Options/framework.lua.
function Window:_UpdateScrollThumb()
    local scrollBar     = self.scrollBar
    local scrollFrame   = self.scrollFrame
    local scrollContent = self.scrollContent
    if not (scrollBar and scrollFrame and scrollContent) then return end

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
    -- Clamp in case the viewport just grew past the previous scroll position.
    if cur > maxScroll then
        cur = maxScroll
        scrollFrame:SetVerticalScroll(cur)
    end
    local ratio = (maxScroll > 0) and (cur / maxScroll) or 0
    local yOff = -ratio * (trackH - thumbH)
    scrollBar.thumb:ClearAllPoints()
    scrollBar.thumb:SetPoint("TOP", scrollBar, "TOP", 0, yOff)
end

-- Show / hide the sticky self-row based on whether the local player's row is
-- inside the currently visible scroll range. The predicate is recomputed on
-- every Refresh and every OnMouseWheel tick. Re-anchors scrollFrame's bottom
-- to make room for the sticky row when shown.
function Window:_UpdateStickyVisibility()
    local sources = self._stickySources
    local sticky  = self.stickyRow
    local sep     = self.stickySeparator
    local sf      = self.scrollFrame
    if not (sticky and sep and sf) then return end

    -- Re-anchor only on transitions; tracked via self._stickyShown.
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

    -- Cheap guards first — bail out before any settings/geometry lookups.
    local s = GetSettings()
    local pinnedSelf = s and s.showPinnedSelf
    if not (pinnedSelf and sources and #sources > 0) then setHidden(); return end

    local localIdx = FindLocalPlayerInSources(sources)
    if not localIdx then setHidden(); return end

    -- Compute the visible row range from current scroll offset + viewport.
    local barH    = ResolveAppearance(self.windowID, "barHeight")  or 18
    local barGap  = ResolveAppearance(self.windowID, "barSpacing") or 2
    local rowPitch = barH + barGap
    local scrollY = sf:GetVerticalScroll() or 0
    local viewH   = sf:GetHeight()
    local firstVisible = math.floor(scrollY / rowPitch) + 1
    -- When viewH < rowPitch, lastVisible < firstVisible and the predicate
    -- below is always false → sticky always shows. The window is unusable
    -- at that size anyway; degrading to "sticky-only" is acceptable.
    local lastVisible  = firstVisible + math.floor(viewH / rowPitch) - 1
    if localIdx >= firstVisible and localIdx <= lastVisible then
        setHidden(); return
    end

    -- Player is outside the visible range — populate + show sticky.
    self:_SetRowSource(sticky, sources[localIdx], self._stickyMaxValue)
    sticky:Show()
    sep:Show()
    if not self._stickyShown then
        local headerH = ResolveAppearance(self.windowID, "headerHeight") or 22
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     self.frame, "TOPLEFT",  0, -headerH)
        sf:SetPoint("BOTTOMRIGHT", sep,        "TOPRIGHT", 0,  0)
        self._stickyShown = true

        -- Viewport shrank; clamp scroll position so we don't display past content.
        local contentH = self.scrollContent and self.scrollContent:GetHeight() or 0
        local newViewH = sf:GetHeight()
        local maxScroll = math.max(0, contentH - newViewH)
        if scrollY > maxScroll then sf:SetVerticalScroll(maxScroll) end
        self:_UpdateScrollThumb()
    end
end

function Window:Refresh()
    if not self.frame then return end

    -- Phase 9: per-window hidden flag. Set via Windows section UI; lets users
    -- temporarily stash a window without deleting it (which would lose
    -- type/session/position state and unregister the Layout Mode handle).
    local s = GetSettings()
    local ws = s and s.windows and s.windows[self.windowID]
    if ws and ws.hidden then
        self.frame:Hide()
        return
    elseif not self.frame:IsShown() then
        self.frame:Show()
    end

    local _t0 = Perf.enabled and PerfNow() or 0
    self:_ApplyHeader()
    self:_ApplyFonts()
    self:_ApplyColors()

    -- Healing views optionally include absorbs (settings.combineAbsorbsIntoHealing).
    local view
    local s_combo = GetSettings()
    if IsHealingType(self.damageMeterType)
        and s_combo and s_combo.combineAbsorbsIntoHealing then
        view = Data:GetCombinedHealingView(self.sessionType, self.sessionID)
    else
        view = Data:GetView(self.sessionType, self.damageMeterType, self.sessionID)
    end
    if view.generation == self._lastGeneration then return end
    self._lastGeneration = view.generation

    -- Session timer text. Secret durations must go straight through
    -- FormatDuration so its C_StringUtil path can handle them.
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

    for i = 1, renderCount do
        self:_SetRowSource(self.rows[i], sources[i], fillMax)
        self.rows[i]:Show()
    end
    for i = renderCount + 1, #self.rows do
        self.rows[i]:Hide()
    end

    -- Size the scroll content to match what's rendered so the scrollbar and
    -- mouse wheel know how far to scroll. Row pitch = barHeight + barSpacing.
    local barH   = ResolveAppearance(self.windowID, "barHeight")  or 18
    local barGap = ResolveAppearance(self.windowID, "barSpacing") or 2
    local rowPitch = barH + barGap
    if self.scrollContent then
        -- Last row has no trailing gap, so subtract one barGap.
        local contentH = renderCount > 0 and (renderCount * rowPitch - barGap) or 0
        self.scrollContent:SetHeight(math.max(1, contentH))
    end
    self:_UpdateScrollThumb()

    -- Sticky self-row: shown when the local player is outside the currently
    -- visible scroll range. _UpdateStickyVisibility computes the predicate
    -- against the current viewport + scroll offset and toggles sticky/sep,
    -- re-anchoring scrollFrame's bottom to shrink/grow the viewport.
    -- pinnedSelf, sources, and fillMax are read directly by the method via
    -- self._stickySources / self._stickyMaxValue so the OnMouseWheel handler
    -- (Task 5) can re-evaluate without re-running the full Refresh.
    self._stickySources = sources
    self._stickyMaxValue = fillMax
    self:_UpdateStickyVisibility()

    -- Phase 4: refresh an open breakdown popup on every parent-window tick.
    self:RefreshBreakdown()
    if Perf.enabled then Perf:Record("window", PerfNow() - _t0) end
end

local function LayoutKey(windowID) return "damageMeter_window_" .. windowID end

local WINDOW_LAYOUT_FEATURE_ID = "damageMeterWindowLayout"

-- Shared min/max bounds for a damage meter window. The corner-drag grips
-- (frame:SetResizeBounds) and the Layout Mode Frame Size sliders both clamp to
-- these, so the two resize paths stay consistent.
local WINDOW_SIZE_MIN_W, WINDOW_SIZE_MAX_W = 120, 1200
local WINDOW_SIZE_MIN_H, WINDOW_SIZE_MAX_H = 60, 1000

local RESIZE_CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

-- Read accent color with sky-blue fallback (matches layoutmode.lua default).
local function GetAccentRGB()
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    local accent = GUI and GUI.Colors and GUI.Colors.accent
    if accent then
        return accent[1], accent[2], accent[3]
    end
    return 0.376, 0.647, 0.980
end

-- Attach four corner resize grips to a layout-mode child overlay. Each grip
-- drives `frame:StartSizing(corner)`; on release we persist w/h to per-window
-- savedvars and call `window:Refresh()` so rows re-layout. Idempotent —
-- skips work if grips have already been built on this overlay.
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

        -- L-bracket: horizontal + vertical bar pinned to the corner.
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
                    GameTooltip:SetText("Hold Shift to resize (anchored)")
                else
                    GameTooltip:SetText("Drag to resize meter window")
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
            -- Locked-when-anchored: mirror the chat resize grips / move-lock. An
            -- anchored window blocks resizing; Shift detaches the anchor (parity
            -- with Shift-drag) and then resizes.
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

            -- Sizing from a corner moves the frame's CENTER while the
            -- frameAnchoring entry (the position store) still holds the
            -- pre-resize center; record the live center as a pending
            -- position or the post-close anchor re-apply recenters the
            -- window by half the size delta. Shared helper — no-op when
            -- anchored or Layout Mode is inactive.
            local LM = ns.QUI_LayoutMode
            if LM and LM.RecordFreeElementPosition then
                LM:RecordFreeElementPosition(overlay._barKey, frame)
            end

            if window.Refresh then
                pcall(window.Refresh, window)
            end

            -- Re-sync the Layout Mode Frame Size sliders to the dragged size
            -- (they read the live size only at build time otherwise).
            local U = ns.QUI_LayoutMode_Utils
            if U and U.RefreshActiveSizeSliders then
                U.RefreshActiveSizeSliders()
            end
        end)

        overlay._dmResizeGrips[corner] = grip
    end
end

-- Note: RegisterWithLayoutMode references WindowManager (defined later in the file).
-- Lua resolves bare locals at PARSE time, so a direct `WindowManager:Get(...)` here
-- would capture `_G.WindowManager` (nil). We go through `QUI_DamageMeter.WindowManager`
-- so field access happens at runtime against the populated table.
local function RegisterWithLayoutMode(window)
    local windowID = window.windowID
    local key      = LayoutKey(windowID)
    local label    = "Damage Meter " .. windowID

    -- Layout Mode handle (idempotent: skinner's pattern). Position persistence
    -- flows through the shared frameAnchoring DB — same path as every other
    -- QUI mover. The frame resolver below maps `key` back to window.frame so
    -- QUI_ApplyFrameAnchor can position it on apply.
    if ns.QUI_LayoutMode and type(ns.QUI_LayoutMode.RegisterElement) == "function" then
        ns.QUI_LayoutMode:RegisterElement({
            key      = key,
            label    = label,
            group    = "Display",
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
            -- Corner resize grips — mirrors the ChatFrame1 pattern in
            -- layoutmode.lua. Drag any corner to reshape the window; on
            -- release we persist w/h to savedvars and trigger a Refresh so
            -- rows re-layout in the new bounds.
            setupOverlay = function(overlay, frame)
                AttachWindowResizeOverlay(overlay, frame, window, windowID)
            end,
        })
    end

    -- Anchor target registry so other QUI elements can anchor TO this window
    -- AND so _G.QUI_ApplyFrameAnchor recognizes the key on reload.
    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(key, {
            resolver    = function() return window.frame end,
            displayName = label,
            category    = "Display",
            order       = 60,
        })
    end

    -- Surface the per-window mover in the Layout Mode settings drawer.
    -- One shared Feature dispatches by providerKey (see registration below);
    -- here we just point the dynamic key at it. Mirrors the CDM-custom-bar
    -- pattern in modules/cdm/cdm_containers.lua.
    local Registry = ns.Settings and ns.Settings.Registry
    if Registry and type(Registry.RegisterLookupKey) == "function" then
        Registry:RegisterLookupKey(WINDOW_LAYOUT_FEATURE_ID, key)
    end

    -- Position the frame from saved frameAnchoring (no-op if no saved entry,
    -- leaving the default CENTER anchor set in Window:New).
    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(key)
    end
end

-- Shared Feature for all damage meter window movers. Registered once at file
-- load; each window calls Registry:RegisterLookupKey(...) in its RegisterWith-
-- LayoutMode to point its dynamic key at this feature. The render function
-- dispatches by options.providerKey so one feature serves all windows.
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
                -- Layout Mode settings panel for a damage meter window. Builds a
                -- Position collapsible plus a Frame Size collapsible (Width /
                -- Height sliders), mirroring the chat-frame provider. The size
                -- sliders write to the same windows[id].size store as the
                -- corner-drag grips, so the two resize paths stay in sync.
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

                    -- Without a live window/frame or the size helper, fall back
                    -- to position-only controls (the pre-size behavior).
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
                        -- Match the corner-drag grips: no resizing in combat.
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
                        -- Anchored windows: keep the anchor point pinned —
                        -- grow away from it, not from center.
                        if _G.QUI_ReassertAnchorAfterResize then
                            _G.QUI_ReassertAnchorAfterResize(providerKey)
                        end
                        if window.Refresh then pcall(window.Refresh, window) end
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
                            widthDescription  = "Damage meter window width in pixels.",
                            heightDescription = "Damage meter window height in pixels.",
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

-- Static factory (dot, not colon): builds and returns a new instance. Declared
-- with a dot so Lua doesn't inject an unused `self` (the class table) that the
-- `local self` instance below would shadow.
function Window.New(windowID)
    local s = GetSettings()
    local windowState = s and s.windows and s.windows[windowID]
    if not windowState then
        -- Defensive: settings missing → use baseline defaults matching T3.
        windowState = {
            damageMeterType = 0, sessionType = 1,
            size     = { w = 240, h = 180 },
            hidden = false,
        }
    end

    local self = setmetatable({
        windowID        = windowID,
        damageMeterType = windowState.damageMeterType,
        sessionType     = windowState.sessionType,
        rows            = {},      -- pool, filled in T10
        _lastGeneration = 0,
    }, Window)
    self.sessionID = nil

    -- Top-level frame; parented to UIParent so each window is independently
    -- positionable and Layout Mode-discoverable. Position is set here as a
    -- safe default; RegisterWithLayoutMode (called at the end of :New) applies
    -- the saved frameAnchoring entry afterward if one exists.
    local frame = CreateFrame("Frame", "QUI_DamageMeterWindow" .. windowID, UIParent)
    frame:SetSize(windowState.size.w, windowState.size.h)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("MEDIUM")
    -- Resizable so Layout Mode corner-grip drags can reshape the window.
    -- Movable so frame:StartSizing works (Blizzard couples the two).
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(WINDOW_SIZE_MIN_W, WINDOW_SIZE_MIN_H, WINDOW_SIZE_MAX_W, WINDOW_SIZE_MAX_H)
    end
    self.frame = frame

    -- Backdrop child: dark fill behind the window. The window border is a
    -- separate 1px ring (added below); rows also carry a per-row accent (T10).
    local backdrop = CreateFrame("Frame", nil, frame)
    backdrop:SetAllPoints(frame)
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(backdrop)
    -- colors.bg is { r, g, b, a } array form (Phase 2 schema); per-window
    -- override resolution lands here so window-specific bg colors paint at spawn.
    local appBg = ResolveAppearance(windowID, "colors", "bg")
    if not appBg then
        local _r, _g, _b = 0, 0, 0
        if Helpers and Helpers.GetSkinBgColor then
            _r, _g, _b = Helpers.GetSkinBgColor()
        end
        appBg = { _r or 0, _g or 0, _b or 0, 0.85 }
    end
    bgTex:SetColorTexture(appBg[1], appBg[2], appBg[3], appBg[4])
    self.backdrop = backdrop
    self.backdropTex = bgTex

    -- Window border: a 1px ring just outside the frame edges, colored from
    -- colors.border (nil = QUI accent). Built once here; _ApplyColors repaints
    -- it when the Appearance -> Colors -> Border picker changes. Guarded so a
    -- missing UIKit (early load) degrades gracefully to no border.
    if ns.UIKit and ns.UIKit.CreateBackdropBorder then
        self.border = ns.UIKit.CreateBackdropBorder(frame, 1, self:_ResolveBorderColor())
    end

    -- Header bar (Button so RegisterForClicks/OnClick work for the right-click
    -- config menu below; anchored TOP-LEFT/TOP-RIGHT, height from settings).
    local headerH = ResolveAppearance(windowID, "headerHeight") or 22
    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(headerH)
    self.header = header

    -- TypeLabel (left side of header): e.g. "Damage Done"
    local typeLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("LEFT", header, "LEFT", 6, 0)
    typeLabel:SetText("Damage Done")  -- T13/T17 wire this to the actual type
    self.TypeLabel = typeLabel

    -- SessionTimer (right side of header): e.g. "[1:24]"
    local sessionTimer = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionTimer:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    sessionTimer:SetText("")
    self.SessionTimer = sessionTimer

    -- CloseButton — Phase 1 stub. Hidden by default so Phase 1 ships without
    -- a way to lose the window accidentally; Phase 2/3 enable it once per-
    -- window hidden-state UI is built.
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(headerH - 6, headerH - 6)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    closeBtn:Hide()
    self.CloseButton = closeBtn

    -- Right-click on the header opens the meter-type / session menu.
    -- Hover shows a hint so the affordance is discoverable without a gear.
    header:EnableMouse(true)
    header:RegisterForClicks("RightButtonUp")
    header:SetScript("OnClick", function(_, button)
        if button == "RightButton" then self:_OpenConfigMenu() end
    end)
    header:SetScript("OnEnter", function(hdr)
        if GameTooltip:IsForbidden() then return end
        GameTooltip:SetOwner(hdr, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        if GameTooltip:IsForbidden() then return end
        GameTooltip:Hide()
    end)

    -- Scrollable row viewport: rows live inside scrollContent (the ScrollFrame's
    -- scroll child) rather than directly on self.frame. This lets the row pool
    -- exceed the window's visible height and be reached via mouse wheel.
    -- The scrollFrame's bottom anchor flips between frame:BOTTOM (sticky hidden)
    -- and stickySeparator:TOP (sticky shown); Refresh re-anchors as needed.
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -headerH)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  0)
    scrollFrame:EnableMouseWheel(true)  -- wheel handler wired in Task 5

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(1, 1)  -- real size assigned by Refresh (Task 7)
    scrollFrame:SetScrollChild(scrollContent)

    -- Keep scrollContent's width synced to the viewport width as the window
    -- resizes. Task 6 extends this handler to also call _UpdateScrollThumb.
    scrollFrame:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then scrollContent:SetWidth(w) end
        if self._UpdateScrollThumb then self:_UpdateScrollThumb() end
    end)

    -- Mouse wheel: two rows per tick, clamped to [0, contentH - viewportH].
    -- Re-evaluates sticky-self visibility (Task 9) since the predicate depends
    -- on scroll offset, and updates the thumb (Task 6). Both guarded with
    -- `if self._X then` so this handler works even before those methods exist.
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
    end)

    -- Thumb scrollbar: thin accent-colored bar at the right edge, auto-hides
    -- when content fits. Convention matches QUI_Options/framework.lua
    -- CreateDropdownScrollBody (uses the same SCROLLBAR_WIDTH = 6 and
    -- accent color with 0.5 alpha).
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

    -- Sticky self-row + 1px separator above it. Both hidden until Refresh
    -- (via Task 9's _UpdateStickyVisibility) decides the local player is
    -- outside the visible scroll range.
    self.stickyRow = self:_BuildStickyRow()

    local separator = self.frame:CreateTexture(nil, "OVERLAY")
    separator:SetHeight(1)
    separator:SetPoint("LEFT",   self.stickyRow, "TOPLEFT",  0, 0)
    separator:SetPoint("RIGHT",  self.stickyRow, "TOPRIGHT", 0, 0)
    separator:SetColorTexture(0, 0, 0, 1)
    separator:Hide()
    self.stickySeparator = separator

    self:_EnsureRowPool()

    RegisterWithLayoutMode(self)

    return self
end

function Window:Hide() if self.frame then self.frame:Hide() end end
function Window:Show() if self.frame then self.frame:Show() end end
function Window:Destroy()
    if self.frame then self.frame:Hide(); self.frame:SetParent(nil) end
    if self._breakdown and self._breakdown.Close then self._breakdown:Close() end
    self.frame, self.backdrop, self.header, self.rows = nil, nil, nil, {}
end

-- Phase 4: open a breakdown popup for the given source row. Lazy-creates
-- the Breakdown frame on first call; subsequent calls reuse the same instance.
function Window:OpenBreakdown(source, anchorRow)
    if not self._breakdown then
        self._breakdown = Breakdown.New(self)
    end
    self._breakdown:Open(source, anchorRow)
end

-- Called from Window:Refresh fan-out: keep an open breakdown popup in sync
-- with new Data ticks.
function Window:RefreshBreakdown()
    if self._breakdown and self._breakdown:IsOpen() then
        self._breakdown:Refresh()
    end
end

-- ==== Breakdown (Phase 4) ====
-- Per-source spell breakdown popup. One Breakdown instance per parent Window;
-- the Window holds a reference so closing the window auto-closes the popup.
-- `Breakdown` is forward-declared in the Window section above.
Breakdown = {}
Breakdown.__index = Breakdown
QUI_DamageMeter.Breakdown = Breakdown
local BREAKDOWN_POOL_SIZE = 25
local TARGET_POOL_SIZE    = 10   -- max target rows shown beneath the spell list
local TARGETS_LABEL_H     = 16   -- height of the "Targets" section label

-- Position helper. If anchor=="row" we anchor TOPLEFT of popup to TOPRIGHT of
-- the row. We mirror to TOPRIGHT→TOPLEFT when the popup would overflow the
-- screen on the right. "center" pins to UIParent center.
local function AnchorBreakdownTo(popup, row, anchorMode)
    popup.frame:ClearAllPoints()
    if anchorMode == "center" or not row then
        popup.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    -- "row" mode. Compute right-edge of popup; flip if it overflows.
    local rowR, _ = row:GetRight(), row:GetTop()
    local uiW = UIParent:GetWidth() or 1280
    local popupW = popup.frame:GetWidth()
    if rowR and (rowR + popupW + 6) > uiW then
        popup.frame:SetPoint("TOPRIGHT", row, "TOPLEFT", -4, 0)
    else
        popup.frame:SetPoint("TOPLEFT", row, "TOPRIGHT", 4, 0)
    end
end

-- Shared icon / bar / name / value visuals for a breakdown row (spell rows and
-- target rows are visually identical; only their anchoring differs).
function Breakdown:_AttachBreakdownRowVisuals(row, barH)
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
    row.Name:SetPoint("LEFT", row.Bar, "LEFT", 4, 0)
    row.Name:SetJustifyH("LEFT")

    row.Value = row.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Value:SetPoint("RIGHT", row.Bar, "RIGHT", -4, 0)
    row.Value:SetJustifyH("RIGHT")
end

function Breakdown:_BuildRow(index)
    local barH = ResolveAppearance(self.parentWindowID, "barHeight") or 18
    local barGap = ResolveAppearance(self.parentWindowID, "barSpacing") or 2
    local headerH = ResolveAppearance(self.parentWindowID, "headerHeight") or 22

    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(barH)
    row:SetPoint("LEFT",  self.frame, "LEFT",  0, 0)
    row:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
    if index == 1 then
        row:SetPoint("TOP", self.frame, "TOP", 0, -headerH)
    else
        row:SetPoint("TOP", self.rows[index - 1], "BOTTOM", 0, -barGap)
    end

    self:_AttachBreakdownRowVisuals(row, barH)
    row:Hide()
    return row
end

-- Target rows live below the "Targets" label. Row 1 anchors to the label
-- (whose own TOP anchor is repositioned each Refresh below the last spell row);
-- subsequent rows chain off the previous target row.
function Breakdown:_BuildTargetRow(index)
    local barH = ResolveAppearance(self.parentWindowID, "barHeight") or 18
    local barGap = ResolveAppearance(self.parentWindowID, "barSpacing") or 2

    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(barH)
    row:SetPoint("LEFT",  self.frame, "LEFT",  0, 0)
    row:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
    if index == 1 then
        row:SetPoint("TOP", self.TargetsLabel, "BOTTOM", 0, -barGap)
    else
        row:SetPoint("TOP", self.targetRows[index - 1], "BOTTOM", 0, -barGap)
    end

    self:_AttachBreakdownRowVisuals(row, barH)
    row:Hide()
    return row
end

-- Static factory (dot, not colon) — see Window.New for why.
function Breakdown.New(parentWindow)
    local self = setmetatable({
        parentWindow    = parentWindow,
        parentWindowID  = parentWindow.windowID,
        source          = nil,    -- set by :Open(source)
        rows            = {},
        _lastGeneration = -1,
    }, Breakdown)

    local frame = CreateFrame("Frame", "QUI_DamageMeterBreakdown" .. parentWindow.windowID, UIParent)
    frame:SetSize(240, 180)   -- height is recomputed each Refresh based on visible row count
    frame:SetFrameStrata("HIGH")   -- spec: popup over the meter window
    frame:SetClampedToScreen(true)
    frame:Hide()
    self.frame = frame

    -- Backdrop
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
    bgTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    self.backdropTex = bgTex

    -- Header
    local headerH = ResolveAppearance(self.parentWindowID, "headerHeight") or 22
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(headerH)
    self.header = header

    self.TitleLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.TitleLabel:SetPoint("LEFT", header, "LEFT", 6, 0)
    self.TitleLabel:SetText("")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(headerH - 6, headerH - 6)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints(closeBtn)
    closeTex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetScript("OnClick", function() self:Close() end)
    self.CloseButton = closeBtn

    -- Spell row pool
    for i = 1, BREAKDOWN_POOL_SIZE do
        self.rows[i] = self:_BuildRow(i)
    end

    -- Targets section: a label ("Targets" / "Attacked By") + its own row pool.
    -- The label's TOP anchor is repositioned each Refresh (below the last spell
    -- row), so it's created here only to be the stable anchor for target row 1.
    self.TargetsLabel = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.TargetsLabel:SetJustifyH("LEFT")
    self.TargetsLabel:SetHeight(TARGETS_LABEL_H)   -- deterministic height for row-1 anchoring
    self.TargetsLabel:SetText("")
    self.TargetsLabel:Hide()
    self.targetRows = {}
    for i = 1, TARGET_POOL_SIZE do
        self.targetRows[i] = self:_BuildTargetRow(i)
    end

    -- Outside-click dismissal (via GLOBAL_MOUSE_DOWN). Only registered while open.
    self._dismissFrame = CreateFrame("Frame")
    self._dismissFrame:SetScript("OnEvent", function(_, _event, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        if not self.frame:IsShown() then return end
        if frame:IsMouseOver() then return end
        self:Close()
    end)

    return self
end

function Breakdown:_SetSpellRow(row, spell, maxAmount)
    ApplyRowBackgroundVisibility(row, self.parentWindowID)

    -- Icon: spell iconID if available; else fallback question mark.
    if spell.iconID and spell.iconID ~= 0 then
        row.Icon:SetTexture(spell.iconID)
    else
        row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    row.Name:SetText((spell.rank or 0) .. ". " .. (spell.name or "?"))
    local numberFormat = ResolveAppearance(self.parentWindowID, "numberFormat") or "compact"
    row.Value:SetText(FormatNumber(spell.totalAmount, numberFormat))

    -- Bar fill: feed raw values to the StatusBar widget, same secret-safe path
    -- as the main rows (see ComputeBarFill) — never divide in Lua. The
    -- breakdown is gated during combat today, but routing through the widget
    -- keeps it correct if a spell amount is ever secret-tagged and stays
    -- consistent with the main meter. nil meter/deaths types skip those
    -- branches; spells have no per-second or Deaths handling.
    local IsSecret = Helpers and Helpers.IsSecretValue
    local fillMin, fillMaxValue, fillValue = ComputeBarFill(nil, spell, maxAmount, nil, IsSecret)
    row.Bar:SetMinMaxValues(fillMin, fillMaxValue)
    row.Bar:SetValue(fillValue or 0)

    -- Bar color: inherit parent window's accent or custom color (class color
    -- doesn't apply to spells).
    local alpha = ResolveAppearance(self.parentWindowID, "barFillAlpha") or 1
    if ResolveAppearance(self.parentWindowID, "barColorAccent") then
        local ar, ag, ab = GetAccentColor()
        row.Bar:SetStatusBarColor(ar, ag, ab, alpha)
    else
        local bc = ResolveAppearance(self.parentWindowID, "barColor") or { 0.35, 0.55, 0.8, 1 }
        row.Bar:SetStatusBarColor(bc[1] or 0.35, bc[2] or 0.55, bc[3] or 0.8, alpha)
    end
end

-- A target row: an enemy this player hit, or a player who hit this enemy.
-- target = { name, totalAmount, classFilename?, specIconID? }. Class data is
-- present only for player targets (enemy->players direction); enemy targets
-- render with a blank icon slot (matching iconStyle "none").
function Breakdown:_SetTargetRow(row, target, maxAmount)
    ApplyRowBackgroundVisibility(row, self.parentWindowID)

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

    row.Name:SetText(ShortenName(target.name) or "?")
    local numberFormat = ResolveAppearance(self.parentWindowID, "numberFormat") or "compact"
    row.Value:SetText(FormatNumber(target.totalAmount, numberFormat))

    -- Aggregated target totals are plain Lua numbers (secret amounts were
    -- skipped during aggregation), but route through the widget anyway for
    -- consistency with the rest of the meter.
    local IsSecret = Helpers and Helpers.IsSecretValue
    local fillMin, fillMaxValue, fillValue = ComputeBarFill(nil, target, maxAmount, nil, IsSecret)
    row.Bar:SetMinMaxValues(fillMin, fillMaxValue)
    row.Bar:SetValue(fillValue or 0)

    -- Bar color: class color for known players, else parent accent / custom.
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

-- Decide which target list (and section label) to show for the current meter
-- type. DamageDone/Dps source = a player → the enemies they hit. EnemyDamageTaken
-- source = an enemy → the players who hit it. Other types have no target view.
function Breakdown:_ResolveTargets(meterType)
    local T = Enum and Enum.DamageMeterType
    if not (T and self.source) then return nil, nil end
    local st = self.parentWindow.sessionType
    local sid = self.parentWindow.sessionID
    if meterType == T.EnemyDamageTaken then
        return Data:GetEnemyAttackers(st, self.source.sourceGUID, self.source.sourceCreatureID, sid), "Attacked By"
    elseif meterType == T.DamageDone or meterType == T.Dps then
        return Data:GetPlayerTargets(st, self.source.name, sid), "Targets"
    end
    return nil, nil
end

function Breakdown:Refresh()
    if not self.source or not self.frame:IsShown() then return end
    local _t0 = Perf.enabled and PerfNow() or 0
    local sessionType   = self.parentWindow.sessionType
    local sessionID = self.parentWindow.sessionID
    local damageMeterType = self.parentWindow.damageMeterType
    -- Healing breakdown optionally merges absorbs (settings.combineAbsorbsIntoHealing).
    local view
    local s_combo = GetSettings()
    if IsHealingType(damageMeterType)
        and s_combo and s_combo.combineAbsorbsIntoHealing then
        view = Data:GetCombinedHealingBreakdown(sessionType,
            self.source.sourceGUID, self.source.sourceCreatureID, sessionID)
    else
        view = Data:GetBreakdownView(sessionType, damageMeterType,
            self.source.sourceGUID, self.source.sourceCreatureID, sessionID)
    end

    -- Title: "Damage Done by <Name>"
    local label = LabelForType(damageMeterType)
    self.TitleLabel:SetText(label .. " by " .. (ShortenName(self.source.name) or "?"))

    local visibleCount = math.min(#view.spells, BREAKDOWN_POOL_SIZE)
    for i = 1, visibleCount do
        self:_SetSpellRow(self.rows[i], view.spells[i], view.maxAmount)
        self.rows[i]:Show()
    end
    for i = visibleCount + 1, #self.rows do
        self.rows[i]:Hide()
    end

    local barH    = ResolveAppearance(self.parentWindowID, "barHeight") or 18
    local barGap  = ResolveAppearance(self.parentWindowID, "barSpacing") or 2
    local headerH = ResolveAppearance(self.parentWindowID, "headerHeight") or 22

    -- Targets section beneath the spell list. The label re-anchors below the
    -- last visible spell row (or the header when there are no spells).
    local targets, targetsLabel = self:_ResolveTargets(damageMeterType)
    local targetCount = 0
    if targets and #targets > 0 and targetsLabel then
        targetCount = math.min(#targets, TARGET_POOL_SIZE)
    end
    if targetCount > 0 then
        self.TargetsLabel:ClearAllPoints()
        if visibleCount > 0 then
            self.TargetsLabel:SetPoint("TOPLEFT", self.rows[visibleCount], "BOTTOMLEFT", 6, -barGap)
        else
            self.TargetsLabel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 6, -headerH)
        end
        self.TargetsLabel:SetText(targetsLabel)
        self.TargetsLabel:Show()
        local tMax = targets[1].totalAmount
        for i = 1, targetCount do
            self:_SetTargetRow(self.targetRows[i], targets[i], tMax)
            self.targetRows[i]:Show()
        end
        for i = targetCount + 1, #self.targetRows do self.targetRows[i]:Hide() end
    else
        self.TargetsLabel:Hide()
        for i = 1, #self.targetRows do self.targetRows[i]:Hide() end
    end

    -- Resize frame to fit header + spell rows [+ targets label + target rows],
    -- with a trailing barGap of padding. Matches the anchor chain above.
    local spellBlock  = visibleCount > 0 and (visibleCount * barH + (visibleCount - 1) * barGap) or 0
    local targetBlock = targetCount > 0
        and (TARGETS_LABEL_H + barGap + targetCount * barH + (targetCount - 1) * barGap) or 0
    local totalH = headerH
    if visibleCount > 0 and targetCount > 0 then
        totalH = headerH + spellBlock + barGap + targetBlock + barGap
    elseif visibleCount > 0 then
        totalH = headerH + spellBlock + barGap
    elseif targetCount > 0 then
        totalH = headerH + targetBlock + barGap
    end
    self.frame:SetHeight(totalH)

    if Perf.enabled then Perf:Record("breakdown", PerfNow() - _t0) end
end

function Breakdown:Open(source, anchorRow)
    self.source = source
    local anchorMode = (GetSettings() and GetSettings().breakdownAnchor) or "row"
    AnchorBreakdownTo(self, anchorRow, anchorMode)
    self.frame:Show()
    self:Refresh()
    -- Register outside-click dismissal AFTER showing (so the show event itself
    -- doesn't trip GLOBAL_MOUSE_DOWN).
    self._dismissFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

function Breakdown:Close()
    self.frame:Hide()
    self.source = nil
    self._dismissFrame:UnregisterAllEvents()
end

function Breakdown:IsOpen()
    return self.frame and self.frame:IsShown() or false
end

-- ==== WindowManager ====
local WindowManager = {
    windows = {},   -- [windowID] = Window instance (table)
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

function WindowManager:Spawn(windowID)
    if self.windows[windowID] then return self.windows[windowID] end
    -- Window:New is wired in T9. Until then, Spawn is harmless to call
    -- (returns nil) and tests just assert the surface exists.
    if not Window.New then return nil end
    local instance = Window.New(windowID)
    self.windows[windowID] = instance
    if windowID >= self.nextID then self.nextID = windowID + 1 end
    return instance
end

function WindowManager:Despawn(windowID)
    local instance = self.windows[windowID]
    if not instance then return end
    if instance.Hide then instance:Hide() end
    if instance.Destroy then instance:Destroy() end
    self.windows[windowID] = nil

    -- Phase 3: also unregister from Layout Mode + the frame resolver registry
    -- so the dead window doesn't continue to claim a slot in the layout list.
    local key = LayoutKey(windowID)
    if ns.QUI_LayoutMode and ns.QUI_LayoutMode.UnregisterElement then
        pcall(ns.QUI_LayoutMode.UnregisterElement, ns.QUI_LayoutMode, key)
    end
    if _G.QUI_UnregisterFrameResolver then
        pcall(_G.QUI_UnregisterFrameResolver, key)
    end
    local Registry = ns.Settings and ns.Settings.Registry
    if Registry and type(Registry.UnregisterLookupKey) == "function" then
        Registry:UnregisterLookupKey(WINDOW_LAYOUT_FEATURE_ID, key)
    end
end

-- Despawn every live window. Used when the feature toggle flips off mid-session
-- so windows disappear immediately instead of lingering until the next reload.
-- Savedvars entries in s.windows are untouched, so a re-enable + reload respawns
-- the same windows at their saved positions.
function WindowManager:DespawnAll()
    -- Snapshot keys first; Despawn mutates self.windows.
    local ids = {}
    for windowID in pairs(self.windows) do
        ids[#ids + 1] = windowID
    end
    for _, windowID in ipairs(ids) do
        self:Despawn(windowID)
    end
end

function WindowManager:ClearRuntimeSessionIDs()
    local s = GetSettings()
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

-- Phase 3: hard cap matches spec's "5 windows" budget. Settings UI's
-- "+ Add Window" button is disabled when at cap.
local MAX_WINDOWS = 5

function WindowManager:Count()
    local n = 0
    for _ in pairs(self.windows) do n = n + 1 end
    return n
end

-- Allocate the lowest unused windowID >= 2 (ID 1 is reserved for the
-- seeded default window). IDs are recycled when slots free up so users see
-- stable, low numbers (2, 3, 4...) instead of an ever-growing counter that
-- climbs after each add/delete cycle.
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
    }
    s.windowCount = (s.windowCount or 0) + 1

    -- Seed a cascade-offset position so new windows don't all stack at
    -- CENTER. Position lives in shared frameAnchoring (same DB as every other
    -- mover); RegisterWithLayoutMode → QUI_ApplyFrameAnchor reads it on spawn.
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

-- Despawn + delete from savedvars. Distinct from Despawn (which keeps the
-- savedvars entry so a reload respawns the same window).
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

-- Phase 3: spawn every window in saved state. Called from PLAYER_LOGIN.
-- Returns count of spawned windows.
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
    -- Force every live window to re-render NOW. Used by:
    --   - settings widget callbacks (texture, font, color changes)
    --   - ConfigButton menu actions (type / session switch)
    -- We bypass the _lastGeneration short-circuit by clearing it; the next
    -- Refresh() call walks all the source binding logic and re-applies
    -- appearance from current settings.
    for _, w in pairs(self.windows) do
        if w then
            w._lastGeneration = -1
            if w.Refresh then w:Refresh() end
        end
    end
end

local function ResetAllDamageMeterSessions()
    if not (C_DamageMeter and C_DamageMeter.ResetAllCombatSessions) then return false end
    C_DamageMeter.ResetAllCombatSessions()
    Data:ResetCombatClock()
    Data:ClearCachedViews()
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

    if not s.autoSwapChallengeSessions then return end
    local S = Enum and Enum.DamageMeterSessionType
    local currentSession = (S and S.Current) or 1
    local overallSession = (S and S.Overall) or 0

    self:Enumerate(function(_windowID, w)
        if w and w.sessionID == nil and w.sessionType == overallSession then
            local windowState = s.windows and s.windows[w.windowID]
            w.sessionType = currentSession
            if windowState then windowState.sessionType = currentSession end
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then
                w._breakdown:Close()
            end
        end
    end)
    self:RefreshAll()
end

function WindowManager:ApplyChallengeModeCompleted()
    local s = GetSettings()
    if not (s and s.autoSwapChallengeSessions) then return end
    local S = Enum and Enum.DamageMeterSessionType
    local currentSession = (S and S.Current) or 1
    local overallSession = (S and S.Overall) or 0

    self:Enumerate(function(_windowID, w)
        if w and w.sessionID == nil and w.sessionType == currentSession then
            local windowState = s.windows and s.windows[w.windowID]
            w.sessionType = overallSession
            if windowState then windowState.sessionType = overallSession end
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then
                w._breakdown:Close()
            end
        end
    end)
    self:RefreshAll()
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

-- T12: Data._onChange fan-out to every live window
-- Note: Data:_onChange is declared here (not in the Data section above) because
-- it references WindowManager, which is defined later. Lua captures WindowManager
-- as an upvalue at call time, so the late definition is fine.
Data._onChange = function(self)
    local clearRuntimeSessions = self._clearRuntimeSessions
    self._clearRuntimeSessions = false
    if clearRuntimeSessions and WindowManager.ClearRuntimeSessionIDs then
        WindowManager:ClearRuntimeSessionIDs()
    end
    WindowManager:Enumerate(function(_id, w)
        if w.Refresh then w:Refresh() end
    end)
end

-- ==== Init ====
-- Lockdown queue. Phase 1 only needs this for the spawn-on-login path that
-- happens when PLAYER_LOGIN fires during combat (rare but possible on
-- reload-mid-pull). Pattern mirrors the skinner's pendingCombatWrites.
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
QUI_DamageMeter._QueueOrRun = QueueOrRun  -- for T16

local function ApplyBlizzardSuppression(enabled)
    -- Flip the canonical CVar Blizzard uses to gate the stock meter.
    if SetCVar then
        SetCVar("damageMeterEnabled", enabled and "0" or "1")
    end
    -- Defensive: if the Blizzard meter is already loaded, hide it now. The
    -- CVar flip will hide it on next addon load anyway, but this covers the
    -- in-session case (settings change without reload).
    if enabled and _G.DamageMeter and _G.DamageMeter.Hide then
        _G.DamageMeter:Hide()
    end
end
QUI_DamageMeter.ApplyBlizzardSuppression = ApplyBlizzardSuppression

-- LOD module: PLAYER_LOGIN already fired before this addon loads, so init
-- runs via ns.WhenLoggedIn (immediate when logged in, deferred otherwise).
-- ns.WhenLoggedIn is nil only in the headless test harness, where the old
-- never-firing PLAYER_LOGIN registration was equally inert.
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        local s = GetSettings()
        if not s then return end
        ApplyBlizzardSuppression(true)
        QueueOrRun(function()
            -- Phase 3: spawn every window in saved state, not just windowID 1.
            WindowManager:LoadSavedWindows()
        end)
    end)
end

-- ==== Reset Keybind (Follow-up C) ====
-- Expose "Reset All Sessions" via Blizzard's Keybindings UI under a "QUI Damage
-- Meter" header. Users assign a key in Esc → Keybindings → QUI Damage Meter.
-- Implementation pattern: SecureActionButton with a macrotext that calls the
-- (non-protected) C_DamageMeter reset; binding name uses the CLICK <button>:LeftButton
-- convention so it shows up in the standard bindings panel.
_G.BINDING_HEADER_QUI_DAMAGEMETER = "QUI Damage Meter"
_G["BINDING_NAME_CLICK QUI_DM_ResetBindingTarget:LeftButton"] = "Reset All Sessions"

local resetBindBtn = CreateFrame("Button", "QUI_DM_ResetBindingTarget", UIParent, "SecureActionButtonTemplate")
resetBindBtn:Hide()
resetBindBtn:SetAttribute("type", "macro")
resetBindBtn:SetAttribute("macrotext",
    "/run if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then C_DamageMeter.ResetAllCombatSessions() end")
QUI_DamageMeter._ResetBindButton = resetBindBtn

-- Also expose a slash command for users who prefer macro-based binds.
-- NOTE: Only ever write *keys* into SlashCmdList (the normal addon pattern).
-- Do NOT reassign the SlashCmdList global itself (e.g. `_G.SlashCmdList = ...`)
-- — that taints the global binding, and FrameXML re-reads it on every chat
-- parse (ImportAllListsToHash), propagating QUI taint into slash dispatch and
-- breaking zero-taint commands like /tm ("QUI tried to call SetRaidTarget()").
_G.SLASH_QUI_DM_RESET1 = "/quidmreset"
_G.SlashCmdList["QUI_DM_RESET"] = function()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
        print("|cff30D1FF[QUI]|r Damage meter sessions reset.")
    end
end

-- ==== Perf slash command (Follow-up D) ====
-- /quidmperf            — print current summary
-- /quidmperf on / off   — toggle instrumentation
-- /quidmperf reset      — clear the ring buffers
_G.SLASH_QUI_DM_PERF1 = "/quidmperf"
_G.SlashCmdList["QUI_DM_PERF"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "on" then
        Perf.enabled = true
        Perf:Reset()
        print("|cff30D1FF[QUI]|r Damage meter perf instrumentation: |cff00ff00ON|r")
    elseif msg == "off" then
        Perf.enabled = false
        print("|cff30D1FF[QUI]|r Damage meter perf instrumentation: |cffff6060OFF|r")
    elseif msg == "reset" then
        Perf:Reset()
        print("|cff30D1FF[QUI]|r Damage meter perf buffers reset.")
    else
        if not Perf.enabled then
            print("|cff30D1FF[QUI]|r Perf is OFF. Run |cffffffff/quidmperf on|r to enable, then re-run to see the summary.")
            return
        end
        print("|cff30D1FF[QUI]|r Damage meter perf summary:")
        for _, line in ipairs(Perf:Summary()) do print(line) end
    end
end

-- Companion skinning registration: damage-meter window backgrounds fall back to
-- the global skin bg (GetSkinBgColor) when no per-window color is set, but the
-- module isn't otherwise refreshed on a skin-color change (which fires only
-- RefreshAll("skinning")). WindowManager:RefreshAll clears each window's
-- generation cache and re-applies appearance from current settings.
if ns.Registry then
    ns.Registry:Register("damageMeterSkin", {
        refresh = function()
            if WindowManager and WindowManager.RefreshAll then
                WindowManager:RefreshAll()
            end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "damageMeter",
        label = "Damage Meter",
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
