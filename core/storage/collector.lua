---------------------------------------------------------------------------
-- Core storage: collection driver. Owns the event wiring for the
-- account-wide character cache, the coalesced next-frame drain scheduler,
-- and login store init. Always on — collection is a core service; UI
-- modules (bags, alts) are pure consumers and their enable flags do not
-- gate scanning. Writes go only to the logged-in character's record.
---------------------------------------------------------------------------
-- luacheck: globals RequestRaidInfo
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local eventFrame = CreateFrame("Frame")
local drainQueued = false
local running = false

--- True once login init completed and the store is writable.
function Storage.IsRunning()
    return running
end

-- Tier-2 scanners (reputations / weeklies / lockouts) honor the per-profile
-- alts.scanners toggles LIVE. Lazy + nil-safe: the profile DB does not exist
-- pre-login, and missing flags default ON (collection is opt-out). Bag /
-- bank / character / professions scanning stays ungated — core service.
local GetAltsSettings -- lazy: profile DB may not exist pre-login
local function ScannerEnabled(key)
    if GetAltsSettings == nil then
        GetAltsSettings = (ns.Helpers and ns.Helpers.CreateDBGetter and ns.Helpers.CreateDBGetter("alts")) or false
    end
    if not GetAltsSettings then return true end
    local s = GetAltsSettings()
    local sc = s and s.scanners
    if sc == nil then return true end
    return sc[key] ~= false
end

---------------------------------------------------------------------------
-- Silent /played request. scan_character only WRITES playedTotal when a
-- TIME_PLAYED_MSG lands, and never issues RequestTimePlayed itself — so the
-- roster Played column stays empty until the user happens to type /played.
-- Stock silent-request dance (the pattern QUI chat's blizzard_suppress
-- mirrors): UnregisterEvent("TIME_PLAYED_MSG") on the chat frames →
-- RequestTimePlayed() → re-register once the reply lands. ChatFrame1 is
-- ALWAYS included in both halves regardless of registration state: the
-- suppress mirror tracks the un/register CALLS on the default frame
-- (hooksecurefunc fires on no-op unregisters too), and that flag is what
-- keeps the chat-takeover capture frame from printing the reply.
-- Re-register is deferred a frame (never inside the TIME_PLAYED_MSG
-- dispatch) with a 10s timeout failsafe so a lost reply can't permanently
-- eat the user's manual /played output.
---------------------------------------------------------------------------
-- luacheck: globals RequestTimePlayed NUM_CHAT_WINDOWS
local silencedChatFrames = nil
local function RestoreTimePlayedChat()
    if not silencedChatFrames then return end
    local frames = silencedChatFrames
    silencedChatFrames = nil
    for _, f in ipairs(frames) do
        pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG")
    end
