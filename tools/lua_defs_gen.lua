-- tools/lua_defs_gen.lua
-- Pure transform helpers that turn a parsed Blizzard APIDocumentation table
-- into LuaLS meta-definition source. IO/discovery lives in
-- tools/generate_lua_definitions.lua, which consumes these.

local M = {}

local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

-- WoW documentation types → Lua types. Anything not listed (enums, structures,
-- mixins) maps to `any`, which keeps generated definitions safe: no
-- undefined-class warnings, and the value stays freely usable.
local PRIMITIVE = {
    bool = "boolean", luaBoolean = "boolean",
    string = "string", cstring = "string", WOWGUID = "string", guid = "string",
    hyperlink = "string", textureAtlas = "string", uiTextureKit = "string",
    number = "number", luaIndex = "number", BigInteger = "number",
    time_t = "number", uiUnit = "number", fileID = "number", uiAddress = "number",
    colorRGB = "number", normalizedValue = "number", single = "number",
    double = "number", float = "number",
    table = "table", luaTable = "table",
    ["function"] = "function", luaFunction = "function",
}

function M.mapType(t)
    if not t then return "any" end
    return PRIMITIVE[t] or "any"
end

function M.sanitizeName(name)
    if not name or name == "" then return "_" end
    name = name:gsub("[^%w_]", "_")
    if name:match("^%d") then name = "_" .. name end
    if LUA_KEYWORDS[name] then name = name .. "_" end
    return name
end

-- Build the shared annotation lines (doc, @param, trailing vararg, @return) and
-- the comma-joined parameter list for a function. All params are optional and a
-- trailing `...any` is appended, so the generated signature never produces
-- missing-parameter or redundant-parameter warnings when the vendored docs lag
-- the live client.
local function buildSignature(fn)
    local lines = {}
    if type(fn.Documentation) == "table" and fn.Documentation[1] then
        lines[#lines + 1] = "--- " .. table.concat(fn.Documentation, " ")
    end
    local params = {}
    if type(fn.Arguments) == "table" then
        for _, a in ipairs(fn.Arguments) do
            local pname = M.sanitizeName(a.Name)
            params[#params + 1] = pname
            lines[#lines + 1] = string.format("---@param %s? %s", pname, M.mapType(a.Type))
        end
    end
    lines[#lines + 1] = "---@param ... any"
    params[#params + 1] = "..."
    if type(fn.Returns) == "table" then
        for _, r in ipairs(fn.Returns) do
            lines[#lines + 1] = string.format("---@return %s %s",
                M.mapType(r.Type), M.sanitizeName(r.Name))
        end
    end
    return lines, table.concat(params, ", ")
end

-- Emit a function's annotation block + stub definition.
--   namespace nil  → global function `function Name(...) end`
--   namespace set  → `function Namespace.Name(...) end`
function M.emitFunction(fn, namespace)
    local lines, paramList = buildSignature(fn)
    local fullname = namespace and (namespace .. "." .. fn.Name) or fn.Name
    lines[#lines + 1] = string.format("function %s(%s) end", fullname, paramList)
    return table.concat(lines, "\n")
end

-- Emit a widget method `function Class:Name(...) end` (colon — implicit self).
function M.emitMethod(fn, className)
    local lines, paramList = buildSignature(fn)
    lines[#lines + 1] = string.format("function %s:%s(%s) end", className, fn.Name, paramList)
    return table.concat(lines, "\n")
end

return M
