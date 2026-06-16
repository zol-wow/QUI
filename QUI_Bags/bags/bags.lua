---------------------------------------------------------------------------
-- QUI Bags Module — entry point.
-- The inventory cache and its event wiring live in core/storage (always
-- on); this file owns the UI lifecycle: takeover, windows, ops, auto-open.
-- `bags.enabled` gates the UI only — disabling hands the bag UI back to
-- Blizzard but collection continues as a core service.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
-- Shared module namespace: sibling data-layer files (loaded before this in
-- bags.xml) publish themselves onto ns.Bags.
local Bags = ns.Bags or {}; ns.Bags = Bags

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local eventFrame = CreateFrame("Frame")
local uiActive = false
local started = false -- post-login startup ran (ns.WhenLoggedIn callback)

--- True while the module is enabled (windows/takeover live). Gate for
--- passive consumers (tooltip counts) whose output must go quiet — not
--- stale — the moment the module is disabled. Collection itself is a core
--- service and keeps running (ns.Storage.IsRunning).
function Bags.IsActive()
    return uiActive
end

local UI_EVENTS = {
    "BANKFRAME_OPENED",                       -- takeover + auto-deposit
    "BANKFRAME_CLOSED",                       -- takeover + deposit-queue cancel
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",  -- auto-open, junk, guild takeover
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "ITEM_LOCK_CHANGED",                      -- live window re-dress
    "BAG_UPDATE_COOLDOWN",
    "EQUIPMENT_SETS_CHANGED",
    "PLAYER_REGEN_DISABLED",                  -- combat hard-stops bag-modifying ops
    "GUILDBANKFRAME_OPENED",                  -- takeover (legacy event)
    "GUILDBANKFRAME_CLOSED",
    "GUILDBANKLOG_UPDATE",                    -- log panel render
    "ADDON_LOADED",                           -- LoD detect → guild takeover arming
}

local function IsEnabled()
    local s = GetSettings()
    return (s and s.enabled) and true or false
end

local function StartUI()
    if uiActive then return end
    uiActive = true
    -- Takeover applies synchronously: a B-press in the deferral window must
    -- not open (then eat) the Blizzard bags. BankTakeover.Suppress shares the
    -- race rationale (a Banker interaction in the window must not show the
    -- Blizzard BankFrame); GuildTakeover.Init must land its suppression
    -- before any guild-banker click when Blizzard_GuildBankUI is already
    -- loaded, else it arms a pending flag and waits for ADDON_LOADED.
    Bags.Takeover.Apply()
    Bags.BankTakeover.Suppress()
    Bags.GuildTakeover.Init()
    ns.RunAfterFirstFrame(function()
        if not uiActive then return end
        for _, ev in ipairs(UI_EVENTS) do eventFrame:RegisterEvent(ev) end
        -- Re-run Init: an ADDON_LOADED inside the deferral window was
        -- unheard; Init is idempotent.
        Bags.GuildTakeover.Init()
        if Bags.NewItems then Bags.NewItems.OnLogin() end
    end, 0.5)
end