end
local function SilentRequestTimePlayed()
    if type(RequestTimePlayed) ~= "function" then return end
    if silencedChatFrames then return end -- dance already in flight
    local frames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f.UnregisterEvent
            and (i == 1 or (f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG"))) then
            pcall(f.UnregisterEvent, f, "TIME_PLAYED_MSG")
            frames[#frames + 1] = f
        end
    end
    silencedChatFrames = frames
    RequestTimePlayed()
    C_Timer.After(10, RestoreTimePlayedChat)
end

--- Coalesced next-frame drain of all scanners. Data files call this after
--- async item loads; event handlers call it after dirty-marking. Each
--- Drain() self-guards on dirty/session state. Later-phase scanners are
--- existence-guarded (unit harnesses and partial loads).
function Storage.RequestDrain()
    if not running or drainQueued then return end
    drainQueued = true
    eventFrame:SetScript("OnUpdate", function()
        eventFrame:SetScript("OnUpdate", nil)
        drainQueued = false
        Storage.ScanBags.Drain()
        Storage.ScanBank.Drain()
        Storage.ScanGuild.Drain()
        if Storage.ScanMail then Storage.ScanMail.Drain() end
        if Storage.ScanEquipped then Storage.ScanEquipped.Drain() end
        if Storage.ScanCurrencies then Storage.ScanCurrencies.Drain() end
        if Storage.ScanAuctions then Storage.ScanAuctions.Drain() end
        if Storage.ScanCharacter then Storage.ScanCharacter.Drain() end
        if Storage.ScanProfessions then Storage.ScanProfessions.Drain() end
        if Storage.ScanReputations then Storage.ScanReputations.Drain() end
        if Storage.ScanWeeklies then Storage.ScanWeeklies.Drain() end
        if Storage.ScanLockouts then Storage.ScanLockouts.Drain() end
    end)
end

-- Data-collection events only. UI/takeover/ops events (interaction-manager
-- auto-open, junk, lock/cooldown re-dress, combat op aborts, guild-bank log,
-- ADDON_LOADED takeover arming) stay in QUI_Bags/bags/bags.lua.
local SCAN_EVENTS = {
    "BAG_UPDATE",                              -- (bagID) bags AND bank-tab containers
    "BAG_UPDATE_DELAYED",                      -- batch boundary → drain
    "BAG_CONTAINER_UPDATE",                    -- bag equipped/unequipped → sizes changed
    "BANKFRAME_OPENED",                        -- full bank scan opportunity
    "BANK_TABS_CHANGED",                       -- (bankType) tab purchase/structure
    "BANK_TAB_SETTINGS_UPDATED",               -- (bankType) rename/icon/flags
    "PLAYERBANKSLOTS_CHANGED",                 -- legacy char-bank slot event
    "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",   -- warband slot event
    "PLAYER_MONEY",
    "PLAYER_GUILD_UPDATE",
    "ACCOUNT_MONEY",                           -- warband bank gold changed (no payload)
    "ITEM_DATA_LOAD_RESULT",                   -- (itemID, success) → item_info
    "PLAYER_LOGOUT",                           -- lastSeen stamp (SVs save after handlers)
    -- Guild bank: scanner session + data events. The session edge is the
    -- interaction-manager event (GUILDBANKFRAME_OPENED has no mainline
    -- consumer); legacy events kept as a latch-safe belt-and-braces.
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_OPENED",
    "GUILDBANKFRAME_CLOSED",
    "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_ITEM_LOCK_CHANGED",
    "GUILDBANK_UPDATE_TABS",
    "GUILDBANK_UPDATE_MONEY",
    "GUILDBANK_UPDATE_WITHDRAWMONEY",
    -- Cache-breadth events:
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_INBOX_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED",
    "CURRENCY_DISPLAY_UPDATE",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "OWNED_AUCTIONS_UPDATED",
    -- Character-basics events (scan_character):
    "PLAYER_LEVEL_UP",
    "PLAYER_XP_UPDATE",
    "UPDATE_EXHAUSTION",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "TIME_PLAYED_MSG",                         -- (total, thisLevel) payload write
    -- Professions events (scan_professions):
    "SKILL_LINES_CHANGED",
    "TRADE_SKILL_LIST_UPDATE",
    -- Reputations events (scan_reputations):
    "FACTION_STANDING_CHANGED",                -- (factionID, updatedStanding)
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",      -- (majorFactionID, new, old)
    -- Weeklies (scan_weeklies):
    "WEEKLY_REWARDS_UPDATE",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_MAPS_UPDATE",
    "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
    -- Lockouts (scan_lockouts):
    "UPDATE_INSTANCE_INFO",                    -- after RequestRaidInfo AND on zone-in (drain is cheap)
    "BOSS_KILL",
}

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "BAG_UPDATE" then
        Storage.ScanBags.MarkDirty(arg1)
        Storage.ScanBank.MarkDirty(arg1) -- bank-tab container updates arrive here too
    elseif event == "BAG_UPDATE_DELAYED" then
        Storage.RequestDrain()
    elseif event == "BAG_CONTAINER_UPDATE" then
        -- Sizes changed; a pure swap fires no BAG_UPDATE for the removed bag
        -- and no BAG_UPDATE_DELAYED is guaranteed to follow.
        Storage.ScanBags.MarkAllDirty()
        Storage.RequestDrain()
    elseif event == "BANKFRAME_OPENED"
        or event == "BANK_TABS_CHANGED"
        or event == "BANK_TAB_SETTINGS_UPDATED" then
        Storage.ScanBank.RefreshTabMetadata()
        Storage.ScanBank.MarkAllDirty()
        Storage.RequestDrain()
    elseif event == "PLAYERBANKSLOTS_CHANGED"
        or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
        Storage.ScanBank.MarkAllDirty()
        Storage.RequestDrain()
    elseif event == "PLAYER_MONEY" or event == "PLAYER_GUILD_UPDATE"
        or event == "ACCOUNT_MONEY" then
        if event ~= "ACCOUNT_MONEY" then
            local rec = Storage.Store.GetCurrentCharacter()
            if rec then
                rec.details.money = GetMoney()
                rec.details.guild = GetGuildInfo("player")
            end
        end
        Storage.Bus.Publish("MoneyChanged")
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        Storage.ItemInfo.OnItemDataLoadResult(arg1, arg2)
    elseif event == "PLAYER_LOGOUT" then
        local rec = Storage.Store.GetCurrentCharacter()
        if rec then rec.details.lastSeen = time() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
            Storage.ScanGuild.OnGuildBankOpened()
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
            Storage.ScanGuild.OnGuildBankClosed()
        end
    elseif event == "GUILDBANKFRAME_OPENED" then
        Storage.ScanGuild.OnGuildBankOpened()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        Storage.ScanGuild.OnGuildBankClosed()
    elseif event == "GUILDBANKBAGSLOTS_CHANGED"
        or event == "GUILDBANK_ITEM_LOCK_CHANGED"
        or event == "GUILDBANK_UPDATE_TABS" then
        Storage.ScanGuild.MarkDirty()
        Storage.RequestDrain()
    elseif event == "GUILDBANK_UPDATE_MONEY"
        or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        Storage.Bus.Publish("GuildMoneyChanged")
    elseif event == "MAIL_SHOW" then
        Storage.ScanMail.OnMailShow()
        Storage.RequestDrain()
    elseif event == "MAIL_CLOSED" then
        Storage.ScanMail.OnMailClosed()
    elseif event == "MAIL_INBOX_UPDATE" then
        Storage.ScanMail.MarkDirty()
        Storage.RequestDrain()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        Storage.ScanEquipped.MarkDirty(arg1)
        Storage.RequestDrain()
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        Storage.ScanCurrencies.OnDisplayUpdate(arg1)
        Storage.RequestDrain()
    elseif event == "AUCTION_HOUSE_SHOW" then
        Storage.ScanAuctions.OnAuctionHouseShow()
        Storage.Bus.Publish("AuctionHouseChanged", true)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Storage.ScanAuctions.OnAuctionHouseClosed()
        Storage.Bus.Publish("AuctionHouseChanged", false)
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        Storage.ScanAuctions.MarkDirty()
        Storage.RequestDrain()
    elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE"
        or event == "UPDATE_EXHAUSTION" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE"
        or event == "ZONE_CHANGED_NEW_AREA" then
        if Storage.ScanCharacter then
            Storage.ScanCharacter.MarkAllDirty()
            Storage.RequestDrain()
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- fires for party members too; (unit) payload, nil on some paths
        if (arg1 == "player" or arg1 == nil) and Storage.ScanCharacter then
            Storage.ScanCharacter.MarkAllDirty()
            Storage.RequestDrain()
        end
    elseif event == "SKILL_LINES_CHANGED" or event == "TRADE_SKILL_LIST_UPDATE" then
        if Storage.ScanProfessions then
            Storage.ScanProfessions.MarkAllDirty()
            Storage.RequestDrain()
        end
    elseif event == "TIME_PLAYED_MSG" then
        if Storage.ScanCharacter then
            Storage.ScanCharacter.OnTimePlayed(arg1, arg2)
        end
        -- end the silent-request dance next frame, never inside the dispatch
        if silencedChatFrames then
            C_Timer.After(0, RestoreTimePlayedChat)
        end
    elseif event == "FACTION_STANDING_CHANGED"
        or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
        if Storage.ScanReputations and ScannerEnabled("reputations") then
            Storage.ScanReputations.OnFactionStandingChanged(arg1)
            Storage.RequestDrain()
        end
    elseif event == "WEEKLY_REWARDS_UPDATE" or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_MAPS_UPDATE"
        or event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
        if Storage.ScanWeeklies and ScannerEnabled("weeklies") then
            Storage.ScanWeeklies.MarkAllDirty()
            Storage.RequestDrain()
        end
    elseif event == "UPDATE_INSTANCE_INFO" or event == "BOSS_KILL" then
        if Storage.ScanLockouts and ScannerEnabled("lockouts") then
            Storage.ScanLockouts.MarkAllDirty()
            Storage.RequestDrain()
        end
    end
end)

-- Startup. Core loads pre-login, so ns.WhenLoggedIn waits for the event.
-- Event registration AND the full scan defer past first paint: the login
-- BAG_UPDATE storm fires during the loading screen and would otherwise
-- drain inside the first rendered frame (login-cost rule).
ns.WhenLoggedIn(function()
    Storage.Store.Initialize()
    if not Storage.Store.IsReady() then return end -- newer-version SV: read-only, collect nothing
    Storage.Store.EnsureCurrentCharacter()
    Storage.Summaries.SeedOwners()
    running = true
    ns.RunAfterFirstFrame(function()
        if not running then return end
        for _, ev in ipairs(SCAN_EVENTS) do eventFrame:RegisterEvent(ev) end
        Storage.ScanBags.MarkAllDirty()
        Storage.ScanEquipped.MarkAllDirty()
        Storage.ScanCurrencies.MarkAllDirty()
        if Storage.ScanCharacter then Storage.ScanCharacter.MarkAllDirty() end
        if Storage.ScanProfessions then Storage.ScanProfessions.MarkAllDirty() end
        if Storage.ScanWeeklies and ScannerEnabled("weeklies") then Storage.ScanWeeklies.MarkAllDirty() end
        if Storage.ScanLockouts and ScannerEnabled("lockouts") and RequestRaidInfo then RequestRaidInfo() end
        if Storage.ScanReputations and ScannerEnabled("reputations") then Storage.ScanReputations.ScheduleFullScan() end
        SilentRequestTimePlayed()
        Storage.RequestDrain()
    end, 0.5)
end)
