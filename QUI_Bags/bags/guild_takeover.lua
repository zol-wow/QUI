---------------------------------------------------------------------------
-- Bags guild-bank takeover: suppresses Blizzard's GuildBankFrame and owns
-- the guild-bank session. The session open/close triggers are the
-- GuildBanker PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE events (the retail
-- path — GUILDBANKFRAME_OPENED/CLOSED have no mainline FrameXML consumer
-- and do not fire at the vault; only classic-era UIParent uses them), with
-- the legacy events kept as redundant latched triggers. Both route to the
-- scanner + the QUI guild window via OnOpened/OnClosed.
--
-- Clones bank_takeover's suppression model (clear scripts, Hide, reparent
-- to a hidden holder) with one structural addition: Blizzard_GuildBankUI is
-- LOAD-ON-DEMAND, so GuildBankFrame does not exist at login. Init() checks
-- whether the addon is already loaded (enable-after-visit, /reload at the
-- vault) and suppresses immediately; otherwise it arms a pending state and
-- bags.lua forwards ADDON_LOADED(arg1) here to complete the suppression the
-- moment the LoD addon materializes.
--
-- Script-clearing differences vs BankFrame (vendored Blizzard_GuildBankUI):
--   * OnEvent is LIVE the moment the addon loads — GuildBankFrameMixin:
--     OnLoad registers 11 events (GUILDBANKBAGSLOTS_CHANGED etc., lines
--     18-28), unlike BankFrame whose interaction routes through
--     PlayerInteractionFrameManager with no frame OnEvent. It must be
--     cleared or the hidden frame keeps reacting to vault traffic.
--   * OnHide calls CloseGuildBankFrame() (line 129) — scripts must be
--     neutered BEFORE any Hide or the session slams shut (Phase-3 ordering
--     lesson, same shape as BankFrame's OnHide → C_Bank.CloseBankFrame()).
-- The GuildBanker interaction still runs PlayerInteractionFrameManager →
-- GuildBankFrame_LoadUI + ShowUIPanel(GuildBankFrame): the panel manager
-- never reparents, so the frame's shown FLAG sets while the hidden parent
-- keeps it invisible. The invisible GuildBankFrame deliberately occupies
-- its UIPanel slot for the session — a DOUBLEWIDE one (UIPanelWindows
-- ["GuildBankFrame"] = { area = "doublewide", width = 793 }) — load-bearing
-- for the ESC truth chain; cosmetic panel-offset accepted (Phase-3
-- precedent, just wider).
--
-- Session state machine:
--   Init()             enable: suppress now (addon loaded) or arm pending
--   OnAddonLoaded(n)   ADDON_LOADED forward: complete a pending suppression
--   OnOpened()         GUILDBANKFRAME_OPENED → live; scanner pump FIRST
--                      (QueryGuildBankTab calls start the server streaming
--                      the data the window renders), then the guild window,
--                      then auto-open bags via Takeover.OpenForFrame
--   OnClosed()         GUILDBANKFRAME_CLOSED → not live; scanner session
--                      closed; window notified; Takeover.CloseForFrame;
--                      latch cleared
--   UserClosedWindow() user closed the guild window while live → ask the
--                      server (CloseGuildBankFrame) ONCE; the `closing`
--                      latch swallows re-entry (chassis onClose fires on
--                      ANY hide) until the echoed CLOSED lands
--   Revert()           disable: defensively Hide, restore scripts + parent,
--                      disarm pending (a disabled takeover must not act on
--                      a later ADDON_LOADED)
--
-- Opener proxy: Takeover.OpenForFrame/CloseForFrame only need GetName()
-- from their frame argument (opener tracking + the autoopen "guildBank"
-- policy key via FRAME_TO_KEY["QUI_GuildBankWindow"]), so a stable
-- name-carrying proxy is passed instead of the real window frame — no
-- load-order or frame dependency on GuildWindow. The internal calls bypass
-- the (un-replaced, Blizzard-owned) globals — see bank_takeover.lua.
--
-- Taint note: GuildBankFrame is not protected; setting its scripts from
-- insecure code follows the established detach-once precedent (chat model).
---------------------------------------------------------------------------
-- luacheck: read globals GuildBankFrame CloseGuildBankFrame
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local GuildTakeover = {}
Bags.GuildTakeover = GuildTakeover

local LOD_ADDON = "Blizzard_GuildBankUI"

local suppressed = false
local pending = false          -- enabled, waiting for the LoD addon to load
local live = false             -- a guild-banker session is open
local closing = false          -- our CloseGuildBankFrame is in flight (echo guard)
local capturedScripts = nil    -- scriptName → original handler
local capturedParent = nil
local hiddenHolder = nil

local SCRIPT_NAMES = { "OnEvent", "OnShow", "OnHide" }

-- Name-carrying stand-in for the guild window (see header).
local GUILD_OPENER = { GetName = function() return "QUI_GuildBankWindow" end }

function GuildTakeover.IsLive()
    return live
end

function GuildTakeover.Init()
    -- C_AddOns.IsAddOnLoaded(name) → loadedOrLoading, loaded (verified in
    -- AddOnsDocumentation); guard both spellings for client drift.
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(LOD_ADDON))
        or (IsAddOnLoaded and IsAddOnLoaded(LOD_ADDON))
    if loaded then
        GuildTakeover.SuppressNow()
    end
    -- Not latched (addon unloaded, or "loading" with no frame yet): arm the
    -- pending state so the ADDON_LOADED forward completes the suppression.
    if not suppressed then
        pending = true
    end
