-- tests/unit/blizzard_mover_herotalent_proxy_parent_test.lua
-- Run: lua tests/unit/blizzard_mover_herotalent_proxy_parent_test.lua
--
-- PROTOTYPE guard (in-game verification pending): re-adds HeroTalentsSelectionDialog
-- as a mover panel that pins to the UIParent-mirroring secure anchor
-- (QUI_MoverSecureAnchor — QUI's FakeUIParent equivalent) instead of the real
-- UIParent. The dialog inherits DefaultPanelTemplate (NOT protected), so every
-- prior QUI attempt anchored it to the real UIParent via the insecure path and
-- tripped 12.0's anchor-family guard (PlaceHeroTalentButton:442) during the tree
-- rebuild. The reference mover only ever anchors moved frames to its proxy; the
-- proxyParent flag forces QUI's secure-anchor (proxy) path for this dialog so we
-- can test whether a distinct anchor node avoids the trip.

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

-- 1. The dialog is a mover panel again, opting into the proxy + deferred re-assert.
local dialog = assert(blockForId(frames, "HeroTalentsSelectionDialog"),
    "HeroTalentsSelectionDialog should be a mover panel again")
assert(dialog:find("proxyParent = true", 1, true),
    "dialog must pin via the secure-anchor proxy, not the real UIParent")
assert(dialog:find("deferReassert = true", 1, true),
    "dialog must defer the re-assert out of any synchronous rebuild pass")

-- 2. proxyParent is plumbed def -> panel.
assert(mover:find("proxyParent = def.proxyParent", 1, true),
    "panel table must carry proxyParent through from the def")

-- 3. Both position-apply paths route proxyParent through securePlace (proxy anchor):
--    applyFrameSettings (combined protected-or-proxy condition) and reassertLayout
--    (its own proxyParent branch).
assert(mover:find("or panel.proxyParent) and not panel.keepTwoPointSize", 1, true),
    "applyFrameSettings must route proxyParent through securePlace")
assert(mover:find("panel.proxyParent and not panel.keepTwoPointSize", 1, true),
    "reassertLayout must route proxyParent through securePlace")

-- 4. The combat-defer guard and applyFrameSettings condition include proxyParent.
assert(mover:find("or panel.proxyParent", 1, true),
    "combat guard / apply condition must include proxyParent")

-- 5. Clamping is skipped for proxyParent panels.
assert(mover:find("f.SetClampedToScreen and not panel.proxyParent", 1, true),
    "proxyParent panels must skip SetClampedToScreen")

-- 6. OnShow defers to the (proxy-routed) reassert instead of a synchronous
--    populate-time applyFrameSettings re-anchor.
assert(mover:find("if panel.proxyParent then", 1, true),
    "OnShow must special-case proxyParent")

print("OK: blizzard_mover_herotalent_proxy_parent_test")
