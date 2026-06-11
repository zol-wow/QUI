---------------------------------------------------------------------------
-- Bags search: search-everywhere query core (PURE — store accessors +
-- Details.Build + Search.Compile only; no frames, no events).
-- Everywhere.Query(queryString, opts) walks EVERY cached owner — each
-- character record's bags/bank/mail/equipped/auctions, the warband tabs,
-- every guild's tabs — matches each slot entry against the compiled query,
-- and aggregates matches by itemID:
--   { itemID, name, icon, quality, link, total,
--     owners = { { ownerKey, location, count }, ... } }
-- * owner keys + locations mirror summaries.lua exactly (charKey /
--   Summaries.WARBAND_OWNER / GUILD_PREFIX..guildKey; bags/bank/mail/
--   equipped/auctions/warband/guild) so consumers speak one dialect.
-- * matcher result ~= false includes the entry: nil (a needed field not
--   loaded yet) counts as a match, same as the window grids.
-- * name/icon/quality/link are first-non-nil across placements (auction
--   entries omit quality; pending items have no name yet).
-- * results sort total desc, then name asc with pending (nil) names last,
--   then itemID; owners sort count desc, then ownerKey, then location.
-- * opts.limit (default 100) caps the array; the overflow count lands in
--   result.truncated (nil when complete) — no silent caps, the window
--   renders "+N more".
-- * blank/whitespace queries return empty with result.blank = true: an
--   empty query compiles to match-everything, and "every item on the
--   account" is useless as a result set (and expensive to render).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Everywhere = {}
Bags.Everywhere = Everywhere

Everywhere.DEFAULT_LIMIT = 100

local function Accumulate(state, ownerKey, location, entry, details)
    local agg = state.byItem[entry.itemID]
    if not agg then
        agg = { itemID = entry.itemID, total = 0, owners = {}, _index = {} }
        state.byItem[entry.itemID] = agg
        state.items[#state.items + 1] = agg
    end
    local count = entry.count or 1
    agg.total = agg.total + count
    -- presentation fields: first non-nil placement wins
    if agg.name == nil and details then agg.name = details.name end
    if agg.icon == nil then agg.icon = entry.icon end
    if agg.quality == nil then agg.quality = entry.quality end
    if agg.link == nil then agg.link = entry.link end
    local key = ownerKey .. "\1" .. location
    local owner = agg._index[key]
    if not owner then
        owner = { ownerKey = ownerKey, location = location, count = 0 }
        agg._index[key] = owner
        agg.owners[#agg.owners + 1] = owner
    end
    owner.count = owner.count + count
end

--- One container ({ size, slots }; phase-1 placeholder {} skipped via the
--- .slots guard, same as summaries' IndexInto).
local function ScanContainer(state, ownerKey, location, container)
    if not container or not container.slots then return end
    for _, entry in pairs(container.slots) do
        if entry and entry.itemID then
            local details = Bags.Details.Build(entry)
            if state.matcher(details) ~= false then -- pending (nil) included
                Accumulate(state, ownerKey, location, entry, details)
            end
        end
    end
end

--- A map of containers (bags/bankTabs/warband.tabs/guild.tabs).
local function ScanContainerMap(state, ownerKey, location, map)
    if not map then return end
    for _, container in pairs(map) do
        ScanContainer(state, ownerKey, location, container)
    end
end

local function SortResults(items)
    table.sort(items, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        if a.name ~= b.name then
            -- pending (nil) names sort after resolved ones
            if a.name == nil then return false end
            if b.name == nil then return true end
            return a.name < b.name
        end
        return a.itemID < b.itemID
    end)
end

local function SortOwners(owners)
    table.sort(owners, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.ownerKey ~= b.ownerKey then return a.ownerKey < b.ownerKey end
        return a.location < b.location
    end)
end

--- Where should a click on this aggregated result navigate? Walks the
--- owners breakdown and picks the highest-priority placement a window can
--- actually render: current-char bags > current-char bank > warband (bank
--- window) > any guild > other-char bags > other-char bank. mail/equipped/
--- auctions have no navigable window — pure placements there → nil.
--- → { window = "bags"|"bank"|"guild", ownerKey?, guildKey?, warband? }
--- ownerKey nil = the current character's own view.
function Everywhere.ResolveTarget(item, currentCharKey)
    local owners = item and item.owners
    if not owners then return nil end
    local Summaries = Bags.Summaries
    local best, bestRank = nil, math.huge
    for _, owner in ipairs(owners) do
        local key, loc = owner.ownerKey, owner.location
        local rank, target
        if loc == "bags" and key == currentCharKey then
            rank, target = 1, { window = "bags" }
        elseif loc == "bank" and key == currentCharKey then
            rank, target = 2, { window = "bank" }
        elseif loc == "warband" and key == Summaries.WARBAND_OWNER then
            rank, target = 3, { window = "bank", warband = true }
        elseif loc == "guild" then
            local guildKey = key:sub(#Summaries.GUILD_PREFIX + 1)
            rank, target = 4, { window = "guild", guildKey = guildKey }
        elseif loc == "bags" then
            rank, target = 5, { window = "bags", ownerKey = key }
        elseif loc == "bank" then
            rank, target = 6, { window = "bank", ownerKey = key }
        end
        if rank and rank < bestRank then
            best, bestRank = target, rank
            if rank == 1 then break end
        end
    end
    return best
end

--- Query the whole cache. → array of aggregated item entries (shape in the
--- header) + result.truncated (overflow count) / result.blank flags.
function Everywhere.Query(queryString, opts)
    local results = {}
    queryString = (queryString or ""):match("^%s*(.-)%s*$")
    if queryString == "" then
        results.blank = true
        return results
    end
    local Store, Summaries = Bags.Store, Bags.Summaries
    local state = {
        matcher = Bags.Search.Compile(queryString),
        byItem = {},
        items = {},
    }
    for _, charKey in ipairs(Store.ListCharacters()) do
        local rec = Store.GetCharacter(charKey)
        if rec then
            ScanContainerMap(state, charKey, "bags", rec.bags)
            ScanContainerMap(state, charKey, "bank", rec.bankTabs)
            ScanContainer(state, charKey, "mail", rec.mail)
            ScanContainer(state, charKey, "equipped", rec.equipped)
            ScanContainer(state, charKey, "auctions", rec.auctions)
        end
    end
    local wb = Store.GetWarband()
    if wb then
        ScanContainerMap(state, Summaries.WARBAND_OWNER, "warband", wb.tabs)
    end
    for _, guildKey in ipairs(Store.ListGuilds()) do
        local guild = Store.GetGuild(guildKey)
        if guild then
            ScanContainerMap(state, Summaries.GUILD_PREFIX .. guildKey, "guild", guild.tabs)
        end
    end
    for _, agg in ipairs(state.items) do
        agg._index = nil
        SortOwners(agg.owners)
    end
    SortResults(state.items)
    local limit = (opts and opts.limit) or Everywhere.DEFAULT_LIMIT
    for i = 1, math.min(limit, #state.items) do
        results[i] = state.items[i]
    end
    if #state.items > limit then
        results.truncated = #state.items - limit
    end
    return results
end
