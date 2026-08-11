local function fail(msg)
    print("FAIL: nameplates_per_type_render_test - " .. msg)
    os.exit(1)
end

local function noop() end
local unpack = unpack or table.unpack

local function NewRegion(parent)
    return {
        _parent = parent, _shown = true, _alpha = 1, _points = {},
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop,
        SetPoint = function(self, p, rel, relP, x, y)
            self._points[#self._points + 1] = { p, rel, relP, x, y }
        end,
        ClearAllPoints = function(self) self._points = {} end,
        SetSize = noop, SetWidth = noop, SetHeight = noop,
        GetAlpha = function(self) return self._alpha end,
        SetAlpha = function(self, a) self._alpha = a end,
        SetAlphaFromBoolean = noop,
        SetColorTexture = noop,
        SetVertexColor = function(self, r, g, b) self._color = { r, g, b } end,
        SetTexture = noop,
        SetAtlas = function(self, atlas) self._atlas = atlas end,
        SetTexCoord = noop, SetBlendMode = noop, AddMaskTexture = noop,
        SetHorizTile = noop, SetVertTile = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetShown = function(self, v) self._shown = v and true or false end,
        IsShown = function(self) return self._shown end,
        SetText = function(self, t) self._text = t end,
        SetFormattedText = function(self, fmt, ...) self._text = string.format(fmt, ...) end,
        SetTextColor = function(self, r, g, b) self._textColor = { r, g, b } end,
        SetFont = noop, SetJustifyH = noop,
        SetDrawLayer = noop, SetShadowOffset = noop, SetShadowColor = noop,
    }
end

local function NewFrame(parent)
    local f = NewRegion(parent)
    f._scripts = {}
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.HookScript = noop
    f.RegisterEvent = noop
    f.RegisterUnitEvent = noop
    f.UnregisterAllEvents = noop
    f.EnableMouse = noop
    f.SetFrameStrata = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 1 end
    f.SetScale = noop
    f.SetIgnoreParentScale = noop
    f.GetWidth = function() return 210 end
    f.GetHeight = function() return 24 end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateMaskTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    f.SetStatusBarTexture = noop
    f.GetStatusBarTexture = function(self) return NewRegion(self) end
    f.SetStatusBarColor = function(self, r, g, b) self._color = { r, g, b } end
    f.SetMinMaxValues = noop
    f.SetValue = noop
    f.SetDrawEdge = noop
    f.GetRegions = function() return nil end
    f.GetChildren = function(self) return unpack(self._children or {}) end
    return f
end

CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame(nil)
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 0 end
InCombatLockdown = function() return false end
SetCVar = noop
RAID_CLASS_COLORS = {}
Enum = {}
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
UnitClassification = function() return "normal" end
UnitLevel = function() return 80 end
UnitEffectiveLevel = function() return 80 end
UnitExists = function() return true end
UnitHealth = function() return 750 end
UnitHealthMax = function() return 1000 end
UnitHealthPercent = function() return 75 end
UnitGetTotalAbsorbs = function() return 0 end
UnitIsDeadOrGhost = function() return false end
UnitName = function() return "Boar" end
UnitIsPlayer = function() return false end
GetCreatureDifficultyColor = function() return { r = 1, g = 0.82, b = 0 } end

local playerClassToken = "ROGUE"
UnitClass = function() return "Rogue", playerClassToken end
UnitPower = function() return 3 end
UnitPowerMax = function() return 5 end
UnitPowerType = function() return 0 end

local function TypeBlock()
    return {
        health = { width = 210, height = 24, borderSize = 1 },
        healthText = { enabled = true, style = "percent", size = 10 },
        name = { enabled = true, size = 11 },
        npcTitle = { enabled = false },
        castbar = { enabled = true, height = 17 },
        absorbs = { enabled = true },
        healPrediction = {},
        powerBar = {},
        colors = {},
        highlight = {},
        raidMarker = { enabled = true, size = 24 },
        questIcon = {},
        pvpIcon = {},
        font = { face = "", outline = "OUTLINE" },
        level = { enabled = false, size = 9, showClassification = false, classificationSize = 14 },
        power = { enabled = false, size = 10, spacing = 3 },
        auras = {},
    }
end

local settings = {
    enabled = true,
    types = {
        enemyNPC = TypeBlock(),
        enemyPlayer = TypeBlock(),
        bossElite = TypeBlock(),
        minorTrivial = TypeBlock(),
        petMinion = TypeBlock(),
        friendly = TypeBlock(),
    },
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeToNumber = function(v, fb) return tonumber(v) or fb or 0 end,
        TruncateUTF8 = function(s) return s end,
        GetModuleSettings = function() return settings end,
        GetProfile = function() return { nameplates = settings } end,
    },
    UIKit = {
        CreateBackground = function(parent) return NewRegion(parent) end,
        CreateBorderLines = noop, UpdateBorderLines = noop,
        CreateText = function(parent) return NewRegion(parent) end,
        ResolveFontPath = function() return "base.ttf" end,
    },
    Addon = {
        Pixels = function(_, v) return v end,
        SetPixelPerfectSize = function(_, f, w, h) f._w, f._h = w, h end,
        ApplyFont = function(_, region, _, size, path, outline)
            region._font = { size = size, path = path, outline = outline }
        end,
    },
    L = setmetatable({}, { __index = function(_, k) return k end }),
    AuraEvents = { Subscribe = noop },
}

