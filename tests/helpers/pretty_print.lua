--[[
  pretty_print.lua

  Deterministic Lua-table serialization for snapshot files. Output is a
  loadable Lua chunk that returns the original table structure. Keys are
  sorted (strings alphabetical, numbers ascending, strings before numbers
  in mixed tables). Strings use %q (escape-safe round-trip). Numbers use
  %.17g (full precision). Empty tables collapse to {}; non-empty span lines.

  Self-test: lua tests/helpers/pretty_print.lua --test
]]

local M = {}

local function CompareKeys(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" then return a < b end
    return tostring(a) < tostring(b)
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, CompareKeys)
    return keys
end

local function FormatScalar(v)
    local t = type(v)
    if t == "string"  then return string.format("%q", v) end
    if t == "number"  then return string.format("%.17g", v) end
    if t == "boolean" then return tostring(v) end
    if t == "nil"     then return "nil" end
    error("pretty_print: unsupported scalar type " .. t)
end

local function FormatKey(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        return k
    end
    return "[" .. FormatScalar(k) .. "]"
end

local function Dump(value, indent, depth, out)
    if type(value) ~= "table" then
        out[#out + 1] = FormatScalar(value)
        return
    end
    local keys = SortedKeys(value)
    if #keys == 0 then
        out[#out + 1] = "{}"
        return
    end
    local pad = string.rep("  ", depth)
    local innerPad = string.rep("  ", depth + 1)
    out[#out + 1] = "{\n"
    for i, k in ipairs(keys) do
        out[#out + 1] = innerPad .. FormatKey(k) .. " = "
        Dump(value[k], indent, depth + 1, out)
        out[#out + 1] = (i < #keys) and ",\n" or "\n"
    end
    out[#out + 1] = pad .. "}"
end

function M.Format(t)
    local out = { "return " }
    Dump(t, "", 0, out)
    out[#out + 1] = "\n"
    return table.concat(out)
end

function M.WriteFile(path, t)
    local f, err = io.open(path, "w")
    if not f then error("pretty_print: cannot open " .. path .. ": " .. tostring(err)) end
    f:write(M.Format(t))
    f:close()
end

----------------------------------------------------------------------------
-- Self-test
----------------------------------------------------------------------------
local function SelfTest()
    local input = {
        b = 2,
        a = "first",
        nested = { z = true, y = "yes", [1] = "one" },
        empty = {},
    }
    local serialized = M.Format(input)

    -- Round-trip: load it back and verify equality.
    -- Lua 5.1 `load` only accepts a function; use `loadstring` there.
    -- Lua 5.2+ `load` accepts strings, but `loadstring` is gone.
    local loadFn = loadstring or load
    local chunk, err = loadFn(serialized, "pretty_print self-test")
    assert(chunk, "load failed: " .. tostring(err))
    local roundTrip = chunk()

    local function DeepEq(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k in pairs(a) do if not DeepEq(a[k], b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    assert(DeepEq(input, roundTrip), "round-trip mismatch:\n" .. serialized)

    -- Determinism: same input → same output
    assert(M.Format(input) == M.Format(input), "non-deterministic output")

    print("pretty_print self-test: OK")
end

if arg and arg[1] == "--test" then SelfTest() end

return M
