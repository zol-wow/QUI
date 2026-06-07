-- tests/unit/cdm_composer_items_tab_in_aura_builtins_test.lua
-- Asserts buff and trackedBar built-in containers expose the Items tab.
-- Run: lua tests/unit/cdm_composer_items_tab_in_aura_builtins_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("QUI_CDM/cdm/settings/composer.lua")

-- Locate BuildAddTabs and the isBuiltIn aura/auraBar branches within it.
local buildStart = assert(source:find("local function BuildAddTabs()", 1, true),
    "BuildAddTabs must exist in composer.lua")

-- The aura branch must carry an items tab.
local auraStart = assert(
    source:find('containerType == "aura" then', buildStart, true),
    "BuildAddTabs must have a containerType == \"aura\" branch")

local auraBarStart = assert(
    source:find('containerType == "auraBar" then', buildStart, true),
    "BuildAddTabs must have a containerType == \"auraBar\" branch")

-- Find the end of BuildAddTabs (the closing "end" before the next function/section).
-- We rely on the comment block that follows the function.
local buildEnd = source:find("\n---------------------------------------------------------------------------", buildStart, true)
assert(buildEnd, "could not locate end of BuildAddTabs region")

-- Extract the aura branch: from "aura then" up to the auraBar branch.
local auraRegion = source:sub(auraStart, auraBarStart - 1)
assert(auraRegion:find('"items"', 1, true),
    "aura branch in BuildAddTabs must include an \"items\" tab key")
assert(auraRegion:find("Items & Trinkets", 1, true),
    "aura branch in BuildAddTabs must label the items tab \"Items & Trinkets\"")

-- Extract the auraBar branch: from "auraBar then" up to end of BuildAddTabs.
local auraBarRegion = source:sub(auraBarStart, buildEnd)
assert(auraBarRegion:find('"items"', 1, true),
    "auraBar branch in BuildAddTabs must include an \"items\" tab key")
assert(auraBarRegion:find("Items & Trinkets", 1, true),
    "auraBar branch in BuildAddTabs must label the items tab \"Items & Trinkets\"")

-- Regression guard: essential/utility (cooldown branch) must still have items.
local cooldownStart = assert(
    source:find('containerType == "cooldown" then', buildStart, true),
    "BuildAddTabs must have a containerType == \"cooldown\" branch")
local cooldownRegion = source:sub(cooldownStart, auraStart - 1)
assert(cooldownRegion:find('"items"', 1, true),
    "cooldown branch (essential/utility) must continue to have an \"items\" tab (regression guard)")

print("PASS: items tab present on aura built-ins")
