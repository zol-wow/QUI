-- Static source-level assertions for the AnchorOrPin / ParentRestricts additions
-- to modules/layout/anchoring.lua.
--
-- Convention: file-content checks only (readFile + :find/:gmatch).
-- No harness bootstrap required. Run from repo root:
--   lua tests/unit/anchoring_dynamic_size_uiparent_pin_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

local ANCHORING = "modules/layout/anchoring.lua"
local src = assert(readFile(ANCHORING), "cannot open " .. ANCHORING)

-- -------------------------------------------------------------------------
-- 1. File declares ParentRestricts and AnchorOrPin as local functions.
-- -------------------------------------------------------------------------
check("anchoring.lua defines local function ParentRestricts",
    src:find("local function ParentRestricts", 1, true) ~= nil)

check("anchoring.lua defines local function AnchorOrPin",
    src:find("local function AnchorOrPin", 1, true) ~= nil)

-- -------------------------------------------------------------------------
-- 2. AnchorOrPin gates on IsDynamicSizeAnchorKey AND ParentRestricts,
--    and calls ns.Helpers.PinFrameToTargetAbsolute on that branch.
-- -------------------------------------------------------------------------

-- Find the AnchorOrPin function body.
local anchorOrPinStart = src:find("local function AnchorOrPin", 1, true)
check("AnchorOrPin start found", anchorOrPinStart ~= nil)

if anchorOrPinStart then
    -- Extract a generous chunk of the function (up to ~50 lines)
    local funcBody = src:sub(anchorOrPinStart, anchorOrPinStart + 2600)

    check("AnchorOrPin gates on IsDynamicSizeAnchorKey(key)",
        funcBody:find("IsDynamicSizeAnchorKey(key)", 1, true) ~= nil)

    check("AnchorOrPin gates on ParentRestricts(parentFrame)",
        funcBody:find("ParentRestricts(parentFrame)", 1, true) ~= nil)

    check("AnchorOrPin calls ns.Helpers.PinFrameToTargetAbsolute on the pin branch",
        funcBody:find("ns.Helpers.PinFrameToTargetAbsolute", 1, true) ~= nil)

    -- -------------------------------------------------------------------------
    -- 3. AnchorOrPin falls back to SmoothSetPoint on the else branch.
    -- -------------------------------------------------------------------------
    check("AnchorOrPin calls SmoothSetPoint on the else/fallback branch",
        funcBody:find("SmoothSetPoint", 1, true) ~= nil)

    -- -------------------------------------------------------------------------
    -- 3b. AnchorOrPin must NOT pin a frame that is itself protected /
    --     anchoring-restricted (e.g. buffFrame/debuffFrame SecureAuraHeaders).
    --     Pinning such a frame is combat-blocked AND loses the native relative
    --     follow that tracks the parent's secure-side resize. Regression guard
    --     for: debuffFrame (anchored to buffFrame) frozen on in-combat resize.
    -- -------------------------------------------------------------------------
    check("AnchorOrPin gates the pin on `not FrameSelfRestricts(frame)`",
        funcBody:find("not FrameSelfRestricts(frame)", 1, true) ~= nil)

    local selfStart = src:find("local function FrameSelfRestricts", 1, true)
    check("anchoring.lua defines local function FrameSelfRestricts", selfStart ~= nil)
    if selfStart then
        local sfBody = src:sub(selfStart, selfStart + 600)
        check("FrameSelfRestricts checks the frame's own FrameIsProtected",
            sfBody:find("ns.Helpers.FrameIsProtected", 1, true) ~= nil)
        check("FrameSelfRestricts checks the frame's own FrameIsAnchoringRestricted",
            sfBody:find("ns.Helpers.FrameIsAnchoringRestricted", 1, true) ~= nil)
    end

    -- ParentRestricts guards UIParent short-circuit first, then delegates.
    local parentRestrictsStart = src:find("local function ParentRestricts", 1, true)
    if parentRestrictsStart then
        local prBody = src:sub(parentRestrictsStart, parentRestrictsStart + 900)
        check("ParentRestricts returns false for UIParent",
            prBody:find("UIParent", 1, true) ~= nil and
            prBody:find("return false", 1, true) ~= nil)
        check("ParentRestricts delegates to ns.Helpers.FrameIsProtected",
            prBody:find("ns.Helpers.FrameIsProtected", 1, true) ~= nil)
        -- Must ALSO check IsAnchoringRestricted: the dependent case (target hosts
        -- SecureActionButton children) leaves IsProtected false but still blocks
        -- SetSize, and is the real-world buff->essential crash.
        check("ParentRestricts delegates to ns.Helpers.FrameIsAnchoringRestricted",
            prBody:find("ns.Helpers.FrameIsAnchoringRestricted", 1, true) ~= nil)
    end
end

-- -------------------------------------------------------------------------
-- 4. ApplyFrameAnchor: the four converted sites now call AnchorOrPin,
--    and SmoothSetPoint is NOT called directly for those sites.
--    Verify: direct calls (AnchorOrPin() and ns.SafeCall(policy, AnchorOrPin,...))
--    total == 4. SmoothSetPoint still exists in the file (boss-array branch & others).
-- -------------------------------------------------------------------------
-- Count direct calls: "AnchorOrPin(key," pattern.
-- NOTE: the "local function AnchorOrPin(key," definition line also matches this
-- pattern, so subtract 1 to exclude it and count only real call sites.
local directCalls = 0
for _ in src:gmatch("AnchorOrPin%(key,") do
    directCalls = directCalls + 1
