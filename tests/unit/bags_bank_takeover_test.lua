-- tests/unit/bags_bank_takeover_test.lua
-- Run: lua tests/unit/bags_bank_takeover_test.lua
-- Bank session state machine: BankFrame suppression (script neutering +
-- reparent to a hidden holder), BANKFRAME_OPENED/CLOSED routing to the bank
-- window, and the user-close -> C_Bank.CloseBankFrame echo guard.
--
-- Verified against the vendored Blizzard_UIPanels_Game/Mainline/BankFrame.lua:
--   OnShow -> OpenAllBags(self)
--   OnHide -> CloseAllBags(self) AND C_Bank.CloseBankFrame()
-- which is exactly why the suppression must clear the scripts BEFORE any
-- Hide (a live OnHide would slam the bank session shut) and why the
-- takeover replicates the open/close calls itself (via the Takeover's
-- internal OpenForFrame/CloseForFrame, not the Blizzard globals). BankFrame
-- has NO OnEvent in the live client (PlayerInteractionFrameManager routes
-- the Banker interaction to BankFrame_Open), so the OnEvent slot here is
-- nil — the capture/restore must round-trip a nil slot, not just functions.
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- BankFrame fake: script slots + parent, recording every mutation. Hide()
-- checks whether OnHide is still wired at hide time (ordering truth).
local origOnShow = function() end
local origOnHide = function() end
local bankFrame = {
    _scripts = { OnShow = origOnShow, OnHide = origOnHide }, -- OnEvent nil (live-client truth)
    _parent = "UIParent",
    _hideCount = 0,
    _hiddenWithLiveOnHide = false,
}
function bankFrame.GetScript(self, name) return self._scripts[name] end
function bankFrame.SetScript(self, name, fn) self._scripts[name] = fn end
function bankFrame.GetParent(self) return self._parent end
function bankFrame.SetParent(self, p) self._parent = p end
function bankFrame.Hide(self)
    self._hideCount = self._hideCount + 1
    if self._scripts.OnHide then self._hiddenWithLiveOnHide = true end
end

