-- tests/unit/nameplates_castbar_test.lua
-- Run: lua tests/unit/nameplates_castbar_test.lua
--
-- Plate castbar via the shared cast engine: engine-driven fill via
-- SetTimerDuration (set once per cast), secret uninterruptible state routed
-- through SetAlphaFromBoolean (never branched), interrupted flash guarded
-- against late STOPs, shared 10 Hz ticker refcount, despawn teardown via
-- UnitExists.

local function fail(msg)
    print("FAIL: nameplates_castbar_test - " .. msg)
    os.exit(1)
end

local function noop() end

---------------------------------------------------------------------------
-- Frame environment (compact variant of the lifecycle test's stubs)
---------------------------------------------------------------------------
local function NewRegion(parent)
    return {
        _parent = parent, _shown = true, _alpha = 1,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop, SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetWidth = noop, SetHeight = noop,
        SetColorTexture = noop, SetVertexColor = noop,
        SetTexture = function(self, t) self._texture = t end,
        SetAlpha = function(self, a) self._alpha = a end,
        GetAlpha = function(self) return self._alpha end,
        SetAlphaFromBoolean = function(self, b, tA, fA)
            self._boolAlpha = { b, tA, fA }
        end,
        SetHorizTile = noop, SetVertTile = noop, SetTexCoord = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetText = function(self, t) self._text = t end,
        SetFormattedText = function(self, fmtStr, v)
            if fmtStr == "%s" then
                self._text = tostring(v)
            else
                self._text = string.format(fmtStr, tonumber(v) or 0)
            end
        end,
        SetTextColor = noop, SetFont = noop, SetJustifyH = noop,
    }
end

local createdFrames = {}
local function NewFrame(parent)
    local f = NewRegion(parent)
    f._events = {}
    f._scripts = {}
    f.SetFrameStrata = noop
    f.SetScale = function(self, s) self._scale = s end
    f.SetShown = function(self, s) if s then self:Show() else self:Hide() end end
    f.HookScript = noop
    f.RegisterEvent = function(self, e) self._events[e] = true end
    f.RegisterUnitEvent = function(self, e, u) self._events[e] = u end
    f.UnregisterAllEvents = function(self) for k in pairs(self._events) do self._events[k] = nil end end
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.EnableMouse = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 1 end
    f.IsShown = function(self) return self._shown end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    f.SetStatusBarTexture = noop
    f.GetStatusBarTexture = function() return nil end
    f.SetStatusBarColor = function(self, r, g, b) self._color = { r, g, b } end
    f.SetMinMaxValues = function(self, lo, hi) self._minMax = { lo, hi } end
    f.SetValue = function(self, v) self._value = v end
    f.SetTimerDuration = function(self, durObj, base, direction)
        self._timerDuration = { durObj, base, direction }
    end
    return f
end

CreateFrame = function(_, _, parent)
    local f = NewFrame(parent)
    createdFrames[#createdFrames + 1] = f
    return f
end
UIParent = NewFrame(nil)

-- Deterministic timer environment
local afterQueue = {}
local tickers = {}
C_Timer = {
    After = function(delay, fn) afterQueue[#afterQueue + 1] = { delay = delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn, cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}
local function RunAfterQueue()
    local q = afterQueue
    afterQueue = {}
    for _, item in ipairs(q) do item.fn() end
end
local function LiveTickers()
    local n = 0
    for _, t in ipairs(tickers) do if not t.cancelled then n = n + 1 end end
    return n
end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetTime = function() return 100 end
InCombatLockdown = function() return false end
SetCVar = noop

-- Secret simulation
local secrets = setmetatable({}, { __mode = "k" })
local function MakeSecret()
    local s = setmetatable({}, { __add = function() error("secret") end })
    secrets[s] = true
    return s
end

-- Cast world state
local cast = nil   -- current UnitCastingInfo tuple
local unitExists = true
UnitCastingInfo = function()
    if not cast then return nil end
    return cast.name, cast.name, cast.icon, cast.startMS, cast.endMS,
        false, false, cast.notInterruptible, cast.spellID
end
UnitChannelInfo = function() return nil end
UnitCastingDuration = function() return cast and cast.durationObj end
UnitChannelDuration = function() return nil end
UnitExists = function() return unitExists end
GetPlayerInfoByGUID = function(guid)
    if guid == "Player-1234" then
        return "loc", "MAGE", "race", "raceEn", 2, "Kicker"
    end
    return nil
end
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.6, b = 0.9, colorStr = "ff3fc7eb" } }

local typeSettings = {
    castbar = { enabled = true, height = 17, showTimer = true, interruptedHoldTime = 1.0 },
    health = { width = 156, texture = nil, borderSize = 1 },
    colors = {
        castInterruptible = { 0.7, 0.4, 0.9 },
        castUninterruptible = { 0.45, 0.45, 0.45 },
        castInterrupted = { 0.8, 0, 0 },
    },
}

local settings = {
    enabled = true,
    types = { enemyNPC = typeSettings },
}

local ns = {
    Helpers = {
        IsSecretValue = function(v) return secrets[v] == true end,
        SafeToNumber = function(v, fallback)
            if secrets[v] then return fallback or 0 end
            return tonumber(v) or fallback or 0
        end,
        TruncateUTF8 = function(s) return s end,
        GetModuleSettings = function() return settings end,
    },
    UIKit = {
        CreateBackground = function(parent) return NewRegion(parent) end,
        CreateBorderLines = noop,
        UpdateBorderLines = noop,
        CreateText = function(parent) return NewRegion(parent) end,
        ResolveFontPath = function() return "font.ttf" end,
    },
    Addon = {
        SetPixelPerfectSize = noop,
        Pixels = function(_, v) return v end,
        ApplyFont = noop,
    },
    LSM = nil,
}

assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/cast_engine.lua"))("QUI", ns)
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_castbar.lua"))("QUI_Nameplates", ns)

local NP = ns.QUI_Nameplates
local NPCastbar = NP.Castbar
if not NPCastbar or not NPCastbar.ProbeCast then fail("castbar module not loaded") end

-- Locate the cast dispatcher via the perf registry
local dispatcher
for _, entry in ipairs(ns.QUI_PerfRegistry or {}) do
    if entry.name == "NameplateCast" then dispatcher = entry.frame end
end
if not dispatcher then fail("cast dispatcher perf entry missing") end
local fire = dispatcher:GetScript("OnEvent")
if not fire then fail("cast dispatcher handler missing") end
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
    if not dispatcher._events[e] then fail("dispatcher missing event " .. e) end
end

-- Build a plate by hand (health bar stub + castbar Build/ApplyAppearance)
local function NewPlate(unit)
    local plate = NewFrame(UIParent)
    plate.unit = unit
    plate.npType = "enemyNPC"
    plate.healthBar = NewFrame(plate)
    NPCastbar.Build(plate)
    NPCastbar.ApplyAppearance(plate, typeSettings)
    NP.plates[unit] = plate
    return plate
end

local function test(n, f) print(n); f(); print("  ok") end

local plate = NewPlate("nameplate1")

---------------------------------------------------------------------------
test("START with secret timing: engine-driven fill, set once", function()
    local durObj = { GetRemainingDuration = function() return 1.5 end }
    cast = { name = "Pyroblast", icon = 135808, startMS = MakeSecret(), endMS = MakeSecret(),
             notInterruptible = false, spellID = 11366, durationObj = durObj }
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")
    local castBar = plate.castBar
    if not castBar._shown then fail("castbar must show") end
    if not castBar._timerDuration then fail("engine fill must go through SetTimerDuration") end
    if castBar._timerDuration[1] ~= durObj then fail("wrong duration object") end
    if castBar._timerDuration[3] ~= 0 then fail("casts must fill (direction 0)") end
    if plate.castIcon._texture ~= 135808 then fail("icon texture not set") end
    if plate.castSpellText._text ~= "Pyroblast" then fail("spell name not set") end
    if LiveTickers() ~= 1 then fail("timer-text ticker must start") end
end)

test("10 Hz tick writes remaining via %.1f", function()
    tickers[1].fn()
    if plate.castBar.timeText._text ~= "1.5" then
        fail("expected '1.5', got " .. tostring(plate.castBar.timeText._text))
    end
end)

test("secret uninterruptible routes through SetAlphaFromBoolean", function()
    local secretBool = MakeSecret()
    cast.notInterruptible = secretBool
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")
    local overlay = plate.castUninterruptibleOverlay
    if not overlay._boolAlpha or overlay._boolAlpha[1] ~= secretBool then
        fail("secret must flow into SetAlphaFromBoolean")
    end
    local c = plate.castBar._color
    if math.abs(c[1] - 0.7) > 1e-9 then fail("secret path must keep interruptible base color") end
end)

test("clean uninterruptible takes the direct color path", function()
    fire(dispatcher, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "nameplate1")
    local c = plate.castBar._color
    if math.abs(c[1] - 0.45) > 1e-9 then fail("clean uninterruptible must recolor grey") end
    if plate.castShield._alpha ~= 1 then fail("shield must show for clean uninterruptible") end
end)

test("INTERRUPTED: red flash + interrupter name, late STOP guarded", function()
    fire(dispatcher, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "castGUID", 11366, "Player-1234")
    local castBar = plate.castBar
    if not plate.npInterrupted then fail("interrupted latch must set") end
    if math.abs(castBar._color[1] - 0.8) > 1e-9 then fail("flash must recolor red") end
    if not plate.castSpellText._text:find("Kicker") then fail("interrupter name missing") end
    if not plate.castSpellText._text:find("ff3fc7eb") then fail("interrupter must be class-colored") end

    -- late STOP during the flash must not cut it short
    cast = nil
    fire(dispatcher, "UNIT_SPELLCAST_STOP", "nameplate1")
    if not castBar._shown then fail("late STOP must not end the interrupted flash") end

    -- hold timer expiry tears it down
    RunAfterQueue()
    if castBar._shown then fail("flash must end after the hold timer") end
    if plate.npInterrupted then fail("interrupted latch must clear") end
end)

test("INTERRUPTED with a SECRET interrupter GUID shows the bare label", function()
    -- Live 12.0 scar: the interrupter GUID is secret in restricted combat;
    -- comparing it (~= \"\") errored 7x per pull. It must fail soft.
    local durObj = { GetRemainingDuration = function() return 2 end }
    cast = { name = "Bolt", icon = 1, startMS = 0, endMS = 2000, notInterruptible = false,
             spellID = 1, durationObj = durObj }
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")
    local secretGUID = MakeSecret()
    fire(dispatcher, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "castGUID", 1, secretGUID)
    if plate.castSpellText._text ~= "Interrupted" then
        fail("secret GUID must degrade to the bare label, got " .. tostring(plate.castSpellText._text))
    end
    RunAfterQueue()
end)

test("ticker refcount: cancelled when the last cast stops", function()
    if LiveTickers() ~= 0 then fail("ticker must cancel when no plate is casting") end
    local durObj = { GetRemainingDuration = function() return 2 end }
    cast = { name = "Bolt", icon = 1, startMS = 0, endMS = 2000, notInterruptible = false,
             spellID = 1, durationObj = durObj }
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")
    if LiveTickers() ~= 1 then fail("ticker must restart for a new cast") end
    fire(dispatcher, "UNIT_SPELLCAST_STOP", "nameplate1")
    if LiveTickers() ~= 0 then fail("ticker must cancel on stop") end
end)

test("despawn teardown: tick uses UnitExists, not cast info truthiness", function()
    local durObj = { GetRemainingDuration = function() return 2 end }
    cast = { name = "Bolt", icon = 1, startMS = MakeSecret(), endMS = MakeSecret(),
             notInterruptible = false, spellID = 1, durationObj = durObj }
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")
    unitExists = false
    -- find the live ticker and run it
    for _, t in ipairs(tickers) do
        if not t.cancelled then t.fn() end
    end
    if plate.castBar._shown then fail("despawned unit must tear the castbar down") end
    unitExists = true
end)

test("StopCast recycle hygiene", function()
    if plate.castBar.durationObj ~= nil then fail("durationObj must clear") end
    if plate.castBar._durationGetterObj ~= nil then fail("memoized getter must clear") end
    if plate.npCasting then fail("npCasting must clear") end
end)

---------------------------------------------------------------------------
-- v1.1: kick tick
---------------------------------------------------------------------------
local kickCD = { onCooldown = false }
IsPlayerSpell = function(id) return id == 1766 end -- Kick
IsSpellKnown = function() return false end
local kickCDObj = { _kick = true }
C_Spell = {
    GetSpellCooldown = function(id)
        if not kickCD.onCooldown then return { startTime = 0, duration = 0 } end
        return { startTime = 90, duration = 15 } -- GetTime()=100 → 5s remaining
    end,
    GetSpellCooldownDuration = function(id) return kickCDObj end,
}

-- locate the kick event frame (registered for SPELL_UPDATE_COOLDOWN)
local kickEventFrame
for _, f in ipairs(createdFrames) do
    if f._events.SPELL_UPDATE_COOLDOWN then kickEventFrame = f end
end

test("kick tick: engine-drained CD bar pinned to the cast fill edge", function()
    if not kickEventFrame then fail("kick event frame not found") end
    -- the resolver cached "no interrupt known" before IsPlayerSpell existed;
    -- SPELLS_CHANGED re-arms it (same as learning a spell in-game)
    kickEventFrame._scripts.OnEvent(kickEventFrame, "SPELLS_CHANGED")
    kickCD.onCooldown = true
    local castTotal = 3.5
    local durObj = {
        GetRemainingDuration = function() return 2 end,
        GetTotalDuration = function() return castTotal end,
    }
    cast = { name = "Big Cast", icon = 1, startMS = MakeSecret(), endMS = MakeSecret(),
             notInterruptible = false, spellID = 5, durationObj = durObj }
    -- castBar fill texture must exist for the anchor re-pin
    plate.castBar.GetStatusBarTexture = function(self) return self._fill or NewRegion(self) end
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")

    local kickBar = plate.kickBar
    if not kickBar._shown then fail("kick tick must show while the kick is on cooldown") end
    if not kickBar._minMax or kickBar._minMax[2] ~= castTotal then
        fail("kick bar domain must be the cast's total duration")
    end
    if not kickBar._timerDuration or kickBar._timerDuration[1] ~= kickCDObj then
        fail("kick bar must drain the interrupt's cooldown DurationObject")
    end
    if kickBar._timerDuration[3] ~= 1 then fail("kick CD must DRAIN (direction 1)") end
end)

test("kick tick: cooldown event re-pins; ready kick hides the tick", function()
    kickCD.onCooldown = false
    kickEventFrame._scripts.OnEvent(kickEventFrame, "SPELL_UPDATE_COOLDOWN")
    if plate.kickBar._shown then fail("a ready interrupt must hide the tick") end
    fire(dispatcher, "UNIT_SPELLCAST_STOP", "nameplate1")
end)

test("kick tick: uninterruptible-agnostic, disabled setting hides", function()
    plate.npKickTickEnabled = false
    kickCD.onCooldown = true
    local durObj = { GetRemainingDuration = function() return 2 end, GetTotalDuration = function() return 3 end }
    cast = { name = "Bolt", icon = 1, startMS = 0, endMS = 3000, notInterruptible = false,
             spellID = 5, durationObj = durObj }
    fire(dispatcher, "UNIT_SPELLCAST_START", "nameplate1")
    if plate.kickBar._shown then fail("disabled kick tick must not show") end
    fire(dispatcher, "UNIT_SPELLCAST_STOP", "nameplate1")
    plate.npKickTickEnabled = true
end)

---------------------------------------------------------------------------
-- v1.1: lift overlay
---------------------------------------------------------------------------
test("lift overlay: real bar reparented into a pinned high-strata container", function()
    typeSettings.castbar.liftOverlay = true
    NPCastbar.ApplyAppearance(plate, typeSettings)
    local container = plate.npLiftContainer
    if not container then fail("lift container must exist") end
    if plate.castBar._parent ~= container then fail("the REAL castbar must reparent into the container") end
    if container._parent ~= UIParent then fail("container must parent to UIParent") end

    typeSettings.castbar.liftOverlay = false
    NPCastbar.ApplyAppearance(plate, typeSettings)
    if plate.castBar._parent ~= plate then fail("disabling must reparent the castbar back onto the plate") end
    if container._shown then fail("disabled lift must hide the container") end
end)

print("OK: nameplates_castbar_test")
