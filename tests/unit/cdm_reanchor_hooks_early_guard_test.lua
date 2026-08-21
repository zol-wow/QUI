-- tests/unit/cdm_reanchor_hooks_early_guard_test.lua
-- Run: lua tests/unit/cdm_reanchor_hooks_early_guard_test.lua
--
-- Root cause under test (utility combat-start snap): the anchor guard was
-- installed only at CLAIM time (runtime PositionEntries), so a frame Blizzard
-- acquires/re-flows at combat start had no SetPoint guard and no alpha-0 park
-- -- it rendered at the native viewer's mid-screen position until the next
-- re-claim pass. The hooks layer must install the guard on every acquire for
-- opted-in keys (post-initial-reanchor), and the acquire blank must not
-- blank frames the bridge still claims (claimed frames re-pin via their
-- guard; blanking them adds an alpha-0/alpha-1 flicker per pool churn).
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_hooks.lua", "cdm_reanchor_hooks.lua")("QUI", ns)
local H = assert(ns.CDMReanchorHooks, "CDMReanchorHooks should be exported")

local function makeFrame()
    return {
        OnActiveStateChanged = function() end,
        OnCooldownIDSet = function() end,
    }
end

local function findHook(hookInstalls, owner, method)
    for i = 1, #hookInstalls do
        local h = hookInstalls[i]
        if h.owner == owner and h.method == method then return h.fn end
    end
    return nil
end

-- Harness: one essential viewer + one buff viewer, controllable
-- isInitialReanchorDone, spies on installGuard / blank / isClaimed.
local function makeHarness(doneByKey)
    local t = {
        hookInstalls = {},
        guardCalls = {},
        blanked = {},
        claimedFrames = {},
    }
    local function fakeHook(owner, method, fn)
        t.hookInstalls[#t.hookInstalls + 1] = { owner = owner, method = method, fn = fn }
    end
    local function makeViewer()
        return {
            RefreshLayout = function() end,
            OnAcquireItemFrame = function() end,
            HookScript = function() end,
        }
    end
    t.viewers = { essential = makeViewer(), buff = makeViewer() }
    t.hooks = H.New({
        refresh = function() end,
        keys = { "essential", "buff" },
        hooksecurefunc = fakeHook,
        schedule = function() end,
        installGuard = function(frame, key)
            t.guardCalls[#t.guardCalls + 1] = { frame = frame, key = key }
        end,
        installGuardKeys = { essential = true, utility = true },
        blank = function(frame) t.blanked[#t.blanked + 1] = frame end,
        blankKeys = { essential = true, buff = true },
        isClaimed = function(frame) return t.claimedFrames[frame] == true end,
        isInitialReanchorDone = function(key) return doneByKey[key] == true end,
    })
    t.hooks:InstallViewerHooks(function(key) return t.viewers[key] end)
    t.acquireEssential = assert(
        findHook(t.hookInstalls, t.viewers.essential, "OnAcquireItemFrame"),
        "OnAcquireItemFrame hook installed on essential viewer")
    t.acquireBuff = assert(
        findHook(t.hookInstalls, t.viewers.buff, "OnAcquireItemFrame"),
        "OnAcquireItemFrame hook installed on buff viewer")
    return t
end

-- 1) Pre-initial-reanchor: no early guard (cold-login frames must not be
--    alpha-0'd by the guard before QUI's first pass adopts them).
do
    local t = makeHarness({ essential = false, buff = false })
    t.acquireEssential(t.viewers.essential, makeFrame())
    assert(#t.guardCalls == 0,
        "no early guard install before the initial reanchor pass is done")
end

-- 2) Post-initial-reanchor: every acquire on an opted-in key installs the
--    guard (idempotence is the bridge's job), including frames first seen
--    before the initial pass completed.
do
    local t = makeHarness({ essential = true, buff = true })
    local fresh = makeFrame()
    t.acquireEssential(t.viewers.essential, fresh)
    assert(#t.guardCalls == 1 and t.guardCalls[1].frame == fresh
        and t.guardCalls[1].key == "essential",
        "acquire on an opted-in key installs the anchor guard on the acquired frame")

    -- re-acquire of the same frame retries the guard (bridge dedupes)
    t.acquireEssential(t.viewers.essential, fresh)
    assert(#t.guardCalls == 2, "guard install retried on every acquire")

    -- buff is NOT opted in (its unclaimed natives are intentionally visible:
    -- skipNativeSink) -- no early guard for it.
    t.acquireBuff(t.viewers.buff, makeFrame())
    assert(#t.guardCalls == 2, "no early guard install for keys outside installGuardKeys")
end

-- 3) Acquire blank skips frames the bridge still claims: their SetPoint guard
--    re-pins them synchronously, and blanking would flicker them per churn.
do
    local t = makeHarness({ essential = true, buff = true })
    local claimed, unclaimed = makeFrame(), makeFrame()
    t.claimedFrames[claimed] = true
    t.acquireEssential(t.viewers.essential, claimed)
    t.acquireEssential(t.viewers.essential, unclaimed)
    local blankedSet = {}
    for _, f in ipairs(t.blanked) do blankedSet[f] = true end
    assert(not blankedSet[claimed], "claimed frames are not blanked on acquire")
    assert(blankedSet[unclaimed], "unclaimed frames are blanked on acquire")
end

-- 4) cdm_containers must wire the new deps for the re-anchor hook instance:
--    essential+utility in blankKeys and installGuardKeys, bridge-backed
--    installGuard + isClaimed.
do
    local f = assert(io.open("QUI_CDM/cdm/cdm_containers.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    assert(src:find("blankKeys = { buff = true }", 1, true),
        "cdm_containers must not alpha-blank newly acquired Essential/Utility frames")
    assert(src:find("installGuardKeys = { essential = true, utility = true }", 1, true),
        "cdm_containers must opt essential+utility into early guard install")
    assert(src:find("installGuard = ", 1, true),
        "cdm_containers must wire installGuard to the boot bridge")
    assert(src:find("isClaimed = ", 1, true),
        "cdm_containers must wire isClaimed to the boot bridge")
end

print("OK: cdm_reanchor_hooks_early_guard_test")
