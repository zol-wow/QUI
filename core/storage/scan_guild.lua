-- luacheck: read globals GetNumGuildBankTabs QueryGuildBankTab GetGuildBankItemInfo
-- luacheck: read globals GetGuildBankItemLink GetCurrentGuildBankTab GetGuildBankTabInfo
-- luacheck: read globals GetGuildBankMoney
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanGuild = {}
Storage.ScanGuild = ScanGuild

local MAX_SLOTS = 98

local guildKey = nil
local hasDirty = false

function ScanGuild.OnGuildBankOpened()
    guildKey = Storage.Store.GetCurrentGuildKey()
    if not guildKey then return end
    Storage.Store.EnsureGuild(guildKey)
    for tab = 1, GetNumGuildBankTabs() do
        QueryGuildBankTab(tab)
    end
end

function ScanGuild.OnGuildBankClosed()
    guildKey = nil
end

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
            record.slots[slot] = {
                itemID = tonumber(link and link:match("item:(%d+)")),
                count = itemCount,
                link = link,
                quality = quality,
                icon = texture,
                isBound = false,
            }
        end
    end
    return record
end

local function CountOccupied(slots)
    local n = 0
    for _ in pairs(slots) do n = n + 1 end
    return n
end

function ScanGuild.Drain()
    if not hasDirty then return false end
    if not guildKey then return false end
    local rec = Storage.Store.GetGuild(guildKey)
    if not rec then return false end
    hasDirty = false
    local changed = {}
    local currentTab = GetCurrentGuildBankTab()
    for tab = 1, GetNumGuildBankTabs() do
        local name, icon, isViewable, _, _, remainingWithdrawals = GetGuildBankTabInfo(tab)
        if isViewable then
            local fresh = ReadTab(tab, name, icon, remainingWithdrawals)
            local freshOccupied = CountOccupied(fresh.slots)
            local old = rec.tabs[tab]
            if freshOccupied == 0 and old ~= nil and CountOccupied(old.slots) > 0
                    and tab ~= currentTab then
            else
                rec.tabs[tab] = fresh
                changed[#changed + 1] = tab
            end
        end
    end
    rec.money = GetGuildBankMoney()
    if #changed > 0 then
        Storage.Bus.Publish("GuildChanged", guildKey, changed)
    end
    return #changed > 0
end
