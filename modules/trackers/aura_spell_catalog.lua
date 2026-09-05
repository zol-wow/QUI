local ADDON_NAME, ns = ...

-- Searchable spell/aura catalog behind the Browse popup: instead of a handful
-- of curated presets, players can find any aura by name. Sources:
--   Active Auras   — live scan of player/target/focus/party at build time
--   My Spellbook   — every spellbook entry, passives included
--   Talents        — selected talent/hero entries (procs often live only here)
--   Recently Seen  — persistent account-wide recorder of auras met in play
--
-- Everything is read-only local API. Aura data is secret in combat, so the
-- recorder only runs out of combat and every field read is secret-guarded;
-- boss debuffs that outlive the fight are picked up on PLAYER_REGEN_ENABLED.

local Catalog = ns.QUI_AuraSpellCatalog or {}
ns.QUI_AuraSpellCatalog = Catalog

local SEEN_CAP = 400
local SEEN_PRUNE_SLACK = 40
local SCAN_THROTTLE = 0.5
local MAX_AURA_INDEX = 40
local CACHE_TTL = 5

local SCAN_UNITS = { "player", "target", "focus", "party1", "party2", "party3", "party4" }
local SCAN_UNIT_SET = {}
for i = 1, #SCAN_UNITS do SCAN_UNIT_SET[SCAN_UNITS[i]] = true end

local WoW_IsSecretValue = issecretvalue
local function IsSecret(value)
    return WoW_IsSecretValue and WoW_IsSecretValue(value) or false
end

