-- tests/unit/tooltip_npc_id_from_guid_test.lua
-- Run: lua tests/unit/tooltip_npc_id_from_guid_test.lua
--
-- Pins NpcIDFromGUID (the TIP-02 "NPC ID on tooltips" helper): the NPC ID is
-- field 6 of a Creature/Vehicle/Pet GUID; Player GUIDs (and malformed input)
-- must return nil. Extracts the function from tooltip.lua between its
-- QUI_TEST_EXTRACT sentinels and drives it with a Lua strsplit stand-in.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/tooltip.lua")
local S = "-- <<< QUI_TEST_EXTRACT npc_id"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

-- Prelude: WoW's strsplit over the standard string/table libs. Splits on the
-- separator and returns each field (empty fields preserved), matching how the
-- real strsplit hands back GUID fields positionally.
local prelude = [[
local function strsplit(sep, str)
    local out, i = {}, 1
    local s, e = string.find(str, sep, i, true)
    while s do
        out[#out + 1] = string.sub(str, i, s - 1)
        i = e + 1
        s, e = string.find(str, sep, i, true)
    end
    out[#out + 1] = string.sub(str, i)
    local up = table.unpack or unpack
    return up(out)
end
]]

local chunk = table.concat({
    prelude,
    block,
    "return { NpcIDFromGUID = NpcIDFromGUID }",
}, "\n")

local M = assert(loadstring(chunk, "tooltip_npc_id"))()

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- Creature GUID: field 6 is the NPC ID.
check("creature guid -> npcID 165946",
    M.NpcIDFromGUID("Creature-0-1465-2222-7-165946-000012ABCD") == 165946)
-- Vehicle + Pet GUIDs also carry an NPC ID in field 6.
check("vehicle guid -> npcID 12345",
    M.NpcIDFromGUID("Vehicle-0-1465-2222-7-12345-000012ABCD") == 12345)
check("pet guid -> npcID 777",
    M.NpcIDFromGUID("Pet-0-1465-2222-7-777-000012ABCD") == 777)
-- Player GUIDs have no NPC ID -> nil.
check("player guid -> nil",
    M.NpcIDFromGUID("Player-1465-0A2B3C4D") == nil)
-- Non-string / empty / malformed -> nil (no error).
check("nil -> nil", M.NpcIDFromGUID(nil) == nil)
check("number -> nil", M.NpcIDFromGUID(12345) == nil)
check("empty string -> nil", M.NpcIDFromGUID("") == nil)
check("creature guid missing field 6 -> nil",
    M.NpcIDFromGUID("Creature-0-1465") == nil)

if failures > 0 then
    print(("\n%d assertion(s) FAILED"):format(failures))
    os.exit(1)
end
print("\nall NpcIDFromGUID assertions passed")
