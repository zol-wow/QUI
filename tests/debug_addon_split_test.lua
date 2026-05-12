-- tests/debug_addon_split_test.lua
-- Run: lua tests/debug_addon_split_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(path, needle, reason)
    local text = readFile(path)
    assert(text:find(needle, 1, true), reason .. " in " .. path)
end

local function assertAbsent(path, needle, reason)
    local text = readFile(path)
    assert(not text:find(needle, 1, true), reason .. " in " .. path)
end

local function assertAbsentText(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

assertAbsent(
    "modules/modules.xml",
    '<Include file="debug\\debug.xml"/>',
    "main addon must not load the debug module package")

assertAbsent(
    "modules/cdm/cdm.xml",
    '<Script file="cdm_debug.lua"/>',
    "main CDM runtime must not load the CDM debug surface")

assertContains(
    "QUI_Debug/QUI_Debug.toc",
    "## LoadOnDemand: 1",
    "debug companion must be load-on-demand")

assertContains(
    "QUI_Debug/QUI_Debug.toc",
    "## RequiredDeps: QUI",
    "debug companion must load after QUI")

assertContains(
    "QUI_Debug/bootstrap.lua",
    'local mainNS = QUI and QUI._ns',
    "debug companion must proxy into the main QUI namespace")

assertContains(
    "QUI_Debug/debug.xml",
    '<Script file="cdm_debug.lua"/>',
    "debug companion must own the CDM debug surface")

assertContains(
    "QUI_Debug/performance.lua",
    'local TARGET_ADDON_NAME = "QUI"',
    "performance monitor must still measure the main addon")

assertContains(
    "QUI_Debug/memaudit.lua",
    'local TARGET_ADDON_NAME = "QUI"',
    "memory audit must still measure the main addon")

assertContains(
    "QUI_Debug/editmode_diagnose.lua",
    'local DIAGNOSE_ADDON_NAME = "QUI"',
    "diagnostic blocker capture must still watch the main addon")

assertContains(
    ".github/workflows/release.yml",
    "--exclude='QUI_Debug'",
    "release package must not nest QUI_Debug under QUI")

assertContains(
    ".github/workflows/release.yml",
    "build/QUI_Debug",
    "release package must include the debug companion as a sibling addon")

local initLua = readFile("init.lua")
local _, debugLoadCallCount = initLua:gsub("self:EnsureDebugToolsLoaded%(%s*%)", "")
assert(
    debugLoadCallCount == 1,
    "debug companion should only be explicitly loaded by the /qui debug startup path")
assertAbsentText(
    initLua,
    'input == "debugtools"',
    "/qui debugtools must not be a second path for loading the debug companion")
assertAbsentText(
    initLua,
    'input == "devtools"',
    "/qui devtools must not be a second path for loading the debug companion")

print("OK: debug_addon_split_test")
