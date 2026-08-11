-- tests/unit/cdm_viewer_addon_test.lua
-- Run: lua tests/unit/cdm_viewer_addon_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_shared.lua", "cdm_viewer_addon.lua")("QUI", ns)

local A = assert(ns.CDMCooldownViewerAddon, "CDMCooldownViewerAddon should be exported")

assert(A.PRIMARY == "Blizzard_CooldownViewer", "primary addon name is Blizzard_CooldownViewer")
assert(A.IsViewerAddon("Blizzard_CooldownViewer"), "recognizes the current viewer addon")
assert(not A.IsViewerAddon("Blizzard_CooldownManager"), "does not recognize stale manager addon")
assert(not A.IsViewerAddon("Blizzard_Test"), "rejects unrelated addons")

local calls = {}
local ok, loadedName = A.Load(function(name)
    calls[#calls + 1] = name
    if name == "Blizzard_CooldownViewer" then
        error("missing current addon")
    end
    return true
end)
assert(ok == false and loadedName == nil, "does not fall back to the stale manager addon")
assert(#calls == 1 and calls[1] == "Blizzard_CooldownViewer", "tries only the current viewer addon")

calls = {}
ok, loadedName = A.Load(function(name)
    calls[#calls + 1] = name
    return true
end)
assert(ok == true and loadedName == "Blizzard_CooldownViewer", "uses current addon when it loads")
assert(#calls == 1, "does not load legacy addon after current addon succeeds")

print("OK: cdm_viewer_addon_test")
