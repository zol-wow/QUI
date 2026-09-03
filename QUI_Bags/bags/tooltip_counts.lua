-- luacheck: read globals ItemRefTooltip
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local TooltipCounts = {}
Bags.TooltipCounts = TooltipCounts

local LOCATION_ORDER = { "bags", "bank", "equipped", "mail", "auctions", "warband", "guild" }
local KNOWN_LOCATION = {}
for _, loc in ipairs(LOCATION_ORDER) do KNOWN_LOCATION[loc] = true end

local function ColorLabel(label, classToken)
    local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color and color.colorStr then
        return "|c" .. color.colorStr .. label .. "|r"
    end
    return label
end

local function BuildBreakdown(locCounts)
    local parts = {}
    for _, loc in ipairs(LOCATION_ORDER) do
        local n = locCounts[loc]
        if n and n > 0 then parts[#parts + 1] = loc .. " " .. n end
    end
    local extras
    for loc, n in pairs(locCounts) do
        if not KNOWN_LOCATION[loc] and n > 0 then
            extras = extras or {}
            extras[#extras + 1] = loc .. " " .. n
        end
    end
    if extras then
        table.sort(extras)
        for _, part in ipairs(extras) do parts[#parts + 1] = part end
    end
    return table.concat(parts, ", ")
end

function TooltipCounts.BuildCountLines(counts, getOwnerInfo)
    local lines = {}
    if type(counts) ~= "table" then return lines end
    local owners, grand = {}, 0
    for ownerKey, locCounts in pairs(counts) do
        local total = 0
        for _, n in pairs(locCounts) do total = total + n end
        if total > 0 then
            local info = getOwnerInfo(ownerKey) or {}
            owners[#owners + 1] = {
                total = total,
                locCounts = locCounts,
                label = info.label or ownerKey,
                classToken = info.classToken,
                isCurrent = info.isCurrent and true or false,
                plainTotal = info.plainTotal,
            }
            grand = grand + total
        end
    end
    if #owners == 0 then return lines end
    table.sort(owners, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.total ~= b.total then return a.total > b.total end
        return a.label < b.label
    end)
    for _, owner in ipairs(owners) do
        local label = ColorLabel(owner.label, owner.classToken)
        if owner.plainTotal then
            lines[#lines + 1] = label .. ": " .. owner.total
        else
            lines[#lines + 1] = label .. ": " .. owner.total
                .. " (" .. BuildBreakdown(owner.locCounts) .. ")"
        end
    end
    if #owners >= 2 then
        lines[#lines + 1] = ns.L["Total: "] .. grand
    end
    return lines
end

local function GetOwnerInfo(ownerKey)
    local Summaries, Store = Storage.Summaries, Storage.Store
    if ownerKey == Summaries.WARBAND_OWNER then
        return { label = ns.L["Warband"], plainTotal = true }
    end
    local currentKey = Store.GetCurrentCharacterKey()
    local currentRealm = currentKey and currentKey:match("^[^-]+%-(.+)$")
    local function StripCurrentRealm(label)
        if currentRealm and label:sub(-#currentRealm - 1) == ("-" .. currentRealm) then
            return label:sub(1, #label - #currentRealm - 1)
        end
        return label
    end
    local guildKey = ownerKey:match("^" .. Summaries.GUILD_PREFIX .. "(.+)$")
    if guildKey then
        return { label = StripCurrentRealm(guildKey), plainTotal = true }
    end
    local rec = Store.GetCharacter(ownerKey)
    return {
        label = StripCurrentRealm(ownerKey),
        classToken = rec and rec.details and rec.details.class,
        isCurrent = ownerKey == currentKey,
    }
end

function TooltipCounts.BuildCurrencyLines(currencyID)
    local lines = {}
    if type(currencyID) ~= "number" then return lines end
    if type(issecretvalue) == "function" and issecretvalue(currencyID) then return lines end
    if not (C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function") then return lines end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return lines end
    if info.isAccountWide then
        lines[1] = ns.L["Warband (account-wide)"] .. ": " .. (info.quantity or 0)
        return lines
    end
    local Store = Storage and Storage.Store
    if not (Store and Store.ListCharacters and Store.GetCharacter) then return lines end
    local counts = {}
    for _, ownerKey in ipairs(Store.ListCharacters()) do
        local rec = Store.GetCharacter(ownerKey)
        local quantity = rec and rec.currencies and rec.currencies[currencyID]
        if quantity and quantity > 0 then
            counts[ownerKey] = { currency = quantity }
        end
    end
    return TooltipCounts.BuildCountLines(counts, function(ownerKey)
        local owner = GetOwnerInfo(ownerKey)
        owner.plainTotal = true
        return owner
    end)
end

local function ShouldShowCounts(tooltip)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not (Bags.IsActive and Bags.IsActive()) then return end
    local settings = GetSettings()
    local mode = settings and settings.behavior and settings.behavior.tooltipCounts
    if mode == "off" then return end
    if mode == "modifier" and not IsShiftKeyDown() then return end
    return true
end

local function AddCountLines(tooltip, lines)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    for i = 1, #lines do
        tooltip:AddLine(lines[i], 1, 1, 1, true)
    end
end

local function OnTooltipSetItem(tooltip, data)
    if not ShouldShowCounts(tooltip) then return end
    local itemID = data and data.id
    if type(itemID) ~= "number" then return end
    if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
    local counts = Storage.Summaries.GetCounts(itemID)
    if next(counts) == nil then return end
    AddCountLines(tooltip, TooltipCounts.BuildCountLines(counts, GetOwnerInfo))
end

local function OnTooltipSetCurrency(tooltip, data)
    if not ShouldShowCounts(tooltip) then return end
    AddCountLines(tooltip, TooltipCounts.BuildCurrencyLines(data and data.id))
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType then
    if Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
    end
    if Enum.TooltipDataType.Currency then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, OnTooltipSetCurrency)
    end
end
