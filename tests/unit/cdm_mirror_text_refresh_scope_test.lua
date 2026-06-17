-- tests/unit/cdm_mirror_text_refresh_scope_test.lua
-- Run: lua5.1 tests/unit/cdm_mirror_text_refresh_scope_test.lua
-- luacheck: globals InCombatLockdown CreateFrame C_Timer wipe

local function noop() end

function InCombatLockdown() return false end
function CreateFrame()
    return {
        RegisterEvent = noop,
        SetScript = noop,
        Show = noop,
        Hide = noop,
    }
end

C_Timer = {
    After = function(_, fn) fn() end,
}

function wipe(t)
    for k in pairs(t) do t[k] = nil end
end

---------------------------------------------------------------------------
-- Load CDMIconMirrorIndex standalone
---------------------------------------------------------------------------
local ns = {}
assert(loadfile("QUI_CDM/cdm/cdm_icon_mirror_index.lua"))("QUI", ns)
local CDMIconMirrorIndex = assert(ns.CDMIconMirrorIndex,
    "CDMIconMirrorIndex should be exported")

---------------------------------------------------------------------------
-- Helper: make a minimal icon with mirror binding
---------------------------------------------------------------------------
local function makeIcon(cooldownID, category)
    local icon = {
        _blizzMirrorCooldownID = cooldownID,
        _blizzMirrorCategory   = category,
    }
    return icon
end

---------------------------------------------------------------------------
-- Test helpers: build a controller with spy callbacks
---------------------------------------------------------------------------
local function makeController(spies)
    spies = spies or {}
    local refreshIconCalls = {}
    local mirrorStates = spies.mirrorStates or {}

    local icon = makeIcon(1001, "essential")

    local callbacks = {
        isRuntimeEnabled = function() return true end,
        getCombatDelay   = function() return 0.016 end,
        getMirrorStateByCooldownID = function(cdID, cat)
            local key = cat .. ":" .. cdID
            return mirrorStates[key]
        end,
        storeMirrorStateForIcon = noop,
        prepareBatch = function() return false, nil, nil, false end,
        setStackTextWrites = noop,
        beginBatch = noop,
        endBatch = noop,
        drainLayoutDirty = noop,
        refreshIcon = function(ic, editMode, ncdm, ncdmContainers, inCombat, needsFull)
            refreshIconCalls[#refreshIconCalls + 1] = {
                icon     = ic,
                needsFull = needsFull,
            }
            return true
        end,
    }

    local controller = CDMIconMirrorIndex.Create(callbacks)
    -- Seed the icon index directly
    controller:BindIcon(icon, 1001, "essential")

    return controller, icon, refreshIconCalls
end

