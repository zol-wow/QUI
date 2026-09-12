-- QUI_Reminders/reminders/journal.lua -- this season's bosses and their abilities,
-- read out of the player's own Dungeon Journal.
--
-- Nothing here is shipped data. Every instance, boss, ability name, icon and role
-- flag comes from the client at runtime, so the list cannot go stale and covers
-- whatever tier the client is on. The walk is lazy (nothing is read until the
-- settings page asks) and cached for the session.
--
-- The tank/healer/dps marking is the journal's own icon flag on each section,
-- which arrives already attached to its boss. C_EncounterEvents also carries a
-- role bit, but has no boss association from Lua, and joining on spell id loses
-- the abilities whose cast spell differs from the applied aura -- most of them.
local _, ns = ...

local Journal = {}
ns.RemindersJournal = Journal

local cache

-- Icon flag index -> role/marker name. Blizzard_EncounterJournal builds the same
-- table from the enum: bit position of the flag value is the icon index.
local FALLBACK_FLAG_NAMES = {
    [0] = "Tank", [1] = "Dps", [2] = "Healer", [3] = "Heroic", [4] = "Deadly",
    [5] = "Important", [6] = "Interruptible", [7] = "Magic", [8] = "Curse",
    [9] = "Poison", [10] = "Disease", [11] = "Enrage",
}

local flagIndexNames
local function FlagIndexNames()
    if flagIndexNames then return flagIndexNames end
    local map = {}
    local enum = _G.Enum and _G.Enum.JournalEncounterIconFlags
    if type(enum) == "table" then
        for name, value in pairs(enum) do
            if type(value) == "number" and value > 0 then
                local index, v = 0, value
                while v > 1 do
                    v = v / 2
                    index = index + 1
                end
                map[index] = name
            end
        end
    end
    if next(map) == nil then
        for k, v in pairs(FALLBACK_FLAG_NAMES) do map[k] = v end
    end
    flagIndexNames = map
    return map
end
Journal.FlagIndexNames = FlagIndexNames

local function SectionFlags(sectionID)
    local api = _G.C_EncounterJournal
    if not (api and api.GetSectionIconFlags) then return {} end
    local ok, indices = ns.SafeCall("best-effort-style", api.GetSectionIconFlags, sectionID)
    if not ok or type(indices) ~= "table" then return {} end
    local names = FlagIndexNames()
    local flags = {}
    for _, index in ipairs(indices) do
        local name = names[index]
        if name then flags[name] = true end
    end
    return flags
end

local function EnsureJournalLoaded()
    if type(_G.EJ_GetNumTiers) ~= "function" or type(_G.EJ_GetInstanceByIndex) ~= "function" then
        return false
    end
    local addons = _G.C_AddOns
    if addons and addons.LoadAddOn then
        local loaded = addons.IsAddOnLoaded and addons.IsAddOnLoaded("Blizzard_EncounterJournal")
        if not loaded then ns.SafeCall("compat", addons.LoadAddOn, "Blizzard_EncounterJournal") end
    end
    return true
end

-- Depth-first over a section tree: children first, then siblings. Every
-- section with a spell id is an ability; overview headers carry none.
local MAX_SECTIONS = 4000
local function CollectSections(sectionID, out, seen, budget)
    local api = _G.C_EncounterJournal
    while sectionID and sectionID > 0 and budget.left > 0 do
        budget.left = budget.left - 1
        local ok, info = ns.SafeCall("best-effort-style", api.GetSectionInfo, sectionID)
        if not ok or type(info) ~= "table" then return end
        local spellID = tonumber(info.spellID)
        if spellID and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            out[#out + 1] = {
                spellID = spellID,
                name = type(info.title) == "string" and info.title or ("#" .. spellID),
                icon = info.abilityIcon,
                flags = SectionFlags(sectionID),
                sectionID = sectionID,
            }
        end
        if info.firstChildSectionID then
            CollectSections(info.firstChildSectionID, out, seen, budget)
        end
        sectionID = info.siblingSectionID
    end
end