end
directCalls = directCalls - 1  -- subtract 1 for the definition line
-- Count SafeCall-wrapped calls: 'ns.SafeCall("...", AnchorOrPin, ' pattern
-- (Task 45d converted the prior bare 'pcall(AnchorOrPin,' sites to this form).
local pcallCalls = 0
for _ in src:gmatch('ns%.SafeCall%("[%w%-]+",%s*AnchorOrPin,') do
    pcallCalls = pcallCalls + 1
end
local totalAnchorOrPinCalls = directCalls + pcallCalls

check("anchoring.lua has exactly 4 AnchorOrPin call sites (growAnchor corner + 2 CENTER variants + normal path)",
    totalAnchorOrPinCalls == 4,
    ("found %d direct + %d pcall-wrapped = %d total (need exactly 4)"):format(
        directCalls, pcallCalls, totalAnchorOrPinCalls))

check("SmoothSetPoint still exists in anchoring.lua (boss-array branch preserved)",
    src:find("SmoothSetPoint", 1, true) ~= nil)

-- -------------------------------------------------------------------------
-- 5. buffIcon and buffBar remain in QUI_UpdateFramesAnchoredTo in-combat whitelist.
-- -------------------------------------------------------------------------
local updateFuncStart = src:find("_G%.QUI_UpdateFramesAnchoredTo = function", 1)
check("QUI_UpdateFramesAnchoredTo function found", updateFuncStart ~= nil)

if updateFuncStart then
    local updateBody = src:sub(updateFuncStart, updateFuncStart + 3000)
    check("buffIcon is in the QUI_UpdateFramesAnchoredTo in-combat whitelist",
        updateBody:find('"buffIcon"', 1, true) ~= nil)
    check("buffBar is in the QUI_UpdateFramesAnchoredTo in-combat whitelist",
        updateBody:find('"buffBar"', 1, true) ~= nil)
    check("buffFrame is in the QUI_UpdateFramesAnchoredTo in-combat whitelist",
        updateBody:find('"buffFrame"', 1, true) ~= nil)
    check("debuffFrame is in the QUI_UpdateFramesAnchoredTo in-combat whitelist",
        updateBody:find('"debuffFrame"', 1, true) ~= nil)
end

-- -------------------------------------------------------------------------
-- 5b. Split player aura frames are both first-class anchor targets.
-- -------------------------------------------------------------------------
check("debuffFrame is a dynamic reanchor key",
    src:find("debuffFrame = true", src:find("local DYNAMIC_REANCHOR_KEYS", 1, true) or 1, true) ~= nil)

local frameResolversStart = src:find("local FRAME_RESOLVERS = {", 1, true)
check("FRAME_RESOLVERS table found", frameResolversStart ~= nil)
if frameResolversStart then
    check("FRAME_RESOLVERS has buffFrame resolver",
        src:find("buffFrame = function()", frameResolversStart, true) ~= nil and
        src:find('"QUI_BuffIconContainer"', frameResolversStart, true) ~= nil)
    check("FRAME_RESOLVERS has debuffFrame resolver",
        src:find("debuffFrame = function()", frameResolversStart, true) ~= nil and
        src:find('"QUI_DebuffIconContainer"', frameResolversStart, true) ~= nil)
end

local anchorInfoStart = src:find("local FRAME_ANCHOR_INFO = {", 1, true)
check("FRAME_ANCHOR_INFO table found", anchorInfoStart ~= nil)
if anchorInfoStart then
    local infoBody = src:sub(anchorInfoStart, anchorInfoStart + 7000)
    check("FRAME_ANCHOR_INFO lists buffFrame",
        infoBody:find("buffFrame", 1, true) ~= nil and
        infoBody:find("Buff Frame", 1, true) ~= nil)
    check("FRAME_ANCHOR_INFO lists debuffFrame",
        infoBody:find("debuffFrame", 1, true) ~= nil and
        infoBody:find("Debuff Frame", 1, true) ~= nil)
end

local dynSizeStart = src:find("local DYNAMIC_SIZE_ANCHOR_KEYS = {", 1, true)
check("DYNAMIC_SIZE_ANCHOR_KEYS table found", dynSizeStart ~= nil)
if dynSizeStart then
    local dynBody = src:sub(dynSizeStart, dynSizeStart + 1800)
    check("buffFrame is a dynamic-size anchor key",
        dynBody:find("buffFrame = true", 1, true) ~= nil)
    check("debuffFrame is a dynamic-size anchor key",
        dynBody:find("debuffFrame = true", 1, true) ~= nil)
end

-- -------------------------------------------------------------------------
-- 6. IsDynamicSizeAnchorKey is defined BEFORE AnchorOrPin (scope ordering).
-- -------------------------------------------------------------------------
local dynKeyPos    = src:find("local function IsDynamicSizeAnchorKey", 1, true)
local anchorOrPinPos = src:find("local function AnchorOrPin", 1, true)
check("IsDynamicSizeAnchorKey is defined before AnchorOrPin (upvalue in scope)",
    dynKeyPos ~= nil and anchorOrPinPos ~= nil and dynKeyPos < anchorOrPinPos,
    ("IsDynamicSizeAnchorKey at byte %s, AnchorOrPin at byte %s"):format(
        tostring(dynKeyPos), tostring(anchorOrPinPos)))

print(("\n%d failure(s)"):format(failures))
if failures == 0 then
    print("OK: anchoring_dynamic_size_uiparent_pin_test")
end
os.exit(failures == 0 and 0 or 1)
