-- QUI_Reminders/reminders/defensives.lua -- the player's own defensives: which
-- ones this spec has, whether each is ready, whether one is already up, and
-- whether the boss is on this player.
--
-- Every question here answers with a tri-state: true, false, or nil for
-- "unknowable right now". Nothing collapses nil into false. On 12.1 the numbers
-- behind a cooldown are secret in instanced combat, but the `isActive` and
-- `isOnGCD` booleans on SpellCooldownInfo are never secret, so readiness is a
-- plain Lua decision; the tri-state exists for clients or APIs that answer
-- with nothing at all.
--
-- The candidate list for the picker comes from LibOpenRaid's per-spec dataset
-- (already vendored for party keystones) filtered to the player's class and
-- spec, plus whatever on-use trinkets are equipped. Anything the dataset lacks
-- can be added by spell id.
local _, ns = ...

local Helpers = ns.Helpers

local D = {}
ns.RemindersDefensives = D

-- LibOpenRaid CONST_COOLDOWN_TYPE_DEFENSIVE_PERSONAL
local TYPE_PERSONAL = 2
local TRINKET_SLOTS = { 13, 14 }
local GCD_MAX = 1.6
local FALLBACK_ICON = 134400

local function IsSecret(value)
    if Helpers and Helpers.IsSecretValue then return Helpers.IsSecretValue(value) end
    local probe = _G.issecretvalue
    return probe ~= nil and probe(value) == true
end

-- @secret-policy: reject-secret-value
local function Readable(value)
    if IsSecret(value) then return nil end
    return value
end

-- Every read here may come back secret, so the probe policy is the default.
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = ns.SafeCall("secret-probe", fn, ...)
    if not ok then return nil end
    return a, b, c
end

-------------------------------------------------------------------------------
-- Player context
-------------------------------------------------------------------------------
function D.PlayerClass()
    local _, class = SafeCall(_G.UnitClass, "player")
    class = Readable(class)
    if type(class) == "string" then return class end
    return nil
end

function D.PlayerSpecID()
    if Helpers and Helpers.GetCurrentSpecID then
        local id = Helpers.GetCurrentSpecID()
        if type(id) == "number" then return id end
    end
    local W = ns.QUI_AuraWizard
    if W and W.PlayerSpecID then return W.PlayerSpecID() end
    return nil
end

function D.PlayerRole()
    local W = ns.QUI_AuraWizard
    if W and W.PlayerRole then return W.PlayerRole() end
    local specAPI = _G.C_SpecializationInfo
    local idx = specAPI and specAPI.GetSpecialization and specAPI.GetSpecialization()
    if idx and _G.GetSpecializationInfo then
        local role = select(5, _G.GetSpecializationInfo(idx))
        if role == "TANK" or role == "HEALER" then return role end
    end
    return "DAMAGER"
end

-------------------------------------------------------------------------------
-- Candidate discovery
-------------------------------------------------------------------------------
local function Dataset()
    local table_ = _G.LIB_OPEN_RAID_COOLDOWNS_INFO
    if type(table_) == "table" then return table_ end
    local lib = _G.LibStub and _G.LibStub("LibOpenRaid-1.0", true)
    local manager = lib and lib.CooldownManager
    if manager and manager.GetAllRegisteredCooldowns then
        local ok, result = ns.SafeCall("best-effort-style", manager.GetAllRegisteredCooldowns)
        if ok and type(result) == "table" then return result end
    end
    return nil
end
D.Dataset = Dataset

local function SpecMatches(specs, specID)
    if type(specs) ~= "table" or #specs == 0 then return true end
    if not specID then return true end
    for i = 1, #specs do
        if specs[i] == specID then return true end
    end
    return false
end

-- Spellbook MEMBERSHIP is not knowledge: IsSpellInSpellBook is documented to
-- answer true for talent-linked override spells the player cannot cast, so
-- only the knowledge functions count here.
function D.SpellKnown(spellID)
    local known = SafeCall(_G.IsPlayerSpell, spellID)
    if known == true then return true end
    known = SafeCall(_G.IsSpellKnown, spellID)
    if known == true then return true end
    local book = _G.C_SpellBook
    if book and book.IsSpellKnown then
        known = SafeCall(book.IsSpellKnown, spellID)
        if known == true then return true end
    end
    return false
end

local function SpellName(spellID)
    local api = _G.C_Spell
    local name = api and api.GetSpellName and SafeCall(api.GetSpellName, spellID)
    name = Readable(name)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function SpellIcon(spellID)
    local api = _G.C_Spell
    local icon = api and api.GetSpellTexture and SafeCall(api.GetSpellTexture, spellID)
    icon = Readable(icon)
    if icon ~= nil then return icon end
    return nil
end

