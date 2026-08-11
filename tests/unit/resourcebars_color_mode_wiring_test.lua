-- tests/unit/resourcebars_color_mode_wiring_test.lua
-- Run: lua tests/unit/resourcebars_color_mode_wiring_test.lua
--
-- The settings dropdown and preview use cfg.colorMode. The live bars must use
-- that same enum instead of the retired boolean trio, while retaining a
-- fallback for raw legacy config tables that do not yet have colorMode.

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local runtime = read("QUI_ResourceBars/resourcebars/resourcebars.lua")
local preview = read("QUI_ResourceBars/resourcebars/settings/resource_bars_preview_driver.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

-- Execute the real mode resolver in isolation so priority/fallback behavior is
-- verified rather than duplicated in the test.
local resolverStart = assert(runtime:find("local function GetResourceBarColorMode", 1, true))
local resolverEnd = assert(runtime:find("\nlocal function GetConfiguredResourceColor", resolverStart, true))
local resolverChunk = runtime:sub(resolverStart, resolverEnd - 1)
    .. "\nreturn GetResourceBarColorMode"
local resolver = assert(loadstring(resolverChunk))()

check("explicit power mode overrides stale custom boolean",
    resolver({ colorMode = "power", useCustomColor = true }) == "power")
check("explicit class mode overrides stale power boolean",
    resolver({ colorMode = "class", usePowerColor = true }) == "class")
check("explicit custom mode overrides stale power boolean",
    resolver({ colorMode = "custom", usePowerColor = true }) == "custom")
check("legacy power boolean remains supported",
    resolver({ usePowerColor = true }) == "power")
check("legacy class boolean remains supported",
    resolver({ useClassColor = true }) == "class")
check("legacy custom boolean remains supported",
    resolver({ useCustomColor = true }) == "custom")
check("missing color config defaults to power",
    resolver({}) == "power" and resolver(nil) == "power")

local configuredCalls = 0
for _ in runtime:gmatch("GetConfiguredResourceColor%(cfg, resource%)") do
    configuredCalls = configuredCalls + 1
end
-- One definition plus the three live update owners: primary, secondary, and
-- fragmented secondary. The secondary owner shares its resolved color across
-- its continuous and fragmented branches.
check("all live color update owners share the enum resolver", configuredCalls == 4)
local runtimeOutsideResolver = runtime:sub(1, resolverStart - 1) .. runtime:sub(resolverEnd)
check("live bar branches no longer select colors from legacy booleans",
    runtimeOutsideResolver:find("if cfg.usePowerColor then", 1, true) == nil
    and runtimeOutsideResolver:find("elseif cfg.useClassColor then", 1, true) == nil
    and runtimeOutsideResolver:find("elseif cfg.useCustomColor", 1, true) == nil)
check("preview shares the runtime mode resolver",
    preview:find("Internal.GetResourceBarColorMode(cfg)", 1, true) ~= nil)
check("mode resolver is exported to the preview driver",
    runtime:find("GetResourceBarColorMode = GetResourceBarColorMode", 1, true) ~= nil)

local primaryStart = assert(runtime:find("function QUICore:UpdatePowerBarValue", 1, true))
local primarySecret = assert(runtime:find('if valueType == "secret" then', primaryStart, true))
local primaryColor = assert(runtime:find("GetConfiguredResourceColor(cfg, resource)", primaryStart, true))
check("primary power color is applied before the secret-value early return",
    primaryColor < primarySecret)

local secondaryStart = assert(runtime:find("function QUICore:UpdateSecondaryPowerBarValue", 1, true))
local secondarySecret = assert(runtime:find('if valueType == "secret" then', secondaryStart, true))
local secondaryColor = assert(runtime:find("GetConfiguredResourceColor(cfg, resource)", secondaryStart, true))
check("secondary power color is applied before the secret-value early return",
    secondaryColor < secondarySecret)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("resourcebars_color_mode_wiring_test: all checks passed")
