-- tests/unit/nameplates_aura_no_delta_subscription_test.lua
-- Run: lua tests/unit/nameplates_aura_no_delta_subscription_test.lua
--
-- The Lua aura-delta consumer plate_auras.lua used to own (pooled
-- addedAuras/removedAuraInstanceIDs/updatedAuraInstanceIDs dispatch,
-- classify-into-channels, rate-limited flush) is gone: the engine's
-- CustomAuraContainer self-drives off UNIT_AURA now, so nameplates must
-- never register a ns.AuraEvents:Subscribe("nameplate", ...) dispatcher
-- tier at all. This is a regression guard, not a behavioural test of a
-- consumer that no longer exists.

local function fail(msg)
    print("FAIL: nameplates_aura_no_delta_subscription_test - " .. msg)
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

_G.QUI = { AuraSkin = {
    Configure = noop,
    Restyle = noop,
    LayoutAnchor = function() return "TOPLEFT" end,
} }

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
NP.Extras = { GetContext = function() return { instanceKind = "world" } end }

local subscribed = false
ns.AuraEvents = { Subscribe = function() subscribed = true end }

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
if subscribed then
    fail("ApplyAppearance must not subscribe to aura events on the container path")
end

local pool = plate._quiAuraContainers
if not pool or #pool ~= 3 then
    fail("sanity check failed: the container pass itself did not run (got "
        .. tostring(pool and #pool) .. " containers) -- the no-subscription result above would be meaningless")
end

print("OK: nameplates_aura_no_delta_subscription_test")
