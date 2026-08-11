-- tests/unit/groupframes_ally_buffs_test.lua
-- Run: lua tests/unit/groupframes_ally_buffs_test.lua
-- Validates the ALLY_BUFFS data table, UnitHasMyBuff player-cast filtering,
-- group scan + spec gate, and BuildMatches wiring for ally-buff reminders.

-- =========================================================================
-- Minimal WoW global stubs (set BEFORE loadfile so locals capture them)
-- =========================================================================

-- CreateFrame: needed by EnsureEventFrame() in groupframes_missing_raid_buffs.lua
-- and by the eventFrame registration block in raidbuffs.lua.
_G.CreateFrame = function(frameType, name, parent, template) -- luacheck: ignore 431
    return setmetatable({}, { __index = function() return function() end end })
end

_G.UIParent = {}
_G.SlashCmdList = {}

-- wipe: WoW global absent from stock Lua 5.1.
_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Unit query APIs captured as locals at file-load time by the engine modules.
_G.UnitExists      = function() return true  end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsConnected = function() return true  end
_G.UnitIsPlayer    = function() return true  end
_G.UnitCanAssist   = function() return true  end
_G.UnitInRange     = function() return true, true end
_G.UnitClass       = function() return "Unknown", "WARRIOR" end
-- Stub UnitIsUnit to recognise raid5 == player (used by the real _isPlayerUnitProbe
-- in Task5/C1 to exercise the pcall path instead of stubbing the seam).
_G.UnitIsUnit      = function(u, other) return u == "raid5" and other == "player" end
_G.IsInRaid        = function() return false end
_G.IsInGroup       = function() return false end
_G.GetNumGroupMembers = function() return 0  end
_G.InCombatLockdown  = function() return false end
_G.GetTime           = function() return 0   end
_G.GetWeaponEnchantInfo = function()
    return false, nil, nil, nil, false, nil, nil, nil
end
_G.C_Item = { GetItemInfoInstant = function() return nil end }
_G.C_Timer = {
    After     = function() end,
    NewTicker = function() return { Cancel = function() end } end,
}
-- GetAuraDataByIndex / C_Secrets.ShouldAurasBeSecret are captured as LOCALS
-- by groupframes_missing_raid_buffs.lua at loadfile time, so a bare
-- _G.C_UnitAuras.field = fn reassignment afterward would never be seen — each
-- stub instead calls through a stable closure that dereferences a
-- reassignable upvalue (same technique as tests/unit/
-- raidbuffs_unknown_tolerance_test.lua). Defaults (empty scan, auras not
-- secret) are a behavioral no-op vs. the previous bare `_G.C_UnitAuras = {}`
-- for every existing Task in this file (GetAuraDataByIndex was implicitly
-- nil-forever before too) — Task2b below is the only block that reassigns
-- them, and restores the defaults immediately after.
local indexScanImpl = function() return nil end
local aurasSecretFlag = false
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter) return indexScanImpl(unit, index, filter) end,
}
_G.C_Spell     = {}
_G.AuraUtil    = {}
_G.C_Secrets   = { ShouldAurasBeSecret = function() return aurasSecretFlag end }
_G.LibStub     = nil

-- =========================================================================
-- Namespace: load groupframes_missing_raid_buffs.lua first (fewer deps).
-- =========================================================================
local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"))(
    "QUI_GroupFrames", ns)

-- Extend ns with what raidbuffs.lua needs before loading it.
ns.Helpers = {
    IsSecretValue = function() return false end,
    GetModuleSettings = function(key, defaults) -- luacheck: ignore 431
        return setmetatable({}, { __index = defaults or {} })
    end,
    GetSkinBgColor    = function() return 0, 0, 0 end,
    GetGeneralFont    = function() return "Interface\\Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "OUTLINE" end,
    ApplyFontWithFallback = function() end,
    CreateDBGetter    = nil,
}
ns.Addon = setmetatable({}, { __index = function() return function() return 0 end end })
ns.SkinBase = { ApplyPixelBackdrop = function() end }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.LSM       = nil
ns.AuraEvents  = nil
ns.Registry    = nil
ns.DebugRegister = nil
ns.Utils = { IsInInstancedContent = function() return false end }

assert(loadfile("QUI_GroupFrames/groupframes/raidbuffs.lua"))("QUI_GroupFrames", ns)

