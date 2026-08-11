-- tests/unit/cdm_reanchor_runtime_new_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_new_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime, "CDMReanchorRuntime should be exported")
assert(type(R.New) == "function", "New is a function")
local inst = R.New({ bridge = "B", wiring = "W" })
assert(type(inst) == "table", "New returns an instance")
assert(inst._bridge == "B" and inst._wiring == "W", "bridge/wiring stored")
print("OK: cdm_reanchor_runtime_new_test")
