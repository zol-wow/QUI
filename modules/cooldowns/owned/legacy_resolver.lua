----------------------------------------------------------------------------
-- LegacyTrackerResolver
--
-- Recovers customBar entries whose entry.id stores a spellbook slot index
-- instead of a spell ID — the result of a pre-V2 drag-drop handler that
-- read GetCursorInfo()'s 2nd return verbatim. Post-DF, that return is the
-- spellbook slot index, not the spellID. Profiles authored under that
-- handler ship with bar entries that GetSpellTexture/GetSpellInfo can't
-- resolve, surfacing as "?" or wrong icons.
--
-- Resolution requires the player's live spellbook, so it can't run as a
-- migration. Migration v35 only stamps _sourceSpecID on spec-specific
-- containers; this module hooks PLAYER_LOGIN / PLAYER_SPECIALIZATION_CHANGED
-- and walks tagged containers when the player is on the matching spec.
--
-- Recovery is propose-only — proposals are stashed in a runtime cache
-- (not written to db) until the user accepts via /qui legacyrecover.
-- That keeps an unambiguous mismatch (e.g. wrong-spec slot 174 happening
-- to land on a different real spell) from silently corrupting data.
----------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

local LegacyResolver = {}
ns.LegacyResolver = LegacyResolver

local _proposalsByContainer = {}
local _resolverFrame
local _pendingPostCombat = false
local FindLegacyBar
local NotifyRefresh

