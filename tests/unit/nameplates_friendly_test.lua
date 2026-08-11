local function fail(msg)
    print("FAIL: nameplates_friendly_test - " .. msg)
    os.exit(1)
end

local function noop() end

local function NewRegion(parent)
    return {
        _parent = parent, _shown = true, _alpha = 1,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop,
        SetPoint = function(self, point, ...) self._points = { point, ... } end,
        ClearAllPoints = function(self) self._points = nil end,
        SetSize = noop, SetWidth = noop, SetHeight = noop,
        SetColorTexture = noop, SetVertexColor = noop, SetTexture = noop,
        SetAlpha = function(self, a) self._alpha = a end,
        GetAlpha = function(self) return self._alpha end,
        SetHorizTile = noop, SetVertTile = noop, SetTexCoord = noop,
        AddMaskTexture = noop, SetBlendMode = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetText = function(self, t) self._text = t end,
        SetFormattedText = noop, SetTextColor = noop, SetFont = noop,
        SetJustifyH = noop,
    }
end

local createdFrames = {}
local function NewFrame(parent)
    local f = NewRegion(parent)
    f._events = {}
    f._scripts = {}
    f._level = 1
    f.RegisterEvent = function(self, e) self._events[e] = "all" end
    f.RegisterUnitEvent = function(self, e, u) self._events[e] = u end
    f.UnregisterAllEvents = function(self) for k in pairs(self._events) do self._events[k] = nil end end
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.EnableMouse = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 1 end
    f.IsShown = function(self) return self._shown end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateMaskTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    f.SetStatusBarTexture = noop
    f.GetStatusBarTexture = function() return nil end
    f.SetStatusBarColor = function(self, r, g, b) self._color = { r, g, b } end
    f.SetMinMaxValues = function(self, lo, hi) self._minMax = { lo, hi } end
    f.SetValue = function(self, v) self._value = v end
    f.SetStackingBoundsFrame = function(self, frame) self._stackBounds = frame end
    f.SetDrawEdge = noop
    f.SetHideCountdownNumbers = noop
    f.SetCooldownFromDurationObject = noop
    f.Clear = noop
    return f
end

CreateFrame = function(kind, _, parent)
    local f = NewFrame(parent)
    if kind == "AuraContainer" then
        f._enabled = nil
        f.SetUnit = function(self, unit) self._unit = unit end
        f.SetEnabled = function(self, e) self._enabled = e end
    end
    createdFrames[#createdFrames + 1] = f
    return f
end
AuraContainerSortMethod = { Default = 0, Expiration = 4 }
_G.QUI = { AuraSkin = {
    Configure = noop,
    Restyle = noop,
    LayoutAnchor = function() return "TOPLEFT" end,
} }
UIParent = NewFrame(nil)
C_Timer = { After = function() end, NewTicker = function() return { Cancel = noop } end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local inCombat = false
InCombatLockdown = function() return inCombat end

local cvarWrites = {}
SetCVar = function(name, value) cvarWrites[name] = value end
GetTime = function() return 0 end

local QUI_FONT = "Interface\\AddOns\\QUI\\media\\fonts\\Test.ttf"

local world = { units = {} }
local function U(u) return world.units[u] end
UnitExists = function(u) local d = U(u) return d ~= nil end
UnitIsUnit = function(a, b) return a == b end
UnitCanAttack = function(_, u) local d = U(u) return d and d.canAttack == true end
UnitIsPlayer = function(u) local d = U(u) return d and d.isPlayer == true end
UnitReaction = function(u) local d = U(u) return d and d.reaction or 2 end
UnitClass = function(u) local d = U(u) return "x", d and d.class or nil end
UnitIsTapDenied = function() return false end
UnitAffectingCombat = function() return false end
UnitThreatSituation = function() return nil end
UnitHealth = function(u) local d = U(u) return d and d.health or 0 end
UnitHealthMax = function(u) local d = U(u) return d and d.maxHealth or 1 end
UnitGetTotalAbsorbs = function() return 0 end
UnitIsDeadOrGhost = function() return false end
UnitName = function(u) local d = U(u) return d and d.name or "Friend" end
UnitHealthPercent = function() return 100 end
UnitClassification = function(u) local d = U(u) return d and d.classification end
UnitLevel = function(u) local d = U(u) return d and d.level end
UnitIsMinion = function(u) local d = U(u) return d and d.isMinion end
UnitIsOtherPlayersPet = function(u) local d = U(u) return d and d.isOtherPet end
UnitTreatAsPlayerForDisplay = function(u) local d = U(u) return d and d.treatAsPlayer end
CurveConstants = nil
IsInInstance = function() return world.inInstance == true, world.instanceType or "none" end
UnitGroupRolesAssigned = function() return "DAMAGER" end
GetRaidTargetIndex = function() return nil end
SetRaidTargetIconTexture = noop
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 0.96, b = 0.98 } }
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
GetPlayerInfoByGUID = function() return nil end
C_TooltipInfo = nil
C_CurveUtil = nil
C_UnitAuras = nil
C_StringUtil = nil
CreateColor = nil
Enum = {}

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
    GetNamePlateForUnit = function(t) return bases[t] end,
    SetNamePlateSize = noop,
    GetNamePlates = function()
        local out = {}
        for _, b in pairs(bases) do out[#out + 1] = b end
        return out
    end,
}
hooksecurefunc = function(target, method, fn)
    local orig = target[method] or noop
    target[method] = function(...) orig(...); fn(...) end
