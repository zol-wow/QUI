local ADDON_NAME, ns = ...

local MRB = ns.QUI_GroupFrameMissingRaidBuffs or {}
ns.QUI_GroupFrameMissingRaidBuffs = MRB

local type = type
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local wipe = wipe
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitIsPlayer = UnitIsPlayer
local UnitCanAssist = UnitCanAssist
local UnitInRange = UnitInRange
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local InCombatLockdown = InCombatLockdown
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local IsPlayerSpell = IsPlayerSpell
local IsSpellKnown = IsSpellKnown
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local AuraUtil = AuraUtil

local IsSecretValue = (ns.Helpers and ns.Helpers.IsSecretValue)
    or function(v) return issecretvalue and issecretvalue(v) or false end
local GetDB = ns.Helpers and ns.Helpers.CreateDBGetter and ns.Helpers.CreateDBGetter("quiGroupFrames")

local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local GetUnitAuraBySpellID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
local C_Secrets = C_Secrets
local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex

local _allyBuffIDs = nil

local RAID_BUFFS = {
    { key = "intellect", ids = { 1459, 432778 }, label = "Arcane Intellect", providerClass = "MAGE", iconSpellID = 1459 },
    { key = "stamina", ids = { 21562 }, label = "Power Word: Fortitude", providerClass = "PRIEST", iconSpellID = 21562 },
    { key = "attackPower", ids = { 6673 }, label = "Battle Shout", providerClass = "WARRIOR", iconSpellID = 6673 },
    { key = "versatility", ids = { 1126, 432661 }, label = "Mark of the Wild", providerClass = "DRUID", iconSpellID = 1126 },
    { key = "skyfury", ids = { 462854 }, label = "Skyfury", providerClass = "SHAMAN", iconSpellID = 462854 },
    {
        key = "bronze",
        ids = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 },
        label = "Blessing of the Bronze",
        providerClass = "EVOKER",
        iconSpellID = 381748,
    },
}

local CLASS_TO_BUFF_KEY = {
    MAGE = "intellect",
    PRIEST = "stamina",
    WARRIOR = "attackPower",
    DRUID = "versatility",
    SHAMAN = "skyfury",
    EVOKER = "bronze",
}

local NON_SECRET_RAID_BUFF_IDS = {
    [1126] = true, [432661] = true, [1459] = true, [432778] = true,
    [21562] = true, [6673] = true, [462854] = true,
    [381732] = true, [381741] = true, [381746] = true, [381748] = true,
    [381749] = true, [381750] = true, [381751] = true, [381752] = true,
    [381753] = true, [381754] = true, [381756] = true, [381757] = true,
    [381758] = true,
    [53563] = true, [156910] = true, [156322] = true, [1244893] = true,
    [974] = true, [383648] = true,
    [369459] = true,
}

MRB.RaidBuffs = RAID_BUFFS
MRB.ClassToBuffKey = CLASS_TO_BUFF_KEY
MRB.NonSecretRaidBuffIDs = NON_SECRET_RAID_BUFF_IDS

local iconCache = {}
local nameCache = {}
local syntheticAuraCache = {}
local singleID = {}
local preCombatSnapshot = {}
local snapshotBuffIDs = {}
local activePredicates = {}
local _groupUnitsScratch = {}
local snapshotEventFrame
local rangeListenerFrames
local refreshQueued = false

local function RegisterSnapshotIDs(spellIDOrTable)
    if type(spellIDOrTable) == "table" then
        for i = 1, #spellIDOrTable do
            snapshotBuffIDs[spellIDOrTable[i]] = true
        end
    elseif spellIDOrTable then
        snapshotBuffIDs[spellIDOrTable] = true
    end
end

for i = 1, #RAID_BUFFS do
    RegisterSnapshotIDs(RAID_BUFFS[i].ids)
end

function MRB:RegisterSnapshotBuffIDs(spellIDOrTable)
    RegisterSnapshotIDs(spellIDOrTable)
end

