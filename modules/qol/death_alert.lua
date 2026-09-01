local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local ALERT_HOLD = 3
local RECAP_RETRY_DELAYS = { 0.3, 1.0 }

local alertFrame, alertText
local deadState = {}
local tracked = {}
local hideTimer = 0
local alertSerial = 0

local function Cfg()
    local s = GetSettings()
    return s and s.deathAlert or nil
end

local function Enabled()
    local cfg = Cfg()
    if not (cfg and cfg.enabled == true and IsInGroup()) then return false end
    if cfg.instanceOnly and not ns.Utils.IsInInstancedContent() then return false end
    return true
end

local function EnsureFrame()
    if alertFrame then return end
    alertFrame = CreateFrame("Frame", "QUI_DeathAlertFrame", UIParent)
    alertFrame:SetSize(400, 40)
    alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    alertFrame:SetFrameStrata("HIGH")
    alertText = alertFrame:CreateFontString(nil, "OVERLAY")
    alertText:SetAllPoints()
    local font = Helpers.GetGeneralFont and Helpers.GetGeneralFont()
    if ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(alertText, font or STANDARD_TEXT_FONT, 24, "OUTLINE")
    else
        alertText:SetFont(font or STANDARD_TEXT_FONT, 24, "OUTLINE")
    end
    alertText:SetTextColor(1, 0.25, 0.25)
    alertFrame:Hide()
    alertFrame:SetScript("OnUpdate", function(self, elapsed)
        hideTimer = hideTimer - elapsed
        if hideTimer <= 0 then self:Hide() end
    end)
    -- The frame is created lazily, so the startup anchor pass could not have
    -- resolved it; pull in any saved Layout Mode anchor now (mplus_timer.lua
    -- does the same).
    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor("deathAlert")
    end
end

local function ApplyPosition()
    local cfg = Cfg()
    if not alertFrame or not cfg then return end
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("deathAlert")) then
        alertFrame:ClearAllPoints()
        alertFrame:SetPoint("CENTER", UIParent, "CENTER",
            tonumber(cfg.offsetX) or 0, tonumber(cfg.offsetY) or 220)
    end
    local size = tonumber(cfg.fontSize) or 24
    local font = Helpers.GetGeneralFont and Helpers.GetGeneralFont()
    if ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(alertText, font or STANDARD_TEXT_FONT, size, "OUTLINE")
    end
end

local function PlayAlertSound()
    local cfg = Cfg()
    local soundName = cfg and cfg.sound
    if not soundName or soundName == "None" or soundName == "" then return end
    local LSM = ns.LSM
    local path = LSM and LSM:Fetch("sound", soundName)
    if path and type(path) == "string" then
        PlaySoundFile(path, "Master")
    end
end

-- Killing-blow lookup: CLEU is gutted for addons in 12.x, but the native
-- damage meter's Deaths session lists a deathRecapID per combatSources entry
-- (NeverSecret, readable in combat) that keys C_DeathRecap. Everything here
-- degrades to nil and the alert stays "Name died!".
--
-- Identity is by recapID novelty, not GUID: sourceGUID/name on the entries
-- can be secret in combat and must never be compared, while deathRecapID and
-- classFilename are NeverSecret. knownRecapIDs is the baseline of recaps that
-- predate the death being announced.
local function ForEachDeathSource(callback)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end
    local S = Enum and Enum.DamageMeterSessionType
    local T = Enum and Enum.DamageMeterType
    if not (S and S.Current and T and T.Deaths) then return end
    for _, sessionType in ipairs({ S.Current, S.Overall }) do
        local duration
        if C_DamageMeter.GetSessionDurationSeconds then
            local okD, d = ns.SafeCall("best-effort-style",
                C_DamageMeter.GetSessionDurationSeconds, sessionType)
            if okD and not Helpers.IsSecretValue(d) and type(d) == "number" then
                duration = d
            end
        end
        local ok, session = ns.SafeCall("best-effort-style",
            C_DamageMeter.GetCombatSessionFromType, sessionType, T.Deaths)
        if ok and not Helpers.IsSecretValue(session) and type(session) == "table" then
            local sources = session.combatSources
            if not Helpers.IsSecretValue(sources) and type(sources) == "table" then
                for i = 1, #sources do
                    local src = sources[i]
                    if not Helpers.IsSecretValue(src) and type(src) == "table" then
                        local recapID = src.deathRecapID
                        if Helpers.IsSecretValue(recapID)
                            or type(recapID) ~= "number" or recapID <= 0 then
                            recapID = nil -- @secret-policy: reject-secret-ids
                        end
                        local age
                        local deathTime = src.deathTimeSeconds
                        if duration and not Helpers.IsSecretValue(deathTime)
                            and type(deathTime) == "number" then
                            age = duration - deathTime
                        end
                        if recapID and callback(recapID, src, age) then return end
                    end
                end
            end
        end
    end
