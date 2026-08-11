-- tests/unit/cdm_reanchor_runtime_native_clickslot_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_native_clickslot_test.lua
-- Big-bang native model: Essential/Utility direct-anchor live Blizzard frames
-- and put secure click handling on a separate QUI-owned slot overlay.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local function runFor(containerKey)
    local liveFrame = { id = "live-" .. containerKey }
    local entry = { name = "entry-" .. containerKey, _assignedRow = 1 }
    local container, viewer = { c = containerKey }, { v = containerKey }
    local overlayRects, clickSlots, clickUpdates, tooltips = {}, {}, {}, {}
    local bridge = {
        InstallAnchorGuard = function(_, frame) frame.guarded = true end,
        OverlayRect = function(_, frame, relativeTo, tlRelPoint, tlX, tlY, brRelPoint, brX, brY)
            overlayRects[#overlayRects + 1] = {
                frame = frame, relativeTo = relativeTo,
                tlRelPoint = tlRelPoint, tlX = tlX, tlY = tlY,
                brRelPoint = brRelPoint, brX = brX, brY = brY,
            }
        end,
        Overlay = function()
            error(containerKey .. " must not use shell Overlay")
        end,
        Sink = function() end,
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
        getSettings = function() return {} end,
        getCurated = function() return { entry } end,
        getAdditional = function() return {} end,
        pixelRound = function(v) return v end,
        decorate = function() end,
        ensureLiveTooltip = function(frame, tooltipEntry)
            tooltips[#tooltips + 1] = { frame = frame, entry = tooltipEntry }
        end,
        buildBuffLayout = function(_, icons)
            local p = {}
            for i = 1, #icons do
                p[i] = {
                    icon = icons[i], x = 4, y = -6, w = 40, h = 30,
                    rowConfig = { size = 40 },
                }
            end
            return { placements = p, metrics = { iconWidth = 40, totalHeight = 30 } }
        end,
        mintShell = function()
            error(containerKey .. " must not mint a shell")
        end,
        positionShell = function()
            error(containerKey .. " must not position a shell")
        end,
        positionClickSlot = function(clickContainer, frame, slotEntry, key, x, y, w, h, rc)
            local slot = { slot = key, frame = frame }
            clickSlots[#clickSlots + 1] = {
                container = clickContainer, frame = frame, entry = slotEntry,
                key = key, x = x, y = y, w = w, h = h, rowConfig = rc, slot = slot,
            }
            return slot
        end,
        updateClickOverlay = function(host, clickEntry, key)
            clickUpdates[#clickUpdates + 1] = { host = host, entry = clickEntry, key = key }
        end,
    })
    local n = runtime:RefreshContainer(containerKey)
    return n, overlayRects, clickSlots, clickUpdates, tooltips
end

for _, key in ipairs({ "essential", "utility" }) do
    local n, overlays, slots, clicks, tooltips = runFor(key)
    assert(n == 1, key .. ": one native entry positioned")
    assert(#overlays == 1, key .. ": live frame direct-anchored to container")
    assert(#slots == 1, key .. ": separate click slot positioned")
    assert(#clicks == 1, key .. ": click overlay updated on the click slot")
    assert(clicks[1].host == slots[1].slot, key .. ": click overlay host is the slot, not the live frame")
    assert(clicks[1].entry == slots[1].entry, key .. ": click overlay keeps curated entry")
    assert(#tooltips == 1, key .. ": native live tooltip overlay still installed")
end

do
    local n, overlays, slots, clicks, tooltips = runFor("buff")
    assert(n == 1, "buff: one native entry positioned")
    assert(#overlays == 1, "buff: live frame direct-anchored to container")
    assert(#slots == 0, "buff: no secure click slot")
    assert(#clicks == 0, "buff: no click overlay update")
    assert(#tooltips == 1, "buff: native live tooltip overlay installed")
end

print("OK: cdm_reanchor_runtime_native_clickslot_test")
