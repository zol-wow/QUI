-- cast_engine_test.lua
-- Behavioral test for core/cast_engine.lua (ns.CastEngine): cast info
-- querying, secret-timing detection, the non-player timing decision ladder,
-- engine-driven animation handoff, and timer-text memoization.

local unpack = unpack or table.unpack -- Lua 5.1 (CI) / 5.4 (local) compat

local function fail(msg)
    print("FAIL: cast_engine_test - " .. msg)
    os.exit(1)
end

-- Minimal secret-value simulation: a table that errors on arithmetic, like a
-- 12.0 secret. IsSecretValue recognizes it via a marker registry.
local secrets = setmetatable({}, { __mode = "k" })
local function MakeSecret(label)
    local s = setmetatable({}, {
        __add = function() error("secret arithmetic") end,
        __div = function() error("secret arithmetic") end,
        __tostring = function() error("secret tostring") end,
    })
    secrets[s] = label or true
    return s
end

local ns = {
    Helpers = {
        IsSecretValue = function(v) return secrets[v] == true or (v ~= nil and secrets[v] ~= nil) end,
    },
}

-- WoW API stubs, reconfigured per scenario
local castingInfo, channelInfo
local castingDuration, channelDuration
function UnitCastingInfo(unit) -- luacheck: ignore
    if not castingInfo then return nil end
    return unpack(castingInfo, 1, 9)
end
function UnitChannelInfo(unit) -- luacheck: ignore
    if not channelInfo then return nil end
    return unpack(channelInfo, 1, 10)
end
function UnitCastingDuration(unit) return castingDuration end -- luacheck: ignore
function UnitChannelDuration(unit) return channelDuration end -- luacheck: ignore

assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/cast_engine.lua"))("QUI", ns)
local CastEngine = ns.CastEngine
if not CastEngine then fail("ns.CastEngine not exported") end

---------------------------------------------------------------------------
-- GetCastInfo: plain cast
---------------------------------------------------------------------------
castingInfo = { "Fireball", "Fireball", 135812, 1000, 3500, false, "castid", false, 133 }
channelInfo = nil
castingDuration = { GetRemainingDuration = function() return 2.5 end }
channelDuration = nil

local spellName, _, texture, startMS, endMS, notInterruptible, spellID, isChanneled, _, durationObj, hasSecretTiming =
    CastEngine.GetCastInfo("target")
if spellName ~= "Fireball" then fail("GetCastInfo spellName") end
if texture ~= 135812 then fail("GetCastInfo texture") end
if startMS ~= 1000 or endMS ~= 3500 then fail("GetCastInfo timing") end
if notInterruptible ~= false then fail("GetCastInfo notInterruptible") end
if spellID ~= 133 then fail("GetCastInfo spellID") end
if isChanneled then fail("GetCastInfo isChanneled should be false") end
if durationObj ~= castingDuration then fail("GetCastInfo durationObj") end
if hasSecretTiming then fail("plain timing must not be flagged secret") end

---------------------------------------------------------------------------
-- GetCastInfo: channel fallback + spellID adoption
---------------------------------------------------------------------------
castingInfo = nil
channelInfo = { "Drain Life", "Drain Life", 136169, 2000, 7000, false, true, 234153, false, 0 }
channelDuration = { GetRemainingDuration = function() return 4.0 end }

local cName, _, _, _, _, cNotInterruptible, cSpellID, cIsChanneled, _, cDurObj =
    CastEngine.GetCastInfo("target")
if cName ~= "Drain Life" then fail("channel spellName") end
if cIsChanneled ~= true then fail("channel isChanneled") end
if cSpellID ~= 234153 then fail("channel spellID adoption") end
if cNotInterruptible ~= true then fail("channel notInterruptible") end
if cDurObj ~= channelDuration then fail("channel durationObj") end

---------------------------------------------------------------------------
-- GetCastInfo: secret timing detection (arithmetic probe path)
---------------------------------------------------------------------------
local secretStart, secretEnd = MakeSecret("start"), MakeSecret("end")
-- Bypass IsSecretValue (pretend the marker misses) to exercise the pcall probe
local realIsSecret = ns.Helpers.IsSecretValue
ns.Helpers.IsSecretValue = function() return false end
-- NOTE: IsSecretValue is captured at load time by cast_engine, so the probe
-- test must reload the module with the always-false checker.
local ns2 = { Helpers = { IsSecretValue = function() return false end } }
assert(loadfile("core/safecall.lua"))("QUI", ns2)
assert(loadfile("core/cast_engine.lua"))("QUI", ns2)
ns.Helpers.IsSecretValue = realIsSecret

castingInfo = { "Shadow Bolt", "Shadow Bolt", 136197, secretStart, secretEnd, false, "castid", false, 686 }
channelInfo = nil
castingDuration = { GetRemainingDuration = function() return 1.5 end }

local _, _, _, _, _, _, _, _, _, _, probeSecret = ns2.CastEngine.GetCastInfo("target")
if not probeSecret then fail("arithmetic probe must flag secret timing") end

-- IsSecretValue path on the primary instance
local _, _, _, _, _, _, _, _, _, sDurObj, sSecret = CastEngine.GetCastInfo("target")
if not sSecret then fail("IsSecretValue must flag secret timing") end

