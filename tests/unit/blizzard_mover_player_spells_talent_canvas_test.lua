-- tests/unit/blizzard_mover_player_spells_talent_canvas_test.lua
-- Run: lua tests/unit/blizzard_mover_player_spells_talent_canvas_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function blockForId(source, id)
    local pattern = '{%s*id = "' .. id .. '".-defaultEnabled = true,%s*}'
    return source:match(pattern)
end

local frameRegistry = readFile("QUI_QoL/qol/blizzard_mover_frames.lua")
local playerSpellsBlock = assert(blockForId(frameRegistry, "PlayerSpellsFrame"), "PlayerSpellsFrame registry entry should exist")

assert(playerSpellsBlock:find('"TalentsFrame"', 1, true), "PlayerSpellsFrame should keep the talent tab as a drag surface")
assert(not playerSpellsBlock:find("TalentsFrame.ButtonsParent", 1, true), "PlayerSpellsFrame must not hook the talent button canvas")

print("OK: blizzard_mover_player_spells_talent_canvas_test")
