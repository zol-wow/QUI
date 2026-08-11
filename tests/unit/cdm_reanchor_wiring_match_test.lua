-- tests/unit/cdm_reanchor_wiring_match_test.lua
-- Run: lua tests/unit/cdm_reanchor_wiring_match_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring)

-- resolveEntryCooldownID override: entry.cd carries the cooldownID directly for the test
local wiring = W.New({ resolveEntryCooldownID = function(e) return e.cd end })

local fA, fB = { f = "A" }, { f = "B" }
local frameMap = { [11] = fA, [22] = fB }

local e1 = { name = "first", cd = 11 }   -- matches fA
local e2 = { name = "dup",   cd = 11 }   -- also cd 11, but fA already claimed -> frameless
local e3 = { name = "miss",  cd = 99 }   -- no frame -> frameless
local e4 = { name = "second", cd = 22 }  -- matches fB
local curated = { e1, e2, e3, e4 }

local matched, frameless, claimed = wiring:MatchCuratedToFrames(curated, frameMap)

assert(#matched == 2, "two matched")
assert(matched[1].entry == e1 and matched[1].frame == fA, "first match in curated order")
assert(matched[2].entry == e4 and matched[2].frame == fB, "second match in curated order")
assert(#frameless == 2, "two frameless (dup + miss)")
assert(frameless[1] == e2 and frameless[2] == e3, "frameless preserves curated order")
assert(claimed[fA] == true and claimed[fB] == true, "claimed set marks both frames")

-- Same spell can exist in multiple Blizzard CDM viewers with different cooldownIDs.
-- Matching an Essential container must use the Essential ordered provider identity;
-- the global CDMIndex.Get path may legitimately return the Buff duplicate first.
local fEssential = { f = "essential" }
local duplicateIndex = {
    IsUsableID = function(id) return type(id) == "number" and id > 0 end,
    GetOrderedForContainer = function(containerKey, spellID)
        if containerKey == "essential" and spellID == 12345 then
            return { cooldownID = 88, category = 0 }
        end
    end,
    Get = function(spellID)
        if spellID == 12345 then
            return { cooldownID = 22, category = 2 }
        end
    end,
}
local duplicateWiring = W.New({ index = duplicateIndex })
local duplicateEntry = { spellID = 12345, id = 12345, source = "blizzardCDM" }
local matched2, frameless2 = duplicateWiring:MatchCuratedToFrames(
    { duplicateEntry },
    { [88] = fEssential },
    "essential")
assert(#matched2 == 1 and matched2[1].entry == duplicateEntry and matched2[1].frame == fEssential,
    "container-specific ordered lookup should match the visible Essential frame")
assert(#frameless2 == 0, "visible Essential duplicate must not become frameless")

-- If the ordered cooldownID lookup is stale or incomplete, fall back to the
-- aliases collected from the live Blizzard frame itself. Blizzard-CDM-sourced
-- entries must not become frameless just because the provider identity missed.
local fAlias = { f = "alias" }
local aliasWiring = W.New({
    index = {
        IsUsableID = function() return false end,
        ToBaseSpellID = function(id)
            if type(id) == "number" and id > 0 then return id end
            return nil
        end,
    },
})
local matched3, frameless3 = aliasWiring:MatchCuratedToFrames(
    { { type = "spell", id = 777, source = "blizzardCDM" } },
    { _bySpell = { [777] = fAlias }, _byEquipSlot = {}, _bySpellCategory = {} },
    "essential")
assert(#matched3 == 1 and matched3[1].frame == fAlias,
    "spell entry should match by live frame spell alias when cooldownID lookup misses")
assert(#frameless3 == 0, "spell alias fallback must not leave the entry frameless")

local fSlot, fConsumable = { f = "slot" }, { f = "consumable" }
local matched4, frameless4 = aliasWiring:MatchCuratedToFrames(
    {
        { type = "slot", id = 13, source = "blizzardCDM" },
        { type = "consumable", id = 4, source = "blizzardCDM" },
    },
    {
        _bySpell = {},
        _byEquipSlot = { [13] = fSlot },
        _bySpellCategory = { [4] = fConsumable },
    },
    "essential")
assert(#matched4 == 2 and matched4[1].frame == fSlot and matched4[2].frame == fConsumable,
    "slot and consumable entries should match by live frame item identity fallback")
assert(#frameless4 == 0, "item identity fallback must not leave entries frameless")

print("OK: cdm_reanchor_wiring_match_test")
