-- tests/unit/bonus_roll_anchor_defer_test.lua
-- Run: lua tests/unit/bonus_roll_anchor_defer_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("modules/layout/layoutmode.lua")
local blockStart = assert(
    source:find("if _G.BonusRollFrame and not _G.BonusRollFrame._QUI_AnchorHooked then", 1, true),
    "BonusRollFrame anchoring hook block should exist")
local blockEnd = assert(
    source:find("local function ChatDB()", blockStart, true),
    "BonusRollFrame anchoring hook block should end before the chat section")
local block = source:sub(blockStart, blockEnd - 1)

assert(
    block:find("C_Timer.After%(0", 1, false) or block:find("RunNextFrame", 1, true),
    "BonusRollFrame anchoring must defer out of Blizzard Show/SetPoint setup")

assert(
    not block:find('hooksecurefunc%(bonusRollFrame, "SetPoint", ApplyBonusRollAnchor%)', 1, false),
    "BonusRollFrame SetPoint hook must schedule, not apply synchronously")

assert(
    not block:find('hooksecurefunc%(bonusRollFrame, "Show", ApplyBonusRollAnchor%)', 1, false),
    "BonusRollFrame Show hook must schedule, not apply synchronously")

assert(
    not block:find('HookScript%("OnShow", ApplyBonusRollAnchor%)', 1, false),
    "BonusRollFrame OnShow hook must schedule, not apply synchronously")

print("OK: bonus_roll_anchor_defer_test")
