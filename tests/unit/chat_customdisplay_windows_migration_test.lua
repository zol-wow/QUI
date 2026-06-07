-- tests/unit/chat_customdisplay_windows_migration_test.lua
-- v42 MigrateCustomDisplayWindows: flat customDisplay {width,height,position,
-- tabs} wraps into customDisplay.windows[1]; geometry-less profiles with only
-- tabs still wrap; fully-default (empty) profiles are untouched; re-running is
-- a no-op; a profile already carrying windows[] just sheds leftover flat keys.
-- Run: lua tests/unit/chat_customdisplay_windows_migration_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, nv in pairs(v) do out[k] = deepCopy(nv) end
    return out
end
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- 1. Full flat config wraps into windows[1]
local prof = { chat = { customDisplay = {
    width = 500, height = 240,
    position = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 60 },
    tabs = { { name = "General", groups = { SAY = true }, channels = {}, invert = false } },
    maxLines = 2000,
} } }
ns.Migrations.RunOnProfile(prof)
local cd = prof.chat.customDisplay
check("windows array created", type(cd.windows) == "table" and #cd.windows == 1)
check("geometry wrapped", cd.windows[1].width == 500 and cd.windows[1].height == 240)
check("position wrapped", cd.windows[1].position and cd.windows[1].position.x == -20)
check("tabs wrapped", cd.windows[1].tabs and cd.windows[1].tabs[1]
    and cd.windows[1].tabs[1].name == "General")
check("flat keys removed", cd.width == nil and cd.height == nil
    and cd.position == nil and cd.tabs == nil)
check("global keys preserved", cd.maxLines == 2000)

-- 2. Idempotent (snapshot taken after first run so version stamp is included)
local snapshot = deepCopy(prof)
ns.Migrations.RunOnProfile(prof)
check("re-run is a no-op", deepEqual(prof, snapshot))

-- 3. Tabs-only profile (geometry stripped by AceDB) still wraps
local prof2 = { chat = { customDisplay = {
    tabs = { { name = "Raid", groups = { RAID = true }, channels = {}, invert = false } },
} } }
ns.Migrations.RunOnProfile(prof2)
local cd2 = prof2.chat.customDisplay
check("tabs-only wraps", type(cd2.windows) == "table" and cd2.windows[1].tabs[1].name == "Raid")
check("tabs-only no phantom geometry", cd2.windows[1].width == nil)

-- 4. Fully-default profile: no flat keys -> no windows fabricated
local prof3 = { chat = { customDisplay = { maxLines = 1500 } } }
ns.Migrations.RunOnProfile(prof3)
check("default profile untouched",
    prof3.chat.customDisplay.windows == nil
    or #prof3.chat.customDisplay.windows == 0)

-- 5. Profile already on windows[] sheds leftover flat keys
local prof4 = { chat = { customDisplay = {
    windows = { { width = 300, height = 100, tabs = {} } },
    tabs = { { name = "stale" } }, width = 999,
} } }
ns.Migrations.RunOnProfile(prof4)
local cd4 = prof4.chat.customDisplay
check("existing windows kept", cd4.windows[1].width == 300)
check("leftover flat keys dropped", cd4.tabs == nil and cd4.width == nil)

-- 6. Position-only profile (width/height/tabs stripped as defaults) wraps
local profP = { chat = { customDisplay = {
    position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
} } }
ns.Migrations.RunOnProfile(profP)
local cdP = profP.chat.customDisplay
check("position-only wraps", type(cdP.windows) == "table" and #cdP.windows == 1)
check("position-only preserves point", cdP.windows[1].position and cdP.windows[1].position.point == "CENTER")
check("position-only no phantom width", cdP.windows[1].width == nil)

if failures > 0 then os.exit(1) end
print("chat_customdisplay_windows_migration_test: all passed")
