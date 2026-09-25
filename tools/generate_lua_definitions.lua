-- tools/generate_lua_definitions.lua
-- Generate the LuaLS meta-definition library for the WoW client API. The editor
-- picks these up via .luarc.json's workspace.library so the addon's own files
-- stop reporting undefined-global / redundant-parameter for the WoW API.
--
-- Run from the repo root:
--   lua tools/generate_lua_definitions.lua
--
-- Writes three files under meta/:
--   wow-api.lua      C_* namespaces + global functions (precise, from the
--                    vendored Blizzard docs in tests/api-docs/blizzard)
--   wow-widgets.lua  Frame/Region/Texture/FontString/Button widget classes with
--                    every widget method (from the ScriptObject docs), so frame
--                    method calls and `---@return Frame`-style annotations resolve
--   wow-globals.lua  permissive `any` declarations for every WoW global listed
--                    in .luacheckrc that the precise files don't already define
--
-- Re-run whenever the vendored docs or .luacheckrc change.

local Gen = dofile("tools/lua_defs_gen.lua")

local options = { docs = "tests/api-docs/blizzard", out = "meta", globals = ".luacheckrc" }
local specified = {}
for i = 1, #arg, 2 do
    local key = arg[i]:match("^%-%-(.+)$")
    assert(key and options[key], "Unknown option: " .. arg[i])
    assert(arg[i + 1] and arg[i + 1] ~= "" and arg[i + 1]:sub(1, 2) ~= "--",
        arg[i] .. " requires a path (or none for --globals)")
    options[key] = arg[i + 1]
    specified[key] = true
end
assert(not specified.docs or specified.out, "--docs requires an explicit --out directory")
if specified.docs and not specified.globals then options.globals = "none" end
local DOCS_DIR = options.docs
local API_PATH = options.out .. "/wow-api.lua"
local WIDGETS_PATH = options.out .. "/wow-widgets.lua"
local GLOBALS_PATH = options.out .. "/wow-globals.lua"
local function shellQuote(value)
    return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end

-- Widget type names our code annotates with (`---@return Frame`, etc.) plus the
-- common WoW UI object types. Each becomes a class inheriting the shared widget
-- base, so every widget method resolves on any of them.
-- Only *type* names here — names used in `---@param/@return` annotations or as
-- the inferred type of a widget value. Singleton frame *instances* (GameTooltip,
-- Minimap, UIParent, …) are NOT types; they live in wow-globals.lua as values.
local WIDGET_TYPES = {
    "Region", "Frame", "Texture", "MaskTexture", "Line", "FontString", "Button",
    "CheckButton", "StatusBar", "Slider", "EditBox", "ScrollFrame", "Cooldown",
    "Model", "PlayerModel", "ModelScene", "Animation", "AnimationGroup",
    "ColorSelect", "MessageFrame", "ScrollingMessageFrame", "SimpleHTML",
    "Browser", "MovieFrame", "FontInstance",
}

