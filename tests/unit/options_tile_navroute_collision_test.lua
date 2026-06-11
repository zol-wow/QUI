-- Guards the V2 options tile nav-route namespace: every tile's navRoutes
-- tabIndex claims must be unique across tiles. GUI._navMap is keyed
-- "tabIndex:subTabIndex" with last-writer-wins registration (framework.lua
-- RegisterV2NavRoute), and RegisterNavigationItem dedupes on
-- tabIndex*100000 — so two tiles claiming the same tabIndex silently
-- hijack each other's NavigateTo target and eat one tile's nav entry
-- (June 2026: the Bags tile took 18, already held by the Info Bar tile —
-- the Info Bar context menu's Settings deep-link landed on the Bags page).
--
-- Loads each QUI_Options/tiles/*.lua with a stubbed registrar and collects
-- the navRoutes each tile declares (spec-level and per sub-page, matching
-- shared.lua's RegisterNavRoutes call sites).
-- Standalone: lua tests/unit/options_tile_navroute_collision_test.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]unit[/\\]") or "./"

local failures = 0
local function check(cond, label)
    if cond then
        print("ok - " .. label)
    else
        failures = failures + 1
        print("FAIL - " .. label)
    end
end

local function ListTileFiles()
    local files = {}
    local pipe = assert(io.popen('ls "' .. ROOT .. 'QUI_Options/tiles/"*.lua'))
    for line in pipe:lines() do
        files[#files + 1] = line
    end
    pipe:close()
    return files
end

-- Captured spec list; the Opts stub answers any other method with a noop so
-- tile registrars that poke extra registrar surface don't crash the load.
local specs = {}
local optsStub = setmetatable({
    RegisterFeatureTile = function(_, spec)
        specs[#specs + 1] = spec
    end,
}, { __index = function() return function() end end })

for _, path in ipairs(ListTileFiles()) do
    local chunk, err = loadfile(path)
    check(chunk ~= nil, "compiles: " .. path .. (err and (" (" .. err .. ")") or ""))
    if chunk then
        local ns = { QUI_Options = optsStub }
        -- related.lua/help_content.lua read globals at file scope and are
        -- not tile registrars; tolerate load failures, require registrars
        -- via the coverage checks below instead.
        local okLoad = pcall(chunk, "QUI_Options", ns)
        if okLoad then
            for key, tile in pairs(ns) do
                if key:match("^QUI_.+Tile$") and type(tile) == "table"
                        and type(tile.Register) == "function" then
                    pcall(tile.Register, {})
                end
            end
        end
    end
end

-- Coverage floor: a stub change that silently breaks loading must not look
-- like "no collisions".
check(#specs >= 10, "captured at least 10 tile specs (got " .. #specs .. ")")
local capturedIds = {}
for _, spec in ipairs(specs) do capturedIds[spec.id or "?"] = true end
check(capturedIds.bags, "bags tile captured")
check(capturedIds.infobar, "infobar tile captured")

-- Collect route claims per tile id (spec-level + per sub-page navRoutes,
-- the two RegisterNavRoutes call sites in shared.lua). The map key — and
-- therefore the uniqueness unit — is the (tabIndex, subTabIndex) PAIR:
-- legacy tabs were split across tiles distinguished by subTabIndex, so a
-- shared tabIndex alone is legitimate (e.g. tab 2's sub-tabs span the
-- action_bars/appearance/chat_tooltips/gameplay tiles).
local claims = {} -- ["t:s"] = { [tileId] = true }
local function Claim(tileId, navRoutes)
    if type(navRoutes) ~= "table" then return end
    for _, route in ipairs(navRoutes) do
        if type(route) == "table" and type(route.tabIndex) == "number" then
            local key = route.tabIndex .. ":" .. (route.subTabIndex or 0)
            claims[key] = claims[key] or {}
            claims[key][tileId] = true
        end
    end
end
for _, spec in ipairs(specs) do
    local tileId = spec.id or "?"
    Claim(tileId, spec.navRoutes)
    if type(spec.subPages) == "table" then
        for _, subPage in ipairs(spec.subPages) do
            Claim(tileId, subPage and subPage.navRoutes)
        end
    end
end

local sortedKeys = {}
for key in pairs(claims) do sortedKeys[#sortedKeys + 1] = key end
table.sort(sortedKeys)
for _, key in ipairs(sortedKeys) do
    local owners, count = {}, 0
    for tileId in pairs(claims[key]) do
        owners[#owners + 1] = tileId
        count = count + 1
    end
    table.sort(owners)
    check(count == 1, "route " .. key .. " claimed by exactly one tile ("
        .. table.concat(owners, ", ") .. ")")
end

if failures == 0 then
    print("ALL TESTS PASSED")
    os.exit(0)
else
    print(failures .. " FAILURES")
    os.exit(1)
end
