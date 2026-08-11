-- tests/unit/cdm_reanchor_enumerate_test.lua
-- Run: lua tests/unit/cdm_reanchor_enumerate_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)
local CDMReanchor = assert(ns.CDMReanchor)
local bridge = CDMReanchor.New()

-- (a) GetItemFrames path
local a, b = {}, {}
local viewer1 = { GetItemFrames = function() return { a, b } end }
local items1 = bridge:EnumerateItems(viewer1)
assert(#items1 == 2 and items1[1] == a and items1[2] == b, "GetItemFrames path returns ordered frames")

-- (b) itemFramePool:EnumerateActive fallback
local c, d, e = {}, {}, {}
local pooled = { c, d, e }
local viewer2 = {
    itemFramePool = {
        EnumerateActive = function()
            local i = 0
            return function() i = i + 1; return pooled[i] end
        end,
    },
}
local items2 = bridge:EnumerateItems(viewer2)
assert(#items2 == 3 and items2[1] == c and items2[3] == e, "itemFramePool fallback enumerates active frames")

-- (c) empty viewer
assert(#bridge:EnumerateItems({}) == 0, "viewer with no items -> empty array")

print("OK: cdm_reanchor_enumerate_test")
