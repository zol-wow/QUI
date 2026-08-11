-- tests/unit/cdm_reanchor_runtime_directanchor_position_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_directanchor_position_test.lua
-- Big-bang native model: PositionEntries direct-anchors native live frames to the
-- container CENTER at slot corners (OverlayRect), decorates against an entry
-- stand-in carrying _spellEntry, and installs secure click overlays on separate
-- QUI-owned slots for Essential/Utility only.
-- trackedBar is rendered by owned CDMBars frames, not live direct anchoring.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local guards, overlayRects, overlays, decorated, shells, clickSlots, clickOverlays = {}, {}, {}, {}, {}, {}, {}
local liveTooltips = {}
local bridge = {
    InstallAnchorGuard = function(_, f) guards[#guards + 1] = f end,
    OverlayRect = function(_, f, rel, tlP, tlX, tlY, brP, brX, brY)
        overlayRects[#overlayRects + 1] = { f = f, rel = rel, tlP = tlP, tlX = tlX, tlY = tlY,
            brP = brP, brX = brX, brY = brY }
    end,
    Overlay = function(_, f, anchor) overlays[#overlays + 1] = { f = f, anchor = anchor } end,
}
local container = {}
local blizzFrame = { b = 1 }
local entrySrc = { spellID = 123 }
-- direct-anchor wrapper: frame == liveFrame == the live Blizzard frame.
local wDirect = { src = entrySrc, frame = blizzFrame, liveFrame = blizzFrame,
    reanchored = true, directAnchor = true }
local rc = { size = 40 }
local plan = { placements = { { icon = wDirect, x = 5, y = -5, w = 30, h = 20, rowConfig = rc } } }

local runtime = R.New({
    bridge = bridge,
    pixelRound = function(v) return v end, -- identity so the corner math is exact
    positionShell = function(...) shells[#shells + 1] = { ... } end,
    decorate = function(live, shell, rowConfig, key)
        decorated[#decorated + 1] = { live = live, shell = shell, rowConfig = rowConfig, key = key }
    end,
    positionClickSlot = function(containerArg, live, src, key, x, y, w, h, rowConfig)
        local slot = { slot = key }
        clickSlots[#clickSlots + 1] = {
            container = containerArg, live = live, src = src, key = key,
            x = x, y = y, w = w, h = h, rowConfig = rowConfig, slot = slot,
        }
        return slot
    end,
    updateClickOverlay = function(...) clickOverlays[#clickOverlays + 1] = { ... } end,
    ensureLiveTooltip = function(live, src) liveTooltips[#liveTooltips + 1] = { live = live, src = src } end,
})

local n = runtime:PositionEntries(container, plan, "buff")
assert(n == 1, "one direct-anchor wrapper positioned")

-- no per-slot shell positioned; the live frame is guarded + two-point RECT-overlaid.
assert(#shells == 0, "direct-anchor path never calls positionShell")
assert(#guards == 1 and guards[1] == blizzFrame, "guard installed on the live frame")
assert(#overlays == 0, "direct-anchor uses OverlayRect, not the shell Overlay")
assert(#overlayRects == 1, "one OverlayRect call")
local o = overlayRects[1]
-- corners: CENTER-relative, tlX=x-w/2, tlY=y+h/2, brX=x+w/2, brY=y-h/2
assert(o.f == blizzFrame and o.rel == container, "live frame pinned to the container")
assert(o.tlP == "CENTER" and o.brP == "CENTER", "both corners relative to container CENTER")
assert(o.tlX == 5 - 15 and o.tlY == -5 + 10, "TL corner = (x-w/2, y+h/2)")   -- -10, 5
assert(o.brX == 5 + 15 and o.brY == -5 - 10, "BR corner = (x+w/2, y-h/2)")   -- 20, -15

-- decorate: stand-in shell carrying the curated entry, correct key; NO click overlay.
assert(#decorated == 1 and decorated[1].live == blizzFrame, "decorate called for the live frame")
assert(decorated[1].shell ~= nil and decorated[1].shell._spellEntry == entrySrc,
    "decorate stand-in carries _spellEntry = wrapper.src")
assert(decorated[1].rowConfig == rc and decorated[1].key == "buff", "rowConfig + containerKey forwarded")
assert(#clickOverlays == 0, "direct-anchor buff has NO secure click overlay")
assert(#clickSlots == 0, "direct-anchor buff has NO click slot")

-- Task B3: direct-anchor restores the tooltip via an own-child overlay on the LIVE frame.
assert(#liveTooltips == 1 and liveTooltips[1].live == blizzFrame and liveTooltips[1].src == entrySrc,
    "direct-anchor calls ensureLiveTooltip(live, wrapper.src)")

-- trackedBar owned bars are not direct-anchor wrappers, so PositionEntries should
-- not touch the live Blizzard frame when handed a normal owned wrapper.
do
    local g2, or2, cl2, ownedPositions = {}, {}, {}, {}
    local ownedBar = { bar = 1 }
    local wOwnedBar = { src = entrySrc, frame = ownedBar, reanchored = false }
    local br2 = {
        InstallAnchorGuard = function(_, f) g2[#g2 + 1] = f end,
        OverlayRect = function(_, f, rel) or2[#or2 + 1] = { f = f, rel = rel } end,
        Overlay = function() error("trackedBar must not use the shell Overlay") end,
    }
    local rt2 = R.New({
        bridge = br2, pixelRound = function(v) return v end,
        decorate = function() end,
        updateClickOverlay = function(...) cl2[#cl2 + 1] = { ... } end,
        positionOwned = function(frame) ownedPositions[#ownedPositions + 1] = frame end,
    })
    local n2 = rt2:PositionEntries(container, {
        placements = { { icon = wOwnedBar, x = 0, y = 0, w = 100, h = 20, rowConfig = rc } },
    }, "trackedBar")
    assert(n2 == 1 and #ownedPositions == 1 and ownedPositions[1] == ownedBar,
        "trackedBar owned wrapper is positioned by positionOwned")
    assert(#or2 == 0, "trackedBar owned wrapper does not OverlayRect a live frame")
    assert(#g2 == 0, "trackedBar owned wrapper does not guard the live frame")
    assert(#cl2 == 0, "trackedBar owned wrapper has NO secure click overlay")
end

-- Essential/Utility native path: direct-anchor live frame, then position a
-- separate click slot and wire the secure overlay to that slot.
for _, key in ipairs({ "essential", "utility" }) do
    local g3, ov3, orr3, dec3, sh3, slots3, cl3, tt3 = {}, {}, {}, {}, {}, {}, {}, {}
    local br3 = {
        InstallAnchorGuard = function(_, f) g3[#g3 + 1] = f end,
        Overlay = function(_, f, anchor) ov3[#ov3 + 1] = { f = f, anchor = anchor } end,
        OverlayRect = function(...) orr3[#orr3 + 1] = { ... } end,
    }
    local wNative = { src = entrySrc, frame = blizzFrame, liveFrame = blizzFrame,
        reanchored = true, directAnchor = true }
    local rt3 = R.New({
        bridge = br3, pixelRound = function(v) return v end,
        positionShell = function(...) sh3[#sh3 + 1] = { ... } end,
        decorate = function(live, shell) dec3[#dec3 + 1] = { live = live, shell = shell } end,
        positionClickSlot = function(containerArg, live, src, keyArg, x, y, w, h, rowConfig)
            local slot = { slot = keyArg }
            slots3[#slots3 + 1] = {
                container = containerArg, live = live, src = src, key = keyArg,
                x = x, y = y, w = w, h = h, rowConfig = rowConfig, slot = slot,
            }
            return slot
        end,
        updateClickOverlay = function(host, entry, keyArg)
            cl3[#cl3 + 1] = { host = host, entry = entry, key = keyArg }
        end,
        ensureLiveTooltip = function(live, src) tt3[#tt3 + 1] = { live = live, src = src } end,
    })
    local n3 = rt3:PositionEntries(container, {
        placements = { { icon = wNative, x = 1, y = -2, w = 30, h = 20, rowConfig = rc } },
    }, key)
    assert(n3 == 1, key .. " native wrapper positioned")
    assert(#sh3 == 0, key .. " never uses positionShell")
    assert(#ov3 == 0, key .. " never overlays onto a shell")
    assert(#orr3 == 1, key .. " direct-anchors with OverlayRect")
    assert(#dec3 == 1 and dec3[1].live == blizzFrame and dec3[1].shell._spellEntry == entrySrc,
        key .. " decorates the live frame against an entry stand-in")
    assert(#slots3 == 1 and slots3[1].slot, key .. " positions a separate click slot")
    assert(#cl3 == 1 and cl3[1].host == slots3[1].slot and cl3[1].entry == entrySrc,
        key .. " wires the secure click overlay to the click slot")
    assert(#tt3 == 1 and tt3[1].live == blizzFrame and tt3[1].src == entrySrc,
        key .. " installs live tooltip overlay")
end

print("OK: cdm_reanchor_runtime_directanchor_position_test")
