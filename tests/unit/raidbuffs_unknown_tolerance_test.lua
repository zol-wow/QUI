-- tests/unit/raidbuffs_unknown_tolerance_test.lua
-- Task 14: Unknown-tolerance in legacy buff trackers. PTR7 makes Beacon/Earth
-- Shield-class HoT auras SECRET in combat; the binary UnitHasBuff presence
-- check must become TRISTATE (true=has, false=definitely absent, nil=UNKNOWN)
-- so consumers stop false-flagging allies as missing a buff whose aura data
-- simply could not be read this pass.
--
-- Part A (brief floor): source-text assertions — verbatim from
-- .superpowers/sdd/task-14-brief.md. Vacuous to a bug where the tristate
-- exists textually but the consumer transform is missing or wired backwards.
-- Part B is a BEHAVIORAL harness (mirrors tests/unit/
-- aura_slots_never_secret_exemption_test.lua's loadfile+stub approach, and
-- tests/unit/groupframes_ally_buffs_test.lua's dual-file load order) that
-- drives the REAL MRB:UnitHasBuff (engine implementation backing raidbuffs.
-- lua's local UnitHasBuff wrapper) through the three required scenarios, and
-- both missing-flag consumers (BuildMatches in groupframes_missing_raid_
-- buffs.lua; GetRelevantBuffs/PlayerHasRaidBuff in raidbuffs.lua) end to end.
--
-- Run: lua tests/unit/raidbuffs_unknown_tolerance_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part A: brief's source-text floor (verbatim from task-14-brief.md).
----------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local rb = readAll("QUI_GroupFrames/groupframes/raidbuffs.lua")
assert(rb:find("UNKNOWN", 1, true) or rb:find("tristate", 1, true) or rb:find("== false", 1, true),
    "raidbuffs presence check must distinguish unknown from absent")
local mrb = readAll("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua")
assert(mrb:find("== false", 1, true),
    "missing-raid-buff flag must fire only on a definite false, never on unknown/nil")
print("OK raidbuffs_unknown_tolerance_test (source-text floor)")

----------------------------------------------------------------------------
-- Part B: behavioral harness.
----------------------------------------------------------------------------

-- =========================================================================
-- Minimal WoW global stubs (set BEFORE loadfile so locals capture them) —
-- mirrors tests/unit/groupframes_ally_buffs_test.lua's proven baseline.
-- =========================================================================
_G.CreateFrame = function() -- luacheck: ignore 431
    return setmetatable({}, { __index = function() return function() end end })
end
_G.UIParent = {}
_G.SlashCmdList = {}
_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

_G.UnitExists        = function() return true  end
_G.UnitIsDeadOrGhost  = function() return false end
_G.UnitIsConnected    = function() return true  end
_G.UnitIsPlayer       = function() return true  end
_G.UnitCanAssist      = function() return true  end
_G.UnitInRange        = function() return true, true end
_G.UnitClass          = function() return "Unknown", "WARRIOR" end
_G.UnitIsUnit         = function(u, other) return u == "player" and other == "player" end
_G.IsInRaid           = function() return false end
_G.IsInGroup          = function() return false end
_G.GetNumGroupMembers = function() return 0  end
_G.InCombatLockdown   = function() return false end
_G.GetTime             = function() return 0   end
_G.GetWeaponEnchantInfo = function()
    return false, nil, nil, nil, false, nil, nil, nil
end
_G.C_Item  = { GetItemInfoInstant = function() return nil end }
_G.C_Timer = {
    After     = function() end,
    NewTicker = function() return { Cancel = function() end } end,
}

-- Controllable low-level aura-read seams. Each is a stable function
-- reference captured as a LOCAL by groupframes_missing_raid_buffs.lua at
-- loadfile time — mutating a bare _G table field afterward would NOT be
-- seen, so each stub closes over a forward-declared local the scenarios
-- below reassign, and the module-captured local calls through it every time.
local directAuraResult      -- controls GetPlayerAuraBySpellID / GetUnitAuraBySpellID
local findAuraImpl = function() return nil end
local indexScanImpl = function() return nil end
local aurasSecretFlag = false

local secretMarker = setmetatable({}, {})  -- unique sentinel = "secret" for this harness
_G.issecretvalue = function(v) return v == secretMarker end

_G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return directAuraResult end,
    GetUnitAuraBySpellID   = function() return directAuraResult end,
    GetAuraDataByIndex     = function(unit, index, filter) return indexScanImpl(unit, index, filter) end,
}
_G.AuraUtil = {
    FindAuraByName = function(name, unit, filter) return findAuraImpl(name, unit, filter) end,
}
_G.C_Spell  = {}
_G.C_Secrets = { ShouldAurasBeSecret = function() return aurasSecretFlag end }
_G.LibStub  = nil

-- =========================================================================
-- Load groupframes_missing_raid_buffs.lua first (fewer deps), then
-- raidbuffs.lua on the same ns — exact order groupframes_ally_buffs_test.lua
-- establishes as working for this pair.
-- =========================================================================
local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"))(
    "QUI_GroupFrames", ns)
