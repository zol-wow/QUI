local function fail(msg)
    print("FAIL: nameplates_execute_threshold_test - " .. msg)
    os.exit(1)
end

local function noop() end

CreateFrame = function(_, _, _)
    return {
        _events = {},
        RegisterEvent = function(self, e) self._events[e] = true end,
        UnregisterEvent = noop,
        SetScript = function(self, k, h) self._scripts = self._scripts or {}; self._scripts[k] = h end,
        GetScript = function(self, k) return self._scripts and self._scripts[k] end,
        Hide = noop, Show = noop, SetAlpha = noop,
        CreateTexture = function() return { SetTexture = noop, Hide = noop, SetColorTexture = noop } end,
    }
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) fn() end }
C_TooltipInfo = nil
UnitName = function(_) return "Selfie" end
IsInInstance = function() return false, "none" end
UnitGroupRolesAssigned = function(_) return "NONE" end
IsInRaid = function() return false end
IsInGroup = function() return false end
UnitExists = function(_) return false end
UnitIsUnit = function(_, _) return false end
UnitThreatSituation = function(_, _) return nil end
GetRaidTargetIndex = function(_) return nil end
UnitHealthPercent = function(_, _, _) return nil end
IsPlayerSpell = function(_) return false end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return { enabled = true } end,
    },
    UIKit = {},
    Addon = { Pixels = function(_, v) return v end },
}

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_colors.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_extras.lua"))("QUI_Nameplates", ns)

local Extras = ns.QUI_Nameplates and ns.QUI_Nameplates.Extras
if not Extras then fail("NP.Extras not exported") end
if not Extras.ResolveExecuteThreshold then fail("NPExtras.ResolveExecuteThreshold not exported") end
if not Extras._SetExecuteKnownProbe then fail("NPExtras._SetExecuteKnownProbe not exported") end
if not Extras.GetExecuteSpellThresholds then fail("NPExtras.GetExecuteSpellThresholds not exported") end

local function eq(label, got, want)
    if got ~= want then
        fail(("%s: expected %s got %s"):format(label, tostring(want), tostring(got)))
    end
end

local THRESHOLDS = Extras.GetExecuteSpellThresholds()
if type(THRESHOLDS) ~= "table" then fail("GetExecuteSpellThresholds must return a table") end
local count = 0
for spellId, pct in pairs(THRESHOLDS) do
    count = count + 1
    if type(spellId) ~= "number" or spellId <= 0 then
        fail("execute table key must be a positive spell ID, got " .. tostring(spellId))
    end
    if type(pct) ~= "number" or pct <= 0 or pct > 100 then
        fail("execute threshold for " .. tostring(spellId) .. " must be a percent, got " .. tostring(pct))
    end
end
if count < 5 then fail("execute spell table looks empty (" .. count .. " entries)") end

local function known(set)
    Extras._SetExecuteKnownProbe(function(spellId) return set[spellId] == true end)
end

known({ [163201] = true })
eq("base Execute alone resolves 20", Extras.ResolveExecuteThreshold(35, true), 20)

known({ [163201] = true, [281001] = true })
eq("Massacre variant wins on max", Extras.ResolveExecuteThreshold(35, true), 35)

known({ [281001] = true, [163201] = true })
eq("scan order does not matter", Extras.ResolveExecuteThreshold(35, true), 35)

known({})
eq("no execute ability falls back to manual", Extras.ResolveExecuteThreshold(42, true), 42)

known({ [163201] = true })
eq("auto disabled always uses manual", Extras.ResolveExecuteThreshold(42, false), 42)

known({ [163201] = true })
eq("auto nil is treated as enabled", Extras.ResolveExecuteThreshold(42, nil), 20)

local calls = 0
Extras._SetExecuteKnownProbe(function(spellId)
    calls = calls + 1
    return spellId == 163201
end)
Extras.ResolveExecuteThreshold(35, true)
local afterFirst = calls
Extras.ResolveExecuteThreshold(35, true)
eq("resolved threshold is cached, not rescanned per plate", calls, afterFirst)

Extras.InvalidateExecuteThreshold()
Extras.ResolveExecuteThreshold(35, true)
if calls <= afterFirst then
    fail("InvalidateExecuteThreshold must force a rescan")
end

local src = io.open("QUI_Nameplates/nameplates/plate_extras.lua", "rb")
if not src then fail("plate_extras.lua not found") end
local text = src:read("*a")
src:close()
if not text:find('RegisterEvent("SPELLS_CHANGED")', 1, true) then
    fail("plate_extras must register SPELLS_CHANGED or a learned execute ability never invalidates the cache")
end
if not text:find("ResolveExecuteThreshold(", 1, true) then
    fail("UpdateExecute must go through ResolveExecuteThreshold")
end

print("OK: nameplates_execute_threshold_test")
