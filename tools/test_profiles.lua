#!/usr/bin/env lua
--[[
  test_profiles.lua

  Headless QUI profile regression test runner. Walks tests/fixtures/, runs
  the round-trip pipeline against each, snapshot-diffs results.

  Usage:
    lua tools/test_profiles.lua [options] [pattern]

  Options:
    --update              regenerate expected.*.lua files for any divergence
    --only <pattern>      run only fixtures whose path matches <pattern>
    --list                list discovered fixtures and exit
    --verbose             print each pipeline step per fixture
    --no-color            plain output for log capture
    --bail                stop on first failure
    --strip-impl <opt>    "library" (default) or "manual"
    --help

  Exit codes:
    0  all fixtures passed
    1  snapshot mismatch / invariant violation
    2  harness error (lib load fail, missing required file, malformed Lua)
]]

local env = dofile((arg[0]:gsub("[\\/][^\\/]+$", "")) .. "/_addon_env.lua")
local PrettyPrint  = dofile(env.REPO_ROOT .. "tests/helpers/pretty_print.lua")
local DeepCompare  = dofile(env.REPO_ROOT .. "tests/helpers/deep_compare.lua")
local StripHelper  = dofile(env.REPO_ROOT .. "tests/helpers/ace_db_strip.lua")

----------------------------------------------------------------------------
-- CLI arg parsing
----------------------------------------------------------------------------
local options = {
    update     = false,
    only       = nil,
    list       = false,
    verbose    = false,
    color      = true,
    bail       = false,
    stripImpl  = "library",
    pattern    = nil,
}

local function PrintUsage()
    io.stdout:write([[
Usage: lua tools/test_profiles.lua [options] [pattern]
  --update              regenerate expected.*.lua files for any divergence
  --only <pattern>      run only fixtures whose path matches <pattern>
  --list                list discovered fixtures and exit
  --verbose             print each pipeline step per fixture
  --no-color            plain output for log capture
  --bail                stop on first failure
  --strip-impl <opt>    "library" (default) or "manual"
  --help
]])
end

local i = 1
while i <= #arg do
    local a = arg[i]
    if     a == "--update"  then options.update = true
    elseif a == "--list"    then options.list = true
    elseif a == "--verbose" then options.verbose = true
    elseif a == "--no-color"then options.color = false
    elseif a == "--bail"    then options.bail = true
    elseif a == "--only"    then
        i = i + 1
        if not arg[i] then io.stderr:write("--only requires a value\n"); os.exit(2) end
        options.only = arg[i]
    elseif a == "--strip-impl" then
        i = i + 1
        if not arg[i] then io.stderr:write("--strip-impl requires a value\n"); os.exit(2) end
        options.stripImpl = arg[i]
    elseif a == "--help" or a == "-h" then PrintUsage(); os.exit(0)
    elseif a:sub(1, 2) == "--" then
        io.stderr:write("Unknown option: " .. a .. "\n"); PrintUsage(); os.exit(2)
    else
        options.pattern = a
    end
    i = i + 1
end

----------------------------------------------------------------------------
-- Fixture discovery
----------------------------------------------------------------------------
-- Returns a sorted list of fixture descriptors:
--   { path = "tests/fixtures/current/basic_fresh", category = "current",
--     name = "basic_fresh", files = { seed = "...", expected = "...", ... } }
local FIXTURE_ROOT = env.REPO_ROOT .. "tests/fixtures/"
local CATEGORIES = { "current", "legacy", "edge" }

