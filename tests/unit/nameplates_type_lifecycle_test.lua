local function fail(msg)
    print("FAIL: nameplates_type_lifecycle_test - " .. msg)
    os.exit(1)
end

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

CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame(nil)
C_Timer = {
    After = function(_, fn) end,
    NewTicker = function(interval, fn)
        local t = { fn = fn, cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        return t
    end,
}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local world = {
    units = {},
}
local function U(token) return world.units[token] end

UnitExists = function(u) local d = U(u) return d ~= nil and d.exists ~= false end
local aliases = {}
UnitIsUnit = function(a, b)
    if a == b then return true end
    if aliases[a] == b or aliases[b] == a then return true end
    return false
end
local raidMarks = {}
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

local bases = {}
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

local hooks = {}
hooksecurefunc = function(target, method, fn)
    hooks[target] = hooks[target] or {}
    hooks[target][method] = hooks[target][method] or {}
    table.insert(hooks[target][method], fn)
    local orig = target[method] or noop
    target[method] = function(...)
        orig(...)
        for _, h in ipairs(hooks[target][method]) do h(...) end
    end
end

NamePlateDriverFrame = NewFrame(UIParent)
NamePlateDriverFrame.OnNamePlateAdded = function() end
NamePlateDriverFrame.UpdateNamePlateOptions = function() end

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

local function test(n, f) print(n); f(); print("  ok") end

world.units.nameplate1 = {
    canAttack = true, reaction = 2, health = 750, maxHealth = 1000, name = "Boar",
    classification = "normal", level = 80, isPlayer = false,
    isMinion = false, isOtherPet = false, treatAsPlayer = false,
}
NewBase("nameplate1")
local plate = NP.Driver.BuildEnemyPlate("nameplate1", bases.nameplate1)
local unitState = world.units.nameplate1

test("ComputeUnitState stamps npType on the plate", function()
    unitState.classification = "worldboss"
    NP.Driver.ComputeUnitState(plate)
    if plate.npType ~= "bossElite" then
        fail("expected bossElite, got " .. tostring(plate.npType))
    end
end)

test("RefreshPlateType reports a change and updates the cache", function()
    unitState.classification = "normal"
    NP.Driver.ComputeUnitState(plate)
    unitState.classification = "elite"
    if NP.Driver.RefreshPlateType(plate) ~= true then
        fail("a classification change must report true")
    end
    if plate.npType ~= "bossElite" then fail("cache was not updated") end
end)

test("RefreshPlateType reports no change when the type is stable", function()
    unitState.classification = "normal"
    NP.Driver.ComputeUnitState(plate)
    if NP.Driver.RefreshPlateType(plate) ~= false then
        fail("an unchanged type must report false")
    end
end)

test("UNIT_CLASSIFICATION_CHANGED drives the type refresh through the plate's own OnEvent", function()
    unitState.classification = "normal"
    NP.Driver.ComputeUnitState(plate)
    if plate.npType ~= "enemyNPC" then
        fail("setup: expected enemyNPC, got " .. tostring(plate.npType))
    end

    local onEvent = plate:GetScript("OnEvent")
    if type(onEvent) ~= "function" then fail("the plate has no OnEvent handler") end

    local restyles = 0
    local realRestyle = NP.RestyleActivePlates
    NP.RestyleActivePlates = function(...)
        restyles = restyles + 1
        return realRestyle(...)
    end

    unitState.classification = "rareelite"
    onEvent(plate, "UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    if plate.npType ~= "bossElite" then
        fail("the event must refresh npType, got " .. tostring(plate.npType))
    end
    if restyles ~= 1 then
        fail("a type change must restyle active plates once, saw " .. restyles)
    end

    unitState.classification = "elite"
    onEvent(plate, "UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    if plate.npType ~= "bossElite" then
        fail("elite and rareelite are both bossElite, got " .. tostring(plate.npType))
    end
    if restyles ~= 1 then
        fail("a classification change that leaves the type alone must not restyle, saw " .. restyles)
    end

    NP.RestyleActivePlates = realRestyle
end)

test("releasing a plate clears npType", function()
    NP.Driver.ComputeUnitState(plate)
    NP.Driver.ClearUnit(plate)
    if plate.npType ~= nil then fail("npType must be cleared on release") end
end)

print("OK: nameplates_type_lifecycle_test")
