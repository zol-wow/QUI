-- tests/unit/minimap_drawer_toggle_icon_test.lua
-- Run: lua tests/unit/minimap_drawer_toggle_icon_test.lua
--
-- Guards the drawer toggle-icon texture map. The high-value assertion is the
-- on-disk existence check: a typo in the asset filename renders as a green
-- question mark in game and nothing else in the suite would catch it.

local env = (dofile("tests/helpers/load_minimap_runtime.lua"))()
local findUpvalue = env.findUpvalue

local refresh = assert(_G.QUI_RefreshMinimapButtonDrawer,
    "drawer refresh function should be exported")

local textures = assert(findUpvalue(refresh, "TOGGLE_ICON_TEXTURES"),
    "TOGGLE_ICON_TEXTURES should be reachable from the exported drawer refresh")

assert(type(textures) == "table", "TOGGLE_ICON_TEXTURES should be a table")

local ASSET_ROOT = "Interface\\AddOns\\QUI\\assets\\"

-- Every mapped icon must point inside the addon's own assets directory and the
-- file must actually exist. WoW resolves .tga/.blp without an extension, so an
-- extensionless path is probed against both.
local function assetExists(texturePath)
    local tail = texturePath:sub(#ASSET_ROOT + 1)
    assert(texturePath:sub(1, #ASSET_ROOT) == ASSET_ROOT,
        "texture path should live under the addon assets root: " .. texturePath)
    tail = tail:gsub("\\", "/")
    local candidates
    if tail:match("%.%w+$") then
        candidates = { tail }
    else
        candidates = { tail .. ".tga", tail .. ".blp" }
    end
    for _, candidate in ipairs(candidates) do
        local handle = io.open("assets/" .. candidate, "rb")
        if handle then
            handle:close()
            return true
        end
    end
    return false
end

local seen = {}
for value, texturePath in pairs(textures) do
    assert(type(value) == "string", "toggle icon keys should be strings")
    assert(type(texturePath) == "string", "toggle icon values should be texture paths")
    assert(assetExists(texturePath),
        ("toggle icon %q points at a missing asset: %s"):format(value, texturePath))
    seen[value] = true
end

assert(seen.hammer, "the legacy hammer icon should still be renderable")
assert(seen.qui, "the QUI mark should be renderable")
assert(textures.grid == nil,
    "grid is drawn from colour textures, not a file — it must NOT be in the texture map")

assert(textures.qui == ASSET_ROOT .. "QUI.tga",
    "the QUI mark should render from the already-shipped assets/QUI.tga")

-- The shipped default must be a value the renderer can actually draw. Loading
-- defaults needs a second addon environment; tools/_addon_env.lua provides the
-- one tests/unit/shipped_defaults_maintenance_test.lua uses.
-- The minimap stub harness above left _G.LibStub pointed at its own
-- return-nil stub (a bare function, set by tests/helpers/load_minimap_runtime.lua).
-- Lua 5.1 functions have no __index, and libs/LibStub/LibStub.lua:9 does
-- `LibStub.minor` on the existing global to decide whether to reinitialize —
-- so when tools/_addon_env.lua's LoadLibs() loads the real library over that
-- stub, indexing .minor on a function throws. Nilling the global first makes
-- that guard's `not LibStub` branch short-circuit instead, same precedent
-- tests/unit/external_skin_bridge_test.lua and
-- tests/unit/raidbuffs_unknown_tolerance_test.lua establish for nilling
-- _G.LibStub before downstream code re-derives its LibStub state (there,
-- to force the "no LibStub available" fallback path; here, to let the real
-- library's own re-init guard run clean).
_G.LibStub = nil
local defaultsEnv = dofile("tools/_addon_env.lua")
local coreNS = defaultsEnv.LoadCore()
assert(coreNS and coreNS.defaults, "tools/_addon_env.lua LoadCore() should expose ns.defaults")

local drawerDefaults = coreNS.defaults.profile
    and coreNS.defaults.profile.minimap
    and coreNS.defaults.profile.minimap.buttonDrawer
assert(drawerDefaults, "core/defaults.lua should define profile.minimap.buttonDrawer")

assert(drawerDefaults.toggleIcon == "qui",
    "the shipped default drawer toggle icon should be the QUI mark, got "
        .. tostring(drawerDefaults.toggleIcon))

-- tools/generate_search_cache.lua hardcodes its own copy of this dropdown
-- instead of reading the provider, so the two silently drift. Parse the mirror
-- out of the generator source and compare value sets.
local generatorSource
do
    local handle = assert(io.open("tools/generate_search_cache.lua", "r"),
        "tools/generate_search_cache.lua should be readable from the repo root")
    generatorSource = handle:read("*a")
    handle:close()
end

local mirrorBody = generatorSource:match(
    "MINIMAP_DRAWER_TOGGLE_ICON_OPTIONS%s*=%s*{(.-)}%s*\n")
assert(mirrorBody,
    "MINIMAP_DRAWER_TOGGLE_ICON_OPTIONS should still exist in tools/generate_search_cache.lua")

local mirrorValues = {}
for value in mirrorBody:gmatch('value%s*=%s*"([^"]+)"') do
    mirrorValues[value] = true
end

-- The renderable set is every file-texture icon plus the colour-texture "grid".
local renderable = { grid = true }
for value in pairs(textures) do renderable[value] = true end

for value in pairs(renderable) do
    assert(mirrorValues[value],
        ("toggle icon %q is renderable but missing from the search-cache mirror"):format(value))
end
for value in pairs(mirrorValues) do
    assert(renderable[value],
        ("the search-cache mirror offers %q, which the renderer cannot draw"):format(value))
end

-- Everything above this line only checks the shape of TOGGLE_ICON_TEXTURES.
-- Nothing has ever called UpdateToggleIcon, so a flipped condition like
-- `dot:SetShown(texturePath == nil)` -> `~= nil` (icon and dots both visible
-- at once) would sail through the whole file above unnoticed. Drive the real
-- function against a fake button and assert the show/hide outcome.
local UpdateToggleIcon = assert(findUpvalue(refresh, "UpdateToggleIcon"),
    "UpdateToggleIcon should be reachable from the exported drawer refresh")

-- UpdateToggleIcon reads two more file-locals with no other way in: the
-- module-local `drawerToggleButton` (nil until CreateDrawerToggleButton
-- runs, which this stub harness never drives — it has no CreateTexture) and
-- `GetSettings()` (which reads ns.Helpers.GetModuleDB(), not the profile
-- defaults table built above). debug.setupvalue swaps both for the duration
-- of this probe; both are restored afterward since they are file-locals
-- closed over by every other function in the module too, and leaving a fake
-- in place could bleed into any later code path that runs in this process.
local drawerToggleButtonIdx, getSettingsIdx
do
    local i = 1
    while true do
        local name = debug.getupvalue(UpdateToggleIcon, i)
        if not name then break end
        if name == "drawerToggleButton" then drawerToggleButtonIdx = i end
        if name == "GetSettings" then getSettingsIdx = i end
        i = i + 1
    end
end
assert(drawerToggleButtonIdx, "UpdateToggleIcon should read the drawerToggleButton upvalue")
assert(getSettingsIdx, "UpdateToggleIcon should read the GetSettings upvalue")

local _, originalDrawerToggleButton = debug.getupvalue(UpdateToggleIcon, drawerToggleButtonIdx)
local _, originalGetSettings = debug.getupvalue(UpdateToggleIcon, getSettingsIdx)

-- Minimal fake button exposing only what UpdateToggleIcon touches: an
-- _iconTexture with SetTexture/SetShown and a _gridDots array of SetShown
-- recorders. No other methods, so a widened touch surface would error.
local function newFakeToggleButton()
    local iconTexture = { shown = nil, texturePath = nil }
    function iconTexture:SetTexture(path) self.texturePath = path end
    function iconTexture:SetShown(shown) self.shown = shown end

    local gridDots = {}
    for i = 1, 4 do
        local dot = { shown = nil }
        function dot:SetShown(shown) self.shown = shown end
        gridDots[i] = dot
    end

    return { _iconTexture = iconTexture, _gridDots = gridDots }
end

local function dotsShown(button)
    local first = button._gridDots[1].shown
    for _, dot in ipairs(button._gridDots) do
        assert(dot.shown == first, "all four grid dots should move together")
    end
    return first
end

for _, icon in ipairs({ "qui", "hammer", "grid" }) do
    local fakeButton = newFakeToggleButton()
    debug.setupvalue(UpdateToggleIcon, drawerToggleButtonIdx, fakeButton)
    debug.setupvalue(UpdateToggleIcon, getSettingsIdx, function()
        return { buttonDrawer = { toggleIcon = icon } }
    end)

    UpdateToggleIcon()

    local expectTexture = textures[icon] ~= nil

    -- Direction 1: the file-texture icon is shown exactly when there is a
    -- texture path for this icon value.
    assert(fakeButton._iconTexture.shown == expectTexture,
        ("toggleIcon %q: file-texture icon SetShown(%s), expected %s"):format(
            icon, tostring(fakeButton._iconTexture.shown), tostring(expectTexture)))

    -- Direction 2: the grid dots are shown exactly when there is NOT a
    -- texture path — i.e. the inverse of direction 1.
    assert(dotsShown(fakeButton) == not expectTexture,
        ("toggleIcon %q: grid dots SetShown(%s), expected %s"):format(
            icon, tostring(dotsShown(fakeButton)), tostring(not expectTexture)))

    -- The bug this guards against is both showing at once: assert the two
    -- outcomes are always opposite, never equal.
    assert(fakeButton._iconTexture.shown ~= dotsShown(fakeButton),
        ("toggleIcon %q: file-texture icon and grid dots must never agree on shown state"):format(icon))

    if expectTexture then
        assert(fakeButton._iconTexture.texturePath == textures[icon],
            ("toggleIcon %q: SetTexture should receive %s, got %s"):format(
                icon, tostring(textures[icon]), tostring(fakeButton._iconTexture.texturePath)))
    end
end

debug.setupvalue(UpdateToggleIcon, drawerToggleButtonIdx, originalDrawerToggleButton)
debug.setupvalue(UpdateToggleIcon, getSettingsIdx, originalGetSettings)

print("OK: minimap_drawer_toggle_icon_test")
