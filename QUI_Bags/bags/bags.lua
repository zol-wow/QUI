---------------------------------------------------------------------------
-- QUI Bags Module — entry point.
-- Owns event wiring for the inventory cache, the next-frame drain
-- scheduler, and the takeover lifecycle. `bags.enabled` is the master
-- switch (chat-module precedent): disabled = no scanning, no SV writes,
-- Blizzard bag UI restored (silently — the reload prompt belongs to the
-- options module toggle in a later phase, not to profile switches).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
-- Shared module namespace: sibling data-layer files (loaded before this in
-- bags.xml) publish themselves onto ns.Bags.
local Bags = ns.Bags or {}; ns.Bags = Bags

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local eventFrame = CreateFrame("Frame")
local drainQueued = false
local scanning = false
local started = false -- post-login startup ran (ns.WhenLoggedIn callback)

--- True while the module is enabled and scanning (cache is live). Gate for
--- passive consumers (tooltip counts) whose output must go quiet — not stale
--- — the moment the module is disabled.
function Bags.IsActive()
    return scanning
end

--- Coalesced next-frame drain of all scanners (bags, bank, guild bank).
--- Data files call this after async item loads; event handlers call it
--- after dirty-marking. The guild scanner rides the same coalescing: its
--- Drain() self-guards on session + dirty state, so draining it alongside
--- the others is a no-op outside an open guild bank.
--- Data-layer-internal: UI code must NOT call this as a refresh mechanism —
--- subscribe to the bus events instead.
function Bags.RequestDrain()
    if not scanning or drainQueued then return end
    drainQueued = true
    eventFrame:SetScript("OnUpdate", function()
        eventFrame:SetScript("OnUpdate", nil)
        drainQueued = false
        Bags.ScanBags.Drain()
        Bags.ScanBank.Drain()
        Bags.ScanGuild.Drain()
        -- Phase-6 breadth scanners (each self-guards on dirty/session state).
        -- Existence-guarded: unit harnesses load partial module sets.
        if Bags.ScanMail then Bags.ScanMail.Drain() end
        if Bags.ScanEquipped then Bags.ScanEquipped.Drain() end
        if Bags.ScanCurrencies then Bags.ScanCurrencies.Drain() end
        if Bags.ScanAuctions then Bags.ScanAuctions.Drain() end
    end)
end

local SCAN_EVENTS = {
    "BAG_UPDATE",                              -- (bagID) bags AND bank-tab containers
    "BAG_UPDATE_DELAYED",                      -- batch boundary → drain
    "BAG_CONTAINER_UPDATE",                    -- (no payload) bag equipped/unequipped → sizes changed
    "BANKFRAME_OPENED",                        -- full bank scan opportunity
    "BANKFRAME_CLOSED",                        -- scanner-neutral; bank session routing
    "BANK_TABS_CHANGED",                       -- (bankType) tab purchase/structure
    "BANK_TAB_SETTINGS_UPDATED",               -- (bankType) rename/icon/flags
    "PLAYERBANKSLOTS_CHANGED",                 -- legacy char-bank slot event
    "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",   -- warband slot event
    "PLAYER_MONEY",
    "PLAYER_GUILD_UPDATE",
    "ACCOUNT_MONEY",                           -- warband bank gold changed (no payload)
    "ITEM_DATA_LOAD_RESULT",                   -- (itemID, success) → item_info
    "PLAYER_REGEN_DISABLED",                   -- combat start → abort in-flight ops
    -- Guild bank events — only fire while the LoD addon has been loaded:
    "GUILDBANKFRAME_OPENED",                   -- session start → takeover + scanner
    "GUILDBANKFRAME_CLOSED",                   -- session end → takeover + scanner
    "GUILDBANKBAGSLOTS_CHANGED",               -- slot data arrived → rescan
    "GUILDBANK_ITEM_LOCK_CHANGED",             -- lock state flip → rescan
    "GUILDBANK_UPDATE_TABS",                   -- tab metadata changed → rescan
    "GUILDBANK_UPDATE_MONEY",                  -- vault gold changed → footer
    "GUILDBANK_UPDATE_WITHDRAWMONEY",          -- withdraw limit changed → footer
    "GUILDBANKLOG_UPDATE",                     -- log data arrived → log panel
    "ADDON_LOADED",                            -- LoD detect → guild takeover arming
    -- Phase-6 cache-breadth events:
    "MAIL_SHOW",                               -- mailbox session start → full inbox scan
    "MAIL_CLOSED",                             -- mailbox session end
    "MAIL_INBOX_UPDATE",                       -- inbox contents changed → rescan
    "PLAYER_EQUIPMENT_CHANGED",                -- (equipmentSlot, hasCurrent) per-slot
    "CURRENCY_DISPLAY_UPDATE",                 -- (currencyType?, quantity?, ...) all nilable
    "AUCTION_HOUSE_SHOW",                      -- AH session start
    "AUCTION_HOUSE_CLOSED",                    -- AH session end
    "OWNED_AUCTIONS_UPDATED",                  -- owned list arrived → rescan
}

