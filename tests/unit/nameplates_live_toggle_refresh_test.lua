local function fail(msg)
    print("FAIL: nameplates_live_toggle_refresh_test - " .. msg)
    os.exit(1)
end

local function noop() end
local unpack = unpack or table.unpack

local function NewRegion(parent)
    return {
        _parent = parent, _shown = true, _alpha = 1,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = function(self, t) self._allPoints = t end,
        SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetWidth = noop, SetHeight = noop,
        GetAlpha = function(self) return self._alpha end,
        SetAlpha = function(self, a) self._alpha = a end,
        SetAlphaFromBoolean = noop,
        SetColorTexture = noop, SetVertexColor = noop, SetTexture = noop,
        SetAtlas = noop, SetTexCoord = noop, SetBlendMode = noop,
        AddMaskTexture = noop, SetHorizTile = noop, SetVertTile = noop,
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
    f.GetStatusBarTexture = function(self) return self._fill or NewRegion(self) end
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
C_StringUtil, C_CurveUtil, C_UnitAuras, CreateColor = nil, nil, nil, nil
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end

local typeSettings = {
    health = { width = 210, height = 24, borderSize = 1 },
    healthText = { enabled = true, style = "percent", size = 10 },
    name = { enabled = true, size = 11 },
    castbar = { enabled = true, height = 17 },
    absorbs = { enabled = true },
    colors = {},
    highlight = {},
    raidMarker = { enabled = true },
}

local settings = {
    enabled = true,
    types = { enemyNPC = typeSettings },
    cvars = { hitboxVisualizer = false },
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
        CreateIcon = function(parent)
            local f = NewFrame(parent)
            f.texture = NewRegion(f)
            f.border = NewRegion(f)
            return f
        end,
        UpdateIconLayout = noop,
    },
    Addon = {
        Pixels = function(_, v) return v end,
        SetPixelPerfectSize = function(_, f, w, h) f._w, f._h = w, h end,
        ApplyFont = noop,
    },
    L = setmetatable({}, { __index = function(_, k) return k end }),
    AuraEvents = { Subscribe = noop },
}

assert(loadfile("core/cast_engine.lua"))("QUI", ns)
for _, file in ipairs({ "shared.lua", "plate_type.lua", "cvars.lua", "plate_colors.lua", "plate_health.lua",
    "plate_castbar.lua", "plate_extras.lua" }) do
    assert(loadfile("QUI_Nameplates/nameplates/" .. file))("QUI_Nameplates", ns)
end

local NP = ns.QUI_Nameplates
local plate = CreateFrame("Frame", nil, UIParent)
NP.Health.Build(plate)
NP.Castbar.Build(plate)
NP.Extras.BuildPlate(plate)
plate.npBase = NewFrame(UIParent)
plate.npType = "enemyNPC"

local function test(name, fn) print(name); fn(); print("  ok") end

test("disabling health text clears and hides it without a plate rebuild", function()
    NP.Health.ApplyAppearance(plate, typeSettings)
    if not plate.healthText._shown then fail("enabled health text must be shown") end

    plate.healthText:SetText("65%")

    typeSettings.healthText.enabled = false
    NP.Health.ApplyAppearance(plate, typeSettings)
    if plate.healthText._shown then
        fail("disabling health text must hide it, not leave the last value on screen")
    end
    if (plate.healthText._text or "") ~= "" then
        fail("disabling health text must clear it, got " .. tostring(plate.healthText._text))
    end

    if plate.npHealthTextStyle ~= "none" then fail("style must fall to none when disabled") end
    NP.Health.UpdateHealth(plate)
    if plate.healthText._shown then fail("a later health update must not resurrect the text") end

    typeSettings.healthText.enabled = true
    NP.Health.ApplyAppearance(plate, typeSettings)
    if not plate.healthText._shown then fail("re-enabling must show the text again") end
end)

test("the hitbox visualizer follows a settings refresh, not only plate show", function()
    settings.cvars.hitboxVisualizer = false
    NP.Extras.ApplyAppearance(plate, typeSettings)
    if plate.npHitboxVis._shown then fail("disabled visualizer must stay hidden") end

    settings.cvars.hitboxVisualizer = true
    NP.Extras.ApplyAppearance(plate, typeSettings)
    if not plate.npHitboxVis._shown then
        fail("enabling must reach plates already on screen, without OnPlateShown")
    end
    if plate.npHitboxVis._allPoints ~= plate.npBase then
        fail("the visualizer must size onto the Blizzard base frame")
    end

    settings.cvars.hitboxVisualizer = false
    NP.Extras.ApplyAppearance(plate, typeSettings)
    if plate.npHitboxVis._shown then fail("disabling must reach plates already on screen") end
end)

test("a plate with no base frame never shows the visualizer", function()
    local orphan = CreateFrame("Frame", nil, UIParent)
    NP.Health.Build(orphan)
    NP.Castbar.Build(orphan)
    NP.Extras.BuildPlate(orphan)
    orphan.npType = "enemyNPC"

    settings.cvars.hitboxVisualizer = true
    NP.Extras.ApplyAppearance(orphan, typeSettings)
    if orphan.npHitboxVis._shown then fail("no npBase means nothing to outline") end
    settings.cvars.hitboxVisualizer = false
end)

print("OK: nameplates_live_toggle_refresh_test")
