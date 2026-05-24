-- tests/unit/cdm_composer_displaymode_toggle_gating_test.lua
-- Asserts ShouldShowItemDisplayModeRow gating predicate.

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local chunk = loadChunk("modules/cdm/cdm_domain.lua", "cdm_shared.lua")
chunk("QUI", ns)

local Shared = assert(ns.CDMShared, "CDMShared not exported")
local should = assert(Shared.ShouldShowItemDisplayModeRow,
    "ShouldShowItemDisplayModeRow was not exported on CDMShared")

local customDB  = { containerType = "customBar" }
local builtinDB = { containerType = "cooldown", builtIn = true }

-- Custom + item-type entry → true
assert(should({ type = "item",    id = 1 }, "customBar:test", customDB) == true,
    "custom + item should show row")
assert(should({ type = "trinket", id = 13 }, "customBar:test", customDB) == true,
    "custom + trinket should show row")
assert(should({ type = "slot",    id = 14 }, "customBar:test", customDB) == true,
    "custom + slot should show row")

-- Custom + spell/macro → false
assert(should({ type = "spell", id = 1 }, "customBar:test", customDB) == false,
    "custom + spell must NOT show row")
assert(should({ type = "macro", id = 1 }, "customBar:test", customDB) == false,
    "custom + macro must NOT show row")

-- Built-in containers → false regardless of type
for _, ckey in ipairs({"essential", "utility", "buff", "trackedBar"}) do
    assert(should({ type = "item", id = 1 }, ckey, builtinDB) == false,
        "built-in " .. ckey .. " must NOT show row")
end

-- nil / missing entry → false
assert(should(nil, "customBar:test", customDB) == false, "nil entry → false")
assert(should({ type = "item", id = 1 }, nil, nil) == false, "nil containerKey → false")
assert(should({ type = "item", id = 1 }, "customBar:test", nil) == false,
    "nil containerDB → false")

print("PASS: ShouldShowItemDisplayModeRow gating")
