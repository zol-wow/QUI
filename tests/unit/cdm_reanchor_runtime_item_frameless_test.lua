-- tests/unit/cdm_reanchor_runtime_item_frameless_test.lua
-- A frameless Blizzard-CDM entry must NOT be minted as a synthetic icon; manual
-- frameless entries still are, including trinket/slot entries from the Items tab.
-- Run: lua tests/unit/cdm_reanchor_runtime_item_frameless_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local eManual   = { type = "spell",      name = "manual",   _assignedRow = 1 }
local eBlizzard = { type = "spell",      name = "blizzard", _assignedRow = 2, source = "blizzardCDM" }
local eSlot     = { type = "slot",       name = "slot",     _assignedRow = 3 }
local eBlizzSlot= { type = "slot",       name = "blizzslot",_assignedRow = 4, source = "blizzardCDM" }
local eConsum   = { type = "consumable", name = "consum",   _assignedRow = 5 }
local eTrinket  = { type = "trinket",    name = "trinket",  _assignedRow = 6 }

-- all entries are frameless (no Blizzard frame matched)
local wiring = {
    MatchCuratedToFrames = function(_, curated, frameMap)
        return {}, { eManual, eBlizzard, eSlot, eBlizzSlot, eConsum, eTrinket }, {}
    end,
}
local minted = {}
local runtime = R.New({
    bridge = {}, wiring = wiring,
    getCurated = function() return { eManual, eBlizzard, eSlot, eBlizzSlot, eConsum, eTrinket } end,
    getAdditional = function() return {} end,
    mintOwned = function(entry)
        minted[#minted + 1] = entry
        return { icon = entry.name }  -- a non-nil synthetic icon
    end,
})

local entries = runtime:AssembleEntries("essential", {})

assert(#entries == 4, "manual frameless entries should be assembled, got " .. #entries)
assert(entries[1].src == eManual, "the surviving entry is the manual spell")
assert(entries[2].src == eSlot, "manual slot survives as owned fallback")
assert(entries[3].src == eConsum, "manual consumable survives as owned fallback")
assert(entries[4].src == eTrinket, "manual trinket survives as owned fallback")
assert(#minted == 4 and minted[1] == eManual and minted[2] == eSlot
    and minted[3] == eConsum and minted[4] == eTrinket,
    "mintOwned called ONLY for manual entries, not Blizzard-CDM entries")

print("OK cdm_reanchor_runtime_item_frameless_test")
