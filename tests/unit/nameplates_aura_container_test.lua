-- tests/unit/nameplates_aura_container_test.lua
-- Run: lua tests/unit/nameplates_aura_container_test.lua
--
-- Shared element-model container path: NPAuras.Build/ApplyAppearance drive
-- NP.DefaultNameplateBucket()'s three seeded elements through
-- ns.AuraSurface.ApplyElementPass into a per-ordinal container pool on
-- plate._quiAuraContainers -- the master switch and the per-context gate
-- (world/dungeon/raid) both route through NPAuras.ResolveElements, which
-- empties the pool's active-element list rather than touching each
-- container directly, and every container anchors to plate.healthBar, not
-- the plate itself.

local function fail(msg)
    print("FAIL: nameplates_aura_container_test - " .. msg)
    os.exit(1)
end
local function noop() end

local function NewRegion(parent)
    return { _parent = parent, _shown = true,
        SetParent = noop,
        SetAllPoints = function(self, target) self._allPoints = target end,
        SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetColorTexture = noop,
        SetTexture = function(self, value) self._texture = value end,
        GetTexture = function(self) return self._texture end,
        SetVertexColor = function(self, ...) self._vertexColor = { ... } end,
        SetAlpha = function(self, value) self._alpha = value end,
        SetIgnoreParentAlpha = function(self, value) self._ignoreParentAlpha = value end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetText = noop, SetFont = noop, SetTextColor = noop, SetJustifyH = noop }
end
local function NewFrame(parent)
    local f = NewRegion(parent)
    f._scripts = {}
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.RegisterEvent = noop; f.RegisterUnitEvent = noop; f.UnregisterAllEvents = noop
    f.EnableMouse = noop
    f.SetFrameLevel = function(self, value) self._frameLevel = value end
    f.GetFrameLevel = function(self) return self._frameLevel or 1 end
    f.SetFrameStrata = function(self, value) self._frameStrata = value end
    f.GetFrameStrata = function(self) return self._frameStrata or "MEDIUM" end
    f.GetParent = function(self) return self._parent end
    f.IsShown = function(self) return self._shown end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    return f
end

CreateFrame = function(kind, name, parent)
    if kind == "AuraContainer" then
        local c = NewFrame(parent)
        c._enabled = nil
        c._points = {}
        c.SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end
        c.SetUnit = function(self, unit)
            assert(type(unit) == "string", "SetUnit requires a unit")
            self._unit = unit
        end
        c.SetEnabled = function(self, e) self._enabled = e end
        return c
    end
    return NewFrame(parent)
end
UIParent = NewFrame(nil)
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = noop } end }
InCombatLockdown = function() return false end
Enum = {}
AuraContainerSortMethod = { Default = 0, Expiration = 4 }

_G.QUI = { AuraSkin = {
    Configure = noop,
    Restyle = noop,
    LayoutAnchor = function(profile) return "TOPLEFT" end,
} }

local instanceKind = "world"
local settings
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return settings end,
    },
    Addon = { Pixels = function(_, v) return v end },
    AuraSlots = { Park = noop, Sync = function() return true end },
}

assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("core/aura_glue.lua"))("QUI", ns)
assert(loadfile("core/aura_surface.lua"))("QUI", ns)
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", ns)
local NP = ns.QUI_Nameplates
NP.Extras = { GetContext = function() return { instanceKind = instanceKind } end }
assert(loadfile("QUI_Nameplates/nameplates/plate_auras.lua"))("QUI_Nameplates", ns)
local NPAuras = NP.Auras

local function NewPlate()
    local plate = NewFrame(UIParent)
    plate.healthBar = NewFrame(plate)
    local fill = NewRegion(plate.healthBar)
    fill._texture = "nameplate-health-texture"
    plate.healthBar.GetStatusBarTexture = function() return fill end
    plate.npType = "enemyNPC"
    return plate
end

local auraSettings = { enabled = true, elements = {} }
local typeSettings = { auras = auraSettings }
settings = { types = { enemyNPC = typeSettings } }

do
    local prewarmPlate = NewPlate()
    NPAuras.ApplyAppearance(prewarmPlate)
    if prewarmPlate._quiAuraContainers ~= nil then
        fail("ApplyAppearance on a plate with no unit (the genuine prewarm state) must not create containers")
    end
end

