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

local DOCS_DIR = "tests/api-docs/blizzard"
local API_PATH = "meta/wow-api.lua"
local WIDGETS_PATH = "meta/wow-widgets.lua"
local GLOBALS_PATH = "meta/wow-globals.lua"

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
    local p = io.popen(string.format('find "%s" -maxdepth 1 -type f -name "*.lua" 2>/dev/null', dir), "r")
    if p then
        for line in p:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then files[#files + 1] = line end
        end
        p:close()
    end
    table.sort(files)
    return files
end

local function loadTables(dir)
    local captured = {}
    local APIDocumentation = {}
    function APIDocumentation:AddDocumentationTable(tbl) -- luacheck: ignore self
        captured[#captured + 1] = tbl
    end
    for _, path in ipairs(discoverFiles(dir)) do
        local f = io.open(path, "rb")
        if f then
            local source = f:read("*a"); f:close()
            local env = setmetatable({ APIDocumentation = APIDocumentation }, { __index = _G })
            if setfenv then
                -- Lua 5.1: load a string via loadstring + setfenv.
                local chunk = (loadstring or load)(source, "@" .. path)
                if chunk then setfenv(chunk, env); pcall(chunk) end
            else
                -- Lua 5.2+: env is the 4th argument to load.
                local chunk = load(source, "@" .. path, "t", env)
                if chunk then pcall(chunk) end
            end
        end
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
                    if ns then
                        ensureNs(ns)[#namespaces[ns] + 1] = Gen.emitFunction(fn, ns)
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
        "-- Blizzard docs under tests/api-docs/blizzard. Do not edit by hand.",
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
        "-- docs under tests/api-docs/blizzard. Do not edit by hand.",
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
    local fh = io.open(".luacheckrc", "rb")
    if not fh then return {} end
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
        "-- .luacheckrc global lists. Do not edit by hand.",
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

os.execute("mkdir -p meta")
local tables = loadTables(DOCS_DIR)

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
