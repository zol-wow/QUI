-- tests/taint/parser/init.lua
-- Bridge to vendored LuaMinify parser. Hides ParseLua/Util internals from
-- consumers so the parser can be swapped or upgraded without churning callers.

-- Resolve the directory containing this file so that the vendored modules
-- (Util, Scope, strict) are locatable via require regardless of where the
-- caller's working directory is.
local PARSER_DIR
do
    -- When loaded via require("tests.taint.parser.init") or similar, '...'
    -- holds the dotted module name.  Strip the trailing component to get the
    -- prefix we can use for sibling modules.
    local modname = ...
    if type(modname) == "string" then
        PARSER_DIR = modname:gsub("%.init$", ""):gsub("%.", "/")
    else
        -- Loaded via dofile — derive path from the source info of this chunk.
        local info = debug.getinfo(1, "S")
        PARSER_DIR = (info.source or ""):gsub("^@", ""):gsub("[/\\][^/\\]*$", "")
        if PARSER_DIR == "" then PARSER_DIR = "tests/taint/parser" end
    end
end

-- Make bare require('Util'), require('Scope'), require('strict') work by
-- inserting the parser directory at the front of package.path.
-- Always use forward slashes — Lua's package loaders accept '/' on both
-- Windows and Linux, and mixing separators is fragile.
local parser_dir_fwd = PARSER_DIR:gsub("\\", "/")
local parser_path_pattern = parser_dir_fwd .. "/?.lua"
if not _G.__qui_parser_path_added then
    package.path = parser_path_pattern .. ";" .. package.path
    _G.__qui_parser_path_added = true
end

local parseLuaMod = require("ParseLua")
if type(parseLuaMod) ~= "table" or type(parseLuaMod.ParseLua) ~= "function" then
    error("ParseLua module shape unexpected: missing .ParseLua function", 0)
end
local ParseLua = parseLuaMod.ParseLua

local M = {}

--- Parse a Lua source string into an AST.
--- @param source string  Lua source code.
--- @param chunkName string?  Name used in error messages (e.g. file path).
--- @return table|nil ast  AST root node on success (AstType == "Statlist"), or nil on failure.
--- @return string|nil err  Error message on parse failure, nil on success.
function M.parse(source, chunkName)
    if type(source) ~= "string" then
        return nil, (chunkName and chunkName .. ": " or "") ..
                    "source must be a string, got " .. type(source)
    end
    -- Mirror luaL_loadfile: a leading line beginning with '#' (e.g. the "#!"
    -- shebang on an executable CLI script) is not Lua source. Strip its
    -- contents but keep the newline so later line numbers stay accurate.
    if source:sub(1, 1) == "#" then
        source = source:gsub("^[^\n]*", "", 1)
    end
    -- LuaMinify's ParseLua(src) returns (true, ast) on success and
    -- (false, errMsg) on failure.  The chunkName is used as a prefix in
    -- error output if passed, but ParseLua itself doesn't take a name
    -- argument -- errors already include line:col information.
    local ok, result = ParseLua(source)
    if not ok then
        local prefix = chunkName and (chunkName .. ": ") or ""
        return nil, prefix .. tostring(result)
    end
    return result, nil
end

return M
