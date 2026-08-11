local function fail(msg)
    print("FAIL: nameplates_classification_marker_test - " .. msg)
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
        SetTextColor = noop, SetFont = noop, SetJustifyH = noop,
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
    f.SetStatusBarColor = noop
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

local unitClassification = "elite"
local unitLevel = 80
UnitClassification = function() return unitClassification end
UnitLevel = function() return unitLevel end
UnitEffectiveLevel = function() return unitLevel end
GetCreatureDifficultyColor = function() return { r = 1, g = 0.82, b = 0 } end

local typeSettings = {
    health = { width = 210, height = 24, borderSize = 1 },
    healthText = { enabled = true, style = "percent", size = 10 },
    name = { enabled = true, size = 11 },
    castbar = { enabled = true, height = 17 },
    absorbs = { enabled = true },
    colors = {},
    highlight = {},
    level = { enabled = false, size = 9, showClassification = false, classificationSize = 14 },
}

local settings = {
    enabled = true,
    types = { enemyNPC = typeSettings },
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
        ResolveFontPath = function() return "" end,
    },
    Addon = {
        Pixels = function(_, v) return v end,
        SetPixelPerfectSize = function(_, f, w, h) f._w, f._h = w, h end,
        ApplyFont = noop,
    },
    L = setmetatable({}, { __index = function(_, k) return k end }),
    AuraEvents = { Subscribe = noop },
}

assert(loadfile("core/classification.lua"))("QUI", ns)
assert(loadfile("core/cast_engine.lua"))("QUI", ns)
for _, file in ipairs({ "shared.lua", "plate_type.lua", "cvars.lua", "plate_colors.lua", "plate_health.lua" }) do
    assert(loadfile("QUI_Nameplates/nameplates/" .. file))("QUI_Nameplates", ns)
end

local NP = ns.QUI_Nameplates
local plate = CreateFrame("Frame", nil, UIParent)
NP.Health.Build(plate)
plate.unit = "nameplate1"
plate.npType = "enemyNPC"

local function test(name, fn) print(name); fn(); print("  ok") end

local function Apply()
    NP.Health.ApplyAppearance(plate, typeSettings)
    NP.Health.UpdateLevel(plate)
end

test("the marker shows with the level number hidden", function()
    typeSettings.level.enabled = false
    typeSettings.level.showClassification = true
    Apply()

    if plate.npLevelText._shown then fail("level text must stay hidden") end
    if not plate.npClassIcon._shown then
        fail("the marker must no longer be gated behind Show Level")
    end
    if plate.npClassIcon._w ~= 14 then
        fail("marker must size from classificationSize, got " .. tostring(plate.npClassIcon._w))
    end

    local point = plate.npClassIcon._points[1]
    if not point or point[2] ~= plate.healthBar then
        fail("with no level text the marker must anchor to the health bar")
    end
end)

test("the marker still rides the level number when both are on", function()
    typeSettings.level.enabled = true
    Apply()
    if not plate.npLevelText._shown then fail("level text must show") end
    if not plate.npClassIcon._shown then fail("marker must show") end
    local point = plate.npClassIcon._points[1]
    if not point or point[2] ~= plate.npLevelText then
        fail("with level text shown the marker must anchor beside it")
    end
end)

test("the level number shows alone when the marker is off", function()
    typeSettings.level.showClassification = false
    Apply()
    if not plate.npLevelText._shown then fail("level text must show") end
    if plate.npClassIcon._shown then fail("marker must hide when its own toggle is off") end
end)

test("nameplates and unit frames resolve the same atlas and tint", function()
    typeSettings.level.showClassification = true
    Apply()

    local Classification = ns.Classification
    for _, case in ipairs({ "elite", "rare", "rareelite", "worldboss" }) do
        unitClassification = case
        Apply()
        local atlas, r, g, b = Classification.Resolve(case)
        if plate.npClassIcon._atlas ~= atlas then
            fail(case .. " must use the shared atlas, got " .. tostring(plate.npClassIcon._atlas))
        end
        local c = plate.npClassIcon._color or {}
        if c[1] ~= r or c[2] ~= g or c[3] ~= b then
            fail(case .. " must use the shared tint")
        end
    end

    unitClassification = "normal"
    Apply()
    if plate.npClassIcon._shown then fail("a normal mob must show no marker") end
end)

test("a level -1 unit falls back to the boss marker", function()
    unitClassification = "normal"
    unitLevel = -1
    Apply()
    local atlas = ns.Classification.Resolve("worldboss")
    if plate.npClassIcon._atlas ~= atlas then
        fail("level -1 must resolve as a boss, got " .. tostring(plate.npClassIcon._atlas))
    end
    unitLevel = 80
end)

print("OK: nameplates_classification_marker_test")
