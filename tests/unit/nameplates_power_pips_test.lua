local function fail(msg)
    print("FAIL: nameplates_power_pips_test - " .. msg)
    os.exit(1)
end

local function noop() end

local function NewRegion(parent)
    return {
        _parent = parent, _shown = false,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop, SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetWidth = noop, SetHeight = noop,
        SetColorTexture = noop, SetVertexColor = noop, SetTexture = noop,
        SetAlpha = noop, SetDrawLayer = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
    }
end

local createdFrames = {}
CreateFrame = function(_, _, parent)
    local f = NewRegion(parent)
    f._events = {}
    f._scripts = {}
    f.RegisterEvent = function(self, e) self._events[e] = "all" end
    f.RegisterUnitEvent = function(self, e, u) self._events[e] = u end
    f.UnregisterEvent = function(self, e) self._events[e] = nil end
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 1 end
    f.EnableMouse = noop
    createdFrames[#createdFrames + 1] = f
    return f
end

UIParent = CreateFrame("Frame")
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) fn() end }
GetTime = function() return 1000 end
Enum = {
    PowerType = {
        ComboPoints = 4, HolyPower = 9, SoulShards = 7,
        ArcaneCharges = 16, Chi = 12, Essence = 19, Runes = 5,
    },
}
RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 } }
UnitClass = function() return "Rogue", "ROGUE" end
UnitPower = function() return 0 end
UnitPowerMax = function() return 5 end
GetRuneCooldown = function() return 0, 10, true end
GetShapeshiftFormID = function() return nil end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return { enabled = true } end,
    },
    UIKit = {
        CreateBorderLines = noop,
        UpdateBorderLines = noop,
        CreateBackground = function(parent) return NewRegion(parent) end,
        ResolveFontPath = function() return "font.ttf" end,
    },
    Addon = {
        Pixels = function(_, v) return v end,
        SetPixelPerfectSize = function(_, f, w, h) f:SetSize(w, h) end,
        ApplyFont = noop,
    },
}

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_power.lua"))("QUI_Nameplates", ns)

local Power = ns.QUI_Nameplates and ns.QUI_Nameplates.Power
if not Power then fail("NP.Power not exported") end
if not Power.ResolvePips then fail("NPPower.ResolvePips not exported") end
if not Power.AttachToTarget then fail("NPPower.AttachToTarget not exported") end
if not Power.Detach then fail("NPPower.Detach not exported") end

local function pips(cur, max)
    local a, b = Power.ResolvePips(cur, max)
    if a == nil then return "nil" end
    return a .. "/" .. b
end

local function eq(label, got, want)
    if got ~= want then
        fail(("%s: expected %s got %s"):format(label, tostring(want), tostring(got)))
    end
end

eq("in range passes through", pips(3, 5), "3/5")
eq("over max clamps down", pips(7, 5), "5/5")
eq("negative clamps to zero", pips(-2, 5), "0/5")
eq("zero filled is valid", pips(0, 5), "0/5")
eq("nil current rejected", pips(nil, 5), "nil")
eq("nil max rejected", pips(3, nil), "nil")
eq("zero max rejected", pips(3, 0), "nil")
eq("absurd max rejected", pips(3, 99), "nil")
eq("non-number current rejected", pips("3", 5), "nil")
eq("max at the cap is allowed", pips(10, 10), "10/10")

if Power.GetClassPowerSpec then
    local spec = Power.GetClassPowerSpec("ROGUE")
    if type(spec) ~= "table" or spec.type ~= Enum.PowerType.ComboPoints then
        fail("ROGUE must map to ComboPoints")
    end
    if Power.GetClassPowerSpec("WARRIOR") ~= nil then
        fail("WARRIOR has no pip resource and must map to nil")
    end
    local dk = Power.GetClassPowerSpec("DEATHKNIGHT")
    if type(dk) ~= "table" or dk.runes ~= true then
        fail("DEATHKNIGHT must be flagged as rune-driven")
    end
end

local src = io.open("QUI_Nameplates/nameplates/plate_power.lua", "rb")
if not src then fail("plate_power.lua not found") end
local text = src:read("*a")
src:close()
for _, member in ipairs({
    "ComboPoints", "HolyPower", "SoulShards", "ArcaneCharges", "Chi", "Essence",
}) do
    if not text:find("Enum.PowerType." .. member, 1, true) then
        fail("plate_power.lua must reference Enum.PowerType." .. member)
    end
end
if text:find("RegisterEvent(\"UNIT_POWER_FREQUENT\")", 1, true) then
    fail("UNIT_POWER_FREQUENT must be a RegisterUnitEvent on player, not a broadcast RegisterEvent")
end

local toc = io.open("QUI_Nameplates/QUI_Nameplates.toc", "rb")
if not toc then fail("TOC not found") end
local tocText = toc:read("*a")
toc:close()
if not tocText:find("plate_power.lua", 1, true) then
    fail("plate_power.lua is missing from QUI_Nameplates.toc — the file would never load in game")
end

print("OK: nameplates_power_pips_test")
