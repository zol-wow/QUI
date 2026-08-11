-- tests/unit/cdm_icon_cooldown_policy_test.lua
-- Run: lua tests/unit/cdm_icon_cooldown_policy_test.lua
--
-- The Blizzard-mirror pipeline (charge-mirror cycle bookkeeping) was removed.
-- The cooldown policy controller now owns only the icon-local GCD swipe flags.

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_policies.lua", "cdm_icon_cooldown_policy.lua")("QUI", ns)

local policyModule = assert(ns.CDMIconCooldownPolicy, "CDMIconCooldownPolicy should be exported")

local policy = policyModule.Create()

local icon = {
    _spellEntry = { spellID = 100 },
}

policy:MarkGCDSwipe(icon)
assert(icon._showingGCDSwipe == true, "MarkGCDSwipe should stamp GCD swipe state")
assert(icon._showingRealCooldownSwipe == nil, "MarkGCDSwipe should clear real cooldown swipe state")
policy:ClearGCDSwipe(icon)
assert(icon._showingGCDSwipe == nil, "ClearGCDSwipe should clear GCD swipe state")

print("OK: cdm_icon_cooldown_policy_test")
