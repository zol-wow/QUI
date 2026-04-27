--[[
  deep_compare.lua

  Structural equality with path-rooted diff output for snapshot mismatches.

  M.Equal(a, b)              → boolean
  M.Diff(a, b, rootLabel)    → list of diff entries; empty list when equal

  Diff entry shapes:
    { op = "+",  path = "profile.x",       value = "added" }
    { op = "-",  path = "profile.y",       value = "removed" }
    { op = "~",  path = "profile.z", from = old, to = new }

  Self-test: lua tests/helpers/deep_compare.lua --test
]]

local M = {}

local function Repr(v)
    local t = type(v)
    if t == "string"  then return string.format("%q", v) end
    if t == "number"  then return string.format("%.17g", v) end
    if t == "table"   then return "<table>" end
    return tostring(v)
end

local function JoinPath(base, key)
    if base == "" then return tostring(key) end
    if type(key) == "number" then return base .. "[" .. key .. "]" end
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        return base .. "." .. key
    end
    return base .. "[" .. Repr(key) .. "]"
end

local function CollectDiff(a, b, path, out)
    if type(a) ~= "table" or type(b) ~= "table" then
        if a ~= b then
            out[#out + 1] = { op = "~", path = path, from = a, to = b }
        end
        return
    end
    -- keys in a
    for k, va in pairs(a) do
        local p = JoinPath(path, k)
        local vb = b[k]
        if vb == nil then
            out[#out + 1] = { op = "-", path = p, value = va }
        elseif type(va) == "table" or type(vb) == "table" then
            CollectDiff(va, vb, p, out)
        elseif va ~= vb then
            out[#out + 1] = { op = "~", path = p, from = va, to = vb }
        end
    end
    -- keys only in b
    for k, vb in pairs(b) do
        if a[k] == nil then
            out[#out + 1] = { op = "+", path = JoinPath(path, k), value = vb }
        end
    end
end

function M.Diff(a, b, rootLabel)
    local out = {}
    CollectDiff(a, b, rootLabel or "", out)
    return out
end

function M.Equal(a, b)
    return #M.Diff(a, b, "") == 0
end

function M.FormatDiff(diff)
    local lines = {}
    -- Sort by path for readable output
    table.sort(diff, function(x, y) return x.path < y.path end)
    for _, e in ipairs(diff) do
        if e.op == "+" then
            lines[#lines + 1] = "  + " .. e.path .. " = " .. Repr(e.value)
        elseif e.op == "-" then
            lines[#lines + 1] = "  - " .. e.path .. " = " .. Repr(e.value)
        else
            lines[#lines + 1] = "  ~ " .. e.path .. ": " .. Repr(e.from) .. " → " .. Repr(e.to)
        end
    end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------------
-- Self-test
----------------------------------------------------------------------------
local function SelfTest()
    -- Equal
    assert(M.Equal({}, {}))
    assert(M.Equal({ a = 1 }, { a = 1 }))
    assert(M.Equal({ a = { b = 2 } }, { a = { b = 2 } }))

    -- Scalar mismatch
    local d = M.Diff({ a = 1 }, { a = 2 }, "root")
    assert(#d == 1 and d[1].op == "~" and d[1].path == "root.a" and d[1].from == 1 and d[1].to == 2)

    -- Added key
    d = M.Diff({}, { a = 1 }, "p")
    assert(#d == 1 and d[1].op == "+" and d[1].path == "p.a" and d[1].value == 1)

    -- Removed key
    d = M.Diff({ a = 1 }, {}, "p")
    assert(#d == 1 and d[1].op == "-" and d[1].path == "p.a" and d[1].value == 1)

    -- Nested + array index
    d = M.Diff({ list = { 10, 20 } }, { list = { 10, 99 } }, "p")
    assert(#d == 1 and d[1].path == "p.list[2]" and d[1].from == 20 and d[1].to == 99)

    -- Format output
    local out = M.FormatDiff(M.Diff({ a = 1, b = 2 }, { a = 1, c = 3 }, "p"))
    assert(out:find("- p.b"))
    assert(out:find("+ p.c"))

    print("deep_compare self-test: OK")
end

if arg and arg[1] == "--test" then SelfTest() end

return M
