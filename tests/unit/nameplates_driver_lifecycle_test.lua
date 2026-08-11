-- tests/unit/nameplates_driver_lifecycle_test.lua
-- Run: lua tests/unit/nameplates_driver_lifecycle_test.lua
--
-- Driver lifecycle against stubbed C_NamePlate/events
-- (plans/009-nameplates.md test plan): ADDED builds and registers a plate,
-- REMOVED releases to the pool with exhaustive ClearUnit field hygiene,
-- token-swap on a health tick rebinds in place, and suppression is
-- unconditional-on-added / restored-on-removed.

local function fail(msg)
    print("FAIL: nameplates_driver_lifecycle_test - " .. msg)
    os.exit(1)
end

---------------------------------------------------------------------------
-- WoW frame environment
---------------------------------------------------------------------------
local function noop() end

local function NewRegion(parent)
    local r = {
        _parent = parent,
        _shown = true,
        _alpha = 1,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop, SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetWidth = noop, SetHeight = noop,
        SetColorTexture = noop, SetVertexColor = noop, SetTexture = noop,
        SetAlpha = function(self, a) self._alpha = a end,
        GetAlpha = function(self) return self._alpha end,
        SetHorizTile = noop, SetVertTile = noop, SetTexCoord = noop,
        AddMaskTexture = noop, SetBlendMode = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetText = noop, SetFormattedText = noop, SetTextColor = noop, SetFont = noop,
        SetJustifyH = noop, SetDrawLayer = noop, SetShadowOffset = noop, SetShadowColor = noop,
    }
    return r
end

local function NewFrame(parent)
    local f = NewRegion(parent)
    f._events = {}
    f._scripts = {}
    f._level = 1
    f._minMax = nil
    f._value = nil
    f.RegisterEvent = function(self, e) self._events[e] = "all" end
    f.RegisterUnitEvent = function(self, e, u) self._events[e] = u end
    f.UnregisterEvent = function(self, e) self._events[e] = nil end
    f.UnregisterAllEvents = function(self) for k in pairs(self._events) do self._events[k] = nil end end
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.EnableMouse = noop
    f.SetFrameLevel = function(self, l) self._level = l end
    f.GetFrameLevel = function(self) return self._level end
    f.IsShown = function(self) return self._shown end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateMaskTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    f.SetDrawEdge = noop
    f.SetHideCountdownNumbers = noop
    f.SetCooldownFromDurationObject = noop
    f.SetCountdownFormatter = noop
    f.Clear = noop
    f.GetRegions = function() return nil end
    f.SetStatusBarTexture = noop
    f.GetStatusBarTexture = function(self) return self._barTex or nil end
    f.SetStatusBarColor = function(self, r, g, b) self._color = { r, g, b } end
    f.SetMinMaxValues = function(self, lo, hi) self._minMax = { lo, hi } end
    f.SetValue = function(self, v) self._value = v end
    f.SetStackingBoundsFrame = function(self, frame) self._stackBounds = frame end
    return f
end