assert(loadfile("core/classification.lua"))("QUI", ns)
assert(loadfile("core/cast_engine.lua"))("QUI", ns)

local SUITE = {
    "shared.lua", "plate_type.lua", "cvars.lua", "plate_colors.lua", "plate_health.lua",
    "plate_castbar.lua", "plate_auras.lua", "plate_extras.lua", "plate_power.lua",
    "driver.lua",
}
for _, file in ipairs(SUITE) do
    assert(loadfile("QUI_Nameplates/nameplates/" .. file))("QUI_Nameplates", ns)
end

local NP = ns.QUI_Nameplates
if not NP then fail("suite did not export ns.QUI_Nameplates") end

local function BuildPlate()
    local plate = CreateFrame("Frame", nil, UIParent)
    NP.Health.Build(plate)
    NP.Castbar.Build(plate)
    NP.Extras.BuildPlate(plate)
    plate.npStackBounds = CreateFrame("Frame", nil, plate)
    plate.unit = "nameplate1"
    return plate
end

local plate = BuildPlate()

local function test(name, fn) print(name); fn(); print("  ok") end

test("a boss plate renders from the bossElite config", function()
    settings.types.bossElite.health.width = 300
    settings.types.enemyNPC.health.width = 210
    plate.npType = "bossElite"
    NP.Health.ApplyAppearance(plate, NP.GetTypeSettings(plate))
    if plate.healthBar._w ~= 300 then
        fail("expected the bossElite width, got " .. tostring(plate.healthBar._w))
    end
end)

test("an npc plate renders from the enemyNPC config", function()
    settings.types.bossElite.health.width = 300
    settings.types.enemyNPC.health.width = 210
    plate.npType = "enemyNPC"
    NP.Health.ApplyAppearance(plate, NP.GetTypeSettings(plate))
    if plate.healthBar._w ~= 210 then
        fail("expected the enemyNPC width, got " .. tostring(plate.healthBar._w))
    end
end)

test("ResolveFont reads the plate's own type", function()
    settings.types.bossElite.font = { face = "", outline = "THICKOUTLINE" }
    settings.types.enemyNPC.font = { face = "", outline = "OUTLINE" }
    plate.npType = "bossElite"
    local _, outline = NP.ResolveFont(plate)
    if outline ~= "THICKOUTLINE" then
        fail("expected the bossElite outline, got " .. tostring(outline))
    end
    plate.npType = "enemyNPC"
    local _, plain = NP.ResolveFont(plate)
    if plain ~= "OUTLINE" then
        fail("expected the enemyNPC outline, got " .. tostring(plain))
    end
end)