local MRB = assert(ns.QUI_GroupFrameMissingRaidBuffs)

ns.Helpers = {
    IsSecretValue = function() return false end,
    GetModuleSettings = function(_, defaults) -- luacheck: ignore 431
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
ns.LSM = nil
ns.AuraEvents = nil
ns.Registry = nil
ns.DebugRegister = nil
ns.Utils = { IsInInstancedContent = function() return false end }

assert(loadfile("QUI_GroupFrames/groupframes/raidbuffs.lua"))("QUI_GroupFrames", ns)

----------------------------------------------------------------------------
-- Scenario 1: buff present (whitelisted direct hit) -> true.
-- 21562 = Power Word: Fortitude, on NON_SECRET_RAID_BUFF_IDS.
----------------------------------------------------------------------------
do
    directAuraResult = { spellId = 21562 }
    local result = MRB:UnitHasBuff("player", { 21562 }, "Power Word: Fortitude")
    check("present: whitelisted direct hit => true", result == true, tostring(result))
    directAuraResult = nil
end

----------------------------------------------------------------------------
-- Scenario 2: clean scan, buff absent (whitelisted, nothing found) -> false.
----------------------------------------------------------------------------
do
    directAuraResult = nil
    local result = MRB:UnitHasBuff("player", { 21562 }, "Power Word: Fortitude")
    check("absent: whitelisted clean scan, nothing found => false", result == false, tostring(result))
end

----------------------------------------------------------------------------
-- Scenario 3a: scan THROWS (pcall failure inside an already-guarded scan
-- strategy) -> nil. Non-whitelisted spellID so the direct-lookup fast path
-- is bypassed; a spellName routes through the guarded AuraUtil.FindAuraByName
-- pcall, which we make throw.
----------------------------------------------------------------------------
do
    findAuraImpl = function() error("secret-tainted throw inside Blizzard lookup") end
    indexScanImpl = function() return nil end  -- immediate end-of-list; no other evidence
    local result = MRB:UnitHasBuff("player", { 700001 }, "Custom Ally Buff")
    check("unknown: FindAuraByName pcall throws => nil", result == nil, tostring(result))
    findAuraImpl = function() return nil end
end

----------------------------------------------------------------------------
-- Scenario 3b: scan RETURNS a secret marker (already-guarded IsSecretValue
-- probe fires) -> nil. No spellName, so the index scan is the sole strategy;
-- the first index-scan entry is the secret marker.
----------------------------------------------------------------------------
do
    local callCount = 0
    indexScanImpl = function()
        callCount = callCount + 1
        if callCount == 1 then return secretMarker end
        return nil
    end
    local result = MRB:UnitHasBuff("party1", { 700002 }, nil)
    check("unknown: index-scan secret marker => nil", result == nil, tostring(result))
    indexScanImpl = function() return nil end
end

----------------------------------------------------------------------------
-- Scenario 3c (bonus): auras globally secret and the index-scan fallback
-- cannot run at all (no spellName, no snapshot, no direct hit) -> nil, not a
-- silent false.
----------------------------------------------------------------------------
do
    aurasSecretFlag = true
    local result = MRB:UnitHasBuff("player", { 700003 }, nil)
    check("unknown: AurasAreSecret() gates the index scan entirely => nil", result == nil, tostring(result))
    aurasSecretFlag = false
end

----------------------------------------------------------------------------
-- Consumer A: MRB:BuildMatches (groupframes_missing_raid_buffs.lua's
-- RAID_BUFFS missing-flag decision). false must flag; nil must not.
----------------------------------------------------------------------------
do
    local savedHasBuff = MRB.UnitHasBuff
    local element = { classDetection = false, buffChecks = { intellect = true } }

    MRB.UnitHasBuff = function() return false end
    local outFalse = MRB:BuildMatches("player", element)
    local flaggedFalse = false
    for _, a in ipairs(outFalse) do if a.spellId == 1459 then flaggedFalse = true end end
    check("BuildMatches consumer: false => flagged missing", flaggedFalse == true)

    MRB.UnitHasBuff = function() return nil end
    local outNil = MRB:BuildMatches("player", element)
    local flaggedNil = false
    for _, a in ipairs(outNil) do if a.spellId == 1459 then flaggedNil = true end end
    check("BuildMatches consumer: nil (unknown) => NOT flagged", flaggedNil == false)

    MRB.UnitHasBuff = savedHasBuff
end

----------------------------------------------------------------------------
-- Consumer B: raidbuffs.lua's GetRelevantBuffs (via PlayerHasRaidBuff /
-- PlayerHasBuff / the local UnitHasBuff wrapper). false must flag (icon
-- shown as missing); nil must not.
-- Battle Shout (6673, providerClass WARRIOR) matches the stubbed player
-- class ("WARRIOR" above) so groupClasses[buff.providerClass] gates true.
----------------------------------------------------------------------------
do
    local savedHasBuff = MRB.UnitHasBuff
    _G.IsInGroup = function() return true end

    MRB.UnitHasBuff = function() return false end
    local resultFalse = ns.RaidBuffs._getRelevantBuffs()
    local flaggedFalse = false
    for _, b in ipairs(resultFalse) do if b.spellId == 6673 then flaggedFalse = true end end
    check("raidbuffs consumer: false => flagged missing (Battle Shout)", flaggedFalse == true)

    MRB.UnitHasBuff = function() return nil end
    local resultNil = ns.RaidBuffs._getRelevantBuffs()
    local flaggedNil = false
    for _, b in ipairs(resultNil) do if b.spellId == 6673 then flaggedNil = true end end
    check("raidbuffs consumer: nil (unknown) => NOT flagged (Battle Shout)", flaggedNil == false)

    _G.IsInGroup = function() return false end
    MRB.UnitHasBuff = savedHasBuff
