-- tests/unit/bags_takeover_test.lua
-- Run: lua tests/unit/bags_takeover_test.lua
-- Models the REAL Blizzard nested call graph: stub ToggleBackpack calls the
-- GLOBAL ToggleBag(0)/CloseAllBags by name, exactly like the live client.
-- Under the old hook design those nested calls were intercepted too and a
-- single B press double-fired; the full-replacement design must toggle the
-- window EXACTLY once per press.
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

-- Blizzard global stubs with the real nested call structure.
local log = {}
local backpackOpen = false
_G.ToggleAllBags = function() log[#log + 1] = "blizz-toggleall" end
_G.OpenAllBags = function() log[#log + 1] = "blizz-openall" end
_G.CloseAllBags = function() log[#log + 1] = "blizz-closeall" end
_G.ToggleBag = function(id) log[#log + 1] = "blizz-bag" .. id end
_G.OpenBag = function(id) log[#log + 1] = "blizz-openbag" .. id end
_G.CloseBag = function(id) log[#log + 1] = "blizz-closebag" .. id end
_G.OpenBackpack = function() log[#log + 1] = "blizz-openbackpack" end
_G.CloseBackpack = function() log[#log + 1] = "blizz-closebackpack" end
_G.ToggleBackpack = function()
    log[#log + 1] = "blizz-backpack"
    -- nested internal calls BY GLOBAL NAME (live-client behavior)
    if backpackOpen then _G.CloseAllBags() else _G.ToggleBag(0) end
    backpackOpen = not backpackOpen
end
_G.OpenAllBagsMatchingContext = function() log[#log + 1] = "blizz-openallmatching"; return 0 end

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

-- Test 1: Apply replaces all ten globals and hides-then-reparents frames
Takeover.Apply()
assert(Takeover.IsActive(), "takeover should be active")
for _, name in ipairs(GLOBALS) do
    assert(_G[name] ~= stubs[name], name .. " must be replaced")
end
for fname, f in pairs(frames) do
    assert(f._hidden == true, fname .. " must be Hide()-d before reparenting")
    assert(f._parent ~= "orig", fname .. " must be reparented to the holder")
end

-- Test 2: ONE B-press semantics (C1 regression — hooks double-fired here)
local blizzCalls = #log
assert(shown == false, "window starts hidden")
local presses = #windowLog
_G.ToggleBackpack()
assert(shown == true, "one B press must open the window")
assert(#windowLog == presses + 1, "exactly ONE window op per press (no nested double-fire)")
_G.ToggleBackpack()
assert(shown == false, "second B press must close the window")
assert(#log == blizzCalls, "Blizzard bodies must never run while takeover is active")

-- Test 3: ESC chain truth (C2 — CloseAllWindows needs a real boolean)
_G.OpenAllBags()
assert(shown == true, "manual OpenAllBags must open")
assert(_G.CloseAllBags() == true, "CloseAllBags must return true when it closed something")
assert(_G.CloseAllBags() == false, "CloseAllBags must return false when already hidden")

-- Test 4: opener tracking (I1 — programmatic close requires opener match)
local merchantFrame = { GetName = function() return "MerchantFrame" end }
local mailFrame = { GetName = function() return "MailFrame" end }
_G.OpenAllBags() -- user opens manually (opener = nil)
assert(shown == true, "manual open")
assert(_G.CloseAllBags(merchantFrame) == false,
    "merchant close against user-opened bags must fail")
assert(shown == true, "window must STAY shown after mismatched programmatic close")
_G.OpenAllBags(merchantFrame) -- already open: must NOT re-record the opener
assert(_G.CloseAllBags(merchantFrame) == false,
    "open-while-shown must not re-record the opener (Blizzard parity)")
assert(shown == true, "window still shown")
assert(_G.CloseAllBags() == true, "manual close always succeeds")
_G.OpenAllBags(merchantFrame) -- programmatic open (policy=true) records opener
assert(shown == true, "programmatic open with policy=true must open")
assert(_G.CloseAllBags(mailFrame) == false,
    "mismatched closer must fail against merchant-opened bags")
assert(shown == true, "window must survive the mismatched closer")
assert(_G.CloseAllBags(merchantFrame) == true,
    "matching closer must close merchant-opened bags")
assert(shown == false, "window closed by matching closer")

-- Test 5: auto-open policy gates programmatic opens only
ns.Bags.AutoOpen.ShouldOpenFor = function() return false end
_G.OpenAllBags(merchantFrame)
assert(shown == false, "policy=false must suppress programmatic open")
_G.OpenAllBags() -- manual (no frame): always opens
assert(shown == true, "manual open must ignore policy")
_G.CloseAllBags()
ns.Bags.AutoOpen.ShouldOpenFor = function() return true end

-- Test 6: OpenAllBagsMatchingContext — the tenth global. ItemButtonUtil.
-- OpenAndFilterBags (keystone/enchant/item-upgrade UIs) uses the returned
-- open count to decide whether the context frame closes bags on hide.
assert(shown == false, "precondition: window hidden")
assert(_G.OpenAllBagsMatchingContext(merchantFrame) == 1,
    "matching-context open from hidden must open and report 1")
assert(shown == true, "matching-context open must show the window")
assert(_G.OpenAllBagsMatchingContext(merchantFrame) == 0,
    "matching-context open while already shown must report 0")
assert(_G.CloseAllBags(merchantFrame) == true,
    "matching-context open must record the opener (context frame may close)")
ns.Bags.AutoOpen.ShouldOpenFor = function() return false end
assert(_G.OpenAllBagsMatchingContext(merchantFrame) == 0,
    "policy=false must suppress the matching-context open and report 0")
assert(shown == false, "window must stay hidden under policy=false")
ns.Bags.AutoOpen.ShouldOpenFor = function() return true end

-- Test 7: CloseBag/CloseBackpack propagate CloseAllBags' boolean (ESC/
-- CloseAllWindows chain truth applies to the per-bag entry points too)
_G.OpenAllBags()
assert(shown == true, "precondition: window shown")
assert(_G.CloseBag(1) == true, "CloseBag must return CloseAllBags' boolean (closed)")
assert(_G.CloseBag(1) == false, "CloseBag must return false when already hidden")
_G.OpenBackpack()
assert(_G.CloseBackpack() == true, "CloseBackpack must return CloseAllBags' boolean (closed)")
assert(_G.CloseBackpack() == false, "CloseBackpack must return false when already hidden")

-- Test 8: Revert restores originals exactly and hands back clean frames
for _, f in pairs(frames) do f._hidden = false end -- watch for the defensive Hide
Takeover.Revert()
assert(not Takeover.IsActive(), "takeover should be inactive")
for _, name in ipairs(GLOBALS) do
    assert(_G[name] == stubs[name], name .. " must be restored to the exact original")
end
for fname, f in pairs(frames) do
    assert(f._hidden == true, fname .. " must be Hide()-d on revert")
    assert(f._parent == "orig", fname .. " parent must be restored")
end
local windowOps = #windowLog
_G.ToggleBackpack()
assert(log[#log] == "blizz-bag0", "reverted ToggleBackpack must run Blizzard's nested body")
assert(#windowLog == windowOps, "reverted toggles must not touch the window")



-- Test 9: enable → disable → ANOTHER addon takes the global → enable →
-- disable must restore the CURRENT pre-QUI owner, not the first-ever
-- snapshot (originals must re-capture on every Apply).
local foreign = function() return "foreign-open" end
_G.OpenAllBags = foreign
Takeover.Apply()
assert(_G.OpenAllBags ~= foreign, "apply must swap the foreign global too")
Takeover.Revert()
assert(_G.OpenAllBags == foreign,
    "revert must restore the current pre-QUI owner, not the first-ever snapshot")

-- Test 10: a global overwritten by another addon WHILE QUI is active must
-- survive Revert (restore only the globals that still point at our wrappers).
Takeover.Apply()
local lateOwner = function() return "late-owner" end
_G.ToggleAllBags = lateOwner
Takeover.Revert()
assert(_G.ToggleAllBags == lateOwner,
    "revert must leave a newer foreign owner intact")
assert(_G.OpenAllBags == foreign,
    "globals still pointing at our wrappers must restore normally")
print("OK: bags_takeover_test")
