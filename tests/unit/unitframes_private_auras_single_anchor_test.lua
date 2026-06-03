-- tests/unit/unitframes_private_auras_single_anchor_test.lua
-- Run: lua tests/unit/unitframes_private_auras_single_anchor_test.lua
--
-- Mirrors the group-frame fix for the player/target/focus private-aura module.
-- See groupframes_private_auras_single_anchor_test.lua for the full rationale:
--   Bug 1: every AddPrivateAuraAnchor draws its own (unsuppressible) Count and
--          Duration fontstrings, so the dual-anchor system double-rendered them.
--          Collapse to a single anchor; textScale/textOffset are retired.
--   Bug 2: the Blizzard-rendered frame is level 0 with no useParentLevel, so the
--          icon needs a locked DIALOG strata (not a frame-level bump) to clear
--          the healthbar.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local src = readFile("modules/unitframes/unitframe_private_auras.lua")

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
    "container strata must be locked with SetFixedFrameStrata(true)")

---------------------------------------------------------------------------
-- Bug 1 behavioural: execute RegisterAnchor with stubs -> one anchor per slot.
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
local id = RegisterAnchor("target", 1, container,
    { iconSize = 22, borderScale = 1, showCountdown = true, showCountdownNumbers = true })

assert(#anchorCalls == 1,
    "RegisterAnchor must register EXACTLY ONE anchor per slot; got " .. #anchorCalls)
assert(id == 101, "RegisterAnchor must return the AddPrivateAuraAnchor id")

local a = anchorCalls[1]
assert(a.unitToken == "target", "anchor must use the unit token")
assert(a.auraIndex == 1, "anchor must use the slot index")
assert(a.parent == container, "anchor must parent into the icon container")
assert(a.iconInfo and a.iconInfo.iconWidth == 22, "icon must render at the configured iconSize")
assert(a.isContainer == false, "12.0.5+ non-container anchor must pass isContainer=false")
assert(a.showCountdownNumbers == true,
    "showCountdownNumbers must follow the setting directly (no textScale gating)")

print("OK: unitframes_private_auras_single_anchor_test")