local createdFrames = {}
CreateFrame = function(_, _, parent)
    local f = NewFrame(parent)
    createdFrames[#createdFrames + 1] = f
    return f
end
UIParent = NewFrame(nil)
local tickers = {}
C_Timer = {
    After = function(_, fn) end,
    NewTicker = function(interval, fn)
        local t = { fn = fn, cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- Unit world state, controllable per test
local world = {
    units = {},   -- [token] = { exists, canAttack, reaction, isPlayer, class, health, maxHealth }
}
local function U(token) return world.units[token] end

UnitExists = function(u) local d = U(u) return d ~= nil and d.exists ~= false end
-- unit aliasing: aliases.target / aliases.mouseover point at a nameplate token
local aliases = {}
UnitIsUnit = function(a, b)
    if a == b then return true end
    if aliases[a] == b or aliases[b] == a then return true end
    return false
end
local raidMarks = {}   -- [token] = index
GetRaidTargetIndex = function(u) return raidMarks[u] end
SetRaidTargetIconTexture = function(tex, index) tex._markIndex = index end
UnitCanAttack = function(_, u) local d = U(u) return d and d.canAttack == true end
UnitIsPlayer = function(u) local d = U(u) return d and d.isPlayer == true end
UnitReaction = function(u) local d = U(u) return d and d.reaction or 2 end
UnitClass = function(u) local d = U(u) return "x", d and d.class or nil end
UnitIsTapDenied = function() return false end
UnitAffectingCombat = function() return true end
UnitThreatSituation = function() return nil end
UnitHealth = function(u) local d = U(u) return d and d.health or 0 end
UnitHealthMax = function(u) local d = U(u) return d and d.maxHealth or 1 end
UnitGetTotalAbsorbs = function() return 0 end
UnitIsDeadOrGhost = function() return false end
UnitName = function(u) local d = U(u) return d and d.name or "Stub" end
UnitHealthPercent = function() return 55 end
UnitClassification = function(u) local d = U(u) return d and d.classification end
UnitLevel = function(u) local d = U(u) return d and d.level end
UnitIsMinion = function(u) local d = U(u) return d and d.isMinion end
UnitIsOtherPlayersPet = function(u) local d = U(u) return d and d.isOtherPet end
UnitTreatAsPlayerForDisplay = function(u) local d = U(u) return d and d.treatAsPlayer end
CurveConstants = { ScaleTo100 = {} }
IsInInstance = function() return false, "none" end
UnitGroupRolesAssigned = function() return "DAMAGER" end
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.6, b = 0.9 } }
SetCVar = noop
InCombatLockdown = function() return false end
AbbreviateNumbers = nil

-- Blizzard nameplate bases
local bases = {}   -- [token] = base frame
local function NewBase(token)
    local base = NewFrame(UIParent)
    base.unitToken = token
    base.UnitFrame = NewFrame(base)
    base.UnitFrame.HealthBarsContainer = NewFrame(base.UnitFrame)
    base.UnitFrame.castBar = NewFrame(base.UnitFrame)
    base.UnitFrame.RaidTargetFrame = NewFrame(base.UnitFrame)
    base.UnitFrame.ClassificationFrame = NewFrame(base.UnitFrame)
    base.UnitFrame.AurasFrame = NewFrame(base.UnitFrame)
    base.UnitFrame.PlayerLevelDiffFrame = NewFrame(base.UnitFrame)
    base.UnitFrame.SoftTargetFrame = NewFrame(base.UnitFrame)
    bases[token] = base
    return base
end

C_NamePlate = {
    GetNamePlateForUnit = function(token) return bases[token] end,
    SetNamePlateSize = noop,
}
C_CVar = nil
C_TooltipInfo = nil
Enum = { NamePlateType = { Friendly = 0, Enemy = 1 } }

-- hooksecurefunc capture (frame-method form only, as the driver uses)
local hooks = {}
hooksecurefunc = function(target, method, fn)
    hooks[target] = hooks[target] or {}
    hooks[target][method] = hooks[target][method] or {}
    table.insert(hooks[target][method], fn)
    -- emulate post-hook by wrapping
    local orig = target[method] or noop
    target[method] = function(...)
        orig(...)
        for _, h in ipairs(hooks[target][method]) do h(...) end
    end
end

NamePlateDriverFrame = NewFrame(UIParent)
NamePlateDriverFrame.OnNamePlateAdded = function() end
NamePlateDriverFrame.UpdateNamePlateOptions = function() end

---------------------------------------------------------------------------
-- QUI namespace
---------------------------------------------------------------------------
local settingsStore = nil
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        TruncateUTF8 = function(s, n) return type(s) == "string" and s:sub(1, n) or s end,
        GetModuleSettings = function(_, defaults)
            settingsStore = settingsStore or { enabled = true }
            return settingsStore
        end,
    },
    UIKit = {
        CreateBackground = function(parent) return NewRegion(parent) end,
        CreateBorderLines = noop,
        UpdateBorderLines = noop,
        CreateText = function(parent) return NewRegion(parent) end,
        ResolveFontPath = function() return "font.ttf" end,
        CreateIcon = function(parent)
            local f = NewFrame(parent)
            f.texture = NewRegion(f)
            f.border = NewRegion(f)
            return f
        end,
        UpdateIconLayout = noop,
    },
    Addon = {
        SetPixelPerfectSize = function(_, frame, w, h) frame:SetSize(w, h) end,
        Pixels = function(_, v) return v end,
        ApplyFont = noop,
    },
    LSM = nil,
}