-- ---------------------------------------------------------------------------
-- Load every doc file in a sandbox that captures AddDocumentationTable.
-- ---------------------------------------------------------------------------
local function discoverFiles(dir)
    local files = {}
    local p = io.popen("find " .. shellQuote(dir) .. " -maxdepth 1 -type f -name '*.lua' 2>/dev/null", "r")
    if p then
        for line in p:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then files[#files + 1] = line end
        end
        p:close()
    end
    table.sort(files)
    assert(#files > 0, "No Lua documentation files in " .. dir)
    return files
end

-- Some doc files read Enum.*/Constants.* at load time (e.g. `Default =
-- Enum.Foo.Bar`). The client defines those; a bare sandbox does not, so the
-- chunk raises and the pcall below silently dropped the whole file. That cost
-- us every Simple*API table — i.e. essentially the entire widget surface,
-- SetFrameLevel included. Auto-vivifying stubs keep those files loadable.
-- A few Constants files also do arithmetic on those values (`MAX_SLOTS + 1`),
-- so the stub answers numeric operators with 0 rather than raising.
local function autoStub()
    local mt
    local zero = function() return 0 end
    mt = {
        __index = function(t, k)
            local v = setmetatable({}, mt)
            rawset(t, k, v)
            return v
        end,
        __add = zero, __sub = zero, __mul = zero, __div = zero,
        __mod = zero, __pow = zero, __unm = zero, __len = zero,
        __concat = function() return "" end,
        __tostring = function() return "0" end,
    }
    return setmetatable({}, mt)
end

local function loadTables(dir)
    local captured = {}
    local failures = {}
    local APIDocumentation = {}
    function APIDocumentation:AddDocumentationTable(tbl) -- luacheck: ignore self
        captured[#captured + 1] = tbl
    end
    for _, path in ipairs(discoverFiles(dir)) do
        local f = assert(io.open(path, "rb"))
        if f then
            local source = f:read("*a"); f:close()
            local env = setmetatable({
                APIDocumentation = APIDocumentation,
                Enum = autoStub(),
                Constants = autoStub(),
            }, { __index = _G })
            local ok, err
            if setfenv then
                -- Lua 5.1: load a string via loadstring + setfenv.
                local chunk = (loadstring or load)(source, "@" .. path)
                if chunk then setfenv(chunk, env); ok, err = pcall(chunk) else ok, err = false, "compile error" end
            else
                -- Lua 5.2+: env is the 4th argument to load.
                local chunk = load(source, "@" .. path, "t", env)
                if chunk then ok, err = pcall(chunk) else ok, err = false, "compile error" end
            end
            -- Surface skipped files instead of swallowing them; a silent drop
            -- here reads downstream as "the API simply doesn't have that method".
            if not ok then failures[#failures + 1] = path .. ": " .. tostring(err) end
        end
    end
    if #failures > 0 then
        error("Documentation load failed:\n" .. table.concat(failures, "\n"))
    end
    return captured
end

-- A no-namespace system whose Name ends in one of these is a global table
-- accessor (e.g. AbbreviateConfigAPI.Foo), not a set of bare global functions.
local function isNamespaceLikeName(name)
    return name:match("API$") or name:match("Manager$") or name:match("Mixin$")
end

-- ---------------------------------------------------------------------------
-- wow-api.lua — C_* namespaces + global functions (skip ScriptObject docs,
-- those are widget methods handled by generateWidgets).
-- `defined` accumulates every name this file declares so generateGlobals can
-- avoid clobbering a precise definition with a permissive `any`.
-- ---------------------------------------------------------------------------
local function generateApi(tables, defined)
    local namespaces, nsOrder = {}, {}
    local globals, globalOrder = {}, {}

    local function ensureNs(ns)
        if not namespaces[ns] then
            namespaces[ns] = {}
            nsOrder[#nsOrder + 1] = ns
        end
        return namespaces[ns]
    end

    for _, tbl in ipairs(tables) do
        if tbl.Type ~= "ScriptObject" and type(tbl.Functions) == "table" then
            local ns = tbl.Namespace
            if not ns and tbl.Name and isNamespaceLikeName(tbl.Name) then ns = tbl.Name end
            for _, fn in ipairs(tbl.Functions) do
                if type(fn) == "table" and fn.Name then
                    local namespace = fn.Namespace or ns
                    if namespace and namespace ~= "" then
                        ensureNs(namespace)[#namespaces[namespace] + 1] = Gen.emitFunction(fn, namespace)
                    elseif not globals[fn.Name] then
                        globals[fn.Name] = Gen.emitFunction(fn, nil)
                        globalOrder[#globalOrder + 1] = fn.Name
                    end
                end
            end
        end
    end

    local out = {
        "---@meta",
        "-- WoW client API: C_* namespaces + global functions.",
        "-- AUTO-GENERATED by tools/generate_lua_definitions.lua from the vendored",
        "-- Blizzard docs under " .. DOCS_DIR .. ". Do not edit by hand.",
        "--",
        "-- Namespaces are plain tables (not a named ---@class) so addon code and",
        "-- tests can still reassign them (e.g. `C_ClassTalents = nil`) without an",
        "-- assign-type-mismatch. Functions take optional params + a trailing vararg",
        "-- so arg-count never false-positives and undocumented methods still resolve.",
        "",
    }
    table.sort(nsOrder)
    for _, ns in ipairs(nsOrder) do
        defined[ns] = true
        out[#out + 1] = ns .. " = {}"
        for _, d in ipairs(namespaces[ns]) do out[#out + 1] = d end
        out[#out + 1] = ""
    end
    table.sort(globalOrder)
    out[#out + 1] = "-- Global (non-namespaced) functions"
    for _, name in ipairs(globalOrder) do
        if not namespaces[name] then
            defined[name] = true
            out[#out + 1] = globals[name]
        end
    end
    out[#out + 1] = ""
    return table.concat(out, "\n"), #nsOrder, #globalOrder
end

-- ---------------------------------------------------------------------------
-- wow-widgets.lua — every widget method (from ScriptObject docs) on one shared
-- base class, with Frame/Region/Texture/FontString/Button/... inheriting it.
-- Over-broad (a Texture "has" Frame methods) but it means any frame-typed value
-- resolves every widget method with a tolerant signature.
-- ---------------------------------------------------------------------------
local BASE = "__WowWidget"

local function generateWidgets(tables)
    local methods, methodOrder = {}, {}
    for _, tbl in ipairs(tables) do
        if tbl.Type == "ScriptObject" and type(tbl.Functions) == "table" then
            for _, fn in ipairs(tbl.Functions) do
                if type(fn) == "table" and fn.Name and not methods[fn.Name] then
                    methods[fn.Name] = Gen.emitMethod(fn, BASE)
                    methodOrder[#methodOrder + 1] = fn.Name
                end
            end
        end
    end
    table.sort(methodOrder)

    local out = {
        "---@meta",
        "-- WoW widget API for the Lua language server.",
        "-- AUTO-GENERATED by tools/generate_lua_definitions.lua from the ScriptObject",
        "-- docs under " .. DOCS_DIR .. ". Do not edit by hand.",
        "--",
        "-- Every widget method lives on " .. BASE .. "; the concrete widget types our",
        "-- code references inherit it, so frame method calls and `---@return Frame`",
        "-- style annotations resolve. Methods take optional params + a trailing",
        "-- vararg so arg-count never false-positives.",
        "",
        "---@class " .. BASE,
        "local " .. BASE .. " = {}",
        "",
    }
    for _, name in ipairs(methodOrder) do out[#out + 1] = methods[name] end
    out[#out + 1] = ""
    for _, t in ipairs(WIDGET_TYPES) do
        out[#out + 1] = "---@class " .. t .. " : " .. BASE
    end
    out[#out + 1] = ""
    return table.concat(out, "\n"), #methodOrder
end

-- ---------------------------------------------------------------------------
-- wow-globals.lua — permissive `any` for every WoW global listed in .luacheckrc
-- that the precise files don't already define. .luacheckrc is the maintained,
-- third-party-clean list of globals this addon uses, so sourcing from it keeps
-- coverage complete without naming any external addon.
-- ---------------------------------------------------------------------------
local function readLuacheckGlobals()
    if options.globals == "none" then return {} end
    local fh = assert(io.open(options.globals, "rb"))
    local src = fh:read("*a"); fh:close()
    local env = setmetatable({}, { __index = _G })
    local chunk = (loadstring or load)(src, "@.luacheckrc")
    if chunk then
        if setfenv then setfenv(chunk, env) end
        pcall(chunk)
    end
    local seen, names = {}, {}
    for _, key in ipairs({ "globals", "read_globals" }) do
        local list = env[key]
        if type(list) == "table" then
            for _, n in ipairs(list) do
                if type(n) == "string" and not seen[n] then
                    seen[n] = true; names[#names + 1] = n
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function generateGlobals(defined)
    local out = {
        "---@meta",
        "-- WoW globals (UI frames, font objects, constants, legacy functions) the",
        "-- addon references, declared opaque so they resolve without per-symbol",
        "-- signatures. AUTO-GENERATED by tools/generate_lua_definitions.lua from the",
        options.globals == "none" and "-- No supplemental globals configured."
            or "-- " .. options.globals .. " global lists. Do not edit by hand.",
        "",
    }
    local count = 0
    for _, name in ipairs(readLuacheckGlobals()) do
        -- Skip names already given a precise definition in wow-api.lua, and any
        -- widget type name (those are classes in wow-widgets.lua).
        if not defined[name] then
            out[#out + 1] = name .. " = nil ---@type any"
            count = count + 1
        end
    end
    out[#out + 1] = ""
    return table.concat(out, "\n"), count
end

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------
local function writeFile(path, source)
    local fh = assert(io.open(path, "wb"))
    fh:write(source)
    fh:close()
end

local tables = loadTables(DOCS_DIR)
os.execute("mkdir -p " .. shellQuote(options.out))

local defined = {}
for _, t in ipairs(WIDGET_TYPES) do defined[t] = true end

local apiSrc, nsCount, globalCount = generateApi(tables, defined)
writeFile(API_PATH, apiSrc)

local widgetsSrc, methodCount = generateWidgets(tables)
writeFile(WIDGETS_PATH, widgetsSrc)

local globalsSrc, globalsCount = generateGlobals(defined)
writeFile(GLOBALS_PATH, globalsSrc)

print(string.format("wow-api.lua:     %d namespaces, %d global functions", nsCount, globalCount))
print(string.format("wow-widgets.lua: %d widget methods on %d types", methodCount, #WIDGET_TYPES))
print(string.format("wow-globals.lua: %d permissive globals from .luacheckrc", globalsCount))