end

function GuildTakeover.OnAddonLoaded(name)
    if name ~= LOD_ADDON or not pending then return end
    pending = false
    GuildTakeover.SuppressNow()
end

function GuildTakeover.SuppressNow()
    if suppressed then return end
    local guildBankFrame = GuildBankFrame
    if not guildBankFrame then return end -- LoD safety: nothing to suppress yet
    suppressed = true

    capturedScripts = {}
    for _, name in ipairs(SCRIPT_NAMES) do
        capturedScripts[name] = guildBankFrame:GetScript(name)
        guildBankFrame:SetScript(name, nil)
    end
    -- Hide AFTER neutering: the real OnHide calls CloseGuildBankFrame() —
    -- a live OnHide here would slam an open vault session shut (mid-session
    -- enable while the Blizzard guild bank UI is up).
    guildBankFrame:Hide()

    if not hiddenHolder then
        hiddenHolder = Bags.TakeoverShared.MakeHiddenHolder()
    end
    capturedParent = guildBankFrame:GetParent()
    guildBankFrame:SetParent(hiddenHolder)
end

function GuildTakeover.OnOpened()
    -- Latched: the session open has TWO triggers — the GuildBanker
    -- interaction SHOW (the retail path; GUILDBANKFRAME_OPENED has no
    -- mainline consumer and was observed NOT to fire at the vault) plus the
    -- legacy event kept as a redundant trigger — so a build where both fire
    -- must not double-pump the scanner or double-open.
    if live then return end
    live = true
    -- The scan session is driven by the core collector (it hears the same
    -- GuildBanker interaction edge and runs OnGuildBankOpened's QueryGuildBankTab
    -- loop, which starts the server streaming GUILDBANKBAGSLOTS_CHANGED). The
    -- window renders cache + fresh data as the streamed slots drain.
    Bags.GuildWindow.ShowLive()
    -- Opener parity with Blizzard's GuildBankFrame session + the autoopen
    -- "guildBank" policy key.
    Bags.Takeover.OpenForFrame(GUILD_OPENER)
end

function GuildTakeover.OnClosed()
    -- Same dual-trigger latch as OnOpened (CLOSED + interaction HIDE):
    -- `closing` is only ever set while live, so a not-live close has
    -- nothing to do.
    if not live then return end
    closing = false -- our echo landed (or the close was server-driven)
    live = false
    -- The core collector owns the scan session and closes it on the same
    -- GuildBanker interaction-HIDE edge; the window just tears down here.
    Bags.GuildWindow.OnBankClosed()
    Bags.Takeover.CloseForFrame(GUILD_OPENER)
end

function GuildTakeover.UserClosedWindow()
    -- Routes a USER close of a live session to the server; the resulting
    -- GUILDBANKFRAME_CLOSED then runs OnClosed. The latch keeps a second
    -- hide (chassis onClose fires on ANY hide) from double-calling.
    if not live or closing then return end
    closing = true
    CloseGuildBankFrame()
end

function GuildTakeover.Revert()
    -- Disarm pending unconditionally: a takeover disabled before the vault
    -- was ever visited must not suppress on a later ADDON_LOADED.
    pending = false
    if not suppressed then return end
    suppressed = false

    -- Belt-and-braces: if a vault session is somehow still live with no
    -- close in flight, end it server-side — reverting with the session open
    -- would strand it (the restored Blizzard GuildBankFrame is hidden, so
    -- its OnHide close never fires). Callers are expected to Hide the guild
    -- window FIRST (its onClose routes UserClosedWindow, latching
    -- `closing`), so the latch keeps this from double-sending in the normal
    -- disable path.
    if live and not closing then
        CloseGuildBankFrame()
    end

    local guildBankFrame = GuildBankFrame
    if guildBankFrame then
        -- Hide while the scripts are still cleared AND before reparenting:
        -- ShowUIPanel may have set the shown flag during suppression, and
        -- restoring the parent with that flag set would pop a live Blizzard
        -- frame open (and fire its OnShow/OnHide).
        guildBankFrame:Hide()
        if capturedScripts then
            for _, name in ipairs(SCRIPT_NAMES) do
                guildBankFrame:SetScript(name, capturedScripts[name])
            end
        end
        if capturedParent then
            guildBankFrame:SetParent(capturedParent)
        end
    end
    capturedScripts = nil
    capturedParent = nil
    live = false
    closing = false
end
