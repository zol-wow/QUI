-- tests/unit/uihider_nameplate_cvar_delegation_test.lua
-- Run: lua tests/unit/uihider_nameplate_cvar_delegation_test.lua
--
-- CVar ownership handshake (plans/009-nameplates.md Phase 0): uihider must yield
-- to ns.QUI_NameplatesCVars when the suite's CVar owner is active, and its
-- fallback writes must stay inside the C_Timer.After(0) taint break. Static
-- source-pattern checks — uihider.lua needs a full frame environment to load.

local function fail(msg)
    print("FAIL: uihider_nameplate_cvar_delegation_test - " .. msg)
    os.exit(1)
end

local f = io.open("modules/ui/uihider.lua", "rb")
if not f then fail("cannot open modules/ui/uihider.lua") end
local src = f:read("*a")
f:close()

local blockStart = src:find("local friendly = profile and profile.nameplates and profile.nameplates.friendly", 1, true)
if not blockStart then fail("friendly nameplate block anchor not found") end
local block = src:sub(blockStart, blockStart + 2200)

-- 1. The delegation must consult the suite's CVar owner.
if not block:find("ns%.QUI_NameplatesCVars") then
    fail("friendly CVar block must consult ns.QUI_NameplatesCVars")
end
if not block:find("IsActive") then
    fail("delegation must gate on the owner's IsActive()")
end
if not block:find("profile%.nameplates%.friendly") then
    fail("uihider must derive from profile.nameplates.friendly, not its own keys")
end

-- 2. The delegation and the fallback SetCVar writes must both be inside the
--    C_Timer.After(0) deferred closure (taint break). Check order: the
--    C_Timer.After appears before the owner check, and the SetCVar fallback
--    after the owner check.
local deferPos = block:find("C_Timer%.After%(0")
local ownerPos = block:find("ns%.QUI_NameplatesCVars")
local setcvarPos = block:find('SetCVar%("nameplateShowFriendlyPlayers"')
if not (deferPos and ownerPos and setcvarPos) then
    fail("expected defer + owner check + fallback SetCVar in the block")
end
if not (deferPos < ownerPos and ownerPos < setcvarPos) then
    fail("owner delegation must sit inside the deferred closure, before the SetCVar fallback")
end

-- 3. The fallback must return before the raw writes when the owner is active.
local returnPos = block:find("return", ownerPos, true)
if not (returnPos and returnPos < setcvarPos) then
    fail("active-owner path must return before the raw SetCVar writes")
end

-- 4. No OTHER writer of the friendly visibility CVars may exist in uihider
--    outside this block (single-owner rule).
local before = src:sub(1, blockStart - 1)
local after = src:sub(blockStart + 2200)
if before:find('SetCVar%("nameplateShowFriendly') or after:find('SetCVar%("nameplateShowFriendly') then
    fail("nameplateShowFriendly* CVars written outside the delegated block")
end

print("OK: uihider_nameplate_cvar_delegation_test")