local function CollectEncounters(instanceID)
    local encounters = {}
    local index = 1
    while index < 200 do
        local name, _, bossID, rootSectionID = _G.EJ_GetEncounterInfoByIndex(index, instanceID)
        if not bossID or bossID <= 0 then break end
        local abilities = {}
        if _G.C_EncounterJournal and _G.C_EncounterJournal.GetSectionInfo and rootSectionID then
            CollectSections(rootSectionID, abilities, {}, { left = MAX_SECTIONS })
        end
        encounters[#encounters + 1] = {
            id = bossID,
            name = type(name) == "string" and name or ("#" .. bossID),
            abilities = abilities,
        }
        index = index + 1
    end
    return encounters
end

local function CollectInstances(isRaid)
    local instances = {}
    local index = 1
    while index < 200 do
        local instanceID, name = _G.EJ_GetInstanceByIndex(index, isRaid)
        if not instanceID then break end
        _G.EJ_SelectInstance(instanceID)
        instances[#instances + 1] = {
            id = instanceID,
            name = type(name) == "string" and name or ("#" .. instanceID),
            isRaid = isRaid == true,
            encounters = CollectEncounters(instanceID),
        }
        index = index + 1
    end
    return instances
end

local function BuildUnsafe()
    local numTiers = _G.EJ_GetNumTiers()
    if type(numTiers) ~= "number" or numTiers < 1 then return nil end
    _G.EJ_SelectTier(numTiers)

    local instances = {}
    for _, inst in ipairs(CollectInstances(false)) do instances[#instances + 1] = inst end
    for _, inst in ipairs(CollectInstances(true)) do instances[#instances + 1] = inst end
    return { tier = numTiers, instances = instances }
end

-- The walk moves the journal's shared tier/instance/encounter selection. Put
-- all three back the way Blizzard's frame remembers them, success or not, so
-- reopening the journal does not show one instance's UI over another's data.
local function CaptureSelection()
    local ej = _G.EncounterJournal
    return {
        tier = _G.EJ_GetCurrentTier and _G.EJ_GetCurrentTier() or nil,
        instanceID = ej and tonumber(ej.instanceID) or nil,
        encounterID = ej and tonumber(ej.encounterID) or nil,
    }
end

local function RestoreSelection(sel)
    if type(sel.tier) == "number" and _G.EJ_SelectTier then _G.EJ_SelectTier(sel.tier) end
    if sel.instanceID and _G.EJ_SelectInstance then _G.EJ_SelectInstance(sel.instanceID) end
    if sel.encounterID and _G.EJ_SelectEncounter then _G.EJ_SelectEncounter(sel.encounterID) end
end

-- Returns the cached catalog, building it on first use. Refuses to run while
-- the player has the Dungeon Journal open, since tier/instance selection is
-- shared state the walk has to move.
function Journal.Get(force)
    if cache and not force then return cache end
    if not EnsureJournalLoaded() then return nil end
    local ej = _G.EncounterJournal
    if ej and ej.IsShown and ej:IsShown() then return nil end
    local selection = CaptureSelection()
    local ok, built = ns.SafeCall("best-effort-style", BuildUnsafe)
    ns.SafeCall("best-effort-style", RestoreSelection, selection)
    if ok and type(built) == "table" then
        cache = built
        return cache
    end
    return nil
end

function Journal.Invalidate()
    cache = nil
end

function Journal.IsCached()
    return cache ~= nil
end

-- Instance and encounter by their journal ids, from the cache only.
function Journal.FindEncounter(encounterID)
    if not cache then return nil end
    for _, inst in ipairs(cache.instances) do
        for _, enc in ipairs(inst.encounters) do
            if enc.id == encounterID then return inst, enc end
        end
    end
    return nil
end

function Journal.FindAbility(spellID)
    if not cache then return nil end
    for _, inst in ipairs(cache.instances) do
        for _, enc in ipairs(inst.encounters) do
            for _, ability in ipairs(enc.abilities) do
                if ability.spellID == spellID then return inst, enc, ability end
            end
        end
    end
    return nil
end
