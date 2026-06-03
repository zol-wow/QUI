-- tests/unit/actionbars_flyout_strata_and_autodir_test.lua
-- Run: lua tests/unit/actionbars_flyout_strata_and_autodir_test.lua
--
-- Guards two flyout fixes:
--   Bug 1 (strata): the owned flyout (QUI_SpellFlyout) is reparented onto the
--     clicked action button by the secure HandleFlyout snippet. A non-fixed
--     frame inherits its new parent's (low) strata on reparent, dropping the
--     flyout behind group/raid frames. The frame must lock its DIALOG strata
--     with SetFixedFrameStrata(true).
--   Bug 2 (auto direction): QUI's owned-flyout buttons have no `self.bar`, so
--     Blizzard's UpdateFlyout never runs its position-based auto-detect. Left on
--     AUTO the arrow defaults to "DOWN" while the container snippet defaults to
--     "UP" — they disagree. AUTO must resolve to a concrete, position-based
--     direction applied to BOTH the secure attribute and SetPopupDirection.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

---------------------------------------------------------------------------
-- Bug 1: owned flyout locks its DIALOG strata against the secure reparent.
---------------------------------------------------------------------------
local flyoutSrc = readFile("modules/actionbars/actionbars_flyout.lua")

local ensureStart = assert(flyoutSrc:find("EnsureOwnedFlyoutFrame = function", 1, true),
    "EnsureOwnedFlyoutFrame must exist")
local ensureEnd = assert(flyoutSrc:find("\n    return ownedFlyout\nend", ensureStart, true),
    "EnsureOwnedFlyoutFrame must end with `return ownedFlyout`")
local ensureBlock = flyoutSrc:sub(ensureStart, ensureEnd)

assert(ensureBlock:find('SetFrameStrata("DIALOG")', 1, true),
    "owned flyout must set DIALOG strata")
assert(ensureBlock:find("SetFixedFrameStrata(true)", 1, true),
    "owned flyout must lock its strata with SetFixedFrameStrata(true) so the "
    .. "secure SetParent(parent) reparent cannot drop it below group frames")

-- The lock must come from the same setup block (before the frame is returned),
-- i.e. it is applied once at creation, not left to the secure snippet.
local strataPos = ensureBlock:find('SetFrameStrata("DIALOG")', 1, true)
local fixedPos = ensureBlock:find("SetFixedFrameStrata(true)", 1, true)
assert(fixedPos > strataPos,
    "SetFixedFrameStrata(true) must follow SetFrameStrata so DIALOG is the locked value")

-- Background tint must live on the flyout frame's own BACKGROUND layer, not on a
-- sibling child frame (whose texture can render over the popup-button icons and
-- dim them). A parent's draw layers always render beneath its child frames.
assert(ensureBlock:find("ownedFlyout:CreateTexture(nil, \"BACKGROUND\")", 1, true),
    "flyout background tint must be a texture on the flyout frame itself")
assert(not ensureBlock:find("ownedFlyout.Background = CreateFrame", 1, true),
    "flyout background tint must NOT be a separate sibling child frame")

---------------------------------------------------------------------------
-- Bug 2: ApplyFlyoutDirection resolves AUTO to a concrete direction and keeps
-- the container attribute and the Blizzard arrow in sync.
---------------------------------------------------------------------------
local usabilitySrc = readFile("modules/actionbars/actionbars_usability.lua")

local applyStart = assert(usabilitySrc:find("ApplyFlyoutDirection = function", 1, true),
    "ApplyFlyoutDirection must exist")
local applyEnd = assert(usabilitySrc:find("ApplyAllFlyoutDirections = function", applyStart, true),
    "ApplyAllFlyoutDirections must follow ApplyFlyoutDirection")
local applyBlock = usabilitySrc:sub(applyStart, applyEnd)

-- AUTO must resolve to a concrete direction (never a bare nil passed through).
assert(applyBlock:find("dir or ComputeAutoFlyoutDirection(", 1, true),
    "AUTO must fall back to ComputeAutoFlyoutDirection instead of leaving nil")

-- The SAME resolved value must drive the container attribute and the arrow.
assert(applyBlock:find('SetAttribute("flyoutDirection", effectiveDir)', 1, true),
    "container attribute must use the resolved effectiveDir")
assert(applyBlock:find("SetPopupDirection(effectiveDir)", 1, true),
    "Blizzard arrow (SetPopupDirection) must use the same resolved effectiveDir")

-- Orientation drives the axis (vertical bar -> LEFT/RIGHT, horizontal -> UP/DOWN).
assert(applyBlock:find('GetOwnedLayout(barKey)) == "vertical"', 1, true),
    "AUTO axis must come from the bar orientation via GetOwnedLayout")

---------------------------------------------------------------------------
-- Bug 2 behavioural: execute ComputeAutoFlyoutDirection with stubs and verify
-- the position-based mapping + secret/absent-center fallbacks.
---------------------------------------------------------------------------
local fnSrc = assert(usabilitySrc:match("(ComputeAutoFlyoutDirection = function.-\nend)\n"),
    "could not extract ComputeAutoFlyoutDirection source")

local SCREEN_W, SCREEN_H = 1920, 1080

local function loadComputeFn(safeToNumber)
    local env = {
        GetScreenWidth = function() return SCREEN_W end,
        GetScreenHeight = function() return SCREEN_H end,
        Helpers = { SafeToNumber = safeToNumber },
    }
    local chunk = assert(loadstring(fnSrc, "ComputeAutoFlyoutDirection"))
    setfenv(chunk, env)
    chunk()
    return assert(env.ComputeAutoFlyoutDirection, "function did not assign into env")
end

-- Plain numeric center (non-secret): SafeToNumber passes numbers through.
local passThrough = function(v) if type(v) == "number" then return v end return nil end
local compute = loadComputeFn(passThrough)

local function fakeBtn(cx, cy)
    return { GetCenter = function() return cx, cy end }
end

-- Horizontal bars use the vertical position: below mid-screen opens UP.
assert(compute(fakeBtn(960, 200), false) == "UP",
    "horizontal bar on the lower half should open UP")
assert(compute(fakeBtn(960, 900), false) == "DOWN",
    "horizontal bar on the upper half should open DOWN")

-- Vertical bars use the horizontal position: right of mid-screen opens LEFT.
assert(compute(fakeBtn(1700, 540), true) == "LEFT",
    "vertical bar on the right half should open LEFT")
assert(compute(fakeBtn(200, 540), true) == "RIGHT",
    "vertical bar on the left half should open RIGHT")

-- GetCenter may return nothing (MayReturnNothing) -> safe axis-default fallback.
assert(compute(fakeBtn(nil, nil), false) == "UP", "missing center -> horizontal default UP")
assert(compute(fakeBtn(nil, nil), true) == "RIGHT", "missing center -> vertical default RIGHT")

-- Secret center (SafeToNumber returns nil for a secret value) -> same fallback,
-- and crucially never compares the secret coordinate in Lua.
local secretCompute = loadComputeFn(function() return nil end)
assert(secretCompute(fakeBtn(960, 200), false) == "UP", "secret center -> horizontal default UP")
assert(secretCompute(fakeBtn(960, 200), true) == "RIGHT", "secret center -> vertical default RIGHT")

print("OK: actionbars_flyout_strata_and_autodir_test")
