-- tests/unit/bags_takeover_test.lua
-- Run: lua tests/unit/bags_takeover_test.lua
-- Models the REAL Blizzard nested call graph: stub bodies call the GLOBAL
-- ToggleBag(0)/CloseAllBags/ToggleBackpack by name, exactly like the live
-- client. The hook design must leave all globals except ToggleAllBags
-- BLIZZARD'S (taint: MailFrame_Show calls OpenAllBags then the restricted
-- PerformEmote — a replaced global taints the secure execution), run the
-- original bodies, and still toggle the QUI window EXACTLY once per press.
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- Blizzard container frame stubs: record Hide() calls and parent.
local frames = {}
local function fakeFrame(name)
    local f = { _name = name, _parent = "orig", _hidden = false }
    function f.Hide(self) self._hidden = true end
    function f.SetParent(self, p) self._parent = p end
    function f.GetParent(self) return self._parent end
    frames[name] = f
    return f
end
for i = 1, 6 do fakeFrame("ContainerFrame" .. i) end
fakeFrame("ContainerFrameCombinedBags")
for k, v in pairs(frames) do _G[k] = v end

-- Faithful hooksecurefunc: post-hook, same args, original's returns kept.
_G.hooksecurefunc = function(name, hook)
    local orig = assert(_G[name], "hooksecurefunc target missing: " .. name)
    _G[name] = function(...)
        local results = { orig(...) }
        hook(...)
        return (table.unpack or unpack)(results)
    end
end

-- debugstack via stock traceback: the stubs call nested globals BY NAME so
-- function names appear in the stack like the live client's debugstack().
_G.debugstack = function() return debug.traceback() end

-- Frame clock: GetTime is constant within a frame; tests advance it
-- between presses like the live client advances per rendered frame.
local now = 100
_G.GetTime = function() return now end
local function nextFrame() now = now + 0.1 end

_G.SetCVarBitfield = function() end
_G.LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG = 42