test("ResolveFont with no plate falls back to the default type", function()
    settings.types.enemyNPC.font = { face = "", outline = "THICKOUTLINE" }
    local _, outline = NP.ResolveFont(nil)
    if outline ~= "THICKOUTLINE" then
        fail("expected the default type outline, got " .. tostring(outline))
    end
    settings.types.enemyNPC.font = { face = "", outline = "OUTLINE" }
end)

test("the castbar sizes from the plate's own type", function()
    settings.types.bossElite.castbar.height = 30
    settings.types.enemyNPC.castbar.height = 17
    plate.npType = "bossElite"
    NP.Castbar.ApplyAppearance(plate, NP.GetTypeSettings(plate))
    if plate.castBar._h ~= 30 then
        fail("expected the bossElite castbar height, got " .. tostring(plate.castBar._h))
    end
    plate.npType = "enemyNPC"
    NP.Castbar.ApplyAppearance(plate, NP.GetTypeSettings(plate))
    if plate.castBar._h ~= 17 then
        fail("expected the enemyNPC castbar height, got " .. tostring(plate.castBar._h))
    end
end)

test("the raid marker sizes from the plate's own type", function()
    settings.types.bossElite.raidMarker.size = 40
    settings.types.enemyNPC.raidMarker.size = 24
    plate.npType = "bossElite"
    NP.Extras.ApplyAppearance(plate, NP.GetTypeSettings(plate))
    if plate.npRaidMarker._w ~= 40 then
        fail("expected the bossElite marker size, got " .. tostring(plate.npRaidMarker._w))
    end
    plate.npType = "enemyNPC"
    NP.Extras.ApplyAppearance(plate, NP.GetTypeSettings(plate))
    if plate.npRaidMarker._w ~= 24 then
        fail("expected the enemyNPC marker size, got " .. tostring(plate.npRaidMarker._w))
    end
end)

test("the name colour comes from the plate's own type", function()
    settings.types.bossElite.name.color = { 1, 0, 0 }
    settings.types.enemyNPC.name.color = { 0, 0, 1 }
    plate.npIsPlayer = false
    plate.npType = "bossElite"
    NP.Health.UpdateName(plate)
    local c = plate.nameText._textColor or {}
    if c[1] ~= 1 or c[3] ~= 0 then
        fail("expected the bossElite name colour, got " .. tostring(c[1]) .. "," .. tostring(c[3]))
    end
    plate.npType = "enemyNPC"
    NP.Health.UpdateName(plate)
    c = plate.nameText._textColor or {}
    if c[1] ~= 0 or c[3] ~= 1 then
        fail("expected the enemyNPC name colour, got " .. tostring(c[1]) .. "," .. tostring(c[3]))
    end
end)

test("the class power row sizes from the plate's own type", function()
    settings.types.bossElite.power = { enabled = true, size = 18, spacing = 3 }
    settings.types.enemyNPC.power = { enabled = true, size = 8, spacing = 3 }
    plate.npType = "bossElite"
    NP.Power.RenderPreview(plate)
    local row = plate.npPowerPreviewRow
    if not row then fail("the preview row was never built") end
    local bossTotal = row._w
    plate.npType = "enemyNPC"
    NP.Power.RenderPreview(plate)
    if row._w == bossTotal then
        fail("the pip row must resize with the plate's type, stayed at " .. tostring(bossTotal))
    end
    settings.types.bossElite.power.enabled = false
    settings.types.enemyNPC.power.enabled = false
end)

test("the driver re-applies appearance when a plate changes type", function()
    local drvPlate = BuildPlate()
    NP.plates["nameplate1"] = drvPlate
    settings.types.bossElite.health.width = 300
    settings.types.enemyNPC.health.width = 210

    drvPlate.npType = "enemyNPC"
    NP.RestyleActivePlates()
    if drvPlate.healthBar._w ~= 210 then
        fail("expected the enemyNPC width first, got " .. tostring(drvPlate.healthBar._w))
    end

    drvPlate.npType = "bossElite"
    NP.RestyleActivePlates()
    if drvPlate.healthBar._w ~= 300 then
        fail("a type change must re-apply appearance, got " .. tostring(drvPlate.healthBar._w))
    end

    NP.plates["nameplate1"] = nil
end)

print("OK: nameplates_per_type_render_test")
