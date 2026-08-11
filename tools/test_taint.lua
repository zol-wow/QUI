#!/usr/bin/env lua
--[[
  test_taint.lua

  End-to-end CLI for the QUI static taint-flow analyzer. Discovers .lua files
  under a root directory, analyzes each, renders findings, and returns an exit
  code indicating whether strict violations were found.

  Usage:
    lua tools/test_taint.lua [options] [rootDir]

  Options:
    --report <fmt>      Output format: text (default), json, github
    --json-out <file>   Also write all findings as JSON to <file> (unfiltered)
    --strict-only       Only show strict-tier findings (suppress advisory/review)
    --suppress-review   Hide review-tier findings
    --only <pattern>    Only analyze files whose path contains <pattern>
    --verbose           Print each file analyzed (even if no findings)
    --no-color          Plain output (no ANSI escape codes)
    --help              Show this message

  Exit codes:
    0  No strict findings
    1  One or more strict findings
    2  Harness error (load failure, bad config, etc.)
]]

-- ---------------------------------------------------------------------------
-- Path helpers
-- ---------------------------------------------------------------------------

local function scriptDir()
    local p = (arg and arg[0]) or ""
    p = p:gsub("\\", "/")
    local dir = p:match("(.*/)")
    return dir or "./"
end

local TOOLS_DIR = scriptDir()
-- REPO_ROOT is one level up from tools/
local REPO_ROOT = TOOLS_DIR .. "../"

-- Normalize a path: collapse backslashes, strip trailing slash.
local function normPath(p)
    p = p:gsub("\\", "/")
    p = p:gsub("/+$", "")
    return p
end

-- Resolve a possibly-relative path to an absolute path by asking the OS.
-- On Windows uses `cd /d <path> && cd`; on Unix uses `pwd` after cd.
-- Falls back to the input unchanged if the command fails.
local function absPath(p)
    if p == nil or p == "" then return p end
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd
    if isWindows then
        cmd = 'cmd /c "pushd "' .. p .. '" && cd && popd"'
    else
        cmd = 'sh -c "cd \\"' .. p .. '\\" && pwd"'
    end
    local ph = io.popen(cmd, "r")
    if ph then
        local line = ph:read("*l")
        ph:close()
        if line and line ~= "" then
            return normPath(line:gsub("[\r\n]+$", ""))
        end
    end
    return normPath(p)
end

