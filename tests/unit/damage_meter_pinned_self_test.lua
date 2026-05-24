-- tests/unit/damage_meter_pinned_self_test.lua
-- Run: lua tests/unit/damage_meter_pinned_self_test.lua
--
-- Standalone test for the FindLocalPlayerInSources helper. We extract the
-- function body and load() it; it touches no WoW globals.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("modules/damage_meter/damage_meter.lua")
local chunk = src:match("(local function FindLocalPlayerInSources.-\nend\n)")
assert(chunk, "could not locate FindLocalPlayerInSources in damage_meter.lua")

local loader = assert(loadstring(chunk .. "\nreturn FindLocalPlayerInSources"))
local FindLocalPlayerInSources = loader()

-- Case 1: empty sources -> nil
assert(FindLocalPlayerInSources({}) == nil, "empty -> nil")

-- Case 2: player at rank 1 -> returns 1
assert(FindLocalPlayerInSources({
    { rank = 1, isLocalPlayer = true },
    { rank = 2, isLocalPlayer = false },
}) == 1, "player at rank 1")

-- Case 3: player at rank 7 -> returns 7
local sources = {}
for i = 1, 10 do
    sources[i] = { rank = i, isLocalPlayer = (i == 7) }
end
assert(FindLocalPlayerInSources(sources) == 7, "player at rank 7")

-- Case 4: no local player -> nil
assert(FindLocalPlayerInSources({
    { rank = 1, isLocalPlayer = false },
    { rank = 2, isLocalPlayer = false },
}) == nil, "no local player -> nil")

-- Case 5: nil input -> nil
assert(FindLocalPlayerInSources(nil) == nil, "nil -> nil")

print("OK: damage_meter_pinned_self_test")
