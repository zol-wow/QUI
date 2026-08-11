-- tests/unit/backdrop_deferred_combat_retry_test.lua
-- Run: lua tests/unit/backdrop_deferred_combat_retry_test.lua
--
-- The deferred-backdrop OnUpdate incremented pendingData.retries every tick
-- even when InCombatLockdown() was the only blocker, so 5s of combat
-- (50 ticks) permanently abandoned frames whose dimensions would have become
-- valid after combat. Combat ticks must return before touching retry counts;
-- the OnUpdate keeps running and resumes naturally after regen.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("core/backdrop_deferred.lua")

local tickStart = assert(source:find('updateFrame:SetScript("OnUpdate"', 1, true))
local retryIdx = assert(source:find("pendingData.retries = (pendingData.retries or 0) + 1", tickStart, true))
local combatIdx = source:find("if InCombatLockdown() then return end", tickStart, true)

assert(combatIdx, "OnUpdate tick must bail out during combat")
assert(combatIdx < retryIdx, "combat bail must precede retry increment")

print("PASS backdrop_deferred_combat_retry_test")
