-- tests/unit/blizzard_mover_reassert_sync_default_test.lua
-- Run: lua tests/unit/blizzard_mover_reassert_sync_default_test.lua
--
-- Regression guard: the SetPoint-hook position re-assert must be SYNCHRONOUS
-- by default and only DEFERRED (one frame, coalesced) for panels that opt in
-- via deferReassert = true.
--
-- Why: UIParentPanelManager (SetUIPanel/MoveUIPanel) re-anchors managed panels
-- (CharacterFrame, FriendsFrame, ...) via SetPoint whenever a sibling panel
-- opens/closes. A synchronous re-assert snaps the moved frame back in the SAME
-- frame, so Blizzard's reflow position never renders. Deferring the re-assert
-- for ALL panels (the form the hero-talent fix originally shipped) lets the
-- frame render one frame at Blizzard's position, then snap back = a visible
-- flicker when opening a second panel next to a moved one.
--
-- Only PlayerSpellsFrame needs the deferred path: a synchronous re-anchor mid
-- hero-talent-tree rebuild trips 12.0's anchor-family guard. Everything else
-- must stay synchronous (matches the reference mover, which re-asserts SetPoint
-- synchronously by default).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function blockForId(source, id)
    local pattern = '{%s*id = "' .. id .. '".-defaultEnabled = true,%s*}'
    return source:match(pattern)
end

local mover = readFile("QUI_QoL/qol/blizzard_mover.lua")
local frames = readFile("QUI_QoL/qol/blizzard_mover_frames.lua")

-- 1. PlayerSpellsFrame opts into the deferred re-assert.
local playerSpells = assert(blockForId(frames, "PlayerSpellsFrame"),
    "PlayerSpellsFrame registry entry should exist")
assert(playerSpells:find("deferReassert = true", 1, true),
    "PlayerSpellsFrame must keep the deferred re-assert (anchor-family guard)")

-- 2. CharacterFrame (and the general case) must NOT opt in -> stays synchronous.
local character = assert(blockForId(frames, "CharacterFrame"),
    "CharacterFrame registry entry should exist")
assert(not character:find("deferReassert", 1, true),
    "CharacterFrame must use the synchronous re-assert (no flicker)")

-- 3. The flag is plumbed from def -> panel.
assert(mover:find("deferReassert = def.deferReassert", 1, true),
    "panel table must carry deferReassert through from the def")

-- 4. The SetPoint hook is SELECTED on deferReassert, not unconditionally deferred.
assert(not mover:find('hooksecurefunc(root, "SetPoint", reassertLayoutSoon)', 1, true),
    "SetPoint hook must not be unconditionally deferred for every panel")
assert(mover:find("panel.deferReassert", 1, true),
    "SetPoint hook must choose sync vs deferred based on panel.deferReassert")
-- The synchronous re-assert must still be wired as the default path.
assert(mover:find('hooksecurefunc(root, "SetPoint", reassertHook)', 1, true),
    "SetPoint hook should install the selected reassert handler")

print("OK: blizzard_mover_reassert_sync_default_test")
