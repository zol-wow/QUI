-- tests/unit/layoutmode_screen_anchor_handle_sync_test.lua
-- Run: lua tests/unit/layoutmode_screen_anchor_handle_sync_test.lua
--
-- Regression guard: Layout Mode X/Y sliders must move screen-anchored movers
-- whose DB entry uses a non-CENTER anchor pair (e.g. the minimap's shipped
-- TOPRIGHT/TOPRIGHT default). Three pieces cooperate:
--
-- 1. SyncHandle must compute the handle position from UIParent edges + DB
--    offsets for parent="screen" entries instead of reading the live frame's
--    center — that read is circular for proxy movers (the frame is glued to
--    the handle via SetAllPoints during layout mode), so the handle never
--    moved when the drawer sliders wrote new offsets.
-- 2. The minimap anchor-proxy mirror hooks must not reposition the Minimap
--    while it is parented away from UIParent (layout-mode handle ownership);
--    mirroring would rip the SetAllPoints glue so handle drags stop carrying
--    the Minimap.
-- 3. The minimap SetParent HUD-detection hook must ignore layout mode's own
--    reparent into the handle — latching externalHudActive there hid all
--    decorations and disabled the mirror for the whole layout-mode session.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return d:gsub("\r\n", "\n")
end

-- 1. SyncHandle screen-anchor math branch.
local layoutmode = readAll("modules/layout/layoutmode.lua")

local syncPos = assert(layoutmode:find("SyncHandle = function(key)", 1, true),
    "SyncHandle must exist")
local syncBlock = layoutmode:sub(syncPos)

-- Shared anchor-rect helper: prefers the parent's mover handle, falls back
-- to the parent FRAME's rect (scale-corrected), and maps screen/disabled to
-- UIParent edges.
local helperPos = assert(layoutmode:find("local function GetAnchorRectInUIParent(anchorKey)", 1, true),
    "shared anchor-rect helper must exist")
local helper = layoutmode:sub(helperPos, helperPos + 2000)
assert(helper:find('anchorKey == "screen" or anchorKey == "disabled"', 1, true),
    "helper must map sentinel parents to UIParent edges")
assert(helper:find("QUI_LayoutMode._handles[anchorKey]", 1, true),
    "helper must prefer the parent's mover handle rect")
assert(helper:find("_G.QUI_ResolveAnchorTargetFrame", 1, true),
    "helper must fall back to the anchor parent FRAME's rect when it has no mover handle")
assert(helper:find("GetEffectiveScale", 1, true),
    "helper's frame-rect fallback must scale-correct to UIParent units")

-- SyncHandle must use the helper for non-CENTER entries instead of the
-- circular frame:GetCenter() read.
local rectPos = assert(syncBlock:find('GetAnchorRectInUIParent(anchorParent or "screen")', 1, true),
    "SyncHandle must resolve the anchor rect for non-CENTER entries")
local branch = syncBlock:sub(rectPos, rectPos + 2500)
assert(branch:find("elseif relPt and rL and rR and rT and rB then", 1, true),
    "SyncHandle must position the handle from the resolved anchor rect + DB offsets")
assert(branch:find('relPt:find("LEFT")', 1, true)
    and branch:find('relPt:find("TOP")', 1, true),
    "rect branch must resolve the target edge from the entry's relative point")
assert(branch:find('pt:find("LEFT")', 1, true)
    and branch:find('pt:find("TOP")', 1, true),
    "rect branch must offset by the handle's own anchor point")

-- Drag-save (SavePendingPosition) must use the same helper so offsets
-- written for handle-less anchor parents aren't screen-center garbage.
local savePos = assert(layoutmode:find("local function SavePendingPosition(key", 1, true),
    "SavePendingPosition must exist")
local saveBlock = layoutmode:sub(savePos, layoutmode:find("function QUI_LayoutMode:RecordFreeElementPosition", savePos, true))
assert(select(2, saveBlock:gsub("GetAnchorRectInUIParent%(", "")) >= 2,
    "SavePendingPosition must resolve both the anchorTarget and existing-parent rects via the shared helper")

-- The parent-frame rect resolver global must exist in anchoring.lua.
local anchoring = readAll("modules/layout/anchoring.lua")
assert(anchoring:find("_G.QUI_ResolveAnchorTargetFrame = function(key)", 1, true),
    "anchoring must expose QUI_ResolveAnchorTargetFrame for layout-mode handle math")

-- Drag-path live cascade: SavePendingPosition must re-apply the full
-- anchored-descendant chain (and the proxy for indirect keys) so chained
-- frames follow a drag immediately, not only on layout-mode save.
local cascadePos = assert(layoutmode:find("local function ReapplyAnchoredDescendants(rootKey)", 1, true),
    "descendant cascade helper must exist")
local cascade = layoutmode:sub(cascadePos, cascadePos + 1500)
assert(cascade:find("childSettings.parent == parentKey", 1, true)
    and cascade:find("visited", 1, true),
    "cascade must walk the anchor graph breadth-first with a cycle guard")
assert(saveBlock:find("ReapplyAnchoredDescendants(key)", 1, true),
    "SavePendingPosition must cascade to anchored descendants")
assert(saveBlock:find("resolved ~= elFrame", 1, true),
    "SavePendingPosition must reposition the anchor proxy for indirect keys (minimap)")

-- Re-glue: after positioning a proxy-mover handle, SyncHandle must re-pin
-- the real frame inside it — ForceReapply/ApplyFrameAnchor rips the
-- SetAllPoints glue, which would leave the frame behind on the next drag.
assert(syncBlock:find("targetFrame:GetParent() == handle", 1, true)
    and syncBlock:find("pcall(targetFrame.SetAllPoints, targetFrame, handle)", 1, true),
    "SyncHandle must re-glue the frame to its handle after repositioning")

-- The circular frame:GetCenter() fallback must come AFTER (not instead of)
-- the anchor-rect branch.
local fallbackPos = assert(syncBlock:find("local frame = def.getFrame and def.getFrame()", rectPos, true),
    "frame-center fallback must remain for entries whose anchor rect can't be resolved")
assert(fallbackPos > rectPos, "anchor-rect branch must take priority over the frame-center fallback")

-- 2 + 3. Minimap mirror-ownership and HUD-latch guards.
local minimap = readAll("QUI_Minimap/minimap/minimap.lua")

local ownsPos = assert(minimap:find("local function MirrorOwnsMinimap()", 1, true),
    "anchor-proxy mirror must gate on Minimap geometry ownership")
local ownsBlock = minimap:sub(ownsPos, ownsPos + 400)
assert(ownsBlock:find("externalHudActive", 1, true),
    "mirror ownership gate must keep the external-HUD skip")
assert(ownsBlock:find("parent == UIParent", 1, true),
    "mirror must only fire while Minimap is parented to UIParent")
assert(minimap:find('hooksecurefunc(minimapAnchor, "SetPoint", function', 1, true)
    and minimap:find("if not MirrorOwnsMinimap() then return end", 1, true),
    "mirror hooks must consult MirrorOwnsMinimap")

local hudHookPos = assert(minimap:find('hooksecurefunc(Minimap, "SetParent", function()', 1, true),
    "SetParent HUD hook must exist")
local hudHookBlock = minimap:sub(hudHookPos, hudHookPos + 900)
assert(hudHookBlock:find("ns.QUI_LayoutMode", 1, true)
    and hudHookBlock:find("um.isActive", 1, true),
    "SetParent HUD hook must ignore layout mode's own reparent into the mover handle")

print("OK: layoutmode_screen_anchor_handle_sync_test")
