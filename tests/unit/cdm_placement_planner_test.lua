-- tests/unit/cdm_placement_planner_test.lua
-- Run: lua tests/unit/cdm_placement_planner_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_placement_planner.lua", "cdm_placement_planner.lua")("QUI", ns)
local P = assert(ns.CDMPlacementPlanner)

local shared = {}
local essential = { type = "spell", id = 100, kind = "cooldown" }
local utility = { type = "spell", id = 100, kind = "cooldown" }

local plan = P.Plan({
    { containerKey = "utility", ordinal = 1, entry = utility, frame = shared },
    { containerKey = "essential", ordinal = 1, entry = essential, frame = shared },
})
assert(plan.ownerByFrame[shared].containerKey == "essential",
    "fixed ownership must not depend on candidate/refresh order")
assert(plan.assignmentsByContainer.essential[essential].renderKind == "native",
    "essential owns an ordinary shared spell")
assert(plan.assignmentsByContainer.utility[utility].renderKind == "spellMirror",
    "the second ordinary placement becomes a spell mirror")
assert(#plan.consumersByFrame[shared] == 2, "both logical placements remain consumers")
assert(plan.consumersByFrame[shared][1].renderKind == "native"
    and plan.consumersByFrame[shared][2].renderKind == "spellMirror",
    "consumer fanout exposes resolved placement renderers")

local auraFrame = {}
local auraEssential = { type = "spell", id = 200, kind = "aura" }
local auraBuff = { type = "spell", id = 200, kind = "aura" }
local auraPlan = P.Plan({
    { containerKey = "essential", ordinal = 1, entry = auraEssential, frame = auraFrame },
    { containerKey = "buff", ordinal = 1, entry = auraBuff, frame = auraFrame },
})
assert(auraPlan.ownerByFrame[auraFrame].containerKey == "buff",
    "the Blizzard buff surface preserves native aura lifecycle/layout")
assert(auraPlan.assignmentsByContainer.essential[auraEssential].renderKind == "auraMirror",
    "a duplicate aura outside the buff surface becomes a managed-aura mirror")

local itemFrame = {}
local itemEssential = { type = "slot", id = 13 }
local itemUtility = { type = "slot", id = 13 }
local itemPlan = P.Plan({
    { containerKey = "utility", ordinal = 1, entry = itemUtility, frame = itemFrame },
    { containerKey = "essential", ordinal = 1, entry = itemEssential, frame = itemFrame },
})
assert(itemPlan.assignmentsByContainer.essential[itemEssential].renderKind == "native",
    "one equipment placement retains the exact native frame")
assert(itemPlan.assignmentsByContainer.utility[itemUtility].renderKind == "unsupportedMirror",
    "extra equipment placements fail explicitly instead of showing false timing")

local mixedFrame = {}
local spellEntry = { type = "spell", id = 300 }
local slotEntry = { type = "slot", id = 13 }
local mixedPlan = P.Plan({
    { containerKey = "buff", ordinal = 1, entry = spellEntry, frame = mixedFrame },
    { containerKey = "utility", ordinal = 1, entry = slotEntry, frame = mixedFrame },
})
assert(mixedPlan.ownerByFrame[mixedFrame].entry == slotEntry,
    "native-only identity outranks the normal container preference")

local totemFrame = {}
local totemEssential = { type = "spell", id = 500, _isTotemInstance = true }
local totemUtility = { type = "spell", id = 500, _isTotemInstance = true }
local totemPlan = P.Plan({
    { containerKey = "utility", ordinal = 1, entry = totemUtility, frame = totemFrame },
    { containerKey = "essential", ordinal = 1, entry = totemEssential, frame = totemFrame },
})
assert(totemPlan.assignmentsByContainer.essential[totemEssential].renderKind == "native",
    "one secure totem placement retains the native frame")
assert(totemPlan.assignmentsByContainer.utility[totemUtility].renderKind == "unsupportedMirror",
    "secure totem instances never enter the ordinary spell-mirror path")

local keyA = P.BuildPlacementKey("essential", 2, { type = "spell", id = 400, _instanceKey = "x" })
local keyB = P.BuildPlacementKey("essential", 2, { type = "spell", id = 400, _instanceKey = "x" })
assert(keyA == keyB, "placement keys are deterministic runtime identities")

print("OK: cdm_placement_planner_test")
