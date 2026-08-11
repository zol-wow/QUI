-- tests/unit/cdm_reanchor_wiring_viewer_test.lua
-- Run: lua tests/unit/cdm_reanchor_wiring_viewer_test.lua
-- luacheck: globals EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer BuffBarCooldownViewer
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring, "CDMReanchorWiring should be exported")
assert(type(W.New) == "function", "New is a function")

-- default path resolves Blizzard viewer globals via _G
EssentialCooldownViewer = { tag = "ess" }
BuffIconCooldownViewer = { tag = "bufficon" }
local wiring = W.New({})
assert(wiring:GetViewerForKey("essential") == EssentialCooldownViewer, "essential -> EssentialCooldownViewer")
assert(wiring:GetViewerForKey("buff") == BuffIconCooldownViewer, "buff -> BuffIconCooldownViewer")
assert(wiring:GetViewerForKey("trackedBar") == nil, "trackedBar global not set -> nil")
assert(wiring:GetViewerForKey("nonsense") == nil, "unknown key -> nil")

-- injected override wins
local fake = {}
local wiring2 = W.New({ getViewerForKey = function(k) return k == "utility" and fake or nil end })
assert(wiring2:GetViewerForKey("utility") == fake, "deps.getViewerForKey override honored")

EssentialCooldownViewer = nil
BuffIconCooldownViewer = nil
print("OK: cdm_reanchor_wiring_viewer_test")