local function IsEnabled()
    local s = GetSettings()
    return (s and s.enabled) and true or false
end

local function StartScanning()
    if scanning or not Bags.Store.IsReady() then return end
    scanning = true
    Bags.Store.EnsureCurrentCharacter()
    Bags.Summaries.SeedOwners()
    -- Takeover applies synchronously: a B-press in the deferral window must
    -- not open (then eat) the Blizzard bags. Apply is 7 hides + 10 global
    -- writes — login-cost negligible. BankTakeover.Suppress shares the same
    -- race rationale: a Banker interaction in the deferral window must not
    -- show the Blizzard BankFrame. GuildTakeover.Init runs synchronously too:
    -- if Blizzard_GuildBankUI is already loaded (enable-after-visit, /reload
    -- at the vault) the suppression must land before any guild-banker click;
    -- if not yet loaded it arms a pending flag and waits for ADDON_LOADED.
    Bags.Takeover.Apply()
    Bags.BankTakeover.Suppress()
    Bags.GuildTakeover.Init()
    -- Event registration AND the full scan defer past first paint: the login
    -- BAG_UPDATE storm fires during the loading screen and would otherwise
    -- drain inside the first rendered frame (login-cost rule). The deferred
    -- MarkAllDirty subsumes anything missed in the window; bank events can't
    -- meaningfully fire pre-paint. Mid-session enables route through
    -- C_Timer.After and register ~delay later — fine for a settings toggle.
    ns.RunAfterFirstFrame(function()
        if not scanning then return end
        for _, ev in ipairs(SCAN_EVENTS) do eventFrame:RegisterEvent(ev) end
        eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
        eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
        eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
        eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
        eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
        -- Re-run Init: an ADDON_LOADED fired inside the deferral window was
        -- unheard; Init is idempotent and re-checks IsAddOnLoaded.
        Bags.GuildTakeover.Init()
        Bags.ScanBags.MarkAllDirty()
        -- Login catch-up for the breadth surfaces readable away from an
        -- interaction: equipped + currencies can change inside the deferral
        -- window (login-fireable events were unheard). Mail/auction data
        -- exists only at their interactions — a catch-up there would drain
        -- against a closed surface, so they wait for MAIL_SHOW /
        -- AUCTION_HOUSE_SHOW.
        Bags.ScanEquipped.MarkAllDirty()
        Bags.ScanCurrencies.MarkAllDirty()
        -- New-item tracking: open the session priming window (baseline now,
        -- re-baseline per BagsChanged, arm ~5s later) so only items looted
        -- after it closes glow (existence-guarded: partial test harnesses).
        if Bags.NewItems then Bags.NewItems.OnLogin() end
        Bags.RequestDrain()
    end, 0.5)
end

