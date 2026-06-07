-- tests/unit/damage_meter_normalize_test.lua
-- Run: lua tests/unit/damage_meter_normalize_test.lua
--
-- Standalone test for Data.NormalizeSources. Extracts the function body by
-- locating its declaration in the source file and load()-ing just that chunk.
-- Avoids needing a Lua loader that understands WoW globals like CreateFrame.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

-- Find the function declaration and extract everything until Data._NormalizeSources
local start_pos = src:find("local function NormalizeSources")
assert(start_pos, "could not locate NormalizeSources block in damage_meter.lua")

-- Find the assignment to Data._NormalizeSources which marks the end
local end_pos = src:find("Data%._NormalizeSources", start_pos)
assert(end_pos, "could not locate Data._NormalizeSources assignment")

-- Extract the function definition
local chunk = src:sub(start_pos, end_pos - 1):match("^(.-)\n%s*$")
assert(chunk, "failed to extract function chunk")

-- Load the function and extract it
local loader = assert(loadstring(chunk .. "\nreturn NormalizeSources"))
local NormalizeSources = loader()

-- Case 1: empty input
do
    local view = NormalizeSources({})
    assert(#view == 0, "empty input must return empty view")
end

-- Case 2: rank assigned by input order (no re-sort)
do
    local raw = {
        { name = "Alpha",   totalAmount = 1000, isLocalPlayer = false },
        { name = "Bravo",   totalAmount = 3000, isLocalPlayer = true  },
        { name = "Charlie", totalAmount = 2000, isLocalPlayer = false },
    }
    local view = NormalizeSources(raw)
    assert(#view == 3, "view should have 3 entries")
    -- New invariant: input order preserved (API returns pre-sorted)
    assert(view[1].name == "Alpha",   "rank 1 must be Alpha (first in input)")
    assert(view[1].rank == 1,         "rank 1 must be marked")
    assert(view[1].totalAmount == 1000, "totalAmount preserved")
    assert(view[2].name == "Bravo",   "rank 2 must be Bravo (second in input)")
    assert(view[3].name == "Charlie", "rank 3 must be Charlie")
end

-- Case 3: missing totalAmount is preserved as nil (renderer guards arithmetic)
do
    local raw = { { name = "Solo" } }  -- no totalAmount field
    local view = NormalizeSources(raw)
    assert(view[1].totalAmount == nil, "missing totalAmount stays nil")
end

-- Case 4: amountPerSecond pulled from input (was computed previously)
do
    local raw = { { name = "Solo", totalAmount = 500, amountPerSecond = 50 } }
    local view = NormalizeSources(raw)
    assert(view[1].amountPerSecond == 50, "amountPerSecond preserved from input")
end

-- Phase 5 fix: secret-value handling source-pattern check
do
    local src2 = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")
    assert(src2:find("Helpers.IsSecretValue", 1, true),
        "NormalizeSources / formatters must consult Helpers.IsSecretValue")
    assert(src2:find("C_StringUtil", 1, true),
        "FormatDuration/FormatNumber must route secret values through C_StringUtil")
end

print("OK: damage_meter_normalize_test")
