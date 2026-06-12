---------------------------------------------------------------------------
-- Core storage: guild bank scanner.
-- Guild data is server-resident and only readable while the guild bank is
-- open, through the legacy global API (no C_Container surface):
-- GetNumGuildBankTabs / QueryGuildBankTab / GetGuildBankTabInfo /
-- GetGuildBankItemInfo / GetGuildBankItemLink / GetGuildBankMoney.
-- The session is keyed by GUILDBANKFRAME_OPENED/CLOSED; the update events
-- (GUILDBANKBAGSLOTS_CHANGED etc.) are payload-free, so the rescan unit is
-- the whole bank — at most 8 tabs × 98 synchronous reads, which is cheap.
-- No async item loads here, so no snapshot-swap is needed (cf. scan_bank).
---------------------------------------------------------------------------
-- luacheck: read globals GetNumGuildBankTabs QueryGuildBankTab GetGuildBankItemInfo
-- luacheck: read globals GetGuildBankItemLink GetCurrentGuildBankTab GetGuildBankTabInfo
-- luacheck: read globals GetGuildBankMoney
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanGuild = {}
Storage.ScanGuild = ScanGuild

-- 98 = 7 columns × 14 slots per group (vendored Blizzard_GuildBankUI).
local MAX_SLOTS = 98

local guildKey = nil   -- session: set while the guild bank is open
local hasDirty = false

--- GUILDBANKFRAME_OPENED: bind the session to the current guild (nil when
--- unguilded → the entire session no-ops) and pump the server for every
--- tab's contents — GUILDBANKBAGSLOTS_CHANGED then streams in per tab.
function ScanGuild.OnGuildBankOpened()
    guildKey = Storage.Store.GetCurrentGuildKey()
    if not guildKey then return end
    Storage.Store.EnsureGuild(guildKey)
    for tab = 1, GetNumGuildBankTabs() do
        QueryGuildBankTab(tab)
    end
end

--- GUILDBANKFRAME_CLOSED: clears the session; later drains no-op.
function ScanGuild.OnGuildBankClosed()
    guildKey = nil
end

--- Guild update events carry no payload → whole-bank rescan is the unit.
function ScanGuild.MarkDirty()
    hasDirty = true
end

local function ReadTab(tab, name, icon, remainingWithdrawals)
    local record = {
        size = MAX_SLOTS,
        slots = {},
        name = name,
        icon = icon,
        withdrawals = remainingWithdrawals,
    }
    for slot = 1, MAX_SLOTS do
        local texture, itemCount, _, _, quality = GetGuildBankItemInfo(tab, slot)
        if texture then
            local link = GetGuildBankItemLink(tab, slot)
            -- Battlepet links carry no "item:" payload → itemID stays nil;
            -- the entry is still kept (summaries' IndexInto guards on
            -- entry.itemID, so nil-itemID entries simply don't aggregate).
            record.slots[slot] = {
                itemID = tonumber(link and link:match("item:(%d+)")),
                count = itemCount,
                link = link,
                quality = quality,
                icon = texture,
                isBound = false, -- guild bank items are never soulbound
            }
        end
    end
    return record
end

--- Count occupied (non-nil) slots in a sparse slots table.
local function CountOccupied(slots)
    local n = 0
    for _ in pairs(slots) do n = n + 1 end
    return n
end

--- Re-read every viewable tab + guild money; publishes
--- GuildChanged(guildKey, changedTabs). Returns true when anything was
--- written. No-op unless dirty AND a guild-bank session is open AND the
--- guild record exists.
function ScanGuild.Drain()
    if not hasDirty then return false end
    if not guildKey then return false end
    local rec = Storage.Store.GetGuild(guildKey)
    if not rec then return false end
    hasDirty = false
    local changed = {} -- viewable tab indices written this drain (unordered)
    local currentTab = GetCurrentGuildBankTab()
    for tab = 1, GetNumGuildBankTabs() do
        local name, icon, isViewable, _, _, remainingWithdrawals = GetGuildBankTabInfo(tab)
        if isViewable then
            local fresh = ReadTab(tab, name, icon, remainingWithdrawals)
            local freshOccupied = CountOccupied(fresh.slots)
            local old = rec.tabs[tab]
            if freshOccupied == 0 and old ~= nil and CountOccupied(old.slots) > 0
                    and tab ~= currentTab then
                -- Unstreamed tab: an all-empty read over a previously occupied
                -- cached tab means the server hasn't streamed it yet (no
                -- queried-ness API exists). Keep the cache. The current tab is
                -- exempt — its data is what the user is actively viewing, so a
                -- genuine full-empty there must persist.
            else
                rec.tabs[tab] = fresh
                changed[#changed + 1] = tab
            end
        end
        -- not viewable: keep the previously cached tab record untouched
    end
    rec.money = GetGuildBankMoney()
    if #changed > 0 then
        Storage.Bus.Publish("GuildChanged", guildKey, changed)
    end
    return #changed > 0
end
