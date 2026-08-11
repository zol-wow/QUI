local function fail(msg)
    print("FAIL: nameplates_render_mode_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

do
    local env = dofile("tools/_addon_env.lua")
    local harness = env.LoadHarness(nil, { noSeed = true })
    local nameplates = harness.db.profile.nameplates
    local ALL_TYPES = { "enemyPlayer", "enemyNPC", "bossElite", "minorTrivial", "petMinion", "friendly" }

    test("renderMode defaults to bars on every shipped type but friendly", function()
        for _, key in ipairs(ALL_TYPES) do
            local expected = (key == "friendly") and "nameonly" or "bars"
            if nameplates.types[key].renderMode ~= expected then
                fail(key .. ".renderMode must default to " .. expected
                    .. ", got " .. tostring(nameplates.types[key].renderMode))
            end
            if nameplates.types[key].useSimplified ~= nil then
                fail(key .. ".useSimplified must be gone from the defaults")
            end
        end
    end)

    test("the global simplified scale block defaults to 1.0", function()
        if type(nameplates.simplified) ~= "table" then fail("nameplates.simplified must be a table") end
        if nameplates.simplified.scale ~= 1.0 then fail("nameplates.simplified.scale must default to 1.0") end
    end)
end

local function noop() end

local function NewRegion(parent)
    local r = {
        _parent = parent, _shown = true, _alpha = 1,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop,
        SetPoint = function(self, point, relativeTo, relativePoint, x, y)
            self._points = { point, relativeTo, relativePoint, x, y }
        end,
        ClearAllPoints = function(self) self._points = nil end,
        SetSize = function(self, w, h) self._w, self._h = w, h end,
        SetWidth = function(self, w) self._w = w end,
        SetHeight = function(self, h) self._h = h end,
        SetColorTexture = noop, SetVertexColor = noop, SetTexture = noop,
        SetAtlas = noop,
        SetAlpha = function(self, a) self._alpha = a end,
        GetAlpha = function(self) return self._alpha end,
        SetHorizTile = noop, SetVertTile = noop, SetTexCoord = noop,
        AddMaskTexture = noop, SetBlendMode = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetText = function(self, t) self._text = t end,
        SetFormattedText = function(self, fmt, ...) self._text = string.format(fmt, ...) end,
        SetTextColor = noop, SetFont = noop, GetFont = function() return "font.ttf" end,
        SetJustifyH = noop, SetDrawLayer = noop, SetShadowOffset = noop, SetShadowColor = noop,
        SetScale = function(self, s) self._scale = s end,
        GetScale = function(self) return self._scale or 1 end,
        SetIgnoreParentScale = function(self, v) self._ignoreParentScale = v end,
    }
    r.GetEffectiveScale = function(self)
        local own = self._scale or 1
        if self._ignoreParentScale or not self._parent then return own end
        return own * self._parent:GetEffectiveScale()
    end
    return r
end

local function NewFrame(parent)
    local f = NewRegion(parent)
    f._events = {}
    f._scripts = {}
    f._level = 1
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

local function PumpDeferred()
    for _, f in ipairs(createdFrames) do
        local fn = f._scripts and f._scripts.OnUpdate
        if fn and f._shown then fn(f) end
    end
end
UIParent = NewFrame(nil)
C_Timer = {
    After = function() end,
    NewTicker = function() return { Cancel = noop } end,
}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
hooksecurefunc = noop
InCombatLockdown = function() return false end
SetCVar = noop
AbbreviateNumbers = nil

local world = { units = {} }
local function U(token) return world.units[token] end
UnitExists = function(u) local d = U(u) return d ~= nil and d.exists ~= false end
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
UnitGetTotalAbsorbs = function() return world.absorbs or 0 end
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
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
GetPlayerInfoByGUID = function() return nil end
UnitPowerType = function() return 0 end
UnitPowerMax = function() return 100 end
UnitPower = function() return 50 end
UnitGetIncomingHeals = function() return world.incomingHeals or 0 end
PowerBarColor = { [0] = { r = 0.3, g = 0.5, b = 0.9 } }
GetRaidTargetIndex = function() return 3 end
SetRaidTargetIconTexture = noop
GetPhysicalScreenSize = function() return 1366, 768 end
GetScreenWidth = function() return 1366 end
GetScreenHeight = function() return 768 end

C_NamePlate = { GetNamePlateForUnit = function() return nil end, SetNamePlateSize = noop }
C_CVar = { SetCVarBitfield = noop, GetCVarInfo = function() return nil end }
Enum = { NamePlateType = { Friendly = 0, Enemy = 1 } }

local simplifiedCalls = {}
C_NamePlateManager = {
    SetNamePlateSimplified = function(unit, flag)
        simplifiedCalls[#simplifiedCalls + 1] = { unit, flag }
    end,
}

local auraElementsSeen = setmetatable({}, { __mode = "k" })

local function RenderableType()
    return {
        renderMode = "bars",
        health = { width = 210, height = 24 },
        name = { enabled = true, size = 11, offsetY = 4 },
        healthText = { enabled = true, style = "percent" },
        level = { enabled = true, showClassification = true },
        powerBar = { enabled = true, height = 6 },
        raidMarker = { enabled = true },
        castbar = { enabled = true, height = 17 },
        absorbs = { enabled = true },
        healPrediction = { enabled = true },
        auras = { enabled = true, elements = { ["*"] = { { enabled = true }, { enabled = true } } } },
    }
end

local function AuraElementCount(plate)
    local seen = auraElementsSeen[plate]
    return seen and #seen or nil
end

local settingsStore = {
    enabled = true,
    simplified = { scale = 0.5 },
    types = {
        enemyPlayer  = { renderMode = "bars" },
        enemyNPC     = { renderMode = "bars" },
        bossElite    = { renderMode = "bars" },
        minorTrivial = { renderMode = "bars" },
        petMinion    = { renderMode = "bars" },
        friendly     = { renderMode = "bars" },
    },
}

_G.QUI = { AuraSkin = { LayoutAnchor = function() return "TOPLEFT" end } }

local function LoadSuite()
    local ns = {
        AuraElements = { EnsureSeeded = noop },
        AuraSurface = {
            ApplyElementPass = function(plate, elements)
                auraElementsSeen[plate] = elements
            end,
        },
        AuraGlue = { ElementProfile = function() return {} end, QueueRegenWork = noop },
        Helpers = {
            IsSecretValue = function() return false end,
            TruncateUTF8 = function(s, n) return type(s) == "string" and s:sub(1, n) or s end,
            GetModuleSettings = function() return settingsStore end,
            CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
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
        Addon = {},
        LSM = nil,
    }
    assert(loadfile("core/scaling.lua"))("QUI", ns)
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
    return ns.QUI_Nameplates
end

local NP = LoadSuite()
if not NP then fail("suite did not export ns.QUI_Nameplates") end
if NP.SIMPLIFIED_AVAILABLE ~= true then fail("SIMPLIFIED_AVAILABLE must be true when the API is present") end

test("the flag is pushed to the API for the resolved type", function()
    simplifiedCalls = {}
    settingsStore.types.minorTrivial.renderMode = "simplified"
    local plate = { npType = "minorTrivial", unit = "nameplate1" }
    NP.Driver.ApplySimplified(plate)
    if simplifiedCalls[1] == nil then fail("expected a SetNamePlateSimplified call") end
    if simplifiedCalls[1][1] ~= "nameplate1" then fail("wrong unit token pushed") end
    if simplifiedCalls[1][2] ~= true then fail("expected isSimplified true") end
end)

test("a type without the flag pushes false", function()
    simplifiedCalls = {}
    settingsStore.types.enemyNPC.renderMode = "bars"
    local plate = { npType = "enemyNPC", unit = "nameplate1" }
    NP.Driver.ApplySimplified(plate)
    if simplifiedCalls[1] == nil then fail("expected a SetNamePlateSimplified call") end
    if simplifiedCalls[1][2] ~= false then fail("expected isSimplified false") end
end)

test("a plate with no unit token is skipped", function()
    simplifiedCalls = {}
    NP.Driver.ApplySimplified({ npType = "enemyNPC" })
    if #simplifiedCalls ~= 0 then fail("must not call the API without a unit token") end
end)

test("BuildEnemyPlate pushes the flag for the resolved type", function()
    simplifiedCalls = {}
    world.units.nameplateA = { canAttack = true, classification = "minus", health = 100, maxHealth = 100 }
    settingsStore.types.minorTrivial.renderMode = "simplified"
    local base = NewFrame(UIParent)
    local plate = NP.Driver.BuildEnemyPlate("nameplateA", base)
    if not plate then fail("BuildEnemyPlate must return a plate") end
    if plate.npType ~= "minorTrivial" then fail("expected npType minorTrivial, got " .. tostring(plate.npType)) end
    if #simplifiedCalls ~= 1 then fail("expected exactly one call from BuildEnemyPlate, got " .. #simplifiedCalls) end
    if simplifiedCalls[1][1] ~= "nameplateA" then fail("wrong unit token pushed") end
    if simplifiedCalls[1][2] ~= true then fail("expected isSimplified true") end
end)

test("RefreshPlateType pushes the flag again when the resolved type changes", function()
    simplifiedCalls = {}
    world.units.nameplateA.classification = nil
    settingsStore.types.enemyNPC.renderMode = "bars"
    local plate = NP.plates.nameplateA
    local changed = NP.Driver.RefreshPlateType(plate)
    if changed ~= true then fail("expected RefreshPlateType to report the type change") end
    if plate.npType ~= "enemyNPC" then fail("expected plate to move to enemyNPC, got " .. tostring(plate.npType)) end
    if #simplifiedCalls ~= 1 then fail("expected RefreshPlateType to push exactly one call, got " .. #simplifiedCalls) end
    if simplifiedCalls[1][2] ~= false then fail("expected isSimplified false for enemyNPC") end
end)

test("RefreshPlateType with no type change pushes nothing", function()
    simplifiedCalls = {}
    local plate = NP.plates.nameplateA
    local changed = NP.Driver.RefreshPlateType(plate)
    if changed ~= false then fail("expected no type change to be reported") end
    if #simplifiedCalls ~= 0 then fail("must not call the API when the type did not change") end
end)

test("UNIT_NAME_UPDATE re-resolves the type and pushes that type's flag", function()
    simplifiedCalls = {}
    local plate = NP.plates.nameplateA
    if plate.npType ~= "enemyNPC" then
        fail("fixture: the plate must start on enemyNPC, got " .. tostring(plate.npType))
    end
    world.units.nameplateA.classification = "minus"
    settingsStore.types.minorTrivial.renderMode = "simplified"

    plate:GetScript("OnEvent")(plate, "UNIT_NAME_UPDATE", "nameplateA")

    if plate.npType ~= "minorTrivial" then
        fail("UNIT_NAME_UPDATE must re-resolve the type, got " .. tostring(plate.npType))
    end
    if #simplifiedCalls ~= 1 then
        fail("UNIT_NAME_UPDATE must push the re-resolved type's flag, got " .. #simplifiedCalls .. " calls")
    end
    if simplifiedCalls[1][1] ~= "nameplateA" then fail("wrong unit token pushed") end
    if simplifiedCalls[1][2] ~= true then
        fail("expected isSimplified true for minorTrivial, got " .. tostring(simplifiedCalls[1][2]))
    end
end)

test("a settings change reaches live plates through NPDriver.Refresh, with no rebind", function()
    local plate = NP.plates.nameplateA
    settingsStore.types[plate.npType].renderMode = "bars"
    NP.Driver.Refresh()

    simplifiedCalls = {}
    settingsStore.types[plate.npType].renderMode = "simplified"
    NP.Driver.Refresh()

    local seen
    for _, call in ipairs(simplifiedCalls) do
        if call[1] == "nameplateA" then seen = call end
    end
    if not seen then
        fail("a settings refresh must re-push the flag to every live plate, or the option needs a /reload")
    end
    if seen[2] ~= true then
        fail("expected the newly enabled flag to reach the live plate, got " .. tostring(seen[2]))
    end
    settingsStore.types[plate.npType].renderMode = "simplified"
end)

test("a pooled frame recycled across types pushes the new type's flag", function()
    world.units.nameplateC1 = { canAttack = true, level = -1, health = 100, maxHealth = 100 }
    settingsStore.types.bossElite.renderMode = "bars"
    local baseC = NewFrame(UIParent)
    baseC.unitToken = "nameplateC1"
    local plateC = NP.Driver.BuildEnemyPlate("nameplateC1", baseC)
    if plateC.npType ~= "bossElite" then fail("expected npType bossElite, got " .. tostring(plateC.npType)) end

    simplifiedCalls = {}
    world.units.nameplateC2 = { canAttack = true, classification = "minus", health = 50, maxHealth = 100 }
    settingsStore.types.minorTrivial.renderMode = "simplified"
    baseC.unitToken = "nameplateC2"
    plateC:GetScript("OnEvent")(plateC, "UNIT_HEALTH", "nameplateC1")

    if plateC.unit ~= "nameplateC2" then fail("expected the plate to rebind to the new token") end
    if plateC.npType ~= "minorTrivial" then fail("expected npType minorTrivial after rebind, got " .. tostring(plateC.npType)) end
    if #simplifiedCalls ~= 1 then fail("expected the rebind to push exactly one call, got " .. #simplifiedCalls) end
    if simplifiedCalls[1][1] ~= "nameplateC2" then fail("wrong unit token pushed after rebind") end
    if simplifiedCalls[1][2] ~= true then fail("expected isSimplified true for the recycled minorTrivial unit") end
end)

local RENDER_STRIPPED = {
    "healthText", "npLevelText", "npClassIcon", "powerBar", "npRaidMarker",
    "npTitleText", "npAbsorbText", "npQuestIcon", "npTargetGlow", "npFocusGlow",
}

local function ShownReport(plate, keys)
    local out = {}
    for _, key in ipairs(keys) do
        out[#out + 1] = key .. "=" .. tostring(plate[key] and plate[key]._shown)
    end
    return table.concat(out, " ")
end

do
    settingsStore.types.enemyNPC = RenderableType()
    world.units.nameplateR = {
        canAttack = true, level = 80, health = 60, maxHealth = 100, name = "Dummy",
    }
    local baseR = NewFrame(UIParent)
    baseR.unitToken = "nameplateR"
    local plateR = NP.Driver.BuildEnemyPlate("nameplateR", baseR)
    if not plateR then fail("BuildEnemyPlate must return a plate for the render fixture") end
    if plateR.npType ~= "enemyNPC" then
        fail("render fixture must resolve to enemyNPC, got " .. tostring(plateR.npType))
    end
    PumpDeferred()

    test("with simplified off the plate draws its full furniture", function()
        for _, key in ipairs({ "healthBar", "nameText", "healthText", "npLevelText", "powerBar", "npRaidMarker" }) do
            if not (plateR[key] and plateR[key]._shown) then
                fail("baseline must draw " .. key .. " -- " .. ShownReport(plateR, RENDER_STRIPPED))
            end
        end
        if AuraElementCount(plateR) ~= 2 then
            fail("baseline must push both aura elements to the surface, got " .. tostring(AuraElementCount(plateR)))
        end
    end)

    test("simplified on strips the QUI plate down to the bar and the name", function()
        settingsStore.types.enemyNPC.renderMode = "simplified"
        NP.Driver.Refresh()

        if plateR.npRenderMode ~= "simplified" then
            fail("expected the simplified render mode, got " .. tostring(plateR.npRenderMode))
        end
        for _, key in ipairs(RENDER_STRIPPED) do
            local region = plateR[key]
            if region and region._shown then
                fail(key .. " must stop drawing on a simplified plate -- " .. ShownReport(plateR, RENDER_STRIPPED))
            end
        end
        if not plateR.healthBar._shown then fail("a simplified plate must keep its health bar") end
        if not plateR.nameText._shown then fail("a simplified plate must keep its name") end
        if plateR.npCastEnabled ~= false then fail("simplified must disable the castbar path") end
        if plateR.npHealthTextStyle ~= "none" then fail("simplified must force the health text off") end
        if AuraElementCount(plateR) ~= 0 then
            fail("a simplified plate must push no aura elements to the surface, got "
                .. tostring(AuraElementCount(plateR)))
        end
    end)

    test("the simplified scale reaches the plate and survives pixel-perfect sizing", function()
        if plateR._scale ~= 0.5 then
            fail("expected the plate scaled to 0.5, got " .. tostring(plateR._scale))
        end
        if plateR.healthBar._w ~= 210 then
            fail("the appearance pass must size against the unscaled reference, or the scale cancels out; got "
                .. tostring(plateR.healthBar._w))
        end
    end)

    test("turning simplified back off restores every region it hid", function()
        settingsStore.types.enemyNPC.renderMode = "bars"
        NP.Driver.Refresh()

        if plateR.npRenderMode ~= "bars" then
            fail("expected the bars render mode, got " .. tostring(plateR.npRenderMode))
        end
        for _, key in ipairs({ "healthBar", "nameText", "healthText", "npLevelText", "powerBar", "npRaidMarker" }) do
            if not (plateR[key] and plateR[key]._shown) then
                fail(key .. " must come back when simplified is turned off, with no reload -- "
                    .. ShownReport(plateR, RENDER_STRIPPED))
            end
        end
        if plateR._scale ~= 1 then
            fail("the plate must drop back to the unscaled size, got " .. tostring(plateR._scale))
        end
        if plateR.healthBar._w ~= 210 then
            fail("the health bar must keep its configured width, got " .. tostring(plateR.healthBar._w))
        end
        if AuraElementCount(plateR) ~= 2 then
            fail("aura elements must come back when simplified is turned off, got "
                .. tostring(AuraElementCount(plateR)))
        end
    end)

    test("simplified hides the absorb and heal-prediction bars, and hands them back", function()
        world.absorbs = 0
        world.incomingHeals = 0
        NP.Driver.Refresh()
        if plateR.absorbBar._shown then fail("fixture: a unit with no absorb must not show the absorb bar") end

        world.absorbs = 500
        world.incomingHeals = 300
        NP.Driver.Refresh()
        if not plateR.absorbBar._shown then
            fail("fixture: an absorbing unit must show the absorb bar before the strip")
        end
        if not plateR.healPredictBar._shown then
            fail("fixture: an incoming heal must show the heal prediction bar before the strip")
        end

        settingsStore.types.enemyNPC.renderMode = "simplified"
        NP.Driver.Refresh()
        if plateR.absorbBar._shown then
            fail("a simplified plate must hide the absorb bar; its updater early-returns when disabled "
                .. "and never hides it for you")
        end
        if plateR.healPredictBar._shown then fail("a simplified plate must hide the heal prediction bar") end

        settingsStore.types.enemyNPC.renderMode = "bars"
        NP.Driver.Refresh()
        if not plateR.absorbBar._shown then
            fail("the absorb bar must come back; hiding it must also reset the show-cache it is gated on, "
                .. "or it stays hidden for the life of the plate")
        end
        if not plateR.healPredictBar._shown then
            fail("the heal prediction bar must come back when simplified is turned off")
        end

        world.absorbs = 0
        world.incomingHeals = 0
    end)
end

do
    settingsStore.friendly = { mode = "show", showInWorld = true }
    settingsStore.types.friendly = RenderableType()
    settingsStore.types.friendly.renderMode = "nameonly"
    world.units.nameplateF = {
        reaction = 5, isPlayer = true, level = 80, health = 60, maxHealth = 100, name = "Ally",
    }
    local baseF = NewFrame(UIParent)
    baseF.unitToken = "nameplateF"
    local plateF = NP.Driver.BuildEnemyPlate("nameplateF", baseF)
    if plateF.npType ~= "friendly" then
        fail("friendly fixture must resolve to friendly, got " .. tostring(plateF.npType))
    end

    test("name-only hides the health bar, simplified keeps it", function()
        if plateF.npRenderMode ~= "nameonly" then
            fail("expected nameonly, got " .. tostring(plateF.npRenderMode))
        end
        if plateF.healthBar._shown then fail("name-only must hide the health bar") end

        settingsStore.types.friendly.renderMode = "simplified"
        NP.Driver.Refresh()

        if plateF.npRenderMode ~= "simplified" then
            fail("the friendly type's own render mode must reach the plate, got " .. tostring(plateF.npRenderMode))
        end
        if not plateF.healthBar._shown then
            fail("simplified is a bar-and-name plate, so the health bar must be back")
        end
        if plateF.npLevelText._shown then fail("simplified must still strip the level text") end
        settingsStore.types.friendly.renderMode = "bars"
    end)

    test("friendly off wins over the friendly type's render mode", function()
        settingsStore.types.friendly.renderMode = "bars"
        settingsStore.friendly.enabled = false
        NP.Driver.Refresh()

        if plateF.npRenderMode ~= "off" then
            fail("friendly off must beat renderMode bars, got " .. tostring(plateF.npRenderMode))
        end
        if plateF._shown then fail("off must hide the plate") end

        settingsStore.friendly.enabled = true
        NP.Driver.Refresh()
        if plateF.npRenderMode ~= "bars" then
            fail("turning friendly back on must restore the type's own render mode, got "
                .. tostring(plateF.npRenderMode))
        end
        if not plateF._shown then fail("show must bring the plate back") end
    end)
end

do
    local MATRIX = {
        {
            key = "petMinion",
            token = "nameplateM1",
            unit = { canAttack = true, isMinion = true, level = 70,
                health = 40, maxHealth = 100, name = "Pet" },
        },
        {
            key = "enemyPlayer",
            token = "nameplateM2",
            unit = { canAttack = true, isPlayer = true, level = 80,
                health = 90, maxHealth = 100, name = "Rival" },
        },
    }

    local WATCHED = { "healthBar", "nameText", "healthText", "npLevelText", "powerBar", "npRaidMarker",
        "npClassIcon", "npTitleText", "npAbsorbText", "npQuestIcon", "npTargetGlow", "npFocusGlow" }
    local REQUIRED_IN_BARS = { "healthBar", "nameText", "healthText", "npLevelText", "npRaidMarker" }

    local function ShownSet(plate)
        local out = {}
        for _, key in ipairs(WATCHED) do
            out[key] = (plate[key] and plate[key]._shown) == true
        end
        return out
    end

    local function NameAnchor(plate)
        local p = plate.nameText._points or {}
        return tostring(p[1]) .. "->" .. tostring(p[3])
    end

    for _, def in ipairs(MATRIX) do
        settingsStore.types[def.key] = RenderableType()
        world.units[def.token] = def.unit
        local base = NewFrame(UIParent)
        base.unitToken = def.token
        local plate = NP.Driver.BuildEnemyPlate(def.token, base)
        if not plate then fail(def.key .. " fixture: BuildEnemyPlate returned nothing") end
        if plate.npType ~= def.key then
            fail(def.key .. " fixture must resolve to " .. def.key .. ", got " .. tostring(plate.npType))
        end
        PumpDeferred()

        local function SetMode(mode)
            settingsStore.types[def.key].renderMode = mode
            NP.Driver.Refresh()
        end

        test(def.key .. " renders bars, simplified and nameonly as three distinct results", function()
            SetMode("bars")
            if plate.npRenderMode ~= "bars" then
                fail("expected bars, got " .. tostring(plate.npRenderMode))
            end
            for _, key in ipairs(REQUIRED_IN_BARS) do
                if not (plate[key] and plate[key]._shown) then
                    fail("bars must draw " .. key .. " on " .. def.key
                        .. " -- " .. ShownReport(plate, RENDER_STRIPPED))
                end
            end
            local barsShown = ShownSet(plate)
            local barsAnchor = NameAnchor(plate)
            if barsAnchor == "CENTER->CENTER" then
                fail("fixture: bars must anchor the name off the health bar, got " .. barsAnchor)
            end
            if AuraElementCount(plate) ~= 2 then
                fail("bars must push both aura elements on " .. def.key
                    .. ", got " .. tostring(AuraElementCount(plate)))
            end

            SetMode("simplified")
            if plate.npRenderMode ~= "simplified" then
                fail("expected simplified, got " .. tostring(plate.npRenderMode))
            end
            if not plate.healthBar._shown then
                fail("simplified must keep the health bar on " .. def.key)
            end
            if not plate.nameText._shown then fail("simplified must keep the name on " .. def.key) end
            for _, key in ipairs(RENDER_STRIPPED) do
                if plate[key] and plate[key]._shown then
                    fail(key .. " must stop drawing on a simplified " .. def.key
                        .. " -- " .. ShownReport(plate, RENDER_STRIPPED))
                end
            end
            if NameAnchor(plate) ~= barsAnchor then
                fail("simplified keeps the bar, so the name must stay anchored to it, got " .. NameAnchor(plate))
            end
            if AuraElementCount(plate) ~= 0 then
                fail("simplified must push no aura elements on " .. def.key
                    .. ", got " .. tostring(AuraElementCount(plate)))
            end

            SetMode("nameonly")
            if plate.npRenderMode ~= "nameonly" then
                fail("expected nameonly, got " .. tostring(plate.npRenderMode))
            end
            if plate.healthBar._shown then
                fail("nameonly must hide the health bar on " .. def.key
                    .. " -- this is the case the pet bug reported")
            end
            if not plate.nameText._shown then fail("nameonly must draw the name on " .. def.key) end
            if NameAnchor(plate) ~= "CENTER->CENTER" then
                fail("nameonly must recentre the name on " .. def.key .. ", got " .. NameAnchor(plate))
            end
            if plate.nameText._points[2] ~= plate then
                fail("nameonly must centre the name on the plate itself, not the hidden bar")
            end
            for _, key in ipairs(RENDER_STRIPPED) do
                if plate[key] and plate[key]._shown then
                    fail(key .. " must stop drawing on a nameonly " .. def.key
                        .. " -- " .. ShownReport(plate, RENDER_STRIPPED))
                end
            end
            if AuraElementCount(plate) ~= 0 then
                fail("nameonly must push no aura elements on " .. def.key
                    .. ", got " .. tostring(AuraElementCount(plate)))
            end

            SetMode("bars")
            local restored = ShownSet(plate)
            for _, key in ipairs(WATCHED) do
                if restored[key] ~= barsShown[key] then
                    fail(key .. " did not come back to its bars state on " .. def.key
                        .. " with no reload -- " .. ShownReport(plate, RENDER_STRIPPED))
                end
            end
            for _, key in ipairs(REQUIRED_IN_BARS) do
                if not restored[key] then
                    fail(key .. " must draw again on " .. def.key .. " when bars returns")
                end
            end
            if NameAnchor(plate) ~= barsAnchor then
                fail("returning to bars must undo the nameonly re-anchor, got " .. NameAnchor(plate))
            end
            if AuraElementCount(plate) ~= 2 then
                fail("returning to bars must restore the aura elements on " .. def.key
                    .. ", got " .. tostring(AuraElementCount(plate)))
            end
        end)
    end

    test("each type keeps its own render mode, they do not leak across types", function()
        settingsStore.types.petMinion.renderMode = "nameonly"
        settingsStore.types.enemyPlayer.renderMode = "bars"
        NP.Driver.Refresh()

        local pet = NP.plates.nameplateM1
        local rival = NP.plates.nameplateM2
        if pet.npRenderMode ~= "nameonly" then
            fail("the pet must take nameonly, got " .. tostring(pet.npRenderMode))
        end
        if rival.npRenderMode ~= "bars" then
            fail("the enemy player must stay on bars, got " .. tostring(rival.npRenderMode))
        end
        if pet.healthBar._shown then fail("the pet must be name-only") end
        if not rival.healthBar._shown then fail("the enemy player must still draw its bar") end

        settingsStore.types.petMinion.renderMode = "bars"
        NP.Driver.Refresh()
    end)
end

do
    local function LoadFoldOnly()
        local nsF = {
            Helpers = { IsSecretValue = function() return false end },
        }
        assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", nsF)
        assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", nsF)
        return nsF.QUI_Nameplates
    end

    local NPF = LoadFoldOnly()

    test("a saved useSimplified=true folds to renderMode simplified and the legacy key is dropped", function()
        local settings = {
            types = {
                minorTrivial = { useSimplified = true, renderMode = "bars" },
                enemyNPC = { useSimplified = false, renderMode = "bars" },
            },
        }
        NPF.NormalizeTypes(settings)

        if settings.types.minorTrivial.renderMode ~= "simplified" then
            fail("useSimplified=true must fold to simplified, got "
                .. tostring(settings.types.minorTrivial.renderMode))
        end
        if settings.types.minorTrivial.useSimplified ~= nil then
            fail("the legacy key must be dropped, or it strands on the profile forever")
        end
        if settings.types.enemyNPC.renderMode ~= "bars" then
            fail("useSimplified=false must stay on bars, got " .. tostring(settings.types.enemyNPC.renderMode))
        end
        if settings.types.enemyNPC.useSimplified ~= nil then fail("the legacy key must be dropped everywhere") end
    end)

    test("a saved friendly.mode look folds onto the friendly type and leaves a visibility verdict", function()
        local settings = { friendly = { mode = "nameonly" }, types = { friendly = { renderMode = "bars" } } }
        NPF.NormalizeTypes(settings)
        if settings.types.friendly.renderMode ~= "nameonly" then
            fail("friendly.mode=nameonly must carry the user's look forward, got "
                .. tostring(settings.types.friendly.renderMode))
        end
        if settings.friendly.enabled ~= true then
            fail("the folded mode must become a visibility verdict, got " .. tostring(settings.friendly.enabled))
        end

        settings = { friendly = { mode = "bars" }, types = { friendly = { renderMode = "nameonly" } } }
        NPF.NormalizeTypes(settings)
        if settings.types.friendly.renderMode ~= "bars" then
            fail("friendly.mode=bars must carry bars forward, got "
                .. tostring(settings.types.friendly.renderMode))
        end
        if settings.friendly.enabled ~= true then fail("bars must fold to enabled too") end
    end)

    test("useSimplified wins over the legacy friendly.mode, as the old resolver did", function()
        local settings = {
            friendly = { mode = "nameonly" },
            types = { friendly = { useSimplified = true, renderMode = "bars" } },
        }
        NPF.NormalizeTypes(settings)
        if settings.types.friendly.renderMode ~= "simplified" then
            fail("the old resolver let useSimplified beat friendly nameonly; the fold must preserve that, got "
                .. tostring(settings.types.friendly.renderMode))
        end
    end)

    test("friendly off is never folded away, and a second pass changes nothing", function()
        local settings = { friendly = { mode = "off" }, types = { friendly = { renderMode = "nameonly" } } }
        NPF.NormalizeTypes(settings)
        if settings.friendly.enabled ~= false then
            fail("off is a visibility state, it must survive the fold as enabled=false, got "
                .. tostring(settings.friendly.enabled))
        end
        if rawget(settings.friendly, "mode") ~= nil then
            fail("the legacy mode key must be consumed, not left beside its replacement")
        end

        local folded = { friendly = { mode = "nameonly" }, types = { friendly = { renderMode = "bars" } } }
        NPF.NormalizeTypes(folded)
        NPF.NormalizeTypes(folded)
        if folded.types.friendly.renderMode ~= "nameonly" or folded.friendly.enabled ~= true then
            fail("the fold must be idempotent -- it runs on every GetTypeSettings call")
        end
    end)

    test("an unknown renderMode falls back to bars instead of rendering nothing", function()
        local settings = { types = { enemyNPC = { renderMode = "wat" } } }
        NPF.NormalizeTypes(settings)
        if settings.types.enemyNPC.renderMode ~= "bars" then
            fail("a junk renderMode must normalize to bars, got " .. tostring(settings.types.enemyNPC.renderMode))
        end
        if NPF.ResolveRenderMode({ renderMode = "wat" }) ~= "bars" then fail("ResolveRenderMode must reject junk") end
        if NPF.ResolveRenderMode(nil) ~= "bars" then fail("ResolveRenderMode must survive a nil type config") end
    end)
end

do
    local cvarWrites = {}
    CreateFrame = function() return NewFrame(nil) end
    InCombatLockdown = function() return false end
    SetCVar = function(name, value) cvarWrites[name] = value end
    local cvarInfoHasSimplifiedScale = false
    C_CVar = {
        SetCVarBitfield = noop,
        GetCVarInfo = function(name)
            if name == "nameplateSimplifiedScale" and cvarInfoHasSimplifiedScale then
                return { defaultValue = "1" }
            end
            return nil
        end,
    }

    local cvarsSettings = {
        enabled = true,
        simplified = { scale = 1.25 },
        cvars = {},
        fading = {},
    }
    local ns5 = {
        Helpers = {
            IsSecretValue = function() return false end,
            GetModuleSettings = function() return cvarsSettings end,
        },
    }
    assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns5)
    assert(loadfile("QUI_Nameplates/nameplates/cvars.lua"))("QUI_Nameplates", ns5)
    local NPCVars5 = ns5.QUI_NameplatesCVars
    if not NPCVars5 then fail("cvars.lua did not export ns.QUI_NameplatesCVars") end

    test("nameplateSimplifiedScale is written when the CVar exists on this client", function()
        cvarWrites = {}
        cvarInfoHasSimplifiedScale = true
        NPCVars5.ApplyScaleEnvironment()
        if cvarWrites.nameplateSimplifiedScale ~= 1.25 then
            fail("expected nameplateSimplifiedScale 1.25, got " .. tostring(cvarWrites.nameplateSimplifiedScale))
        end
    end)

    test("nameplateSimplifiedScale is skipped when the CVar does not exist on this client", function()
        cvarWrites = {}
        cvarInfoHasSimplifiedScale = false
        NPCVars5.ApplyScaleEnvironment()
        if cvarWrites.nameplateSimplifiedScale ~= nil then
            fail("must not write a CVar the client does not expose")
        end
    end)
end

test("the feature no-ops when the API is absent", function()
    _G.C_NamePlateManager = nil
    simplifiedCalls = {}

    local ns2 = {
        Helpers = {
            IsSecretValue = function() return false end,
            GetModuleSettings = function() return { enabled = true, types = {} } end,
        },
    }
    assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns2)
    assert(loadfile("QUI_Nameplates/nameplates/driver.lua"))("QUI_Nameplates", ns2)
    local NP2 = ns2.QUI_Nameplates
    if NP2.SIMPLIFIED_AVAILABLE ~= false then fail("SIMPLIFIED_AVAILABLE must be false without the API") end

    NP2.Driver.ApplySimplified({ npType = "minorTrivial", unit = "nameplate1" })
    if #simplifiedCalls ~= 0 then fail("must not call a missing API") end
end)

print("OK: nameplates_render_mode_test")