local function DescribeSpell(spellID)
    return {
        id = spellID,
        kind = "spell",
        spellID = spellID,
        name = SpellName(spellID) or ("#" .. tostring(spellID)),
        icon = SpellIcon(spellID) or FALLBACK_ICON,
        known = D.SpellKnown(spellID),
    }
end

local function DescribeSlot(slot)
    local itemID = SafeCall(_G.GetInventoryItemID, "player", slot)
    itemID = Readable(itemID)
    if type(itemID) ~= "number" then return nil end
    local itemAPI = _G.C_Item
    local _, spellID = nil, nil
    if itemAPI and itemAPI.GetItemSpell then
        _, spellID = SafeCall(itemAPI.GetItemSpell, itemID)
    end
    spellID = Readable(spellID)
    if type(spellID) ~= "number" then return nil end
    local name = itemAPI and itemAPI.GetItemNameByID and SafeCall(itemAPI.GetItemNameByID, itemID)
    name = Readable(name)
    local icon = SafeCall(_G.GetInventoryItemTexture, "player", slot)
    icon = Readable(icon)
    return {
        id = "slot:" .. slot,
        kind = "item",
        slot = slot,
        itemID = itemID,
        spellID = spellID,
        name = type(name) == "string" and name or (ns.L["Trinket"] .. " " .. (slot - 12)),
        icon = icon or FALLBACK_ICON,
        known = true,
    }
end

-- A priority-list entry (number spell id or "slot:N") -> description, or nil
-- when it cannot be resolved right now (trinket slot empty, not on-use).
function D.Describe(id)
    if type(id) == "string" then
        local slot = tonumber(id:match("^slot:(%d+)$"))
        if slot then return DescribeSlot(slot) end
        id = tonumber(id)
    end
    if type(id) ~= "number" then return nil end
    return DescribeSpell(id)
end