-- =========================================================================
-- Task 1: ALLY_BUFFS table shape + whitelist coverage
-- =========================================================================
local ALLY = ns.QUI_AllyBuffs
assert(type(ALLY) == "table" and #ALLY >= 2, "ALLY_BUFFS must exist with >= 2 entries")

local byName = {}
for _, e in ipairs(ALLY) do byName[e.name] = e end

local beacon = byName["Beacon"]
assert(beacon, "Beacon entry present")
assert(beacon.providerClass == "PALADIN", "Beacon provider PALADIN")
-- Holy paladin spec id = 65
assert(beacon.providerSpecIDs and beacon.providerSpecIDs[65], "Beacon gated to Holy (65)")
for _, id in ipairs({53563, 156910, 156322, 1244893}) do
    local has = false
    for _, e in ipairs(ALLY) do
        for _, x in ipairs(e.ids) do
            if x == id then has = true end
        end
    end
    assert(has, "beacon id " .. id .. " in ALLY_BUFFS")
end

local earth = byName["Earth Shield"]
assert(earth and earth.providerClass == "SHAMAN", "Earth Shield SHAMAN")
assert(earth.providerSpecIDs and earth.providerSpecIDs[264], "Earth Shield gated to Resto (264)")
for _, id in ipairs({974, 383648}) do
    local found = false
    for _, x in ipairs(earth.ids) do if x == id then found = true end end
    assert(found, "earth shield id " .. id)
end

local som = byName["Source of Magic"]
assert(som and som.providerClass == "EVOKER", "Source of Magic EVOKER")
-- Augmentation Evoker spec id = 1473
assert(som.providerSpecIDs and som.providerSpecIDs[1473], "Source of Magic gated to Augmentation (1473)")
do
    local found = false
    for _, x in ipairs(som.ids) do if x == 369459 then found = true end end
    assert(found, "source of magic id 369459")
end

-- All in-scope ids must be on the engine non-secret whitelist
local MRB = ns.QUI_GroupFrameMissingRaidBuffs
local wl = MRB.NonSecretRaidBuffIDs
for _, id in ipairs({53563, 156910, 156322, 1244893, 974, 383648, 369459}) do
    assert(wl[id], "id " .. id .. " whitelisted as non-secret")
end
print("OK: groupframes_ally_buffs_test Task1")

-- =========================================================================
-- Task 2: UnitHasMyBuff filters to player-cast
-- =========================================================================
do
    -- Monkeypatch the aura probe seam so the method is deterministic.
    local present = { ["raid1:53563"] = "mine", ["raid2:53563"] = "other" }
    MRB._auraProbe = function(unit, id)
        local key = unit .. ":" .. id
        local who = present[key]
        if not who then return nil end
        return { isFromPlayerOrPlayerPet = (who == "mine") }
    end
    assert(MRB:UnitHasMyBuff("raid1", {53563}) == true,  "my beacon on raid1 counts")
    -- Task 14 tristate update: raid2/raid3 stay `false` here — these are
    -- genuine DEFINITE-negative outcomes (a readable "someone else's copy"
    -- and a readable "nothing"), not a collapsed unknown. GetAuraDataByIndex
    -- is now a live (default no-op) stub, so these two asserts exercise the
    -- real index-scan fallback end to end, not a dead branch. Task2b below
    -- pins the genuinely-UNKNOWN outcome for this same spell ID (53563) so
    -- the two tristate branches are both proven for the brief's own
    -- motivating spell, not just asserted by omission.
    assert(MRB:UnitHasMyBuff("raid2", {53563}) == false, "someone else's beacon does not count")
    assert(MRB:UnitHasMyBuff("raid3", {53563}) == false, "absent = false")
    print("OK: groupframes_ally_buffs_test Task2")
end

-- =========================================================================
-- Task 2b (Task 14 follow-up): UnitHasMyBuff tristate — unreadable (secret)
-- aura data for the SAME spell (53563, Beacon of Light) must yield nil
-- (UNKNOWN), never collapse into the same `false` Task2 asserts for a
-- genuinely-absent result above.
-- =========================================================================
do
    -- raid4 is not in Task2's `present` map (whitelist seam returns nil, same
    -- as raid3), but this time the index-scan fallback reports the aura data
    -- as globally secret instead of cleanly finding nothing.
    aurasSecretFlag = true
    local result = MRB:UnitHasMyBuff("raid4", { 53563 })
    aurasSecretFlag = false
    assert(result == nil, "unreadable (secret) aura data => nil (UNKNOWN), not false")
    print("OK: groupframes_ally_buffs_test Task2b")
