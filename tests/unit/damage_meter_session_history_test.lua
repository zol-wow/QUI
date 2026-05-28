-- tests/unit/damage_meter_session_history_test.lua
-- Run: lua tests/unit/damage_meter_session_history_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("modules/damage_meter/damage_meter.lua")

local start_pos = src:find("local function SessionKey")
assert(start_pos, "could not locate SessionKey helper")
local end_pos = src:find("QUI_DamageMeter%.SessionKey", start_pos)
assert(end_pos, "could not locate QUI_DamageMeter.SessionKey assignment")
local chunk = src:sub(start_pos, end_pos - 1):match("^(.-)\n%s*$")
local SessionKey = assert(loadstring(chunk .. "\nreturn SessionKey"))()

assert(SessionKey(1, nil) == "type:1", "Current selector key must be type-backed")
assert(SessionKey(0, nil) == "type:0", "Overall selector key must be type-backed")
assert(SessionKey(1, 1) == "id:1", "sessionID must take precedence over sessionType")
assert(SessionKey(0, 42) == "id:42", "historical selector key must use the sessionID")
assert(SessionKey(1, 1) ~= SessionKey(1, nil), "id:1 and type:1 must not collide")

assert(src:find("GetCombatSessionFromID", 1, true),
    "main views must support C_DamageMeter.GetCombatSessionFromID")
assert(src:find("GetCombatSessionSourceFromID", 1, true),
    "breakdowns must support C_DamageMeter.GetCombatSessionSourceFromID")
assert(src:find("GetAvailableCombatSessions", 1, true),
    "menu must use C_DamageMeter.GetAvailableCombatSessions")
assert(src:find('root:CreateButton("Previous"', 1, true),
    "Session menu must expose a Previous submenu")
assert(src:find("previousMenu:CreateRadio", 1, true),
    "Previous submenu must create selectable session rows")
assert(src:find("availableSession.name", 1, true),
    "Previous submenu rows must use Blizzard's session name field")
assert(src:find("self.sessionID = nil", 1, true),
    "Window runtime state must initialize sessionID to nil")

local defaults = readAll("core/defaults.lua")
local nativeStart = defaults:find("native = {", 1, true)
assert(nativeStart, "could not locate damageMeter.native defaults")
local nativeEnd = defaults:find("\n%s*alerts%s*=", nativeStart) or #defaults
local nativeBlock = defaults:sub(nativeStart, nativeEnd)
assert(not nativeBlock:find("sessionID", 1, true),
    "sessionID must remain runtime-only and absent from damage meter defaults")

print("OK: damage_meter_session_history_test")
