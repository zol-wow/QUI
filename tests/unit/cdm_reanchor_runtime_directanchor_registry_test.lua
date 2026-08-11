-- tests/unit/cdm_reanchor_runtime_directanchor_registry_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_directanchor_registry_test.lua
-- Big-bang native model: direct-anchored Essential/Utility/Buff live frames
-- must still be registered in the per-frame feature registry
-- (_entryByFrame / _reanchoredByKey).
-- This registry is LOAD-BEARING: proc-glow (cdm_reanchor_hooks GetEntryForFrame),
-- keybinds, and GetReanchoredFrames (cdm_containers) all read it to cover the
-- re-anchored Blizzard frames -- which stay under the viewer, not container:GetChildren().
-- The direct-anchor wrapper carries reanchored=true + liveFrame=the live frame, so the
-- RefreshContainer registration loop (keyed on w.reanchored and w.liveFrame) registers it
-- exactly like the shell path -- NO separate code path. This test LOCKS that.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

-- Drive a full RefreshContainer for a direct-anchor container key and return the runtime.
local function runFor(containerKey)
    local liveFrame = { id = "live-" .. containerKey }
    local entry = { name = "e", _assignedRow = 1 }
    local container, viewer = { c = 1 }, { v = 1 }
    local sinks = {}
    local bridge = {
        InstallAnchorGuard = function() end,
        OverlayRect = function() end,
        Overlay = function() error(containerKey .. " must direct-anchor (OverlayRect), never shell Overlay") end,
        Sink = function(_, f) sinks[#sinks + 1] = f end,
    }
    local wiring = {
        GetViewerForKey = function() return viewer end,
        BuildFrameMap = function() return { [1] = liveFrame }, { liveFrame } end,
        MatchCuratedToFrames = function()
            return { { entry = entry, frame = liveFrame } }, {}, { [liveFrame] = true }
        end,
    }
    local runtime = R.New({
        bridge = bridge, wiring = wiring,
        getContainer = function() return container end,
        getSettings = function() return {} end,          -- no iconDisplayMode -> "always"
        getCurated = function() return { entry } end,
        getAdditional = function() return {} end,
        pixelRound = function(v) return v end,
        decorate = function() end,
        ensureLiveTooltip = function() end,
        -- This test drives the flat layout fallback for every native surface.
        buildBuffLayout = function(_, icons)
            local p = {}
            for i = 1, #icons do
                p[i] = { icon = icons[i], x = i, y = -i, w = 30, h = 20, rowConfig = { size = 30 } }
            end
            return { placements = p, metrics = { iconWidth = 30, totalHeight = 20 } }
        end,
        positionClickSlot = function() return {} end,
        updateClickOverlay = function() end,
        -- mintShell MUST NOT be called for native matches (direct-anchor, no shell).
        mintShell = function() error(containerKey .. " must NOT mint a shell (direct-anchor)") end,
        positionShell = function() error(containerKey .. " must NOT positionShell (direct-anchor)") end,
    })
    local n = runtime:RefreshContainer(containerKey)
    return runtime, liveFrame, entry, n, sinks
end

for _, key in ipairs({ "buff", "essential", "utility" }) do
    local runtime, liveFrame, entry, n, sinks = runFor(key)

    assert(n == 1, key .. ": one direct-anchor entry assembled")

    -- CRITICAL: the direct-anchored live frame resolves to its curated entry.
    assert(runtime:GetEntryForFrame(liveFrame) == entry,
        key .. ": direct-anchored live frame MUST be registered in _entryByFrame (proc-glow/keybinds)")
    -- And it appears in the per-container re-anchored frame list.
    local reFrames = runtime:GetReanchoredFrames(key)
    assert(type(reFrames) == "table" and #reFrames == 1 and reFrames[1] == liveFrame,
        key .. ": direct-anchored live frame MUST be listed by GetReanchoredFrames")
    -- Claimed-by-any-container is true (so a sibling refresh won't sink it).
    assert(runtime:IsFrameClaimedByAnyContainer(liveFrame) == true,
        key .. ": direct-anchored live frame MUST report claimed")
    -- The claimed frame is NOT sunk (else proc-glow/keybinds see a parked frame).
    assert(#sinks == 0, key .. ": the claimed direct-anchored frame must not be sunk")

    -- Registry rebuilds (not accumulates) on a second pass.
    runtime:RefreshContainer(key)
    assert(#runtime:GetReanchoredFrames(key) == 1, key .. ": registry rebuilt, not accumulated")
    assert(runtime:GetEntryForFrame(liveFrame) == entry, key .. ": mapping stable across refresh")
end

do
    local runtime, liveFrame, _entry, n, sinks = runFor("trackedBar")
    assert(n == 0, "trackedBar: re-anchor runtime must not assemble live BuffBar frames")
    assert(runtime:GetEntryForFrame(liveFrame) == nil,
        "trackedBar: live BuffBar frame must not be registered as re-anchored")
    local reFrames = runtime:GetReanchoredFrames("trackedBar")
    assert(type(reFrames) == "table" and #reFrames == 0,
        "trackedBar: no live BuffBar frames are exposed through GetReanchoredFrames")
    assert(#sinks == 0,
        "trackedBar: accidental re-anchor refresh should not sink the matched Blizzard data source")
end

print("OK: cdm_reanchor_runtime_directanchor_registry_test")