local function StopUI()
    if not uiActive then return end
    uiActive = false
    for _, ev in ipairs(UI_EVENTS) do eventFrame:UnregisterEvent(ev) end
    -- Silent stop: Revert is a clean restoration, and profile switches must
    -- not nag. The reload prompt will live on the options module toggle in a
    -- later phase. Collection is a core service and keeps running — disabling
    -- the UI only hands the bag windows back to Blizzard.
    -- Hide BEFORE Revert: the bank and guild-bank windows' onClose must still
    -- see IsLive() so a mid-session disable routes UserClosedWindow to the
    -- appropriate server-side close (C_Bank.CloseBankFrame /
    -- CloseGuildBankFrame) instead of stranding the session open.
    Bags.BagWindow.Hide()
    Bags.BankWindow.Hide()
    Bags.GuildWindow.Hide()
    Bags.SearchWindow.Hide()
    -- ops must not outlive the module: running queues would keep issuing
    -- cursor ops (and a post-close UseContainerItem USES the item)
    if Bags.SortExecutor and Bags.SortExecutor.Cancel then Bags.SortExecutor.Cancel() end
    if Bags.Transfers and Bags.Transfers.Cancel then Bags.Transfers.Cancel() end
    if Bags.Junk and Bags.Junk.OnMerchant then Bags.Junk.OnMerchant(false) end
    -- New-item tracking wipes its session store and goes inert until a
    -- re-enable re-runs the full priming window (items acquired while
    -- disabled must not glow).
    if Bags.NewItems then Bags.NewItems.OnDisable() end
    Bags.Takeover.Revert()
    Bags.BankTakeover.Revert()
    Bags.GuildTakeover.Revert()
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "BANKFRAME_OPENED" then
        Bags.BankTakeover.OnBankOpened()
        if Bags.Transfers and Bags.Transfers.AutoDepositReagentsOnOpen then
            Bags.Transfers.AutoDepositReagentsOnOpen()
        end
    elseif event == "BANKFRAME_CLOSED" then
        -- the deposit queue must not outlive the bank session (a post-close
        -- UseContainerItem would USE the item instead of depositing it)
        if Bags.Transfers and Bags.Transfers.Cancel then Bags.Transfers.Cancel() end
        Bags.BankTakeover.OnBankClosed()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        Bags.AutoOpen.OnInteraction(arg1, true)
        -- Merchant open/close also gates junk selling. Existence-guarded:
        -- unit harnesses load partial module sets.
        if arg1 == Enum.PlayerInteractionType.Merchant and Bags.Junk then
            Bags.Junk.OnMerchant(true)
        elseif arg1 == Enum.PlayerInteractionType.GuildBanker
            and Bags.GuildTakeover then
            -- The RETAIL guild-bank session trigger: GUILDBANKFRAME_OPENED
            -- has no mainline FrameXML consumer (only the classic-era
            -- UIParent registers it) and does not fire at the vault — the
            -- interaction manager event is what drives Blizzard's own
            -- GuildBankFrame. Blizzard's manager handles this same event
            -- first (registered at UI load, before this frame), so the LoD
            -- addon is loaded and the takeover suppression has landed by
            -- the time OnOpened runs. OnOpened is latched: harmless if a
            -- build fires the legacy event too.
            Bags.GuildTakeover.OnOpened()
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        Bags.AutoOpen.OnInteraction(arg1, false)
        if arg1 == Enum.PlayerInteractionType.Merchant and Bags.Junk then
            Bags.Junk.OnMerchant(false)
        elseif arg1 == Enum.PlayerInteractionType.GuildBanker
            and Bags.GuildTakeover then
            -- Session end mirror (walk-away or our CloseGuildBankFrame
            -- echo); latched like OnOpened.
            Bags.GuildTakeover.OnClosed()
        end
    elseif event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN"
        or event == "EQUIPMENT_SETS_CHANGED" then
        -- live lock/cooldown/equipment-set-mark dressing is the window's
        -- concern; cheap full re-render
        if Bags.BagWindow.IsShown() then
            Bags.Bus.Publish("BagsChanged", Bags.Store.GetCurrentCharacterKey(), {})
        end
        -- lock/cooldown re-dress ping
        if Bags.BankWindow.IsShown() then
            Bags.Bus.Publish("BankChanged", Bags.Store.GetCurrentCharacterKey(), {})
            -- warband-scope lock edge: the sort executor's warband scope
            -- listens on WarbandChanged only (shape: eventName, changed)
            Bags.Bus.Publish("WarbandChanged", {})
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat hard-stops bag-modifying ops (the moves aren't protected;
        -- the spec blocks them for UX + lock churn). Existence-guarded:
        -- Transfers lands in the next task, and unit harnesses load partial
        -- module sets.
        if Bags.SortExecutor then Bags.SortExecutor.OnCombat() end
        if Bags.Transfers then Bags.Transfers.OnCombat() end
        if Bags.Junk and Bags.Junk.OnCombat then Bags.Junk.OnCombat() end
    -- ── Guild bank events ──────────────────────────────────────────────
    elseif event == "GUILDBANKFRAME_OPENED" then
        Bags.GuildTakeover.OnOpened()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        Bags.GuildTakeover.OnClosed()
    elseif event == "GUILDBANKLOG_UPDATE" then
        -- Log data arrived after QueryGuildBankLog: re-render the log
        -- panel only while the window is actually showing it.
        if Bags.GuildWindow.IsShown() then
            Bags.GuildWindow.OnLogUpdate()
        end
    elseif event == "ADDON_LOADED" then
        -- Forward every ADDON_LOADED to the guild takeover so it can
        -- complete a pending suppression the moment Blizzard_GuildBankUI
        -- materialises (LoD load-on-demand; GuildBankFrame doesn't exist
        -- at login).
        Bags.GuildTakeover.OnAddonLoaded(arg1)
    end
end)

local function Refresh()
    if not started then return end
    if IsEnabled() then StartUI() else StopUI() end
    if uiActive then
        if Bags.BagWindow.OnProfileChanged then Bags.BagWindow.OnProfileChanged() end
        if Bags.BankWindow.OnProfileChanged then Bags.BankWindow.OnProfileChanged() end
        if Bags.GuildWindow.OnProfileChanged then Bags.GuildWindow.OnProfileChanged() end
        if Bags.SearchWindow.OnProfileChanged then Bags.SearchWindow.OnProfileChanged() end
    end
end

