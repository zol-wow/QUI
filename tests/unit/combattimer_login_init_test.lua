-- tests/unit/combattimer_login_init_test.lua
-- Run: lua tests/unit/combattimer_login_init_test.lua
--
-- Regression guard for the "Eager-LOD self-ADDON_LOADED init is DEAD" class.
-- QUI_QoL is eager-LoadAddOn'd by the core from OnEnable, so this module's own
-- ADDON_LOADED self-event is never delivered to its just-registered handler.
-- combattimer registers its runtime events (PLAYER_REGEN_DISABLED/ENABLED,
-- ENCOUNTER_START/END) lazily via UpdateEventRegistrations(), which previously
-- ran ONLY inside the (undelivered) ADDON_LOADED branch -- so the timer frame
-- was never created and no combat event was ever registered (in-game report:
-- "not seeing the combat timer in an encounter").
--
-- Init must therefore run via ns.WhenLoggedIn (fires immediately for a
-- post-login LOD load). This test NEVER fires ADDON_LOADED, so it only passes
-- if init hangs off ns.WhenLoggedIn.

local function noop() end

-- Track every event registered on any frame, and every named frame created.
local registeredEvents = {}
local namedFrames = {}

local function newFrame(name)
    local frame = { _events = {} }
    if name then namedFrames[name] = frame end
    local methods = {}
    function methods:RegisterEvent(ev) self._events[ev] = true; registeredEvents[ev] = true end
    function methods:RegisterUnitEvent(ev) self._events[ev] = true; registeredEvents[ev] = true end
    function methods:UnregisterEvent(ev) self._events[ev] = nil end
    function methods:CreateTexture() return newFrame() end
    function methods:CreateFontString() return newFrame() end
    return setmetatable(frame, { __index = function(_, k) return methods[k] or noop end })
end

function CreateFrame(_, name) return newFrame(name) end
function InCombatLockdown() return false end
function IsLoggedIn() return true end
function GetTime() return 0 end

UIParent = newFrame("UIParent")

local settings = { enabled = true }

local ns = {
    __test = true,
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
        GetSkinBgColor = function() return 0, 0, 0 end,
        -- nil CreateOnUpdateThrottle is fine: the module falls back internally.
    },
    UIKit = {
        GetBackdropInfo = function() return {} end,
        CreateBorderLines = noop,
        UpdateBorderLines = noop,
    },
    -- ns.WhenLoggedIn fires the callback immediately when already logged in,
    -- mirroring init.lua for a sub-addon loaded after PLAYER_LOGIN. This is the
    -- ONLY init path that runs for an eager-LOD module.
    WhenLoggedIn = function(fn) if fn then fn() end end,
}

assert(loadfile("QUI_QoL/qol/combattimer.lua"))("QUI_QoL", ns)

-- 1) The timer frame must be created at login.
assert(namedFrames["QUI_CombatTimer"],
    "QUI_CombatTimer frame should be created at login via ns.WhenLoggedIn")

-- 2) With the feature enabled, the runtime combat events must be registered at
--    login. Without WhenLoggedIn init, UpdateEventRegistrations() never runs and
--    none of these are registered -> the timer never tracks combat.
for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END" }) do
    assert(registeredEvents[ev],
        "runtime event '" .. ev .. "' should be registered at login (UpdateEventRegistrations via ns.WhenLoggedIn)")
end

print("OK: combattimer_login_init_test")