end

-- =========================================================================
-- Task 3: group scan + spec gate
-- =========================================================================
do
    -- Stub eligibility and per-unit check through documented seams.
    MRB._eligibleProbe = function(unit)
        return unit == "player" or unit == "party1" or unit == "party2"
    end
    local mine = { party1 = true }            -- my beacon is on party1 only
    MRB.UnitHasMyBuff = function(_, unit_or_self)
        return mine[unit_or_self] == true
    end
    -- Group of player + party1..party2
    MRB._groupUnitsProbe = function() return { "player", "party1", "party2" } end
    assert(MRB:AnyEligibleAllyHasMyBuff({53563}) == true, "present on an ally")
    mine.party1 = nil
    assert(MRB:AnyEligibleAllyHasMyBuff({53563}) == false, "absent everywhere = missing")

    -- spec gate
    MRB._specProbe = function() return 65 end  -- Holy
    assert(MRB:PlayerIsProviderSpec({ providerSpecIDs = { [65] = true } }) == true,
        "Holy passes")
    assert(MRB:PlayerIsProviderSpec({ providerSpecIDs = { [264] = true } }) == false,
        "non-Resto fails")
    print("OK: groupframes_ally_buffs_test Task3")
end

-- =========================================================================
-- Task 4: BuildMatches appends a missing-beacon synthetic aura for the player
-- =========================================================================
do
    MRB._eligibleProbe    = function(unit) return unit == "player" end
    MRB._specProbe        = function() return 65 end             -- Holy
    MRB._spellKnownProbe  = function(_) return true end          -- beacon known
    MRB._groupUnitsProbe  = function() return { "player" } end
    MRB.UnitHasMyBuff     = function() return false end          -- beacon NOT out anywhere

    -- ensure RAID_BUFFS path yields nothing for this synthetic player
    local out = MRB:BuildMatches("player", { classDetection = false, buffChecks = {} })
    local names = {}
    for _, a in ipairs(out) do names[a.name or a.label or ""] = true end
    assert(names["Beacon"] or names["Beacon of Light"],
        "missing beacon appended for player")

    MRB.UnitHasMyBuff = function() return true end          -- beacon out on someone
    local out2 = MRB:BuildMatches("player", { classDetection = false, buffChecks = {} })
    for _, a in ipairs(out2) do
        assert((a.name or "") ~= "Beacon", "no reminder when beacon out")
    end
    print("OK: groupframes_ally_buffs_test Task4")
end

-- =========================================================================
-- Task 5: C1 fix — ally-buff pass runs when unit is a raidN token = player
-- =========================================================================
do
    MRB._eligibleProbe    = function(u) return u == "raid5" end
    MRB._specProbe        = function() return 65 end  -- Holy Paladin
    MRB._spellKnownProbe  = function() return true end
    MRB._groupUnitsProbe  = function() return { "raid5" } end
    MRB.UnitHasMyBuff     = function() return false end  -- beacon not on anyone
    -- Let the REAL _isPlayerUnitProbe run: UnitIsUnit("raid5", "player") was stubbed
    -- to return true at the top of this file (before loadfile captured the local),
    -- so the pcall path resolves correctly without needing a seam override.
    assert(MRB._isPlayerUnitProbe("raid5") == true,
        "C1: real _isPlayerUnitProbe resolves raid5 == player via UnitIsUnit pcall")

    local out = MRB:BuildMatches("raid5", { classDetection = false, buffChecks = {} })
    local names = {}
    for _, a in ipairs(out) do names[a.name or a.label or ""] = true end
    assert(names["Beacon"] or names["Beacon of Light"],
        "C1: ally-buff reminder fires for raidN player-unit (not just literal 'player')")
    print("OK: groupframes_ally_buffs_test Task5/C1")
end

