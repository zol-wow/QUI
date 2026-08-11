-- tests/unit/cdm_reanchor_runtime_aura_mirror_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_aura_mirror_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_placement_planner.lua", "cdm_placement_planner.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local shared = {}
local containers = { essential = {}, utility = {} }
local entries = {
    essential = { type = "spell", id = 100, kind = "aura", source = "blizzardCDM" },
    utility = { type = "spell", id = 100, kind = "aura", source = "blizzardCDM" },
}
local began, acquired, positioned, ended = {}, {}, {}, {}
local runtime = R.New({
    bridge = { InstallAnchorGuard = function() end, OverlayRect = function() end, Sink = function() end },
    wiring = {
        GetViewersForKey = function(_, key) return { key } end,
        BuildFrameMapForViewers = function() return { [100] = shared }, { shared } end,
        MatchCuratedToFrames = function(_, curated)
            return { { entry = curated[1], frame = shared } }, {}, { [shared] = true }
        end,
    },
    placementPlanner = ns.CDMPlacementPlanner,
    getContainer = function(key) return containers[key] end,
    getSettings = function() return { enabled = true } end,
    getCurated = function(key) return { entries[key] } end,
    getAdditional = function() return {} end,
    mintOwned = function(entry) return { entry = entry } end,
    releaseOwned = function() return true end,
    positionOwned = function() error("managed aura placement should own positioning") end,
    beginAuraMirrorPass = function(container) began[#began + 1] = container; return true end,
    acquireAuraMirror = function(entry, key, placementKey)
        acquired[#acquired + 1] = { entry = entry, key = key, placementKey = placementKey }
        return { id = "managed" }
    end,
    positionAuraMirror = function(record, icon, container)
        positioned[#positioned + 1] = { record = record, icon = icon, container = container }
        return true
    end,
    endAuraMirrorPass = function(container) ended[#ended + 1] = container end,
    positionClickSlot = function() return {} end,
    updateClickOverlay = function() end,
    buildLayout = function(_, icons)
        local placements = {}
        for i = 1, #icons do
            placements[i] = { icon = icons[i], x = 0, y = 0, rowConfig = { size = 30 } }
        end
        return { placements = placements, metrics = {} }
    end,
})

local counts = runtime:RefreshContainers({ "utility", "essential" })
assert(counts.essential == 1 and counts.utility == 1, "aura duplicate keeps both placements")
assert(#acquired == 1 and acquired[1].key == "utility"
    and type(acquired[1].placementKey) == "string",
    "only the non-owner aura placement allocates a managed overlay")
assert(#positioned == 1 and positioned[1].container == containers.utility,
    "managed overlay positions the utility mirror's owned base")
assert(#began == 2 and #ended == 2, "every participating container closes its aura pass")

print("OK: cdm_reanchor_runtime_aura_mirror_test")
