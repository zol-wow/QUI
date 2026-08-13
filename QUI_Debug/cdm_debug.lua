local _, ns = ...

local Helpers     = ns.Helpers
local CDMIcons    = ns.CDMIcons
local iconPools   = ns.CDMIconFactory and ns.CDMIconFactory._iconPools or {}
local Sources     = ns.CDMSources
local Resolvers   = ns.CDMResolvers
local GetTime     = GetTime

local function TrimText(text)
    return (text and tostring(text) or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function DebugIsSecretValue(value)
    if Helpers and Helpers.IsSecretValue then
        local ok, isSecret = pcall(Helpers.IsSecretValue, value)
        if ok and isSecret then return true end
    end
    if issecretvalue then
        local ok, isSecret = pcall(issecretvalue, value)
        if ok and isSecret then return true end
    end
    return false
end

local function SecureFieldInfo(tbl, field)
    local secure, taint = issecurevariable(tbl, field)
    if secure then return "|cff34D399secure|r" end
    return "|cffff5555tainted:" .. tostring(taint or "?") .. "|r"
end

local function EventTraceCooldownInfoField(info, key)
    if Resolvers and Resolvers.GetCooldownInfoField then
        return Resolvers.GetCooldownInfoField(info, key)
    end
    if not info then return nil, false end

    local value = info[key]
    if DebugIsSecretValue(value) then
        return value, true
    end
    return value, false
end

local function EventTraceGetItemUseSpellID(itemID)
    if not itemID then return nil end

    if Sources and Sources.QueryItemSpell then
        local _, spellID = Sources.QueryItemSpell(itemID)
        if spellID then
            return spellID
        end
    end

    if Sources and Sources.QueryFirstTriggeredSpellForItem then
        local itemQuality
        if Sources.QueryItemQualityByID then
            local quality = Sources.QueryItemQualityByID(itemID)
            if quality ~= nil then
                itemQuality = quality
            end
        end

        local spellID = Sources.QueryFirstTriggeredSpellForItem(itemID, itemQuality)
        if spellID then
            return spellID
        end
    end

    return nil
end

local function EventTraceIsItemLikeEntry(entry)
    return entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
end

local function EventTraceResolveItemCooldownIdentity(entry)
    if not entry then return nil, nil, nil, nil end

    local itemID, slotID
    if entry.type == "item" then
        itemID = entry.id
    elseif entry.type == "trinket" or entry.type == "slot" then
        slotID = entry.id
        if Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", slotID)
        end
        itemID = itemID or entry.itemID
    elseif entry.type == "macro" and Resolvers and Resolvers.ResolveMacro then
        local resolvedID, resolvedType = Resolvers.ResolveMacro(entry)
        if resolvedType == "item" then
            itemID = resolvedID
        end
    end

    if not itemID then return nil, slotID, nil, nil end

    local itemSpellID = EventTraceGetItemUseSpellID(itemID)
    local keySource = slotID and (tostring(slotID) .. ":" .. tostring(itemID)) or tostring(itemID)
    return itemID, slotID, itemSpellID, keySource
end

function CDMIcons.EventTraceValue(value)
    if DebugIsSecretValue(value) then return "<SECRET:" .. type(value) .. ">" end
    if value == nil then return "nil" end
    return tostring(value)
end

function CDMIcons.EventTraceSpellIDMatches(targetID, value)
    if DebugIsSecretValue(value) then return false end
    if not targetID or value == nil then return false end
    return value == targetID
end

local function EventTraceIDList(ids)
    if type(ids) ~= "table" or #ids == 0 then return "nil" end
    local out = {}
    for i, id in ipairs(ids) do
        out[i] = tostring(id)
    end
    return table.concat(out, ",")
end

local function EventTraceAuraSpellID(auraData)
    if type(auraData) ~= "table" then return nil end
    local spellID = auraData.spellId
    if DebugIsSecretValue(spellID) then return spellID end
    if spellID == nil then
        spellID = auraData.spellID
    end
    return spellID
end

local function EventTraceCleanNumber(value)
    if DebugIsSecretValue(value) then return nil end
    if type(value) == "number" then return value end
    return nil
end

local function EventTraceTargetFilterPass(unit, auraInstanceID, filter)
    if DebugIsSecretValue(unit) then return "skip" end
    if unit ~= "target" then return "skip" end
    local cleanAuraInstanceID = EventTraceCleanNumber(auraInstanceID)
    if cleanAuraInstanceID == nil then return "skip" end
    if not (Sources and Sources.QueryAuraFilteredOutByInstanceID) then return "na" end

    local filteredOut = Sources.QueryAuraFilteredOutByInstanceID(unit, cleanAuraInstanceID, filter)
    if DebugIsSecretValue(filteredOut) then
        return CDMIcons.EventTraceValue(filteredOut)
    end
    if type(filteredOut) == "boolean" then
        return tostring(filteredOut == false)
    end
    return CDMIcons.EventTraceValue(filteredOut)
end

local function EventTraceAddedAuras(unit, addedAuras)
    if type(addedAuras) ~= "table" or #addedAuras == 0 then return "nil" end

    local out = {}
    local limit = math.min(#addedAuras, 3)
    for i = 1, limit do
        local auraData = addedAuras[i]
        if type(auraData) == "table" then
            local auraInstanceID = auraData.auraInstanceID
            out[#out + 1] = string.format(
                "#%d inst=%s sid=%s name=%s help=%s harm=%s src=%s helpfulPlayer=%s harmfulPlayer=%s",
                i,
                CDMIcons.EventTraceValue(auraInstanceID),
                CDMIcons.EventTraceValue(EventTraceAuraSpellID(auraData)),
                CDMIcons.EventTraceValue(auraData.name),
                CDMIcons.EventTraceValue(auraData.isHelpful),
                CDMIcons.EventTraceValue(auraData.isHarmful),
                CDMIcons.EventTraceValue(auraData.sourceUnit),
                EventTraceTargetFilterPass(unit, auraInstanceID, "HELPFUL|PLAYER"),
                EventTraceTargetFilterPass(unit, auraInstanceID, "HARMFUL|PLAYER"))
        else
            out[#out + 1] = string.format("#%d=%s", i, CDMIcons.EventTraceValue(auraData))
        end
    end

    if #addedAuras > limit then
        out[#out + 1] = "+" .. tostring(#addedAuras - limit)
    end

    return "[" .. table.concat(out, " | ") .. "]"
end

local function EventTraceEntryMatches(targetID, entry)
    if not (targetID and entry) then return false end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.cooldownID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.overrideSpellID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.spellID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.id) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.itemID) then return true end
    if type(entry.linkedSpellIDs) == "table" then
        for _, linkedID in ipairs(entry.linkedSpellIDs) do
            if CDMIcons.EventTraceSpellIDMatches(targetID, linkedID) then return true end
        end
    end
    return false
end

function CDMIcons.EventTraceIconMatches(icon, targetID)
    local entry = icon and icon._spellEntry
    if not entry or not targetID then return false end
    if CDMIcons.EventTraceSpellIDMatches(targetID, icon._runtimeSpellID) then return true end
    if EventTraceEntryMatches(targetID, entry) then return true end
    if (entry.type == "trinket" or entry.type == "slot")
       and Sources and Sources.QueryInventoryItemID then
        local itemID = Sources.QueryInventoryItemID("player", entry.id)
        if CDMIcons.EventTraceSpellIDMatches(targetID, itemID) then return true end
    end
    return false
end

function CDMIcons.EventTraceItemUseSpellMatches(targetID, value)
    if DebugIsSecretValue(value) then return false end
    if not targetID or value == nil then return false end
    local spellID = value
    if not spellID then return false end

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if CDMIcons.EventTraceIconMatches(icon, targetID)
               and EventTraceIsItemLikeEntry(entry) then
                local _, _, itemSpellID = EventTraceResolveItemCooldownIdentity(entry)
                if itemSpellID == spellID then
                    return true
                end
            end
        end
    end
    return false
end

local function EventTraceHasItemOrSlotCooldownIconForTarget(targetID)
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMIcons.EventTraceIconMatches(icon, targetID) then
                local entry = icon._spellEntry
                if entry and (entry.type == "item"
                              or entry.type == "trinket"
                              or entry.type == "slot"
                              or entry.kind == "item-cooldown"
                              or entry.itemID) then
                    return true
                end
            end
        end
    end
    return false
end

function CDMIcons.EventTraceShouldPrintFrameEvent(event, arg1, arg2, arg3, arg4, arg5)
    local targetID = CDMIcons._eventTraceSpellID
    if not targetID then return false end

    if event == "UNIT_SPELLCAST_START"
       or event == "UNIT_SPELLCAST_STOP"
       or event == "UNIT_SPELLCAST_SUCCEEDED"
       or event == "UNIT_SPELLCAST_CHANNEL_START"
       or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if DebugIsSecretValue(arg1) then return false end
        return arg1 == "player" and (
            CDMIcons.EventTraceSpellIDMatches(targetID, arg2)
            or CDMIcons.EventTraceSpellIDMatches(targetID, arg3)
            or CDMIcons.EventTraceItemUseSpellMatches(targetID, arg2)
            or CDMIcons.EventTraceItemUseSpellMatches(targetID, arg3)
        )
    end

    if event == "SPELL_UPDATE_COOLDOWN" then
        if issecretvalue and issecretvalue(arg1) then
            return false -- @secret-policy: reject-secret-value (unmatchable trace fire)
        end
        if issecretvalue and issecretvalue(arg2) then
            return false -- @secret-policy: reject-secret-value (unmatchable trace fire)
        end
        if arg1 == nil and arg2 == nil then
            return true
        end
        return CDMIcons.EventTraceSpellIDMatches(targetID, arg1)
            or CDMIcons.EventTraceSpellIDMatches(targetID, arg2)
            or CDMIcons.EventTraceSpellIDMatches(targetID, arg5)
    end

    if event == "BAG_UPDATE_COOLDOWN" then
        return EventTraceHasItemOrSlotCooldownIconForTarget(targetID)
    end

    return true
end

local function EventTraceBuildSpellUpdateCooldownExtra(arg1, arg2, arg3, arg4, arg5)
    if not Sources then return nil end
    local parts = {}
    parts[#parts + 1] = "startRec=" .. CDMIcons.EventTraceValue(arg4)
    parts[#parts + 1] = "cat=" .. CDMIcons.EventTraceValue(arg3)
    if arg5 ~= nil then
        parts[#parts + 1] = "itemID=" .. CDMIcons.EventTraceValue(arg5)
    end

    local function probeSpell(label, sid)
        if type(sid) ~= "number" then return end
        local cdActive, chActive
        if Sources.QuerySpellCooldown then
            local cdInfo = Sources.QuerySpellCooldown(sid)
            if cdInfo then
                cdActive = EventTraceCooldownInfoField(cdInfo, "isActive")
            end
        end
        if Sources.QuerySpellCharges then
            local chInfo = Sources.QuerySpellCharges(sid)
            if chInfo then
                chActive = chInfo.isActive
            end
        end
        parts[#parts + 1] = string.format("%s=%d cdActive=%s chActive=%s",
            label,
            sid,
            CDMIcons.EventTraceValue(cdActive),
            CDMIcons.EventTraceValue(chActive))
    end

    probeSpell("sid", arg1)
    if type(arg2) == "number" and arg2 ~= arg1 then
        probeSpell("base", arg2)
    end
    return table.concat(parts, " ")
end

function CDMIcons.EventTraceIconSummary(targetID)
    local parts = {}
    local matches = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMIcons.EventTraceIconMatches(icon, targetID) then
                matches = matches + 1
                if #parts < 3 then
                    local entry = icon._spellEntry
                    local shown = icon.IsShown and icon:IsShown() and "shown" or "hidden"
                    parts[#parts + 1] = string.format(
                        "%s/%s %s eid=%s espell=%s eov=%s ecid=%s runtime=%s kind=%s type=%s elinks=%s mode=%s aura=%s cd=%s real=%s gcd=%s key=%s auraSource=%s auraInst=%s auraUnit=%s activeAura=%s",
                        tostring(entry.name or "?"),
                        tostring(entry.viewerType or "?"),
                        shown,
                        tostring(entry.id),
                        tostring(entry.spellID),
                        tostring(entry.overrideSpellID),
                        tostring(entry.cooldownID),
                        tostring(icon._runtimeSpellID),
                        tostring(entry.kind),
                        tostring(entry.type),
                        EventTraceIDList(entry.linkedSpellIDs),
                        tostring(icon._resolvedCooldownMode),
                        tostring(icon._auraActive == true),
                        tostring(icon._hasCooldownActive == true),
                        tostring(icon._hasRealCooldownActive == true),
                        tostring(icon._showingGCDSwipe == true),
                        tostring(icon._lastDurObjKey),
                        CDMIcons.EventTraceValue(icon._lastAuraSourceID),
                        CDMIcons.EventTraceValue(icon._auraInstanceID),
                        CDMIcons.EventTraceValue(icon._auraUnit),
                        CDMIcons.EventTraceValue(icon._activeAuraSpellID))
                end
            end
        end
    end
    if matches == 0 then return "icons=0" end
    local more = matches > #parts and string.format(" +%d more", matches - #parts) or ""
    return string.format("icons=%d [%s%s]", matches, table.concat(parts, " | "), more)
end

--            SetCooldownFromDurationObject is annotated
local function ProbeDurObjState(durObj)
    if durObj == nil then return "nil" end
    local durObjType = type(durObj)
    if durObjType ~= "table" and durObjType ~= "userdata" then
        return durObjType
    end
    local okSec, hasSecret = pcall(durObj.HasSecretValues, durObj)
    if not okSec then return "err" end
    if hasSecret then return "secret" end
    local okZero, isZero = pcall(durObj.IsZero, durObj)
    if not okZero then return "err" end
    return isZero and "zero" or "live"
end

local function EventTraceBarMatches(bar, targetID)
    if not (bar and targetID) then return false end
    if CDMIcons.EventTraceSpellIDMatches(targetID, bar._runtimeSpellID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, bar._spellID) then return true end
    return EventTraceEntryMatches(targetID, bar._spellEntry)
end

local function EventTraceGetBarRuntimeState(bar)
    local store = ns.CDMRuntimeStore
    if store and store.GetFrameState then
        return store.GetFrameState(bar)
    end
    return bar and bar._cdmRuntimeState or nil
end

function CDMIcons.EventTraceBarSummary(targetID)
    local bars = ns.CDMBars
    local getActiveBars = bars and bars.GetActiveBars
    if not (targetID and getActiveBars) then return "bars=0" end

    local activeBars = getActiveBars(bars)
    if type(activeBars) ~= "table" then return "bars=0" end

    local parts = {}
    local matches = 0
    for _, bar in ipairs(activeBars) do
        if EventTraceBarMatches(bar, targetID) then
            matches = matches + 1
            if #parts < 3 then
                local entry = bar._spellEntry or {}
                local state = EventTraceGetBarRuntimeState(bar) or {}
                local shown = bar.IsShown and bar:IsShown() and "shown" or "hidden"
                parts[#parts + 1] = string.format(
                    "%s/%s %s spell=%s eid=%s espell=%s eov=%s ecid=%s mode=%s active=%s auraInst=%s auraUnit=%s dataUnit=%s durObj=%s cside=%s hideDur=%s hasExp=%s stateActive=%s stateAuraUnit=%s count=%s/%s/%s",
                    tostring(entry.name or "?"),
                    tostring(entry.viewerType or "?"),
                    shown,
                    CDMIcons.EventTraceValue(bar._spellID),
                    tostring(entry.id),
                    tostring(entry.spellID),
                    tostring(entry.overrideSpellID),
                    tostring(entry.cooldownID),
                    CDMIcons.EventTraceValue(state.mode),
                    CDMIcons.EventTraceValue(bar._active),
                    CDMIcons.EventTraceValue(bar._auraInstanceID),
                    CDMIcons.EventTraceValue(bar._auraUnit),
                    CDMIcons.EventTraceValue(bar._auraDataUnit),
                    ProbeDurObjState(bar._durObj),
                    CDMIcons.EventTraceValue(bar._cSideFill),
                    CDMIcons.EventTraceValue(bar._hideDurationText),
                    CDMIcons.EventTraceValue(bar._hasAuraExpirationTime),
                    CDMIcons.EventTraceValue(state.active),
                    CDMIcons.EventTraceValue(state.auraUnit),
                    CDMIcons.EventTraceValue(state.countValue),
                    CDMIcons.EventTraceValue(state.countShown),
                    CDMIcons.EventTraceValue(state.countSource))
            end
        end
    end

    if matches == 0 then return "bars=0" end
    local more = matches > #parts and string.format(" +%d more", matches - #parts) or ""
    return string.format("bars=%d [%s%s]", matches, table.concat(parts, " | "), more)
end

local function ProbeNumeric(v)
    if issecretvalue and issecretvalue(v) then return "secret" end -- @secret-policy: report-secret-detected
    if v == nil then return "nil" end
    if type(v) == "number" then return "clean" end
    return type(v)
end

function CDMIcons.EventTraceIconWriteState(icon)
    if not icon then return "" end
    local entry = icon._spellEntry or {}

    local baseSid = icon._runtimeSpellID or entry.spellID
    local ovSid = entry.overrideSpellID
    local qChg, qDur = "skip", "skip"
    if baseSid and Sources then
        if Sources.QuerySpellChargeDuration then
            qChg = ProbeDurObjState(Sources.QuerySpellChargeDuration(baseSid))
        end
        if Sources.QuerySpellCooldownDuration then
            qDur = ProbeDurObjState(Sources.QuerySpellCooldownDuration(baseSid, true))
        end
    end
    local qChgO, qDurO = "same", "same"
    if ovSid and baseSid and ovSid ~= baseSid and Sources then
        if Sources.QuerySpellChargeDuration then
            qChgO = ProbeDurObjState(Sources.QuerySpellChargeDuration(ovSid))
        end
        if Sources.QuerySpellCooldownDuration then
            qDurO = ProbeDurObjState(Sources.QuerySpellCooldownDuration(ovSid, true))
        end
    end

    local eMaxCharges = "skip"
    if baseSid and Sources and Sources.QuerySpellCharges then
        local chargeInfo = Sources.QuerySpellCharges(baseSid)
        if chargeInfo == nil then
            eMaxCharges = "no-charge-info"
        else
            local mc = chargeInfo.maxCharges
            if mc == nil then
                eMaxCharges = "nil"
            elseif issecretvalue and issecretvalue(mc) then
                eMaxCharges = "secret"
            elseif type(mc) == "number" then
                eMaxCharges = tostring(mc)
            else
                eMaxCharges = type(mc)
            end
        end
    end

    local probeNumeric = ProbeNumeric
    local cdStart, cdDur = "nil", "nil"
    if baseSid and Sources and Sources.QuerySpellCooldown then
        local cdInfo = Sources.QuerySpellCooldown(baseSid)
        if cdInfo then
            cdStart = probeNumeric(cdInfo.startTime)
            cdDur   = probeNumeric(cdInfo.duration)
        end
    end

    return string.format(
        "eid=%s espell=%s eov=%s ecid=%s runtime=%s kind=%s type=%s elinks=%s mode=%s aura=%s cd=%s real=%s gcd=%s key=%s auraSource=%s auraInst=%s auraUnit=%s activeAura=%s qChg=%s qDur=%s qChgO=%s qDurO=%s cdStart=%s cdDur=%s iStackText=%s iStackSrc=%s eMaxCharges=%s",
        tostring(entry.id),
        tostring(entry.spellID),
        tostring(entry.overrideSpellID),
        tostring(entry.cooldownID),
        tostring(icon._runtimeSpellID),
        tostring(entry.kind),
        tostring(entry.type),
        EventTraceIDList(entry.linkedSpellIDs),
        tostring(icon._resolvedCooldownMode),
        tostring(icon._auraActive == true),
        tostring(icon._hasCooldownActive == true),
        tostring(icon._hasRealCooldownActive == true),
        tostring(icon._showingGCDSwipe == true),
        tostring(icon._lastDurObjKey),
        tostring(icon._lastAuraSourceID),
        tostring(icon._auraInstanceID),
        tostring(icon._auraUnit),
        tostring(icon._activeAuraSpellID),
        qChg, qDur, qChgO, qDurO,
        cdStart, cdDur,
        CDMIcons.EventTraceValue(icon.stackText),
        tostring(icon._stackTextSource),
        eMaxCharges)
end

function CDMIcons.EventTraceAPISummary(spellID)
    local cdActive, cdOnGCD = nil, nil
    local chargeActive, currentCharges, maxCharges = nil, nil, nil
    local usable, resourceBlocked = nil, nil
    local itemStart, itemDuration, itemEnabled = nil, nil, nil
    local itemSpellID = EventTraceGetItemUseSpellID(spellID)
    local itemSpellCdActive, itemSpellCdOnGCD = nil, nil

    if Sources and Sources.QuerySpellCooldown then
        local cdInfo = Sources.QuerySpellCooldown(spellID)
        if cdInfo then
            cdActive = EventTraceCooldownInfoField(cdInfo, "isActive")
            cdOnGCD = cdInfo.isOnGCD
        end
        if itemSpellID then
            local itemSpellCdInfo = Sources.QuerySpellCooldown(itemSpellID)
            if itemSpellCdInfo then
                itemSpellCdActive = EventTraceCooldownInfoField(itemSpellCdInfo, "isActive")
                itemSpellCdOnGCD = itemSpellCdInfo.isOnGCD
            end
        end
    end
    if Sources and Sources.QuerySpellCharges then
        local chargeInfo = Sources.QuerySpellCharges(spellID)
        if chargeInfo then
            chargeActive = chargeInfo.isActive
            currentCharges = chargeInfo.currentCharges
            maxCharges = chargeInfo.maxCharges
        end
    end
    if Sources and Sources.QuerySpellUsable then
        local isUsable, isResourceBlocked = Sources.QuerySpellUsable(spellID)
        usable = isUsable
        resourceBlocked = isResourceBlocked
    end
    if Sources and Sources.QueryItemCooldown then
        local startTime, duration, enabled = Sources.QueryItemCooldown(spellID)
        itemStart = startTime
        itemDuration = duration
        itemEnabled = enabled
    end

    return string.format(
        "api cdActive=%s isOnGCD=%s charges=%s/%s chargeActive=%s usable=%s resourceBlocked=%s itemCd=%s/%s/%s itemSpell=%s itemSpellCd=%s/%s",
        CDMIcons.EventTraceValue(cdActive),
        CDMIcons.EventTraceValue(cdOnGCD),
        CDMIcons.EventTraceValue(currentCharges),
        CDMIcons.EventTraceValue(maxCharges),
        CDMIcons.EventTraceValue(chargeActive),
        CDMIcons.EventTraceValue(usable),
        CDMIcons.EventTraceValue(resourceBlocked),
        CDMIcons.EventTraceValue(itemStart),
        CDMIcons.EventTraceValue(itemDuration),
        CDMIcons.EventTraceValue(itemEnabled),
        CDMIcons.EventTraceValue(itemSpellID),
        CDMIcons.EventTraceValue(itemSpellCdActive),
        CDMIcons.EventTraceValue(itemSpellCdOnGCD))
end

function CDMIcons.EventTraceAuraInfo(unit, updateInfo)
    if type(unit) == "table" and updateInfo == nil then
        updateInfo = unit
        unit = nil
    end
    if type(updateInfo) ~= "table" then return "auraInfo=nil" end
    local added = type(updateInfo.addedAuras) == "table" and #updateInfo.addedAuras or 0
    local updated = type(updateInfo.updatedAuraInstanceIDs) == "table" and #updateInfo.updatedAuraInstanceIDs or 0
    local removed = type(updateInfo.removedAuraInstanceIDs) == "table" and #updateInfo.removedAuraInstanceIDs or 0
    return string.format(
        "aura full=%s added=%d addedAuras=%s updated=%d updatedIDs=%s removed=%d removedIDs=%s",
        CDMIcons.EventTraceValue(updateInfo.isFullUpdate),
        added,
        EventTraceAddedAuras(unit, updateInfo.addedAuras),
        updated,
        EventTraceIDList(updateInfo.updatedAuraInstanceIDs),
        removed,
        EventTraceIDList(updateInfo.removedAuraInstanceIDs))
end

local DEFAULT_EVENT_TRACE_INTERVAL = 0.25
local MAX_EVENT_TRACE_INTERVAL = 10

local function EventTraceNormalizeInterval(interval)
    local value = tonumber(interval)
    if value == nil then value = DEFAULT_EVENT_TRACE_INTERVAL end
    if value < 0 then value = 0 end
    if value > MAX_EVENT_TRACE_INTERVAL then value = MAX_EVENT_TRACE_INTERVAL end
    return value
end

local function EventTraceThrottle(key, now)
    local interval = tonumber(CDMIcons._eventTraceMinInterval) or 0
    if interval <= 0 then return true, nil end

    key = key or "events"
    local lastByKey = CDMIcons._eventTraceLastPrintAt
    if type(lastByKey) ~= "table" then
        lastByKey = {}
        CDMIcons._eventTraceLastPrintAt = lastByKey
    end
    local suppressedByKey = CDMIcons._eventTraceSuppressed
    if type(suppressedByKey) ~= "table" then
        suppressedByKey = {}
        CDMIcons._eventTraceSuppressed = suppressedByKey
    end

    local last = lastByKey[key]
    if last and (now - last) < interval then
        suppressedByKey[key] = (suppressedByKey[key] or 0) + 1
        return false, nil
    end

    lastByKey[key] = now
    local suppressed = suppressedByKey[key] or 0
    suppressedByKey[key] = 0
    if suppressed > 0 then
        return true, string.format("throttled=%d interval=%.2fs", suppressed, interval)
    end
    return true, nil
end

local function EventTraceAppendExtra(extra, note)
    if not note or note == "" then return extra end
    if extra and extra ~= "" then
        return extra .. " " .. note
    end
    return note
end

function CDMIcons.EventTracePrint(source, event, arg1, arg2, arg3, arg4, arg5, extra)
    local targetID = CDMIcons._eventTraceSpellID
    if not targetID then return end
    local frameSource = source == "frame" or source == "frame-pre"
        or source == "frame-post" or source == "runtime-pre"
    if frameSource and not CDMIcons.EventTraceShouldPrintFrameEvent(event, arg1, arg2, arg3, arg4, arg5) then
        return
    end

    local throttleBucket = "events"
    if event == "SPELL_UPDATE_COOLDOWN" then
        throttleBucket = "events:SUC"
    elseif source == "aura-pre" then
        throttleBucket = "events:aura-pre"
    elseif source == "aura-post" then
        throttleBucket = "events:aura-post"
    end
    local now = GetTime and GetTime() or 0
    local shouldPrint, throttleNote = EventTraceThrottle(throttleBucket, now)
    if not shouldPrint then return end

    if event == "SPELL_UPDATE_COOLDOWN" then
        extra = EventTraceAppendExtra(extra,
            EventTraceBuildSpellUpdateCooldownExtra(arg1, arg2, arg3, arg4, arg5))
    end
    extra = EventTraceAppendExtra(extra, throttleNote)

    local start = CDMIcons._eventTraceStartedAt or now
    print(string.format(
        "|cff34d399[cdmevents]|r +%.3f sid=%d %s:%s args=(%s,%s,%s,%s,%s) %s %s %s %s",
        now - start,
        targetID,
        tostring(source or "?"),
        tostring(event or "?"),
        CDMIcons.EventTraceValue(arg1),
        CDMIcons.EventTraceValue(arg2),
        CDMIcons.EventTraceValue(arg3),
        CDMIcons.EventTraceValue(arg4),
        CDMIcons.EventTraceValue(arg5),
        CDMIcons.EventTraceAPISummary(targetID),
        CDMIcons.EventTraceIconSummary(targetID),
        CDMIcons.EventTraceBarSummary(targetID),
        extra or ""))
end

ns.CDMRuntimeEventTraceHook = function(source, event, arg1, arg2, arg3, arg4, arg5)
    return CDMIcons.EventTracePrint(source, event, arg1, arg2, arg3, arg4, arg5)
end

local function FormatColorTuple(r, g, b, a)
    return string.format("(%.2f,%.2f,%.2f,%.2f)", r or 1, g or 1, b or 1, a or 1)
end

function CDMIcons.EventTracePrintWrite(label, icon, value, extra)
    local targetID = CDMIcons._eventTraceSpellID
    if not targetID then return end
    if icon and not CDMIcons.EventTraceIconMatches(icon, targetID) then return end

    local now = GetTime and GetTime() or 0
    local throttleKey = "writes:" .. tostring(label or "?")
    local shouldPrint, throttleNote = EventTraceThrottle(throttleKey, now)
    if not shouldPrint then return end

    local start = CDMIcons._eventTraceStartedAt or now
    local prevField = "_cdmevents_prev_" .. label
    local prev = icon and icon[prevField]
    if icon then icon[prevField] = value end
    local changedNote = (prev == nil) and "(new)"
        or (prev == value and "(unchanged)")
        or ("(was " .. tostring(prev) .. ")")
    local writeState = icon and CDMIcons.EventTraceIconWriteState(icon)
    if writeState and writeState ~= "" then
        extra = extra and (extra .. " " .. writeState) or writeState
    end
    extra = EventTraceAppendExtra(extra, throttleNote)

    print(string.format(
        "|cffff8800[cdmwrites]|r +%.3f sid=%d %s=%s %s%s",
        now - start,
        targetID,
        label,
        tostring(value),
        changedNote,
        extra and (" " .. extra) or ""))
end

function CDMIcons.EventTracePrintSource(channel, sid, msg, rawAlways)
    if not CDMIcons._eventTraceSpellID then return end
    local now = GetTime and GetTime() or 0
    local throttleNote
    if not rawAlways then
        local shouldPrint
        shouldPrint, throttleNote = EventTraceThrottle("src:" .. channel, now)
        if not shouldPrint then return end
    end
    local start = CDMIcons._eventTraceStartedAt or now
    print(string.format(
        "|cff60a5fa[cdmsrc]|r +%.3f sid=%s %s=%s%s",
        now - start,
        tostring(sid or "?"),
        channel,
        msg,
        throttleNote and (" " .. throttleNote) or ""))
end

local function InstallIconWriteProbe(icon)
    if not icon or icon._cdmevents_probed then return end
    icon._cdmevents_probed = true

    if icon.Icon then
        if icon.Icon.SetVertexColor then
            hooksecurefunc(icon.Icon, "SetVertexColor", function(_, r, g, b, a)
                local extra = string.format(
                    "rangeTinted=%s usabilityTinted=%s lastVisualState=%s cdDesat=%s greyedOut=%s mode=%s",
                    tostring(icon._rangeTinted),
                    tostring(icon._usabilityTinted),
                    tostring(icon._lastVisualState),
                    tostring(icon._cdDesaturated),
                    tostring(icon._greyedOut),
                    tostring(icon._resolvedCooldownMode))
                CDMIcons.EventTracePrintWrite("Icon:SetVertexColor", icon, FormatColorTuple(r, g, b, a), extra)
            end)
        end
        if icon.Icon.SetDesaturated then
            hooksecurefunc(icon.Icon, "SetDesaturated", function(_, value)
                local extra = string.format(
                    "cdDesat=%s greyedOut=%s mode=%s hasCD=%s hasRealCD=%s",
                    tostring(icon._cdDesaturated),
                    tostring(icon._greyedOut),
                    tostring(icon._resolvedCooldownMode),
                    tostring(icon._hasCooldownActive),
                    tostring(icon._hasRealCooldownActive))
                CDMIcons.EventTracePrintWrite("Icon:SetDesaturated", icon, tostring(value), extra)
            end)
        end
        if icon.Icon.SetAlpha then
            hooksecurefunc(icon.Icon, "SetAlpha", function(_, value)
                CDMIcons.EventTracePrintWrite("Icon:SetAlpha", icon, tostring(value), nil)
            end)
        end
    end
    if icon.Cooldown then
        if icon.Cooldown.SetSwipeColor then
            hooksecurefunc(icon.Cooldown, "SetSwipeColor", function(_, r, g, b, a)
                CDMIcons.EventTracePrintWrite("Cooldown:SetSwipeColor", icon, FormatColorTuple(r, g, b, a), nil)
            end)
        end
        if icon.Cooldown.SetDrawSwipe then
            hooksecurefunc(icon.Cooldown, "SetDrawSwipe", function(_, value)
                CDMIcons.EventTracePrintWrite("Cooldown:SetDrawSwipe", icon, tostring(value), nil)
            end)
        end
        if icon.Cooldown.SetDrawEdge then
            hooksecurefunc(icon.Cooldown, "SetDrawEdge", function(_, value)
                CDMIcons.EventTracePrintWrite("Cooldown:SetDrawEdge", icon, tostring(value), nil)
            end)
        end
        if icon.Cooldown.SetCooldown then
            hooksecurefunc(icon.Cooldown, "SetCooldown", function(_, startTime, duration)
                local extra = string.format(
                    "startProbe=%s durProbe=%s mode=%s",
                    ProbeNumeric(startTime),
                    ProbeNumeric(duration),
                    tostring(icon._resolvedCooldownMode))
                CDMIcons.EventTracePrintWrite("Cooldown:SetCooldown", icon, "(numeric)", extra)
            end)
        end
        if icon.Cooldown.SetCooldownFromDurationObject then
            hooksecurefunc(icon.Cooldown, "SetCooldownFromDurationObject", function(_, durObj)
                local extra = string.format(
                    "durObjState=%s mode=%s",
                    ProbeDurObjState(durObj),
                    tostring(icon._resolvedCooldownMode))
                CDMIcons.EventTracePrintWrite("Cooldown:SCFDO", icon, "(durObj)", extra)
            end)
        end
    end
    if icon.StackText then
        if icon.StackText.SetText then
            hooksecurefunc(icon.StackText, "SetText", function(_, value)
                local extra = string.format(
                    "mode=%s iStackSrc=%s",
                    tostring(icon._resolvedCooldownMode),
                    tostring(icon._stackTextSource))
                CDMIcons.EventTracePrintWrite("StackText:SetText", icon,
                    CDMIcons.EventTraceValue(value), extra)
            end)
        end
        if icon.StackText.SetFormattedText then
            hooksecurefunc(icon.StackText, "SetFormattedText", function(_, fmt, value)
                CDMIcons.EventTracePrintWrite("StackText:SetFormattedText", icon,
                    CDMIcons.EventTraceValue(value), "fmt=" .. tostring(fmt))
            end)
        end
        if icon.StackText.Show then
            hooksecurefunc(icon.StackText, "Show", function()
                CDMIcons.EventTracePrintWrite("StackText:Show", icon, "show",
                    "mode=" .. tostring(icon._resolvedCooldownMode))
            end)
        end
        if icon.StackText.Hide then
            hooksecurefunc(icon.StackText, "Hide", function()
                CDMIcons.EventTracePrintWrite("StackText:Hide", icon, "hide",
                    "mode=" .. tostring(icon._resolvedCooldownMode))
            end)
        end
    end
end

local _raProbed = false
local _raPrev = { r = nil, g = nil, b = nil, a = nil }

local function InstallRotationAssistProbe()
    if _raProbed then return end
    local raAccessor = _G.QUI and _G.QUI.RotationAssistIcon and _G.QUI.RotationAssistIcon.GetFrame
    local raFrame = raAccessor and raAccessor()
    if not raFrame or not raFrame.icon or not raFrame.icon.SetVertexColor then return end
    _raProbed = true

    hooksecurefunc(raFrame.icon, "SetVertexColor", function(_, r, g, b, a)
        if not CDMIcons._eventTraceSpellID then return end
        local now = GetTime and GetTime() or 0
        local shouldPrint, throttleNote = EventTraceThrottle("rotassist", now)
        if not shouldPrint then return end
        local start = CDMIcons._eventTraceStartedAt or now
        local changed = (r ~= _raPrev.r) or (g ~= _raPrev.g)
            or (b ~= _raPrev.b) or (a ~= _raPrev.a)
        local prevNote
        if _raPrev.r == nil then
            prevNote = "(new)"
        elseif not changed then
            prevNote = "(unchanged)"
        else
            prevNote = "(was " .. FormatColorTuple(_raPrev.r, _raPrev.g, _raPrev.b, _raPrev.a) .. ")"
        end
        _raPrev.r, _raPrev.g, _raPrev.b, _raPrev.a = r, g, b, a
        print(string.format(
            "|cffff8800[cdmwrites]|r +%.3f rotassist:SetVertexColor=%s %s%s",
            now - start,
            FormatColorTuple(r, g, b, a),
            prevNote,
            throttleNote and (" " .. throttleNote) or ""))
    end)
end

function CDMIcons.EventTraceInstallWriteProbes(targetID)
    if not targetID then return 0, false end
    local installed = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMIcons.EventTraceIconMatches(icon, targetID) then
                if not icon._cdmevents_probed then
                    InstallIconWriteProbe(icon)
                    installed = installed + 1
                end
            end
        end
    end
    local raPrior = _raProbed
    InstallRotationAssistProbe()
    local raJustInstalled = _raProbed and not raPrior
    return installed, raJustInstalled
end

function CDMIcons.EventTraceMaybeProbeIcon(icon)
    if not icon or icon._cdmevents_probed then return end
    local targetID = CDMIcons._eventTraceSpellID
    if not targetID then return end
    if CDMIcons.EventTraceIconMatches(icon, targetID) then
        InstallIconWriteProbe(icon)
    end
end

local _sourceProbesInstalled = false
function CDMIcons.EventTraceInstallSourceProbes()
    if _sourceProbesInstalled then return false end

    if CDMIcons.UpdateAllCooldowns then
        hooksecurefunc(CDMIcons, "UpdateAllCooldowns", function()
            CDMIcons.EventTracePrintSource("updateAll", CDMIcons._eventTraceSpellID or "?",
                "UpdateAllCooldowns")
        end)
    end

    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG then
        local function GlowCallerChain()
            if not debugstack then return "?" end
            local s = debugstack(2, 6, 0) or ""
            local frames = {}
            for path, line in s:gmatch("([%w_]+%.lua):(%d+)") do
                frames[#frames + 1] = path .. ":" .. line
                if #frames >= 5 then break end
            end
            return #frames > 0 and table.concat(frames, "<-") or "?"
        end
        local function GlowIconTag(button)
            local entry = button and button._spellEntry
            if not entry then return "noentry" end
            return string.format("cat=%s eid=%s eov=%s",
                tostring(entry.viewerType),
                tostring(entry.spellID or entry.id),
                tostring(entry.overrideSpellID))
        end
        local function HookGlow(name)
            if type(LCG[name]) ~= "function" then return end
            hooksecurefunc(LCG, name, function(button)
                local targetID = CDMIcons._eventTraceSpellID
                if not targetID or not button then return end
                if not CDMIcons.EventTraceIconMatches(button, targetID) then return end
                local tracked = ns._OwnedGlows and ns._OwnedGlows.GetGlowState
                    and ns._OwnedGlows.GetGlowState(button) ~= nil
                CDMIcons.EventTracePrintSource("glow", targetID,
                    name .. " tracked=" .. tostring(tracked)
                        .. " " .. GlowIconTag(button)
                        .. " via " .. GlowCallerChain(), true)
            end)
        end
        HookGlow("ButtonGlow_Start"); HookGlow("ButtonGlow_Stop")
        HookGlow("PixelGlow_Start");  HookGlow("PixelGlow_Stop")
        HookGlow("ProcGlow_Start");   HookGlow("ProcGlow_Stop")
        HookGlow("AutoCastGlow_Start"); HookGlow("AutoCastGlow_Stop")
    end

    local evFrame = CreateFrame and CreateFrame("Frame")
    if evFrame and evFrame.RegisterEvent and evFrame.SetScript then
        evFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        evFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        evFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
        evFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
        evFrame:SetScript("OnEvent", function(_, event, spellID)
            if not CDMIcons._eventTraceSpellID then return end
            CDMIcons.EventTracePrintSource("glow-event", CDMIcons._eventTraceSpellID,
                event .. " spell=" .. tostring(spellID), true)
        end)
    end

    _sourceProbesInstalled = true
    return true
end

function CDMIcons.ShouldDebugSpell(spellID, spellName)
    local dbg = _G.QUI_CDM_ICON_DEBUG
    if not dbg then return false end
    if dbg == true then return true end
    local filter = tostring(dbg):lower()
    if spellID and tostring(spellID) == filter then return true end
    local name = spellName and tostring(spellName):lower() or ""
    return name ~= "" and name:find(filter, 1, true) ~= nil
end

function CDMIcons.ShouldDebugIcon(icon)
    local dbg = _G.QUI_CDM_ICON_DEBUG
    if not dbg then return false end
    local entry = icon and icon._spellEntry
    if not entry then return false end
    if dbg == true then return true end
    local filter = tostring(dbg):lower()
    local name = entry and entry.name and tostring(entry.name):lower() or ""
    local sid = icon and icon._runtimeSpellID and tostring(icon._runtimeSpellID) or ""
    local eid = entry and entry.id and tostring(entry.id) or ""
    return name:find(filter, 1, true) ~= nil
        or sid == filter
        or eid == filter
end

function CDMIcons.DebugSpellEvent(spellID, spellName, label, ...)
    if not CDMIcons.ShouldDebugSpell(spellID, spellName) then return end
    print("|cff34D399[CDM-IconTrace]|r", tostring(label), tostring(spellName or "?"), "spellID=", tostring(spellID), ...)
end

function CDMIcons.DebugIconEvent(icon, label, ...)
    if not CDMIcons.ShouldDebugIcon(icon) then return end
    local now = GetTime()
    icon._debugEventTimes = icon._debugEventTimes or {}
    local last = icon._debugEventTimes[label]
    if last and (now - last) < 0.25 then return end
    icon._debugEventTimes[label] = now
    local entry = icon._spellEntry
    print("|cff34D399[CDM-IconTrace]|r", tostring(label),
        entry and (entry.name or "?") or "?",
        "viewer=", entry and tostring(entry.viewerType) or "nil",
        "entryID=", entry and tostring(entry.id) or "nil",
        ...)
end

function CDMIcons.DebugEntryBuild(entry, spellEntry, viewerType)
    if not CDMIcons.ShouldDebugSpell(spellEntry and (spellEntry.spellID or spellEntry.id), spellEntry and spellEntry.name) then return end
    print("|cff34D399[CDM-IconTrace]|r", "build",
        spellEntry and (spellEntry.name or "?") or "?",
        "viewer=", tostring(viewerType),
        "entryType=", entry and tostring(entry.type) or "nil",
        "entryID=", entry and tostring(entry.id) or "nil",
        "spellID=", spellEntry and tostring(spellEntry.spellID) or "nil",
        "kind=", spellEntry and tostring(spellEntry.kind) or "nil",
        "isAura=", spellEntry and tostring(spellEntry.isAura) or "nil")
end

function CDMIcons.DebugLayoutFilter(icon, filterHides, settings, effectiveOnCD)
    CDMIcons.DebugIconEvent(icon, "layout-filter",
        "hide=", tostring(filterHides and true or false),
        "effectiveOnCD=", tostring(effectiveOnCD),
        "dynamic=", tostring(settings and settings.dynamicLayout),
        "containerType=", tostring(settings and settings.containerType),
        "showOnlyOnCooldown=", tostring(settings and settings.showOnlyOnCooldown))
end

local function DumpDebugIcon(icon)
    if not CDMIcons.ShouldDebugIcon(icon) then return end
    local entry = icon and icon._spellEntry
    if not entry then return end
    local P = "|cff34D399[CDM-IconDbg]|r"
    print(P, entry.name or "?", "viewerType=", tostring(entry.viewerType),
        "spellID=", tostring(entry.spellID), "entry.id=", tostring(entry.id))
    print(P, "  shown=", tostring(icon:IsShown()),
        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
        "auraActive=", tostring(icon._auraActive),
        "customActive=", tostring(icon._customBarActive),
        "hasCooldownActive=", tostring(icon._hasCooldownActive),
        "hasRealCooldown=", tostring(icon._hasRealCooldownActive),
        "lastStart=", tostring(icon._lastStart),
        "lastDuration=", tostring(icon._lastDuration),
        "isTotemInstance=", tostring(icon._isTotemInstance),
        "entry._totemSlot=", tostring(entry._totemSlot),
        "icon._totemSlot=", tostring(icon._totemSlot),
        "instanceKey=", tostring(entry._instanceKey))
    local containerDB = CDMIcons.GetTrackerSettings(entry.viewerType)
    if CDMIcons.IsCustomBarContainer(containerDB) then
        local visibility = CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, GetTime())
        print(P, "  customVisibility mode=", tostring(visibility.visibilityMode),
            "layout=", tostring(visibility.layoutVisible),
            "render=", tostring(visibility.renderVisible),
            "usable=", tostring(visibility.isUsable),
            "onCD=", tostring(visibility.isOnCooldown),
            "recharge=", tostring(visibility.rechargeActive),
            "active=", tostring(visibility.isActive),
            "dynamic=", tostring(containerDB.dynamicLayout),
            "displayMode=", tostring(containerDB.iconDisplayMode))
    end
    if icon.Icon and icon.Icon.GetTexture then
        print(P, "  iconTexture=", tostring(icon.Icon.GetTexture(icon.Icon)))
    end
    if icon.StackText and icon.StackText.GetText then
        print(P, "  stackText=", tostring(icon.StackText.GetText(icon.StackText)))
    end
    if icon.DurationText and icon.DurationText.GetText then
        print(P, "  durationText=", tostring(icon.DurationText.GetText(icon.DurationText)))
    end
end

local DEBUG_FLAGS = {
    icon   = { global = "QUI_CDM_ICON_DEBUG",   label = "[CDM-Icon]",   takesFilter = true  },
    bar    = { global = "QUI_CDM_BAR_DEBUG",    label = "[CDM-Bar]",    takesFilter = true  },
    blizz  = { global = "QUI_CDM_BLIZZ_DEBUG",  label = "[CDM-Blizz]",  takesFilter = true  },
    aura   = { global = "QUI_CDM_AURA_DEBUG",   label = "[CDM-Aura]",   takesFilter = true  },
    charge = { global = "QUI_CDM_CHARGE_DEBUG", label = "[CDM-Charge]", takesFilter = true  },
    totem  = { global = "QUI_CDM_TOTEM_DEBUG",  label = "[CDM-Totem]",  takesFilter = false },
    taint  = { global = "QUI_CDM_TAINT_DEBUG",  label = "[CDM-Taint]",  takesFilter = true,  requiresReload = true },
}

local DEBUG_FLAG_ORDER = { "icon", "bar", "blizz", "aura", "charge", "totem", "taint" }

local function FormatFlagState(value)
    if value == nil or value == false then return "off" end
    if value == true then return "ON (all)" end
    return "ON [" .. tostring(value) .. "]"
end

local function PrintFlagState(key)
    local def = DEBUG_FLAGS[key]
    print("|cff34D399" .. def.label .. "|r " .. FormatFlagState(_G[def.global]))
end

local function ListDebugFlags()
    print("|cff34D399[CDM-Debug]|r subsystems (use /cdmdebug flags <name> [filter|on|off|all]):")
    for _, key in ipairs(DEBUG_FLAG_ORDER) do
        local def = DEBUG_FLAGS[key]
        local note = def.requiresReload and "  (requires /rl)" or ""
        print(string.format("  %-7s %s%s", key, FormatFlagState(_G[def.global]), note))
    end
    print("  /cdmdebug flags off          -> clear all flags")
    print("  /cdmdebug flags icon dump    -> also walk every icon and dump state")
end

local function RunCDMDebugFlags(msg)
    local text = TrimText(msg)
    if text == "" then
        ListDebugFlags()
        return
    end

    local cmd, rest = text:match("^(%S+)%s*(.-)$")
    local lower = cmd and cmd:lower() or ""

    if lower == "off" or lower == "clear" then
        for _, key in ipairs(DEBUG_FLAG_ORDER) do
            _G[DEBUG_FLAGS[key].global] = nil
        end
        print("|cff34D399[CDM-Debug]|r all flags cleared")
        return
    end

    local def = DEBUG_FLAGS[lower]
    if not def then
        print("|cffffaa00[CDM-Debug]|r unknown subsystem '" .. cmd .. "'. /cdmdebug for list.")
        return
    end

    local arg = TrimText(rest)
    local argLower = arg:lower()

    if lower == "icon" and (argLower == "dump" or argLower:find("^dump%s+")) then
        local dumpFilter = arg:match("^[Dd]ump%s+(.*)$")
        if dumpFilter and dumpFilter ~= "" then
            _G.QUI_CDM_ICON_DEBUG = dumpFilter
        elseif not _G.QUI_CDM_ICON_DEBUG then
            _G.QUI_CDM_ICON_DEBUG = true
        end
        print("|cff34D399[CDM-Icon]|r dump - filter:", tostring(_G.QUI_CDM_ICON_DEBUG))
        if CDMIcons and CDMIcons.ForEachIcon then
            CDMIcons:ForEachIcon(function(icon)
                DumpDebugIcon(icon)
            end)
        end
        return
    end

    if arg == "" then
        _G[def.global] = (not _G[def.global]) and true or nil
    elseif argLower == "off" or argLower == "0" or argLower == "false" then
        _G[def.global] = nil
    elseif argLower == "on" or argLower == "all" or argLower == "true" then
        _G[def.global] = true
    elseif def.takesFilter then
        _G[def.global] = arg
    else
        print("|cffffaa00[CDM-Debug]|r '" .. lower .. "' has no filter; use on/off.")
        return
    end

    PrintFlagState(lower)

    if def.requiresReload and _G[def.global] then
        print("|cffffaa00[CDM-Debug]|r " .. lower .. " hooks need /rl to wire up.")
    end
end

function CDMIcons._OnBarUpdate(bar)
    local dbg = _G.QUI_CDM_BAR_DEBUG
    if not dbg then return end
    if not bar or not bar._spellEntry then return end
    local entry = bar._spellEntry
    local entryName = entry.name or "?"

    if type(dbg) == "string" then
        if not entryName:lower():find(dbg, 1, true)
           and tostring(bar._spellID) ~= dbg then
            return
        end
    end

    local P = "|cff34D399[CDM-BarDbg]|r"
    print(P, entryName, "spellID=", bar._spellID, "entry.id=", entry.id,
          "entry.spellID=", entry.spellID, "entry.overrideSpellID=", entry.overrideSpellID)
    print(P, "  active=", bar._active, "cSideFill=", bar._cSideFill,
          "durObj=", bar._durObj and "yes" or "nil",
          "hideDuration=", tostring(bar._hideDurationText),
          "hasExpiration=", tostring(bar._hasAuraExpirationTime))
    print(P, "  isTotemInstance=", tostring(bar._isTotemInstance),
          "totemSlot=", tostring(bar._totemSlot),
          "instanceKey=", tostring(bar._instanceKey))
    if bar.NameText then
        print(P, "  owned NameText=", tostring(bar.NameText.GetText(bar.NameText)))
    end
    if bar.DurationText then
        print(P, "  owned DurationText=", tostring(bar.DurationText.GetText(bar.DurationText)))
    end
    if bar.IconTexture and bar.IconTexture.GetTexture then
        print(P, "  owned IconTexture=", tostring(bar.IconTexture.GetTexture(bar.IconTexture)))
    end
end

local function RunCDMDebugEvents(msg, interval)
    local text = TrimText(msg)
    if text == "" or text == "off" or text == "clear" then
        CDMIcons._eventTraceSpellID = nil
        CDMIcons._eventTraceStartedAt = nil
        CDMIcons._eventTraceMinInterval = nil
        CDMIcons._eventTraceLastPrintAt = nil
        CDMIcons._eventTraceSuppressed = nil
        print("|cffffaa00[cdmevents]|r cleared")
        return
    end

    local spellID = tonumber(text:match("^(%d+)"))
    if not spellID then
        print("|cffffaa00[cdmevents]|r Usage: /cdmdebug spell <spellID> events [seconds]")
        return
    end
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmevents]|r Owned engine not enabled.")
        return
    end

    local minInterval = EventTraceNormalizeInterval(interval)
    CDMIcons._eventTraceSpellID = spellID
    CDMIcons._eventTraceStartedAt = GetTime and GetTime() or 0
    CDMIcons._eventTraceMinInterval = minInterval
    CDMIcons._eventTraceLastPrintAt = {}
    CDMIcons._eventTraceSuppressed = {}
    local throttleText = minInterval > 0
        and string.format("throttled to one line per trace channel every %.2fs", minInterval)
        or "unthrottled"
    print(string.format(
        "|cff34d399[cdmevents]|r tracing events for spellID %d (%s). Use /cdmdebug spell off to stop.",
        spellID,
        throttleText))
    print("|cff34d399[cdmevents]|r " .. CDMIcons.EventTraceAPISummary(spellID))
    print("|cff34d399[cdmevents]|r " .. CDMIcons.EventTraceIconSummary(spellID))
    print("|cff34d399[cdmevents]|r " .. CDMIcons.EventTraceBarSummary(spellID))

    local installed, raInstalled = CDMIcons.EventTraceInstallWriteProbes(spellID)
    print(string.format(
        "|cff34d399[cdmwrites]|r write-probe installed on %d icon(s)%s. Hooks are permanent (gated by trace state); rerun if icons are recycled.",
        installed,
        raInstalled and " + rotation assistant" or ""))

    local newSourceProbes = CDMIcons.EventTraceInstallSourceProbes()
    print("|cff34d399[cdmsrc]|r cause probes " .. (newSourceProbes and "installed" or "active")
        .. " (mrefresh / glow / overlay / updateAll). For raw flash timing use: /cdmdebug spell <name> events 0")
end

local function RunCDMDebugTrace(msg)
    local name = TrimText(msg)
    if name == "" then
        CDMIcons._desatTraceName = nil
        for _, pool in pairs(iconPools) do
            for _, icon in ipairs(pool) do
                if icon then icon._desatTracePrev = nil end
            end
        end
        print("|cffffaa00[cdmtrace]|r cleared")
        return
    end
    CDMIcons._desatTraceName = name
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon then icon._desatTracePrev = nil end
        end
    end
    print("|cff34d399[cdmtrace]|r tracing transitions for '" .. name .. "'")
end

local function CDMGCDIsSecret(value)
    if Helpers and Helpers.IsSecretValue then
        return Helpers.IsSecretValue(value)
    end
    return issecretvalue and issecretvalue(value) or false
end

local function CDMGCDValue(value)
    if CDMGCDIsSecret(value) then
        return "<SECRET:" .. type(value) .. ">"
    end
    if value == nil then return "nil" end
    if type(value) == "table" or type(value) == "userdata" then
        return "yes"
    end
    return tostring(value)
end

local function CDMGCDIDMatches(value, targetID)
    if CDMGCDIsSecret(value) then return false end
    return value == targetID
end

local function CDMGCDFirstID(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if not CDMGCDIsSecret(value) and value ~= nil then
            return value
        end
    end
    return nil
end

local function CDMGCDCall(owner, methodName)
    if not (owner and owner[methodName]) then
        return "n/a"
    end
    local ok, value = pcall(owner[methodName], owner)
    if not ok then
        return "err"
    end
    return CDMGCDValue(value)
end

local function CDMGCDResolveCooldownState(icon)
    local resolveCooldownState = Resolvers and Resolvers.ResolveCooldownState or CDMIcons.ResolveCooldownState
    if not resolveCooldownState then
        return nil
    end
    local entry = icon and icon._spellEntry
    if not entry then
        return nil
    end
    return resolveCooldownState({
        entry = entry,
        runtimeSpellID = icon._runtimeSpellID,
        containerKey = entry.viewerType,
        totemSlot = icon._totemSlot,
        useBuffSwipe = CDMIcons.ShouldUseBuffSwipeForIcon
            and CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry) or nil,
        skipAuraPhase = CDMIcons.ShouldSkipAuraPhaseForCooldownIcon
            and CDMIcons.ShouldSkipAuraPhaseForCooldownIcon(icon, entry) or nil,
    })
end

local function CDMGCDIconMatches(icon, needle, targetID)
    local entry = icon and icon._spellEntry
    if not entry then return false end
    if targetID then
        if CDMGCDIDMatches(icon._runtimeSpellID, targetID)
            or CDMGCDIDMatches(entry.overrideSpellID, targetID)
            or CDMGCDIDMatches(entry.spellID, targetID)
            or CDMGCDIDMatches(entry.id, targetID)
            or CDMGCDIDMatches(entry.itemID, targetID) then
            return true
        end

        if EventTraceIsItemLikeEntry(entry) then
            local itemID = EventTraceResolveItemCooldownIdentity(entry)
            if CDMGCDIDMatches(itemID, targetID) then
                return true
            end
            if Sources and Sources.QueryBestOwnedItemVariant then
                local targetVariant = Sources.QueryBestOwnedItemVariant(targetID)
                if CDMGCDIDMatches(itemID, targetVariant) then
                    return true
                end
                local entryVariant = Sources.QueryBestOwnedItemVariant(itemID)
                if CDMGCDIDMatches(entryVariant, targetID) then
                    return true
                end
            end
        end

        return false
    end
    local name = entry.name
    if CDMGCDIsSecret(name) then return false end
    if type(name) ~= "string" then return false end
    return name:lower():find(needle, 1, true) ~= nil
end

local function CDMGCDParseRequest(msg)
    local text = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" then
        return "", 5, false, false
    end

    local lower = text:lower()
    if lower == "off" or lower == "stop" or lower == "clear" then
        return text, 0, false, true
    end

    local duration = 5
    local once = false
    local base, tail = text:match("^(.-)%s+(%S+)$")
    if base and base ~= "" then
        local tailLower = tail:lower()
        local tailNumber = tonumber(tail)
        if tailLower == "once" then
            text = base
            once = true
        elseif tailLower == "watch" then
            text = base
        elseif tailNumber then
            text = base
            duration = tailNumber
        end
    end

    if duration < 1 then duration = 1 end
    if duration > 15 then duration = 15 end
    return text, duration, once, false
end

local watchFrames = {}

local function AcquireWatchFrame(key)
    local frame = watchFrames[key]
    if not frame then
        if not CreateFrame then return nil end
        frame = CreateFrame("Frame")
        watchFrames[key] = frame
    end
    frame:SetScript("OnUpdate", nil)
    return frame
end

local function StopWatchFrame(key)
    local frame = watchFrames[key]
    if frame then frame:SetScript("OnUpdate", nil) end
end

local function CDMGCDStopWatch(silent)
    StopWatchFrame("gcd")
    if not silent then
        print("|cffffaa00[cdmgcd]|r watch stopped.")
    end
end

local function CDMGCDPrintWatchSample(elapsed, needle, targetID)
    local matches = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMGCDIconMatches(icon, needle, targetID) then
                matches = matches + 1
                local entry = icon._spellEntry
                local sid = CDMGCDFirstID(
                    icon._runtimeSpellID,
                    entry.overrideSpellID,
                    entry.spellID,
                    entry.id,
                    entry.itemID)
                local cdInfo = sid and Sources and Sources.QuerySpellCooldown
                    and Sources.QuerySpellCooldown(sid)
                local cdActive = cdInfo and EventTraceCooldownInfoField(cdInfo, "isActive")
                local cdOnGCD = cdInfo and EventTraceCooldownInfoField(cdInfo, "isOnGCD")
                local gcdDur = sid and Sources and Sources.QuerySpellCooldownDuration
                    and Sources.QuerySpellCooldownDuration(sid, false)
                local realDur = sid and Sources and Sources.QuerySpellCooldownDuration
                    and Sources.QuerySpellCooldownDuration(sid, true)
                local usable, resourceBlocked = nil, nil
                if sid and Sources and Sources.QuerySpellUsable then
                    usable, resourceBlocked = Sources.QuerySpellUsable(sid)
                end
                local resolvedState = CDMGCDResolveCooldownState(icon)
                local mode = resolvedState and resolvedState.mode
                local cd = icon.Cooldown

                print(string.format(
                    "|cff34d399[cdmgcd]|r +%.2f #%d sid=%s active=%s onGCD=%s usable=%s resourceBlocked=%s gcdDur=%s realDur=%s mode=%s showingGCD=%s draw=%s intended=%s shown=%s cdDur=%s cdShown=%s setErr=%s",
                    elapsed,
                    matches,
                    CDMGCDValue(sid),
                    CDMGCDValue(cdActive),
                    CDMGCDValue(cdOnGCD),
                    CDMGCDValue(usable),
                    CDMGCDValue(resourceBlocked),
                    CDMGCDValue(gcdDur),
                    CDMGCDValue(realDur),
                    tostring(mode),
                    tostring(icon._showingGCDSwipe),
                    CDMGCDCall(cd, "GetDrawSwipe"),
                    tostring(cd and cd._quiIntendedDrawSwipe),
                    CDMGCDCall(icon, "IsShown"),
                    CDMGCDCall(cd, "GetCooldownDuration"),
                    CDMGCDCall(cd, "IsShown"),
                    tostring(ns.CDMRenderers and ns.CDMRenderers._lastCooldownSetError)))
            end
        end
    end

    if matches == 0 then
        print(string.format("|cffffaa00[cdmgcd]|r +%.2f no icon found", elapsed))
    end
    return matches
end

local function CDMGCDStartWatch(text, needle, targetID, duration)
    local frame = GetTime and AcquireWatchFrame("gcd")
    if not frame then
        print("|cffffaa00[cdmgcd]|r watch unavailable.")
        return
    end

    local startTime = GetTime()
    local nextSample = 0
    local sampleCount = 0
    local lastMatches = 0
    local interval = 0.2

    print(string.format(
        "|cff34d399[cdmgcd]|r watching '%s' for %.1fs - cast/use it now",
        text,
        duration))

    frame:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - startTime
        if elapsed < nextSample and elapsed < duration then
            return
        end
        if elapsed > duration then
            elapsed = duration
        end

        sampleCount = sampleCount + 1
        lastMatches = CDMGCDPrintWatchSample(elapsed, needle, targetID)
        nextSample = nextSample + interval

        if elapsed >= duration then
            self:SetScript("OnUpdate", nil)
            print(string.format(
                "|cff34d399[cdmgcd]|r ended samples=%d matches=%d",
                sampleCount,
                lastMatches))
        end
    end)
end

local function RunCDMDebugGCD(msg)
    local text, duration, once, stop = CDMGCDParseRequest(msg)
    if stop then
        CDMGCDStopWatch(false)
        return
    end
    if text == "" then
        print("|cffffaa00[cdmgcd]|r Usage: /cdmdebug spell <spellID or spell name> [once|watch [seconds]|off]")
        return
    end
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmgcd]|r Owned engine not enabled.")
        return
    end

    local targetID = tonumber(text:match("^(%d+)$"))
    local needle = targetID and nil or text:lower()
    local swipe = ns._OwnedSwipe or (_G.QUI and _G.QUI.CooldownSwipe)
    local settings = swipe and swipe.GetSettings and swipe.GetSettings() or nil
    local settingsShowGCD = settings and settings.showGCDSwipe
    local settingsShowCooldown = settings and settings.showCooldownSwipe
    local runtimeShowGCD = CDMIcons.IsGCDSwipeEnabled and CDMIcons.IsGCDSwipeEnabled()

    print(string.format(
        "|cff34d399[cdmgcd]|r settings showGCDSwipe=%s showCooldownSwipe=%s runtimeGCDEnabled=%s swipeModule=%s",
        CDMGCDValue(settingsShowGCD),
        CDMGCDValue(settingsShowCooldown),
        CDMGCDValue(runtimeShowGCD),
        swipe and "yes" or "nil"))

    local matches = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMGCDIconMatches(icon, needle, targetID) then
                matches = matches + 1
                local entry = icon._spellEntry
                local sid = CDMGCDFirstID(
                    icon._runtimeSpellID,
                    entry.overrideSpellID,
                    entry.spellID,
                    entry.id,
                    entry.itemID)
                local cdInfo = sid and Sources and Sources.QuerySpellCooldown
                    and Sources.QuerySpellCooldown(sid)
                local cdActive = cdInfo and EventTraceCooldownInfoField(cdInfo, "isActive")
                local cdOnGCD = cdInfo and EventTraceCooldownInfoField(cdInfo, "isOnGCD")
                local gcdDur = sid and Sources and Sources.QuerySpellCooldownDuration
                    and Sources.QuerySpellCooldownDuration(sid, false)
                local realDur = sid and Sources and Sources.QuerySpellCooldownDuration
                    and Sources.QuerySpellCooldownDuration(sid, true)
                local chargeDur = sid and Sources and Sources.QuerySpellChargeDuration
                    and Sources.QuerySpellChargeDuration(sid)
                local charges = sid and Sources and Sources.QuerySpellCharges
                    and Sources.QuerySpellCharges(sid)
                local chargeActive = charges and charges.isActive
                local maxCharges = charges and charges.maxCharges
                local usable, resourceBlocked = nil, nil
                if sid and Sources and Sources.QuerySpellUsable then
                    usable, resourceBlocked = Sources.QuerySpellUsable(sid)
                end
                local resolvedState = CDMGCDResolveCooldownState(icon)
                local durObj = resolvedState and resolvedState.durObj
                local mode = resolvedState and resolvedState.mode
                local sourceID = resolvedState and resolvedState.sourceID
                local cd = icon.Cooldown

                print(string.format(
                    "|cff34d399[cdmgcd]|r #%d %s sid=%s viewer=%s kind=%s type=%s shown=%s",
                    matches,
                    CDMGCDValue(entry.name),
                    CDMGCDValue(sid),
                    CDMGCDValue(entry.viewerType),
                    CDMGCDValue(entry.kind),
                    CDMGCDValue(entry.type),
                    CDMGCDCall(icon, "IsShown")))
                print(string.format(
                    "|cff34d399[cdmgcd]|r api isActive=%s isOnGCD=%s usable=%s resourceBlocked=%s gcdDur=%s realDur=%s chargeDur=%s chargeActive=%s maxCharges=%s",
                    CDMGCDValue(cdActive),
                    CDMGCDValue(cdOnGCD),
                    CDMGCDValue(usable),
                    CDMGCDValue(resourceBlocked),
                    CDMGCDValue(gcdDur),
                    CDMGCDValue(realDur),
                    CDMGCDValue(chargeDur),
                    CDMGCDValue(chargeActive),
                    CDMGCDValue(maxCharges)))
                print(string.format(
                    "|cff34d399[cdmgcd]|r resolver mode=%s durObj=%s source=%s resolvedMode=%s lastKey=%s",
                    tostring(mode),
                    CDMGCDValue(durObj),
                    CDMGCDValue(sourceID),
                    tostring(icon._resolvedCooldownMode),
                    tostring(icon._lastDurObjKey)))
                print(string.format(
                    "|cff34d399[cdmgcd]|r icon showingGCD=%s showingReal=%s hasReal=%s hasCooldown=%s aura=%s",
                    tostring(icon._showingGCDSwipe),
                    tostring(icon._showingRealCooldownSwipe),
                    tostring(icon._hasRealCooldownActive),
                    tostring(icon._hasCooldownActive),
                    tostring(icon._auraActive)))
                print(string.format(
                    "|cff34d399[cdmgcd]|r cooldown drawSwipe=%s intendedDrawSwipe=%s drawEdge=%s intendedDrawEdge=%s color=%s",
                    CDMGCDCall(cd, "GetDrawSwipe"),
                    tostring(cd and cd._quiIntendedDrawSwipe),
                    CDMGCDCall(cd, "GetDrawEdge"),
                    tostring(cd and cd._quiIntendedDrawEdge),
                    CDMGCDValue(cd and cd._quiIntendedSwipeColor)))
                local setErr = ns.CDMRenderers and ns.CDMRenderers._lastCooldownSetError
                if setErr ~= nil then
                    print("|cffff5555[cdmgcd]|r SetCooldownFromDurationObject threw: " .. tostring(setErr))
                end
                print(string.format(
                    "|cff34d399[cdmgcd]|r widget dur=%s shown=%s alpha=%s w=%s cdLevel=%s iconLevel=%s",
                    CDMGCDCall(cd, "GetCooldownDuration"),
                    CDMGCDCall(cd, "IsShown"),
                    CDMGCDCall(cd, "GetEffectiveAlpha"),
                    CDMGCDCall(cd, "GetWidth"),
                    CDMGCDCall(cd, "GetFrameLevel"),
                    CDMGCDCall(icon, "GetFrameLevel")))
            end
        end
    end

    if matches == 0 then
        print("|cffffaa00[cdmgcd]|r no icon found for '" .. text .. "'")
    end
    if not once then
        CDMGCDStartWatch(text, needle, targetID, duration)
    end
end

local function CDMDebugClassifySpellCooldownState(spellID)
    if CDMIcons.ClassifySpellCooldownState then
        return CDMIcons.ClassifySpellCooldownState(spellID)
    end
    if not (spellID and Sources and Sources.QuerySpellCooldown) then
        return nil, nil, nil
    end

    local cdInfo = Sources.QuerySpellCooldown(spellID)
    if not cdInfo then
        return nil, nil, nil
    end

    local apiActive, apiSecret = EventTraceCooldownInfoField(cdInfo, "isActive")
    local onGCD, gcdSecret = EventTraceCooldownInfoField(cdInfo, "isOnGCD")
    if apiSecret or gcdSecret then
        return nil, nil, nil
    end

    local realActive
    if apiActive == true then
        if onGCD == true then
            local realDur = Sources.QuerySpellCooldownDuration
                and Sources.QuerySpellCooldownDuration(spellID, true)
            realActive = realDur and true or false
        else
            realActive = true
        end
    elseif apiActive == false then
        realActive = false
    end

    return apiActive, realActive, onGCD
end

local function RunCDMDebugCharge(msg)
    local targetText = TrimText(msg)
    if targetText == "" then
        print("|cffffaa00[cdmcharge]|r Usage: /cdmdebug spell <spell name> charge")
        return
    end
    local targetID = tonumber(targetText:match("^(%d+)$"))
    local needle = targetID and nil or targetText:lower()
    local matches = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry and CDMGCDIconMatches(icon, needle, targetID) then
                matches = matches + 1
                local sid = icon._runtimeSpellID
                    or entry.overrideSpellID or entry.spellID or entry.id
                local apiA, realA, onGCD = CDMDebugClassifySpellCooldownState(sid)
                local chargeDur = Sources and Sources.QuerySpellChargeDuration
                    and Sources.QuerySpellChargeDuration(sid)
                local cdDur = Sources and Sources.QuerySpellCooldownDuration
                    and Sources.QuerySpellCooldownDuration(sid, true)
                print(string.format(
                    "|cff34d399[cdmcharge]|r %s sid=%s hasCharges=%s apiA=%s realA=%s onGCD=%s chargeDur=%s cdDur=%s",
                    tostring(entry.name), tostring(sid),
                    tostring(entry.hasCharges),
                    tostring(apiA), tostring(realA), tostring(onGCD),
                    chargeDur and "yes" or "nil",
                    cdDur and "yes" or "nil"))
            end
        end
    end
    if matches == 0 then
        print("|cffffaa00[cdmcharge]|r no icon found for '" .. targetText .. "'")
    end
end

local function RunCDMDebugFlicker(msg)
    local targetText = TrimText(msg)
    if targetText == "" then
        print("|cffffaa00[cdmflicker]|r Usage: /cdmdebug spell <spell name> flicker")
        return
    end
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmflicker]|r Owned engine not enabled.")
        return
    end

    local target
    local targetID = tonumber(targetText:match("^(%d+)$"))
    local needle = targetID and nil or targetText:lower()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon._spellEntry and CDMGCDIconMatches(icon, needle, targetID) then
                target = icon
                break
            end
        end
        if target then break end
    end
    if not target then
        print("|cffffaa00[cdmflicker]|r Icon not found: " .. targetText)
        return
    end

    print(string.format(
        "|cff34d399[cdmflicker]|r logging '%s' for 5s — cast the spell NOW so the flicker happens within the window",
        targetText))

    local samples = {}
    local lastSig = nil
    local startTime = GetTime()
    local frame = AcquireWatchFrame("flicker")
    if not frame then
        print("|cffffaa00[cdmflicker]|r sampler unavailable.")
        return
    end

    local function snapshot()
        local now = GetTime() - startTime
        local rState = CDMGCDResolveCooldownState(target)
        local rMode = rState and rState.mode

        local sig = string.format(
            "aA=%s sRC=%s hRC=%s sGCD=%s rMode=%s",
            tostring(target._auraActive),
            tostring(target._showingRealCooldownSwipe),
            tostring(target._hasRealCooldownActive),
            tostring(target._showingGCDSwipe),
            tostring(rMode))

        if sig ~= lastSig then
            samples[#samples+1] = string.format("+%.3f  %s", now, sig)
            lastSig = sig
        end

        if now > 5 then
            frame:SetScript("OnUpdate", nil)
            print(string.format(
                "|cff34d399[cdmflicker]|r '%s' end — %d transitions over 5s",
                targetText, #samples))
            for _, s in ipairs(samples) do
                print(s)
            end
        end
    end

    frame:SetScript("OnUpdate", snapshot)
end

local function CDMItemAuraStopWatch(silent)
    StopWatchFrame("itemaura")
    if not silent then
        print("|cffffaa00[cdmaura]|r watch stopped.")
    end
end

local function CDMItemAuraHasOpaqueValue(value)
    if CDMGCDIsSecret(value) then return true end
    return value ~= nil
end

local function CDMItemAuraField(owner, key)
    if not owner or CDMGCDIsSecret(owner) then return nil end
    local ok, value = pcall(function() return owner[key] end)
    if ok then return value end
    return nil
end

local function CDMItemAuraResolveItem(entry)
    if not entry then return nil, nil, nil end
    local itemID, slotID, itemSpellID = EventTraceResolveItemCooldownIdentity(entry)
    return itemID, slotID, itemSpellID
end

local function CDMItemAuraSnapshot(icon, elapsed)
    local entry = icon and icon._spellEntry
    if not entry then return nil end

    local itemID, slotID, itemSpellID = CDMItemAuraResolveItem(entry)
    local itemStart, itemDuration, itemEnabled
    if itemID and Sources and Sources.QueryItemCooldown then
        itemStart, itemDuration, itemEnabled = Sources.QueryItemCooldown(itemID)
    end

    local scanner = QUI and QUI.SpellScanner
    local scannerItemActive, scannerExpiration, scannerDuration, scannerAuraInstanceID, scannerAuraUnit
    if scanner and scanner.IsItemActive and itemID then
        local ok, active, expiration, duration, auraInstanceID, auraUnit =
            pcall(scanner.IsItemActive, itemID)
        if ok then
            scannerItemActive = active
            scannerExpiration = expiration
            scannerDuration = duration
            scannerAuraInstanceID = auraInstanceID
            scannerAuraUnit = auraUnit
        end
    end

    local scanned
    if Sources and Sources.QueryScannedItemAuraInfo and itemID then
        scanned = Sources.QueryScannedItemAuraInfo(itemID, itemSpellID)
    end

    local auraUnit = (scanned and scanned.auraUnit) or scannerAuraUnit or "player"
    local auraInstanceID = scanned and scanned.auraInstanceID or scannerAuraInstanceID
    local auraDurObj, auraData
    if CDMItemAuraHasOpaqueValue(auraInstanceID) and Sources then
        if Sources.QueryAuraDuration then
            auraDurObj = Sources.QueryAuraDuration(auraUnit, auraInstanceID)
        end
        if Sources.QueryAuraDataByAuraInstanceID then
            auraData = Sources.QueryAuraDataByAuraInstanceID(auraUnit, auraInstanceID)
        end
    end

    local resolvedState = CDMGCDResolveCooldownState(icon)
    local cd = icon.Cooldown

    local fields = {
        "name=" .. CDMGCDValue(entry.name),
        "item=" .. CDMGCDValue(itemID),
        "slot=" .. CDMGCDValue(slotID),
        "use=" .. CDMGCDValue(itemSpellID),
        "itemCd=" .. CDMGCDValue(itemStart) .. "/" .. CDMGCDValue(itemDuration) .. "/" .. CDMGCDValue(itemEnabled),
        "scan=" .. CDMGCDValue(scannerItemActive) .. " " .. CDMGCDValue(scannerExpiration) .. "/" .. CDMGCDValue(scannerDuration),
        "scanInst=" .. tostring(CDMItemAuraHasOpaqueValue(scannerAuraInstanceID)),
        "scanned=" .. CDMGCDValue(scanned and scanned.active)
            .. " src=" .. CDMGCDValue(scanned and scanned.source)
            .. " buff=" .. CDMGCDValue(scanned and scanned.buffSpellID)
            .. " use=" .. CDMGCDValue(scanned and scanned.useSpellID)
            .. " exp=" .. CDMGCDValue(scanned and scanned.expiration)
            .. " dur=" .. CDMGCDValue(scanned and scanned.duration)
            .. " inst=" .. tostring(CDMItemAuraHasOpaqueValue(scanned and scanned.auraInstanceID)),
        "auraObj=" .. CDMGCDValue(auraDurObj),
        "auraData=" .. CDMGCDValue(auraData)
            .. " exp=" .. CDMGCDValue(CDMItemAuraField(auraData, "expirationTime"))
            .. " dur=" .. CDMGCDValue(CDMItemAuraField(auraData, "duration")),
        "resolver=" .. CDMGCDValue(resolvedState and resolvedState.mode)
            .. " src=" .. CDMGCDValue(resolvedState and resolvedState.sourceID)
            .. " active=" .. CDMGCDValue(resolvedState and resolvedState.active)
            .. " durObj=" .. CDMGCDValue(resolvedState and resolvedState.durObj)
            .. " num=" .. CDMGCDValue(resolvedState and resolvedState.start)
            .. "/" .. CDMGCDValue(resolvedState and resolvedState.duration)
            .. " aura=" .. CDMGCDValue(resolvedState and resolvedState.auraActive)
            .. " hasInst=" .. CDMGCDValue(resolvedState and resolvedState.hasAuraInstanceID)
            .. " auraSpell=" .. CDMGCDValue(resolvedState and resolvedState.resolvedAuraSpellID)
            .. " onCd=" .. CDMGCDValue(resolvedState and resolvedState.isOnCooldown)
            .. " render=" .. CDMGCDValue(resolvedState and resolvedState.hasRenderableCooldown),
        "iconMode=" .. CDMGCDValue(icon._resolvedCooldownMode)
            .. " key=" .. CDMGCDValue(icon._lastDurObjKey)
            .. " aura=" .. CDMGCDValue(icon._auraActive)
            .. " hasCd=" .. CDMGCDValue(icon._hasCooldownActive)
            .. " real=" .. CDMGCDValue(icon._hasRealCooldownActive)
            .. " draw=" .. CDMGCDCall(cd, "GetDrawSwipe")
            .. " shown=" .. CDMGCDCall(icon, "IsShown"),
    }

    local sig = table.concat(fields, " ")
    return string.format("+%.2f %s", elapsed or 0, sig), sig
end

local function RunCDMDebugItemAura(msg, seconds)
    local targetText = TrimText(msg)
    if targetText == "" then
        print("|cffffaa00[cdmaura]|r Usage: /cdmdebug spell <itemID|name> aura [seconds]")
        return
    end
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmaura]|r Owned engine not enabled.")
        return
    end

    local targetID = tonumber(targetText:match("^(%d+)$"))
    local needle = targetID and nil or targetText:lower()
    local matched = {}
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon._spellEntry and CDMGCDIconMatches(icon, needle, targetID) then
                matched[#matched + 1] = icon
            end
        end
    end
    if #matched == 0 then
        print("|cffffaa00[cdmaura]|r no icon found for '" .. targetText .. "'")
        return
    end

    local duration = tonumber(seconds) or 10
    if duration < 1 then duration = 1 end
    if duration > 30 then duration = 30 end
    CDMItemAuraStopWatch(true)

    print(string.format(
        "|cff34d399[cdmaura]|r watching '%s' for %.1fs; logs only state changes. Use /cdmdebug spell off to stop.",
        targetText,
        duration))

    local frame = AcquireWatchFrame("itemaura")
    if not frame then
        print("|cffffaa00[cdmaura]|r watch unavailable.")
        return
    end
    local startTime = GetTime()
    local lastSigByIcon = {}
    local transitionCount = 0
    local nextSample = 0
    local interval = 0.05

    frame:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - startTime
        if elapsed < nextSample and elapsed < duration then return end
        nextSample = nextSample + interval

        for i, icon in ipairs(matched) do
            local line, sig = CDMItemAuraSnapshot(icon, elapsed)
            if line and sig ~= lastSigByIcon[i] then
                transitionCount = transitionCount + 1
                lastSigByIcon[i] = sig
                print("|cff34d399[cdmaura]|r #" .. tostring(i) .. " " .. line)
            end
        end

        if elapsed >= duration then
            self:SetScript("OnUpdate", nil)
            print(string.format(
                "|cff34d399[cdmaura]|r ended icons=%d transitions=%d",
                #matched,
                transitionCount))
        end
    end)
end

local SecretRows = { count = 0 }

local function AppendSecretRow(label, value)
    if not (C_StringUtil and C_StringUtil.WrapString) then return end
    if not SecretRows.frame then
        local frame = CreateFrame("Frame", "QUI_CDMProbeSecretRows", UIParent)
        frame:SetSize(760, 190)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 8, -8)
        text:SetPoint("BOTTOMRIGHT", -8, 8)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        SecretRows.frame = frame
        SecretRows.text = text
    end
    local header = "|cff34d399[cdmprobe]|r secret rows (drag to move):"
    if SecretRows.count == 0 or SecretRows.count >= 10 then
        SecretRows.buffer = header
        SecretRows.count = 0
    end
    SecretRows.buffer = C_StringUtil.WrapString(SecretRows.buffer, nil, "\n" .. label)
    SecretRows.buffer = C_StringUtil.WrapString(SecretRows.buffer, nil, value)
    SecretRows.count = SecretRows.count + 1
    SecretRows.text:SetText(SecretRows.buffer)
    SecretRows.frame:Show()
end

local function RunCDMDebugProbe()
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmprobe]|r Owned engine not enabled.")
        return
    end

    local HookTextHasDisplay = CDMIcons.HookTextHasDisplay

    local rows = 0
    local agree = 0
    local disagree = 0
    local resolverInactive = 0

    print("|cff34d399[cdmprobe]|r begin parity sweep")
    print("name | kind | mode | mActive | parity | rText | curText | textPar")

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon:IsShown() and icon._spellEntry then
                local entry = icon._spellEntry
                local name = entry.name or "?"
                local kind = entry.kind or "?"

                local state = CDMGCDResolveCooldownState(icon)
                local mode = state and state.mode
                local rText = CDMIcons.ResolveIconStackText(icon)
                local curText = icon.StackText and icon.StackText:GetText()
                local rIsSecret = DebugIsSecretValue(rText)
                local cIsSecret = DebugIsSecretValue(curText)
                if not cIsSecret and curText == nil then
                    curText = ""
                end
                local textParity
                if rIsSecret or cIsSecret then
                    textParity = "secret"
                elseif not HookTextHasDisplay(rText) and not HookTextHasDisplay(curText) then
                    textParity = "OK"
                elseif rText == curText then
                    textParity = "OK"
                else
                    textParity = "MISMATCH"
                end
                local resolverActive = (mode ~= "inactive")
                local mirrorActive = icon._hasRealCooldownActive == true
                                  or icon._showingRealCooldownSwipe == true
                                  or icon._auraActive == true

                local parity
                if resolverActive == mirrorActive then
                    parity = "OK"
                    agree = agree + 1
                else
                    parity = "MISMATCH"
                    disagree = disagree + 1
                end
                if mode == "inactive" then
                    resolverInactive = resolverInactive + 1
                end

                rows = rows + 1
                local rTextDisplay = rIsSecret and "<secret>" or (rText == nil and "nil" or tostring(rText))
                local curTextDisplay = cIsSecret and "<secret>" or (curText == nil and "nil" or tostring(curText))
                print(string.format("%s | %s | %s | %s | %s | %s | %s | %s",
                    name, kind, mode,
                    mirrorActive and "yes" or "no",
                    parity,
                    rTextDisplay, curTextDisplay, textParity))

                if rIsSecret then
                    AppendSecretRow("  |cff888888\\_ rText[" .. name .. "]:|r ", rText)
                end
                if cIsSecret then
                    AppendSecretRow("  |cff888888\\_ curText[" .. name .. "]:|r ", curText)
                end
            end
        end
    end

    print(string.format(
        "|cff34d399[cdmprobe]|r end — %d icons, %d agree, %d mismatch (%.1f%%), %d inactive",
        rows, agree, disagree,
        rows > 0 and (100 * agree / rows) or 0,
        resolverInactive))
end

local function RunCDMDebugMint()
    local P = "|cff34D399[CDM-Mint]|r"

    local secinfo = SecureFieldInfo

    local settings = _G.CooldownViewerSettings
    local provider = settings and settings.GetDataProvider and settings:GetDataProvider()
    if not provider then
        print(P .. " provider: |cffffaa00nil (data not loaded yet)|r")
    else
        local built = (not provider.displayDataDirty) and provider.displayData ~= nil
        print(string.format("%s provider: built=%s dirty=%s displayData=%s displayDataDirty=%s",
            P, tostring(built), tostring(provider.displayDataDirty),
            secinfo(provider, "displayData"), secinfo(provider, "displayDataDirty")))
    end

    local viewers = {
        { "Essential", _G.EssentialCooldownViewer },
        { "Utility", _G.UtilityCooldownViewer },
        { "BuffIcon", _G.BuffIconCooldownViewer },
        { "BuffBar", _G.BuffBarCooldownViewer },
    }
    for _, row in ipairs(viewers) do
        local label, viewer = row[1], row[2]
        if viewer then
            print(string.format("%s %s: shown=%s visibleSetting=%s hideWhenInactive=%s",
                P, label, tostring(viewer:IsShown()),
                secinfo(viewer, "visibleSetting"), secinfo(viewer, "hideWhenInactive")))
        end
    end

    local buffViewer = _G.BuffIconCooldownViewer
    local pool = buffViewer and buffViewer.itemFramePool
    if not (pool and pool.EnumerateActive) then
        print(P .. " BuffIcon item pool unavailable")
        return
    end
    local items, active = 0, 0
    for item in pool:EnumerateActive() do
        items = items + 1
        local okID, cooldownID = pcall(item.GetCooldownID, item)
        if not okID or issecretvalue(cooldownID) then cooldownID = "?" end
        local okActive, isActive = pcall(item.IsActive, item)
        if not okActive or issecretvalue(isActive) then isActive = "?" end
        if isActive == true then active = active + 1 end
        print(string.format(
            "%s   item %d: cooldownID=%s active=%s shown=%s | cooldownID=%s cooldownInfo=%s isActive=%s",
            P, items, tostring(cooldownID), tostring(isActive), tostring(item:IsShown()),
            secinfo(item, "cooldownID"), secinfo(item, "cooldownInfo"), secinfo(item, "isActive")))
    end
    print(string.format("%s BuffIcon items=%d active=%d", P, items, active))
end

local function RunCDMDebugProfiles()
    local P = "|cff34D399[CDM-Profiles]|r"
    local db = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    if not db then
        print(P, "No ncdm database found.")
        return
    end

    local currentSpecID = GetSpecialization and GetSpecializationInfo(GetSpecialization()) or "?"
    print(P, "Current spec ID:", currentSpecID)
    print(P, "_lastSpecID:", db._lastSpecID or "nil")

    local profiles = db._specProfiles
    if not profiles or not next(profiles) then
        print(P, "_specProfiles: empty/nil")
        return
    end

    for specID, specData in pairs(profiles) do
        local label = specID
        if GetSpecializationInfoByID then
            local _, specName = GetSpecializationInfoByID(specID)
            if specName then label = specID .. " (" .. specName .. ")" end
        end
        local containerCount = 0
        local totalSpells = 0
        for key, cData in pairs(specData) do
            if type(cData) == "table" and cData.ownedSpells then
                containerCount = containerCount + 1
                local count = type(cData.ownedSpells) == "table" and #cData.ownedSpells or 0
                totalSpells = totalSpells + count
                local spellNames = {}
                if type(cData.ownedSpells) == "table" then
                    for i = 1, math.min(5, #cData.ownedSpells) do
                        local entry = cData.ownedSpells[i]
                        if entry and entry.id then
                            local sname = Sources and Sources.QuerySpellName and Sources.QuerySpellName(entry.id)
                            spellNames[#spellNames + 1] = (sname or "?") .. "(" .. entry.id .. ")"
                        end
                    end
                end
                local dormantCount = 0
                if type(cData.dormantSpells) == "table" then
                    for _ in pairs(cData.dormantSpells) do dormantCount = dormantCount + 1 end
                end
                local removedCount = 0
                if type(cData.removedSpells) == "table" then
                    for _ in pairs(cData.removedSpells) do removedCount = removedCount + 1 end
                end
                print(P, "  " .. key .. ":", count, "owned,", dormantCount, "dormant,", removedCount, "removed")
                if #spellNames > 0 then
                    local suffix = count > 5 and (" +" .. (count - 5) .. " more") or ""
                    print(P, "    ", table.concat(spellNames, ", ") .. suffix)
                end
            end
        end
        print(P, label .. ":", containerCount, "containers,", totalSpells, "total spells")
    end
end

local function CDMDebugIsSpellKnownByPlayer(spellID)
    if type(spellID) ~= "number" then return false end

    local spellData = ns.CDMSpellData
    if spellData and type(spellData.IsSpellKnown) == "function" then
        local ok, isKnown = pcall(spellData.IsSpellKnown, spellData, spellID)
        if ok and isKnown then
            return true
        end
    end

    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        local ok, isKnown = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and isKnown then
            return true
        end
    end

    return false
end

local CDM_DEBUG_BUILTIN_CONTAINER_KEYS = {
    essential = true,
    utility = true,
    buff = true,
    trackedBar = true,
}

local function CDMDebugCountSet(set)
    local count = 0
    if type(set) == "table" then
        for _ in pairs(set) do
            count = count + 1
        end
    end
    return count
end

local function CDMDebugGetCurrentProfileName(addonDB)
    if addonDB and type(addonDB.GetCurrentProfile) == "function" then
        local ok, profileName = pcall(addonDB.GetCurrentProfile, addonDB)
        if ok and type(profileName) == "string" and profileName ~= "" then
            return profileName
        end
    end
    return "Default"
end

local function CDMDebugGetCurrentSpecID()
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = GetSpecializationInfo(specIndex)
            if type(specID) == "number" and specID ~= 0 then
                return specID
            end
        end
    end
    return nil
end

local function CDMDebugNormalizeLoadoutID(loadoutID)
    if loadoutID == nil or loadoutID == -2 then return 0 end
    if type(loadoutID) == "number" and loadoutID > 0 then return loadoutID end
    return 0
end

local function CDMDebugGetCurrentLoadoutID(profileDB, charDB, specID)
    if not profileDB or not profileDB.perLoadoutSpec then return 0 end
    if type(specID) ~= "number" or specID == 0 then return 0 end

    local savedID
    if C_ClassTalents and type(C_ClassTalents.GetLastSelectedSavedConfigID) == "function" then
        local ok, result = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
        if ok then
            savedID = result
        end
    end
    if savedID ~= nil then
        return CDMDebugNormalizeLoadoutID(savedID)
    end

    local cache = charDB and charDB._lastLoadoutConfigID
    local cachedID = type(cache) == "table" and cache[specID]
    return CDMDebugNormalizeLoadoutID(cachedID)
end

local function CDMDebugCollectCurrentSpecCDMSpells()
    local knownSpells = {}
    local catalog = ns.CDMCatalog
    if catalog and type(catalog.CollectKnownCDMSpellIDs) == "function" then
        local ok = pcall(catalog.CollectKnownCDMSpellIDs, knownSpells)
        if ok and next(knownSpells) then
            return knownSpells
        end
    end

    local composer = ns.CDMComposer
    if composer and type(composer.CollectKnownCDMSpellIDs) == "function" then
        ns.SafeCall("report", composer.CollectKnownCDMSpellIDs, knownSpells)
    end
    return knownSpells
end

local function CDMDebugShouldKeepCurrentSpecEntry(entry, allowedSpells, containerKey)
    if not entry or entry.type ~= "spell" or type(entry.id) ~= "number" then
        return true
    end
    if allowedSpells[entry.id] then
        return true
    end

    if (containerKey == "buff" or containerKey == "trackedBar")
       and entry.kind == "aura"
       and entry.source ~= "blizzardCDM" then
        return true
    end

    return false
end

local function CDMDebugCleanContainerByAllowedSpells(cData, allowedSpells, label, containerKey, reasonLabel, P)
    if type(cData) ~= "table" then return 0 end
    local cleanedCount = 0

    if type(cData.ownedSpells) == "table" then
        local cleaned = {}
        local removed = 0
        for _, entry in ipairs(cData.ownedSpells) do
            if CDMDebugShouldKeepCurrentSpecEntry(entry, allowedSpells, containerKey) then
                cleaned[#cleaned + 1] = entry
            else
                removed = removed + 1
                local spellName = Sources and Sources.QuerySpellName and Sources.QuerySpellName(entry.id) or "?"
                print(P, "  Removed", spellName .. "(" .. entry.id .. ") from", label, containerKey, reasonLabel)
            end
        end
        if removed > 0 then
            cData.ownedSpells = cleaned
            cleanedCount = cleanedCount + removed
        end
    end

    if type(cData.dormantSpells) == "table" then
        for sid in pairs(cData.dormantSpells) do
            if type(sid) == "number" and not allowedSpells[sid] then
                cData.dormantSpells[sid] = nil
                cleanedCount = cleanedCount + 1
                local spellName = Sources and Sources.QuerySpellName and Sources.QuerySpellName(sid) or "?"
                print(P, "  Removed", spellName .. "(" .. sid .. ") from", label, containerKey, "dormant", reasonLabel)
            end
        end
    end

    return cleanedCount
end

local function CDMDebugCleanContainerMapByAllowedSpells(containerMap, allowedSpells, label, reasonLabel, P)
    if type(containerMap) ~= "table" then return 0 end
    local cleanedCount = 0
    for containerKey, cData in pairs(containerMap) do
        if CDM_DEBUG_BUILTIN_CONTAINER_KEYS[containerKey] then
            cleanedCount = cleanedCount
                + CDMDebugCleanContainerByAllowedSpells(cData, allowedSpells, label, containerKey, reasonLabel, P)
        end
    end
    return cleanedCount
end

local function RunCDMDebugClean()
    local P = "|cff34D399[CDM-Clean]|r"

    if InCombatLockdown() then
        print(P, "Cannot clean during combat.")
        return
    end

    local addonDB = ns.Addon and ns.Addon.db
    local profileDB = addonDB and addonDB.profile and addonDB.profile.ncdm
    local charDB = addonDB and addonDB.char and addonDB.char.ncdm
    if not profileDB then
        print(P, "No CDM profile to clean.")
        return
    end

    local _, playerClass = UnitClass("player")
    -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
    if issecretvalue and issecretvalue(playerClass) then playerClass = nil end
    if not playerClass then
        print(P, "Could not determine player class.")
        return
    end

    local knownSpells = {}
    local composer = ns.CDMComposer
    if composer and composer.CollectKnownCDMSpellIDs then
        composer.CollectKnownCDMSpellIDs(knownSpells)
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
        if numTabs then
            for tab = 1, numTabs do
                local sli = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                if sli then
                    local offset = sli.itemIndexOffset or 0
                    for i = 1, (sli.numSpellBookItems or 0) do
                        local ii = C_SpellBook.GetSpellBookItemInfo(offset + i, Enum.SpellBookSpellBank.Player)
                        if ii and ii.spellID then knownSpells[ii.spellID] = true end
                    end
                end
            end
        end
    end

    local totalCleaned = 0
    local profilesChecked = 0

    if type(profileDB._specProfiles) == "table" and next(profileDB._specProfiles) then
        for specID, specData in pairs(profileDB._specProfiles) do
            local specLabel = tostring(specID)
            local specClass
            if GetSpecializationInfoByID then
                local _, specName, _, _, _, classFile = GetSpecializationInfoByID(specID)
                if specName then specLabel = specID .. " (" .. specName .. ")" end
                specClass = classFile
            end

            if specClass == playerClass then
                profilesChecked = profilesChecked + 1
                local specCleaned = 0
                for containerKey, cData in pairs(specData) do
                    if type(cData) == "table" and type(cData.ownedSpells) == "table" then
                        local cleaned = {}
                        local removed = 0
                        for _, entry in ipairs(cData.ownedSpells) do
                            if entry and entry.id and entry.type == "spell" then
                                if knownSpells[entry.id] or CDMDebugIsSpellKnownByPlayer(entry.id) then
                                    cleaned[#cleaned + 1] = entry
                                else
                                    removed = removed + 1
                                    local spellName = Sources and Sources.QuerySpellName and Sources.QuerySpellName(entry.id) or "?"
                                    print(P, "  Removed", spellName .. "(" .. entry.id .. ") from", specLabel, containerKey)
                                end
                            else
                                cleaned[#cleaned + 1] = entry
                            end
                        end
                        if removed > 0 then
                            cData.ownedSpells = cleaned
                            specCleaned = specCleaned + removed
                        end
                        if type(cData.dormantSpells) == "table" then
                            for sid in pairs(cData.dormantSpells) do
                                if type(sid) == "number" and not knownSpells[sid] and not CDMDebugIsSpellKnownByPlayer(sid) then
                                    cData.dormantSpells[sid] = nil
                                    specCleaned = specCleaned + 1
                                end
                            end
                        end
                    end
                end
                if specCleaned > 0 then
                    totalCleaned = totalCleaned + specCleaned
                    print(P, specLabel .. ": cleaned", specCleaned, "foreign spells")
                else
                    print(P, specLabel .. ": clean")
                end
            elseif specClass and specClass ~= playerClass then
                local specCleaned = 0
                for containerKey, cData in pairs(specData) do
                    if type(cData) == "table" and type(cData.ownedSpells) == "table" then
                        local cleaned = {}
                        local removed = 0
                        for _, entry in ipairs(cData.ownedSpells) do
                            if entry and entry.id and entry.type == "spell"
                               and (knownSpells[entry.id] or CDMDebugIsSpellKnownByPlayer(entry.id)) then
                                removed = removed + 1
                                local spellName = Sources and Sources.QuerySpellName and Sources.QuerySpellName(entry.id) or "?"
                                print(P, "  Removed", spellName .. "(" .. entry.id .. ") from", specLabel, containerKey)
                            else
                                cleaned[#cleaned + 1] = entry
                            end
                        end
                        if removed > 0 then
                            cData.ownedSpells = cleaned
                            specCleaned = specCleaned + removed
                        end
                        if type(cData.dormantSpells) == "table" then
                            for sid in pairs(cData.dormantSpells) do
                                if type(sid) == "number" and (knownSpells[sid] or CDMDebugIsSpellKnownByPlayer(sid)) then
                                    cData.dormantSpells[sid] = nil
                                    specCleaned = specCleaned + 1
                                end
                            end
                        end
                    end
                end
                if specCleaned > 0 then
                    totalCleaned = totalCleaned + specCleaned
                    print(P, specLabel .. ": cleaned", specCleaned, "foreign spells")
                else
                    print(P, specLabel .. ": clean")
                end
            else
                print(P, specLabel .. ": skipped (unknown spec)")
            end
        end
    else
        print(P, "_specProfiles: empty/nil")
    end

    local currentSpecID = CDMDebugGetCurrentSpecID()
    local currentSpecSpells = CDMDebugCollectCurrentSpecCDMSpells()
    local currentSpecSpellCount = CDMDebugCountSet(currentSpecSpells)
    if currentSpecID and currentSpecSpellCount > 0 then
        local profileName = CDMDebugGetCurrentProfileName(addonDB)
        local loadoutID = CDMDebugGetCurrentLoadoutID(profileDB, charDB, currentSpecID)
        local byProfile = charDB and charDB._specProfilesByProfile and charDB._specProfilesByProfile[profileName]
        local scopedSlot = byProfile and byProfile[currentSpecID] and byProfile[currentSpecID][loadoutID]
        if type(scopedSlot) == "table" then
            profilesChecked = profilesChecked + 1
            local label = "current spec scoped " .. tostring(currentSpecID) .. "/" .. tostring(loadoutID)
            local scopedCleaned = CDMDebugCleanContainerMapByAllowedSpells(
                scopedSlot, currentSpecSpells, label, "missing from current spec CDM", P)
            totalCleaned = totalCleaned + scopedCleaned
            print(P, label .. ": cleaned", scopedCleaned, "entries")
        else
            print(P, "current spec scoped " .. tostring(currentSpecID) .. "/" .. tostring(loadoutID) .. ": empty/nil")
        end

        local liveCleaned = CDMDebugCleanContainerMapByAllowedSpells(
            profileDB, currentSpecSpells, "current live profile", "missing from current spec CDM", P)
        if liveCleaned > 0 then
            totalCleaned = totalCleaned + liveCleaned
            print(P, "current live profile: cleaned", liveCleaned, "entries")
        else
            print(P, "current live profile: clean")
        end
    else
        print(P, "current spec CDM catalog unavailable; skipped current scoped cleanup.")
    end

    print(P, "Done.", profilesChecked, "profiles checked,", totalCleaned, "entries removed.")
    print(P, "Run /cdmdebug profile to verify. Run this on each character to clean their specs.")
end

local CDMDebug = {}
ns.CDMDebug = CDMDebug

function CDMDebug.MatchFilter(flag, ...)
    if not flag then return false end
    if flag == true then return true end
    local needle = tostring(flag):lower()
    if needle == "" then return false end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v then
            local s = tostring(v):lower()
            if s == needle or s:find(needle, 1, true) then return true end
        end
    end
    return false
end

function CDMDebug.ShouldBar(entry, spellID)
    return CDMDebug.MatchFilter(_G.QUI_CDM_BAR_DEBUG, entry and entry.name, spellID)
end

function CDMDebug.ShouldAura(entryName, spellID, entryID)
    return CDMDebug.MatchFilter(_G.QUI_CDM_AURA_DEBUG, entryName, spellID, entryID)
end

function CDMDebug.FormatIDList(ids)
    if type(ids) ~= "table" or #ids == 0 then return "nil" end
    local out = {}
    for i, id in ipairs(ids) do
        out[i] = tostring(id)
    end
    return table.concat(out, ",")
end

local _chargeDebugThrottle = {}
function CDMDebug.Charge(spellName, ...)
    if not _G.QUI_CDM_CHARGE_DEBUG then return end
    local filter = _G.QUI_CDM_CHARGE_DEBUG
    if type(filter) == "string" and spellName and not spellName:find(filter, 1, true) then return end
    local tag = select(1, ...) or ""
    if tag == "FWD path:" or tag == "SKIP API path:" or tag == "API path:" or tag == "FWD path CLEAR:"
        or tag == "DESAT charged check:" or tag == "DESAT result:" then
        local key = (spellName or "") .. tag
        local now = GetTime()
        if _chargeDebugThrottle[key] and now - _chargeDebugThrottle[key] < 1 then return end
        _chargeDebugThrottle[key] = now
    end
    local parts = { "|cff34D399[CDM-Charge]|r", spellName or "?", "-" }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
end

function CDMIcons.DebugStackText(icon, action, value, reason)
    if not _G.QUI_CDM_CHARGE_DEBUG then return end
    local entry = icon and icon._spellEntry
    local okShown, shown = false, nil
    local okText, text = false, nil
    if icon then
        okShown = true; shown = icon.IsShown(icon)
    end
    if icon and icon.StackText and icon.StackText.GetText then
        okText = true; text = icon.StackText.GetText(icon.StackText)
    end
    CDMDebug.Charge(entry and entry.name,
        "STACKTEXT", action,
        "reason=", reason or "nil",
        "value=", tostring(value),
        "oldText=", okText and tostring(text) or "err",
        "iconShown=", okShown and tostring(shown) or "err",
        "entryType=", entry and entry.type,
        "viewerType=", entry and entry.viewerType,
        "hasCharges=", entry and entry.hasCharges,
        "spellID=", entry and entry.spellID,
        "overrideSpellID=", entry and entry.overrideSpellID,
        "runtimeSpellID=", icon and icon._runtimeSpellID,
        "auraActive=", icon and icon._auraActive)
end

function CDMDebug.Bar(entry, spellID, ...)
    if not CDMDebug.ShouldBar(entry, spellID) then return end
    print("|cff34D399[CDM-BarDbg]|r", ...)
end

function CDMDebug.Blizz(enabled, entry, label, ...)
    if not enabled then return end
    print("|cff34D399[CDM-BlizzBind]|r",
        tostring(label),
        entry and (entry.name or "?") or "?",
        "viewer=", entry and tostring(entry.viewerType) or "nil",
        "kind=", entry and tostring(entry.kind) or "nil",
        "entryID=", entry and tostring(entry.id) or "nil",
        "spellID=", entry and tostring(entry.spellID) or "nil",
        "override=", entry and tostring(entry.overrideSpellID) or "nil",
        ...)
end

local _auraDebugFrame
local _auraDebugFontStrings
local _auraDebugMaxLines = 30
local _auraDebugWriteIdx = 0

local function EnsureAuraDebugFrame()
    if _auraDebugFrame then return end
    _auraDebugFrame = CreateFrame("Frame", "QUI_CDMAuraDebugFrame", UIParent)
    _auraDebugFrame:SetSize(900, _auraDebugMaxLines * 16 + 16)
    _auraDebugFrame:SetPoint("TOPLEFT", 60, -120)
    _auraDebugFrame:SetFrameStrata("DIALOG")
    _auraDebugFrame:EnableMouse(true)
    _auraDebugFrame:SetMovable(true)
    _auraDebugFrame:RegisterForDrag("LeftButton")
    _auraDebugFrame:SetScript("OnDragStart", _auraDebugFrame.StartMoving)
    _auraDebugFrame:SetScript("OnDragStop", _auraDebugFrame.StopMovingOrSizing)
    local bg = _auraDebugFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    _auraDebugFontStrings = {}
    for i = 1, _auraDebugMaxLines do
        local fs = _auraDebugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 16)
        fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        _auraDebugFontStrings[i] = fs
    end
end

local function HasSecretArg(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue(select(i, ...)) then return true end
    end
    return false
end

function CDMDebug.Aura(enabled, ...)
    if not enabled then return end

    if not HasSecretArg(...) then
        local parts = { "|cff34D399[CDM-Aura]|r" }
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        print(table.concat(parts, " "))
        return
    end

    EnsureAuraDebugFrame()
    _auraDebugWriteIdx = (_auraDebugWriteIdx % _auraDebugMaxLines) + 1
    local fs = _auraDebugFontStrings and _auraDebugFontStrings[_auraDebugWriteIdx]
    if not fs then return end

    local canWrap = (C_StringUtil and C_StringUtil.WrapString) ~= nil
    local message = "|cff34D399[CDM-Aura]|r"
    local messageSecret = false
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local vSecret = (issecretvalue and issecretvalue(v)) or false
        local piece
        if vSecret and canWrap then
            piece = v
        elseif vSecret then
            piece = "<SECRET>"
        else
            piece = tostring(v)
        end
        if messageSecret or (vSecret and canWrap) then
            message = C_StringUtil.WrapString(message, nil, " ")
            message = C_StringUtil.WrapString(message, nil, piece)
            messageSecret = true
        else
            -- @secret-safe: messageSecret lockstep shadow flag; clean-only branch
            message = message .. " " .. piece
        end
    end

    fs:SetText(message)
end

local function _formatTaintField(name, v)
    local prefix = tostring(name) .. "="
    if issecretvalue and issecretvalue(v) then
        return prefix .. "<SECRET:" .. type(v) .. ">"
    end
    if v == nil then return prefix .. "nil" end
    local t = type(v)
    if t == "boolean" then return prefix .. (v and "true" or "false") .. ":bool" end
    if t == "number"  then return prefix .. tostring(v) .. ":num" end
    if t == "string"  then return prefix .. "\"" .. v .. "\":str" end
    return prefix .. "<" .. t .. ">"
end

local _taintFrame
local _taintEditBox
local _taintScroll
local _taintBuffer = {}
local _taintBufferMax = 1000
local _taintAutoScroll = true
local _taintLastMessage
local _taintLastRepeat = 0

local function _getTaintBufferMax()
    local n = tonumber(_G.QUI_CDM_TAINT_BUFFER_MAX)
    if not n then return _taintBufferMax end
    if n < 50 then return 50 end
    if n > 5000 then return 5000 end
    return math.floor(n)
end

local function _taintMessageAllowed(label, message)
    local filter = _G.QUI_CDM_TAINT_FILTER
    if type(_G.QUI_CDM_TAINT_DEBUG) == "string" then
        filter = _G.QUI_CDM_TAINT_DEBUG
    end
    if type(filter) ~= "string" or filter == "" then return true end

    local needle = filter:lower()
    local labelText = tostring(label):lower()
    return labelText:find(needle, 1, true) ~= nil
        or message:lower():find(needle, 1, true) ~= nil
end

local function _appendTaintMessage(message)
    if _taintLastMessage == message and #_taintBuffer > 0 then
        _taintLastRepeat = _taintLastRepeat + 1
        _taintBuffer[#_taintBuffer] = message .. " | repeat=" .. tostring(_taintLastRepeat) .. ":num"
    else
        _taintLastMessage = message
        _taintLastRepeat = 1
        _taintBuffer[#_taintBuffer + 1] = message
    end

    local maxLines = _getTaintBufferMax()
    while #_taintBuffer > maxLines do
        table.remove(_taintBuffer, 1)
    end
end

local function _ensureTaintFrame()
    if _taintFrame then return end
    _taintFrame = CreateFrame("Frame", "QUI_CDMTaintDebugFrame", UIParent)
    _taintFrame:SetSize(1100, 500)
    _taintFrame:SetPoint("TOPLEFT", 60, -50)
    _taintFrame:SetFrameStrata("DIALOG")
    _taintFrame:EnableMouse(true)
    _taintFrame:SetMovable(true)
    _taintFrame:RegisterForDrag("LeftButton")
    _taintFrame:SetScript("OnDragStart", _taintFrame.StartMoving)
    _taintFrame:SetScript("OnDragStop", _taintFrame.StopMovingOrSizing)

    local bg = _taintFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)

    local title = _taintFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetText("|cffFF6699[CDM Taint]|r drag to move \194\183 click text to select \194\183 Ctrl+A / Ctrl+C to copy \194\183 filter: /cdmdebug taint <text>")

    _taintScroll = CreateFrame("ScrollFrame", "QUI_CDMTaintDebugScroll", _taintFrame, "UIPanelScrollFrameTemplate")
    _taintScroll:SetPoint("TOPLEFT", 8, -22)
    _taintScroll:SetPoint("BOTTOMRIGHT", -28, 8)

    _taintEditBox = CreateFrame("EditBox", nil, _taintScroll)
    _taintEditBox:SetMultiLine(true)
    _taintEditBox:SetMaxLetters(0)
    _taintEditBox:SetFontObject("GameFontHighlightSmall")
    _taintEditBox:SetWidth(1060)
    _taintEditBox:SetAutoFocus(false)
    _taintEditBox:EnableMouse(true)
    _taintEditBox:SetScript("OnEscapePressed", _taintEditBox.ClearFocus)
    _taintEditBox:SetScript("OnEditFocusGained", function() _taintAutoScroll = false end)
    _taintEditBox:SetScript("OnEditFocusLost",   function() _taintAutoScroll = true end)
    _taintScroll:SetScrollChild(_taintEditBox)
end

function CDMDebug.Taint(label, ...)
    if not _G.QUI_CDM_TAINT_DEBUG then return end

    local n = select("#", ...)
    local message = "[Taint] " .. tostring(label)
    for i = 1, n, 2 do
        local k = select(i, ...)
        local v = select(i + 1, ...)
        message = message .. " | " .. _formatTaintField(k, v)
    end

    if not _taintMessageAllowed(label, message) then return end

    _ensureTaintFrame()
    if not _taintEditBox then return end

    _appendTaintMessage(message)

    _taintEditBox:SetText(table.concat(_taintBuffer, "\n"))

    if _taintAutoScroll and _taintScroll and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if _taintScroll then
                local maxScroll = _taintScroll:GetVerticalScrollRange()
                if maxScroll then _taintScroll:SetVerticalScroll(maxScroll) end
            end
        end)
    end
end

local function FindDebugTargetID(target)
    local numeric = tonumber(target and target:match("^(%d+)$"))
    if numeric then return numeric end
    local needle = TrimText(target):lower()
    if needle == "" then return nil end

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            local name = entry and entry.name
            if type(name) == "string" and name:lower():find(needle, 1, true) then
                return CDMGCDFirstID(
                    icon._runtimeSpellID,
                    entry.overrideSpellID,
                    entry.spellID,
                    entry.id,
                    entry.itemID)
            end
        end
    end
    return nil
end

local function FindDebugTargetName(target)
    local targetText = TrimText(target)
    if targetText == "" then return nil end
    local targetID = tonumber(targetText:match("^(%d+)$"))
    local needle = targetID and nil or targetText:lower()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry and CDMGCDIconMatches(icon, needle, targetID) then
                return entry.name
            end
        end
    end
    return nil
end

local SPELL_MODES = {
    once = true,
    watch = true,
    events = true,
    event = true,
    writes = true,
    write = true,
    trace = true,
    desat = true,
    charge = true,
    aura = true,
    itemaura = true,
    flicker = true,
}

local function ParseSpellDebugRequest(msg)
    local text = TrimText(msg)
    local lower = text:lower()
    if lower == "" then return "", "help", nil end
    if lower == "off" or lower == "clear" or lower == "stop" then
        return "", "off", nil
    end

    local seconds
    local base, tail = text:match("^(.-)%s+(%S+)$")
    if base and tonumber(tail) then
        seconds = tonumber(tail)
        text = TrimText(base)
        lower = text:lower()
    end

    local mode = seconds and "watch" or "once"
    base, tail = text:match("^(.-)%s+(%S+)$")
    if base and tail then
        local tailLower = tail:lower()
        if SPELL_MODES[tailLower] then
            mode = tailLower
            text = TrimText(base)
        end
    elseif SPELL_MODES[lower] then
        return "", lower, seconds
    end

    if mode == "event" then mode = "events" end
    if mode == "write" or mode == "writes" then mode = "events" end
    if mode == "desat" then mode = "trace" end

    return text, mode, seconds
end

local function RunCDMDebugSpell(msg)
    local target, mode, seconds = ParseSpellDebugRequest(msg)
    if mode == "help" then
        print("|cff34D399[CDM-Debug]|r spell usage:")
        print("  /cdmdebug spell <spellID|name>              -> one-shot resolver/API/icon report")
        print("  /cdmdebug spell <spellID|name> watch [sec]  -> timed GCD/swipe watch")
        print("  /cdmdebug spell <spellID|name> events [sec] -> event + write trace; default 0.25s throttle, 0 = raw")
        print("  /cdmdebug spell <itemID|name> aura [sec]    -> compact item-aura scanner/resolver watch")
        print("  /cdmdebug spell <spell name> trace          -> desaturation transition trace")
        print("  /cdmdebug spell <spell name> charge         -> charge-path report")
        print("  /cdmdebug spell <spell name> flicker        -> 5-second transition sampler")
        print("  /cdmdebug spell off                         -> stop spell traces/watchers")
        return
    end

    if mode == "off" then
        RunCDMDebugEvents("off")
        RunCDMDebugTrace("")
        CDMGCDStopWatch(false)
        CDMItemAuraStopWatch(false)
        StopWatchFrame("flicker")
        print("|cffffaa00[cdmflicker]|r sampler stopped.")
        return
    end

    if target == "" then
        RunCDMDebugSpell("")
        return
    end

    if mode == "events" then
        local targetID = FindDebugTargetID(target)
        if not targetID then
            print("|cffffaa00[cdmevents]|r no spellID found for '" .. tostring(target) .. "'")
            return
        end
        RunCDMDebugEvents(tostring(targetID), seconds)
    elseif mode == "trace" then
        RunCDMDebugTrace(FindDebugTargetName(target) or target)
    elseif mode == "charge" then
        RunCDMDebugCharge(target)
    elseif mode == "aura" or mode == "itemaura" then
        RunCDMDebugItemAura(target, seconds)
    elseif mode == "flicker" then
        RunCDMDebugFlicker(target)
    elseif mode == "watch" then
        local duration = tonumber(seconds) or 5
        RunCDMDebugGCD(target .. " " .. tostring(duration))
    else
        RunCDMDebugGCD(target .. " once")
    end
end

local function RunCDMDebugCache(msg)
    local sub = TrimText(msg):lower()
    if sub == "" then sub = "status" end

    local SD = ns.CDMSpellData
    local IC = ns.CDMIcons
    local BR = ns.CDMBars
    if not SD then
        print("|cffffaa00[CDM-Cache]|r CDM not loaded.")
        return
    end

    if sub == "status" then
        local s = SD.GetCacheStats and SD:GetCacheStats() or {}
        local ic = (IC and IC.GetCacheStats) and IC:GetCacheStats() or {}
        local br = (BR and BR.GetCacheStats) and BR:GetCacheStats() or {}
        local fr = ns.GetCDMFrameCacheStats and ns.GetCDMFrameCacheStats() or {}
        local rt = (ns.CDMRuntimeStore and ns.CDMRuntimeStore.GetStats)
            and ns.CDMRuntimeStore.GetStats() or {}
        local combat = InCombatLockdown() and "true" or "false"
        print(("|cff34D399[CDM-Cache]|r status (combat=%s)"):format(combat))
        if ns._cdmBootError then
            print(("  reanchor bootError:       %s"):format(tostring(ns._cdmBootError)))
        end
        print(("  hud_visibility frames:    dirty=%s size=%d"):format(
            tostring(fr.dirty), tonumber(fr.size) or 0))
        print(("  child map (spellID->child): dirty=%s size=%d"):format(
            tostring(s.childMapDirty), tonumber(s.childMapSize) or 0))
        print(("  captured aura index:      entries=%d units=%d spellKeys=%d nameKeys=%d"):format(
            tonumber(s.capturedAuraEntries) or 0,
            tonumber(s.capturedAuraUnits) or 0,
            tonumber(s.capturedAuraSpellKeys) or 0,
            tonumber(s.capturedAuraNameKeys) or 0))
        print(("  runtime store:            frame-owned (no central count) version=%d compat=%d"):format(
            tonumber(rt.version) or 0,
            tonumber(rt.compatState) or 0))
        print(("  learned cooldowns:        dirty=%s size=%d"):format(
            tostring(s.learnedDirty), tonumber(s.learnedSize) or 0))
        print(("  tick aura caches:         data=%d dur=%d exp=%d app=%d"):format(
            tonumber(s.tickAuraData) or 0,
            tonumber(s.tickAuraDuration) or 0,
            tonumber(s.tickAuraExpiration) or 0,
            tonumber(s.tickAuraApplication) or 0))
        print(("  resolve memos:            icon=%d auraActive=%d"):format(
            tonumber(s.resolveIconMemo) or 0,
            tonumber(s.resolveAuraMemo) or 0))
        print(("  totem slot map:           size=%d"):format(
            tonumber(s.totemSlotMap) or 0))
        print(("  texture cycle cache:      size=%d"):format(
            tonumber(ic.textureCycleCache) or 0))
        print(("  bar pool:                 active=%d"):format(
            tonumber(br.activeBars) or 0))
        print(("  icon update:              barsDirty=%s pending=%s"):format(
            tostring(ic.barsDirty), tostring(ic.updatePending)))
        if ic.iconEventProfileTop and #ic.iconEventProfileTop > 0 then
            print(("  icon events:              window=%.1fs"):format(
                tonumber(ic.iconEventProfileWindow) or 0))
            for _, row in ipairs(ic.iconEventProfileTop) do
                print(("    %-30s %6.2f ms/s  %5.0f/s"):format(
                    tostring(row.event),
                    tonumber(row.msPerSec) or 0,
                    tonumber(row.callsPerSec) or 0))
            end
        end
        print("  run |cFFFFFF00/cdmdebug cache reset|r to wipe and rebuild (OOC only).")
        return
    end

    if sub == "reset" then
        if InCombatLockdown() then
            print("|cffffaa00[CDM-Cache]|r reset blocked in combat; try again out of combat.")
            return
        end
        if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
        if SD.InvalidateLearnedCache then SD:InvalidateLearnedCache() end
        if SD.ClearChildCaches then SD:ClearChildCaches() end
        if IC and IC.ClearTextureCycleCache then IC:ClearTextureCycleCache() end
        if BR and BR.ClearPerBarCaches then BR:ClearPerBarCaches() end
        if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearAll then ns.CDMRuntimeStore.ClearAll() end
        if SD.CheckAllDormantSpells then SD:CheckAllDormantSpells() end
        if SD.ReconcileAllContainers then SD:ReconcileAllContainers() end
        if _G.QUI_OnSpellDataChanged then _G.QUI_OnSpellDataChanged() end
        if IC and IC.RequestFullUpdate then IC:RequestFullUpdate() end
        print("|cff34D399[CDM-Cache]|r reset complete; caches wiped and full rebuild scheduled.")
        return
    end

    print("|cffffaa00[CDM-Cache]|r usage: /cdmdebug cache [status|reset]")
end

local function RunCDMDebugProfile(msg)
    local sub = TrimText(msg):lower()
    if sub == "" or sub == "status" then
        RunCDMDebugProfiles()
    elseif sub == "clean" then
        RunCDMDebugClean()
    else
        print("|cffffaa00[CDM-Debug]|r profile usage: /cdmdebug profile [status|clean]")
    end
end

local function RunCDMDebugBuff()
    local P = "|cff34D399[CDM-Buff]|r"
    local boot = ns._cdmBoot
    if not boot or not boot.runtime then
        print(P .. " reanchor engine not booted (ns._cdmBoot nil) -- legacy owned-icon path active")
        return
    end
    local runtime = boot.runtime

    local function fmtv(v)
        if DebugIsSecretValue(v) then return "|cffff5555SECRET|r" end
        return tostring(v)
    end
    local function readCall(obj, method)
        local fn = obj and obj[method]
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, obj)
        if not ok then return "|cffff5555throw|r" end
        return fmtv(v)
    end

    local diag = runtime.GetLastDiag and runtime:GetLastDiag("buff")
    if not diag then
        print(P .. " lastPass: |cffffaa00none (no buff pass has run this session)|r")
    else
        local age = (GetTime and diag.at) and string.format("%.1fs", GetTime() - diag.at) or "?"
        print(string.format("%s lastPass: seq=%s age=%s early=%s mode=%s filterInactive=%s editing=%s auraProbe=%s",
            P, tostring(diag.seq), age, tostring(diag.earlyReturn), tostring(diag.displayMode),
            tostring(diag.filterInactive), tostring(diag.editing), tostring(diag.auraProbe)))
        print(string.format("%s   curated=%s matched=%s frameless=%s nativeClaimed=%s staleNative=%s hiddenPreview=%s fallbackLive=%s minted=%s mintFailed=%s planNil=%s positioned=%s",
            P, tostring(diag.curated), tostring(diag.matched), tostring(diag.frameless),
            tostring(diag.nativeClaimed), tostring(diag.staleNative), tostring(diag.hiddenPreview),
            tostring(diag.fallbackLive), tostring(diag.minted), tostring(diag.mintFailed),
            tostring(diag.planNil), tostring(diag.positioned)))
    end

    local viewer = _G.BuffIconCooldownViewer
    if not viewer then
        print(P .. " BuffIconCooldownViewer missing")
    else
        print(string.format("%s viewer: shown=%s visibleSetting=%s hideWhenInactive=%s",
            P, readCall(viewer, "IsShown"), fmtv(viewer.visibleSetting), fmtv(viewer.hideWhenInactive)))
        local pool = viewer.itemFramePool
        if pool and pool.EnumerateActive then
            local n = 0
            for item in pool:EnumerateActive() do
                n = n + 1
                local entry = runtime.GetEntryForFrame and runtime:GetEntryForFrame(item)
                local claimTag = "unclaimed"
                if entry then
                    local sid = entry.overrideSpellID or entry.spellID or entry.id
                    local name = Sources and Sources.QuerySpellName and Sources.QuerySpellName(sid)
                    claimTag = "CLAIMED:" .. tostring(name or sid)
                end
                print(string.format("%s   item %d: cooldownID=%s isActive=%s shown=%s alpha=%s %s",
                    P, n, readCall(item, "GetCooldownID"), readCall(item, "IsActive"),
                    readCall(item, "IsShown"), readCall(item, "GetAlpha"), claimTag))
            end
            print(string.format("%s BuffIcon items=%d", P, n))
        else
            print(P .. " BuffIcon item pool unavailable")
        end
    end

    local deps = runtime._deps or {}
    local okCurated, curated = pcall(deps.getCurated or function() end, "buff")
    if okCurated and type(curated) == "table" then
        for i = 1, #curated do
            local e = curated[i]
            local sid = e.overrideSpellID or e.spellID or e.id
            local name = Sources and Sources.QuerySpellName and Sources.QuerySpellName(sid)
            local auraLive = "n/a"
            if type(deps.entryAuraIsPresent) == "function" then
                local okA, live = pcall(deps.entryAuraIsPresent, e)
                auraLive = okA and fmtv(live) or "|cffff5555throw|r"
            end
            print(string.format("%s   curated %d: %s (%s) type=%s source=%s auraLive=%s",
                P, i, tostring(name or "?"), tostring(sid), tostring(e.type),
                tostring(e.source), auraLive))
        end
    else
        print(P .. " curated list unavailable")
    end
end

-- /cdmdebug edges: dump absolute frame/texture edges in PHYSICAL pixels.
-- GetLeft() etc. are in the region's own coordinate space; dividing by
-- QUICore:GetPixelSize(region) converts to physical pixels, so a border
-- renders crisp only when these values are (near-)integers.
local function RunCDMDebugEdges(rest)
    local P = "|cff34D399[CDM-Edges]|r"
    local core = ns.Addon or _G.QUI
    local Containers = ns.CDMContainers
    if not (core and core.GetPixelSize and Containers and Containers.GetContainer) then
        print(P .. " core/containers unavailable")
        return
    end

    local physW, physH = GetPhysicalScreenSize()
    local okScale, uiScale = ns.SafeCallMethod("best-effort-style", UIParent, "GetEffectiveScale")
    local scaleText = "?"
    if okScale and not DebugIsSecretValue(uiScale) and type(uiScale) == "number" then
        scaleText = string.format("%.5f", uiScale)
    end
    print(string.format("%s physical=%dx%d uiParentScale=%s", P, physW, physH, scaleText))

    local function safeEdges(region)
        local ok, l, r, t, b = pcall(function()
            return region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
        end)
        if not ok then return nil end
        if DebugIsSecretValue(l) or DebugIsSecretValue(r)
            or DebugIsSecretValue(t) or DebugIsSecretValue(b) then return nil end
        if not (l and r and t and b) then return nil end
        return l, r, t, b
    end

    local function fmtPx(v)
        local frac = v - math.floor(v + 0.5)
        if math.abs(frac) > 0.05 then
            return string.format("|cffffaa00%.2f|r", v)
        end
        return string.format("%.2f", v)
    end

    local function dumpRegion(indent, label, region)
        if not region then return end
        local l, r, t, b = safeEdges(region)
        if not l then
            print(string.format("%s%s %s: rect unavailable", P, indent, label))
            return
        end
        local px = core:GetPixelSize(region)
        print(string.format("%s%s %s: L=%s R=%s T=%s B=%s w=%.2f h=%.2f px=%.4f",
            P, indent, label, fmtPx(l / px), fmtPx(r / px), fmtPx(t / px), fmtPx(b / px),
            (r - l) / px, (t - b) / px, px))
    end

    -- GetRegions on protected live frames can return secret region refs
    -- (SecretAspect.Hierarchy); guard the call and each region before use.
    local function collectRegions(frame)
        return { frame:GetRegions() }
    end

    local function findChromeBorder(frame)
        if frame.Border then return frame.Border, "Border" end
        local fl = safeEdges(frame)
        if not fl then return nil end
        if not frame.GetRegions then return nil end
        local ok, regions = ns.SafeCall("best-effort-style", collectRegions, frame)
        if not ok or type(regions) ~= "table" then return nil end
        for i = 1, #regions do
            local reg = regions[i]
            if reg and not DebugIsSecretValue(reg)
                and reg.GetObjectType and reg:GetObjectType() == "Texture" then
                local l = safeEdges(reg)
                if l and l < fl - 0.001 then
                    return reg, "chromeBorder"
                end
            end
        end
    end

    local function dumpIcon(kind, i, icon)
        local shown = icon.IsShown and icon:IsShown()
        if not shown then return false end
        dumpRegion("  ", string.format("%s#%d", kind, i), icon)
        dumpRegion("    ", "Icon tex", icon.Icon)
        local border, borderLabel = findChromeBorder(icon)
        dumpRegion("    ", borderLabel or "border", border)
        return true
    end

    rest = TrimText(rest or "")
    local keys = (rest ~= "" and rest ~= "all") and { rest }
        or { "essential", "utility", "buff" }
    local boot = ns._cdmBoot
    local runtime = boot and boot.runtime

    for _, key in ipairs(keys) do
        local container = Containers.GetContainer(key)
        print(string.format("%s === %s ===", P, key))
        if not container then
            print(P .. "  container: nil")
        else
            dumpRegion("  ", "container", container)
            local cx, cy
            if container.GetCenter then
                local ok, x, y = pcall(container.GetCenter, container)
                if ok and not DebugIsSecretValue(x) and not DebugIsSecretValue(y)
                    and x and y then
                    cx, cy = x, y
                end
            end
            if cx then
                local px = core:GetPixelSize(container)
                print(string.format("%s   center: X=%s Y=%s", P, fmtPx(cx / px), fmtPx(cy / px)))
            end
            local shownCount = 0
            local pool = ns.CDMIconFactory and ns.CDMIconFactory.GetIconPool
                and ns.CDMIconFactory:GetIconPool(key) or {}
            for i = 1, #pool do
                if dumpIcon("owned", i, pool[i]) then shownCount = shownCount + 1 end
            end
            local live = runtime and runtime.GetReanchoredFrames
                and runtime:GetReanchoredFrames(key) or nil
            if type(live) == "table" then
                for i = 1, #live do
                    if dumpIcon("live", i, live[i]) then shownCount = shownCount + 1 end
                end
            end
            print(string.format("%s   shown icons: %d", P, shownCount))
        end
    end
end

local BORROW_VIEWER_GLOBALS = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buff      = "BuffIconCooldownViewer",
}

local borrowedNativeItem = nil

local function BorrowReleaseCurrent()
    local state = borrowedNativeItem
    borrowedNativeItem = nil
    if not state then return false end
    local item, pool = state.item, state.pool
    if item then
        ns.SafeCallMethodIfPresent("compat", item, "ClearCooldownID")
        ns.SafeCallMethodIfPresent("best-effort-style", item, "Hide")
    end
    if pool and pool.Release and item then
        ns.SafeCall("compat", pool.Release, pool, item)
    end
    return true
end

local function BorrowResolveCooldownID(spellID, containerKey)
    local Index = ns.CDMIndex
    if not Index then return nil end
    local rec
    if Index.GetOrderedForContainer then
        rec = Index.GetOrderedForContainer(containerKey, spellID)
    end
    if not rec and Index.GetOrdered then rec = Index.GetOrdered(spellID) end
    if not rec and Index.Get then rec = Index.Get(spellID) end
    return rec and rec.cooldownID or nil
end

local function BorrowReadable(fn, owner)
    if type(fn) ~= "function" then return "no-method" end
    local ok, value = pcall(fn, owner)
    if not ok then return "ERR" end
    if DebugIsSecretValue(value) then return "|cff34D399SECRET|r" end
    return tostring(value)
end

local function BorrowDescribeItem(P, label, item)
    if not item then
        print(string.format("%s %s: |cffffaa00absent|r", P, label))
        return
    end
    local cd = item.Cooldown
    if not cd and item.GetCooldownFrame then
        local okFrame, frame = ns.SafeCallMethod("compat", item, "GetCooldownFrame")
        if okFrame then cd = frame end
    end
    print(string.format("%s %s: cooldownID=%s active=%s shown=%s alpha=%s",
        P, label,
        BorrowReadable(item.GetCooldownID, item),
        BorrowReadable(item.IsActive, item),
        BorrowReadable(item.IsShown, item),
        BorrowReadable(item.GetAlpha, item)))
    print(string.format("%s   taint: cooldownID=%s cooldownInfo=%s isActive=%s",
        P,
        SecureFieldInfo(item, "cooldownID"),
        SecureFieldInfo(item, "cooldownInfo"),
        SecureFieldInfo(item, "isActive")))
    if cd then
        print(string.format("%s   cooldown: duration=%s drawSwipe=%s paused=%s",
            P,
            BorrowReadable(cd.GetCooldownDuration, cd),
            BorrowReadable(cd.GetDrawSwipe, cd),
            BorrowReadable(cd.IsPaused, cd)))
    else
        print(string.format("%s   cooldown: |cffffaa00no cooldown frame|r", P))
    end
end

local function BorrowFindNativeItem(cooldownID)
    for _, globalName in pairs(BORROW_VIEWER_GLOBALS) do
        local viewer = _G[globalName]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                local ok, id = pcall(item.GetCooldownID, item)
                if ok and not DebugIsSecretValue(id) and id == cooldownID then
                    return item
                end
            end
        end
    end
    return nil
end

local function BorrowReport(P)
    local state = borrowedNativeItem
    if not state then
        print(P .. " nothing borrowed. /cdmdebug borrow <spellID|name> [essential|utility|buff]")
        return
    end
    print(string.format("%s target spellID=%s cooldownID=%s viewer=%s combat=%s",
        P, tostring(state.spellID), tostring(state.cooldownID),
        state.containerKey, tostring(InCombatLockdown())))
    print(string.format("%s SetCooldownID: secure=%s raw=%s",
        P, tostring(state.secureResult), tostring(state.rawResult)))
    if state.setError then
        print(string.format("%s   last error: |cffff5555%s|r", P, tostring(state.setError)))
    end
    BorrowDescribeItem(P, "borrowed", state.item)
    local native = BorrowFindNativeItem(state.cooldownID)
    if native ~= state.item then
        BorrowDescribeItem(P, "native ref", native)
    end
    print(P .. " VERDICT: borrowed duration SECRET (or numeric > 0) = Blizzard is driving it.")
    print(P .. "          duration=0 and no error = SetCooldownID did not take.")
end

local function RunCDMDebugBorrow(msg)
    local P = "|cff34D399[CDM-Borrow]|r"
    local text = TrimText(msg)
    local sub = text:lower()

    if sub == "off" or sub == "release" then
        print(P .. (BorrowReleaseCurrent() and " released." or " nothing to release."))
        return
    end
    if sub == "" or sub == "report" then
        BorrowReport(P)
        return
    end

    local target, containerKey = text:match("^(.-)%s+(%a+)$")
    if not target or not BORROW_VIEWER_GLOBALS[containerKey:lower()] then
        target, containerKey = text, "utility"
    end
    containerKey = containerKey:lower()

    local spellID = FindDebugTargetID(target)
    if not spellID then
        print(P .. " no spellID found for '" .. tostring(target) .. "'")
        return
    end
    local cooldownID = BorrowResolveCooldownID(spellID, containerKey)
    if not cooldownID then
        print(P .. " no cooldownID in CDMIndex for spellID " .. tostring(spellID))
        return
    end

    local viewer = _G[BORROW_VIEWER_GLOBALS[containerKey]]
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.Acquire) then
        print(P .. " " .. containerKey .. " viewer has no itemFramePool")
        return
    end

    BorrowReleaseCurrent()

    local okAcquire, item = pcall(pool.Acquire, pool)
    if not okAcquire or not item then
        print(P .. " pool:Acquire failed: " .. tostring(item))
        return
    end

    ns.SafeCallMethodIfPresent("compat", viewer, "OnAcquireItemFrame", item)
    item.layoutIndex = nil
    ns.SafeCallMethodIfPresent("compat", item, "SetHideWhenInactive", false)
    ns.SafeCallMethodIfPresent("compat", item, "SetTimerShown", true)
    ns.SafeCallMethodIfPresent("compat", item, "SetIsEditing", false)

    local secureResult, rawResult, setError = "skipped", "skipped", nil
    if securecallfunction then
        local okSecure, err = pcall(securecallfunction, item.SetCooldownID, item, cooldownID, true)
        secureResult = okSecure and "ok" or "threw"
        if not okSecure then setError = err end
    end
    if secureResult ~= "ok" then
        local okRaw, err = pcall(item.SetCooldownID, item, cooldownID, true)
        rawResult = okRaw and "ok" or "threw"
        if not okRaw then setError = err end
    end

    ns.SafeCallMethodIfPresent("best-effort-style", item, "SetParent", UIParent)
    ns.SafeCallMethodIfPresent("best-effort-style", item, "ClearAllPoints")
    ns.SafeCallMethodIfPresent("best-effort-style", item, "SetPoint",
        "CENTER", UIParent, "CENTER", 0, -160)
    ns.SafeCallMethodIfPresent("best-effort-style", item, "SetScale", 2)
    ns.SafeCallMethodIfPresent("best-effort-style", item, "Show")

    borrowedNativeItem = {
        item = item,
        pool = pool,
        viewer = viewer,
        containerKey = containerKey,
        spellID = spellID,
        cooldownID = cooldownID,
        secureResult = secureResult,
        rawResult = rawResult,
        setError = setError,
    }

    print(P .. " parked at screen centre, 0,-160. Pull a dummy, then /cdmdebug borrow report")
    print(P .. " if the CooldownViewer error spam returns, /cdmdebug borrow off then /reload")
    BorrowReport(P)
end

local function PrintCDMDebugHelp()
    print("|cff34D399[CDM-Debug]|r commands:")
    print("  /cdmdebug status                         -> command help + flag state")
    print("  /cdmdebug flags [name] [on|off|filter]   -> debug flags")
    print("  /cdmdebug spell <target> [mode]           -> spell/icon case report")
    print("  /cdmdebug cache [status|reset]            -> cache status/reset")
    print("  /cdmdebug profile [status|clean]          -> CDM profile tools")
    print("  /cdmdebug probe                           -> resolver parity sweep")
    print("  /cdmdebug mint                            -> native mint/provider taint verdict")
    print("  /cdmdebug borrow <spell> [container]      -> borrow a spare native item frame; off|report")
    print("  /cdmdebug buff                            -> reanchor BuffIcon pipeline dump")
    print("  /cdmdebug edges [container]               -> icon/border edges in physical pixels")
    print("  direct flag shorthand: /cdmdebug icon on, /cdmdebug taint Sync, /cdmdebug off")
    ListDebugFlags()
end

local function RunCDMDebugCommand(msg)
    local text = TrimText(msg)
    if text == "" or text:lower() == "help" or text:lower() == "status" then
        PrintCDMDebugHelp()
        return
    end

    local cmd, rest = text:match("^(%S+)%s*(.-)$")
    local lower = cmd and cmd:lower() or ""
    if lower == "flags" then
        RunCDMDebugFlags(rest)
    elseif DEBUG_FLAGS[lower] or lower == "off" or lower == "clear" then
        RunCDMDebugFlags(text)
    elseif lower == "spell" then
        RunCDMDebugSpell(rest)
    elseif lower == "cache" then
        RunCDMDebugCache(rest)
    elseif lower == "profile" or lower == "profiles" then
        RunCDMDebugProfile(rest)
    elseif lower == "probe" then
        RunCDMDebugProbe()
    elseif lower == "mint" then
        RunCDMDebugMint()
    elseif lower == "borrow" then
        RunCDMDebugBorrow(rest)
    elseif lower == "buff" then
        RunCDMDebugBuff()
    elseif lower == "edges" then
        RunCDMDebugEdges(rest)
    else
        print("|cffffaa00[CDM-Debug]|r unknown command '" .. tostring(cmd) .. "'. Use /cdmdebug help.")
    end
end

SLASH_QUI_CDMDEBUG1 = "/cdmdebug"
SlashCmdList["QUI_CDMDEBUG"] = function(msg)
    RunCDMDebugCommand(msg)
end

local function BindAll()
    local mods = {
        ns.CDMIcons,
        ns.CDMIconFactory,
        ns.CDMBars,
        ns.CDMSpellData,
    }
    for _, mod in ipairs(mods) do
        if mod and mod._BindDebugImports then
            mod._BindDebugImports()
        end
    end
end

CDMIcons.ChargeDebug = CDMDebug.Charge

BindAll()