local function StopScanning()
    if not scanning then return end
    scanning = false
    for _, ev in ipairs(SCAN_EVENTS) do eventFrame:UnregisterEvent(ev) end
    eventFrame:UnregisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    eventFrame:UnregisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    eventFrame:UnregisterEvent("ITEM_LOCK_CHANGED")
    eventFrame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:UnregisterEvent("EQUIPMENT_SETS_CHANGED")
    -- Cancel any scheduled drain and drop in-flight load callbacks: the
    -- header contract is "disabled = no scanning, no SV writes".
    eventFrame:SetScript("OnUpdate", nil)
    drainQueued = false
    Bags.ItemInfo.CancelAll()
    -- Silent stop: Revert is a clean restoration, and profile switches must
    -- not nag. The reload prompt will live on the options module toggle in a
    -- later phase.
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
    -- Scanner session flags must not outlive the module either (same
    -- precedent): MAIL_CLOSED/AUCTION_HOUSE_CLOSED/GUILDBANKFRAME_CLOSED are
    -- unregistered from here on, so a stale at-mailbox/at-AH/at-guild flag
    -- would let a post-re-enable drain clobber cached guild money/tab-1
    -- away from the vault, or wipe a mail/AH cache against a closed surface.
    if Bags.ScanMail then Bags.ScanMail.OnMailClosed() end
    if Bags.ScanAuctions then Bags.ScanAuctions.OnAuctionHouseClosed() end
    if Bags.ScanGuild and Bags.ScanGuild.OnGuildBankClosed then Bags.ScanGuild.OnGuildBankClosed() end
    -- New-item tracking wipes its session store and goes inert until a
    -- re-enable re-runs the full priming window (items acquired while
    -- disabled must not glow).
    if Bags.NewItems then Bags.NewItems.OnDisable() end
    Bags.Takeover.Revert()
    Bags.BankTakeover.Revert()
    Bags.GuildTakeover.Revert()
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "BAG_UPDATE" then
        Bags.ScanBags.MarkDirty(arg1)
        Bags.ScanBank.MarkDirty(arg1) -- bank-tab container updates arrive here too
    elseif event == "BAG_UPDATE_DELAYED" then
        Bags.RequestDrain()
    elseif event == "BAG_CONTAINER_UPDATE" then
        -- A container was equipped/unequipped/swapped (ContainerDocumentation
        -- BagContainerUpdate, no payload; Blizzard's ContainerFrame re-lays
        -- out on it). Bag SIZES changed — a pure swap fires no BAG_UPDATE
        -- for the removed bag, so the stale reagent-bag section survived
        -- until the next unrelated update. Re-read all player bags and
        -- drain now (no BAG_UPDATE_DELAYED is guaranteed to follow).
        Bags.ScanBags.MarkAllDirty()
        Bags.RequestDrain()
    elseif event == "BANKFRAME_OPENED"
        or event == "BANK_TABS_CHANGED"
        or event == "BANK_TAB_SETTINGS_UPDATED" then
        Bags.ScanBank.RefreshTabMetadata()
        Bags.ScanBank.MarkAllDirty()
        Bags.RequestDrain()
        if event == "BANKFRAME_OPENED" then
            Bags.BankTakeover.OnBankOpened()
            if Bags.Transfers and Bags.Transfers.AutoDepositReagentsOnOpen then
                Bags.Transfers.AutoDepositReagentsOnOpen()
            end
        end
    elseif event == "BANKFRAME_CLOSED" then
        -- the deposit queue must not outlive the bank session (a post-close
        -- UseContainerItem would USE the item instead of depositing it)
        if Bags.Transfers and Bags.Transfers.Cancel then Bags.Transfers.Cancel() end
        Bags.BankTakeover.OnBankClosed()
    elseif event == "PLAYERBANKSLOTS_CHANGED"
        or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
        -- Slot args don't map cleanly to a bag ID across both event eras;
        -- re-marking all purchased tabs is cheap (metadata-bounded).
        Bags.ScanBank.MarkAllDirty()
        Bags.RequestDrain()
    elseif event == "PLAYER_MONEY" or event == "PLAYER_GUILD_UPDATE"
        or event == "ACCOUNT_MONEY" then
        -- ACCOUNT_MONEY (warband bank gold, no payload) publishes only: the
        -- character record caches CHARACTER money/guild, while warband gold
        -- is fetched live (C_Bank.FetchDepositedMoney) by whoever renders it.
        if event ~= "ACCOUNT_MONEY" then
            local rec = Bags.Store.GetCurrentCharacter()
            if rec then
                rec.details.money = GetMoney()
                rec.details.guild = GetGuildInfo("player")
            end
        end
        Bags.Bus.Publish("MoneyChanged")
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
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        Bags.ItemInfo.OnItemDataLoadResult(arg1, arg2)
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
    elseif event == "GUILDBANKBAGSLOTS_CHANGED"
        or event == "GUILDBANK_ITEM_LOCK_CHANGED"
        or event == "GUILDBANK_UPDATE_TABS" then
        -- Tab-structure / slot-data / lock changes: mark the whole bank
        -- dirty (payload-free events; 8×98 reads is cheap) and coalesce.
        Bags.ScanGuild.MarkDirty()
        Bags.RequestDrain()
    elseif event == "GUILDBANK_UPDATE_MONEY"
        or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        -- Money / withdraw-limit update: publish so the guild window
        -- footer refreshes without a full rescan.
        Bags.Bus.Publish("GuildMoneyChanged")
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
    -- ── Cache-breadth events (mail / equipped / currencies / auctions) ──
    elseif event == "MAIL_SHOW" then
        -- session start doubles as the full-scan trigger (inbox data is
        -- only readable at a mailbox)
        Bags.ScanMail.OnMailShow()
        Bags.RequestDrain()
    elseif event == "MAIL_CLOSED" then
        Bags.ScanMail.OnMailClosed()
    elseif event == "MAIL_INBOX_UPDATE" then
        Bags.ScanMail.MarkDirty()
        Bags.RequestDrain()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- (equipmentSlot, hasCurrent) — per-slot dirty unit; the scanner
        -- range-guards slots outside 1..19
        Bags.ScanEquipped.MarkDirty(arg1)
        Bags.RequestDrain()
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        -- arg1 (currencyType) is nilable — payload-free fires mean "list
        -- changed"; carried IDs feed the collapsed-header capture
        Bags.ScanCurrencies.OnDisplayUpdate(arg1)
        Bags.RequestDrain()
    elseif event == "AUCTION_HOUSE_SHOW" then
        Bags.ScanAuctions.OnAuctionHouseShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Bags.ScanAuctions.OnAuctionHouseClosed()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        Bags.ScanAuctions.MarkDirty()
        Bags.RequestDrain()
    end