end
NamePlateDriverFrame = NewFrame(UIParent)
NamePlateDriverFrame.OnNamePlateAdded = function() end
NamePlateDriverFrame.UpdateNamePlateOptions = function() end

local settings = {
    enabled = true,
    friendly = { enabled = true, showInWorld = true, showInInstances = false },
    health = {}, name = {}, castbar = {}, colors = {}, highlight = {}, raidMarker = {},
    font = { face = "", outline = "THICKOUTLINE" },
    auras = { enabled = true, elements = {} }, cvars = {},
}
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        TruncateUTF8 = function(s) return s end,
        GetModuleSettings = function() return settings end,
    },
    UIKit = {
        CreateBackground = function(parent) return NewRegion(parent) end,
        CreateBorderLines = noop, UpdateBorderLines = noop,
        CreateText = function(parent) return NewRegion(parent) end,
        ResolveFontPath = function() return QUI_FONT end,
        CreateIcon = function(parent) local f = NewFrame(parent); f.texture = NewRegion(f); f.border = NewRegion(f); return f end,
        UpdateIconLayout = noop,
    },
    Addon = {
        SetPixelPerfectSize = noop,
        Pixels = function(_, v) return v end,
        ApplyFont = noop,
    },
    AuraEvents = { Subscribe = noop },
    AuraSlots = { Park = noop, Sync = function() return true end },
    LSM = nil,
}

