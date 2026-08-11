-- tests/unit/cdm_reanchor_hooks_test.lua
-- Run: lua tests/unit/cdm_reanchor_hooks_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_hooks.lua", "cdm_reanchor_hooks.lua")("QUI", ns)
local H = assert(ns.CDMReanchorHooks, "CDMReanchorHooks should be exported")
assert(type(H.New) == "function", "New is a function")

-- scheduler that records the callback so the test drives the flush
local pending
local refreshed = {}
local hooks = H.New({
    refresh = function(key) refreshed[#refreshed+1] = key end,
    keys = { "essential", "utility" },
    schedule = function(fn) pending = fn end,
})

-- MarkDirty coalesces: many marks -> one scheduled flush
hooks:MarkDirty("essential")
hooks:MarkDirty("essential")
hooks:MarkDirty("utility")
assert(#refreshed == 0, "nothing refreshes until the scheduled flush fires")
assert(type(pending) == "function", "a flush was scheduled once")

pending()  -- fire the scheduled flush
assert(#refreshed == 2, "each dirty container refreshed once")
local seen = {}
for _, k in ipairs(refreshed) do seen[k] = (seen[k] or 0) + 1 end
assert(seen.essential == 1 and seen.utility == 1, "essential + utility each refreshed once")

-- after flush, a new mark schedules again
pending = nil
hooks:MarkDirty("essential")
assert(type(pending) == "function", "re-arms scheduling after a flush")

-- MarkAllDirty marks every managed key
refreshed = {}
hooks:MarkAllDirty()
pending()
assert(#refreshed == 2, "MarkAllDirty requeues every managed container")

-- InstallViewerHooks: hooks Blizzard relayout/acquire/viewer visibility plus
-- per-frame CDM state changes. Re-running after nil viewers is the retry path
-- used when Blizzard_CooldownViewer loads after QUI.
local hookInstalls = {}
local function fakeHook(owner, method, fn) hookInstalls[#hookInstalls+1] = { owner = owner, method = method, fn = fn } end
local scripts = {}
local function makeFrame()
    return {
        OnActiveStateChanged = function() end,
        OnCooldownIDSet = function() end,
    }
end
local existingFrame, acquiredFrame = makeFrame(), makeFrame()
local pool = {
    Acquire = function() end,
    EnumerateActive = function()
        local yielded = false
        return function()
            if yielded then return nil end
            yielded = true
            return existingFrame
        end
    end,
}
local viewers = {
    essential = {
        RefreshLayout = function() end,
        OnAcquireItemFrame = function() end,
        itemFramePool = pool,
        HookScript = function(self, scriptName, fn) scripts[scriptName] = fn end,
    },
    utility = { RefreshLayout = function() end },
}
local h2refresh = {}
local h2 = H.New({
    refresh = function(k) h2refresh[#h2refresh+1] = k end,
    keys = { "essential", "utility" },
    hooksecurefunc = fakeHook,
    schedule = function(fn) fn() end,  -- immediate flush
})
h2:InstallViewerHooks(function() return nil end)
assert(#hookInstalls == 0, "nil viewers do not permanently block later hook install")
h2:InstallViewerHooks(function(k) return viewers[k] end)
assert(#hookInstalls >= 6, "viewer acquire/refresh and frame state hooks installed")
assert(hookInstalls[1].method == "RefreshLayout", "hooks RefreshLayout")
-- idempotent: re-install does not double-hook
local installedCount = #hookInstalls
h2:InstallViewerHooks(function(k) return viewers[k] end)
assert(#hookInstalls == installedCount, "InstallViewerHooks is idempotent per viewer/frame")
-- firing a hooked RefreshLayout drives one refresh (immediate scheduler here)
hookInstalls[1].fn()
assert(#h2refresh == 1, "firing the RefreshLayout hook drives one re-claim")

local acquireHook, activeHook, idHook
for _, h in ipairs(hookInstalls) do
    if h.owner == viewers.essential and h.method == "OnAcquireItemFrame" then acquireHook = h.fn end
    if h.owner == existingFrame and h.method == "OnActiveStateChanged" then activeHook = h.fn end
    if h.owner == existingFrame and h.method == "OnCooldownIDSet" then idHook = h.fn end
end
assert(type(acquireHook) == "function", "hooks viewer OnAcquireItemFrame")
assert(type(activeHook) == "function", "hooks existing frame OnActiveStateChanged")
assert(type(idHook) == "function", "hooks existing frame OnCooldownIDSet")
assert(type(scripts.OnShow) == "function" and type(scripts.OnHide) == "function", "hooks viewer show/hide")

local before = #h2refresh
acquireHook(viewers.essential, acquiredFrame)
assert(#h2refresh == before + 1, "acquired frame queues a re-claim")
local acquiredIDHook
for _, h in ipairs(hookInstalls) do
    if h.owner == acquiredFrame and h.method == "OnCooldownIDSet" then acquiredIDHook = h.fn end
end
assert(type(acquiredIDHook) == "function", "acquired frame gets cooldown-id hook")

before = #h2refresh
activeHook(existingFrame)
idHook(existingFrame)
scripts.OnShow(viewers.essential)
scripts.OnHide(viewers.essential)
assert(#h2refresh == before + 4, "frame and viewer state changes each queue re-claim")

-- Buff active-state changes are fired while Blizzard is still mutating the pooled
-- item. Match the reference model: re-apply the existing position immediately,
-- but defer the collect/re-claim through the active-state settle scheduler.
do
    local installs = {}
    local refreshes = {}
    local genericPending = {}
    local activePending = {}
    local reapply = {}
    local function hook(owner, method, fn)
        installs[#installs + 1] = { owner = owner, method = method, fn = fn }
    end
    local frame = { OnActiveStateChanged = function() end }
    local pool = {
        EnumerateActive = function()
            local yielded = false
            return function()
                if yielded then return nil end
                yielded = true
                return frame
            end
        end,
    }
    local viewer = { RefreshLayout = function() end, itemFramePool = pool }
    local settled = H.New({
        refresh = function(k) refreshes[#refreshes + 1] = k end,
        keys = { "buff" },
        hooksecurefunc = hook,
        schedule = function(fn) genericPending[#genericPending + 1] = fn end,
        scheduleActiveState = function(fn) activePending[#activePending + 1] = fn end,
        reapplyPositions = function(k) reapply[#reapply + 1] = k end,
    })
    settled:InstallViewerHooks(function() return viewer end)

    local activeStateHook
    for _, h in ipairs(installs) do
        if h.owner == frame and h.method == "OnActiveStateChanged" then
            activeStateHook = h.fn
        end
    end
    assert(type(activeStateHook) == "function", "active-state settle test installs frame hook")

    activeStateHook(frame)
    assert(#reapply == 1 and reapply[1] == "buff", "active-state hook re-applies current positions immediately")
    assert(#refreshes == 0, "active-state hook does not refresh synchronously")
    assert(#genericPending == 0, "active-state hook bypasses the generic refresh scheduler")
    assert(#activePending == 1, "active-state hook uses the settled active-state scheduler")

    activePending[1]()
    assert(#refreshes == 1 and refreshes[1] == "buff",
        "settled active-state callback re-claims the buff container")
end

-- Native-show restore: Blizzard can SetShown(true) a previously alpha-0'd
-- (sunk) BuffIcon frame from its incremental UNIT_AURA path without firing any
-- Acquire/RefreshLayout/OnCooldownIDSet. Alpha-0 is a one-way door that only a
-- successful re-claim pass reopens, so the item's OnShow must re-drive the
-- active-state re-claim; without it a re-shown frame stays invisible at alpha 0.
do
    local installs, refreshes, activePending, itemScripts = {}, {}, {}, {}
    local function hook(owner, method, fn)
        installs[#installs + 1] = { owner = owner, method = method, fn = fn }
    end
    local frame = {
        OnActiveStateChanged = function() end,
        HookScript = function(self, name, fn) itemScripts[name] = fn end,
    }
    local pool = {
        EnumerateActive = function()
            local yielded = false
            return function()
                if yielded then return nil end
                yielded = true
                return frame
            end
        end,
    }
    local viewer = { RefreshLayout = function() end, itemFramePool = pool }
    local restore = H.New({
        refresh = function(k) refreshes[#refreshes + 1] = k end,
        keys = { "buff" },
        hooksecurefunc = hook,
        scheduleActiveState = function(fn) activePending[#activePending + 1] = fn end,
    })
    restore:InstallViewerHooks(function() return viewer end)

    assert(type(itemScripts.OnShow) == "function",
        "item frames get an OnShow native-show restore hook")
    itemScripts.OnShow(frame)
    assert(#refreshes == 0, "item OnShow does not refresh synchronously")
    assert(#activePending == 1, "item OnShow routes through the active-state settle scheduler")
    activePending[1]()
    assert(#refreshes == 1 and refreshes[1] == "buff",
        "settled item OnShow callback re-claims the buff container")
end

-- Buff RefreshLayout is latency-sensitive: reference-style buff reanchor runs
-- immediately on RefreshLayout with a small guard instead of waiting for the
-- generic delayed dirty flush. This prevents a one-frame overlap at the native
-- viewer position while buffs pop in/out.
do
    local installs = {}
    local refreshes = {}
    local pending = {}
    local function hook(owner, method, fn)
        installs[#installs + 1] = { owner = owner, method = method, fn = fn }
    end
    local viewer = { RefreshLayout = function() end }
    local immediate = H.New({
        refresh = function(k) refreshes[#refreshes + 1] = k end,
        keys = { "buff" },
        hooksecurefunc = hook,
        schedule = function(fn) pending[#pending + 1] = fn end,
        immediateKeys = { buff = true },
    })
    immediate:InstallViewerHooks(function() return viewer end)

    local refreshHook
    for _, h in ipairs(installs) do
        if h.owner == viewer and h.method == "RefreshLayout" then refreshHook = h.fn end
    end
    assert(type(refreshHook) == "function", "immediate buff test installs RefreshLayout hook")

    refreshHook(viewer)
    assert(#refreshes == 1 and refreshes[1] == "buff",
        "buff RefreshLayout refreshes immediately")
    assert(#pending == 0, "buff RefreshLayout bypasses the generic delayed scheduler")
end

-- Buff pool acquisition is latency-sensitive too. A newly acquired native
-- BuffIcon item can flash at Blizzard's native position if we wait for the
-- generic delayed dirty flush. Reference-style hooks re-claim immediately.
do
    local installs = {}
    local refreshes = {}
    local pending = {}
    local function hook(owner, method, fn)
        installs[#installs + 1] = { owner = owner, method = method, fn = fn }
    end
    local viewer = { RefreshLayout = function() end, OnAcquireItemFrame = function() end }
    local immediate = H.New({
        refresh = function(k) refreshes[#refreshes + 1] = k end,
        keys = { "buff" },
        hooksecurefunc = hook,
        schedule = function(fn) pending[#pending + 1] = fn end,
        immediateAcquireKeys = { buff = true },
    })
    immediate:InstallViewerHooks(function() return viewer end)

    local acquireHook
    for _, h in ipairs(installs) do
        if h.owner == viewer and h.method == "OnAcquireItemFrame" then acquireHook = h.fn end
    end
    assert(type(acquireHook) == "function", "immediate acquire test installs OnAcquireItemFrame hook")

    acquireHook(viewer, { OnCooldownIDSet = function() end })
    assert(#refreshes == 1 and refreshes[1] == "buff",
        "buff OnAcquireItemFrame refreshes immediately")
    assert(#pending == 0, "buff OnAcquireItemFrame bypasses the generic delayed scheduler")
end

-- Global CooldownViewer item mixin hooks catch Blizzard item mutations even
-- before a newly pooled frame has been enumerated or seen by a viewer hook.
do
    local installs = {}
    local refreshes = {}
    local pending = {}
    local buffMixin = { OnCooldownIDSet = function() end }
    local trackedBarMixin = { OnCooldownIDSet = function() end }
    local function hook(owner, method, fn)
        installs[#installs + 1] = { owner = owner, method = method, fn = fn }
    end
    local globalHooks = H.New({
        refresh = function(k) refreshes[#refreshes + 1] = k end,
        keys = { "buff", "trackedBar" },
        hooksecurefunc = hook,
        schedule = function(fn) pending[#pending + 1] = fn end,
        immediateAcquireKeys = { buff = true, trackedBar = true },
        getMixinForKey = function(key)
            if key == "buff" then return buffMixin end
            if key == "trackedBar" then return trackedBarMixin end
        end,
    })
    assert(type(globalHooks.InstallGlobalMixinHooks) == "function",
        "global mixin hook installer is exported")
    assert(globalHooks:InstallGlobalMixinHooks() == true,
        "global mixin hooks install for buff icons and tracked bars")

    local byOwner = {}
    for _, h in ipairs(installs) do
        byOwner[h.owner] = h
    end
    assert(byOwner[buffMixin] and byOwner[buffMixin].method == "OnCooldownIDSet",
        "hooks CooldownViewerBuffIconItemMixin.OnCooldownIDSet")
    assert(byOwner[trackedBarMixin] and byOwner[trackedBarMixin].method == "OnCooldownIDSet",
        "hooks CooldownViewerBuffBarItemMixin.OnCooldownIDSet")

    byOwner[buffMixin].fn(buffMixin)
    byOwner[trackedBarMixin].fn(trackedBarMixin)
    assert(#refreshes == 0,
        "mixin OnCooldownIDSet hooks do not refresh synchronously")
    assert(#pending == 1,
        "global mixin hooks coalesce through the delayed dirty scheduler")
    pending[1]()
    local seen = {}
    for _, key in ipairs(refreshes) do seen[key] = true end
    assert(#refreshes == 2 and seen.buff and seen.trackedBar,
        "mixin OnCooldownIDSet hooks re-claim dirty latency-sensitive viewers")

    local before = #installs
    assert(globalHooks:InstallGlobalMixinHooks() == false,
        "global mixin hook install is idempotent")
    assert(#installs == before, "global mixin hooks do not double-install")
end

-- CDMIndex broker events also dirty all managed viewers.
local sub
h2:InstallIndexSubscription({
    Subscribe = function(name, fn, priority)
        sub = { name = name, fn = fn, priority = priority }
    end,
})
assert(sub and sub.name == "reanchor" and type(sub.fn) == "function", "subscribes to CDMIndex")
before = #h2refresh
sub.fn("data_loaded")
assert(#h2refresh == before + 2, "CDMIndex events dirty all managed containers")

-- Buff acquire blanking is reference-style but must wait until the first
-- successful reanchor pass. Blanking during first-login cold load can hide the
-- very first aura before QUI has adopted it; after initial reanchor, blanking
-- prevents a newly acquired native item from flashing in Blizzard's position.
do
    local blanked = {}
    local initFlag = false
    local initialDoneByKey = {}
    local installs = {}
    local function fakeHook2(owner, method, fn) installs[#installs+1] = { owner=owner, method=method, fn=fn } end
    local g11 = H.New({
        refresh = function() end,
        keys = { "essential", "buff" },
        hooksecurefunc = fakeHook2,
        schedule = function(fn) fn() end,  -- immediate flush
        blank = function(frame) blanked[#blanked+1] = frame end,
        isInitWindow = function() return initFlag end,
        isInitialReanchorDone = function(key) return initialDoneByKey[key] == true end,
        blankKeys = { buff = true },
    })
    local buffViewer = { RefreshLayout = function() end, OnAcquireItemFrame = function() end }
    local essViewer  = { RefreshLayout = function() end, OnAcquireItemFrame = function() end }
    local vmap = { buff = buffViewer, essential = essViewer }
    g11:InstallViewerHooks(function(k) return vmap[k] end)

    local function acquireFor(viewer)
        for _, h in ipairs(installs) do
            if h.owner == viewer and h.method == "OnAcquireItemFrame" then return h.fn end
        end
    end
    local buffAcquire, essAcquire = acquireFor(buffViewer), acquireFor(essViewer)
    assert(type(buffAcquire) == "function" and type(essAcquire) == "function",
        "G11: both viewers expose an OnAcquireItemFrame hook")

    -- past init but before initial reanchor: no blank yet
    initFlag = false
    local bf = { OnActiveStateChanged = function() end }
    buffAcquire(buffViewer, bf)
    assert(#blanked == 0, "buff acquire does not blank before the first reanchor completes")

    -- after initial reanchor: blank immediately, then re-claim
    blanked = {}
    initialDoneByKey.buff = true
    buffAcquire(buffViewer, bf)
    assert(#blanked == 1 and blanked[1] == bf,
        "buff acquire blanks fresh frames after initial reanchor")

    -- during the initial boot window: still no blank, even if a prior reanchor completed
    blanked = {}
    initFlag = true
    buffAcquire(buffViewer, { OnActiveStateChanged = function() end })
    assert(#blanked == 0, "buff acquire does not blank during the initial boot window")

    -- essential: no blank either
    blanked = {}
    initFlag = false
    essAcquire(essViewer, { OnActiveStateChanged = function() end })
    assert(#blanked == 0, "essential/utility acquires are not blanked")
end

-- Global placement mode: a coalesced dirty set is delivered as one ordered
-- batch, never one refresh per key (which would reintroduce refresh-order
-- ownership). Immediate lifecycle paths use the same batch seam.
do
    local batches = {}
    local batchHooks = H.New({
        keys = { "essential", "utility", "buff" },
        refresh = function() error("refreshMany must own the batch path") end,
        refreshMany = function(keys)
            local copy = {}
            for i = 1, #keys do copy[i] = keys[i] end
            batches[#batches + 1] = copy
        end,
    })
    batchHooks._dirty.utility = true
    batchHooks._dirty.essential = true
    batchHooks:Flush()
    assert(#batches == 1 and #batches[1] == 2
        and batches[1][1] == "essential" and batches[1][2] == "utility",
        "Flush emits one deterministic multi-key refresh")
    batchHooks:MarkImmediate("buff")
    assert(#batches == 2 and #batches[2] == 1 and batches[2][1] == "buff",
        "immediate paths also enter the batch refresh seam")
end

print("OK: cdm_reanchor_hooks_test")