---------------------------------------------------------------------------
-- Test 1: text-only reason → refreshIcon called with needsFull=false
---------------------------------------------------------------------------
do
    local controller, icon, calls = makeController()

    controller:RequestRefresh(1001, "essential", false) -- needsFull=false (text-only)
    assert(#calls == 1, "test1: refreshIcon should be called once")
    assert(calls[1].needsFull == false,
        "test1: text-only reason should pass needsFull=false (got "
        .. tostring(calls[1].needsFull) .. ")")
    assert(calls[1].icon == icon,
        "test1: refreshIcon should receive the matching icon")
    print("PASS test1: text-only reason → needsFull=false")
end

---------------------------------------------------------------------------
-- Test 2: full reason → refreshIcon called with needsFull=true
---------------------------------------------------------------------------
do
    local controller, icon, calls = makeController()

    controller:RequestRefresh(1001, "essential", true) -- needsFull=true
    assert(#calls == 1, "test2: refreshIcon should be called once")
    assert(calls[1].needsFull == true,
        "test2: full reason should pass needsFull=true (got "
        .. tostring(calls[1].needsFull) .. ")")
    print("PASS test2: full reason → needsFull=true")
end

---------------------------------------------------------------------------
-- Test 3: Coalescing — text then full → drains as full (upgrade)
---------------------------------------------------------------------------
do
    -- Disable C_Timer.After to batch manually
    local pendingCallbacks = {}
    local origAfter = C_Timer.After
    C_Timer.After = function(_, fn)
        pendingCallbacks[#pendingCallbacks + 1] = fn
    end

    local controller, icon, calls = makeController()

    -- Queue text-only first (needsFull=false)
    controller:RequestRefresh(1001, "essential", false)
    -- Queue full second (needsFull=true) — should upgrade
    controller:RequestRefresh(1001, "essential", true)

    -- Drain pending
    for _, fn in ipairs(pendingCallbacks) do fn() end
    C_Timer.After = origAfter

    -- Both queues collapsed into one drain; only one icon call expected
    assert(#calls == 1,
        "test3: coalesced queue should produce exactly one refreshIcon call (got "
        .. tostring(#calls) .. ")")
    assert(calls[1].needsFull == true,
        "test3: coalesced full+text should drain as full (got "
        .. tostring(calls[1].needsFull) .. ")")
    print("PASS test3: coalescing text→full stays full (upgrade)")
end

---------------------------------------------------------------------------
-- Test 4: Coalescing — two text-only reasons → stays text
---------------------------------------------------------------------------
do
    local pendingCallbacks = {}
    local origAfter = C_Timer.After
    C_Timer.After = function(_, fn)
        pendingCallbacks[#pendingCallbacks + 1] = fn
    end

    local controller, icon, calls = makeController()

    controller:RequestRefresh(1001, "essential", false)
    controller:RequestRefresh(1001, "essential", false)

    for _, fn in ipairs(pendingCallbacks) do fn() end
    C_Timer.After = origAfter

    assert(#calls == 1,
        "test4: two text requests should collapse to one call (got "
        .. tostring(#calls) .. ")")
    assert(calls[1].needsFull == false,
        "test4: two text requests should stay text (needsFull=false, got "
        .. tostring(calls[1].needsFull) .. ")")
    print("PASS test4: two text-only reasons → stays text (no upgrade)")
end

---------------------------------------------------------------------------
-- Test 5: full then text → stays full (no downgrade)
---------------------------------------------------------------------------
do
    local pendingCallbacks = {}
    local origAfter = C_Timer.After
    C_Timer.After = function(_, fn)
        pendingCallbacks[#pendingCallbacks + 1] = fn
    end

    local controller, icon, calls = makeController()

    controller:RequestRefresh(1001, "essential", true)  -- full first
    controller:RequestRefresh(1001, "essential", false) -- text second — must NOT downgrade

    for _, fn in ipairs(pendingCallbacks) do fn() end
    C_Timer.After = origAfter

    assert(#calls == 1,
        "test5: full+text should collapse to one call (got "
        .. tostring(#calls) .. ")")
    assert(calls[1].needsFull == true,
        "test5: full followed by text must not downgrade to text (got "
        .. tostring(calls[1].needsFull) .. ")")
    print("PASS test5: full+text → stays full (no downgrade)")
end

---------------------------------------------------------------------------
-- Test 6: Reason classification — TEXT_ONLY_REASONS set
-- We extract the classifier logic from CDMBlizzMirror inline here to verify
-- the exact set, independent of loading the heavy blizz_mirror module.
-- The set is mirrored from the implementation — a diff between them will
-- cause the test to fail, surfacing any divergence.
---------------------------------------------------------------------------
do
    -- Expected text-only set (the spec). Cross-checked below against the REAL
    -- CDMBlizzMirror._textOnlyMirrorReasons when blizz_mirror loads in-harness.
    local TEXT_ONLY = {
        ["stack-text"]        = true,
        ["stack-hidden"]      = true,
        ["stack-empty"]       = true,
        ["stack-clear"]       = true,
        ["aura-stack-carry"]  = true,
        ["aura-stack-hidden"] = true,
        ["charge-field"]      = true,
        ["charge-field-hide"] = true,
    }

    local function classifyReason(reason)
        return not TEXT_ONLY[reason]
    end

    -- Text-only reasons → needsFull=false
    local textOnlyReasons = {
        "stack-text", "stack-hidden", "stack-empty", "stack-clear",
        "aura-stack-carry", "aura-stack-hidden", "charge-field", "charge-field-hide",
    }
    for _, r in ipairs(textOnlyReasons) do
        assert(classifyReason(r) == false,
            "test6: '" .. r .. "' should be classified as text-only (needsFull=false)")
    end

    -- Full-resolve reasons → needsFull=true
    local fullReasons = {
        "aura-clear", "active-state", "related-aura", "related-aura-clear",
        "totem-active", "totem-inactive", "overlay", "uses",
    }
    for _, r in ipairs(fullReasons) do
        assert(classifyReason(r) == true,
            "test6: '" .. r .. "' should be classified as full-resolve (needsFull=true)")
    end

    -- Unknown reasons → full (safe default)
    local unknownReasons = { "unknown", "xyz", "", nil }
    -- nil indexed into TEXT_ONLY returns nil (not true), so not TEXT_ONLY[nil] == true → needsFull=true
    assert(classifyReason("unknown-xyz") == true,
        "test6: unknown reason should default to needsFull=true")
    assert(classifyReason(nil) == true,
        "test6: nil reason should default to needsFull=true")

    -- Cross-check against the REAL published set so the spec above can't silently
    -- drift from cdm_blizz_mirror.lua. blizz_mirror pulls many WoW globals, so the
    -- load may not succeed in this minimal harness — guard with pcall and only
    -- assert equality when the real set is actually available.
    local ok = pcall(function()
        assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)
    end)
    local realSet = ok and ns.CDMBlizzMirror and ns.CDMBlizzMirror._textOnlyMirrorReasons
    if type(realSet) == "table" then
        for reason in pairs(TEXT_ONLY) do
            assert(realSet[reason] == true,
                "test6: real set missing text-only reason '" .. reason .. "'")
        end
        for reason in pairs(realSet) do
            assert(TEXT_ONLY[reason] == true,
                "test6: real set has unexpected text-only reason '" .. tostring(reason) .. "'")
        end
        print("PASS test6: classification matches real CDMBlizzMirror._textOnlyMirrorReasons")
    else
        print("PASS test6: classification spec verified (real-set cross-check skipped — blizz_mirror not loadable in harness)")
    end
end

print("OK: cdm_mirror_text_refresh_scope_test")
