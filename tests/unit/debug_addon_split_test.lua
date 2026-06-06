-- tests/unit/debug_addon_split_test.lua
-- Run: lua tests/unit/debug_addon_split_test.lua

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
    'local PRIMARY_ADDON_NAME = "QUI"',
    "performance monitor must still measure the main addon")

assertContains(
    "QUI_Debug/memaudit.lua",
    'local TARGET_ADDON_NAME = "QUI"',
    "memory audit must still measure the main addon")

assertContains(
    "QUI_Debug/editmode_diagnose.lua",
    'local DIAGNOSE_ADDON_NAME = "QUI"',
    "diagnostic blocker capture must still watch the main addon")

-- Release packaging (hardened): QUI_Debug is dropped from the release zip
-- entirely and the packaging guards against it via forbidden_paths, rather than
-- an rsync --exclude. The debug companion must never be nested under QUI...
assertContains(
    ".github/workflows/release.yml",
    "build/QUI/QUI_Debug",
    "release packaging must forbid nesting QUI_Debug under QUI")

-- ...and must not ship as a top-level addon in the release zip either.
assertContains(
    ".github/workflows/release.yml",
    "build/QUI_Debug",
    "release packaging must forbid shipping QUI_Debug in the release zip")

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

-- Debug-instrumentation gate: QUI_Debug must activate the main addon's
-- queued instrumentation, and must do so AFTER every other debug file so
-- activation closures can bind ns.MemAuditProfilerMeasure/Mark (defined by
-- memaudit.lua) and land probes in the ns._memprobes array memaudit keeps
-- alive.
assertContains(
    "QUI_Debug/activate.lua",
    "ns.DebugActivate()",
    "debug companion must activate the main addon's instrumentation gate")

local debugXml = readFile("QUI_Debug/debug.xml")
local activatePos = debugXml:find('<Script file="activate.lua"/>', 1, true)
assert(activatePos, "debug.xml must load activate.lua")
local lastScriptPos = 0
for pos in debugXml:gmatch('()<Script file=') do
    lastScriptPos = pos
end
local lastScriptLine = debugXml:sub(lastScriptPos, lastScriptPos + 60)
assert(lastScriptLine:find('file="activate.lua"', 1, true),
    "activate.lua must be the LAST script in debug.xml, found last: " .. lastScriptLine)

print("OK: debug_addon_split_test")
