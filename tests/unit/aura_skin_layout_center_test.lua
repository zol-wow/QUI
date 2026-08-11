-- tests/unit/aura_skin_layout_center_test.lua
-- CENTER grow (Task 5): the PTR4 flow layout (SetFlowLayoutAnchorPoint) only
-- accepts corner anchors internally, but CustomAuraContainer AUTO-SIZES to
-- content — so visual centering falls out of pinning the container's CENTER
-- to the host instead of teaching the engine a center flow. FlowFor keeps
-- deriving a corner for the engine (CENTER behaves as RIGHT internally, since
-- the engine still lays icons out left-to-right from a corner);
-- AuraSkin.LayoutAnchor returns "CENTER" for the consumer's own SetPoint pin.
--
-- LayoutAnchor/ResolveLayout/FlowFor are pure profile-table math (no
-- CreateFrame, no secure template), unlike Configure/Restyle/WireButton which
-- need the live secure CustomAuraContainer — so, unusually for this file,
-- they can be loaded and called headless here.
-- Run: lua tests/unit/aura_skin_layout_center_test.lua

local ns = {}
assert(loadfile("core/aura_theme.lua"))("QUI", ns)   -- populates ns.Addon.AuraTheme
assert(loadfile("core/aura_skin.lua"))("QUI", ns)    -- populates ns.Addon.AuraSkin
local AuraSkin = ns.Addon.AuraSkin
assert(AuraSkin, "core/aura_skin.lua must publish ns.Addon.AuraSkin")
assert(type(AuraSkin.LayoutAnchor) == "function", "must define AuraSkin.LayoutAnchor")

-- CENTER grow: engine flow gets a corner internally, but the consumer pin is
-- CENTER — pinning the auto-sized container's own center to the host centers
-- the whole row without teaching the engine a center flow.
local anchor = AuraSkin.LayoutAnchor({ grow = "CENTER" })
assert(anchor == "CENTER", "LayoutAnchor CENTER: got " .. tostring(anchor))

-- Regression pin: RIGHT (and the unset-grow default) still return their flow
-- corner — the CENTER branch must not touch the non-CENTER path.
local right = AuraSkin.LayoutAnchor({ grow = "RIGHT" })
assert(right == "TOPLEFT", "LayoutAnchor RIGHT: got " .. tostring(right))

local default = AuraSkin.LayoutAnchor({})
assert(default == "TOPLEFT", "LayoutAnchor default (no grow set): got " .. tostring(default))

-- The other three corner-grow directions are untouched by the CENTER branch.
local left = AuraSkin.LayoutAnchor({ grow = "LEFT" })
assert(left == "TOPRIGHT", "LayoutAnchor LEFT: got " .. tostring(left))

local up = AuraSkin.LayoutAnchor({ grow = "UP" })
assert(up == "BOTTOMLEFT", "LayoutAnchor UP: got " .. tostring(up))

local down = AuraSkin.LayoutAnchor({ grow = "DOWN" })
assert(down == "TOPLEFT", "LayoutAnchor DOWN: got " .. tostring(down))

-- wrap="UP" still flips a horizontal-row corner (CENTER is a horizontal row
-- internally, same as RIGHT, so it is NOT expected to flip with wrap — only
-- LayoutAnchor's own CENTER short-circuit governs its return).
local rightWrapUp = AuraSkin.LayoutAnchor({ grow = "RIGHT", wrap = "UP" })
assert(rightWrapUp == "BOTTOMLEFT", "LayoutAnchor RIGHT+wrapUP: got " .. tostring(rightWrapUp))

print("aura_skin_layout_center_test OK")
