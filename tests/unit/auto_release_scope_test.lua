-- tests/unit/auto_release_scope_test.lua
-- Run: lua tests/unit/auto_release_scope_test.lua
--
-- Proves the SYS-01 auto-release SAFETY property: it must NEVER auto-release in
-- a dungeon, raid, or arena (where a combat resurrection matters). Extracts the
-- pure ShouldAutoReleaseInScope decision from qol.lua between its
-- QUI_TEST_EXTRACT sentinels and exhaustively checks the scope matrix.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/qol.lua")
local S = "-- <<< QUI_TEST_EXTRACT release_scope"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

local chunk = block .. "\nreturn { ShouldAutoReleaseInScope = ShouldAutoReleaseInScope }"
local M = assert(loadstring(chunk, "auto_release_scope"))()
local F = M.ShouldAutoReleaseInScope

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- SAFETY: never in dungeon (party), raid, or arena, in ANY mode.
for _, mode in ipairs({ "pvp", "pvpworld" }) do
    check("NEVER in dungeon ("..mode..")",   F(mode, true, "party") == false)
    check("NEVER in raid ("..mode..")",      F(mode, true, "raid")  == false)
    check("NEVER in arena ("..mode..")",     F(mode, true, "arena") == false)
    check("ALWAYS in battleground ("..mode..")", F(mode, true, "pvp") == true)
end

-- Open world: only when opted into "pvpworld".
check("open world: pvpworld -> release", F("pvpworld", false, "none") == true)
check("open world: pvp -> no release",   F("pvp", false, "none") == false)

-- Off / unset: never.
check("off -> never (world)",   F("off", false, "none") == false)
check("off -> never (bg)",      F("off", true, "pvp")  == false)
check("nil mode -> never",      F(nil, true, "pvp")    == false)

if failures > 0 then
    print(("\n%d assertion(s) FAILED"):format(failures))
    os.exit(1)
end
print("\nall auto-release scope assertions passed")