local SPEC_ID_CLASS_TOKEN = {
    [62] = "MAGE", [63] = "MAGE", [64] = "MAGE",
    [65] = "PALADIN", [66] = "PALADIN", [70] = "PALADIN",
    [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR",
    [102] = "DRUID", [103] = "DRUID", [104] = "DRUID", [105] = "DRUID",
    [250] = "DEATHKNIGHT", [251] = "DEATHKNIGHT", [252] = "DEATHKNIGHT",
    [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [256] = "PRIEST", [257] = "PRIEST", [258] = "PRIEST",
    [259] = "ROGUE", [260] = "ROGUE", [261] = "ROGUE",
    [262] = "SHAMAN", [263] = "SHAMAN", [264] = "SHAMAN",
    [265] = "WARLOCK", [266] = "WARLOCK", [267] = "WARLOCK",
    [268] = "MONK", [269] = "MONK", [270] = "MONK",
    [577] = "DEMONHUNTER", [581] = "DEMONHUNTER",
    [1467] = "EVOKER", [1468] = "EVOKER", [1473] = "EVOKER",
}

local function GetCurrentSpecID()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local idx = GetSpecialization()
    if not idx then return nil end
    local id = GetSpecializationInfo(idx)
    return type(id) == "number" and id or nil
end

local function GetSpecClassToken(specID)
    if not specID then return nil end
    if GetSpecializationInfoByID then
        local ok, id, name, description, icon, role, classToken = pcall(GetSpecializationInfoByID, specID)
        if ok and classToken then return classToken end
    end
    return SPEC_ID_CLASS_TOKEN[specID]
end

local function GetSpecKeyCandidates(specID, preferredKey)
    local keys, seen = {}, {}
    local function push(key)
        if key == nil then return end
        key = tostring(key)
        if key ~= "" and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end

    push(preferredKey)
    local classToken = GetSpecClassToken(specID) or SPEC_ID_CLASS_TOKEN[specID]
    if classToken and specID then
        push(classToken .. "-" .. tostring(specID))
    end
    push(specID)
    return keys
end

local function IsCastableForPlayer(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return false end
    if not C_Spell or not C_Spell.GetSpellInfo then return false end
    local info = C_Spell.GetSpellInfo(spellID)
    if not info or not info.name then return false, nil end
    if not IsPlayerSpell or not IsPlayerSpell(spellID) then
        return false, info
    end
    return true, info
end

local function ProbeEntry(entry)
    if type(entry) ~= "table" or entry.type ~= "spell" then return nil end
    local id = entry.id
    if type(id) ~= "number" or id <= 0 then return nil end

    local candidates = {}
    local seen = {}

    local function pushCandidate(source, spellID, info)
        if not spellID or seen[spellID] then return end
        seen[spellID] = true
        candidates[#candidates + 1] = {
            source  = source,
            spellID = spellID,
            name    = info and info.name or tostring(spellID),
            iconID  = info and info.iconID,
        }
    end

    do
        local castable, info = IsCastableForPlayer(id)
        if castable and info and not info.isPassive then
            pushCandidate("as-is", id, info)
        end
    end

    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
        local ok, book = pcall(C_SpellBook.GetSpellBookItemInfo, id, Enum.SpellBookSpellBank.Player)
        if ok and book and book.spellID and not book.isPassive then
            local sid = book.spellID
            if C_Spell and C_Spell.GetOverrideSpell then
                local override = C_Spell.GetOverrideSpell(sid)
                if override and override ~= 0 then sid = override end
            end
            local castable, info = IsCastableForPlayer(sid)
            if castable then
                pushCandidate("slot", sid, info)
            end
        end
    end

    if #candidates == 0 then
        return { state = "no-match", originalID = id }
    end

    if #candidates == 1 then
        return { state = "proposed", originalID = id, target = candidates[1] }
    end

    for _, c in ipairs(candidates) do
        if c.source == "as-is" then
            return { state = "proposed", originalID = id, target = c }
        end
    end
    return { state = "ambiguous", originalID = id, candidates = candidates }
end

-- Resolve the per-spec list path: db.global.ncdm.specTrackerSpells[containerKey][specKey].
-- After migration v35, this is the canonical storage for spec-specific bar entries.
-- Returns the list (may be nil) and the key that was used.
local function GetPerSpecList(containerKey, specID, createIfMissing, preferredKey)
    local db = QUICore and QUICore.db
    if not db or type(db.global) ~= "table" then return nil end
    local global = db.global
    if type(global.ncdm) ~= "table" then
        if not createIfMissing then return nil end
        global.ncdm = {}
    end
    if type(global.ncdm.specTrackerSpells) ~= "table" then
        if not createIfMissing then return nil end
        global.ncdm.specTrackerSpells = {}
    end
    local byContainer = global.ncdm.specTrackerSpells[containerKey]
    if type(byContainer) ~= "table" then
        if not createIfMissing then return nil end
        byContainer = {}
        global.ncdm.specTrackerSpells[containerKey] = byContainer
    end

    local keys = GetSpecKeyCandidates(specID, preferredKey)
    for _, specKey in ipairs(keys) do
        local list = byContainer[specKey]
        if type(list) == "table" then
            return list, specKey
        end
    end

    local specKey = keys[1] or tostring(specID)
    if type(byContainer[specKey]) ~= "table" then
        if not createIfMissing then return nil end
        byContainer[specKey] = {}
    end
    return byContainer[specKey], specKey
end

local function GetEntryListForContainer(containerKey, container, createIfMissing, preferredKey, specID)
    if type(container) ~= "table" then return nil end
    local requestedSpecID = type(specID) == "number" and specID or container._sourceSpecID
    if container.specSpecific == true or container.specSpecificSpells == true then
        local list, specKey = GetPerSpecList(containerKey, requestedSpecID, createIfMissing, preferredKey)
        if type(list) == "table" then
            return list, "spec", specKey
        end
    end
    if type(container.entries) == "table" then
        return container.entries, "container", nil
    end
    return nil
end

local function DeduplicateEntryList(entries)
    if type(entries) ~= "table" then return false, 0 end
    local seen = {}
    local kept = {}
    local removed = 0
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local key = tostring(entry.type or "") .. "\031"
                .. tostring(entry.id or "") .. "\031"
                .. tostring(entry.macroName or "") .. "\031"
                .. tostring(entry.customName or "")
            if not seen[key] then
                seen[key] = true
                kept[#kept + 1] = entry
            else
                removed = removed + 1
            end
        else
            kept[#kept + 1] = entry
        end
    end
    if removed > 0 then
        for i = 1, math.max(#entries, #kept) do
            entries[i] = kept[i]
        end
        return true, removed
    end
    return false, 0
end

local function MergeEntryLists(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for _, entry in ipairs(src) do
        if type(entry) == "table" then
            local exists = false
            for _, existing in ipairs(dst) do
                if type(existing) == "table"
                   and existing.type == entry.type
                   and existing.id == entry.id
                   and existing.macroName == entry.macroName
                   and existing.customName == entry.customName
                then
                    exists = true
                    break
                end
            end
            if not exists then
                dst[#dst + 1] = entry
                changed = true
            end
        end
    end
    if DeduplicateEntryList(dst) then
        changed = true
    end
    return changed
end

local function NormalizePerSpecStorage(containerKey, container, specID)
    local db = QUICore and QUICore.db
    local root = db and db.global and db.global.ncdm and db.global.ncdm.specTrackerSpells
    local byContainer = root and root[containerKey]
    if type(byContainer) ~= "table" then return false end

    local keys = GetSpecKeyCandidates(specID)
    local canonicalKey = keys[1]
    if type(canonicalKey) ~= "string" then return false end

    local canonicalList = byContainer[canonicalKey]
    local changed = false
    if type(canonicalList) ~= "table" then
        for i = 2, #keys do
            local aliasKey = keys[i]
            if type(byContainer[aliasKey]) == "table" then
                canonicalList = byContainer[aliasKey]
                byContainer[canonicalKey] = canonicalList
                changed = true
                break
            end
        end
    end
    if type(canonicalList) ~= "table" then return changed end

    for i = 2, #keys do
        local aliasKey = keys[i]
        local aliasList = byContainer[aliasKey]
        if type(aliasList) == "table" then
            if aliasList ~= canonicalList and MergeEntryLists(canonicalList, aliasList) then
                changed = true
            end
            byContainer[aliasKey] = nil
            if type(container) == "table" then
                if type(container._legacySpecKeyAliases) ~= "table" then
                    container._legacySpecKeyAliases = {}
                end
                container._legacySpecKeyAliases[aliasKey] = canonicalKey
            end
            changed = true
        end
    end
    if DeduplicateEntryList(canonicalList) then
        changed = true
    end
    return changed
end

local function ContainerIsCandidate(container)
    if type(container) ~= "table" then return false end
    -- Accept either V2 (specSpecific) or legacy (specSpecificSpells) flag.
    -- After migration v35, entries live in per-spec storage rather than
    -- container.entries; the entries-existence check belongs in WalkAll
    -- against per-spec storage, not here.
    if not (container.specSpecific or container.specSpecificSpells) then return false end
    if type(container._sourceSpecID) ~= "number" then return false end
    return true
end

function LegacyResolver:WalkAll(opts)
    local db = QUICore and QUICore.db
    if not db or not db.profile then return end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    if type(containers) ~= "table" then return end

    local currentSpec = GetCurrentSpecID()
    if not currentSpec then return end

    local autoApply = (opts == nil) or opts.autoApply ~= false

    local matchedAny = false
    local proposalCount = 0
    local containerCount = 0
    local autoAppliedTotal = 0

    for key, container in pairs(containers) do
        if type(key) == "string" and ContainerIsCandidate(container)
           and not container._legacyResolutionDismissed
        then
            matchedAny = true
            local proposalsForContainer = {}
            local stats = { proposed = 0, ambiguous = 0, noMatch = 0, asIs = 0, total = 0 }

            -- Entries live in the current spec's private bucket. Older
            -- imported profiles may still have alias buckets; normalize the
            -- active spec before probing slot IDs.
            if NormalizePerSpecStorage(key, container, currentSpec) then
                autoAppliedTotal = autoAppliedTotal + 1
            end
            local entryList, entryListSource, entryListKey = GetEntryListForContainer(key, container, false, nil, currentSpec)
            if type(entryList) ~= "table" then entryList = {} end

            for ei, entry in ipairs(entryList) do
                if type(entry) == "table" and entry.type == "spell" then
                    stats.total = stats.total + 1
                    local res = ProbeEntry(entry)
                    if res then
                        if res.state == "proposed" and res.target and res.target.source == "as-is" then
                            stats.asIs = stats.asIs + 1
                        else
                            proposalsForContainer[ei] = res
                            if res.state == "proposed" then
                                stats.proposed = stats.proposed + 1
                            elseif res.state == "ambiguous" then
                                stats.ambiguous = stats.ambiguous + 1
                            else
                                stats.noMatch = stats.noMatch + 1
                            end
                        end
                    end
                end
            end

            if next(proposalsForContainer) then
                _proposalsByContainer[key] = {
                    proposals = proposalsForContainer,
                    stats     = stats,
                    listSource = entryListSource,
                    listKey    = entryListKey,
                    specID     = currentSpec,
                    walkedAt  = (time and time()) or 0,
                }
                proposalCount = proposalCount + (stats.proposed + stats.ambiguous + stats.noMatch)
                containerCount = containerCount + 1

                if autoApply and stats.proposed > 0 then
                    local ok, info = self:AcceptProposalsForContainer(key, { quiet = true })
                    if ok and type(info) == "table" then
                        autoAppliedTotal = autoAppliedTotal + (info.applied or 0)
                    end
                end
            else
                if DeduplicateEntryList(entryList) then
                    autoAppliedTotal = autoAppliedTotal + 1
                end
                _proposalsByContainer[key] = nil
            end
        end
    end

    if autoAppliedTotal > 0 then
        NotifyRefresh()
    end

    return matchedAny, containerCount, proposalCount, autoAppliedTotal
end

function LegacyResolver:RemoveBrokenEntriesForContainer(containerKey)
    local db = QUICore and QUICore.db
    if not db or not db.profile then return false, "db unavailable" end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    if type(containers) ~= "table" then return false, "no containers" end
    local container = containers[containerKey]
    if type(container) ~= "table" then return false, "container missing" end

    local proposalSet = _proposalsByContainer[containerKey]
    if not proposalSet then return false, "no proposals" end

    -- Build the set of indices to remove (everything that probe couldn't auto-apply).
    local removeIdx = {}
    for entryIdx in pairs(proposalSet.proposals) do
        removeIdx[entryIdx] = true
    end

    local function CompactEntries(entries)
        if type(entries) ~= "table" then return 0 end
        local kept = {}
        for ei, e in ipairs(entries) do
            if not removeIdx[ei] then kept[#kept + 1] = e end
        end
        local removed = #entries - #kept
        for i = 1, math.max(#entries, #kept) do entries[i] = kept[i] end
        return removed
    end

    local entryList = GetEntryListForContainer(containerKey, container, false, proposalSet.listKey, proposalSet.specID)
    local removed = CompactEntries(entryList)
    if proposalSet.listSource == "container" then
        local legacyBar = FindLegacyBar(db.profile, container._legacyId)
        if legacyBar then CompactEntries(legacyBar.entries) end
    end

    _proposalsByContainer[containerKey] = nil
    NotifyRefresh()

    return true, { removed = removed }
end

function LegacyResolver:DismissContainer(containerKey)
    local db = QUICore and QUICore.db
    if not db or not db.profile then return false end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    local container = containers and containers[containerKey]
    if type(container) ~= "table" then return false end
    container._legacyResolutionDismissed = true
    _proposalsByContainer[containerKey] = nil
    return true
end

function LegacyResolver:GetProposalsForContainer(containerKey)
    return _proposalsByContainer[containerKey]
end

function LegacyResolver:GetAllProposals()
    return _proposalsByContainer
end

FindLegacyBar = function(profile, legacyId)
    if not legacyId then return nil end
    local ct = profile.customTrackers
    if type(ct) ~= "table" or type(ct.bars) ~= "table" then return nil end
    for _, b in ipairs(ct.bars) do
        if type(b) == "table" and b.id == legacyId then
            return b
        end
    end
    return nil
end

local function ApplyResolutionToEntry(entry, res, includeAmbiguous)
    if type(entry) ~= "table" then return false end
    if res.state == "proposed" and res.target and res.target.spellID then
        entry._sourceID = res.originalID
        if res.target.source == "slot" and entry._legacySpellbookSlot == nil then
            entry._legacySpellbookSlot = res.originalID
        end
        entry.id = res.target.spellID
        return true
    elseif res.state == "ambiguous" and includeAmbiguous and res.candidates and res.candidates[1] then
        entry._sourceID = res.originalID
        entry._ambiguousResolved = true
        if res.candidates[1].source == "slot" and entry._legacySpellbookSlot == nil then
            entry._legacySpellbookSlot = res.originalID
        end
        entry.id = res.candidates[1].spellID
        return true
    end
    return false
end

NotifyRefresh = function()
    if ns.Registry and ns.Registry.RefreshAll then
        pcall(ns.Registry.RefreshAll, ns.Registry)
    elseif QUICore and QUICore.RefreshAll then
        pcall(QUICore.RefreshAll, QUICore)
    end
end

function LegacyResolver:AcceptProposalsForContainer(containerKey, opts)
    local db = QUICore and QUICore.db
    if not db or not db.profile then return false, "db unavailable" end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    if type(containers) ~= "table" then return false, "no containers" end
    local container = containers[containerKey]
    if type(container) ~= "table" then return false, "container missing" end

    local proposalSet = _proposalsByContainer[containerKey]
    if not proposalSet then return false, "no proposals" end

    local includeAmbiguous = opts and opts.includeAmbiguous
    local quiet = opts and opts.quiet
    local applied, skipped = 0, 0

    -- Resolve the same current-spec list that WalkAll sourced.
    local entryList = GetEntryListForContainer(containerKey, container, false, proposalSet.listKey, proposalSet.specID)
    if type(entryList) ~= "table" then entryList = {} end

    local remaining, remainStats = {}, { proposed = 0, ambiguous = 0, noMatch = 0, total = 0 }

    for entryIdx, res in pairs(proposalSet.proposals) do
        local entry = entryList[entryIdx]
        local wasApplied = ApplyResolutionToEntry(entry, res, includeAmbiguous)
        if wasApplied then
            applied = applied + 1
        else
            skipped = skipped + 1
            remaining[entryIdx] = res
            remainStats.total = remainStats.total + 1
            if res.state == "proposed" then
                remainStats.proposed = remainStats.proposed + 1
            elseif res.state == "ambiguous" then
                remainStats.ambiguous = remainStats.ambiguous + 1
            else
                remainStats.noMatch = remainStats.noMatch + 1
            end
        end
    end

    local listMutated = false
    if applied > 0 then
        listMutated = DeduplicateEntryList(entryList)
    end

    container._legacyResolutionAcceptedAt = (time and time()) or 0

    if next(remaining) and not listMutated then
        proposalSet.proposals = remaining
        proposalSet.stats = remainStats
    else
        _proposalsByContainer[containerKey] = nil
    end

    if not quiet then
        NotifyRefresh()
    end

    return true, { applied = applied, skipped = skipped }
end

function LegacyResolver:AcceptAllProposals(opts)
    local total = { containers = 0, applied = 0, skipped = 0 }
    local keys = {}
    for k in pairs(_proposalsByContainer) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
        local ok, info = self:AcceptProposalsForContainer(k, opts)
        if ok and type(info) == "table" then
            total.containers = total.containers + 1
            total.applied = total.applied + (info.applied or 0)
            total.skipped = total.skipped + (info.skipped or 0)
        end
    end
    return total
end

function LegacyResolver:CountUnresolvedSpecMismatchContainers()
    local db = QUICore and QUICore.db
    if not db or not db.profile then return 0 end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    if type(containers) ~= "table" then return 0 end
    local currentSpec = GetCurrentSpecID()
    local mismatched = 0
    for _, container in pairs(containers) do
        if ContainerIsCandidate(container)
           and container._sourceSpecID ~= currentSpec
           and not container._legacyResolutionDismissed
        then
            mismatched = mismatched + 1
        end
    end
    return mismatched
end

----------------------------------------------------------------------------
-- Public state query for the settings UI banner.
--
-- Returns nil when there's nothing to surface for this container.
-- Otherwise returns a table { kind = "needs-review" | "spec-mismatch", ... }
-- carrying enough metadata for a banner to render its message and actions
-- without having to peek at the resolver's internals.
----------------------------------------------------------------------------
function LegacyResolver:GetRecoveryStateForContainer(containerKey)
    local db = QUICore and QUICore.db
    if not db or not db.profile then return nil end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    local container = containers and containers[containerKey]
    if type(container) ~= "table" then return nil end
    if type(container._sourceSpecID) ~= "number" then return nil end
    if container._legacyResolutionDismissed then return nil end

    local currentSpec = GetCurrentSpecID()
    local proposalSet = _proposalsByContainer[containerKey]

    if proposalSet and next(proposalSet.proposals) then
        return {
            kind         = "needs-review",
            container    = container,
            sourceSpecID = container._sourceSpecID,
            currentSpec  = currentSpec,
            proposals    = proposalSet.proposals,
            stats        = proposalSet.stats,
        }
    end

    if currentSpec ~= container._sourceSpecID then
        return {
            kind         = "spec-mismatch",
            container    = container,
            sourceSpecID = container._sourceSpecID,
            currentSpec  = currentSpec,
        }
    end

    return nil
end

function LegacyResolver:GetSpecLabel(specID)
    if type(specID) ~= "number" then return "(unknown spec)" end
    if not GetSpecializationInfoByID then return tostring(specID) end
    local _, name, _, _, _, classToken = GetSpecializationInfoByID(specID)
    if name and classToken then return ("%s %s"):format(name, classToken) end
    if name then return name end
    return tostring(specID)
end

----------------------------------------------------------------------------
-- Strip spell entries that aren't castable by the current player. Works
-- without a spec match — used by spec-mismatch banner where there's no
-- proposal cache (the resolver never walked because the gate failed).
-- Items, slots, macros are preserved untouched.
----------------------------------------------------------------------------
function LegacyResolver:RemoveInvalidSpellEntriesForContainer(containerKey)
    local db = QUICore and QUICore.db
    if not db or not db.profile then return false, "db unavailable" end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    local container = containers and containers[containerKey]
    if type(container) ~= "table" then return false, "container missing" end

    local function CompactEntries(entries)
        if type(entries) ~= "table" then return 0 end
        local kept, removed = {}, 0
        for _, e in ipairs(entries) do
            if type(e) == "table" and e.type == "spell" then
                local isPlayerCastable = type(e.id) == "number"
                    and IsPlayerSpell and IsPlayerSpell(e.id)
                if isPlayerCastable then
                    kept[#kept + 1] = e
                else
                    removed = removed + 1
                end
            else
                kept[#kept + 1] = e
            end
        end
        for i = 1, math.max(#entries, #kept) do entries[i] = kept[i] end
        return removed
    end

    -- Operate on per-spec storage at the source spec when present (post-v35),
    -- and also compact container.entries in case migration hasn't moved them
    -- yet. Either or both may have data; both get compacted with the same
    -- predicate.
    local removed = 0
    if type(container._sourceSpecID) == "number" then
        local list = GetPerSpecList(containerKey, container._sourceSpecID, false)
        if list then removed = removed + CompactEntries(list) end
    end
    if type(container.entries) == "table" then
        removed = removed + CompactEntries(container.entries)
    end

    _proposalsByContainer[containerKey] = nil
    NotifyRefresh()

    return true, { removed = removed }
end

----------------------------------------------------------------------------
-- Hard delete: remove the V2 customBar container AND its legacy bar entry.
-- Routes the V2 deletion through CDMContainers.DeleteContainer so any
-- container-level cleanup (anchoring, glow registration, etc.) runs.
----------------------------------------------------------------------------
function LegacyResolver:DeleteContainerAndLegacy(containerKey)
    if type(containerKey) ~= "string" or containerKey == "" then return false end

    local db = QUICore and QUICore.db
    local profile = db and db.profile
    if not profile then return false end

    local container = profile.ncdm and profile.ncdm.containers and profile.ncdm.containers[containerKey]
    local legacyId = container and container._legacyId

    if ns.CDMContainers and type(ns.CDMContainers.DeleteContainer) == "function" then
        ns.CDMContainers.DeleteContainer(containerKey)
    elseif profile.ncdm and profile.ncdm.containers then
        profile.ncdm.containers[containerKey] = nil
    end

    if legacyId and profile.customTrackers and type(profile.customTrackers.bars) == "table" then
        local kept = {}
        for _, b in ipairs(profile.customTrackers.bars) do
            if not (type(b) == "table" and b.id == legacyId) then
                kept[#kept + 1] = b
            end
        end
        for i = 1, math.max(#profile.customTrackers.bars, #kept) do
            profile.customTrackers.bars[i] = kept[i]
        end
    end

    -- Drop per-spec storage too: the entries lived under the container key,
    -- so without the container they're orphaned data.
    if type(db.global) == "table" and type(db.global.ncdm) == "table"
       and type(db.global.ncdm.specTrackerSpells) == "table"
    then
        db.global.ncdm.specTrackerSpells[containerKey] = nil
    end

    _proposalsByContainer[containerKey] = nil
    NotifyRefresh()
    return true
end

local function PrintNotice(autoAppliedCount)
    if autoAppliedCount and autoAppliedCount > 0 and not LegacyResolver._autoAppliedNoticeShown then
        LegacyResolver._autoAppliedNoticeShown = true
        print(("|cff60A5FAQUI:|r Auto-recovered %d legacy tracker entry(ies) for the current spec."):format(autoAppliedCount))
    end

    local proposals = _proposalsByContainer
    local count = 0
    for _ in pairs(proposals) do count = count + 1 end
    if count > 0 and not LegacyResolver._proposalsNoticeShown then
        LegacyResolver._proposalsNoticeShown = true
        print(("|cff60A5FAQUI:|r %d legacy tracker bar(s) need attention — open Settings → Cooldown Manager → Custom CDM Bars to review."):format(count))
        return
    end

    local mismatched = LegacyResolver:CountUnresolvedSpecMismatchContainers()
    if mismatched > 0 and not LegacyResolver._mismatchNoticeShown then
        LegacyResolver._mismatchNoticeShown = true
        print(("|cff60A5FAQUI:|r %d legacy tracker bar(s) imported from another spec — open Settings → Cooldown Manager → Custom CDM Bars to remove them, or switch to the matching spec to recover."):format(mismatched))
    end
end

local function HasAnySpecStampedContainer()
    local db = QUICore and QUICore.db
    if not db or not db.profile then return false end
    local containers = db.profile.ncdm and db.profile.ncdm.containers
    if type(containers) ~= "table" then return false end
    for _, c in pairs(containers) do
        if type(c) == "table" and type(c._sourceSpecID) == "number" then
            return true
        end
    end
    return false
end

local function RunWalk(announce)
    if InCombatLockdown and InCombatLockdown() then
        _pendingPostCombat = true
        return
    end
    local matched, _, _, autoApplied = LegacyResolver:WalkAll()
    -- Spec changes flip the visibility gate in cdm_containers.LayoutContainer
    -- regardless of whether we auto-applied anything, so any profile carrying
    -- spec-stamped containers needs a refresh on every spec event.
    if HasAnySpecStampedContainer() then
        NotifyRefresh()
    end
    if announce and matched then
        PrintNotice(autoApplied)
    end
end

-- Auto-walk hooks intentionally disabled: v32(d) no longer promotes
-- bar.entries into per-spec storage, so there's nothing for the resolver
-- to clean up on a typical login. The salvage probe stays available as
-- an opt-in /qui legacyrecover slash command for users with corner-case
-- profiles whose live data is still suspect (e.g. CooldownManager-drag
-- victims who configured bars before the drag-handler hardening shipped).
--
-- Re-enable by reinstating the OnEvent + Init below if a future migration
-- decision flips back to auto-promote semantics.
local function OnEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if _pendingPostCombat then
            _pendingPostCombat = false
            RunWalk(true)
        end
    end
end

function LegacyResolver:Init()
    if _resolverFrame then return end
    _resolverFrame = CreateFrame("Frame")
    -- Only the post-combat retry stays wired, since RunWalk can be invoked
    -- manually via the slash command and may need to defer if combat is
    -- active when the user runs it.
    _resolverFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _resolverFrame:SetScript("OnEvent", OnEvent)
end

LegacyResolver:Init()

----------------------------------------------------------------------------
-- Slash command surface — minimal CLI review/accept until the V2 settings
-- panel grows a dedicated Recovery section.
----------------------------------------------------------------------------

local function SpecLabel(specID)
    if type(specID) ~= "number" then return tostring(specID) end
    if not GetSpecializationInfoByID then return tostring(specID) end
    local _, name, _, _, _, classToken = GetSpecializationInfoByID(specID)
    if name and classToken then
        return ("%s %s"):format(name, classToken)
    end
    return name or tostring(specID)
end

local function FormatTarget(target)
    if not target then return "—" end
    return ("%s [spellID=%d, source=%s]"):format(
        tostring(target.name or "?"),
        tonumber(target.spellID) or 0,
        tostring(target.source or "?"))
end

function LegacyResolver:PrintReview()
    local db = QUICore and QUICore.db
    if not db or not db.profile then
        print("|cff60A5FAQUI legacyrecover:|r no profile loaded.")
        return
    end

    local proposals = _proposalsByContainer
    local proposalCount = 0
    for _ in pairs(proposals) do proposalCount = proposalCount + 1 end
    local mismatched = self:CountUnresolvedSpecMismatchContainers()
    local currentSpec = GetCurrentSpecID()

    print(("|cff60A5FAQUI legacyrecover:|r current spec = %s"):format(SpecLabel(currentSpec)))
    print(("  containers with proposals: %d"):format(proposalCount))
    print(("  containers awaiting source-spec match: %d"):format(mismatched))
    if proposalCount == 0 and mismatched == 0 then
        print("  no legacy recovery work pending.")
        return
    end

    if proposalCount > 0 then
        print(" ")
        print("Proposals (run |cFFFFFF00/qui legacyrecover accept <containerKey>|r or |cFFFFFF00/qui legacyrecover acceptall|r):")
        for key, set in pairs(proposals) do
            local s = set.stats
            print(("  |cFFFFFF00%s|r — %d proposed, %d ambiguous, %d no-match (of %d spell entries)"):format(
                key, s.proposed, s.ambiguous, s.noMatch, s.total))
            for entryIdx, res in pairs(set.proposals) do
                if res.state == "proposed" then
                    print(("    [%d] %d → %s"):format(entryIdx, res.originalID, FormatTarget(res.target)))
                elseif res.state == "ambiguous" then
                    print(("    [%d] %d → AMBIGUOUS, %d candidates:"):format(entryIdx, res.originalID, #res.candidates))
                    for _, c in ipairs(res.candidates) do
                        print(("      • %s"):format(FormatTarget(c)))
                    end
                else
                    print(("    [%d] %d → no resolution found"):format(entryIdx, res.originalID))
                end
            end
        end
    end

    if mismatched > 0 then
        print(" ")
        print("Bars awaiting source-spec match:")
        local containers = db.profile.ncdm and db.profile.ncdm.containers
        if type(containers) == "table" then
            for k, c in pairs(containers) do
                if ContainerIsCandidate(c) and c._sourceSpecID ~= currentSpec then
                    print(("  %s — imported from %s"):format(k, SpecLabel(c._sourceSpecID)))
                end
            end
        end
    end
end

function LegacyResolver:HandleSlash(rest)
    rest = (type(rest) == "string" and rest:gsub("^%s+", ""):gsub("%s+$", "")) or ""
    local sub, arg = rest:match("^(%S+)%s*(.*)$")
    sub = sub or ""

    if sub == "" or sub == "review" or sub == "list" or sub == "status" then
        self:PrintReview()
        return
    end

    if sub == "scan" then
        if InCombatLockdown and InCombatLockdown() then
            print("|cff60A5FAQUI legacyrecover:|r in combat — will scan after combat ends.")
            _pendingPostCombat = true
            return
        end
        local matched, containerCount, proposalCount = self:WalkAll()
        if not matched then
            print("|cff60A5FAQUI legacyrecover:|r no spec-tagged containers match the current spec.")
        else
            print(("|cff60A5FAQUI legacyrecover:|r scanned. %d container(s) with %d proposed entry(ies)."):format(
                containerCount or 0, proposalCount or 0))
        end
        return
    end

    if sub == "acceptall" then
        local total = self:AcceptAllProposals({ includeAmbiguous = arg == "ambiguous" })
        print(("|cff60A5FAQUI legacyrecover:|r accepted %d proposal(s) across %d container(s) (%d skipped)."):format(
            total.applied, total.containers, total.skipped))
        return
    end

    if sub == "accept" then
        local key = arg
        if key == "" then
            print("|cff60A5FAQUI legacyrecover:|r usage: |cFFFFFF00/qui legacyrecover accept <containerKey>|r")
            return
        end
        local ok, info = self:AcceptProposalsForContainer(key, { includeAmbiguous = false })
        if not ok then
            print(("|cff60A5FAQUI legacyrecover:|r accept failed for '%s' — %s"):format(key, tostring(info)))
            return
        end
        print(("|cff60A5FAQUI legacyrecover:|r accepted %d proposal(s) for %s (%d skipped)."):format(
            info.applied, key, info.skipped))
        return
    end

    print("|cff60A5FAQUI legacyrecover:|r usage:")
    print("  |cFFFFFF00/qui legacyrecover|r              — print review of pending proposals")
    print("  |cFFFFFF00/qui legacyrecover scan|r         — re-walk containers and refresh proposals")
    print("  |cFFFFFF00/qui legacyrecover accept <K>|r   — apply proposals for container K")
    print("  |cFFFFFF00/qui legacyrecover acceptall|r    — apply all unambiguous proposals")
end

_G.QUI_LegacyRecoverHandle = function(rest)
    LegacyResolver:HandleSlash(rest)
end
