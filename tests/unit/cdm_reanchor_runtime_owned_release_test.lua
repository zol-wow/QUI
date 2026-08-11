-- tests/unit/cdm_reanchor_runtime_owned_release_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_owned_release_test.lua
--
-- Ghost owned-icon release. AssembleEntries mints a BRAND-NEW owned icon per
-- frameless/additional entry on EVERY refresh pass (mintOwned -> Factory:
-- AcquireIcon) and nothing ever released the previous pass's icon: it stayed
-- Show()n at its stale slot with its old texture (ghost icons that never clear)
-- and leaked one frame per pass. Fix: the runtime keeps a per-container mint
-- ledger and releases the previous pass's owned icons (deps.releaseOwned ->
-- Factory:ReleaseIcon -> Hide + recycle) before assembling the next pass.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local events = {}          -- interleaved {"mint"|"release", icon} for order checks
local minted = {}
local mintN = 0
local containerAlive = true
local eAdd = { name = "custom-additional" }

local wiring = {
    GetViewersForKey = function() return { { v = 1 } } end,
    BuildFrameMapForViewers = function() return {}, {} end,
    MatchCuratedToFrames = function() return {}, {}, {} end,
}
local runtime = R.New({
    bridge = {},
    wiring = wiring,
    getContainer = function() return containerAlive and { c = 1 } or nil end,
    getSettings = function() return {} end,
    getCurated = function() return {} end,
    getAdditional = function() return { eAdd } end,
    mintOwned = function()
        mintN = mintN + 1
        local icon = { id = mintN }
        minted[#minted + 1] = icon
        events[#events + 1] = { "mint", icon }
        return icon
    end,
    releaseOwned = function(icon, containerKey)
        events[#events + 1] = { "release", icon, containerKey }
    end,
})

-- Pass 1: mints one owned icon, releases nothing (no previous pass).
runtime:RefreshContainer("essential")
assert(#minted == 1, "first pass mints one owned icon for the additional entry")
assert(#events == 1 and events[1][1] == "mint", "first pass has nothing to release")

-- Pass 2: must release pass 1's icon BEFORE minting pass 2's (ghost fix).
runtime:RefreshContainer("essential")
assert(#minted == 2, "second pass re-mints (factory recycle can hand back the same frame)")
assert(#events == 3, "second pass = one release + one mint")
assert(events[2][1] == "release" and events[2][2] == minted[1],
    "second pass releases the FIRST pass's owned icon")
assert(events[2][3] == "essential",
    "release hands the containerKey through (realenv pool membership removal)")
assert(events[3][1] == "mint", "release happens BEFORE the new mint")

-- Container disappears (early-return path): stale owned icons still released.
containerAlive = true
local lastIcon = minted[#minted]
containerAlive = false
runtime:RefreshContainer("essential")
assert(events[#events][1] == "release" and events[#events][2] == lastIcon,
    "container-gone early return releases the stale owned icons too")

-- Missing releaseOwned dep must not crash (ledger still swaps).
do
    local runtime2 = R.New({
        bridge = {},
        wiring = wiring,
        getContainer = function() return { c = 2 } end,
        getSettings = function() return {} end,
        getCurated = function() return {} end,
        getAdditional = function() return { eAdd } end,
        mintOwned = function() return { anon = true } end,
    })
    runtime2:RefreshContainer("essential")
    runtime2:RefreshContainer("essential")
end

-- Refresh-level diag: full pass records plan/positioned; early returns record
-- their reason so a cold-boot dump distinguishes "assemble never ran" from
-- "assemble ran and produced nothing".
do
    local rt = R.New({
        bridge = {},
        wiring = wiring,
        getContainer = function() return { c = 3 } end,
        getSettings = function() return {} end,
        getCurated = function() return {} end,
        getAdditional = function() return {} end,
    })
    rt:RefreshContainer("essential")
    local d = rt:GetLastDiag("essential")
    assert(type(d) == "table" and d.seq == 1, "refresh records diag with pass sequence")
    assert(d.planNil == true and d.positioned == 0, "diag: plan + positioned counts recorded")

    local rtNoViewer = R.New({
        bridge = {},
        wiring = {
            GetViewersForKey = function() return nil end,
            GetViewerForKey = function() return nil end,
            MatchCuratedToFrames = function() return {}, {}, {} end,
        },
        getContainer = function() return { c = 4 } end,
        getSettings = function() return {} end,
    })
    rtNoViewer:RefreshContainer("buff")
    assert(rtNoViewer:GetLastDiag("buff").earlyReturn == "no-viewers-or-container",
        "diag: viewer/container early return recorded")

    local rtNoSettings = R.New({
        bridge = {},
        wiring = wiring,
        getContainer = function() return { c = 5 } end,
        getSettings = function() return nil end,
    })
    rtNoSettings:RefreshContainer("essential")
    assert(rtNoSettings:GetLastDiag("essential").earlyReturn == "no-settings",
        "diag: settings early return recorded")
end

-- Transactional ledger: an icon whose release FAILS (releaseOwned -> false, e.g.
-- Factory:ReleaseIcon refused a protected icon in combat) stays tracked, so the
-- next pass retries it instead of stranding an untracked visible/clickable ghost.
do
    local refuse = true
    local kept = {}
    local rt = R.New({
        bridge = {},
        wiring = wiring,
        getContainer = function() return { c = 9 } end,
        getSettings = function() return {} end,
        getCurated = function() return {} end,
        getAdditional = function() return { eAdd } end,
        mintOwned = function() local ic = { ghost = true }; kept[#kept + 1] = ic; return ic end,
        releaseOwned = function() return not refuse end,  -- refuse=true -> false (refused release)
    })
    rt:RefreshContainer("essential")        -- pass 1 mints ledger icon A
    local iconA = kept[1]
    rt:RefreshContainer("essential")        -- pass 2: release A refused -> A kept, mints B
    local ledger = rt._mintedOwnedByKey["essential"]
    assert(ledger ~= nil, "refused release keeps a ledger (no ghost strand)")
    local keptA = false
    for i = 1, #ledger do if ledger[i] == iconA then keptA = true end end
    assert(keptA, "the REFUSED icon A is retained in the ledger for retry")
end

print("OK: cdm_reanchor_runtime_owned_release_test")
