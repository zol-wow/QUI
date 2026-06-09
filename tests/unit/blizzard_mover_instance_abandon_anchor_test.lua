-- tests/unit/blizzard_mover_instance_abandon_anchor_test.lua
-- Run: lua tests/unit/blizzard_mover_instance_abandon_anchor_test.lua
--
-- Regression guard: the M+ "vote to abandon instance" prompt is Blizzard's
-- reserved StaticPopup dialog InstanceAbandonPopup. FrameXML hard-anchors that
-- reserved frame BOTTOMRIGHT (InstanceAbandon.xml), and StaticPopup_SetUpPosition
-- deliberately leaves reserved/fixed dialogs at their XML anchor instead of
-- stacking them top-center like StaticPopup1..5. So out of the box it pops in the
-- bottom-right corner instead of with the other popups.
--
-- Fix: fold InstanceAbandonPopup into the existing "Static Popups" mover entry so
-- it shares that entry's saved offset (follows the popups when the user moves
-- them), and give the entry a declarative top-center defaultPoint so the DEFAULT
-- (no saved offset) lands where the static popups live, not bottom-right.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local mover = readFile("QUI_QoL/qol/blizzard_mover.lua")
local frames = readFile("QUI_QoL/qol/blizzard_mover_frames.lua")

-- Extract the Static Popups registry entry (id .. up to its defaultEnabled).
local staticPopup = assert(
    frames:match('{%s*id = "StaticPopup".-defaultEnabled = true,%s*}'),
    "StaticPopup registry entry should exist")

-- 1. The reserved abandon-vote dialog joins the Static Popups entry so it shares
--    the same saved offset (moves with the popups).
assert(staticPopup:find("InstanceAbandonPopup", 1, true),
    "InstanceAbandonPopup must be listed in the Static Popups entry names")
assert(staticPopup:find("StaticPopup1", 1, true),
    "Static Popups entry must still cover StaticPopup1..5")

-- 2. The entry declares a top-center default anchor (where static popups live),
--    so the DEFAULT case no longer inherits the BOTTOMRIGHT FrameXML anchor.
local dp = assert(staticPopup:match("defaultPoint = (%b{})"),
    "Static Popups entry must declare a defaultPoint")
assert(dp:find('"TOP"', 1, true), "defaultPoint must anchor TOP (top-center)")
assert(dp:find("%-135"), "defaultPoint must use the Blizzard top-stack offset (-135)")

-- 3. The flag is plumbed from def -> panel.
assert(mover:find("defaultPoint = def.defaultPoint", 1, true),
    "panel table must carry defaultPoint through from the def")

-- 4. The default anchor is SEEDED before rememberAnchors() captures the layout,
--    so the seeded home (not the BOTTOMRIGHT FrameXML default) becomes the
--    remembered/restore baseline; a saved offset still layers on via
--    applyFrameSettings.
local seedAt = assert(mover:find("panel.defaultPoint", 1, true),
    "createHooks must seed from panel.defaultPoint")
local rememberAt = assert(mover:find("rememberAnchors(root)", 1, true),
    "createHooks must remember Blizzard anchors")
assert(seedAt < rememberAt,
    "defaultPoint must be seeded BEFORE rememberAnchors(root) captures the baseline")

print("OK: blizzard_mover_instance_abandon_anchor_test")
