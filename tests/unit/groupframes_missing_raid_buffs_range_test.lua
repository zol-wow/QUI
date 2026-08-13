-- tests/unit/groupframes_missing_raid_buffs_range_test.lua
-- Run: lua tests/unit/groupframes_missing_raid_buffs_range_test.lua
-- Validates the missing-raid-buff range gate (_rangeProbe): prefers the
-- group-frame range engine, fails CLOSED on secret/unknown range, falls
-- back to UnitInRange; plus the C_SpecializationInfo spec probe preference
-- and the synthetic-aura name/icon cache self-heal.

-- =========================================================================
-- Minimal WoW global stubs (set BEFORE loadfile so locals capture them)
-- =========================================================================

_G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
end

_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Test-controlled UnitInRange fallback (captured as a dispatcher at load).
local unitInRangeResult = { true, true }
_G.UnitInRange = function() return unitInRangeResult[1], unitInRangeResult[2] end

_G.UnitExists        = function() return true  end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsConnected   = function() return true  end
_G.UnitIsPlayer      = function() return true  end
_G.UnitCanAssist     = function() return true  end
_G.UnitIsUnit        = function(u, other) return u == other end
_G.UnitClass         = function() return "Priest", "PRIEST" end
_G.IsInRaid          = function() return false end
_G.IsInGroup         = function() return true  end
_G.GetNumGroupMembers = function() return 2 end
_G.InCombatLockdown  = function() return false end
_G.GetTime           = function() return 0 end
_G.C_Timer = { After = function() end }

-- Spell name/icon lookups: start UNRESOLVED (early-login simulation).
local spellDataLoaded = false
_G.C_Spell = {
    GetSpellName = function(id)
        if spellDataLoaded then return "Machtwort: Seelenstaerke" end
        return nil
    end,
    GetSpellTexture = function(id)
        if spellDataLoaded then return 135987 end
        return nil
    end,
}
_G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return nil end,
    GetUnitAuraBySpellID   = function() return nil end,
}
_G.AuraUtil = {}

-- Spec API: both the deprecated globals and the C_ namespace exist; the
-- namespace must win.
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return 111 end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 2 end,
    GetSpecializationInfo = function(idx)
        assert(idx == 2, "spec index must come from C_SpecializationInfo")
        return 222, "SpecName"
    end,
}

local ns = {}
ns.Helpers = {
    IsSecretValue = function(v) return v == "SECRET" end,
}

assert(loadfile("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"))(
    "QUI_GroupFrames", ns)
local MRB = ns.QUI_GroupFrameMissingRaidBuffs

local failures = 0
local function check(label, cond)
    if cond then
        print("  ok  " .. label)
    else
        failures = failures + 1
        print("  FAIL " .. label)
    end
end

-- =========================================================================
-- 1. _rangeProbe with the group-frame range engine
-- =========================================================================
local rangeResult = true
ns.QUI_GroupFrames = {
    CheckUnitRange = function(unit)
        if rangeResult == "THROW" then error("boom") end
        return rangeResult
    end,
}

rangeResult = true
check("engine in-range -> probe true", MRB._rangeProbe("party1") == true)
rangeResult = false
check("engine out-of-range -> probe false", MRB._rangeProbe("party1") == false)
rangeResult = "SECRET"
check("engine secret range -> probe false (fail closed)", MRB._rangeProbe("party1") == false)
rangeResult = "THROW"
check("engine error -> probe false (fail closed)", MRB._rangeProbe("party1") == false)

-- =========================================================================
-- 2. _rangeProbe UnitInRange fallback (no engine available)
-- =========================================================================
ns.QUI_GroupFrames = nil

unitInRangeResult = { true, true }
check("fallback (true, checked) -> probe true", MRB._rangeProbe("party1") == true)
unitInRangeResult = { false, true }
check("fallback (false, checked) -> probe false", MRB._rangeProbe("party1") == false)
unitInRangeResult = { true, false }
check("fallback unchecked -> probe true (range unknowable, keep icon)", MRB._rangeProbe("party1") == true)
unitInRangeResult = { "SECRET", "SECRET" }
check("fallback secret -> probe false (fail closed)", MRB._rangeProbe("party1") == false)

-- =========================================================================
-- 3. BuildMatches honors the range gate
-- =========================================================================
local element = { classDetection = true, maxIcons = 1 }

unitInRangeResult = { true, true }
local matches = MRB:BuildMatches("party1", element, {})
check("in-range unit missing Fortitude -> 1 match", #matches == 1)
check("match is the stamina synthetic aura", matches[1] and matches[1].spellId == 21562)

unitInRangeResult = { false, true }
matches = MRB:BuildMatches("party1", element, {})
check("out-of-range unit -> suppressed", #matches == 0)

unitInRangeResult = { "SECRET", "SECRET" }
matches = MRB:BuildMatches("party1", element, {})
check("secret-range unit -> suppressed (fail closed)", #matches == 0)

matches = MRB:BuildMatches("player", element, {})
check("player token exempt from range gate", #matches == 1)

-- =========================================================================
-- 4. Synthetic aura name/icon self-heal (no permanent fallback caching)
-- =========================================================================
unitInRangeResult = { true, true }
matches = MRB:BuildMatches("party1", element, {})
check("pre-spell-data: label fallback used", matches[1].name == "Power Word: Fortitude")
check("pre-spell-data: question-mark icon fallback", matches[1].icon == 134400)

spellDataLoaded = true
matches = MRB:BuildMatches("party1", element, {})
check("post-spell-data: localized name self-heals", matches[1].name == "Machtwort: Seelenstaerke")
check("post-spell-data: real icon self-heals", matches[1].icon == 135987)

-- =========================================================================
-- 5. _specProbe prefers C_SpecializationInfo over deprecated globals
-- =========================================================================
check("spec probe returns C_SpecializationInfo specID", MRB._specProbe() == 222)

print(string.format("\n%d failure(s)", failures))
if failures > 0 then os.exit(1) end
print("OK: groupframes_missing_raid_buffs_range_test")