end

----------------------------------------------------------------------------
-- Coordinator-escalated follow-up: MRB:UnitHasMyBuff + AnyEligibleAllyHasMyBuff
-- reproduce the same false-flag bug on Beacon of Light / Earth Shield (the
-- brief's own motivating spells) via a SECOND code path (the ally-buff-cast-
-- by-me reminder engine, distinct from UnitHasBuff/BuildMatches's RAID_BUFFS
-- loop above). Same tristate contract, same fold discipline.
----------------------------------------------------------------------------

----------------------------------------------------------------------------
-- UnitHasMyBuff producer scenarios: present / absent / secret => nil.
----------------------------------------------------------------------------
do
    directAuraResult = { isFromPlayerOrPlayerPet = true, spellId = 21562 }
    local result = MRB:UnitHasMyBuff("player", { 21562 })
    check("UnitHasMyBuff present: my whitelisted aura => true", result == true, tostring(result))
    directAuraResult = nil
end

do
    directAuraResult = { isFromPlayerOrPlayerPet = false, spellId = 21562 }  -- someone else's
    indexScanImpl = function() return nil end
    local result = MRB:UnitHasMyBuff("player", { 21562 })
    check("UnitHasMyBuff absent: not mine, clean scan finds nothing => false", result == false, tostring(result))
    directAuraResult = nil
end

do
    -- Non-whitelisted id: the whitelist loop is skipped entirely (only
    -- NON_SECRET_RAID_BUFF_IDS entries call _auraProbe); the index scan is
    -- the sole strategy and its existing IsSecretValue probe hits a marker.
    local callCount = 0
    indexScanImpl = function()
        callCount = callCount + 1
        if callCount == 1 then return secretMarker end
        return nil
    end
    local result = MRB:UnitHasMyBuff("party1", { 700004 })
    check("UnitHasMyBuff unknown: index-scan secret marker => nil", result == nil, tostring(result))
    indexScanImpl = function() return nil end
end