-- Cast API stubs (no active casts by default)
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
GetPlayerInfoByGUID = function() return nil end

assert(loadfile("core/cast_engine.lua"))("QUI", ns)
assert(loadfile("core/classification.lua"))("QUI", ns)

local SUITE = {
    "shared.lua", "cvars.lua", "plate_type.lua", "plate_colors.lua", "plate_health.lua",
    "plate_castbar.lua", "plate_auras.lua", "plate_extras.lua",
    "friendly.lua", "driver.lua",
}
for _, file in ipairs(SUITE) do
    assert(loadfile("QUI_Nameplates/nameplates/" .. file))("QUI_Nameplates", ns)
end

local NP = ns.QUI_Nameplates
if not NP then fail("suite did not export ns.QUI_Nameplates") end

-- Find the driver's event frame: the frame registered for NAME_PLATE_UNIT_ADDED.
-- We can reach it via the perf registry the driver populates.
local driverEventFrame
for _, entry in ipairs(ns.QUI_PerfRegistry or {}) do
    if entry.name == "NameplateDriver" then driverEventFrame = entry.frame end
end
if not driverEventFrame then fail("driver perf registry entry missing") end
local dispatch = driverEventFrame:GetScript("OnEvent")
if not dispatch then fail("driver OnEvent handler missing") end

local function FireAdded(token)
    -- Blizzard's own dispatch runs first (hook fires suppression), then ours.
    NamePlateDriverFrame.OnNamePlateAdded(NamePlateDriverFrame, token)
    dispatch(driverEventFrame, "NAME_PLATE_UNIT_ADDED", token)
end
local function FireRemoved(token)
    dispatch(driverEventFrame, "NAME_PLATE_UNIT_REMOVED", token)
end

local function DrainDefer()
    for _, entry in ipairs(ns.QUI_PerfRegistry or {}) do
        if entry.name == "NameplateDefer" then
            local h = entry.frame:GetScript("OnUpdate")
            if h then h(entry.frame) end
        end
    end
end

local function test(n, f) print(n); f(); print("  ok") end

---------------------------------------------------------------------------
test("ADDED: enemy plate acquired, registered, health painted synchronously", function()
    world.units.nameplate1 = { canAttack = true, reaction = 2, health = 750, maxHealth = 1000, name = "Boar" }
    NewBase("nameplate1")
    FireAdded("nameplate1")

    local plate = NP.plates.nameplate1
    if not plate then fail("registry missing plates.nameplate1") end
    if plate._parent ~= bases.nameplate1 then fail("plate must parent to the Blizzard base") end
    if plate.healthBar._value ~= 750 then fail("health must paint synchronously on SetUnit") end
    if plate.healthBar._minMax[2] ~= 1000 then fail("health max not applied") end
    if plate._events.UNIT_HEALTH ~= "nameplate1" then fail("UNIT_HEALTH not unit-registered") end
    if plate._events.UNIT_THREAT_LIST_UPDATE ~= "nameplate1" then fail("threat event not registered") end
    if not plate.healthBar._color then fail("color must resolve synchronously") end
    if bases.nameplate1._stackBounds ~= plate.npStackBounds then fail("stacking bounds not attached") end
end)

test("suppression: unconditional on added, alpha pinned", function()
    local uf = bases.nameplate1.UnitFrame
    if uf._alpha ~= 0 then fail("UnitFrame alpha must be pinned to 0") end
    local hbc = uf.HealthBarsContainer
    if hbc._parent == uf then fail("HealthBarsContainer must be reparented away") end
    -- Blizzard resets alpha → hook re-pins
    uf:SetAlpha(1)
    if uf._alpha ~= 0 then fail("SetAlpha hook must re-pin alpha to 0 while suppressed") end
end)

test("GetPlateAnchor returns the health bar for managed units", function()
    local anchor = NP:GetPlateAnchor("nameplate1")
    if anchor ~= NP.plates.nameplate1.healthBar then fail("anchor must be the health bar") end
    if NP:GetPlateAnchor("nameplate9") ~= nil then fail("unmanaged unit must return nil") end
end)

test("deferred phase: name paints after one frame", function()
    DrainDefer()
    -- name text was written via SetText (stub records nothing, but the
    -- deferred flag must clear)
    if NP.plates.nameplate1.npDeferredPending then fail("deferred flag must clear") end
end)

