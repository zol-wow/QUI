-- tests/unit/nameplates_aura_multi_filter_scan_test.lua
-- Run: lua tests/unit/nameplates_aura_multi_filter_scan_test.lua
--
-- Sibling to nameplates_aura_filters_test.lua, not an extension of it: that
-- file checks E.CompileFilters/E.CompileCandidateFilters as pure functions;
-- this file drives the same "classify" fan-out through the REAL container
-- pipeline (NPAuras.Build/ApplyAppearance -> ns.AuraSurface.ApplyElementPass
-- -> AuraGlue.ElementGroups -> AuraSkin.Configure), reusing the container
-- mock from nameplates_aura_container_test.lua, to prove the multi-filter
-- fan-out this file is named for actually reaches the engine as multiple
-- distinct configure groups, not just that the compiler produces the right
-- strings in isolation.
--
-- The Lua-side "scan two C_UnitAuras queries and dedupe/concatenate by
-- instanceID" mechanism this file used to exercise no longer exists: the
-- container path never touches C_UnitAuras from Lua at all (the engine's
-- own AddAuraGroup dispatch owns that query+dedupe now, same as every other
-- container-driven surface). That half of the original coverage has no
-- headless equivalent and is dropped, not translated.

local function fail(msg)
    print("FAIL: nameplates_aura_multi_filter_scan_test - " .. msg)
    os.exit(1)
end
local function noop() end

local function NewRegion(parent)
    return { _parent = parent, _shown = true,
        SetParent = noop, SetAllPoints = noop, SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetColorTexture = noop, SetTexture = noop, SetAlpha = noop,
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
    f.EnableMouse = noop; f.SetFrameLevel = noop; f.GetFrameLevel = function() return 1 end
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

local configures = {}
_G.QUI = { AuraSkin = {
    Configure = function(container, profile, groups)
        configures[#configures + 1] = { container = container, profile = profile, groups = groups }
    end,
    Restyle = noop,
    LayoutAnchor = function() return "TOPLEFT" end,
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

local plate = NewFrame(UIParent)
plate.healthBar = NewFrame(plate)
plate.unit = "nameplate1"
plate.npType = "enemyNPC"

local auraSettings = { enabled = true, elements = {} }
local typeSettings = { auras = auraSettings }
settings = { types = { enemyNPC = typeSettings } }
NPAuras.ApplyAppearance(plate)

local pool = plate._quiAuraContainers
if not pool or #pool ~= 3 then
    fail("default seed must produce three containers, got " .. tostring(pool and #pool))
end

local buffsElement = auraSettings.elements["*"][2]
if buffsElement.auraType ~= "HELPFUL" then
    fail("element index 2 must be the buffs (HELPFUL) element, got " .. tostring(buffsElement.auraType))
end
buffsElement.filterMode = "classify"
buffsElement.classifications = { bigDefensive = true, externalDefensive = true }
NPAuras.ApplyAppearance(plate)

local buffsContainer = pool[2]
local latest
for _, cfg in ipairs(configures) do
    if cfg.container == buffsContainer then latest = cfg end
end
if not latest then fail("expected a configure pass for the buffs container") end
if #latest.groups ~= 2 then
    fail("classify(bigDefensive+externalDefensive) must yield 2 groups, got " .. tostring(#latest.groups))
end

local bigDef, extDef
for _, g in ipairs(latest.groups) do
    if g.filter:find("BIG_DEFENSIVE", 1, true) and not g.filter:find("EXTERNAL_DEFENSIVE", 1, true) then
        bigDef = g
    elseif g.filter:find("EXTERNAL_DEFENSIVE", 1, true) then
        extDef = g
    end
end
if not bigDef then fail("bigDefensive group missing from " .. tostring(latest.groups[1] and latest.groups[1].filter)) end
if not extDef then fail("externalDefensive group missing") end
if bigDef.key == extDef.key then fail("groups must carry distinct groupKeys") end
if not bigDef.filter:find("INCLUDE_NAME_PLATE_ONLY", 1, true) then
    fail("bigDefensive group must still carry the nameplate-only token")
end
if bigDef.filter:find("!", 1, true) then
    fail("the higher-priority (bigDefensive) group must carry no negation, got " .. bigDef.filter)
end
if not extDef.filter:find("!BIG_DEFENSIVE", 1, true) then
    fail("the lower-priority (externalDefensive) group must embed the !BIG_DEFENSIVE exclusivity negation, got "
        .. extDef.filter)
end
if bigDef.maxFrameCount ~= buffsElement.maxIcons or extDef.maxFrameCount ~= buffsElement.maxIcons then
    fail("every group must carry the element's maxIcons as maxFrameCount")
end

print("OK: nameplates_aura_multi_filter_scan_test")