-- Hidden-holder factory: record every holder created so reparent targets
-- and holder reuse are assertable.
local holders = {}
_G.CreateFrame = function()
    local holder = {
        _shown = true,
        SetSize = function() end,
        SetPoint = function() end,
        Hide = function(self) self._shown = false end,
        Show = function(self) self._shown = true end,
    }
    holders[#holders + 1] = holder
    return holder
end

local openLog, closeLog = {}, {}

local closeBankCalls = 0
_G.C_Bank.CloseBankFrame = function() closeBankCalls = closeBankCalls + 1 end

local ns = loader.LoadAll()

-- Takeover internal open/close API (bank routes through it, NOT the
-- Blizzard-owned globals): log the GetName() of the opener argument.
ns.Bags.Takeover = {
    OpenForFrame = function(frame)
        openLog[#openLog + 1] = frame and frame.GetName and frame:GetName() or "<no-name>"
    end,
    CloseForFrame = function(frame)
        closeLog[#closeLog + 1] = frame and frame.GetName and frame:GetName() or "<no-name>"
    end,
}

local windowLog = {}
ns.Bags.BankWindow = {
    ShowLive = function() windowLog[#windowLog + 1] = "showlive" end,
    OnBankClosed = function() windowLog[#windowLog + 1] = "onbankclosed" end,
}

local chunk = assert(loadfile("QUI_Bags/bags/bank_takeover.lua"))
chunk("QUI", ns)
local BankTakeover = ns.Bags.BankTakeover

-- Test 1: Suppress reparents + clears scripts, captures for Revert.
-- LoD-safety prelude: no BankFrame yet -> no-op that must NOT latch the
-- suppressed state (a later call with the frame present still works).
_G.BankFrame = nil
BankTakeover.Suppress()
assert(#holders == 0, "no holder may be created while BankFrame is absent")
_G.BankFrame = bankFrame

BankTakeover.Suppress()
assert(bankFrame:GetScript("OnShow") == nil, "Suppress must clear OnShow")
assert(bankFrame:GetScript("OnHide") == nil, "Suppress must clear OnHide")
assert(bankFrame:GetScript("OnEvent") == nil, "Suppress must clear OnEvent")
assert(bankFrame._hideCount == 1, "Suppress must Hide the frame (mid-session enable)")
assert(bankFrame._hiddenWithLiveOnHide == false,
    "scripts must be cleared BEFORE Hide (the real OnHide calls C_Bank.CloseBankFrame)")
assert(#holders == 1, "exactly one hidden holder")
assert(holders[1]._shown == false, "the holder must be hidden")
assert(bankFrame._parent == holders[1], "BankFrame must be reparented to the holder")
-- Idempotence: a second Suppress must not re-capture (it would capture the
-- now-nil scripts and destroy Revert) and must not act again.
BankTakeover.Suppress()
assert(#holders == 1, "idempotent Suppress must not create a second holder")
assert(bankFrame._hideCount == 1, "idempotent Suppress must not Hide again")
assert(BankTakeover.IsLive() == false, "not live before BANKFRAME_OPENED")

-- Test 2: BANKFRAME_OPENED -> live + window shown + OpenAllBags(opener)
BankTakeover.OnBankOpened()
assert(BankTakeover.IsLive() == true, "OPENED must set live")
assert(windowLog[#windowLog] == "showlive", "OPENED must call BankWindow.ShowLive")
assert(#openLog == 1 and openLog[1] == "QUI_BankWindow",
    "OpenForFrame must receive a QUI_BankWindow-named opener (policy key + opener tracking)")

-- Test 3: BANKFRAME_CLOSED (server-driven) -> window notified + CloseAllBags
BankTakeover.OnBankClosed()
assert(BankTakeover.IsLive() == false, "CLOSED must clear live")
assert(windowLog[#windowLog] == "onbankclosed", "CLOSED must call BankWindow.OnBankClosed")
assert(#closeLog == 1 and closeLog[1] == "QUI_BankWindow",
    "CloseForFrame must receive the QUI_BankWindow-named opener")
assert(closeBankCalls == 0, "a server-driven close must NOT call C_Bank.CloseBankFrame")

-- Test 4: user-close while live -> CloseBankFrame EXACTLY once; the echoed
-- BANKFRAME_CLOSED must not re-call it; the closing latch must then reset.
BankTakeover.OnBankOpened()
BankTakeover.UserClosedWindow()
assert(closeBankCalls == 1, "user close must call C_Bank.CloseBankFrame exactly once")
BankTakeover.UserClosedWindow() -- chassis onClose fires on ANY hide: re-entry guard
assert(closeBankCalls == 1, "the closing latch must swallow a re-entrant user close")
BankTakeover.OnBankClosed() -- the server echo of our CloseBankFrame
assert(closeBankCalls == 1, "the echoed BANKFRAME_CLOSED must not re-call CloseBankFrame")
assert(BankTakeover.IsLive() == false, "echoed CLOSED must clear live")
assert(windowLog[#windowLog] == "onbankclosed", "echoed CLOSED still notifies the window")
-- next session: the latch must have reset
BankTakeover.OnBankOpened()
BankTakeover.UserClosedWindow()
assert(closeBankCalls == 2, "the closing latch must reset once the close lands")
BankTakeover.OnBankClosed()

-- Test 5: user-close while NOT live -> CloseBankFrame NOT called
assert(BankTakeover.IsLive() == false, "precondition: not live")
BankTakeover.UserClosedWindow()
assert(closeBankCalls == 2, "user close while not live must NOT call CloseBankFrame")

-- Test 6: Revert restores scripts + parent; idempotent; cycle-safe
local hidesBeforeRevert = bankFrame._hideCount
BankTakeover.Revert()
assert(bankFrame._hideCount == hidesBeforeRevert + 1,
    "Revert must defensively Hide (Blizzard may have set the shown flag while suppressed)")
assert(bankFrame._hiddenWithLiveOnHide == false,
    "Revert's Hide must run while the scripts are still cleared")
assert(bankFrame:GetScript("OnShow") == origOnShow, "Revert must restore the exact OnShow")
assert(bankFrame:GetScript("OnHide") == origOnHide, "Revert must restore the exact OnHide")
assert(bankFrame:GetScript("OnEvent") == nil, "OnEvent must round-trip its nil slot")
assert(bankFrame._parent == "UIParent", "Revert must restore the original parent")
-- idempotence
BankTakeover.Revert()
assert(bankFrame._hideCount == hidesBeforeRevert + 1, "second Revert must be a no-op")
assert(bankFrame:GetScript("OnShow") == origOnShow, "second Revert must not clobber scripts")
assert(bankFrame._parent == "UIParent", "second Revert must not touch the parent")
-- a full re-Suppress/Revert cycle still works after Revert
BankTakeover.Suppress()
assert(bankFrame:GetScript("OnShow") == nil, "re-Suppress after Revert must clear scripts")
assert(bankFrame._parent == holders[1], "re-Suppress must reuse the cached holder")
assert(#holders == 1, "no new holder on re-Suppress")
BankTakeover.Revert()
assert(bankFrame:GetScript("OnShow") == origOnShow, "second cycle must restore scripts")
assert(bankFrame._parent == "UIParent", "second cycle must restore the parent")

-- Test 7: Revert while a session is still live (belt-and-braces) must end
-- it server-side exactly once — reverting with the session open would
-- strand it (the restored Blizzard BankFrame is hidden; its OnHide close
-- never fires). With a user close already in flight (closing latch), Revert
-- must NOT double-send.
BankTakeover.Suppress()
BankTakeover.OnBankOpened()
local callsBeforeLiveRevert = closeBankCalls
BankTakeover.Revert()
assert(closeBankCalls == callsBeforeLiveRevert + 1,
    "Revert with a live session must call C_Bank.CloseBankFrame")
assert(BankTakeover.IsLive() == false, "Revert must clear live")
BankTakeover.Suppress()
BankTakeover.OnBankOpened()
BankTakeover.UserClosedWindow() -- close in flight: closing latched
local callsBeforeLatchedRevert = closeBankCalls
BankTakeover.Revert()
assert(closeBankCalls == callsBeforeLatchedRevert,
    "Revert must not re-send a close already in flight (closing latch)")
assert(BankTakeover.IsLive() == false, "Revert must clear live even with a close in flight")

print("OK: bags_bank_takeover_test")