do
    local buildOnlyPlate = NewPlate()
    buildOnlyPlate.unit = "nameplate2"
    NPAuras.ApplyAppearance(buildOnlyPlate)
    local buildPool = buildOnlyPlate._quiAuraContainers
    if not buildPool or #buildPool ~= 3 then
        fail("first ApplyAppearance must create the container pool, got "
            .. tostring(buildPool and #buildPool))
    end
    for i = 1, 3 do
        if buildPool[i]._unit ~= "nameplate2" then fail("first ApplyAppearance must bind the unit on container " .. i) end
        if buildPool[i]._shown ~= true then fail("first ApplyAppearance must show container " .. i) end
    end
end

local plate = NewPlate()
plate.unit = "nameplate1"

NPAuras.ApplyAppearance(plate)

local pool = plate._quiAuraContainers
if not pool or #pool ~= 3 then
    fail("default seed must produce three containers, got " .. tostring(pool and #pool))
end
for i = 1, 3 do
    if pool[i]._unit ~= "nameplate1" then fail("container " .. i .. " must bind the unit") end
    if pool[i]._shown ~= true then fail("container " .. i .. " must be shown") end
end

auraSettings.enabled = false
NPAuras.ApplyAppearance(plate)
for i = 1, 3 do
    if pool[i]._shown ~= false then fail("master off must hide container " .. i) end
    if pool[i]._enabled ~= false then fail("master off must disable container " .. i) end
end

auraSettings.enabled = true
auraSettings.enableDungeon = false
instanceKind = "dungeon"
NPAuras.ApplyAppearance(plate)
if pool[1]._shown ~= false then fail("dungeon gate off must hide containers") end

auraSettings.enableDungeon = true
instanceKind = "world"
NPAuras.ApplyAppearance(plate)
for i = 1, 3 do
    if pool[i]._shown ~= true then fail("re-enabling must show container " .. i .. " again") end
end
local anchored = pool[1]._points[#pool[1]._points]
if not anchored then fail("container must be anchored") end
if anchored[2] ~= plate.healthBar then
    fail("containers must anchor to plate.healthBar, not the plate")
end
if anchored[1] ~= "TOPLEFT" then
    fail("container 1 must pin at AuraSkin.LayoutAnchor's corner (TOPLEFT), got " .. tostring(anchored[1]))
end
if anchored[3] ~= "TOP" then
    fail("container 1 must attach to element.anchor (TOP), got " .. tostring(anchored[3]))
end
if anchored[4] ~= 0 then
    fail("container 1 X offset must be element.offsetX (0), got " .. tostring(anchored[4]))
end
if anchored[5] ~= 20 then
    fail("container 1 Y offset must be element.offsetY (20), got " .. tostring(anchored[5]))
end

do
    local oldElements, oldSeeded = auraSettings.elements, auraSettings.elementsSeeded
    local element = {
        id = "tint", enabled = true, mode = "tracked", auraType = "HARMFUL",
        spells = { 12345 }, onlyMine = true, displayType = "healthTint",
        color = { 0.8, 0.1, 0.2, 0.4 },
    }
    auraSettings.elements = { ["*"] = { element } }
    auraSettings.elementsSeeded = true
    local tintPlate = NewPlate()
    tintPlate.unit = "nameplate3"
    NPAuras.ApplyAppearance(tintPlate)
    local container = tintPlate._quiAuraContainers and tintPlate._quiAuraContainers[1]
    if not container or type(container._quiFeederAttach) ~= "function" then
        fail("healthTint container must receive a nameplate-local feeder handler")
    end
    local slot = NewFrame(container)
    container._quiFeederAttach(slot, element)
    local cover = slot._quiFeederTint
    if not cover then fail("healthTint feeder must create passive cover art") end
    if cover._allPoints ~= tintPlate.healthBar:GetStatusBarTexture() then
        fail("healthTint cover must follow the real health fill")
    end
    if cover._texture ~= "nameplate-health-texture" then
        fail("healthTint cover must reuse the health fill texture")
    end
    if not cover._vertexColor or cover._vertexColor[1] ~= 0.8
        or cover._vertexColor[2] ~= 0.1 or cover._vertexColor[3] ~= 0.2
        or cover._alpha ~= 0.4 then
        fail("healthTint cover must apply the configured color and alpha")
    end
    container._quiFeederDetach(slot)
    if cover._shown ~= false then fail("retiring healthTint must hide its cover") end
    auraSettings.elements, auraSettings.elementsSeeded = oldElements, oldSeeded
end

NPAuras.Clear(plate)
for i = 1, 3 do
    if pool[i]._shown ~= false then fail("Clear must hide container " .. i) end
    if pool[i]._enabled ~= false then fail("Clear must disable container " .. i) end
    if pool[i]._unit ~= "nameplate1" then fail("Clear must not unbind container " .. i .. "'s unit") end
end

print("OK: nameplates_aura_container_test")
