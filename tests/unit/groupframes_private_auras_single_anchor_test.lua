-- tests/unit/groupframes_private_auras_single_anchor_test.lua
-- Run: lua tests/unit/groupframes_private_auras_single_anchor_test.lua
--
-- Guards two group-frame private-aura fixes:
--
--   Bug 1 (doubled stacks / duration): the old dual-anchor system registered a
--     SECOND AddPrivateAuraAnchor (a scaled "text" anchor) for the same
--     auraIndex whenever textScale ~= 1 (the group-frame default was 2). Per
--     Blizzard_PrivateAurasUI.lua PrivateAuraMixin:Update, every single anchor
--     ALWAYS draws its own Count (stacks) and Duration fontstrings -- neither is
--     suppressible (showCountdownNumbers only hides the cooldown SPIRAL's
--     numbers). So two anchors drew the stacks/timer twice. The fix collapses to
--     a single anchor; textScale/textOffset are retired.
--
--   Bug 2 (icon behind healthbar): the Blizzard-rendered PrivateAuraTemplate has
--     no useParentLevel and is created at SetFrameLevel(0), so the container's
--     +50 frame level is a no-op for the icon -- within a shared strata it sits
--     beneath the healthbar. Only a strata bump fixes it. The icon container must
--     lock a DIALOG strata via SetFixedFrameStrata(true), matching the strata the
--     old text anchor already used (which is why the text floated but the icon
--     sank).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local src = readFile("modules/groupframes/groupframes_private_auras.lua")

---------------------------------------------------------------------------
-- Bug 1: exactly ONE anchor per slot; textScale machinery fully removed.
---------------------------------------------------------------------------
local _, pcallCount = src:gsub("pcall%(AddPrivateAuraAnchor", "")
assert(pcallCount == 1,
    "exactly ONE AddPrivateAuraAnchor registration must remain (the dual-anchor "
    .. "system used 2: main + text); got " .. pcallCount)

assert(not src:find("textScale", 1, true),
    "textScale must be fully removed -- the independent text-scale feature is retired")
assert(not src:find("scaleFrame", 1, true),
    "scaleFrame (the text-anchor parent) must be removed")
assert(not src:find("textAnchorIDs", 1, true),
    "textAnchorIDs state must be removed along with the text anchor")

---------------------------------------------------------------------------
-- Bug 2: the icon container locks a DIALOG strata so it clears the healthbar.
---------------------------------------------------------------------------
assert(src:find('SetFrameStrata("DIALOG")', 1, true),
    "private-aura icon container must set DIALOG strata so the rendered icon "
    .. "(frame level 0, no useParentLevel) clears the healthbar")
assert(src:find("SetFixedFrameStrata(true)", 1, true),
    "container strata must be locked with SetFixedFrameStrata(true) so pool "
    .. "reparent / roster churn cannot drop the icon back behind the healthbar")

---------------------------------------------------------------------------
-- Bug 1 behavioural: execute RegisterAnchor with stubs and prove a single slot
-- produces exactly one anchor registration.
---------------------------------------------------------------------------
local fnSrc = assert(src:match("local function RegisterAnchor.-\nend"),
    "RegisterAnchor must exist (single-anchor replacement for RegisterDualAnchor)")

local anchorCalls = {}
local env = {
    pcall = pcall,
    IS_CONTAINER_SUPPORTED = true,
    AddPrivateAuraAnchor = function(args)
        anchorCalls[#anchorCalls + 1] = args
        return 100 + #anchorCalls -- fake anchor id
    end,
}
local chunk = assert(loadstring(fnSrc .. "\nreturn RegisterAnchor", "RegisterAnchor"))
setfenv(chunk, env)
local RegisterAnchor = assert(chunk(), "extracted chunk must return RegisterAnchor")

local container = { tag = "container" }
local settings = { iconSize = 20, borderScale = 1, showCountdown = true, showCountdownNumbers = true }
local id = RegisterAnchor("raid3", 2, container, settings)

assert(#anchorCalls == 1,
    "RegisterAnchor must register EXACTLY ONE anchor per slot; got " .. #anchorCalls)
assert(id == 101, "RegisterAnchor must return the AddPrivateAuraAnchor id")

local a = anchorCalls[1]
assert(a.unitToken == "raid3", "anchor must use the unit token")
assert(a.auraIndex == 2, "anchor must use the slot index")
assert(a.parent == container, "anchor must parent into the icon container")
assert(a.iconInfo and a.iconInfo.iconWidth == 20, "icon must render at the configured iconSize")
assert(a.isContainer == false, "12.0.5+ non-container anchor must pass isContainer=false")
assert(a.showCountdownNumbers == true,
    "showCountdownNumbers must follow the setting directly (no textScale gating)")

-- A disabled countdown-numbers setting must propagate straight through.
anchorCalls = {}
env.AddPrivateAuraAnchor = function(args)
    anchorCalls[#anchorCalls + 1] = args
    return 200
end
RegisterAnchor("party1", 1, { tag = "c2" },
    { iconSize = 24, showCountdown = true, showCountdownNumbers = false })
assert(#anchorCalls == 1, "still exactly one anchor with numbers disabled")
assert(anchorCalls[1].showCountdownNumbers == false,
    "showCountdownNumbers=false must pass through to the single anchor")

print("OK: groupframes_private_auras_single_anchor_test")