test("token-swap self-heal: health tick rebinds to the base's current token", function()
    local plate = NP.plates.nameplate1
    world.units.nameplate7 = { canAttack = true, reaction = 4, health = 300, maxHealth = 400, name = "Swapped" }
    bases.nameplate1.unitToken = "nameplate7"
    plate._scripts.OnEvent(plate, "UNIT_HEALTH", "nameplate1")
    if NP.plates.nameplate1 ~= nil then fail("old token must leave the registry") end
    if NP.plates.nameplate7 ~= plate then fail("plate must rebind to the new token") end
    if plate._events.UNIT_HEALTH ~= "nameplate7" then fail("events must re-register for the new token") end
    if plate.healthBar._value ~= 300 then fail("rebind must repaint health") end
    bases.nameplate1.unitToken = "nameplate1"
end)

test("REMOVED: ClearUnit field hygiene + pool reuse + art restored", function()
    local plate = NP.plates.nameplate7
    FireRemoved("nameplate7")
    if NP.plates.nameplate7 then fail("registry must drop the unit") end
    for _, key in ipairs({ "unit", "npBase", "npLastMaxHP", "npLastR", "npReaction",
        "npIsPlayer", "npClassToken", "npTapDenied", "npInCombat", "npIsQuest",
        "npThreat", "npIsTarget", "npIsFocus", "npDeferredPending", "npAbsorbHidden" }) do
        if plate[key] ~= nil then fail("ClearUnit left field " .. key) end
    end
    if next(plate._events) then fail("ClearUnit must unregister all events") end
    if bases.nameplate1._stackBounds ~= nil then fail("stacking bounds must detach") end
    local uf = bases.nameplate1.UnitFrame
    if uf._alpha ~= 1 then fail("Blizzard art alpha must be restored on REMOVED") end
    if uf.HealthBarsContainer._parent ~= uf then fail("children must be reparented back") end

    -- pool reuse: the next ADDED must hand back the same frame object
    world.units.nameplate2 = { canAttack = true, reaction = 2, health = 10, maxHealth = 100 }
    NewBase("nameplate2")
    FireAdded("nameplate2")
    if NP.plates.nameplate2 ~= plate then fail("released plate must be reused from the pool") end
    FireRemoved("nameplate2")
end)

test("friendly routing: non-attackable units build through the standard path", function()
    world.units.nameplate3 = { canAttack = false, reaction = 6, health = 50, maxHealth = 100 }
    local base = NewBase("nameplate3")
    FireAdded("nameplate3")
    local plate = NP.plates.nameplate3
    if not plate then fail("friendly units must reach BuildEnemyPlate") end
    if plate.npType ~= "friendly" then fail("a non-attackable unit must resolve types.friendly") end
    if base.UnitFrame._alpha ~= 0 then fail("the friendly plate must keep Blizzard art suppressed") end
    FireRemoved("nameplate3")
    if base.UnitFrame._alpha ~= 1 then fail("REMOVED must hand Blizzard its art back") end
end)

---------------------------------------------------------------------------
-- Phase 4 extras: target/focus O(1), raid markers, mouseover ticker
---------------------------------------------------------------------------
-- Locate the extras event frame (registered for PLAYER_TARGET_CHANGED).
local extrasFrame
for _, f in ipairs(createdFrames) do
    if f._events and f._events.PLAYER_TARGET_CHANGED then extrasFrame = f end
end

test("target change is O(1): old plate cleared, new plate glows + recolors", function()
    if not extrasFrame then fail("extras event frame not found") end
    local fireExtras = extrasFrame:GetScript("OnEvent")

    world.units.nameplate5 = { canAttack = true, reaction = 2, health = 100, maxHealth = 100 }
    world.units.nameplate6 = { canAttack = true, reaction = 2, health = 100, maxHealth = 100 }
    NewBase("nameplate5"); NewBase("nameplate6")
    FireAdded("nameplate5"); FireAdded("nameplate6")
    DrainDefer()
    local p5, p6 = NP.plates.nameplate5, NP.plates.nameplate6

    -- target nameplate5
    bases.target = bases.nameplate5
    aliases.target = "nameplate5"
    fireExtras(extrasFrame, "PLAYER_TARGET_CHANGED")
    if p5.npIsTarget ~= true then fail("new target flag must set") end
    if not p5.npTargetGlow._shown then fail("target glow must show") end

    -- swap target to nameplate6
    bases.target = bases.nameplate6
    aliases.target = "nameplate6"
    fireExtras(extrasFrame, "PLAYER_TARGET_CHANGED")
    if p5.npIsTarget ~= false then fail("old target flag must clear") end
    if p5.npTargetGlow._shown then fail("old target glow must hide") end
    if p6.npIsTarget ~= true then fail("new target must flag") end

    -- clear target
    bases.target = nil
    aliases.target = nil
    fireExtras(extrasFrame, "PLAYER_TARGET_CHANGED")
    if p6.npIsTarget ~= false then fail("cleared target must unflag") end
end)

