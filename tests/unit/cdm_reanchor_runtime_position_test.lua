-- tests/unit/cdm_reanchor_runtime_position_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_position_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local guards, overlayRects, overlays, owned, decorated, shells, clickSlots, clickOverlays = {}, {}, {}, {}, {}, {}, {}, {}
local bridge = {
    InstallAnchorGuard = function(_, f) guards[#guards+1] = f end,
    OverlayRect = function(_, f, rel, tlP, tlX, tlY, brP, brX, brY)
        overlayRects[#overlayRects+1] = {
            f = f, rel = rel, tlP = tlP, tlX = tlX, tlY = tlY,
            brP = brP, brX = brX, brY = brY,
        }
    end,
    Overlay = function(_, f, anchor) overlays[#overlays+1] = { f = f, anchor = anchor } end,
}
local container = {}
local blizzFrame, ownedIcon = { b = 1 }, { o = 1 }
local rowCfg = { row = 2, size = 40 }     -- rowConfig forwarded to owned placement
local rowCfgR = { row = 1, size = 40 }    -- rowConfig forwarded to native decorate/click slot
-- matched wrapper: frame == liveFrame == the live Blizzard frame.
local entryReanchor = { spellID = 123, viewerType = "essential" }
local wReanchor = {
    src = entryReanchor, frame = blizzFrame, liveFrame = blizzFrame,
    reanchored = true, directAnchor = true,
}
local wOwned    = { frame = ownedIcon, reanchored = false }
local plan = {
    placements = {
        { icon = wReanchor, x = 5, y = -5, rowConfig = rowCfgR },
        { icon = wOwned,    x = 9, y = -9, rowConfig = rowCfg },
        { icon = { reanchored = false }, x = 0, y = 0 },  -- no frame -> skipped
    },
}

local runtime = R.New({
    bridge = bridge,
    pixelRound = function(v) return v + 100 end,   -- prove pixelRound is applied
    positionShell = function(shell, c, x, y, w, h, rowConfig)
        shells[#shells+1] = { shell = shell, c = c, x = x, y = y, w = w, h = h, rowConfig = rowConfig }
    end,
    positionOwned = function(icon, c, p, rp, x, y, rowConfig) owned[#owned+1] = { icon = icon, c = c, p = p, rp = rp, x = x, y = y, rowConfig = rowConfig } end,
    decorate = function(live, shell, rowConfig) decorated[#decorated+1] = { live = live, shell = shell, rowConfig = rowConfig } end,
    positionClickSlot = function(c, live, entry, key, x, y, w, h, rowConfig)
        local slot = { slot = key }
        clickSlots[#clickSlots+1] = {
            c = c, live = live, entry = entry, key = key,
            x = x, y = y, w = w, h = h, rowConfig = rowConfig, slot = slot,
        }
        return slot
    end,
    updateClickOverlay = function(host, entry, viewerType)
        clickOverlays[#clickOverlays+1] = { host = host, entry = entry, viewerType = viewerType }
    end,
    ensureLiveTooltip = function() end,
})

local n = runtime:PositionEntries(container, plan, "essential")
assert(n == 2, "two wrappers with frames positioned, frameless wrapper skipped")

-- re-anchored: the live frame is direct-anchored to the container at the slot
-- corners after pixel rounding.
assert(#shells == 0, "no shell positioned in the container")
assert(#guards == 1 and guards[1] == blizzFrame, "guard installed for the live Blizzard frame")
assert(#overlays == 0, "live frame is not overlaid onto a shell")
assert(#overlayRects == 1 and overlayRects[1].f == blizzFrame and overlayRects[1].rel == container,
    "live frame direct-anchored to the container")
assert(overlayRects[1].tlX == 105 - 20 and overlayRects[1].tlY == 95 + 20,
    "TL corner uses pixel-rounded center and rowConfig size")
assert(overlayRects[1].brX == 105 + 20 and overlayRects[1].brY == 95 - 20,
    "BR corner uses pixel-rounded center and rowConfig size")
assert(#decorated == 1 and decorated[1].live == blizzFrame
    and decorated[1].shell._spellEntry == entryReanchor and decorated[1].rowConfig == rowCfgR,
    "decorate called once for the live frame, with entry stand-in + rowConfig")
assert(#clickSlots == 1 and clickSlots[1].live == blizzFrame and clickSlots[1].entry == entryReanchor,
    "separate click slot positioned for native clickable entry")
assert(clickSlots[1].x == 105 and clickSlots[1].y == 95 and clickSlots[1].w == 40 and clickSlots[1].h == 40,
    "click slot uses same pixel-rounded center and derived size")
assert(#clickOverlays == 1 and clickOverlays[1].host == clickSlots[1].slot and clickOverlays[1].entry == entryReanchor
    and clickOverlays[1].viewerType == "essential",
    "click slot gets a secure click overlay for the matched entry")

-- owned: positioned via positionOwned, never guarded/overlaid/decorated
assert(#owned == 1 and owned[1].icon == ownedIcon and owned[1].c == container, "owned icon positioned via positionOwned")
assert(owned[1].p == "CENTER" and owned[1].rp == "CENTER" and owned[1].x == 109 and owned[1].y == 91, "owned coords pixel-rounded at CENTER")
assert(owned[1].rowConfig == rowCfg, "placement.rowConfig forwarded to positionOwned (for ConfigureIcon)")

assert(runtime:PositionEntries(container, nil) == 0, "nil plan -> 0")
print("OK: cdm_reanchor_runtime_position_test")