function MRB:RegisterActivePredicate(predicate)
    if type(predicate) == "function" then
        activePredicates[#activePredicates + 1] = predicate
    end
end

local function BuildCDMGroupBuffEntries(out)
    local CV = _G.C_CooldownViewer
    if not (CV and CV.GetGroupBuffItems) then return end
    local okItems, items = pcall(CV.GetGroupBuffItems)
    if not okItems or type(items) ~= "table" then return end

    local hidden = {}
    local layoutListRead = false
    local CVS = _G.CooldownViewerSettings
    local layoutGetter = _G.CooldownManagerLayout_GetHiddenGroupBuffs
    local layoutMode = _G.Enum and _G.Enum.CDMLayoutMode and _G.Enum.CDMLayoutMode.AccessOnly
    if CVS and type(layoutGetter) == "function" and layoutMode ~= nil then
        local okLayout, list = pcall(function()
            local lm = CVS:GetLayoutManager()
            local layout = lm and lm:GetActiveLayout(layoutMode)
            return layout and layoutGetter(layout) or nil
        end)
        if okLayout and type(list) == "table" then
            layoutListRead = true
            for _, sid in ipairs(list) do hidden[sid] = true end
        end
    end
    if not layoutListRead then
        local UA = _G.C_UnitAuras
        if UA and UA.GetHiddenGroupBuffs then
            local okHidden, hiddenIDs = pcall(UA.GetHiddenGroupBuffs)
            if okHidden and type(hiddenIDs) == "table" then
                for _, sid in ipairs(hiddenIDs) do hidden[sid] = true end
            end
        end
    end

    local builtinIDs = {}
    for i = 1, #out do
        local ids = out[i].ids
        if type(ids) == "table" then
            for j = 1, #ids do builtinIDs[ids[j]] = true end
        end
    end

    local hideByDefault = _G.Enum and _G.Enum.GroupBuffItemFlags
        and _G.Enum.GroupBuffItemFlags.HideByDefault or 1
    local band = bit and bit.band

    local seen = {}
    for _, item in ipairs(items) do
        local sid = item.spellID
        local flaggedHidden = not layoutListRead
            and type(item.flags) == "number" and band
            and band(item.flags, hideByDefault) ~= 0
        if type(sid) == "number" and not IsSecretValue(sid)
            and item.isKnown ~= false
            and not flaggedHidden
            and not hidden[sid] and not builtinIDs[sid] and not seen[sid] then
            seen[sid] = true
            out[#out + 1] = {
                key = "cdm:" .. sid,
                ids = { sid },
                label = (type(item.name) == "string" and item.name) or ("Spell " .. sid),
                providerClass = nil,
                iconSpellID = sid,
                source = "cdm",
            }
        end
    end
end

function MRB:RebuildRaidBuffs()
    for i = #RAID_BUFFS, 1, -1 do
        if RAID_BUFFS[i].source == "cdm" then
            table.remove(RAID_BUFFS, i)
        end
    end
    BuildCDMGroupBuffEntries(RAID_BUFFS)
    for i = 1, #RAID_BUFFS do
        RegisterSnapshotIDs(RAID_BUFFS[i].ids)
    end
end

MRB:RebuildRaidBuffs()

local function SafeBoolean(fn, unit, fallback)
    if not fn then return fallback end
    local ok, value = pcall(fn, unit)
    if not ok or IsSecretValue(value) then
        return fallback
    end
    return value
end

function MRB._isPlayerUnitProbe(unit)
    if unit == "player" then return true end
    if not UnitIsUnit then return false end
    local ok, result = pcall(UnitIsUnit, unit, "player")
    if not ok then return false end
    if IsSecretValue(result) then return false end -- @secret-policy: reject-secret-ids
    return result == true
end

local function ContextHasMissingRaidBuffElement(contextDB)
    local auras = contextDB and contextDB.auras
    if not auras or auras.enabled == false or type(auras.elements) ~= "table" then
        return false
    end
    for key, bucket in pairs(auras.elements) do
        if (key == "*" or type(key) == "number") and type(bucket) == "table" then
            for _, element in ipairs(bucket) do
                if type(element) == "table"
                    and element.mode == "missingRaidBuff"
                    and element.enabled ~= false
                then
                    return true
                end
            end
        end
    end
    return false
end

function MRB:HasActiveElements()
    local db = GetDB and GetDB()
    if db and (ContextHasMissingRaidBuffElement(db.party)
        or ContextHasMissingRaidBuffElement(db.raid))
    then
        return true
    end
    for i = 1, #activePredicates do
        local ok, active = ns.SafeCall("bulkhead", activePredicates[i])
        if ok and active then
            return true
        end
    end
    return false
end

local function GetPlayerClass()
    local ok, _, classFile = pcall(UnitClass, "player")
    if ok and type(classFile) == "string" then
        return classFile
    end
    return nil
end

local function GetBuffName(buff)
    local cached = nameCache[buff.key]
    if cached then return cached end

    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, resolved = pcall(C_Spell.GetSpellName, buff.iconSpellID or buff.ids[1])
        if ok and type(resolved) == "string" and resolved ~= "" then
            name = resolved
        end
    end
    if not name and GetSpellInfo then
        local ok, resolved = pcall(GetSpellInfo, buff.iconSpellID or buff.ids[1])
        if ok and type(resolved) == "string" and resolved ~= "" then
            name = resolved
        end
    end
    name = name or buff.label
    nameCache[buff.key] = name
    return name
end

local function GetBuffIcon(buff)
    local spellID = buff.iconSpellID or buff.ids[1]
    local cached = iconCache[spellID]
    if cached then return cached end

    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, resolved = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and resolved then icon = resolved end
    elseif GetSpellTexture then
        local ok, resolved = pcall(GetSpellTexture, spellID)
        if ok and resolved then icon = resolved end
    end
    icon = icon or 134400
    iconCache[spellID] = icon
    return icon
end

local function GetSyntheticAura(buff)
    local aura = syntheticAuraCache[buff.key]
    if aura then return aura end

    aura = {
        auraInstanceID = "QUI_MissingRaidBuff_" .. buff.key,
        spellId = buff.iconSpellID or buff.ids[1],
        name = GetBuffName(buff),
        icon = GetBuffIcon(buff),
        duration = 0,
        expirationTime = 0,
        isHelpful = true,
        isHarmful = false,
    }
    syntheticAuraCache[buff.key] = aura
    return aura
end

local function SafeAuraField(auraData, field)
    if IsSecretValue(auraData) then return nil end -- @secret-policy: reject-secret-value
    if not auraData then return nil end
    local ok, value = pcall(function() return auraData[field] end)
    if not ok or IsSecretValue(value) then return nil end
    return value
end

local function NormalizeIDs(spellIDOrTable)
    if type(spellIDOrTable) == "table" then
        return spellIDOrTable
    end
    wipe(singleID)
    singleID[1] = spellIDOrTable
    return singleID
end

local function DirectAuraLookup(unit, spellID)
    if unit == "player" and GetPlayerAuraBySpellID then
        local ok, aura = pcall(GetPlayerAuraBySpellID, spellID)
        if ok and aura then return aura end
    elseif GetUnitAuraBySpellID then
        local ok, aura = pcall(GetUnitAuraBySpellID, unit, spellID)
        if ok and aura then return aura end
    end
    return nil
end

function MRB:UnitHasBuff(unit, spellIDOrTable, spellName)
    if not unit or not UnitExists(unit) then return false end

    local spellIDs = NormalizeIDs(spellIDOrTable)
    local allWhitelisted = true
    for i = 1, #spellIDs do
        local id = spellIDs[i]
        if NON_SECRET_RAID_BUFF_IDS[id] then
            if DirectAuraLookup(unit, id) then
                return true
            end
        else
            allWhitelisted = false
        end
    end
    if allWhitelisted then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        local unitSnap = preCombatSnapshot[unit]
        if unitSnap then
            local snapshotAuthoritative = true
            for i = 1, #spellIDs do
                local id = spellIDs[i]
                if unitSnap[id] then
                    return true
                end
                if not snapshotBuffIDs[id] then
                    snapshotAuthoritative = false
                end
            end
            if snapshotAuthoritative then
                return false
            end
        end
    end

    local unknown = false

    if spellName and AuraUtil and AuraUtil.FindAuraByName then
        local ok, aura = pcall(AuraUtil.FindAuraByName, spellName, unit, "HELPFUL")
        if ok then
            if IsSecretValue(aura) then
                -- @secret-policy: readable-only-scan — unidentifiable; fall
                aura = nil
                unknown = true
            end
            if aura then
                return true
            end
        else
            unknown = true
        end
    end

    if GetAuraDataByIndex and not AurasAreSecret() then
        local index = 0
        while true do
            index = index + 1
            local ok, auraData = pcall(GetAuraDataByIndex, unit, index, "HELPFUL")
            if not ok then unknown = true; break end
            if IsSecretValue(auraData) then
                -- @secret-policy: readable-only-scan
                unknown = true
            elseif not auraData then
                break
            else
                local auraSpellID = SafeAuraField(auraData, "spellId")
                if auraSpellID then
                    for i = 1, #spellIDs do
                        if auraSpellID == spellIDs[i] then
                            return true
                        end
                    end
                end
            end
        end
    elseif GetAuraDataByIndex and AurasAreSecret() then
        unknown = true
    end

    if unknown then return nil end
    return false
end

function MRB._auraProbe(unit, id)
    return DirectAuraLookup(unit, id)
end

function MRB:UnitHasMyBuff(unit, ids)
    if not unit or not SafeBoolean(UnitExists, unit, false) then return false end
    for i = 1, #ids do
        local id = ids[i]
        if NON_SECRET_RAID_BUFF_IDS[id] then
            local aura = MRB._auraProbe(unit, id)
            if aura and SafeAuraField(aura, "isFromPlayerOrPlayerPet") == true then
                return true
            end
        end
    end
    local unknown = false
    if GetAuraDataByIndex and not AurasAreSecret() then
        local index = 0
        while true do
            index = index + 1
            local ok, auraData = pcall(GetAuraDataByIndex, unit, index, "HELPFUL|PLAYER")
            if not ok then unknown = true; break end
            if IsSecretValue(auraData) then
                -- @secret-policy: readable-only-scan
                unknown = true
            elseif not auraData then
                break
            else
                local sid = SafeAuraField(auraData, "spellId")
                if sid then
                    for i = 1, #ids do
                        if sid == ids[i] then return true end
                    end
                end
            end
        end
    elseif GetAuraDataByIndex and AurasAreSecret() then
        unknown = true
    end
    if unknown then return nil end
    return false
end

local function UnitInKnownRange(unit)
    if unit == "player" then return true end
    if UnitInRange then
        local ok, inRange, checked = pcall(UnitInRange, unit)
        if ok then
            if IsSecretValue(inRange) or IsSecretValue(checked) then
            elseif checked and inRange == false then
                return false
            end
        end
    end
    return true
end

local function UnitEligible(unit)
    if not unit or not SafeBoolean(UnitExists, unit, false) then return false end
    if SafeBoolean(UnitIsDeadOrGhost, unit, true) then return false end
    if SafeBoolean(UnitIsConnected, unit, false) == false then return false end
    if SafeBoolean(UnitIsPlayer, unit, false) == false then return false end
    if UnitCanAssist then
        local ok, canAssist = pcall(UnitCanAssist, "player", unit)
        if not ok or IsSecretValue(canAssist) or not canAssist then return false end
    end
    if not UnitInKnownRange(unit) then return false end
    return true
end

function MRB._eligibleProbe(unit) return UnitEligible(unit) end

function MRB._specProbe()
    if not GetSpecialization then return nil end
    local idx = GetSpecialization()
    if not idx then return nil end
    local specID = GetSpecializationInfo and GetSpecializationInfo(idx) or nil
    return specID
end

function MRB._groupUnitsProbe()
    wipe(_groupUnitsScratch)
    _groupUnitsScratch[1] = "player"
    if IsInRaid and IsInRaid() then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do _groupUnitsScratch[#_groupUnitsScratch + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n - 1 do _groupUnitsScratch[#_groupUnitsScratch + 1] = "party" .. i end
    end
    return _groupUnitsScratch
end

function MRB._spellKnownProbe(buffOrID)
    local haveCSpellBook = C_SpellBook and C_SpellBook.IsSpellKnown
    if not haveCSpellBook and not IsPlayerSpell and not IsSpellKnown then
        return true
    end
    local ids, icon
    if type(buffOrID) == "table" then
        ids = buffOrID.ids
        icon = buffOrID.iconSpellID
    else
        ids = { buffOrID }
    end
    local function tryID(id)
        if haveCSpellBook then
            local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
            if ok and v == true then return true end
        end
        if IsPlayerSpell then
            local ok, v = pcall(IsPlayerSpell, id)
            if ok and v == true then return true end
        end
        if IsSpellKnown then
            local ok, v = pcall(IsSpellKnown, id)
            if ok and v == true then return true end
        end
        return false
    end
    if icon and tryID(icon) then return true end
    if ids then
        for i = 1, #ids do
            if tryID(ids[i]) then return true end
        end
    end
    return false
end

function MRB:PlayerIsProviderSpec(buff)
    local specs = buff and buff.providerSpecIDs
    if type(specs) ~= "table" then return false end
    local cur = MRB._specProbe()
    return cur ~= nil and specs[cur] == true
end

function MRB:AnyEligibleAllyHasMyBuff(ids)
    local units = MRB._groupUnitsProbe()
    local sawUnknown = false
    for i = 1, #units do
        local unit = units[i]
        if MRB._eligibleProbe(unit) then
            local has = MRB:UnitHasMyBuff(unit, ids)
            if has == true then
                return true
            elseif has == nil then
                sawUnknown = true
            end
        end
    end
    if sawUnknown then return nil end
    return false
end

local function ElementShouldCheckBuff(element, buff)
    if element.classDetection ~= false then
        return CLASS_TO_BUFF_KEY[GetPlayerClass() or ""] == buff.key
            or buff.providerClass == nil
    end
    local checks = element.buffChecks
    if type(checks) ~= "table" then
        return true
    end
    return checks[buff.key] == true
end
MRB.ElementShouldCheckBuff = ElementShouldCheckBuff

function MRB:BuildMatches(unit, element, out)
    out = out or {}
    wipe(out)
    if not UnitEligible(unit) then return out end

    local maxIcons = tonumber(element and element.maxIcons) or 1
    if maxIcons <= 0 then maxIcons = #RAID_BUFFS end

    if MRB._isPlayerUnitProbe(unit) then
        local ally = ns.QUI_AllyBuffs
        if ally then
            for i = 1, #ally do
                local buff = ally[i]
                if MRB:PlayerIsProviderSpec(buff)
                    and MRB._spellKnownProbe(buff)
                    and MRB:AnyEligibleAllyHasMyBuff(buff.ids) == false
                then
                    out[#out + 1] = GetSyntheticAura(buff)
                end
            end
        end
    end

    for i = 1, #RAID_BUFFS do
        if #out >= maxIcons then break end
        local buff = RAID_BUFFS[i]
        if ElementShouldCheckBuff(element or {}, buff) then
            local name = GetBuffName(buff)
            if self:UnitHasBuff(unit, buff.ids, name) == false then
                out[#out + 1] = GetSyntheticAura(buff)
            end
        end
    end

    return out
end

function MRB:SnapshotRaidBuffAuras()
    if not self:HasActiveElements() then return end
    wipe(preCombatSnapshot)

    local function SnapshotUnit(unit)
        if unit and SafeBoolean(UnitExists, unit, false) and not preCombatSnapshot[unit] then
            local snap = {}
            for id in pairs(snapshotBuffIDs) do
                if DirectAuraLookup(unit, id) then
                    snap[id] = true
                end
            end
            preCombatSnapshot[unit] = snap
        end
    end

    SnapshotUnit("player")

    if IsInRaid and IsInRaid() then
        local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, count do
            SnapshotUnit("raid" .. i)
        end
    elseif IsInGroup and IsInGroup() then
        local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, count - 1 do
            SnapshotUnit("party" .. i)
        end
    end

    local GF = ns.QUI_GroupFrames
    if GF and GF.unitFrameMap then
        for unit in pairs(GF.unitFrameMap) do
            SnapshotUnit(unit)
        end
    end
end

function MRB:ClearPreCombatSnapshot()
    wipe(preCombatSnapshot)
end

local function RefreshUnit(unit)
    if not MRB:HasActiveElements() then return end
    local pf = ns.QUI_PerfFlags
    if pf and pf.disabled and pf.disabled.missingbuffs then return end
    local GF = ns.QUI_GroupFrames
    local GFA = ns.QUI_GroupFrameAuras
    local frames = GF and GF.unitFrameMap and GF.unitFrameMap[unit]
    if not frames or not GFA or not GFA.RenderFrame then return end
    for i = 1, #frames do
        local frame = frames[i]
        if frame and frame:IsShown() then
            GFA:RenderFrame(frame)
        end
    end
end

local function RefreshAll()
    if not MRB:HasActiveElements() then return end
    local pf = ns.QUI_PerfFlags
    if pf and pf.disabled and pf.disabled.missingbuffs then return end
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        local GFA = ns.QUI_GroupFrameAuras
        if GFA and GFA.RefreshAll then
            GFA:RefreshAll()
        end
    end)
end

function MRB.MakeDeltaRelevanceTracker(getIDSet, nilSpellIsRelevant)
    local instances = {}
    return function(unit, updateInfo)
        if not updateInfo or updateInfo.isFullUpdate then
            instances[unit] = nil
            return true
        end

        local idSet = getIDSet()
        if not idSet then return true end

        local relevant = false
        local set = instances[unit]

        local added = updateInfo.addedAuras
        if added then
            for i = 1, #added do
                local ad = added[i]
                local sid = ad.spellId
                if IsSecretValue(sid) then
                    relevant = true
                elseif sid == nil then
                    if nilSpellIsRelevant then relevant = true end
                elseif idSet[sid] then
                    relevant = true
                    local iid = ad.auraInstanceID
                    if iid and not IsSecretValue(iid) then
                        set = set or {}
                        instances[unit] = set
                        set[iid] = true
                    end
                end
            end
        end

        if set then
            local removed = updateInfo.removedAuraInstanceIDs
            if removed then
                for i = 1, #removed do
                    local iid = removed[i]
                    if set[iid] then relevant = true; set[iid] = nil end
                end
            end
            local updated = updateInfo.updatedAuraInstanceIDs
            if updated then
                for i = 1, #updated do
                    if set[updated[i]] then relevant = true; break end
                end
            end
        end

        return relevant
    end
end

local AllyDeltaIsRelevant = MRB.MakeDeltaRelevanceTracker(function()
    if _allyBuffIDs then return _allyBuffIDs end
    local ally = ns.QUI_AllyBuffs
    if not ally then return nil end
    _allyBuffIDs = {}
    for i = 1, #ally do
        for _, id in ipairs(ally[i].ids) do
            _allyBuffIDs[id] = true
        end
    end
    return _allyBuffIDs
end, true)
MRB._allyDeltaIsRelevant = AllyDeltaIsRelevant

local function EnsureEventFrame()
    if snapshotEventFrame then return end
    snapshotEventFrame = CreateFrame("Frame")
    snapshotEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    snapshotEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    snapshotEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    snapshotEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    snapshotEventFrame:RegisterEvent("SPELLS_CHANGED")
    snapshotEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    snapshotEventFrame:RegisterEvent("UNIT_CONNECTION")
    snapshotEventFrame:RegisterEvent("UNIT_FLAGS")
    do
        local tokens = { "player" }
        for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
        for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
        rangeListenerFrames = {}
        for i = 1, #tokens do
            local token = tokens[i]
            local listener = CreateFrame("Frame")
            listener:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", token)
            listener:SetScript("OnEvent", function()
                RefreshUnit(token)
            end)
            rangeListenerFrames[i] = listener
        end
    end
    snapshotEventFrame:RegisterEvent("ENCOUNTER_START")
    snapshotEventFrame:RegisterEvent("CHALLENGE_MODE_START")
    pcall(function() snapshotEventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED") end)
    pcall(function() snapshotEventFrame:RegisterEvent("HIDDEN_GROUP_BUFFS_CHANGED") end)
    pcall(function() snapshotEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED") end)
    snapshotEventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            MRB:SnapshotRaidBuffAuras()
            RefreshAll()
        elseif event == "PLAYER_REGEN_ENABLED" then
            MRB:ClearPreCombatSnapshot()
            RefreshAll()
        elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
            RefreshUnit(unit)
        elseif event == "GROUP_ROSTER_UPDATE" then
            C_Timer.After(0.25, RefreshAll)
        elseif event == "COOLDOWN_VIEWER_DATA_LOADED"
            or event == "HIDDEN_GROUP_BUFFS_CHANGED"
            or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            MRB:RebuildRaidBuffs()
            RefreshAll()
        else
            RefreshAll()
        end
    end)
end

EnsureEventFrame()

if ns.AuraEvents then
    ns.AuraEvents:Subscribe("roster", function(unit, updateInfo)
        if not MRB:HasActiveElements() then return end
        local ally = ns.QUI_AllyBuffs
        if not ally then return end
        local isProvider = false
        for i = 1, #ally do
            if MRB:PlayerIsProviderSpec(ally[i]) then
                isProvider = true
                break
            end
        end
        if not isProvider then return end
        if not AllyDeltaIsRelevant(unit, updateInfo) then return end
        local GF = ns.QUI_GroupFrames
        if GF and GF.unitFrameMap then
            for playerUnit in pairs(GF.unitFrameMap) do
                if MRB._isPlayerUnitProbe(playerUnit) then
                    RefreshUnit(playerUnit)
                    break
                end
            end
        end
    end)
end

return MRB