test("raid markers update on RAID_TARGET_UPDATE", function()
    local fireExtras = extrasFrame:GetScript("OnEvent")
    local p5 = NP.plates.nameplate5
    raidMarks.nameplate5 = 8  -- skull
    fireExtras(extrasFrame, "RAID_TARGET_UPDATE")
    if not p5.npRaidMarker._shown then fail("marker must show") end
    if p5.npRaidMarker._markIndex ~= 8 then fail("marker index must be 8 (skull)") end
    raidMarks.nameplate5 = nil
    fireExtras(extrasFrame, "RAID_TARGET_UPDATE")
    if p5.npRaidMarker._shown then fail("marker must hide when unmarked") end
end)

test("mouseover: highlight + ticker only while hovering", function()
    local fireExtras = extrasFrame:GetScript("OnEvent")
    local p5 = NP.plates.nameplate5
    local before = #tickers
    bases.mouseover = bases.nameplate5
    aliases.mouseover = "nameplate5"
    fireExtras(extrasFrame, "UPDATE_MOUSEOVER_UNIT")
    if p5.npHoverHighlight._alpha <= 0 then fail("hover highlight must show") end
    if #tickers ~= before + 1 then fail("hover ticker must start") end
    -- mouse leaves: tick notices and cleans up
    aliases.mouseover = nil
    bases.mouseover = nil
    tickers[#tickers].fn()
    if p5.npHoverHighlight._alpha ~= 0 then fail("hover highlight must clear") end
    if not tickers[#tickers].cancelled then fail("hover ticker must cancel") end
end)

test("extras recycle hygiene on REMOVED", function()
    local p5 = NP.plates.nameplate5
    bases.target = bases.nameplate5
    aliases.target = "nameplate5"
    extrasFrame:GetScript("OnEvent")(extrasFrame, "PLAYER_TARGET_CHANGED")
    FireRemoved("nameplate5")
    FireRemoved("nameplate6")
    if p5.npTargetGlow._shown then fail("target glow must hide on release") end
    bases.target = nil
    aliases.target = nil
end)

test("PEW re-asserts appearance: generation bumps and live plates restyle", function()
    -- Regression: plates styled during the loading screen used a not-yet-
    -- settled effective scale, and the appearance generation made those
    -- wrong sizes sticky. PLAYER_ENTERING_WORLD must bump the generation
    -- and restyle every live plate.
    world.units.nameplate8 = { canAttack = true, reaction = 2, health = 10, maxHealth = 100 }
    NewBase("nameplate8")
    FireAdded("nameplate8")
    local plate = NP.plates.nameplate8
    local genBefore = plate.npAppearanceGen
    dispatch(driverEventFrame, "PLAYER_ENTERING_WORLD")
    if NP.appearanceGen <= genBefore then fail("PEW must bump the appearance generation") end
    if plate.npAppearanceGen ~= NP.appearanceGen then fail("live plates must restyle to the new generation") end
    FireRemoved("nameplate8")
end)

test("disabled: added plates are ignored entirely", function()
    settingsStore.enabled = false
    world.units.nameplate4 = { canAttack = true, reaction = 2, health = 5, maxHealth = 10 }
    local base = NewBase("nameplate4")
    FireAdded("nameplate4")
    if NP.plates.nameplate4 then fail("disabled suite must not build plates") end
    if base.UnitFrame._alpha ~= 1 then fail("disabled suite must not suppress") end
    settingsStore.enabled = true
end)

print("OK: nameplates_driver_lifecycle_test")
