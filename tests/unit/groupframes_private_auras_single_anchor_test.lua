-- tests/unit/groupframes_private_auras_single_anchor_test.lua
-- Run: lua tests/unit/groupframes_private_auras_single_anchor_test.lua
--
-- Guards the group-frame private-aura design across three invariants:
--
--   Bug 1 (doubled stacks / duration): the old system registered a SECOND
--     AddPrivateAuraAnchor (a scaled "text" anchor) for the same auraIndex. Per
--     Blizzard_PrivateAurasUI.lua PrivateAuraMixin:Update, every single anchor
--     ALWAYS draws its own Count (stacks) and Duration fontstrings -- neither is
--     suppressible (showCountdownNumbers only hides the cooldown SPIRAL's
--     numbers). So two anchors drew the stacks/timer twice. There must remain
--     EXACTLY ONE anchor per slot, and the dual-anchor artifacts (scaleFrame /
--     textAnchorIDs) must stay gone.
--
--   Bug 2 (icon behind healthbar): the Blizzard-rendered PrivateAuraTemplate has
--     no useParentLevel and is created at SetFrameLevel(0), so the container's
--     +50 frame level is a no-op for the icon -- within a shared strata it sits
--     beneath the healthbar. Only a strata bump fixes it. The icon container must
--     lock a DIALOG strata via SetFixedFrameStrata(true).
--
--   Text scale (oversized duration/stack text): there is NO anchor-arg to size
--     the Count/Duration fontstrings -- they inherit fixed Blizzard font objects
--     (GameFontNormalSmall / NumberFontNormal), so on a small icon they look
--     huge. The ONLY lever is scaling the parent CONTAINER (the text is rendered
--     as its descendant), then dividing the icon dimension + border scale by the
--     same factor so the icon/border stay at their configured pixel size while
--     only the text shrinks. This is a SINGLE-anchor technique -- it must NOT
--     reintroduce a second anchor.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local src = readFile("QUI_GroupFrames/groupframes/groupframes_private_auras.lua")

---------------------------------------------------------------------------
-- Bug 1: exactly ONE anchor per slot; dual-anchor artifacts stay removed.
---------------------------------------------------------------------------
local _, pcallCount = src:gsub("pcall%(AddPrivateAuraAnchor", "")
assert(pcallCount == 1,
    "exactly ONE AddPrivateAuraAnchor registration must remain (the dual-anchor "
    .. "system used 2: main + text); got " .. pcallCount)

assert(not src:find("scaleFrame", 1, true),
    "scaleFrame (the old text-anchor parent) must stay removed")
assert(not src:find("textAnchorIDs", 1, true),
    "textAnchorIDs state must stay removed along with the second anchor")

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
-- Text scale: the setup path must scale the CONTAINER (so Blizzard's rendered
-- text shrinks) instead of adding a second anchor.
---------------------------------------------------------------------------
assert(src:find("textScale", 1, true),
    "textScale knob must exist (single-anchor container-scale technique)")
assert(src:find("SetScale(textScale)", 1, true),
    "the container must be scaled via SetScale(textScale) so the Blizzard-drawn "
    .. "Count/Duration text (a descendant of the container) inherits the scale")

---------------------------------------------------------------------------
-- Bug 1 + text scale behavioural: run RegisterAnchor with stubs and prove a
-- single slot produces exactly one anchor AND the icon/border are compensated
-- for the container scale.
---------------------------------------------------------------------------
local fnSrc = assert(src:match("local function RegisterAnchor.-\nend"),
    "RegisterAnchor must exist (single-anchor replacement for RegisterDualAnchor)")

local anchorCalls = {}
local env = {
    pcall = pcall,
    math = math,
    IS_CONTAINER_SUPPORTED = true,
    AddPrivateAuraAnchor = function(args)
        anchorCalls[#anchorCalls + 1] = args
        return 100 + #anchorCalls -- fake anchor id
    end,
}
local chunk = assert(loadstring(fnSrc .. "\nreturn RegisterAnchor", "RegisterAnchor"))
setfenv(chunk, env)
local RegisterAnchor = assert(chunk(), "extracted chunk must return RegisterAnchor")

-- Baseline: textScale absent => behaves exactly as before (no compensation).
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
assert(a.iconInfo and a.iconInfo.iconWidth == 20,
    "with textScale absent the icon must render at the configured iconSize")
assert(a.iconInfo.borderScale == 1, "borderScale unchanged when textScale absent")
assert(a.isContainer == false, "12.0.5+ non-container anchor must pass isContainer=false")
assert(a.showCountdownNumbers == true,
    "showCountdownNumbers must follow the setting directly")

-- textScale = 0.5: text shrinks to half on-screen. To keep the icon + border at
-- their configured pixel size despite the 0.5x container, the icon dimension and
-- border scale must be divided by textScale (iconWidth 20 -> 40, border 2 -> 4).
anchorCalls = {}
env.AddPrivateAuraAnchor = function(args)
    anchorCalls[#anchorCalls + 1] = args
    return 300
end
RegisterAnchor("raid5", 1, { tag = "c3" },
    { iconSize = 20, borderScale = 2, textScale = 0.5, showCountdown = true, showCountdownNumbers = true })
assert(#anchorCalls == 1, "still EXACTLY one anchor with textScale active (no second anchor)")
local s = anchorCalls[1]
assert(s.iconInfo.iconWidth == 40 and s.iconInfo.iconHeight == 40,
    "iconWidth/iconHeight must be iconSize/textScale (20/0.5=40) so the on-screen "
    .. "icon stays at the configured size when the container is scaled 0.5x; got "
    .. tostring(s.iconInfo.iconWidth))
assert(s.iconInfo.borderScale == 4,
    "borderScale must be divided by textScale (2/0.5=4) so the border stays the "
    .. "configured size; got " .. tostring(s.iconInfo.borderScale))

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