assert(loadfile("core/cast_engine.lua"))("QUI", ns)
assert(loadfile("core/classification.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("core/aura_glue.lua"))("QUI", ns)
assert(loadfile("core/aura_surface.lua"))("QUI", ns)
for _, file in ipairs({ "shared.lua", "cvars.lua", "plate_type.lua", "plate_colors.lua", "plate_health.lua",
    "plate_castbar.lua", "plate_auras.lua", "plate_extras.lua", "friendly.lua", "driver.lua" }) do
    assert(loadfile("QUI_Nameplates/nameplates/" .. file))("QUI_Nameplates", ns)
end

local NP = ns.QUI_Nameplates
local Friendly = NP.Friendly

local driverEventFrame
for _, entry in ipairs(ns.QUI_PerfRegistry or {}) do
    if entry.name == "NameplateDriver" then driverEventFrame = entry.frame end
end
local dispatch = driverEventFrame:GetScript("OnEvent")

local function FireAdded(token)
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

local function AuraContainersVisible(plate)
    local pool = plate._quiAuraContainers
    if not pool then return false end
    for i = 1, #pool do
        if pool[i]._enabled == true and pool[i]._shown then return true end
    end
    return false
end

local function test(n, f) print(n); f(); print("  ok") end

local function SetFriendlyLook(mode)
    NP.NormalizeTypes(settings)
    settings.types.friendly.renderMode = mode
end

test("an unattackable unit builds through the standard plate path", function()
    world.units.nameplate1 = { canAttack = false, reaction = 6, isPlayer = true, class = "PRIEST",
        health = 80, maxHealth = 100, name = "Healer" }
    local base = NewBase("nameplate1")
    FireAdded("nameplate1")

    local plate = NP.plates.nameplate1
    if not plate then fail("a friendly unit must reach BuildEnemyPlate") end
    if plate.npType ~= "friendly" then
        fail("the promoted plate must resolve types.friendly, got " .. tostring(plate.npType))
    end
    if base.UnitFrame._alpha ~= 0 then fail("the promoted plate must suppress Blizzard art") end
    if plate.healthBar._value ~= 80 then fail("the promoted plate must paint health") end
    if NP:GetPlateAnchor("nameplate1") ~= plate.healthBar then fail("GetPlateAnchor must cover the promoted plate") end
end)

test("the friendly build entry points are gone", function()
    if Friendly.BuildFriendlyPlate ~= nil then fail("BuildFriendlyPlate must be removed") end
    if Friendly.HandleAdded ~= nil then fail("HandleAdded must be removed") end
    if Friendly.HandleRemoved ~= nil then fail("HandleRemoved must be removed") end
    if Friendly.UpdateHealth ~= nil then fail("UpdateHealth must be removed") end
    if Friendly.UpdateName ~= nil then fail("UpdateName must be removed") end
    if NP.friendlyPlates ~= nil then fail("the friendlyPlates registry must be removed") end
end)

test("UNIT_FLAGS re-resolves the plate type instead of releasing the plate", function()
    local plate = NP.plates.nameplate1
    world.units.nameplate1.canAttack = true
    plate._scripts.OnEvent(plate, "UNIT_FLAGS", "nameplate1")
    if NP.plates.nameplate1 ~= plate then fail("an attackability change must not release the plate") end
    if plate.npType ~= "enemyPlayer" then
        fail("UNIT_FLAGS must re-resolve the type, got " .. tostring(plate.npType))
    end
    if plate.npAppearanceType ~= "enemyPlayer" then fail("the re-resolved type must restyle the plate") end

    world.units.nameplate1.canAttack = false
    plate._scripts.OnEvent(plate, "UNIT_FLAGS", "nameplate1")
    if NP.plates.nameplate1 ~= plate then fail("demotion must not release the plate either") end
    if plate.npType ~= "friendly" then fail("demotion must resolve back to friendly") end
end)

test("REMOVED releases the plate and hands Blizzard its art back", function()
    FireRemoved("nameplate1")
    if NP.plates.nameplate1 then fail("the plate must release") end
    if bases.nameplate1.UnitFrame._alpha ~= 1 then fail("Blizzard art must be restored") end
end)

test("GetEffectiveMode is a visibility verdict, never a look", function()
    if Friendly.GetEffectiveMode({ enabled = true }, { inInstance = false }) ~= "show" then
        fail("show in the world stays show")
    end
    if Friendly.GetEffectiveMode({ enabled = true, showInInstances = true }, { inInstance = true }) ~= "show" then
        fail("an instance must no longer force a look onto friendly plates")
    end
    if Friendly.GetEffectiveMode({ enabled = true, showInInstances = false }, { inInstance = true }) ~= "off" then
        fail("showInInstances false in an instance must be off")
    end
    if Friendly.GetEffectiveMode({ enabled = false }, { inInstance = false }) ~= "off" then fail("off stays off") end
    if Friendly.GetEffectiveMode({ enabled = false }, { inInstance = true }) ~= "off" then fail("off stays off in an instance") end
    if Friendly.GetEffectiveMode({}, { inInstance = false }) ~= "show" then fail("an unset mode must default to show") end
end)

test("the Blizzard font handoff is gone", function()
    if Friendly.ApplyNameOnlyFont ~= nil then fail("ApplyNameOnlyFont must be removed") end
end)

test("the class-colour CVar follows the Friendly type's name config", function()
    settings.types.friendly.name.classColorPlayers = false
    settings.types.enemyNPC.name.classColorPlayers = true
    cvarWrites = {}
    Friendly.ApplyModeCVars()
    if cvarWrites.nameplateUseClassColorForFriendlyPlayerUnitNames ~= 0 then
        fail("classColorPlayers=false on types.friendly must write 0, got "
            .. tostring(cvarWrites.nameplateUseClassColorForFriendlyPlayerUnitNames))
    end

    settings.types.friendly.name.classColorPlayers = true
    cvarWrites = {}
    Friendly.ApplyModeCVars()
    if cvarWrites.nameplateUseClassColorForFriendlyPlayerUnitNames ~= 1 then
        fail("classColorPlayers=true on types.friendly must write 1")
    end
end)

test("Blizzard's name-only CVar mirrors the Friendly type's render mode", function()
    SetFriendlyLook("bars")
    cvarWrites = {}
    Friendly.ApplyModeCVars()
    if cvarWrites.nameplateShowOnlyNameForFriendlyPlayerUnits ~= 0 then
        fail("bars must leave Blizzard drawing full plates, got "
            .. tostring(cvarWrites.nameplateShowOnlyNameForFriendlyPlayerUnits))
    end

    SetFriendlyLook("nameonly")
    cvarWrites = {}
    Friendly.ApplyModeCVars()
    if cvarWrites.nameplateShowOnlyNameForFriendlyPlayerUnits ~= 1 then
        fail("the plates QUI cannot own are drawn by Blizzard -- name-only must reach the CVar "
            .. "or forbidden friendly plates render full health bars, got "
            .. tostring(cvarWrites.nameplateShowOnlyNameForFriendlyPlayerUnits))
    end

    SetFriendlyLook("simplified")
    cvarWrites = {}
    Friendly.ApplyModeCVars()
    if cvarWrites.nameplateShowOnlyNameForFriendlyPlayerUnits ~= 0 then
        fail("simplified still draws a bar, so the CVar must stay 0, got "
            .. tostring(cvarWrites.nameplateShowOnlyNameForFriendlyPlayerUnits))
    end

    SetFriendlyLook("bars")
end)

world.units.nameplate2 = { canAttack = false, reaction = 6, isPlayer = true, class = "PRIEST",
    health = 40, maxHealth = 100, name = "Ally" }
NewBase("nameplate2")
FireAdded("nameplate2")

test("bars mode draws the full QUI plate", function()
    local plate = NP.plates.nameplate2
    if not plate then fail("bars mode must build a plate") end
    if plate.npRenderMode ~= "bars" then fail("expected bars, got " .. tostring(plate.npRenderMode)) end
    if not plate._shown then fail("bars mode must show the plate") end
    if not plate.healthBar._shown then fail("bars mode must show the health bar") end
end)

test("name-only renders only the name, and lands without a reload", function()
    SetFriendlyLook("nameonly")
    ns.QUI_RefreshNameplates()

    local plate = NP.plates.nameplate2
    if plate.npRenderMode ~= "nameonly" then
        fail("a mode change must reach live plates through the settings refresh, got "
            .. tostring(plate.npRenderMode))
    end
    if plate.healthBar._shown then fail("name-only must hide the health bar") end
    if plate.castBar._shown then fail("name-only must hide the cast bar") end
    if plate.powerBar._shown then fail("name-only must hide the power bar") end
    if plate.healthText._shown then fail("name-only must hide the health text") end
    if plate.npLevelText._shown then fail("name-only must hide the level text") end
    if plate.npRaidMarker._shown then fail("name-only must hide the raid marker") end
    if plate.npTargetGlow._shown then fail("name-only must hide the target glow") end

    if not plate._shown then fail("name-only must keep the plate shown") end
    if not plate.nameText._shown then fail("name-only must draw the name") end
    if plate.nameText._points[1] ~= "CENTER" then fail("name-only must centre the name on the plate") end

    if plate.npCastEnabled ~= false then fail("name-only must disable the castbar updater") end
    if plate.npPowerBarEnabled ~= false then fail("name-only must disable the power bar updater") end
    if plate.npRaidMarkerEnabled ~= false then fail("name-only must disable the raid marker updater") end
    if plate.npHealthTextStyle ~= "none" then fail("name-only must disable the health text updater") end
end)

test("name-only survives the updaters that would otherwise re-show regions", function()
    local plate = NP.plates.nameplate2
    NP.Health.UpdateLevel(plate)
    NP.Health.UpdateNpcTitle(plate)
    NP.Extras.UpdateRaidMarker(plate)
    if plate.npLevelText._shown then fail("UpdateLevel must respect name-only") end
    if plate.npTitleText._shown then fail("UpdateNpcTitle must respect name-only") end
    if plate.npRaidMarker._shown then fail("UpdateRaidMarker must respect name-only") end
end)

test("name-only keeps auras hidden through the deferred pass and a rebind", function()
    local plate = NP.plates.nameplate2
    local pool = plate._quiAuraContainers
    if not pool or #pool == 0 then fail("the harness must build an aura container pool") end
    if AuraContainersVisible(plate) then fail("name-only must hide the aura containers") end

    DrainDefer()
    if AuraContainersVisible(plate) then fail("the deferred aura pass must not re-show auras in name-only") end

    world.units.nameplate5 = { canAttack = false, reaction = 6, health = 30, maxHealth = 100, name = "Rebound" }
    bases.nameplate2.unitToken = "nameplate5"
    plate._scripts.OnEvent(plate, "UNIT_HEALTH", "nameplate2")
    if NP.plates.nameplate5 ~= plate then fail("the rebind must move the plate to the new token") end
    if AuraContainersVisible(plate) then fail("RebindPlate must not re-show auras in name-only") end
    if plate.healthBar._shown then fail("RebindPlate must not re-show the health bar in name-only") end

    bases.nameplate2.unitToken = "nameplate2"
    plate._scripts.OnEvent(plate, "UNIT_HEALTH", "nameplate5")
end)

test("bars mode does show auras, so the name-only assertion above discriminates", function()
    SetFriendlyLook("bars")
    ns.QUI_RefreshNameplates()
    local plate = NP.plates.nameplate2
    if not AuraContainersVisible(plate) then fail("bars mode must show the aura containers") end
    SetFriendlyLook("nameonly")
    ns.QUI_RefreshNameplates()
end)

test("a rebind that changes the unit type restyles the plate both ways", function()
    local plate = NP.plates.nameplate2
    if plate.npAppearanceType ~= "friendly" then fail("precondition: the plate must be styled as friendly") end
    if plate.healthBar._shown then fail("precondition: name-only must have hidden the health bar") end

    world.units.nameplate6 = { canAttack = true, reaction = 2, isPlayer = true,
        health = 70, maxHealth = 100, name = "Turned" }
    bases.nameplate2.unitToken = "nameplate6"
    plate._scripts.OnEvent(plate, "UNIT_HEALTH", "nameplate2")

    if NP.plates.nameplate6 ~= plate then fail("the rebind must move the plate to the new token") end
    if plate.npType ~= "enemyPlayer" then fail("the rebind must re-resolve the type") end
    if plate.npAppearanceType ~= "enemyPlayer" then fail("a rebind that changes type must restyle the plate") end
    if plate.npRenderMode ~= "bars" then fail("an enemy plate must drop the friendly render mode") end
    if not plate.healthBar._shown then fail("the restyle must restore the health bar") end
    if not AuraContainersVisible(plate) then fail("the restyle must restore the auras") end

    bases.nameplate2.unitToken = "nameplate2"
    plate._scripts.OnEvent(plate, "UNIT_HEALTH", "nameplate6")
    if NP.plates.nameplate2 ~= plate then fail("the rebind back must restore the original token") end
    if plate.npAppearanceType ~= "friendly" then fail("the rebind back must restyle to friendly") end
    if plate.healthBar._shown then fail("the rebind back must re-hide the health bar for name-only") end
    if AuraContainersVisible(plate) then fail("the rebind back must re-hide the auras for name-only") end
end)

test("off hides the QUI plate and zeroes the friendly visibility CVars", function()
    settings.friendly.enabled = false
    cvarWrites = {}
    ns.QUI_RefreshNameplates()

    local plate = NP.plates.nameplate2
    if plate.npRenderMode ~= "off" then fail("expected off, got " .. tostring(plate.npRenderMode)) end
    if plate._shown then fail("off must hide the QUI plate") end
    for _, cv in ipairs({ "nameplateShowFriends", "nameplateShowFriendlyPlayers",
        "nameplateShowFriendlyNpcs", "nameplateShowFriendlyNPCs" }) do
        if cvarWrites[cv] ~= 0 then
            fail("off must zero " .. cv .. ", got " .. tostring(cvarWrites[cv]))
        end
    end
end)

test("returning to bars restores the full plate", function()
    settings.friendly.enabled = true
    SetFriendlyLook("bars")
    ns.QUI_RefreshNameplates()
    local plate = NP.plates.nameplate2
    if not plate._shown then fail("bars must show the plate again") end
    if not plate.healthBar._shown then fail("bars must show the health bar again") end
    if plate.npCastEnabled ~= true then fail("bars must re-enable the castbar updater") end
    if plate.npHealthTextStyle == "none" then fail("bars must re-enable the health text") end
    if plate.npRaidMarkerEnabled ~= true then fail("bars must re-enable the raid marker") end
end)

test("the settings refresh reaches the friendly CVar layer", function()
    settings.types.friendly.name.classColorPlayers = false
    cvarWrites = {}
    ns.QUI_RefreshNameplates()
    if cvarWrites.nameplateUseClassColorForFriendlyPlayerUnitNames ~= 0 then
        fail("a settings refresh must re-write the friendly CVars, got "
            .. tostring(cvarWrites.nameplateUseClassColorForFriendlyPlayerUnitNames))
    end
    settings.types.friendly.name.classColorPlayers = true
end)

test("a late type resolution restyles the plate instead of stranding it", function()
    settings.friendly.enabled = false
    world.units.nameplate4 = { canAttack = true, reaction = 2, isPlayer = true,
        health = 60, maxHealth = 100, name = "Liar" }
    NewBase("nameplate4")
    FireAdded("nameplate4")

    local plate = NP.plates.nameplate4
    if plate.npType ~= "enemyPlayer" then fail("the first frame must take the unit at its word") end
    if not plate._shown then fail("an enemy-resolved plate must show") end

    world.units.nameplate4.canAttack = false
    plate._scripts.OnEvent(plate, "UNIT_NAME_UPDATE", "nameplate4")
    if plate.npType ~= "friendly" then fail("UNIT_NAME_UPDATE must re-resolve the type") end
    if plate.npRenderMode ~= "off" then
        fail("a late resolution must restamp the render mode, got " .. tostring(plate.npRenderMode))
    end
    if plate.npAppearanceType ~= "friendly" then fail("a late resolution must restyle the plate") end
    if plate._shown then fail("a late-resolving friendly unit must not strand a visible plate in off mode") end

    plate._scripts.OnEvent(plate, "UNIT_FLAGS", "nameplate4")
    if plate._shown then fail("the plate must stay hidden after UNIT_FLAGS confirms the type") end

    FireRemoved("nameplate4")
    settings.friendly.enabled = true
end)

test("inside an instance a friendly plate renders its own mode, it is no longer clamped", function()
    settings.friendly.enabled = true
    settings.friendly.showInInstances = true
    SetFriendlyLook("bars")
    world.inInstance = true
    world.instanceType = "party"
    NP.Extras.RefreshContext()
    cvarWrites = {}
    ns.QUI_RefreshNameplates()

    local plate = NP.plates.nameplate2
    if plate.npRenderMode ~= "bars" then
        fail("an instance must no longer force name-only onto a friendly plate, got "
            .. tostring(plate.npRenderMode))
    end
    if not plate._shown then fail("showInInstances=true must keep the plate visible in an instance") end
    if not plate.healthBar._shown then fail("bars in an instance must draw the health bar") end
    if not plate.healthText._shown then fail("bars in an instance must draw the health text") end
    if cvarWrites.nameplateShowFriends ~= 1 then
        fail("showInInstances=true must let friendly players through, got "
            .. tostring(cvarWrites.nameplateShowFriends))
    end
    if cvarWrites.nameplateShowFriendlyNpcs ~= 1 then
        fail("friendly NPCs now follow the Friendly NPCs toggle, not a hardcoded instance rule, got "
            .. tostring(cvarWrites.nameplateShowFriendlyNpcs))
    end

    SetFriendlyLook("nameonly")
    ns.QUI_RefreshNameplates()
    if plate.npRenderMode ~= "nameonly" then
        fail("the type's own mode must still govern inside an instance, got "
            .. tostring(plate.npRenderMode))
    end
    if plate.healthBar._shown then fail("nameonly in an instance must hide the health bar") end

    SetFriendlyLook("bars")
    settings.friendly.showInInstances = false
    world.inInstance = false
    world.instanceType = nil
    NP.Extras.RefreshContext()
    ns.QUI_RefreshNameplates()
end)

test("showInWorld=false no longer suppresses friendly plates inside an instance", function()
    settings.friendly.showInWorld = false
    settings.friendly.showInInstances = true
    world.inInstance = true
    world.instanceType = "party"
    NP.Extras.RefreshContext()
    cvarWrites = {}
    ns.QUI_RefreshNameplates()
    if cvarWrites.nameplateShowFriends ~= 1 then
        fail("hide-in-world plus show-in-instances must still show them in the instance, got "
            .. tostring(cvarWrites.nameplateShowFriends))
    end

    world.inInstance = false
    world.instanceType = nil
    NP.Extras.RefreshContext()
    cvarWrites = {}
    ns.QUI_RefreshNameplates()
    if cvarWrites.nameplateShowFriends ~= 0 then
        fail("showInWorld=false must still hide them in the open world, got "
            .. tostring(cvarWrites.nameplateShowFriends))
    end

    settings.friendly.showInWorld = true
    settings.friendly.showInInstances = false
    ns.QUI_RefreshNameplates()
end)

test("the CVar owner stays active inside the instance gate, so uihider keeps delegating", function()
    local NPCVars = ns.QUI_NameplatesCVars
    settings.friendly.enabled = true
    settings.friendly.showInInstances = false
    world.inInstance = true
    world.instanceType = "party"
    NP.Extras.RefreshContext()
    if NPCVars:IsActive() ~= true then
        fail("the instance gate hides plates, it must not hand CVar ownership back to uihider")
    end

    world.inInstance = false
    world.instanceType = nil
    NP.Extras.RefreshContext()

    local savedMode = settings.friendly.enabled
    settings.friendly.enabled = nil
    if NPCVars:IsActive() ~= true then fail("an unset mode must still count as owned") end
    settings.friendly.enabled = false
    if NPCVars:IsActive() ~= false then fail("friendly off must release ownership") end
    settings.friendly.enabled = savedMode
end)

test("an instance with showInInstances false resolves to off", function()
    world.inInstance = true
    world.instanceType = "party"
    NP.Extras.RefreshContext()
    cvarWrites = {}
    ns.QUI_RefreshNameplates()

    local plate = NP.plates.nameplate2
    if plate.npRenderMode ~= "off" then fail("instance + showInInstances=false must be off") end
    if plate._shown then fail("instance-off must hide the plate") end
    if cvarWrites.nameplateShowFriends ~= 0 then fail("instance-off must zero nameplateShowFriends") end

    world.inInstance = false
    world.instanceType = nil
    NP.Extras.RefreshContext()
    ns.QUI_RefreshNameplates()
end)

test("the friendly mode never touches a non-friendly plate", function()
    settings.friendly.enabled = false
    world.units.nameplate3 = { canAttack = true, reaction = 2, health = 10, maxHealth = 100, name = "Boar" }
    NewBase("nameplate3")
    FireAdded("nameplate3")

    local plate = NP.plates.nameplate3
    if not plate then fail("an enemy unit must still build") end
    if plate.npRenderMode ~= "bars" then fail("a non-friendly plate must never take the friendly mode") end
    if not plate._shown then fail("off must not hide enemy plates") end
    if not plate.healthBar._shown then fail("off must not hide enemy health bars") end
    settings.friendly.enabled = true
end)

test("a friendly PET inside an instance obeys the friendly instance name-only setting", function()
    NP.NormalizeTypes(settings)
    settings.friendly.enabled = true
    settings.friendly.showInInstances = "nameonly"
    settings.types.petMinion.renderMode = "bars"

    world.units.nameplate7 = {
        canAttack = false, reaction = 6, isOtherPet = true,
        health = 40, maxHealth = 100, name = "Bearcub",
    }
    NewBase("nameplate7")
    world.inInstance = true
    world.instanceType = "party"
    NP.Extras.RefreshContext()
    FireAdded("nameplate7")

    local plate = NP.plates.nameplate7
    if not plate then fail("a friendly pet must still build a plate in an instance") end
    if plate.npType ~= "petMinion" then
        fail("setup: expected petMinion, got " .. tostring(plate.npType))
    end
    if plate.npReaction ~= "friendly" then
        fail("setup: expected a friendly reaction, got " .. tostring(plate.npReaction))
    end

    ns.QUI_RefreshNameplates()
    if plate.npRenderMode ~= "nameonly" then
        fail("the friendly instance setting must reach a friendly PET, not just the friendly "
            .. "type -- pets beat reaction in PlateType.ORDER, got " .. tostring(plate.npRenderMode))
    end
    if plate.healthBar._shown then
        fail("name-only in an instance must hide a friendly pet's health bar")
    end

    settings.friendly.showInInstances = "always"
    ns.QUI_RefreshNameplates()
    if plate.npRenderMode ~= "bars" then
        fail("always must hand the pet back to its own render mode, got "
            .. tostring(plate.npRenderMode))
    end

    world.inInstance = false
    world.instanceType = "none"
    NP.Extras.RefreshContext()
    settings.friendly.showInInstances = "nameonly"
    ns.QUI_RefreshNameplates()
    if plate.npRenderMode ~= "bars" then
        fail("the instance setting must not leak into the open world, got "
            .. tostring(plate.npRenderMode))
    end
end)

print("OK: nameplates_friendly_test")
