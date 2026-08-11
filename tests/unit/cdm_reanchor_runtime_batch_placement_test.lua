-- tests/unit/cdm_reanchor_runtime_batch_placement_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_batch_placement_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_placement_planner.lua", "cdm_placement_planner.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local shared = { id = "shared-native" }
local viewers = { essential = { id = "ve" }, utility = { id = "vu" } }
local containers = { essential = { id = "ce" }, utility = { id = "cu" } }
local entries = {
    essential = { type = "spell", id = 100, source = "blizzardCDM", _assignedRow = 1 },
    utility = { type = "spell", id = 100, source = "blizzardCDM", _assignedRow = 1 },
}
local enabled = { essential = true, utility = true }
local overlayRects, sinks, positionedOwned = {}, {}, {}
local nextOwned = 0

local wiring = {
    GetViewersForKey = function(_, key) return { viewers[key] } end,
    BuildFrameMapForViewers = function() return { [100] = shared }, { shared } end,
    MatchCuratedToFrames = function(_, curated)
        local entry = curated[1]
        if not entry then return {}, {}, {} end
        return { { entry = entry, frame = shared } }, {}, { [shared] = true }
    end,
}

local runtime = R.New({
    bridge = {
        InstallAnchorGuard = function() end,
        OverlayRect = function(_, frame, container)
            overlayRects[#overlayRects + 1] = { frame = frame, container = container }
        end,
        Sink = function(_, frame) sinks[#sinks + 1] = frame end,
    },
    wiring = wiring,
    placementPlanner = ns.CDMPlacementPlanner,
    getContainer = function(key) return containers[key] end,
    getSettings = function(key) return { enabled = enabled[key] } end,
    getCurated = function(key) return { entries[key] } end,
    getAdditional = function() return {} end,
    mintOwned = function(entry)
        nextOwned = nextOwned + 1
        return { id = "owned-" .. nextOwned, entry = entry }
    end,
    releaseOwned = function() return true end,
    positionOwned = function(icon, container)
        positionedOwned[#positionedOwned + 1] = { icon = icon, container = container }
    end,
    positionClickSlot = function() return {} end,
    updateClickOverlay = function() end,
    buildLayout = function(_, icons)
        local placements = {}
        for i = 1, #icons do
            placements[i] = { icon = icons[i], x = i, y = -i, w = 20, h = 20 }
        end
        return { placements = placements, metrics = {} }
    end,
})

local counts = runtime:RefreshContainers({ "utility", "essential" })
assert(counts.essential == 1 and counts.utility == 1,
    "both logical placements survive a shared native source")
assert(#overlayRects == 1 and overlayRects[1].frame == shared
    and overlayRects[1].container == containers.essential,
    "the deterministic essential owner is the only native anchor")
assert(#positionedOwned == 1 and positionedOwned[1].container == containers.utility,
    "the utility duplicate renders through an owned mirror")
assert(runtime:GetEntryForFrame(shared) == entries.essential,
    "compatibility frame lookup resolves the native owner")
local consumers = runtime:GetPlacementsForFrame(shared)
assert(type(consumers) == "table" and #consumers == 2,
    "the source frame retains both logical consumers")
assert(#sinks == 0, "a globally-owned shared frame is never sunk by its mirror container")

-- Removing/disabling the preferred owner transfers native ownership cleanly.
enabled.essential = false
overlayRects, positionedOwned, sinks = {}, {}, {}
counts = runtime:RefreshContainers({ "essential", "utility" })
assert(counts.essential == 0 and counts.utility == 1,
    "disabled placements leave the plan without being deleted from the profile")
assert(#overlayRects == 1 and overlayRects[1].container == containers.utility,
    "native ownership transfers to the remaining enabled placement")
assert(#positionedOwned == 0, "the transferred owner no longer needs a mirror")
assert(runtime:GetEntryForFrame(shared) == entries.utility,
    "the owner registry transfers atomically with the visual")

-- Item/equipment duplicates keep one exact native owner and omit the extra
-- placement with an explicit diagnostic instead of inventing a swipe.
enabled.essential = true
entries.essential.type, entries.essential.id = "slot", 13
entries.utility.type, entries.utility.id = "slot", 13
overlayRects, positionedOwned, sinks = {}, {}, {}
counts = runtime:RefreshContainers({ "utility", "essential" })
assert(counts.essential == 1 and counts.utility == 0,
    "native-only item duplicate keeps exactly one visual")
assert(#positionedOwned == 0, "item duplicate never enters the owned spell renderer")
assert(runtime:GetLastDiag("utility").unsupportedMirror == 1,
    "unsupported item mirror is observable in runtime diagnostics")

-- The legacy matcher reserves a frame for the first occurrence in one
-- container and reports the second as frameless. Batch collection must recover
-- that Blizzard-backed duplicate so it reaches arbitration and becomes a mirror.
do
    local sameFrame = {}
    local first = { type = "spell", id = 200, source = "blizzardCDM", _assignedRow = 1 }
    local second = { type = "spell", id = 200, source = "blizzardCDM", _assignedRow = 1 }
    local sameContainer = {}
    local samePositioned = {}
    local sameRuntime = R.New({
        bridge = {
            InstallAnchorGuard = function() end,
            OverlayRect = function() end,
            Sink = function() end,
        },
        wiring = {
            GetViewersForKey = function() return { {} } end,
            BuildFrameMapForViewers = function() return { [200] = sameFrame }, { sameFrame } end,
            MatchCuratedToFrames = function(_, curated)
                return { { entry = curated[1], frame = sameFrame } },
                    { curated[2] }, { [sameFrame] = true }
            end,
            ResolveEntryCooldownID = function(_, entry) return entry.id end,
        },
        placementPlanner = ns.CDMPlacementPlanner,
        getContainer = function() return sameContainer end,
        getSettings = function() return { enabled = true } end,
        getCurated = function() return { first, second } end,
        getAdditional = function() return {} end,
        mintOwned = function(entry) return { entry = entry } end,
        releaseOwned = function() return true end,
        positionOwned = function(icon) samePositioned[#samePositioned + 1] = icon end,
        positionClickSlot = function() return {} end,
        updateClickOverlay = function() end,
        buildLayout = function(_, icons)
            local placements = {}
            for i = 1, #icons do
                placements[i] = { icon = icons[i], x = i, y = 0, w = 20, h = 20 }
            end
            return { placements = placements, metrics = {} }
        end,
    })

    local sameCounts = sameRuntime:RefreshContainers({ "essential" })
    assert(sameCounts.essential == 2,
        "two occurrences in one container survive the legacy first-wins matcher")
    assert(#samePositioned == 1,
        "the second same-container occurrence renders as exactly one owned mirror")
    assert(#sameRuntime:GetPlacementsForFrame(sameFrame) == 2,
        "same-container duplicates remain distinct logical consumers")
end

print("OK: cdm_reanchor_runtime_batch_placement_test")
