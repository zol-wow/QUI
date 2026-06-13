---------------------------------------------------------------------------
-- Bags bank takeover: suppresses Blizzard's BankFrame and owns the bank
-- session (BANKFRAME_OPENED/CLOSED routing to the QUI bank window).
--
-- BankFrame is a UIPanel, not a set of container globals, so the container
-- Takeover model (global swapping) does not generalize. Suppression here =
-- clear the frame's OnEvent/OnShow/OnHide scripts (captured for Revert),
-- then reparent it to a hidden holder. Ordering is load-bearing: the real
-- BankFrameMixin:OnHide calls CloseAllBags(self) AND C_Bank.CloseBankFrame()
-- — scripts must be neutered BEFORE any Hide or the session slams shut.
-- The Banker interaction still runs Blizzard's BankFrame_Open →
-- ShowUIPanel(BankFrame): the panel manager never reparents, so the frame's
-- shown FLAG sets (keeping BankFrame_Open's `not IsShown()` fallback from
-- force-closing the session) while the hidden parent keeps it invisible.
-- The invisible BankFrame deliberately occupies the left UIPanel slot for the
-- session (load-bearing for the ESC truth chain; cosmetic panel-offset accepted).
--
-- Session state machine:
--   Suppress()         login/enable: detach BankFrame once (idempotent)
--   OnBankOpened()     BANKFRAME_OPENED → live; BankWindow.ShowLive();
--                      auto-open bags via Takeover.OpenForFrame
--   OnBankClosed()     BANKFRAME_CLOSED → not live; notify the window;
--                      Takeover.CloseForFrame; clears the closing latch
--   UserClosedWindow() the user closed the bank window while live → ask the
--                      server (C_Bank.CloseBankFrame) ONCE; the `closing`
--                      latch swallows re-entry (chassis onClose fires on ANY
--                      hide) until the echoed BANKFRAME_CLOSED lands
--   Revert()           disable: defensively Hide, restore scripts + parent
--
-- Opener proxy: Takeover.OpenForFrame/CloseForFrame only need GetName()
-- from their frame argument (opener tracking + the autoopen "bank" policy
-- key via FRAME_TO_KEY["QUI_BankWindow"]), so a stable name-carrying proxy
-- is passed instead of the real window frame — no load-order or frame
-- dependency on BankWindow. The internal calls deliberately bypass the
-- (un-replaced, Blizzard-owned) globals: routing through _G would open the
-- hidden Blizzard container frames for no benefit.
--
-- Taint note: BankFrame is not protected; setting its scripts from insecure
-- code follows the established detach-once precedent (chat model).
---------------------------------------------------------------------------
-- luacheck: read globals BankFrame
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local BankTakeover = {}
Bags.BankTakeover = BankTakeover

local suppressed = false
local live = false             -- a banker session is open
local closing = false          -- our CloseBankFrame is in flight (echo guard)
local capturedScripts = nil    -- scriptName → original handler (nil slots kept)
local capturedParent = nil
local hiddenHolder = nil

-- OnEvent is nil on the live client (PlayerInteractionFrameManager routes
-- the Banker interaction to BankFrame_Open, not a frame event handler) but
-- is cleared anyway: defensive against future Blizzard wiring.
local SCRIPT_NAMES = { "OnEvent", "OnShow", "OnHide" }

-- Name-carrying stand-in for the bank window (see header).
local BANK_OPENER = { GetName = function() return "QUI_BankWindow" end }

function BankTakeover.IsLive()
    return live
end

function BankTakeover.Suppress()
    if suppressed then return end
    local bankFrame = BankFrame
    if not bankFrame then return end -- LoD safety: nothing to suppress yet
    suppressed = true

    capturedScripts = {}
    for _, name in ipairs(SCRIPT_NAMES) do
        capturedScripts[name] = bankFrame:GetScript(name)
        bankFrame:SetScript(name, nil)
    end
    -- Hide AFTER neutering (the original OnHide must not fire) — defensive
    -- for a mid-session enable while the Blizzard bank UI is up.
    bankFrame:Hide()

    if not hiddenHolder then
        hiddenHolder = Bags.TakeoverShared.MakeHiddenHolder()
    end
    capturedParent = bankFrame:GetParent()
    bankFrame:SetParent(hiddenHolder)
end

function BankTakeover.OnBankOpened()
    live = true
    Bags.BankWindow.ShowLive()
    -- Opener parity with Blizzard's BankFrame OnShow + the autoopen "bank"
    -- policy key.
    Bags.Takeover.OpenForFrame(BANK_OPENER)
end

function BankTakeover.OnBankClosed()
    closing = false -- our echo landed (or the close was server-driven)
    live = false
    Bags.BankWindow.OnBankClosed()
    Bags.Takeover.CloseForFrame(BANK_OPENER)
end

function BankTakeover.UserClosedWindow()
    -- Routes a USER close of a live session to the server; the resulting
    -- BANKFRAME_CLOSED then runs OnBankClosed. The latch keeps a second
    -- hide (chassis onClose fires on ANY hide) from double-calling.
    if not live or closing then return end
    closing = true
    C_Bank.CloseBankFrame()
end

function BankTakeover.Revert()
    if not suppressed then return end
    suppressed = false

    -- Belt-and-braces: if a banker session is somehow still live with no
    -- close in flight, end it server-side — reverting with the session open
    -- would strand it (the restored Blizzard BankFrame is hidden, so its
    -- OnHide close never fires). Callers are expected to Hide the bank
    -- window FIRST (its onClose routes UserClosedWindow, latching `closing`),
    -- so the latch keeps this from double-sending in the normal disable path.
    if live and not closing then
        C_Bank.CloseBankFrame()
    end

    local bankFrame = BankFrame
    if bankFrame then
        -- Hide while the scripts are still cleared: Blizzard's ShowUIPanel
        -- may have set the shown flag during suppression, and restoring the
        -- parent with that flag set would pop a live Blizzard frame open
        -- (and fire its OnShow/OnHide).
        bankFrame:Hide()
        if capturedScripts then
            for _, name in ipairs(SCRIPT_NAMES) do
                bankFrame:SetScript(name, capturedScripts[name])
            end
        end
        if capturedParent then
            bankFrame:SetParent(capturedParent)
        end
    end
    capturedScripts = nil
    capturedParent = nil
    live = false
    closing = false
end