----------------------------------------------------------------------------
-- AnyEligibleAllyHasMyBuff aggregate scenarios: any-true-wins / all-false /
-- mixed-unknown-with-no-true => nil. Isolated from the producer by stubbing
-- MRB.UnitHasMyBuff directly (aggregate logic under test, not the scan).
----------------------------------------------------------------------------
do
    local savedGroupUnits = MRB._groupUnitsProbe
    local savedEligible = MRB._eligibleProbe
    local savedHasMy = MRB.UnitHasMyBuff

    MRB._groupUnitsProbe = function() return { "party1", "party2", "party3" } end
    MRB._eligibleProbe = function() return true end

    MRB.UnitHasMyBuff = function(_, unit)
        if unit == "party1" then return nil end   -- unknown
        if unit == "party2" then return true end   -- confirmed present
        return false
    end
    check("AnyEligibleAllyHasMyBuff: any true wins over an unknown => true",
        MRB:AnyEligibleAllyHasMyBuff({ 53563 }) == true)

    MRB.UnitHasMyBuff = function() return false end
    check("AnyEligibleAllyHasMyBuff: every ally definite-false => false",
        MRB:AnyEligibleAllyHasMyBuff({ 53563 }) == false)

    MRB.UnitHasMyBuff = function(_, unit)
        if unit == "party2" then return nil end   -- unknown, no true anywhere
        return false
    end
    check("AnyEligibleAllyHasMyBuff: mixed unknown, no true => nil",
        MRB:AnyEligibleAllyHasMyBuff({ 53563 }) == nil)

    MRB._groupUnitsProbe = savedGroupUnits
    MRB._eligibleProbe = savedEligible
    MRB.UnitHasMyBuff = savedHasMy
end

----------------------------------------------------------------------------
-- Consumer C: MRB:BuildMatches's ally-buff block (~:724-737). false must
-- remind the player (Beacon reminder shown); nil must not.
----------------------------------------------------------------------------
do
    local savedProviderSpec = MRB.PlayerIsProviderSpec
    local savedSpellKnown = MRB._spellKnownProbe
    local savedAnyAlly = MRB.AnyEligibleAllyHasMyBuff
    local element = { classDetection = false, buffChecks = {} }  -- RAID_BUFFS loop contributes nothing

    MRB.PlayerIsProviderSpec = function() return true end
    MRB._spellKnownProbe = function() return true end

    MRB.AnyEligibleAllyHasMyBuff = function() return false end
    local outFalse = MRB:BuildMatches("player", element)
    local reminderFalse = false
    for _, a in ipairs(outFalse) do if a.spellId == 53563 then reminderFalse = true end end
    check("BuildMatches ally-buff consumer: false => reminder shown (Beacon)", reminderFalse == true)

    MRB.AnyEligibleAllyHasMyBuff = function() return nil end
    local outNil = MRB:BuildMatches("player", element)
    local reminderNil = false
    for _, a in ipairs(outNil) do if a.spellId == 53563 then reminderNil = true end end
    check("BuildMatches ally-buff consumer: nil (unknown) => NOT shown (Beacon)", reminderNil == false)

    MRB.PlayerIsProviderSpec = savedProviderSpec
    MRB._spellKnownProbe = savedSpellKnown
    MRB.AnyEligibleAllyHasMyBuff = savedAnyAlly
end

----------------------------------------------------------------------------
-- Consumer D: raidbuffs.lua's GetRelevantBuffs ally-buff block (~:765-780,
-- reuses the same MRB engine methods). false must remind; nil must not.
----------------------------------------------------------------------------
do
    local savedProviderSpec = MRB.PlayerIsProviderSpec
    local savedSpellKnown = MRB._spellKnownProbe
    local savedAnyAlly = MRB.AnyEligibleAllyHasMyBuff
    _G.IsInGroup = function() return true end

    MRB.PlayerIsProviderSpec = function() return true end
    MRB._spellKnownProbe = function() return true end

    MRB.AnyEligibleAllyHasMyBuff = function() return false end
    local resultFalse = ns.RaidBuffs._getRelevantBuffs()
    local reminderFalse = false
    for _, b in ipairs(resultFalse) do if b.spellId == 53563 then reminderFalse = true end end
    check("raidbuffs ally-buff consumer: false => reminder shown (Beacon)", reminderFalse == true)

    MRB.AnyEligibleAllyHasMyBuff = function() return nil end
    local resultNil = ns.RaidBuffs._getRelevantBuffs()
    local reminderNil = false
    for _, b in ipairs(resultNil) do if b.spellId == 53563 then reminderNil = true end end
    check("raidbuffs ally-buff consumer: nil (unknown) => NOT shown (Beacon)", reminderNil == false)

    _G.IsInGroup = function() return false end
    MRB.PlayerIsProviderSpec = savedProviderSpec
    MRB._spellKnownProbe = savedSpellKnown
    MRB.AnyEligibleAllyHasMyBuff = savedAnyAlly
end

if fails > 0 then error(fails .. " failure(s) in raidbuffs_unknown_tolerance_test") end
print("OK: raidbuffs_unknown_tolerance_test (all checks passed)")