end)

local function Refresh()
    -- Lazy store init for the mid-session enable: a disabled module never
    -- initialized QUI_StorageDB at login (no SV writes while dormant), so
    -- the first enabled refresh after startup creates the schema here.
    -- IsInitialized (not IsReady) guards the call so a read-only store
    -- doesn't re-run Initialize (and re-print) every refresh.
    if started and IsEnabled() and not Bags.Store.IsInitialized() then
        Bags.Store.Initialize()
    end
    if not Bags.Store.IsReady() then return end -- pre-login; startup callback handles it
    if IsEnabled() then StartScanning() else StopScanning() end
    -- Profile switch between two enabled profiles: StartScanning early-outs
    -- (already scanning) but the new profile's window position must land.
    if IsEnabled() and scanning then
        if Bags.BagWindow.OnProfileChanged then
            Bags.BagWindow.OnProfileChanged()
        end
        if Bags.BankWindow.OnProfileChanged then
            Bags.BankWindow.OnProfileChanged()
        end
        if Bags.GuildWindow.OnProfileChanged then
            Bags.GuildWindow.OnProfileChanged()
        end
        if Bags.SearchWindow.OnProfileChanged then
            Bags.SearchWindow.OnProfileChanged()
        end
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
BINDING_HEADER_QUIBAGS = "QUI Bags"
BINDING_NAME_QUI_BAGS_TOGGLE = "Toggle Bags"
BINDING_NAME_QUI_BAGS_SEARCH_EVERYWHERE = "Search Everywhere"
BINDING_NAME_QUI_BAGS_TOGGLE_BANK = "Toggle Bank (cached anywhere)"
BINDING_NAME_QUI_BAGS_TOGGLE_GUILD = "Toggle Guild Bank (cached anywhere)"

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
-- else waits for the event. Store init is ENABLED-GATED with StartScanning:
-- a dormant module must not create/write QUI_StorageDB at all (header
-- contract "disabled = no scanning, no SV writes"); a mid-session enable
-- initializes lazily in Refresh.
ns.WhenLoggedIn(function()
    started = true
    if IsEnabled() then
        Bags.Store.Initialize()
        StartScanning()
    end
end)
