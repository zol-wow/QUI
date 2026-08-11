-- tests/unit/cdm_reanchor_runtime_disabled_container_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_disabled_container_test.lua
--
-- A tracker with settings.enabled == false must claim NOTHING in the reanchor
-- pass. LayoutContainer already gates the QUI-container side on enabled==false;
-- without the mirror gate in RefreshContainer the disabled tracker still
-- assembled its curated entries and pinned live Blizzard frames alpha-1 onto
-- its hidden container (parked near screen center) — visible mid-screen icons
-- on every churn pass (Towelliee repro: utility disabled, its category spells
-- curated into essential; wings press flashed the utility set mid-screen).
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local container, viewer = { c = 1 }, { v = 1 }

-- 1) Disabled tracker: matcher must not run, no frame claimed, every
--    enumerated frame sunk (nobody else claims them).
do
    local fA, fB = { id = "a" }, { id = "b" }
    local sinks, overlayRects, matcherCalls = {}, {}, 0
    local bridge = {
        InstallAnchorGuard = function() end,
        Overlay = function() end,
        OverlayRect = function(_, f, rel) overlayRects[#overlayRects + 1] = { live = f, rel = rel } end,
        Sink = function(_, f) sinks[#sinks + 1] = f end,
    }
    local runtime = R.New({
        bridge = bridge,
        wiring = {
            GetViewerForKey = function() return viewer end,
            GetViewersForKey = function() return { viewer } end,
            BuildFrameMapForViewers = function() return { [1] = fA, [2] = fB }, { fA, fB } end,
            MatchCuratedToFrames = function()
                matcherCalls = matcherCalls + 1
                return { { entry = { name = "stolen" }, frame = fA } }, {}, { [fA] = true }
            end,
        },
        getContainer = function() return container end,
        getSettings = function() return { enabled = false } end,
        getCurated = function() return { { name = "stolen" } } end,
        getAdditional = function() return {} end,
    })

    assert(runtime:RefreshContainer("utility") == 0, "disabled tracker returns zero entries")
    assert(matcherCalls == 0, "disabled tracker must not assemble/match curated entries")
    assert(#overlayRects == 0, "disabled tracker must not claim any live frame")
    local sset = {}
    for _, f in ipairs(sinks) do sset[f] = true end
    assert(sset[fA] and sset[fB], "disabled tracker sinks every unclaimed enumerated frame")
end

-- 2) Disabled sibling must not sink a frame another container already claimed
--    (essential keeps the cross-category frame it claimed).
do
    local sharedFrame = { id = "shared" }
    local sinks = {}
    local bridge = {
        InstallAnchorGuard = function() end,
        Overlay = function() end,
        OverlayRect = function() end,
        Sink = function(_, f) sinks[#sinks + 1] = f end,
    }
    local runtime = R.New({
        bridge = bridge,
        wiring = {
            GetViewerForKey = function() return viewer end,
            GetViewersForKey = function() return { viewer } end,
            BuildFrameMapForViewers = function() return { [42] = sharedFrame }, { sharedFrame } end,
            MatchCuratedToFrames = function(_, curated, frameMap, key)
                if key == "essential" then
                    return { { entry = curated[1], frame = frameMap[42] } }, {}, { [frameMap[42]] = true }
                end
                return {}, {}, {}
            end,
        },
        getContainer = function() return container end,
        getSettings = function(key)
            if key == "utility" then return { enabled = false } end
            return { s = 1 }
        end,
        getCurated = function(key)
            if key == "essential" then return { { name = "shared", source = "blizzardCDM" } } end
            return {}
        end,
        getAdditional = function() return {} end,
        buildLayout = function(_, icons)
            local p = {}
            for i = 1, #icons do
                p[i] = { icon = icons[i], x = i, y = i, w = 30, h = 20, rowConfig = { size = 30 } }
            end
            return { placements = p, metrics = {} }
        end,
        positionShell = function() end,
        positionClickSlot = function() return {} end,
        updateClickOverlay = function() end,
        decorate = function() end,
        mintShell = function() error("matched native entries must not mint shells") end,
    })

    runtime:RefreshContainer("essential")
    runtime:RefreshContainer("utility")
    assert(#sinks == 0,
        "disabled sibling must not sink a frame claimed by another container")
end

-- 3) A frame the tracker claimed while enabled is released (sunk) on the next
--    pass after the tracker is disabled — no stale alpha-1 pin survives.
do
    local staleFrame = { id = "stale" }
    local sinks, enabled = {}, true
    local bridge = {
        InstallAnchorGuard = function() end,
        Overlay = function() end,
        OverlayRect = function() end,
        Sink = function(_, f) sinks[#sinks + 1] = f end,
    }
    local runtime = R.New({
        bridge = bridge,
        wiring = {
            GetViewerForKey = function() return viewer end,
            GetViewersForKey = function() return { viewer } end,
            BuildFrameMapForViewers = function() return { [7] = staleFrame }, { staleFrame } end,
            MatchCuratedToFrames = function(_, curated, frameMap)
                return { { entry = curated[1], frame = frameMap[7] } }, {}, { [frameMap[7]] = true }
            end,
        },
        getContainer = function() return container end,
        getSettings = function() return { enabled = enabled } end,
        getCurated = function() return { { name = "mine" } } end,
        getAdditional = function() return {} end,
        buildLayout = function(_, icons)
            local p = {}
            for i = 1, #icons do
                p[i] = { icon = icons[i], x = i, y = i, w = 30, h = 20, rowConfig = { size = 30 } }
            end
            return { placements = p, metrics = {} }
        end,
        positionShell = function() end,
        positionClickSlot = function() return {} end,
        updateClickOverlay = function() end,
        decorate = function() end,
        mintShell = function() error("matched native entries must not mint shells") end,
    })

    runtime:RefreshContainer("utility")
    assert(#sinks == 0, "enabled pass claims the frame, nothing sunk")
    enabled = false
    runtime:RefreshContainer("utility")
    assert(#sinks == 1 and sinks[1] == staleFrame,
        "disabling the tracker releases its previously claimed frame on the next pass")
end

print("OK: cdm_reanchor_runtime_disabled_container_test")