end

local knownRecapIDs = {}

-- Every recap on record becomes ineligible for future attribution. Called at
-- the end of each enrichment chain so recaps that were observed but never
-- displayed (simultaneous deaths, unreadable events, ambiguous class matches)
-- cannot contaminate a later death's novelty scan.
local function RetireObservedRecapIDs()
    ForEachDeathSource(function(recapID)
        knownRecapIDs[recapID] = true
    end)
end

local function SnapshotKnownRecapIDs()
    wipe(knownRecapIDs)
    RetireObservedRecapIDs()
end

local function UnitClassToken(unit)
    local ok, _, classToken = ns.SafeCall("best-effort-style", UnitClass, unit)
    if not ok or Helpers.IsSecretValue(classToken) or type(classToken) ~= "string" then
        return nil -- @secret-policy: defer-until-readable
    end
    return classToken
end

-- Ledger of deaths this module itself observed. Recap identity cannot be
-- established from the meter entries in combat (sourceGUID/name may be
-- secret), so the ledger is what prevents cross-player theft: while another
-- unclaimed death of the same (or unknown) class is pending, no recap is
-- attributed at all — its recap could be the one on record.
local PENDING_DEATH_TTL = 10
local pendingDeaths = {}

local function RecordPendingDeath(unit, serial)
    pendingDeaths[#pendingDeaths + 1] = {
        class = UnitClassToken(unit) or false,
        serial = serial,
        time = GetTime(),
        claimed = false,
    }
end

local function ClaimPendingDeath(serial)
    for i = 1, #pendingDeaths do
        if pendingDeaths[i].serial == serial then
            pendingDeaths[i].claimed = true
        end
    end
end

local function HasCompetingPendingDeath(classToken, serial)
    local now = GetTime()
    for i = #pendingDeaths, 1, -1 do
        if now - pendingDeaths[i].time > PENDING_DEATH_TTL then
            table.remove(pendingDeaths, i)
        end
    end
    for i = 1, #pendingDeaths do
        local death = pendingDeaths[i]
        if death.serial ~= serial and not death.claimed
            and (death.class == false or death.class == classToken) then
            return true
        end
    end
    return false
end

-- A recap is attributed to the alerted unit only when it is novel, its
-- NeverSecret classFilename matches the unit's class, it is not stale by the
-- recap's own death time, no competing pending death could own it, and it is
-- the ONLY candidate satisfying all that. A sole novel recap is never taken
-- on novelty alone: it may belong to an earlier death whose chain was
-- superseded before its recap arrived.
local RECAP_MAX_AGE = 5

local function FindNewRecapID(unit, serial)
    local classToken = UnitClassToken(unit)
    if not classToken then return nil end
    if HasCompetingPendingDeath(classToken, serial) then return nil end
    local match, ambiguous
    ForEachDeathSource(function(recapID, src, age)
        if knownRecapIDs[recapID] then return end
        if age and age > RECAP_MAX_AGE then
            -- Predates this death; retire it so it stops surfacing as novel.
            knownRecapIDs[recapID] = true
            return
        end
        local class = src.classFilename
        if Helpers.IsSecretValue(class) or type(class) ~= "string" then return end
        if class ~= classToken then return end
        if match and match ~= recapID then ambiguous = true end
        match = recapID
    end)
    if ambiguous then return nil end
    return match
end

local function GetKillingBlowEvent(recapID)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
    local ok, events = ns.SafeCall("best-effort-style", C_DeathRecap.GetRecapEvents, recapID)
    if not ok or Helpers.IsSecretValue(events) or type(events) ~= "table" then
        return nil -- @secret-policy: defer-until-readable
    end
    -- Recap events arrive newest-first; index 1 is the killing blow
    -- (Blizzard_DeathRecap flags it causedDeath).
    local blow = events[1]
    if Helpers.IsSecretValue(blow) or type(blow) ~= "table" then return nil end
    return blow
end

local function DescribeKillingBlow(event)
    local eventType = event.event
    if Helpers.IsSecretValue(eventType) then eventType = nil end

    local sourceName
    local hideCaster = event.hideCaster
    if not Helpers.IsSecretValue(hideCaster) and not hideCaster then
        local name = event.sourceName
        if not Helpers.IsSecretValue(name) and type(name) == "string" and name ~= "" then
            sourceName = name
        end
    end

    if eventType == "SWING_DAMAGE" then
        return _G.ACTION_SWING or "Melee", sourceName
    end
    if eventType == "ENVIRONMENTAL_DAMAGE" then
        local env = event.environmentalType
        if Helpers.IsSecretValue(env) or type(env) ~= "string" then
            return nil, nil -- @secret-policy: defer-until-readable
        end
        env = string.upper(env)
        return _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. env] or env, nil
    end

    local spellName = event.spellName
    if Helpers.IsSecretValue(spellName) or type(spellName) ~= "string" or spellName == "" then
        return nil, sourceName -- @secret-policy: defer-until-readable
    end
    return spellName, sourceName
