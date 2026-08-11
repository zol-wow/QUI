-- tests/unit/cdm_reanchor_module_test.lua
-- Run: lua tests/unit/cdm_reanchor_module_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)

local CDMReanchor = assert(ns.CDMReanchor, "CDMReanchor should be exported")
assert(type(CDMReanchor.New) == "function", "New should be a function")

local bridge = CDMReanchor.New()
assert(type(bridge) == "function" or type(bridge) == "table", "New returns an instance")

local frame = {}
assert(bridge:IsClaimed(frame) == false, "fresh frame is not claimed")
local data = bridge:GetData(frame)
assert(type(data) == "table", "GetData returns a table")
assert(bridge:GetData(frame) == data, "GetData is stable per frame")
assert(next(frame) == nil, "GetData must NOT write onto the frame")

print("OK: cdm_reanchor_module_test")