local function FileExists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function ListDirSorted(path)
    -- Use Lua's `lfs` if available (cross-platform, requires luarocks).
    local ok, lfs = pcall(require, "lfs")
    if ok then
        local out = {}
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then out[#out + 1] = entry end
        end
        table.sort(out)
        return out
    end
    -- Fallback: shell out. package.config:sub(1,1) is "\\" on Windows, "/" elsewhere.
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd
    if isWindows then
        cmd = 'dir /B "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
        cmd = 'ls "' .. path .. '" 2>/dev/null'
    end
    local handle = io.popen(cmd)
    if not handle then return {} end
    local out = {}
    for line in handle:lines() do
        if line ~= "" then out[#out + 1] = line end
    end
    handle:close()
    table.sort(out)
    return out
end

local function DiscoverFixtures()
    local fixtures = {}
    for _, cat in ipairs(CATEGORIES) do
        local catPath = FIXTURE_ROOT .. cat
        for _, name in ipairs(ListDirSorted(catPath)) do
            local fxPath = catPath .. "/" .. name
            local seedPath = fxPath .. "/seed.sv.lua"
            if FileExists(seedPath) then
                fixtures[#fixtures + 1] = {
                    path = "tests/fixtures/" .. cat .. "/" .. name,
                    category = cat,
                    name = name,
                    files = {
                        seed              = fxPath .. "/seed.sv.lua",
                        expected          = fxPath .. "/expected.sv.lua",
                        defaultsSnapshot  = fxPath .. "/defaults.snapshot.lua",
                        invariants        = fxPath .. "/invariants.lua",
                        postMigration     = fxPath .. "/expected.post_migration.lua",
                        export            = fxPath .. "/expected.export.txt",
                        postImport        = fxPath .. "/expected.post_import.lua",
                    },
                }
            end
        end
    end
    if options.only then
        local filtered = {}
        for _, fx in ipairs(fixtures) do
            if fx.path:find(options.only, 1, true) then filtered[#filtered + 1] = fx end
        end
        fixtures = filtered
    end
    if options.pattern then
        local filtered = {}
        for _, fx in ipairs(fixtures) do
            if fx.path:find(options.pattern, 1, true) then filtered[#filtered + 1] = fx end
        end
        fixtures = filtered
    end
    return fixtures
end

----------------------------------------------------------------------------
-- --list mode
----------------------------------------------------------------------------
if options.list then
    local fixtures = DiscoverFixtures()
    for _, fx in ipairs(fixtures) do print(fx.path) end
    os.exit(0)
end

----------------------------------------------------------------------------
-- Pipeline
----------------------------------------------------------------------------

local function ColorWrap(s, code)
    if not options.color then return s end
    return "\27[" .. code .. "m" .. s .. "\27[0m"
end
local function Green(s) return ColorWrap(s, "32") end
local function Red(s)   return ColorWrap(s, "31") end
local function Dim(s)   return ColorWrap(s, "90") end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = DeepCopy(vv) end
    return out
end

local function LoadLuaFile(path)
    local chunk, err = loadfile(path)
    if not chunk then error("Failed to load " .. path .. ": " .. tostring(err)) end
    return chunk()
end

local function RunFixture(fx)
    local function Tick(label)
        if options.verbose then print("    " .. Dim(label)) end
    end

    -- Fresh _G.QUI_DB / _G.QUIDB before every fixture.
    _G.QUI_DB = nil
    _G.QUIDB  = nil

    -- (1) SEED — dofile sets _G.QUI_DB
    Tick("(1) SEED")
    local seedChunk, err = loadfile(fx.files.seed)
    if not seedChunk then return { error = "seed load: " .. tostring(err) } end
    seedChunk()
    if type(_G.QUI_DB) ~= "table" then
        return { error = "seed.sv.lua did not set _G.QUI_DB" }
    end
    local originalSV = DeepCopy({ QUI_DB = _G.QUI_DB, QUIDB = _G.QUIDB })

    -- (2) BUILD DB — fresh AceDB instance per fixture
    Tick("(2) BUILD DB")
    local h = env.BuildHarness()

    -- (3) MIGRATE — Tier 0 + Tier 1 via QUI:BackwardsCompat()
    Tick("(3) MIGRATE")
    h.QUI:BackwardsCompat()
    local postMigration = DeepCopy(h.db.profile)

    -- (4) EXPORT
    Tick("(4) EXPORT")
    local exportString = h.QUICore:ExportProfileToString()
    if type(exportString) ~= "string" or not exportString:match("^QUI1:") then
        return { error = "export did not return a QUI1: string (got: "
                          .. tostring(exportString):sub(1, 60) .. "...)" }
    end

    -- (5) RESET DB — clear globals + re-build a fresh AceDB on empty SV
    Tick("(5) RESET DB")
    _G.QUI_DB = nil
    _G.QUIDB  = nil
    local h2 = env.BuildHarness()

    -- (6) IMPORT
    Tick("(6) IMPORT")
    local ok, importErr = h2.QUICore:ImportProfileFromString(exportString, "Default")
    if not ok then
        return { error = "import failed: " .. tostring(importErr) }
    end
    local postImport = DeepCopy(h2.db.profile)

    -- (7) STRIP — simulate logout
    Tick("(7) STRIP")
    if options.stripImpl == "manual" then
        StripHelper.StripManual(h2.db)
    else
        StripHelper.StripLibrary(h2.db)
    end

    -- (8) CAPTURE
    Tick("(8) CAPTURE")
    local finalSV = DeepCopy({ QUI_DB = _G.QUI_DB, QUIDB = _G.QUIDB })

    -- (9) ASSERT — load expected snapshot if present
    Tick("(9) ASSERT")
    local expected
    if FileExists(fx.files.expected) then
        expected = LoadLuaFile(fx.files.expected)
    end

    -- Optional checkpoint comparisons (post_migration / export / post_import)
    local checkpointIssues = {}
    if FileExists(fx.files.postMigration) then
        local exp = LoadLuaFile(fx.files.postMigration)
        local diff = DeepCompare.Diff(exp, postMigration, "profile")
        if #diff > 0 then
            checkpointIssues[#checkpointIssues + 1] = { label = "post_migration", diff = diff }
        end
    end
    if FileExists(fx.files.export) then
        local f = io.open(fx.files.export, "r")
        local exp = f:read("*a"); f:close()
        if exp:gsub("%s+$", "") ~= exportString:gsub("%s+$", "") then
            checkpointIssues[#checkpointIssues + 1] = {
                label = "export",
                diff = { { op = "~", path = "exportString",
                           from = exp:sub(1, 40) .. "...",
                           to   = exportString:sub(1, 40) .. "..." } },
            }
        end
    end
    if FileExists(fx.files.postImport) then
        local exp = LoadLuaFile(fx.files.postImport)
        local diff = DeepCompare.Diff(exp, postImport, "profile")
        if #diff > 0 then
            checkpointIssues[#checkpointIssues + 1] = { label = "post_import", diff = diff }
        end
    end

    -- Run invariants (Tier-2 assertions)
    local invariantFailures = {}
    if FileExists(fx.files.invariants) then
        local invariants = LoadLuaFile(fx.files.invariants)
        if type(invariants) ~= "table" then
            return { error = "invariants.lua did not return a list" }
        end
        for _, inv in ipairs(invariants) do
            local okPcall, result = pcall(inv.assert, finalSV, {
                originalSV    = originalSV,
                postMigration = postMigration,
                exportString  = exportString,
                postImport    = postImport,
            })
            if not okPcall then
                invariantFailures[#invariantFailures + 1] =
                    { name = inv.name, error = tostring(result) }
            elseif result ~= true then
                invariantFailures[#invariantFailures + 1] =
                    { name = inv.name, error = "returned " .. tostring(result) }
            end
        end
    end

    return {
        finalSV = finalSV,
        expected = expected,
        checkpointIssues = checkpointIssues,
        invariantFailures = invariantFailures,
    }
end

----------------------------------------------------------------------------
-- Reporting
----------------------------------------------------------------------------

local fixtures = DiscoverFixtures()

if #fixtures == 0 then
    io.stdout:write("No fixtures discovered. (Pattern: "
        .. tostring(options.only or options.pattern or "<none>") .. ")\n")
    os.exit(0)
end

io.stdout:write("QUI profile tests — " .. #fixtures .. " fixture"
                 .. (#fixtures == 1 and "" or "s") .. " discovered\n\n")

local passed, failed, errored = 0, 0, 0
local failures = {}

local clockStart = os.clock()
local lastCategory

for _, fx in ipairs(fixtures) do
    if fx.category ~= lastCategory then
        io.stdout:write(fx.category .. "/\n")
        lastCategory = fx.category
    end
    local label = "  " .. fx.name
    io.stdout:write(label .. string.rep(" ", math.max(1, 40 - #label)))
    io.stdout:flush()

    local fxStart = os.clock()
    local ok, result = pcall(RunFixture, fx)
    local elapsed = math.floor((os.clock() - fxStart) * 1000)

    if not ok then
        errored = errored + 1
        io.stdout:write(Red("ERROR") .. "  (" .. elapsed .. "ms)\n")
        failures[#failures + 1] = { fx = fx, kind = "error", message = tostring(result) }
        if options.bail then break end
    elseif result.error then
        failed = failed + 1
        io.stdout:write(Red("FAIL ") .. " (" .. elapsed .. "ms)\n")
        failures[#failures + 1] = { fx = fx, kind = "fail", message = result.error }
        if options.bail then break end
    else
        local payload = result
        local diff = (payload.expected ~= nil)
            and DeepCompare.Diff(payload.expected, payload.finalSV, "")
            or {}
        if not payload.expected and options.update then
            PrettyPrint.WriteFile(fx.files.expected, payload.finalSV)
            io.stdout:write(Green("WROTE") .. " (" .. elapsed .. "ms)\n")
            passed = passed + 1
        elseif not payload.expected then
            failed = failed + 1
            io.stdout:write(Red("FAIL ") .. " no expected.sv.lua (run --update to create) ("
                             .. elapsed .. "ms)\n")
            failures[#failures + 1] = { fx = fx, kind = "missing_expected" }
            if options.bail then break end
        elseif #diff > 0 then
            if options.update then
                PrettyPrint.WriteFile(fx.files.expected, payload.finalSV)
                io.stdout:write(Green("UPDATED") .. " (" .. elapsed .. "ms)\n")
                io.stdout:write(DeepCompare.FormatDiff(diff) .. "\n")
                passed = passed + 1
            else
                failed = failed + 1
                io.stdout:write(Red("FAIL ") .. " (" .. elapsed .. "ms)\n")
                failures[#failures + 1] = { fx = fx, kind = "diff", diff = diff,
                                             checkpointIssues = payload.checkpointIssues }
                if options.bail then break end
            end
        elseif #(payload.invariantFailures or {}) > 0 then
            failed = failed + 1
            io.stdout:write(Red("FAIL ") .. " (" .. elapsed .. "ms) — invariants\n")
            failures[#failures + 1] = { fx = fx, kind = "invariants",
                                         invariantFailures = payload.invariantFailures }
            if options.bail then break end
        else
            passed = passed + 1
            io.stdout:write(Green("ok   ") .. " (" .. elapsed .. "ms)\n")
        end
    end
end

local totalMs = math.floor((os.clock() - clockStart) * 1000)
io.stdout:write("\n" .. string.rep("─", 60) .. "\n")

if #failures > 0 then
    io.stdout:write(Red("FAILURES (" .. #failures .. ")\n"))
    for _, f in ipairs(failures) do
        io.stdout:write("\n  " .. f.fx.path .. "\n")
        if f.kind == "error" then
            io.stdout:write("    error: " .. (f.message or "<no message>") .. "\n")
        elseif f.kind == "fail" then
            io.stdout:write("    fail: " .. (f.message or "<no message>") .. "\n")
        elseif f.kind == "missing_expected" then
            io.stdout:write("    missing expected.sv.lua — run with --update to create\n")
        elseif f.kind == "diff" then
            io.stdout:write(DeepCompare.FormatDiff(f.diff) .. "\n")
            for _, ci in ipairs(f.checkpointIssues or {}) do
                io.stdout:write("\n    checkpoint " .. ci.label .. " also differs:\n")
                io.stdout:write(DeepCompare.FormatDiff(ci.diff) .. "\n")
            end
        elseif f.kind == "invariants" then
            io.stdout:write("    invariant failures:\n")
            for _, ifail in ipairs(f.invariantFailures) do
                io.stdout:write("      - " .. ifail.name .. ": " .. ifail.error .. "\n")
            end
        end
    end
    io.stdout:write("\n" .. string.rep("─", 60) .. "\n")
end

io.stdout:write(string.format("%d passed, %d failed, %d errored — %dms\n",
                               passed, failed, errored, totalMs))

if errored > 0 then os.exit(2) end
if failed > 0 then os.exit(1) end
os.exit(0)