local function CleanNumber(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function CleanString(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function Now()
    return type(time) == "function" and time() or 0
end

function Catalog.SeenDB()
    local db = QUI and QUI.db and QUI.db.global
    if type(db) ~= "table" then return nil end
    if type(db.auraSpellSeen) ~= "table" then db.auraSpellSeen = {} end
    return db.auraSpellSeen
end

local function PruneSeen(db)
    local count = 0
    for _ in pairs(db) do count = count + 1 end
    if count <= SEEN_CAP + SEEN_PRUNE_SLACK then return end
    local order = {}
    for id, entry in pairs(db) do
        order[#order + 1] = { id = id, t = type(entry) == "table" and entry.t or 0 }
    end
    table.sort(order, function(a, b) return a.t < b.t end)
    for i = 1, count - SEEN_CAP do
        db[order[i].id] = nil
    end
end

function Catalog.RecordAura(spellID, name, icon, harmful, unit)
    spellID = CleanNumber(spellID)
    name = CleanString(name)
    if not spellID or not name then return false end
    local db = Catalog.SeenDB()
    if not db then return false end
    local entry = db[spellID]
    if type(entry) ~= "table" then
        entry = {}
        db[spellID] = entry
    end
    entry.name = name
    entry.icon = CleanNumber(icon) or entry.icon
    if harmful ~= nil then entry.harmful = harmful and true or false end
    -- Where it was last seen sharpens the variant badges; "on you" beats any
    -- other unit, so a player-observed stamp is never downgraded.
    if type(unit) == "string" and not IsSecret(unit) then
        if unit == "player" or entry.unit ~= "player" then
            entry.unit = unit
        end
    end
    entry.t = Now()
    PruneSeen(db)
    return true
end

local function ScanUnitFilter(unit, filter, harmful, record, out, seen)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for i = 1, MAX_AURA_INDEX do
        local ok, aura = ns.SafeCall("best-effort-style", C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok or aura == nil or IsSecret(aura) then break end
        local spellID = CleanNumber(aura.spellId)
        local name = CleanString(aura.name)
        if spellID and name then
            if record then
                Catalog.RecordAura(spellID, name, aura.icon, harmful, unit)
            end
            if out and not seen[spellID] then
                seen[spellID] = true
                out[#out + 1] = {
                    id = spellID,
                    name = name,
                    icon = CleanNumber(aura.icon),
                    harmful = harmful,
                    unit = unit,
                }
            end
        end
    end
end

-- Aura data can be secret even OUT of combat (M+ dungeons, raid restriction);
-- calling the aura APIs then is a hard error, not a secret return value, so
-- every scan checks the engine gate first.
local function AurasReadable()
    if InCombatLockdown and InCombatLockdown() then return false end
    local glue = ns.AuraGlue
    if glue and type(glue.AurasAreSecret) == "function" and glue.AurasAreSecret() then
        return false
    end
    return true
end

local function ScanUnit(unit, record, out, seen)
    if not AurasReadable() then return end
    if type(UnitExists) == "function" then
        local ok, exists = ns.SafeCall("best-effort-style", UnitExists, unit)
        if not ok or IsSecret(exists) or not exists then return end
    end
    ScanUnitFilter(unit, "HELPFUL", false, record, out, seen)
    ScanUnitFilter(unit, "HARMFUL", true, record, out, seen)
end

-- Recorder -------------------------------------------------------------------

local lastScan = {}

local function RecordUnit(unit)
    if not AurasReadable() then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    if lastScan[unit] and now - lastScan[unit] < SCAN_THROTTLE then return end
    lastScan[unit] = now
    ScanUnit(unit, true, nil, nil)
end

local function RecordAllUnits()
    for i = 1, #SCAN_UNITS do
        RecordUnit(SCAN_UNITS[i])
    end
end

local eventFrame

function Catalog.Init()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "UNIT_AURA" then
            -- A secret unit token can neither index the scan set nor be
            -- scanned; there is nothing to defer to, so the event is dropped.
            if WoW_IsSecretValue and WoW_IsSecretValue(arg1) then
                return -- @secret-policy: reject-secret-value — secret unit token, nothing to scan
            end
            if SCAN_UNIT_SET[arg1] then
                RecordUnit(arg1)
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            RecordUnit("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            RecordUnit("focus")
        else
            -- Regen/world events: sweep everything (post-combat pickup of
            -- boss debuffs that outlive the fight).
            for unit in pairs(lastScan) do lastScan[unit] = nil end
            RecordAllUnits()
        end
    end)
end

-- Section builders -----------------------------------------------------------

local function SortByName(list)
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return list
end

local function BuildActiveSection()
    local out, seen = {}, {}
    for i = 1, #SCAN_UNITS do
        ScanUnit(SCAN_UNITS[i], true, out, seen)
    end
    return SortByName(out)
end

local function BuildSpellbookSection()
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then
        return {}
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local out, seen = {}, {}
    local ok, numLines = ns.SafeCall("best-effort-style", C_SpellBook.GetNumSpellBookSkillLines)
    if not ok or type(numLines) ~= "number" then return out end
    for lineIndex = 1, numLines do
        local okLine, line = ns.SafeCall("best-effort-style", C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
        if okLine and type(line) == "table" then
            local offset = tonumber(line.itemIndexOffset) or 0
            local count = tonumber(line.numSpellBookItems) or 0
            for slot = offset + 1, offset + count do
                local okItem, item = ns.SafeCall("best-effort-style", C_SpellBook.GetSpellBookItemInfo, slot, bank)
                if okItem and type(item) == "table"
                    and (spellType == nil or item.itemType == spellType) then
                    local spellID = CleanNumber(item.spellID)
                    local name = CleanString(item.name)
                    if spellID and name and not seen[spellID] then
                        seen[spellID] = true
                        out[#out + 1] = {
                            id = spellID,
                            name = name,
                            icon = CleanNumber(item.iconID),
                        }
                    end
                end
            end
        end
    end
    return SortByName(out)
end

local function BuildTalentSection()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID
        and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes
        and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
        return {}
    end
    local out, seen = {}, {}
    local ok, configID = ns.SafeCall("best-effort-style", C_ClassTalents.GetActiveConfigID)
    if not ok or type(configID) ~= "number" then return out end
    local okCfg, config = ns.SafeCall("best-effort-style", C_Traits.GetConfigInfo, configID)
    if not okCfg or type(config) ~= "table" or type(config.treeIDs) ~= "table" then return out end
    for _, treeID in ipairs(config.treeIDs) do
        local okNodes, nodes = ns.SafeCall("best-effort-style", C_Traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okNode, node = ns.SafeCall("best-effort-style", C_Traits.GetNodeInfo, configID, nodeID)
                local entry = okNode and type(node) == "table"
                    and (node.ranksPurchased or 0) > 0
                    and type(node.activeEntry) == "table" and node.activeEntry or nil
                local entryID = entry and entry.entryID
                if entryID then
                    local okEntry, entryInfo = ns.SafeCall("best-effort-style", C_Traits.GetEntryInfo, configID, entryID)
                    local definitionID = okEntry and type(entryInfo) == "table"
                        and entryInfo.definitionID or nil
                    if definitionID then
                        local okDef, def = ns.SafeCall("best-effort-style", C_Traits.GetDefinitionInfo, definitionID)
                        local spellID = okDef and type(def) == "table"
                            and CleanNumber(def.spellID) or nil
                        if spellID and not seen[spellID] then
                            local name = C_Spell and C_Spell.GetSpellName
                                and CleanString(C_Spell.GetSpellName(spellID)) or nil
                            if name then
                                seen[spellID] = true
                                out[#out + 1] = {
                                    id = spellID,
                                    name = name,
                                    icon = C_Spell and C_Spell.GetSpellTexture
                                        and CleanNumber(C_Spell.GetSpellTexture(spellID)) or nil,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return SortByName(out)
end

local function BuildSeenSection()
    local db = Catalog.SeenDB()
    local out = {}
    if not db then return out end
    for id, entry in pairs(db) do
        if type(entry) == "table" and type(entry.name) == "string" then
            out[#out + 1] = {
                id = id,
                name = entry.name,
                icon = entry.icon,
                harmful = entry.harmful,
                unit = entry.unit,
                seenT = entry.t,
            }
        end
    end
    return SortByName(out)
end

local cachedSections
local cachedAt = 0

-- Sections in preset shape ({ name, spells }) so the Browse popup renders
-- them like any curated list. Earlier sections win the popup's per-id dedupe.
function Catalog.BuildSections()
    local now = type(GetTime) == "function" and GetTime() or 0
    if cachedSections and now - cachedAt < CACHE_TTL then
        return cachedSections
    end
    local sections = {}
    local active = BuildActiveSection()
    if #active > 0 then
        sections[#sections + 1] = { key = "active", name = ns.L["Active Auras"], spells = active }
    end
    local spellbook = BuildSpellbookSection()
    if #spellbook > 0 then
        sections[#sections + 1] = { key = "spellbook", name = ns.L["My Spellbook"], spells = spellbook }
    end
    local talents = BuildTalentSection()
    if #talents > 0 then
        sections[#sections + 1] = { key = "talents", name = ns.L["Talents"], spells = talents }
    end
    local seenSection = BuildSeenSection()
    if #seenSection > 0 then
        sections[#sections + 1] = { key = "seen", name = ns.L["Recently Seen"], spells = seenSection }
    end
    cachedSections = sections
    cachedAt = now
    return sections
end

-- Variant disambiguation ------------------------------------------------------
-- One aura name can map to several live spell IDs (talent entry, cast spell,
-- the aura it applies, rank twins). The popup merges every source a spell ID
-- appears in, then ranks: for aura tracking, an ID observed AS an aura is
-- almost always the right pick, and "on you, right now" is the strongest
-- evidence there is.

function Catalog.MergeVariantSource(merged, sectionKey, spell)
    merged.sources = merged.sources or {}
    local key = sectionKey or "preset"
    merged.sources[key] = true
    if key == "active" then
        if spell.unit == "player" or merged.activeUnit == nil then
            merged.activeUnit = spell.unit or merged.activeUnit
        end
    elseif key == "seen" then
        merged.seenUnit = spell.unit or merged.seenUnit
        merged.seenT = spell.seenT or merged.seenT
    end
    if merged.harmful == nil then merged.harmful = spell.harmful end
    return merged
end

function Catalog.VariantScore(merged)
    local sources = merged.sources or {}
    if sources.active then
        return merged.activeUnit == "player" and 5 or 4
    end
    if sources.seen then return 3 end
    if sources.spellbook then return 2 end
    if sources.talents then return 1 end
    return 0
end

function Catalog.CompareVariants(a, b)
    local sa, sb = Catalog.VariantScore(a), Catalog.VariantScore(b)
    if sa ~= sb then return sa > sb end
    local ta = tonumber(a.seenT) or 0
    local tb = tonumber(b.seenT) or 0
    if ta ~= tb then return ta > tb end
    return a.id < b.id
end

function Catalog.InvalidateCache()
    cachedSections = nil
end

-- Last-resort lookup for a typed name the sections don't contain: the client
-- resolves exact names of any loaded spell.
function Catalog.ExactNameMatch(text)
    if type(text) ~= "string" or #text < 3 or tonumber(text) then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = ns.SafeCall("best-effort-style", C_Spell.GetSpellInfo, text)
    if not ok or type(info) ~= "table" then return nil end
    local spellID = CleanNumber(info.spellID)
    local name = CleanString(info.name)
    if not spellID or not name then return nil end
    return { id = spellID, name = name, icon = CleanNumber(info.iconID) }
end

if ns.RunAfterFirstFrame then ns.RunAfterFirstFrame(Catalog.Init, 0.2) end

return Catalog