-- =========================================================================
-- Task 6: I3 fix — standalone panel scan includes missing ally buff
-- =========================================================================
do
    local savedIsProvider = MRB.PlayerIsProviderSpec
    local savedAnyAlly    = MRB.AnyEligibleAllyHasMyBuff
    local savedSpellKnown = MRB._spellKnownProbe

    -- Simulate Holy Paladin with no beacon out on any ally.
    MRB.PlayerIsProviderSpec    = function(_, buff) return buff.providerSpecIDs and buff.providerSpecIDs[65] == true end
    MRB.AnyEligibleAllyHasMyBuff = function() return false end
    MRB._spellKnownProbe        = function() return true end

    -- showRaidBuffs requires IsInGroup() = true; stub it just for this scope.
    _G.IsInGroup = function() return true end

    local result = ns.RaidBuffs._getRelevantBuffs()

    _G.IsInGroup = function() return false end
    MRB.PlayerIsProviderSpec     = savedIsProvider
    MRB.AnyEligibleAllyHasMyBuff = savedAnyAlly
    MRB._spellKnownProbe         = savedSpellKnown

    local hasAllyBuff = false
    for _, b in ipairs(result) do
        if b.isAllyBuff then hasAllyBuff = true end
    end
    assert(hasAllyBuff, "I3: standalone panel GetRelevantBuffs includes a missing ally buff")
    print("OK: groupframes_ally_buffs_test Task6/I3")
end

-- =========================================================================
-- Task 7: maxIcons — ally buff not starved by RAID_BUFFS filling the slot
-- =========================================================================
do
    MRB._eligibleProbe    = function(u) return u == "player" end
    MRB._specProbe        = function() return 264 end           -- Resto Shaman
    MRB._spellKnownProbe  = function() return true end
    MRB._groupUnitsProbe  = function() return { "player" } end
    MRB.UnitHasMyBuff     = function() return false end         -- Earth Shield not on anyone
    MRB._isPlayerUnitProbe = function(u) return u == "player" end

    local savedHasBuff = MRB.UnitHasBuff
    MRB.UnitHasBuff = function() return false end               -- all raid buffs missing too

    -- maxIcons=1: Earth Shield (ally buff) should appear; RAID_BUFFS can't starve it.
    local out = MRB:BuildMatches("player", {
        classDetection = false,
        buffChecks     = { stamina = true },  -- pretend stamina also missing
        maxIcons       = 1,
    })
    MRB.UnitHasBuff = savedHasBuff

    local names = {}
    for _, a in ipairs(out) do names[a.name or a.label or ""] = true end
    assert(names["Earth Shield"],
        "maxIcons: Earth Shield not starved by RAID_BUFFS filling the single slot")
    print("OK: groupframes_ally_buffs_test Task7/maxIcons")
end

-- =========================================================================
-- Task 8: AllyDeltaIsRelevant — delta scope + instance tracking
-- Tests the perf-fix: only wake the player-frame refresh when a tracked
-- ally-buff spell ID is added/removed (mirrors AuraDeltaIsRelevant pattern).
-- =========================================================================
do
    local deltaFn = MRB._allyDeltaIsRelevant
    assert(type(deltaFn) == "function", "Task8: _allyDeltaIsRelevant seam exposed")

    -- nil updateInfo or full update → always relevant (conservative).
    assert(deltaFn("raid1", nil) == true,                            "nil payload → relevant")
    assert(deltaFn("raid1", { isFullUpdate = true }) == true,        "full update → relevant")

    -- Untracked spell: should NOT be relevant; no instance tracked.
    local notRelevant = deltaFn("raid2", {
        addedAuras = { { spellId = 99999, auraInstanceID = 8001 } },
    })
    assert(notRelevant == false, "untracked spell → not relevant")

    -- Tracked spellId (Beacon of Light) → relevant + instance tracked.
    local beaconID = 53563
    local relevant = deltaFn("raid3", {
        addedAuras = { { spellId = beaconID, auraInstanceID = 9001 } },
    })
    assert(relevant == true, "added tracked beacon → relevant")

    -- Remove the tracked instance → still relevant.
    local removedRelevant = deltaFn("raid3", {
        removedAuraInstanceIDs = { 9001 },
    })
    assert(removedRelevant == true, "removed tracked beacon instance → relevant")

    -- Remove an untracked instance (never seen before) → not relevant.
    local removedUntracked = deltaFn("raid3", {
        removedAuraInstanceIDs = { 5555 },
    })
    assert(removedUntracked == false, "removed untracked instance → not relevant")

    print("OK: groupframes_ally_buffs_test Task8/AllyDelta")
end