-- Blizzard global stubs with the real nested call structure (individual-
-- bags mode, the nesting-heavy path: ContainerFrame.lua).
local log = {}
local blizzShown = {} -- bagID → open (the HIDDEN frames' state)
local function anyBlizzShown()
    for _, v in pairs(blizzShown) do if v then return true end end
    return false
end
_G.ToggleAllBags = function() log[#log + 1] = "blizz-toggleall" end
_G.CloseAllBags = function(frame)
    log[#log + 1] = "blizz-closeall"
    local closed = anyBlizzShown()
    for k in pairs(blizzShown) do blizzShown[k] = false end
    return closed
end
_G.ToggleBag = function(id)
    log[#log + 1] = "blizz-bag" .. id
    if blizzShown[id] and id == 0 then
        _G.CloseAllBags()
    else
        blizzShown[id] = not blizzShown[id]
    end
end
_G.OpenBag = function(id)
    log[#log + 1] = "blizz-openbag" .. id
    blizzShown[id] = true
end
_G.CloseBag = function(id) blizzShown[id] = false end
_G.ToggleBackpack = function()
    log[#log + 1] = "blizz-backpack"
    -- nested internal calls BY GLOBAL NAME (live-client behavior)
    if blizzShown[0] then _G.CloseAllBags() else _G.ToggleBag(0) end
end
_G.OpenBackpack = function()
    log[#log + 1] = "blizz-openbackpack"
    if not blizzShown[0] then _G.ToggleBackpack() end
end
_G.CloseBackpack = function() blizzShown[0] = false end
_G.OpenAllBags = function(frame)
    log[#log + 1] = "blizz-openall"
    if anyBlizzShown() then return end
    _G.OpenBackpack()
    for i = 1, 5 do _G.OpenBag(i) end
end
_G.OpenAllBagsMatchingContext = function(frame)
    log[#log + 1] = "blizz-openallmatching"
    return 2 -- pretend two hidden bags matched the item context
end

local GLOBALS = {
    "ToggleAllBags", "OpenAllBags", "CloseAllBags",
    "ToggleBackpack", "ToggleBag", "OpenBag", "CloseBag",
    "OpenBackpack", "CloseBackpack", "OpenAllBagsMatchingContext",
}
local stubs = {}
for _, name in ipairs(GLOBALS) do stubs[name] = _G[name] end

_G.CreateFrame = function()
    return {
        SetSize = function() end,
        SetPoint = function() end,
        Hide = function() end,
        Show = function() end,
    }
end

local ns = loader.LoadAll()

-- Window stub with a REAL shown boolean (toggle semantics depend on it).
local shown = false
local windowLog = {}
ns.Bags.BagWindow = {
    Show = function() shown = true; windowLog[#windowLog + 1] = "show" end,
    Hide = function() shown = false; windowLog[#windowLog + 1] = "hide" end,
    IsShown = function() return shown end,
    Refresh = function() windowLog[#windowLog + 1] = "refresh" end,
}
ns.Bags.AutoOpen = { ShouldOpenFor = function() return true end }

local chunk = assert(loadfile("QUI_Bags/bags/takeover.lua"))
chunk("QUI", ns)
local Takeover = ns.Bags.Takeover

-- Test 1: Apply replaces ONLY ToggleAllBags. Five globals carry a
-- hooksecurefunc wrapper (identity changes, but the ORIGINAL body still
-- runs — asserted by the log in later tests; in the live client the
-- wrapper is secure, which is the whole point), and four are completely
-- untouched. Frames are hidden-then-reparented.
local HOOKED = {
    OpenAllBags = true, CloseAllBags = true, ToggleBackpack = true,
    ToggleBag = true, OpenAllBagsMatchingContext = true, OpenBag = true,
}
Takeover.Apply()
assert(Takeover.IsActive(), "takeover should be active")
assert(_G.ToggleAllBags ~= stubs.ToggleAllBags, "ToggleAllBags must be replaced")
for _, name in ipairs(GLOBALS) do
    if HOOKED[name] then
        assert(_G[name] ~= stubs[name],
            name .. " must carry the hooksecurefunc wrapper")
    elseif name ~= "ToggleAllBags" then
        assert(_G[name] == stubs[name],
            name .. " must be completely untouched (no hook, no swap)")
    end
end
for fname, f in pairs(frames) do
    assert(f._hidden == true, fname .. " must be Hide()-d before reparenting")
    assert(f._parent ~= "orig", fname .. " must be reparented to the holder")
end

-- Test 2: ONE TOGGLEBACKPACK press = ONE window op, and Blizzard's body
-- RUNS (nested ToggleBag(0) fires both hooks; stack filter + same-GetTime
-- debounce must collapse them).
nextFrame()
assert(shown == false, "window starts hidden")
local presses = #windowLog
local blizzCalls = #log
_G.ToggleBackpack()
assert(shown == true, "one backpack press must open the window")
assert(#windowLog == presses + 1, "exactly ONE window op per press (no nested double-fire)")
assert(#log > blizzCalls, "Blizzard bodies must RUN under the hook design")
nextFrame()
_G.ToggleBackpack() -- hidden backpack now open → body goes via CloseAllBags
assert(shown == false, "second press must close the window")
assert(#windowLog == presses + 2, "exactly ONE window op for the close press too")

-- Test 3: the OPENALLBAGS binding (B) runs OUR ToggleAllBags — window
-- toggles, Blizzard's ToggleAllBags body never runs.
nextFrame()
blizzCalls = #log
_G.ToggleAllBags()
assert(shown == true, "B press must open the window")
assert(#log == blizzCalls, "our ToggleAllBags must not run Blizzard's body")
nextFrame()
_G.ToggleAllBags()
assert(shown == false, "second B press must close the window")

-- Test 4: the MAILBOX flow — secure MailFrame_Show calls the (Blizzard)
-- OpenAllBags global; its nested OpenBackpack→ToggleBackpack must NOT
-- double-toggle (stack filter), and the hook must open the window once
-- with the opener recorded for close parity.
nextFrame()
local mailFrame = { GetName = function() return "MailFrame" end }
local merchantFrame = { GetName = function() return "MerchantFrame" end }
presses = #windowLog
_G.OpenAllBags(mailFrame)
assert(shown == true, "programmatic OpenAllBags must open the window")
assert(#windowLog == presses + 1,
    "exactly ONE window op for a programmatic open (nested toggles filtered)")
assert(Takeover.CloseForFrame(merchantFrame) == false,
    "mismatched closer must fail against mail-opened bags")
assert(shown == true, "window must survive the mismatched closer")
-- MailFrame_Hide calls CloseAllBags(self) — self is nil there (Blizzard
-- bug-by-design): manual semantics, always closes.
nextFrame()
_G.CloseAllBags()
assert(shown == false, "mail-close CloseAllBags must close the window")

-- Test 5: ESC truth — CloseAllWindows runs CloseAllBags FIRST and the
-- UISpecialFrames sweep AFTER; the hook must SKIP under CloseAllWindows so
-- the sweep (which provides ESC's "something closed" truth) finds the
-- window still shown.
nextFrame()
_G.OpenAllBags()
assert(shown == true, "precondition: window shown")
function _G.CloseAllWindows()
    local bagsVisible = _G.CloseAllBags()
    -- CloseSpecialWindows would hide the window here; the hook must not
    -- have beaten it to it.
    return bagsVisible
end
_G.CloseAllWindows()
assert(shown == true,
    "CloseAllBags under CloseAllWindows must NOT close the window (UISpecialFrames owns ESC)")
ns.Bags.BagWindow.Hide() -- the real sweep's job

-- Test 6: opener tracking parity (programmatic open records, open-while-
-- shown does NOT re-record, matching closer closes).
nextFrame()
_G.OpenAllBags(merchantFrame)
assert(shown == true, "programmatic open with policy=true must open")
nextFrame()
_G.OpenAllBags(mailFrame) -- already open: must NOT re-record the opener
assert(Takeover.CloseForFrame(mailFrame) == false,
    "open-while-shown must not re-record the opener (Blizzard parity)")
assert(shown == true, "window still shown")
assert(Takeover.CloseForFrame(merchantFrame) == true,
    "matching closer must close merchant-opened bags")
assert(shown == false, "window closed by matching closer")

-- Test 7: auto-open policy gates programmatic opens only.
nextFrame()
ns.Bags.AutoOpen.ShouldOpenFor = function() return false end
_G.OpenAllBags(merchantFrame)
assert(shown == false, "policy=false must suppress programmatic open")
nextFrame()
_G.OpenAllBags() -- manual (no frame): always opens
assert(shown == true, "manual open must ignore policy")
nextFrame()
_G.CloseAllBags()
ns.Bags.AutoOpen.ShouldOpenFor = function() return true end

-- Test 8: OpenAllBagsMatchingContext (keystone/enchant/item-upgrade UIs):
-- hook opens the window per policy; Blizzard's return value flows through
-- the hook wrapper untouched (drives the caller's closeBagsOnHide).
nextFrame()
assert(shown == false, "precondition: window hidden")
assert(_G.OpenAllBagsMatchingContext(merchantFrame) == 2,
    "Blizzard's matching-context return value must survive the hook")
assert(shown == true, "matching-context open must show the window")
assert(Takeover.CloseForFrame(merchantFrame) == true,
    "matching-context open must record the opener (context frame may close)")
nextFrame()
ns.Bags.AutoOpen.ShouldOpenFor = function() return false end
_G.OpenAllBagsMatchingContext(merchantFrame)
assert(shown == false, "policy=false must suppress the matching-context open")
ns.Bags.AutoOpen.ShouldOpenFor = function() return true end

-- Test 8b: loot-toast OpenBag — AlertFrameSystems' OnClick handlers call
-- OpenBag(slot) directly; the hook opens the window ONLY when that file is
-- in the stack (a bare OpenBag is OpenAllBagsInternal plumbing).
nextFrame()
assert(shown == false, "precondition: window hidden")
_G.OpenBag(3) -- direct/plumbing call: no toast in the stack
assert(shown == false, "bare OpenBag must not open the window")
function _G.AlertFrameSystems_ToastClick() _G.OpenBag(3) end
_G.AlertFrameSystems_ToastClick()
assert(shown == true, "loot-toast OpenBag must open the window")
nextFrame()
_G.CloseAllBags()
assert(shown == false, "cleanup close")

-- Test 9: ContainerFrame_AllowedToOpenBags=false gates both toggle paths.
nextFrame()
_G.ContainerFrame_AllowedToOpenBags = function() return false end
_G.ToggleAllBags()
assert(shown == false, "B press must respect AllowedToOpenBags")
nextFrame()
_G.ToggleBackpack()
assert(shown == false, "backpack press must respect AllowedToOpenBags")
_G.ContainerFrame_AllowedToOpenBags = nil

-- Test 10: Revert restores ToggleAllBags exactly, hands back clean frames,
-- and the permanent hooks go INERT.
for _, f in pairs(frames) do f._hidden = false end -- watch for the defensive Hide
Takeover.Revert()
assert(not Takeover.IsActive(), "takeover should be inactive")
assert(_G.ToggleAllBags == stubs.ToggleAllBags,
    "ToggleAllBags must be restored to the exact original")
for fname, f in pairs(frames) do
    assert(f._hidden == true, fname .. " must be Hide()-d on revert")
    assert(f._parent == "orig", fname .. " parent must be restored")
end
nextFrame()
local windowOps = #windowLog
_G.ToggleBackpack()
_G.OpenAllBags(merchantFrame)
_G.CloseAllBags()
assert(#windowLog == windowOps, "reverted hooks must not touch the window")
assert(Takeover.OpenForFrame(merchantFrame) == nil and shown == false,
    "OpenForFrame must no-op while inactive")
for k in pairs(blizzShown) do blizzShown[k] = false end

-- Test 11: enable → disable → ANOTHER addon takes ToggleAllBags → enable →
-- disable must restore the CURRENT pre-QUI owner, not the first-ever
-- snapshot (the original re-captures on every Apply).
local foreign = function() return "foreign-toggle" end
_G.ToggleAllBags = foreign
Takeover.Apply()
assert(_G.ToggleAllBags ~= foreign, "apply must swap the foreign global too")
Takeover.Revert()
assert(_G.ToggleAllBags == foreign,
    "revert must restore the current pre-QUI owner, not the first-ever snapshot")

-- Test 12: ToggleAllBags overwritten by another addon WHILE QUI is active
-- must survive Revert (restore only when it still points at our wrapper).
Takeover.Apply()
local lateOwner = function() return "late-owner" end
_G.ToggleAllBags = lateOwner
Takeover.Revert()
assert(_G.ToggleAllBags == lateOwner,
    "revert must leave a newer foreign owner intact")
print("OK: bags_takeover_test")