-- Make path relative to rootDir for display. Strips the rootDir prefix
-- (with or without trailing slash) from an absolute-looking path.
local function relPath(rootDir, p)
    local root = normPath(rootDir) .. "/"
    p = p:gsub("\\", "/")
    if p:sub(1, #root) == root then
        return p:sub(#root + 1)
    end
    return p
end

-- ---------------------------------------------------------------------------
-- CLI argument parsing
-- ---------------------------------------------------------------------------

local options = {
    report         = "text",
    jsonOut        = nil,
    strictOnly     = false,
    suppressReview = false,
    only           = nil,
    shard          = nil,
    shards         = nil,
    verbose        = false,
    color          = true,
    rootDir        = nil,
    update_index   = false,
    self_test      = false,
}

local function printUsage()
    io.stdout:write([[
Usage: lua tools/test_taint.lua [options] [rootDir]

  --report <fmt>      text (default) | json | github
  --json-out <file>   Also write every finding as JSON to <file>, ignoring
                      --strict-only/--suppress-review. Lets one analysis pass
                      gate on stdout and archive the full advisory set.
  --strict-only       Only show strict-tier findings
  --suppress-review   Hide review-tier findings
  --only <pattern>    Only analyze files whose path contains <pattern>
  --shard I/N         Analyze only shard I of N (1-based), for xargs -P fan-out.
                      Every shard must run for the result to mean anything.
  --verbose           Print each file analyzed, even if no findings
  --no-color          Plain output (no ANSI codes)
  --update-index      Regenerate tests/api-docs/api-index.lua from vendored corpus, then exit
  --self-test         Run fixture suite under tests/taint/fixtures/, then exit
  --help

Exit codes:
  0  No strict findings (clean or advisory/review only)
  1  One or more strict findings
  2  Harness error
]])
end

local i = 1
while i <= #arg do
    local a = arg[i]
    if     a == "--strict-only"     then options.strictOnly     = true
    elseif a == "--suppress-review" then options.suppressReview = true
    elseif a == "--verbose"         then options.verbose        = true
    elseif a == "--no-color"        then options.color          = false
    elseif a == "--update-index"    then options.update_index   = true
    elseif a == "--self-test"       then options.self_test      = true
    elseif a == "--report" then
        i = i + 1
        if not arg[i] then
            io.stderr:write("--report requires a value\n")
            os.exit(2)
        end
        local fmt = arg[i]
        if fmt ~= "text" and fmt ~= "json" and fmt ~= "github" then
            io.stderr:write("--report must be text|json|github\n")
            os.exit(2)
        end
        options.report = fmt
    elseif a == "--json-out" then
        i = i + 1
        if not arg[i] or arg[i] == "" then
            io.stderr:write("--json-out requires a file path\n")
            os.exit(2)
        end
        options.jsonOut = arg[i]
    elseif a == "--only" then
        i = i + 1
        if not arg[i] then
            io.stderr:write("--only requires a value\n")
            os.exit(2)
        end
        options.only = arg[i]
    elseif a == "--shard" then
        i = i + 1
        local s, n = tostring(arg[i] or ""):match("^(%d+)/(%d+)$")
        s, n = tonumber(s), tonumber(n)
        if not s or not n or n < 1 or s < 1 or s > n then
            io.stderr:write("--shard requires I/N with 1 <= I <= N (e.g. 3/8)\n")
            os.exit(2)
        end
        options.shard, options.shards = s, n
    elseif a == "--help" or a == "-h" then
        printUsage()
        os.exit(0)
    elseif a:sub(1, 2) == "--" then
        io.stderr:write("Unknown option: " .. a .. "\n")
        printUsage()
        os.exit(2)
    else
        -- Positional argument: rootDir override
        if options.rootDir then
            io.stderr:write("Unexpected argument: " .. a .. "\n")
            os.exit(2)
        end
        options.rootDir = a
    end
    i = i + 1
end

local rootDir = options.rootDir and absPath(options.rootDir) or absPath(REPO_ROOT)

-- ---------------------------------------------------------------------------
-- --update-index: regenerate api-index.lua from vendored corpus, then exit
-- ---------------------------------------------------------------------------

if options.update_index then
    local Extract = dofile(REPO_ROOT .. "tests/api-docs/extract_api_index.lua")
    local corpusDir = rootDir .. "/tests/api-docs/blizzard"
    local outPath   = rootDir .. "/tests/api-docs/api-index.lua"

    local index = Extract.fromCorpus(corpusDir)
    local out   = Extract.renderLua(index)

    local f, ferr = io.open(outPath, "wb")
    if not f then
        io.stderr:write("could not open " .. outPath .. " for writing: " .. tostring(ferr) .. "\n")
        os.exit(2)
    end
    f:write(out)
    f:close()

    local count = 0
    for _ in pairs(index) do count = count + 1 end
    io.stdout:write("api-index.lua regenerated at " .. outPath .. " (" .. count .. " entries)\n")
    os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Load analyzer modules (relative to REPO_ROOT)
-- ---------------------------------------------------------------------------

local function dofileFrom(relp)
    local full = REPO_ROOT .. relp
    local chunk, err = loadfile(full)
    if not chunk then
        io.stderr:write("ERROR: failed to load " .. full .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local ok, result = pcall(chunk)
    if not ok then
        io.stderr:write("ERROR: error executing " .. full .. ": " .. tostring(result) .. "\n")
        os.exit(2)
    end
    return result
end

local Config    = dofileFrom("tests/taint/config.lua")
local Registry  = dofileFrom("tests/taint/registry.lua")
local Findings  = dofileFrom("tests/taint/findings.lua")
local Analyzer  = dofileFrom("tests/taint/analyzer.lua")
local IndexLoad = dofileFrom("tests/taint/index_load.lua")

-- ---------------------------------------------------------------------------
-- Load config
-- ---------------------------------------------------------------------------

local function fileExists(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local cfgPath = rootDir .. "/tests/.taintrc.lua"
if not fileExists(cfgPath) then
    cfgPath = rootDir .. "/.taintrc.lua"
end
local cfg = Config.loadFromFile(cfgPath)

-- ---------------------------------------------------------------------------
-- Build registry: built-ins + api-index sources
-- ---------------------------------------------------------------------------

local registry = Registry.new()

-- event:* entries harvested from the api-index (event name → meta table);
-- cross-checked against the config's event_payload_params below. Populated
-- by IndexLoad.populate when the index loads successfully.
local indexedEvents = {}

-- Load api-index from <rootDir>/tests/api-docs/api-index.lua (if it exists)
local apiIndexPath = rootDir .. "/tests/api-docs/api-index.lua"
local fIdx = io.open(apiIndexPath, "rb")
if fIdx then
    local src = fIdx:read("*a")
    fIdx:close()
    local chunk, err = (rawget(_G, "loadstring") or load)(src, "api-index")
    if not chunk then
        io.stderr:write("WARNING: failed to parse api-index: " .. tostring(err) .. "\n")
    else
        local ok, indexTable = pcall(chunk)
        if ok and type(indexTable) == "table" then
            indexedEvents = IndexLoad.populate(registry, indexTable, cfg,
                function(msg) io.stderr:write(msg) end)
        else
            io.stderr:write("WARNING: api-index did not return a table\n")
        end
    end
end

-- Apply extra_safe_sinks and extra_unwraps from config
if cfg.extra_safe_sinks then
    for _, name in ipairs(cfg.extra_safe_sinks) do
        -- Treat as method if no dot/colon separator, otherwise function
        if name:find("[.:]") then
            registry:addSafeSinkFunction(name)
        else
            registry:addSafeSinkMethod(name)
        end
    end
end
if cfg.extra_unwraps then
    for _, name in ipairs(cfg.extra_unwraps) do
        registry:addUnwrap(name)
    end
end
if cfg.clean_fields then
    for _, name in ipairs(cfg.clean_fields) do
        registry:addCleanField(name)
    end
end
if cfg.extra_guards then
    for _, name in ipairs(cfg.extra_guards) do
        registry:addGuard(name)
    end
end
-- Round-23 element-secret container track: config-listed call-site spellings
-- register on the element track (same shape as extra_guards above).
if cfg.element_secret_functions then
    for _, name in ipairs(cfg.element_secret_functions) do
        registry:addElementSecretFunction(name)
    end
end
-- Round-23 helper-param seeding: declared function name → DECLARED argument
-- positions holding element-secret containers ("<param>[*]" seeds in the
-- analyzer's walkFunctionBody). Spellings should be exact — "M.Copy" covers
-- both `function M.Copy` and `function M:Copy` (positions index the declared
-- list, which omits the implicit colon `self`).
if cfg.element_container_params then
    for fnName, positions in pairs(cfg.element_container_params) do
        if type(positions) == "table" and #positions > 0 then
            registry:addElementContainerParams(fnName, positions)
        end
    end
end
if cfg.extra_restriction_gates then
    for _, name in ipairs(cfg.extra_restriction_gates) do
        registry:addRestrictionGate(name)
    end
end
-- event_payload_params registration is config wiring and stays here; the
-- paired forward cross-check (a configured event missing from the index) is
-- config-side validation too, so it stays alongside the registration and
-- reads the indexedEvents IndexLoad.populate returned above. The REVERSE
-- cross-check (an index event with no configured payload positions) is pure
-- index-scan logic and lives inside IndexLoad.populate instead.
if cfg.event_payload_params then
    for eventName, params in pairs(cfg.event_payload_params) do
        if type(params) == "table" and #params > 0 then
            registry:addSecretPayloadEvent(eventName, params)
            -- A configured event that vanished from the api-index is stale
            -- config (removed/renamed in a client bump) — warn, don't fail.
            if next(indexedEvents) ~= nil and not indexedEvents[eventName] then
                io.stderr:write(string.format(
                    "WARNING: event_payload_params[%q] has no event:* entry in the api-index "
                    .. "(removed or renamed?) — its handler coverage is dead config\n",
                    eventName))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- --self-test: run fixture suite under tests/taint/fixtures/
-- ---------------------------------------------------------------------------

if options.self_test then
    local fixturesRoot = rootDir .. "/tests/taint/fixtures"

    local function listDirs(parent)
        local dirs = {}
        local cmd
        if package.config:sub(1, 1) == "\\" then
            cmd = string.format('dir /b /a:d "%s" 2>nul', parent:gsub("/", "\\"))
        else
            cmd = string.format('ls -1 -d "%s"/*/ 2>/dev/null', parent)
        end
        local p = io.popen(cmd, "r")
        if p then
            for line in p:lines() do
                line = line:gsub("[\r\n]+$", "")
                line = line:gsub("[\\/]+$", ""):gsub("\\", "/")
                if line ~= "" then
                    -- On Windows, dir /b returns bare names; on Unix ls returns full paths.
                    if not line:find("/") then
                        line = parent .. "/" .. line
                    end
                    dirs[#dirs + 1] = line
                end
            end
            p:close()
        end
        return dirs
    end

    -- Build a fixture-specific registry seeded with the two canonical test sources.
    local fxRegistry = Registry.new()
    fxRegistry:addSource("C_Spell.GetSpellCharges")
    fxRegistry:addSource("C_Spell.GetSpellCooldownDuration")
    -- Safe-sink method the C-side-pipe safe fixture relies on: an api-index safe
    -- sink (durationObjectArg) at real scan time. Register it so that fixture
    -- exercises the safe-sink branch instead of the round-13 default-reject
    -- fall-through, which now flags unregistered method consumers.
    fxRegistry:addSafeSinkMethod("SetCooldownFromDurationObject")

    local categories = listDirs(fixturesRoot)
    local failures = 0
    local total = 0

    -- Escape special pattern characters in rootDir for use in string.gsub.
    local rootEsc = rootDir:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")

    for _, catDir in ipairs(categories) do
        local fixtures = listDirs(catDir)
        for _, fxDir in ipairs(fixtures) do
            local inputPath   = fxDir .. "/input.lua"
            local expectedPath = fxDir .. "/expected.txt"
            local f = io.open(inputPath, "rb")
            if f then
                local source = f:read("*a"); f:close()
                -- Strip rootDir prefix to get a repo-relative path for findings.
                local relInput = inputPath:gsub("^" .. rootEsc .. "/", "")
                local findings = Analyzer.analyze(source, relInput, fxRegistry, cfg)
                local actual   = Findings.renderText(findings or {})
                local ef       = io.open(expectedPath, "rb")
                local expected = ef and ef:read("*a") or ""
                if ef then ef:close() end
                -- Normalize line endings: expected.txt may carry CRLF after a
                -- Windows checkout; analyzer always emits LF.
                expected = expected:gsub("\r\n", "\n")
                actual   = actual:gsub("\r\n", "\n")
                total = total + 1
                if actual ~= expected then
                    failures = failures + 1
                    io.stderr:write(string.format("FAIL %s\n  expected: %q\n  actual:   %q\n",
                        relInput, expected, actual))
                end
            end
        end
    end

    io.stdout:write(string.format("self-test: %d/%d passed\n", total - failures, total))
    if failures > 0 then os.exit(1) end
    os.exit(0)
end

-- ---------------------------------------------------------------------------
-- File discovery via OS shell command
-- ---------------------------------------------------------------------------

local function discoverFiles(root)
    local files = {}
    local cmd
    -- Detect OS: package.config's first char is the directory separator
    local isWindows = package.config:sub(1, 1) == "\\"
    if isWindows then
        -- dir /s /b lists all files recursively with full paths.
        -- Wrap in double-quotes; use cmd /c to ensure dir is available.
        cmd = 'cmd /c "dir /s /b "' .. root .. '\\*.lua""'
    else
        cmd = 'find "' .. root .. '" -type f -name "*.lua"'
    end

    local p = io.popen(cmd, "r")
    if not p then
        io.stderr:write("ERROR: could not run file discovery command\n")
        os.exit(2)
    end
    for line in p:lines() do
        line = line:gsub("[\r\n]+$", "")
        if line ~= "" then
            -- Normalize to forward slashes
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    p:close()
    return files
end

local allFiles = discoverFiles(rootDir)
-- find(1) walks directories in filesystem order, which is not guaranteed stable
-- across machines or after a checkout. Sort so --shard assigns the same file to
-- the same shard on every run; without this a sharded run could skip a file.
table.sort(allFiles)

-- ---------------------------------------------------------------------------
-- Filter files
-- ---------------------------------------------------------------------------

local filesToAnalyze = {}
for _, fullPath in ipairs(allFiles) do
    local rel = relPath(rootDir, fullPath)

    -- Config ignore_paths check uses rel path
    if Config.isIgnoredPath(cfg, rel) then
        -- precondition_only_paths re-admits ignored files (vendored libs)
        -- for the raw guarded-call scan alone — restriction crash paths in
        -- library code stay covered without taint-tier noise.
        if Config.isPreconditionOnlyPath(cfg, rel)
            and not (options.only and not fullPath:find(options.only, 1, true)) then
            filesToAnalyze[#filesToAnalyze + 1] =
                { full = fullPath, rel = rel, preconditionOnly = true }
        end
    elseif options.only and not fullPath:find(options.only, 1, true) then
        -- skip: does not match --only pattern
    else
        filesToAnalyze[#filesToAnalyze + 1] = { full = fullPath, rel = rel }
    end
end

-- Greedy longest-processing-time bin-packing, keyed on file size.
--
-- The previous split was round-robin (`(idx - 1) % shards`) on the intent that
-- interleaving spreads the expensive files out. It does not: analysis cost
-- varies by an order of magnitude AND correlates with directory, and the list
-- is sorted by path, so neighbouring entries land in different bins but the
-- expensive *runs* still stack up in a few of them. Measured on 730 files at 6
-- shards, round-robin ran 10.5s..41.5s (3.9x); this LPT split runs 20.9s..28.6s
-- (1.4x) over the identical corpus.
--
-- Byte count is a proxy for cost, not a model of it -- that residual 1.4x is
-- the proxy being imperfect, not a bug to chase. Anything better would need
-- measured per-file timings committed to the repo, which is not worth it.
--
-- Determinism matters as much as balance: sizes are fixed in a checkout and
-- ties break on rel path, so every shard computes the same assignment and the
-- union is still every file -- the "every shard must run" contract in --shard's
-- help text is unchanged. The selected bin is re-sorted by path afterwards so
-- findings are emitted in the same order as an unsharded run.
if options.shards then
    for _, entry in ipairs(filesToAnalyze) do
        local fh = io.open(entry.full, "rb")
        local size = 0
        if fh then
            size = fh:seek("end") or 0
            fh:close()
        end
        entry.cost = size
    end
    table.sort(filesToAnalyze, function(a, b)
        if a.cost ~= b.cost then return a.cost > b.cost end
        return a.rel < b.rel
    end)

    local bins, load = {}, {}
    for b = 1, options.shards do
        bins[b], load[b] = {}, 0
    end
    for _, entry in ipairs(filesToAnalyze) do
        local lightest = 1
        for b = 2, options.shards do
            if load[b] < load[lightest] then lightest = b end
        end
        load[lightest] = load[lightest] + entry.cost
        bins[lightest][#bins[lightest] + 1] = entry
    end

    filesToAnalyze = bins[options.shard]
    table.sort(filesToAnalyze, function(a, b) return a.rel < b.rel end)
end

-- ---------------------------------------------------------------------------
-- ANSI helpers
-- ---------------------------------------------------------------------------

local function colorize(code, text)
    if not options.color then return text end
    return "\27[" .. code .. "m" .. text .. "\27[0m"
end

local SEV_COLOR = {
    strict   = "31",  -- red
    advisory = "33",  -- yellow
    review   = "36",  -- cyan
}

-- ---------------------------------------------------------------------------
-- Analyze each file and collect all findings
-- ---------------------------------------------------------------------------

local allFindings = {}
-- Severity-unfiltered mirror, populated only for --json-out. The archived
-- advisory set has to stay complete even when stdout is gated on --strict-only.
local allUnfiltered = {}
local parseErrors = {}
local strictCount = 0

for _, entry in ipairs(filesToAnalyze) do
    local fullPath = entry.full
    local rel      = entry.rel

    local fh = io.open(fullPath, "rb")
    if not fh then
        io.stderr:write("WARNING: cannot open " .. fullPath .. "\n")
    else
        local source = fh:read("*a")
        fh:close()

        -- Strip a UTF-8 BOM (several vendored lib locale files ship one —
        -- luac accepts it, the LuaMinify lexer does not; check_compile.sh
        -- does the same strip).
        if source:sub(1, 3) == "\239\187\191" then
            source = source:sub(4)
        end

        local findings, err = Analyzer.analyze(source, rel, registry, cfg,
            entry.preconditionOnly and { preconditionOnly = true } or nil)
        if not findings then
            parseErrors[#parseErrors + 1] = { file = rel, err = err }
            if options.verbose then
                io.stderr:write("PARSE ERROR " .. rel .. ": " .. tostring(err) .. "\n")
            end
        else
            if options.jsonOut then
                for _, f in ipairs(findings) do
                    allUnfiltered[#allUnfiltered + 1] = f
                end
            end

            -- Apply severity filters
            local visible = {}
            for _, f in ipairs(findings) do
                local keep = true
                if options.strictOnly and f.severity ~= "strict" then keep = false end
                if options.suppressReview and f.severity == "review" then keep = false end
                if keep then
                    visible[#visible + 1] = f
                    if f.severity == "strict" then
                        strictCount = strictCount + 1
                    end
                end
            end

            if options.verbose or #visible > 0 then
                -- Collect for rendering
                for _, f in ipairs(visible) do
                    allFindings[#allFindings + 1] = f
                end
                if options.verbose and #visible == 0 then
                    io.stdout:write("  clean: " .. rel .. "\n")
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Archive the unfiltered set (--json-out)
-- ---------------------------------------------------------------------------

-- Written before the stdout render so a renderer failure still leaves the
-- artifact on disk. Sorted to match the text renderer's file/line/col order,
-- which --report json does not impose on its own.
if options.jsonOut then
    table.sort(allUnfiltered, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
        if a.line ~= b.line then return a.line < b.line end
        return (a.col or 1) < (b.col or 1)
    end)
    local ok, result = pcall(Findings.renderJSON, allUnfiltered)
    if not ok then
        io.stderr:write("ERROR: " .. tostring(result) .. "\n")
        os.exit(2)
    end
    local fh, err = io.open(options.jsonOut, "wb")
    if not fh then
        io.stderr:write("ERROR: cannot write --json-out file: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    fh:write(result)
    fh:close()
end

-- ---------------------------------------------------------------------------
-- Render findings
-- ---------------------------------------------------------------------------

if options.report == "json" then
    local ok, result = pcall(Findings.renderJSON, allFindings)
    if not ok then
        io.stderr:write("ERROR: " .. tostring(result) .. "\n")
        os.exit(2)
    end
    io.stdout:write(result)
elseif options.report == "github" then
    local ok, result = pcall(Findings.renderGitHub, allFindings)
    if not ok then
        io.stderr:write("ERROR: " .. tostring(result) .. "\n")
        os.exit(2)
    end
    io.stdout:write(result)
else
    -- Default: text
    if #allFindings > 0 then
        -- Sort by file, line, col
        table.sort(allFindings, function(a, b)
            if a.file ~= b.file then return a.file < b.file end
            if a.line ~= b.line then return a.line < b.line end
            return (a.col or 1) < (b.col or 1)
        end)

        -- Group by file for a clean display
        local lastFile = nil
        for _, f in ipairs(allFindings) do
            if f.file ~= lastFile then
                io.stdout:write("\n" .. colorize("1", f.file) .. "\n")
                lastFile = f.file
            end
            local sevColor = SEV_COLOR[f.severity] or "0"
            local sevLabel = colorize(sevColor, "[" .. f.severity .. "]")
            io.stdout:write(string.format(
                "  %d:%d %s %s: %s (source: %s)\n",
                f.line, f.col or 1, sevLabel, f.sink, f.message, f.source_function
            ))
        end
        io.stdout:write("\n")
    end

    -- Safe-helper call-site summary (review-tier findings).
    -- Surfaces every Helpers.Safe* / bare-Safe* call site grouped by file
    -- so the audit-and-refactor work toward C-side sinks is visible.
    if not options.suppressReview then
        local reviewByFile = {}
        local reviewTotal = 0
        for _, f in ipairs(allFindings) do
            if f.severity == "review" then
                reviewByFile[f.file] = (reviewByFile[f.file] or 0) + 1
                reviewTotal = reviewTotal + 1
            end
        end
        if reviewTotal > 0 then
            local files = {}
            for file, count in pairs(reviewByFile) do
                files[#files + 1] = { file = file, count = count }
            end
            table.sort(files, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.file < b.file
            end)
            io.stdout:write(colorize("36",
                "=== Safe* helper call sites — refactor toward C-side sinks ===") .. "\n")
            for _, e in ipairs(files) do
                io.stdout:write(string.format("  %4d  %s\n", e.count, e.file))
            end
            io.stdout:write(string.format("  %4d  total across %d files\n\n",
                reviewTotal, #files))
        end
    end

    -- Summary line
    local total = #allFindings
    local label
    if strictCount > 0 then
        label = colorize("31", strictCount .. " strict finding(s)")
    else
        label = colorize("32", "no strict findings")
    end
    if total > strictCount then
        label = label .. string.format(", %d advisory/review", total - strictCount)
    end
    if #parseErrors > 0 then
        label = label .. string.format(", %d parse error(s)", #parseErrors)
    end
    io.stdout:write("taint: " .. label .. "\n")
end

-- ---------------------------------------------------------------------------
-- Exit code
-- ---------------------------------------------------------------------------

if strictCount > 0 then
    os.exit(1)
else
    os.exit(0)
end
