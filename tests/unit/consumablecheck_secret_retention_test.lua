-- tests/unit/consumablecheck_secret_retention_test.lua
-- Run: lua tests/unit/consumablecheck_secret_retention_test.lua
--
-- AuraScanCount() already collapses the buff scan to 0 while
-- C_Secrets.ShouldAurasBeSecret() (consumablecheck.lua:781-786) with the
-- stated intent "keep the last displayed state instead of erroring" — but
-- the state/inventory split's compute/diff/paint pipeline reads
-- snapshotCache.lastStates in DiffButtonStates immediately after
-- ComputeDesiredStates runs, so a restricted UNIT_AURA event that reached
-- the compute/diff bookkeeping with a secret-collapsed scan would repaint
-- everything Not-Ready, just like the old reset did. The secrecy gate must
-- run before any state compute/diff bookkeeping.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("modules/qol/consumablecheck.lua")

local fnStart = assert(source:find("UpdateConsumables = function()", 1, true))
local computeMarker = assert(source:find("local states = ComputeDesiredStates(settings, canUseItems)", fnStart, true))
local head = source:sub(fnStart, computeMarker)

assert(head:find("ShouldAurasBeSecret", 1, true),
    "UpdateConsumables must gate on aura secrecy BEFORE any state compute/diff bookkeeping")

print("PASS consumablecheck_secret_retention_test")
