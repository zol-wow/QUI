-- tests/unit/cdm_reanchor_boot_livetooltip_dep_test.lua
-- Run: lua tests/unit/cdm_reanchor_boot_livetooltip_dep_test.lua
-- Task B6 (G9 Option B): BuildRuntime must forward env.ensureLiveTooltip into the runtime
-- deps. B3 exposed env.ensureLiveTooltip (own-child tooltip overlay on the LIVE frame); the
-- runtime's directAnchor branch calls deps.ensureLiveTooltip(live, src) GUARDED -- without
-- this dep it silently no-ops and buff/bar tooltips are absent in-game. This is the wire
-- that activates B3. This test proves BOTH the dep forward AND the end-to-end fire.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_boot.lua", "cdm_reanchor_boot.lua")("QUI", ns)
local B = assert(ns.CDMReanchorBoot)

local liveBuff = { id = "liveBuff" }
local entry = { name = "e", _assignedRow = 1 }
local container, viewer = { c = 1 }, { v = 1 }

-- Fake bridge: the buff direct-anchor path uses InstallAnchorGuard + OverlayRect (never the
-- shell Overlay). Isolates the test from the real bridge's geometry internals.
local fakeBridge = {
    InstallAnchorGuard = function() end,
    OverlayRect = function() end,
    Overlay = function() error("buff must direct-anchor (OverlayRect), never shell Overlay") end,
    Sink = function() end,
}
-- Fake wiring: match the curated entry to the live buff frame for the buff container.
local fakeWiring = {
    GetViewerForKey = function() return viewer end,
    BuildFrameMap = function() return { [1] = liveBuff }, { liveBuff } end,
    MatchCuratedToFrames = function()
        return { { entry = entry, frame = liveBuff } }, {}, { [liveBuff] = true }
    end,
}

local liveTooltipCalls = {}
local hideLiveTooltipCalls = {}
local capturedDeps
local env = {
    -- Shim the three module constructors so BuildRuntime assembles against our fakes but
    -- uses the REAL runtime (so the directAnchor branch genuinely runs + calls the dep).
    CDMReanchor = { New = function() return fakeBridge end },
    CDMReanchorWiring = { New = function() return fakeWiring end },
    CDMReanchorRuntime = {
        New = function(deps) capturedDeps = deps; return ns.CDMReanchorRuntime.New(deps) end,
    },
    uiParent = {},
    getContainer = function() return container end,
    getCurated = function() return { entry } end,
    getSettings = function() return {} end,          -- no iconDisplayMode -> "always"
    resolveAdditional = function() return {} end,
    pixelRound = function(v) return v end,
    decorate = function() end,
    -- buff uses the flat buff layout (BuildIconLayout returns nil for the flat schema).
    buildBuffLayout = function(_, icons)
        local p = {}
        for i = 1, #icons do
            p[i] = { icon = icons[i], x = i, y = -i, w = 30, h = 20, rowConfig = { size = 30 } }
        end
        return { placements = p, metrics = {} }
    end,
    -- B6: THE wire under test.
    ensureLiveTooltip = function(live, src) liveTooltipCalls[#liveTooltipCalls + 1] = { live = live, src = src } end,
    -- hideLiveTooltip dep forward under test.
    hideLiveTooltip = function(live) hideLiveTooltipCalls[#hideLiveTooltipCalls + 1] = live end,
    -- buff direct-anchor -> no shell must be minted/positioned.
    mintShell = function() error("buff must NOT mint a shell (direct-anchor)") end,
    positionShell = function() error("buff must NOT positionShell (direct-anchor)") end,
}

local facade = B.BuildRuntime(env)

-- B6 (dep wire): the boot dep table forwards env.ensureLiveTooltip to the runtime.
assert(capturedDeps and capturedDeps.ensureLiveTooltip == env.ensureLiveTooltip,
    "B6: BuildRuntime must forward ensureLiveTooltip into the runtime deps (activates B3)")

-- hideLiveTooltip dep wire: boot must also forward env.hideLiveTooltip to the runtime.
assert(capturedDeps and capturedDeps.hideLiveTooltip == env.hideLiveTooltip,
    "boot must forward hideLiveTooltip into the runtime deps (sink teardown)")

-- End-to-end: a buff refresh through the boot facade fires the direct-anchor tooltip.
local count = facade:RefreshBuiltin("buff")
assert(count == 1, "one direct-anchor buff entry assembled")
assert(#liveTooltipCalls == 1
    and liveTooltipCalls[1].live == liveBuff
    and liveTooltipCalls[1].src == entry,
    "B6: given the boot-assembled deps, the directAnchor tooltip fires ensureLiveTooltip(live, src)")

-- Sink-loop hideLiveTooltip: when the same container is refreshed with NO curated entries
-- the previously-enumerated live frame is unclaimed -> sunk -> hideLiveTooltip called.
env.getCurated = function() return {} end
fakeWiring.MatchCuratedToFrames = function()
    return {}, {}, {}
end
hideLiveTooltipCalls = {}
facade:RefreshBuiltin("buff")
assert(#hideLiveTooltipCalls == 1 and hideLiveTooltipCalls[1] == liveBuff,
    "sink loop calls hideLiveTooltip for the sunk direct-anchor frame")

print("OK: cdm_reanchor_boot_livetooltip_dep_test")
