---------------------------------------------------------------------------
-- Bags: tooltip inventory counts.
-- Item-tooltip post call (TooltipDataProcessor) appending per-owner counts
-- from Summaries.GetCounts: current character first, then alts by total,
-- plus warband/guild lines and a grand total when 2+ owners hold the item.
-- BuildCountLines is PURE (unit-tested); only the hook below touches game
-- state. Loads after the data layer in bags.xml; gates per show on
-- Bags.IsActive() so a disabled module adds nothing.
---------------------------------------------------------------------------
-- luacheck: read globals ItemRefTooltip
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local TooltipCounts = {}
Bags.TooltipCounts = TooltipCounts

-- Canonical breakdown order (matches the locations summaries.lua indexes).
local LOCATION_ORDER = { "bags", "bank", "equipped", "mail", "auctions", "warband", "guild" }
local KNOWN_LOCATION = {}
for _, loc in ipairs(LOCATION_ORDER) do KNOWN_LOCATION[loc] = true end

-- Read RAID_CLASS_COLORS directly (chat-classcolors precedent: never route
-- class colors through the CUSTOM-aware accent helper).
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
    -- Future/unknown locations still render (sorted for determinism) rather
    -- than silently vanishing from the breakdown.
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

--- PURE formatter. counts is the Summaries.GetCounts shape
--- ({ ownerKey → { location → count } }); getOwnerInfo(ownerKey) must return
--- { label, classToken|nil, isCurrent|nil, plainTotal|nil } (plainTotal
--- suppresses the breakdown for owners whose single location is implied by
--- the label — warband/guild). Returns an array of display strings:
--- "Label: total (bags 3, bank 5)" per owner — current character first, then
--- total desc, then label asc — plus "Total: N" when 2+ owners hold the item.
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
        lines[#lines + 1] = "Total: " .. grand
    end
    return lines
end

---------------------------------------------------------------------------
-- Hook side (game state from here down)
---------------------------------------------------------------------------

--- Resolves display info for a Summaries owner key. The current realm's
--- "-Realm" suffix is stripped from character AND guild labels (suffix
--- compare, never parsed: realm names can contain dashes); cross-realm
--- owners keep the full key for disambiguation.
local function GetOwnerInfo(ownerKey)
    local Summaries, Store = Bags.Summaries, Bags.Store
    if ownerKey == Summaries.WARBAND_OWNER then
        return { label = "Warband", plainTotal = true }
    end
    local currentKey = Store.GetCurrentCharacterKey()
    -- Character names cannot contain '-', so the first dash splits exactly.
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

local function OnTooltipSetItem(tooltip, data)
    -- Frame filter mirrors the Blizzard item-tooltip post-call idiom
    -- (PTR feedback): main tooltip + chat-link tooltip only — shopping
    -- comparisons and embedded tooltips stay untouched.
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    -- Module gate: disabled bags module = stale cache = no lines.
    if not (Bags.IsActive and Bags.IsActive()) then return end
    local settings = GetSettings()
    local mode = settings and settings.behavior and settings.behavior.tooltipCounts
    if mode == "off" then return end
    -- "modifier" re-checks per call: counts appear only while Shift is held.
    if mode == "modifier" and not IsShiftKeyDown() then return end
    local itemID = data and data.id
    if type(itemID) ~= "number" then return end
    -- EXPLICIT secret-policy decision: this guard-and-bail is intentional
    -- and is NOT the forbidden pass-through gating. The house rule ("format
    -- secrets straight through, never branch") exists for pipelines where
    -- the secret can flow onward to a C-side consumer. Here the itemID is a
    -- TooltipData id (the one secret-capable input in this module) and the
    -- ONLY consumer is our own Lua cache lookup — a secret value cannot
    -- index a table without throwing, and there is no C-side to forward it
    -- to. When the hovered item's identity is restricted, cross-character
    -- counts are information we cannot have: no line is the correct render.
    -- (Guard order per qol/tooltip precedent: type first, then issecretvalue.)
    if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
    local counts = Bags.Summaries.GetCounts(itemID)
    if next(counts) == nil then return end
    local lines = TooltipCounts.BuildCountLines(counts, GetOwnerInfo)
    if #lines == 0 then return end
    -- House separator + wrapped white lines (qol/tooltip info-line idiom).
    -- Post calls run before the tooltip's own Show — no relayout needed.
    tooltip:AddLine(" ")
    for i = 1, #lines do
        tooltip:AddLine(lines[i], 1, 1, 1, true)
    end
end

-- Registration guard covers partial-load environments (unit harness) and
-- API drift (mplus_progress/skinning-tooltips precedent).
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
end
