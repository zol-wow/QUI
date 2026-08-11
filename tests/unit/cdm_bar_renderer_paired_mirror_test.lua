-- tests/unit/cdm_bar_renderer_paired_mirror_test.lua
-- Run: lua tests/unit/cdm_bar_renderer_paired_mirror_test.lua
--
-- Structural regression (bar renderer is dependency-heavy; the suite asserts
-- source structure -- see cdm_buff_layout_no_combat_end_populate_test).
--
-- Paired tracked bars (spell present in Blizzard's BuffBarCooldownViewer)
-- must NEVER enter the Lua resolver: 12.1 blocks duration/aura reads for
-- tainted code while auras are secret, so fill + countdown mirror Blizzard's
-- live bar through absorb-capable widget setters instead
-- (SetMinMaxValues/SetValue/SetText accept secret values natively).
--
-- Contract:
--   1. UpdateOwnedBarAura short-circuits to the paired path BEFORE the
--      resolver runs.
--   2. The 100ms timer loop mirrors visuals for paired bars BEFORE the
--      durObj branches.
--   3. The pairing is re-validated by plain cooldownID compare (pool
--      re-keying must not mirror the wrong spell).
--   4. Mirror visuals contain NO comparison of mirrored values -- straight
--      getter->setter passthrough.
--   5. ReleaseBar clears the pairing (pooled bars must not keep stale
--      Blizzard refs).
--   6. Active state comes from IsActive (not IsShown) and fails OPEN on
--      secret.

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_CDM/cdm/cdm_bar_renderer.lua")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

---------------------------------------------------------------------------
-- 1. UpdateOwnedBarAura: paired short-circuit before the resolver.
---------------------------------------------------------------------------
local updStart = assert(string.find(src, "function CDMBars:UpdateOwnedBarAura(bar)", 1, true),
    "UpdateOwnedBarAura should exist")
local pairedCheck = string.find(src, "GetPairedBlzChild(bar)", updStart, true)
local resolverCall = assert(string.find(src, "ns.CDMResolvers.ResolveCooldownState", updStart, true),
    "resolver lookup should exist in UpdateOwnedBarAura")

check("UpdateOwnedBarAura must check pairing before the resolver",
    pairedCheck ~= nil and pairedCheck < resolverCall,
    pairedCheck == nil and "no GetPairedBlzChild call found"
        or "paired check sits after the resolver lookup")

local pairedBlock = pairedCheck and string.sub(src, pairedCheck, resolverCall)
check("paired branch must return before reaching the resolver",
    pairedBlock ~= nil and string.find(pairedBlock, "UpdatePairedBarState%(bar, blz%)%s+return") ~= nil,
    "UpdatePairedBarState(...) return not found between paired check and resolver")

---------------------------------------------------------------------------
-- 2. Visual ownership: paired bars tick on a dedicated per-frame mirror
--    ticker (reference pattern — fill needs frame-rate updates); the 100ms
--    durObj loop must skip them, not double-drive them.
---------------------------------------------------------------------------
local tickerStart = assert(string.find(src, "local pairedMirrorFrame = CreateFrame", 1, true),
    "per-frame mirror ticker should exist")
check("mirror ticker must call MirrorPairedBarVisuals",
    string.find(src, "MirrorPairedBarVisuals(bar, blz)", tickerStart, true) ~= nil,
    "ticker does not drive the mirror")

local loopStart = assert(string.find(src, 'barTimerGroup:SetScript("OnLoop"', 1, true),
    "timer loop should exist")
local loopSkip = string.find(src, "GetPairedBlzChild(bar)", loopStart, true)
local loopDurObj = assert(string.find(src, "local durObj = bar._durObj", loopStart, true),
    "durObj branch should exist in the timer loop")

check("100ms loop must skip paired bars before the durObj branch",
    loopSkip ~= nil and loopSkip < loopDurObj,
    loopSkip == nil and "no paired skip in the timer loop"
        or "paired skip sits after the durObj branch")
check("100ms loop must not drive paired visuals",
    not string.find(src, "MirrorPairedBarVisuals(bar, pairedBlz)", loopStart, true),
    "100ms loop still mirrors paired bars -- two owners fight over the fill")

---------------------------------------------------------------------------
-- 2b. First tick after show snaps; later ticks ease (reference wasShown).
---------------------------------------------------------------------------
local mirrorFnStart = assert(string.find(src, "local function MirrorPairedBarVisuals(bar, blz)", 1, true))
local mirrorFnEnd = assert(string.find(src, "\nend", mirrorFnStart, true))
local mirrorFnBody = string.sub(src, mirrorFnStart, mirrorFnEnd + 4)
check("mirror must snap on first show and ease afterwards",
    string.find(mirrorFnBody, "bar._mirrorWasShown and barFillInterpolation", 1, true) ~= nil,
    "always-interpolated SetValue -- fresh bars animate from stale values")

---------------------------------------------------------------------------
-- 3. Pairing re-validation by plain cooldownID compare.
---------------------------------------------------------------------------
local pairFnStart = assert(string.find(src, "local function GetPairedBlzChild(bar)", 1, true),
    "GetPairedBlzChild should exist")
local pairFnEnd = assert(string.find(src, "\nend", pairFnStart, true))
local pairFn = string.sub(src, pairFnStart, pairFnEnd + 4)

check("pairing must re-validate cooldownID",
    string.find(pairFn, "cid == wantCid", 1, true) ~= nil,
    "no cooldownID re-validation -- pool re-keying would mirror the wrong spell")
check("pairing must secret-guard the cooldownID before comparing",
    (string.find(pairFn, "issecretvalue(cid)", 1, true) or math.huge)
        < (string.find(pairFn, "cid == wantCid", 1, true) or 0),
    "cooldownID compared without a secret guard")

---------------------------------------------------------------------------
-- 4. Mirror visuals: pure passthrough, no comparisons on mirrored values.
---------------------------------------------------------------------------
local mirrorStart = assert(string.find(src, "local function MirrorPairedBarVisuals(bar, blz)", 1, true),
    "MirrorPairedBarVisuals should exist")
local mirrorEnd = assert(string.find(src, "\nend", mirrorStart, true))
local mirrorFn = string.sub(src, mirrorStart, mirrorEnd + 4)

check("mirror must forward GetMinMaxValues into SetMinMaxValues",
    string.find(mirrorFn, "SetMinMaxValues(sb, nativeBar:GetMinMaxValues())", 1, true) ~= nil,
    "min/max passthrough missing")
check("mirror must forward GetValue into SetValue",
    string.find(mirrorFn, "nativeBar:GetValue()", 1, true) ~= nil,
    "value passthrough missing")
check("mirror must forward Duration text into SetText",
    string.find(mirrorFn, "durationFS:GetText()", 1, true) ~= nil,
    "duration text passthrough missing")
check("mirror must not compare mirrored values",
    not (string.find(mirrorFn, "GetValue() ~=", 1, true)
        or string.find(mirrorFn, "GetValue() ==", 1, true)
        or string.find(mirrorFn, "GetText() ~=", 1, true)
        or string.find(mirrorFn, "GetText() ==", 1, true)),
    "comparison on a mirrored (possibly secret) value")

---------------------------------------------------------------------------
-- 4b. Pairing self-heals (reference pattern): on cooldownID mismatch the
--     lookup re-scans live viewer children instead of going dark — an
--     unpaired bar has no combat fill/timer source and pins full.
---------------------------------------------------------------------------
check("pairing must re-scan viewer children on mismatch",
    string.find(src, "local function FindBlzChildByCooldownID(cooldownID)", 1, true) ~= nil
        and string.find(pairFn == nil and "" or src, "FindBlzChildByCooldownID(wantCid)", 1, true) ~= nil,
    "no self-healing re-scan -- stale pairing after pool recycle leaves the bar sourceless")

---------------------------------------------------------------------------
-- 4c. The no-rebuild reuse path must refresh the pairing from the freshly
--     scanned entries (build-time-only pairing goes stale mid-combat).
---------------------------------------------------------------------------
local reuseStart = assert(string.find(src, "if not needsRebuild then", 1, true),
    "reuse path should exist")
local reuseEnd = assert(string.find(src, "self:ClearPool()", reuseStart, true),
    "reuse path should precede the rebuild")
local reuseBlock = string.sub(src, reuseStart, reuseEnd)
check("reuse path must refresh _blzChild from the scanned entry",
    string.find(reuseBlock, "bar._blzChild = entry._blzFrame", 1, true) ~= nil,
    "reuse path keeps stale pairing -- combat aura churn breaks the mirror")

---------------------------------------------------------------------------
-- 5. ReleaseBar clears the pairing.
---------------------------------------------------------------------------
local relStart = assert(string.find(src, "local function ReleaseBar(bar)", 1, true),
    "ReleaseBar should exist")
local relEnd = assert(string.find(src, "\nend", relStart, true))
local relFn = string.sub(src, relStart, relEnd + 4)

check("ReleaseBar must clear _blzChild",
    string.find(relFn, "bar._blzChild = nil", 1, true) ~= nil,
    "_blzChild not cleared on release")
check("ReleaseBar must clear _blzCooldownID",
    string.find(relFn, "bar._blzCooldownID = nil", 1, true) ~= nil,
    "_blzCooldownID not cleared on release")

---------------------------------------------------------------------------
-- 6. Active state: IsActive-first; secret = keep-visible ACTION POLICY.
-- What this pins is a display policy, NOT a truth conversion: a secret
-- IsActive is INDETERMINATE and must never be read as "active" — the
-- keep-visible return simply ensures a possibly-active bar is never hidden
-- (reference-mirror directive). See ReadPairedBarActive's contract comment.
---------------------------------------------------------------------------
local actStart = assert(string.find(src, "local function ReadPairedBarActive(blz)", 1, true),
    "ReadPairedBarActive should exist")
local actEnd = assert(string.find(src, "\nend", actStart, true))
local actFn = string.sub(src, actStart, actEnd + 4)

check("active state must prefer IsActive over IsShown",
    (string.find(actFn, "blz.IsActive", 1, true) or math.huge)
        < (string.find(actFn, "blz.IsShown", 1, true) or math.huge),
    "IsShown checked before IsActive -- inactive items stay shown by default")
check("secret active state must fail open (return true)",
    string.find(actFn, "issecretvalue(active) then return true", 1, true) ~= nil,
    "secret active state does not fail open -- possibly-active bar would hide")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
