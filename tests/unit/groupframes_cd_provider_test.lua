-- tests/unit/groupframes_cd_provider_test.lua
-- Run: lua tests/unit/groupframes_cd_provider_test.lua
--
-- Behavioral test for the external cooldown-tracker frame-provider adapter.
-- Installs a mock WoW environment, loads the adapter, drives events, and
-- asserts registration / party-only GetFrames / debounced refresh behavior.

local ADAPTER_PATH = "QUI_GroupFrames/groupframes/groupframes_cdprovider.lua"

--=========================================================================
-- Mock WoW environment
--=========================================================================

-- C_Timer.After captures callbacks (test flushes manually to simulate frames).
local timerQueue = {}
_G.C_Timer = { After = function(_, fn) timerQueue[#timerQueue + 1] = fn end }
local function flushTimers()
    local q = timerQueue
    timerQueue = {}
    for _, fn in ipairs(q) do fn() end
end

-- hooksecurefunc: chain a post-hook onto a table method so calling the method
-- also fires the hook (matches real semantics closely enough for this test).
local hooks = {}
_G.hooksecurefunc = function(tbl, key, fn)
    assert(type(tbl) == "table" and type(key) == "string" and type(fn) == "function",
        "adapter must hook a table method: hooksecurefunc(tbl, key, fn)")
    hooks[key] = hooks[key] or {}
    hooks[key][#hooks[key] + 1] = fn
    local orig = tbl[key]
    tbl[key] = function(...)
        if orig then orig(...) end
        fn(...)
    end
end

-- CreateFrame: minimal frame capturing events + OnEvent handler.
local lastFrame
local function makeFrame()
    local f = { _events = {} }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:SetScript(which, fn) if which == "OnEvent" then self._script = fn end end
    function f:Fire(event, ...) if self._script then self._script(self, event, ...) end end
    return f
end
_G.CreateFrame = function() lastFrame = makeFrame(); return lastFrame end

-- IsInRaid: test-controlled.
local raidFlag = false
_G.IsInRaid = function() return raidFlag end

-- Fake QUI_GF module (instance 1).
local enabledFlag = true
local QUI_GF = {
    unitFrameMap = {},
    RefreshAllFrames = function() end,
    Disable = function() end,
}
function QUI_GF:IsEnabled() return enabledFlag end

-- Helper: invoke a hooked module method (fires chained post-hook).
local function fireHook(key, ...) return QUI_GF[key](QUI_GF, ...) end

-- Capturing external API. Starts ABSENT (login-first-then-addon-loaded order).
local registerCalls = {}
local capturedProvider
_G.MiniCCApi = nil
local function installExternalApi()
    _G.MiniCCApi = {
        v1 = {
            RegisterFrameProvider = function(_, provider)
                registerCalls[#registerCalls + 1] = provider
                capturedProvider = provider
            end,
        },
    }
end

-- core/safecall.lua stub: silent pcall swallow matches the pre-SafeCall
-- shape this test was written against (Task 3: groupframes_cdprovider.lua's
-- registration + Notify() callback now route through ns.SafeCall).
local function safeCallStub(_policy, fn, ...) return pcall(fn, ...) end
local function safeCallMethodStub(_policy, obj, name, ...)
    return pcall(function(...) return obj[name](obj, ...) end, ...)
end
local safeCallMethodIfPresentStub = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end

local ns = { QUI_GroupFrames = QUI_GF, SafeCall = safeCallStub, SafeCallMethod = safeCallMethodStub, SafeCallMethodIfPresent = safeCallMethodIfPresentStub }

local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

--=========================================================================
-- Load the adapter (instance 1)
--=========================================================================
local chunk = assert(loadfile(ADAPTER_PATH))
chunk("QUI_GroupFrames", ns)
local frame1 = lastFrame

assert(frame1, "adapter must CreateFrame an event driver")
assert(frame1._events["PLAYER_LOGIN"], "must RegisterEvent PLAYER_LOGIN")
assert(frame1._events["ADDON_LOADED"], "must RegisterEvent ADDON_LOADED")
assert(hooks["RefreshAllFrames"], "must hooksecurefunc RefreshAllFrames")
assert(hooks["Disable"], "must hooksecurefunc Disable")

--=========================================================================
-- Order A: API absent at login, appears on a later ADDON_LOADED
--=========================================================================
frame1:Fire("PLAYER_LOGIN")
assert(#registerCalls == 0, "must NOT register while external API absent")

installExternalApi()
frame1:Fire("ADDON_LOADED")
assert(#registerCalls == 1, "must register once API present after ADDON_LOADED")
assert(capturedProvider.Name == "QUI", "provider Name must be 'QUI'")
assert(frame1._events["ADDON_LOADED"] == nil, "must UnregisterEvent ADDON_LOADED after success")

frame1:Fire("ADDON_LOADED")
frame1:Fire("PLAYER_LOGIN")
assert(#registerCalls == 1, "must register at most once per session")

--=========================================================================
-- GetFrames: party-only filtering
--=========================================================================
local pf1, pf2, plf, rf1 = {id="p1a"}, {id="p1b"}, {id="player"}, {id="raid1"}
QUI_GF.unitFrameMap = {
    party1 = { pf1, pf2 },   -- two frames (e.g. spotlight dupe) -> both returned
    player = { plf },
    raid1  = { rf1 },        -- must be filtered out
}

raidFlag, enabledFlag = false, true
local frames = capturedProvider.GetFrames()
assert(#frames == 3, "party+player frames returned (2 party1 + 1 player), got " .. #frames)
assert(has(frames, pf1) and has(frames, pf2) and has(frames, plf), "must include party/player frames")
assert(not has(frames, rf1), "must NOT include raid* frames")

raidFlag = true
assert(#capturedProvider.GetFrames() == 0, "GetFrames must be empty while IsInRaid()")
raidFlag = false

enabledFlag = false
assert(#capturedProvider.GetFrames() == 0, "GetFrames must be empty when group frames disabled")
enabledFlag = true

--=========================================================================
-- Refresh notification: debounce + gating
--=========================================================================
local cbCount = 0
capturedProvider.RegisterRefreshFrames(function() cbCount = cbCount + 1 end)

fireHook("RefreshAllFrames", "roster")
fireHook("RefreshAllFrames", "settings")
assert(cbCount == 0, "callback must be deferred, not synchronous")
flushTimers()
assert(cbCount == 1, "burst of refreshes must coalesce into ONE callback, got " .. cbCount)

fireHook("RefreshAllFrames", "roster")
flushTimers()
assert(cbCount == 2, "a later refresh must fire the callback again")

fireHook("Disable")
flushTimers()
assert(cbCount == 3, "Disable must notify the consumer")

--=========================================================================
-- pcall safety: a throwing consumer callback must not propagate
--=========================================================================
capturedProvider.RegisterRefreshFrames(function() error("boom") end)
fireHook("RefreshAllFrames", "roster")
assert(pcall(flushTimers), "a throwing consumer callback must be swallowed by pcall")

--=========================================================================
-- Order B: API already present at login -> registers on PLAYER_LOGIN
--=========================================================================
local ns2 = { QUI_GroupFrames = {
    unitFrameMap = {}, RefreshAllFrames = function() end, Disable = function() end,
    IsEnabled = function() return true end,
}, SafeCall = safeCallStub, SafeCallMethod = safeCallMethodStub, SafeCallMethodIfPresent = safeCallMethodIfPresentStub }
local before = #registerCalls
assert(loadfile(ADAPTER_PATH))("QUI_GroupFrames", ns2)
local frame2 = lastFrame
frame2:Fire("PLAYER_LOGIN")
assert(#registerCalls == before + 1, "API present at login must register on PLAYER_LOGIN")
assert(frame2._events["ADDON_LOADED"] == nil, "must UnregisterEvent ADDON_LOADED after login registration")

print("OK: groupframes_cd_provider_test")