end

local function ComposeText(who, blowName, killerName)
    if blowName and killerName then
        return string.format(ns.L["%s died to %s from %s!"], who, blowName, killerName)
    end
    if blowName then
        return string.format(ns.L["%s died to %s!"], who, blowName)
    end
    return who .. " " .. ns.L["died!"]
end

local function DisplayName(unit)
    local who = ns.L["An ally"]
    local okName, name = pcall(UnitName, unit)
    name = Helpers.SafeValue(name)
    if okName and name and name ~= "" then
        who = name
    end
    local cfg = Cfg()
    if cfg and cfg.classColorName then
        local r, g, b = Helpers.GetUnitClassColor(unit)
        who = string.format("|cff%02x%02x%02x%s|r",
            (r or 1) * 255, (g or 1) * 255, (b or 1) * 255, who)
    end
    return who
end

local function TryEnrich(unit, who, serial, attempt)
    -- A newer death owns the alert now; its chain will retire leftovers.
    if serial ~= alertSerial then return end
    local cfg = Cfg()
    if not (cfg and cfg.showKillingBlow) then return end
    if not (alertFrame and alertFrame:IsShown()) then
        RetireObservedRecapIDs()
        return
    end

    local recapID = FindNewRecapID(unit, serial)
    if recapID then
        local blow = GetKillingBlowEvent(recapID)
        local blowName, killerName
        if blow then
            blowName, killerName = DescribeKillingBlow(blow)
        end
        if blowName then
            if not cfg.showKiller then killerName = nil end
            alertText:SetText(ComposeText(who, blowName, killerName))
            ClaimPendingDeath(serial)
            RetireObservedRecapIDs()
            return
        end
    end

    local delay = RECAP_RETRY_DELAYS[attempt + 1]
    if delay then
        C_Timer.After(delay, function() TryEnrich(unit, who, serial, attempt + 1) end)
    else
        RetireObservedRecapIDs()
    end
end

local function ShowAlert(unit)
    EnsureFrame()
    ApplyPosition()
    local cfg = Cfg()
    local who = DisplayName(unit)
    alertSerial = alertSerial + 1
    alertText:SetText(ComposeText(who, nil, nil))
    hideTimer = tonumber(cfg and cfg.duration) or ALERT_HOLD
    alertFrame:Show()
    PlayAlertSound()
    if cfg and cfg.showKillingBlow then
        RecordPendingDeath(unit, alertSerial)
        TryEnrich(unit, who, alertSerial, 0)
    end
end

local function CheckUnit(unit)
    if not tracked[unit] then return end
    local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
    if not okDead or Helpers.IsSecretValue(dead) then return end
    dead = dead and true or false

    if dead and not deadState[unit] then
        local okFeign, feign = pcall(UnitIsFeignDeath, unit)
        if okFeign and not Helpers.IsSecretValue(feign) and feign then
            return
        end
        deadState[unit] = true
        if Enabled() then ShowAlert(unit) end
    elseif not dead and deadState[unit] then
        deadState[unit] = false
    end
end

local function RebuildRoster()
    wipe(tracked)
    wipe(deadState)
    wipe(pendingDeaths)
    if not Enabled() then return end
    local cfg = Cfg()
    if cfg and cfg.showKillingBlow then
        -- Baseline: any recap already on record predates tracking and must
        -- not be announced as the cause of a later death.
        SnapshotKnownRecapIDs()
    end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            tracked[unit] = true
            local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
            deadState[unit] = (okDead and not Helpers.IsSecretValue(dead) and dead) and true or false
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_FLAGS")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        if arg1 then CheckUnit(arg1) end
    else
        RebuildRoster()
    end
end)

ns.RefreshDeathAlert = function()
    RebuildRoster()
    if alertFrame then ApplyPosition() end
end

ns.ToggleDeathAlertPreview = function(show)
    EnsureFrame()
    ApplyPosition()
    if show then
        local cfg = Cfg()
        local blowName = (cfg and cfg.showKillingBlow) and (_G.ACTION_SWING or "Melee") or nil
        alertText:SetText(ComposeText(ns.L["An ally"], blowName, nil))
        hideTimer = math.huge
        alertFrame:Show()
    else
        hideTimer = 0
        alertFrame:Hide()
    end
end