---------------------------------------------------------------------------
-- ResolveNonPlayerTiming ladder
---------------------------------------------------------------------------
local barWithEngine = { SetTimerDuration = function() end }
local barWithout = {}

-- secret + engine-capable bar -> timer-driven
local canShow, timerDriven = CastEngine.ResolveNonPlayerTiming("Spell", secretStart, secretEnd, sDurObj, barWithEngine, true)
if not canShow or not timerDriven then fail("secret+engine must be timer-driven") end

-- plain timing -> direct times in seconds
local canShow2, timerDriven2, st, et = CastEngine.ResolveNonPlayerTiming("Spell", 1000, 3500, nil, barWithEngine, false)
if not canShow2 or timerDriven2 then fail("plain timing must not be timer-driven") end
if st ~= 1.0 or et ~= 3.5 then fail("plain timing conversion to seconds") end

-- secret timing, no IsSecretValue flag, engine-capable -> falls through
-- arithmetic failure to the engine-driven fallback
local canShow3, timerDriven3 = CastEngine.ResolveNonPlayerTiming("Spell", secretStart, secretEnd, sDurObj, barWithEngine, false)
if not canShow3 or not timerDriven3 then fail("secret arithmetic fallback must be timer-driven") end

-- secret timing, no duration object, no engine -> cannot show
local canShow4 = CastEngine.ResolveNonPlayerTiming("Spell", secretStart, secretEnd, nil, barWithout, true)
if canShow4 then fail("secret without engine support must not show") end

-- no spell -> cannot show
local canShow5 = CastEngine.ResolveNonPlayerTiming(nil, 1000, 3500, sDurObj, barWithEngine, false)
if canShow5 then fail("nil spellName must not show") end

---------------------------------------------------------------------------
-- ApplyTimerDriven: direction pass-through + legacy signature fallback
---------------------------------------------------------------------------
local calls = {}
local modernBar = {
    SetTimerDuration = function(self, durObj, base, direction)
        calls[#calls + 1] = { durObj = durObj, base = base, direction = direction }
    end,
}
local dur = { GetRemainingDuration = function() return 2 end }
if not CastEngine.ApplyTimerDriven(modernBar, dur, 1) then fail("ApplyTimerDriven must succeed") end
if #calls ~= 1 or calls[1].durObj ~= dur or calls[1].base ~= 0 or calls[1].direction ~= 1 then
    fail("ApplyTimerDriven must pass (durObj, 0, direction)")
end

local legacyCalls = 0
local legacyBar = {
    SetTimerDuration = function(self, durObj, base, direction)
        if direction ~= nil then error("legacy signature") end
        legacyCalls = legacyCalls + 1
    end,
}
if not CastEngine.ApplyTimerDriven(legacyBar, dur, 0) then fail("legacy fallback must succeed") end
if legacyCalls ~= 1 then fail("legacy fallback must retry without direction") end

if CastEngine.ApplyTimerDriven(barWithout, dur, 0) then fail("bar without SetTimerDuration must return false") end
if CastEngine.ApplyTimerDriven(modernBar, nil, 0) then fail("nil durationObj must return false") end

---------------------------------------------------------------------------
-- GetDurationSeconds: getter chain + secret skip
---------------------------------------------------------------------------
local d1 = { GetTotalDuration = function() return 8 end }
if CastEngine.GetDurationSeconds(d1) ~= 8 then fail("GetDurationSeconds primary getter") end

local d2 = {
    GetTotalDuration = function() return MakeSecret("total") end,
    GetRemaining = function() return 3 end,
}
if CastEngine.GetDurationSeconds(d2) ~= 3 then fail("GetDurationSeconds must skip secret getters") end
if CastEngine.GetDurationSeconds(nil) ~= nil then fail("GetDurationSeconds(nil)") end
if CastEngine.GetDurationSeconds({}) ~= nil then fail("GetDurationSeconds no getters") end

---------------------------------------------------------------------------
-- UpdateTimerText: memoized getter + SetFormattedText sink
---------------------------------------------------------------------------
local written = {}
local timeText = { SetFormattedText = function(self, fmt, v) written[#written + 1] = { fmt = fmt, v = v } end }
local getterLookups = 0
local durObjMeta = {}
durObjMeta.__index = function(t, k)
    if k == "GetRemainingDuration" then
        getterLookups = getterLookups + 1
        return function() return 1.25 end
    end
    return nil
end
local memoDur = setmetatable({}, durObjMeta)
local bar = { timeText = timeText, durationObj = memoDur }

CastEngine.UpdateTimerText(bar)
CastEngine.UpdateTimerText(bar)
if #written ~= 2 then fail("UpdateTimerText must write each tick") end
if written[1].fmt ~= "%.1f" or written[1].v ~= 1.25 then fail("UpdateTimerText format contract (%.1f)") end
if getterLookups ~= 1 then fail("UpdateTimerText must memoize the getter lookup (got " .. getterLookups .. ")") end

-- Secret remaining flows straight through to the sink
local secretRem = MakeSecret("remaining")
bar.durationObj = { GetRemainingDuration = function() return secretRem end }
CastEngine.UpdateTimerText(bar)
if written[3].v ~= secretRem then fail("secret remaining must pass through to SetFormattedText") end

print("OK: cast_engine_test")