---------------------------------------------------------------------------
-- Keybindings. QUI_Bags/Bindings.xml (auto-discovered by the client next to
-- this sub-addon's TOC — no TOC line needed) calls these exported globals.
-- It loads with the sub-addon, so the binds appear in the Key Bindings UI
-- once QUI_Bags is loaded. IsActive-gated
-- silently: a disabled module has handed the bags back to Blizzard, so the
-- custom binds simply do nothing. BINDING_HEADER_QUIBAGS resolves through
-- the bindings UI's GetBindingCategoryName(_G[cat]) lookup (vendored
-- Blizzard_SettingsDefinitions_Frame/Keybindings.lua:189-197).
---------------------------------------------------------------------------
-- luacheck: globals BINDING_HEADER_QUIBAGS BINDING_NAME_QUI_BAGS_TOGGLE
-- luacheck: globals BINDING_NAME_QUI_BAGS_SEARCH_EVERYWHERE
-- luacheck: globals BINDING_NAME_QUI_BAGS_TOGGLE_BANK BINDING_NAME_QUI_BAGS_TOGGLE_GUILD
-- luacheck: globals QUI_BagsToggle QUI_BagsSearchEverywhere
-- luacheck: globals QUI_BagsToggleBank QUI_BagsToggleGuild
BINDING_HEADER_QUIBAGS = ns.L["QUI Bags"]
BINDING_NAME_QUI_BAGS_TOGGLE = ns.L["Toggle Bags"]
BINDING_NAME_QUI_BAGS_SEARCH_EVERYWHERE = ns.L["Search Everywhere"]
BINDING_NAME_QUI_BAGS_TOGGLE_BANK = ns.L["Toggle Bank (cached anywhere)"]
BINDING_NAME_QUI_BAGS_TOGGLE_GUILD = ns.L["Toggle Guild Bank (cached anywhere)"]

function QUI_BagsToggle()
    if not Bags.IsActive() then return end
    Bags.BagWindow.Toggle()
end

function QUI_BagsSearchEverywhere()
    if not Bags.IsActive() then return end
    Bags.SearchWindow.Toggle()
end

-- Cached-anywhere browsing: shared by /quibags bank|guild, the keybinds and
-- the bag-window header buttons. Prefer the LIVE presentation when the
-- session is actually open (clicking at the banker must not render inert
-- cached buttons against a live session); otherwise the cached browse.
function QUI_BagsToggleBank()
    if not Bags.IsActive() then return end
    if Bags.BankWindow.IsShown() then
        Bags.BankWindow.Hide()
    elseif Bags.BankTakeover and Bags.BankTakeover.IsLive and Bags.BankTakeover.IsLive() then
        Bags.BankWindow.ShowLive()
    else
        Bags.BankWindow.ShowCached()
    end
end

function QUI_BagsToggleGuild()
    if not Bags.IsActive() then return end
    if Bags.GuildWindow.IsShown() then
        Bags.GuildWindow.Hide()
    elseif Bags.GuildTakeover and Bags.GuildTakeover.IsLive and Bags.GuildTakeover.IsLive() then
        Bags.GuildWindow.ShowLive()
    else
        Bags.GuildWindow.ShowCached() -- nil key = current character's guild
    end
end

---------------------------------------------------------------------------
-- Slash command. /quibags toggles the bag window; /quibags search toggles
-- the search-everywhere panel. Gated on the active module: a disabled
-- module has reverted the takeover and hidden its windows — toggling one
-- back up would contradict the Blizzard handoff, so explain instead.
---------------------------------------------------------------------------
-- luacheck: globals SLASH_QUIBAGS1
SLASH_QUIBAGS1 = "/quibags"
SlashCmdList["QUIBAGS"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not Bags.IsActive() then
        print("|cff00ff00QUI:|r the Bags module is disabled (Options → Modules).")
        return
    end
    if msg == "" then
        Bags.BagWindow.Toggle()
    elseif msg == "search" then
        Bags.SearchWindow.Toggle()
    elseif msg == "bank" then
        QUI_BagsToggleBank()
    elseif msg == "guild" then
        QUI_BagsToggleGuild()
    elseif msg == "clearnew" then
        if Bags.NewItems and Bags.NewItems.ClearAllNew then
            Bags.NewItems.ClearAllNew()
        end
    else
        print("|cff00ff00QUI:|r /quibags — toggle the bag window; /quibags search — search everywhere; /quibags bank|guild — browse the (cached) bank / guild bank anywhere; /quibags clearnew — clear all new-item glows.")
    end
end

-- Expose refresh globally (keystone.lua precedent): the options surfaces —
-- the Bags settings provider and the Modules-page master toggle — call
-- _G.QUI_RefreshBags after DB writes.
_G.QUI_RefreshBags = Refresh

if ns.Registry then
    ns.Registry:Register("bags", {
        refresh = _G.QUI_RefreshBags,
        priority = 50,
        group = "bags",
        importCategories = { "bags" },
    })
end

-- Startup. QUI_Bags is a LoadOnDemand sub-addon loaded by the core's eager LOD
-- pass AFTER login has already happened, so a raw login-event registration
-- would never fire (guarded by lod_login_event_guard_test). ns.WhenLoggedIn
-- (init.lua) instead fires immediately when already logged in — the LOD case —
-- else waits for the event. The UI starts only when enabled; the store and
-- its collection are a core service (core/storage/collector.lua) and run
-- regardless of this module's enable flag.
ns.WhenLoggedIn(function()
    started = true
    if IsEnabled() then StartUI() end
end)