-- Personal defensives this class/spec has, per LibOpenRaid's dataset.
function D.SpecCandidates()
    local out = {}
    local data = Dataset()
    local class = D.PlayerClass()
    local specID = D.PlayerSpecID()
    if data and class then
        for spellID, info in pairs(data) do
            if type(info) == "table" and type(spellID) == "number"
                and info.class == class and info.type == TYPE_PERSONAL
                and SpecMatches(info.specs, specID) then
                out[#out + 1] = DescribeSpell(spellID)
            end
        end
    end
    table.sort(out, function(a, b)
        if a.known ~= b.known then return a.known end
        return a.name < b.name
    end)
    return out
end

function D.TrinketCandidates()
    local out = {}
    for _, slot in ipairs(TRINKET_SLOTS) do
        local entry = DescribeSlot(slot)
        if entry then out[#out + 1] = entry end
    end
    return out
end

-------------------------------------------------------------------------------
-- Readiness
-------------------------------------------------------------------------------
-- SpellCooldownInfo.isOnGCD is documented as trustworthy only while responding
-- to SPELL_UPDATE_COOLDOWN, so it is snapshotted there for the spells the
-- engine is watching and never read live at decision time.
local GCD_SPELL_ID = 61304
local watchedSpells = {}
local gcdSnapshot = {}
local snapshotFrame

local function SnapshotGCD()
    local api = _G.C_Spell
    if not (api and api.GetSpellCooldown) then return end
    for spellID in pairs(watchedSpells) do
        local ok, info = ns.SafeCall("secret-probe", api.GetSpellCooldown, spellID)
        local onGCD
        if ok and type(info) == "table" then onGCD = Readable(info.isOnGCD) end
        if type(onGCD) == "boolean" then
            gcdSnapshot[spellID] = onGCD
        else
            gcdSnapshot[spellID] = nil
        end
    end
end
D.SnapshotGCD = SnapshotGCD

-- list: priority entries (spell ids or "slot:N"); trinket use-spells count too.
-- No snapshot is taken here: outside the event the flag is not trustworthy, so
-- a newly watched spell stays "unknown" until the next SPELL_UPDATE_COOLDOWN.
function D.SetWatchedSpells(list)
    local next_ = {}
    for i = 1, #(list or {}) do
        local entry = D.Describe(list[i])
        if entry and type(entry.spellID) == "number" then next_[entry.spellID] = true end
    end
    for spellID in pairs(gcdSnapshot) do
        if not next_[spellID] then gcdSnapshot[spellID] = nil end
    end
    watchedSpells = next_
    local wantEvents = next(next_) ~= nil
    if wantEvents and not snapshotFrame and type(CreateFrame) == "function" then
        snapshotFrame = CreateFrame("Frame")
        snapshotFrame:SetScript("OnEvent", SnapshotGCD)
    end
    if not snapshotFrame then return end
    -- Nothing to watch means nothing to pay for on every cooldown event.
    if wantEvents then
        snapshotFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    else
        snapshotFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

function D.IsWatching()
    return next(watchedSpells) ~= nil
end

local function GlobalCooldownActive()
    local api = _G.C_Spell
    if not (api and api.GetSpellCooldown) then return nil end
    local ok, info = ns.SafeCall("secret-probe", api.GetSpellCooldown, GCD_SPELL_ID)
    if not ok or type(info) ~= "table" then return nil end
    local active = Readable(info.isActive)
    if type(active) == "boolean" then return active end
    return nil
end

local function SpellReady(spellID)
    local api = _G.C_Spell
    if not (api and api.GetSpellCooldown) then return nil end
    local ok, info = ns.SafeCall("secret-probe", api.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return nil end

    -- On hold (isEnabled false) reads as inactive but cannot be pressed.
    if Readable(info.isEnabled) == false then return false end
    local isActive = Readable(info.isActive)
    if type(isActive) ~= "boolean" then
        local start, duration = Readable(info.startTime), Readable(info.duration)
        if type(start) ~= "number" or type(duration) ~= "number" then return nil end
        isActive = duration > 0 and start > 0
    end
    if not isActive then return true end

    -- A charge spell reports its recharge here only once every charge is spent,
    -- but a readable charge count is the more direct answer when we have one.
    if api.GetSpellCharges then
        local okCharges, charges = ns.SafeCall("secret-probe", api.GetSpellCharges, spellID)
        if okCharges and type(charges) == "table" then
            local current = Readable(charges.currentCharges)
            if type(current) == "number" then return current > 0 end
        end
    end

    -- Active but only the global cooldown: still ready to press. The trusted
    -- answer is the SPELL_UPDATE_COOLDOWN snapshot; a readable duration is the
    -- next best; with neither, a global cooldown that is NOT running proves
    -- the spell's own cooldown is real, and anything else is unknowable.
    local onGCD = gcdSnapshot[spellID]
    if onGCD == true then return true end
    if onGCD == false then return false end
    local duration = Readable(info.duration)
    if type(duration) == "number" and duration > 0 then return duration <= GCD_MAX end
    if GlobalCooldownActive() == false then return false end
    return nil
end

local function ItemReady(itemID)
    local api = _G.C_Item
    if not (api and api.GetItemCooldown) then return nil end
    local ok, start, duration = ns.SafeCall("secret-probe", api.GetItemCooldown, itemID)
    if not ok then return nil end
    start, duration = Readable(start), Readable(duration)
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if start == 0 or duration <= GCD_MAX then return true end
    return false
end

-- true = press it now, false = on cooldown or not known, nil = unknowable.
function D.IsReady(entry)
    if type(entry) ~= "table" then return false end
    if entry.kind == "item" then return ItemReady(entry.itemID) end
    if entry.known == false then return false end
    return SpellReady(entry.spellID)
end

-- First entry of the list that is ready; failing that, the first one whose
-- readiness is unknowable (the caller may still show it). Second return says
-- whether the pick was a confirmed-ready one.
function D.Pick(list)
    local unknown
    for i = 1, #list do
        local entry = D.Describe(list[i])
        if entry then
            local ready = D.IsReady(entry)
            if ready == true then return entry, true end
            if ready == nil and not unknown then unknown = entry end
        end
    end
    return unknown, false
end

-------------------------------------------------------------------------------
-- Coverage: is one of the listed defensives already up on the player?
-------------------------------------------------------------------------------
function D.IsCovered(list)
    local glue = ns.AuraGlue
    if glue and glue.AurasAreSecret and glue.AurasAreSecret() then return nil end
    local api = _G.C_UnitAuras
    if not (api and api.GetPlayerAuraBySpellID) then return nil end
    local sawReadable = false
    for i = 1, #list do
        local entry = D.Describe(list[i])
        local spellID = entry and entry.spellID
        if spellID then
            local ok, aura = ns.SafeCall("secret-probe", api.GetPlayerAuraBySpellID, spellID)
            if ok then
                if IsSecret(aura) then return nil end
                sawReadable = true
                if type(aura) == "table" then return true end
            end
        end
    end
    if sawReadable then return false end
    return nil
end

-------------------------------------------------------------------------------
-- Boss ownership for tank specs
-------------------------------------------------------------------------------
-- true when a boss unit has this player as its target by threat, false when
-- every boss unit readably says otherwise, nil when there is no boss unit or
-- the threat state is secret.
function D.IsTankingBoss()
    local sawUnit, sawUnknown = false, false
    for i = 1, 5 do
        local unit = "boss" .. i
        local exists = Readable(SafeCall(_G.UnitExists, unit))
        if exists == true then
            sawUnit = true
            local status = Readable(SafeCall(_G.UnitThreatSituation, "player", unit))
            if type(status) == "number" then
                if status >= 2 then return true end
            else
                sawUnknown = true
            end
        end
    end
    if not sawUnit or sawUnknown then return nil end
    return false
end
