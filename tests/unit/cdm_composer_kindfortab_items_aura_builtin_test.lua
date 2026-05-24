-- tests/unit/cdm_composer_kindfortab_items_aura_builtin_test.lua
-- Asserts CDMShared.ResolveKindForItemsTab returns "aura" for built-in
-- aura containers, "cooldown" everywhere else (including custom containers).

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
    },
}

-- Load the cdm_shared.lua chunk from the consolidated domain file.
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local chunk = loadChunk("modules/cdm/cdm_domain.lua", "cdm_shared.lua")
chunk("QUI", ns)

local Shared = assert(ns.CDMShared, "CDMShared not exported")
local resolve = assert(Shared.ResolveKindForItemsTab,
    "ResolveKindForItemsTab was not exported on CDMShared")

assert(resolve("buff")       == "aura",     "buff container Items-tab add must resolve kind=aura")
assert(resolve("trackedBar") == "aura",     "trackedBar container Items-tab add must resolve kind=aura")
assert(resolve("essential")  == "cooldown", "essential container Items-tab add must remain kind=cooldown")
assert(resolve("utility")    == "cooldown", "utility container Items-tab add must remain kind=cooldown")
-- Custom containers: kind=cooldown (override flow takes it from there).
assert(resolve("customBar:test") == "cooldown",
    "custom containers must remain kind=cooldown on Items-tab adds")
assert(resolve(nil)            == "cooldown", "nil containerKey must default to cooldown")

print("PASS: ResolveKindForItemsTab kind resolution by container")
