---------------------------------------------------------------------------
-- Alts datatext: pure data helpers (headless-tested). Reads the core
-- storage cache shape; no frames, no WoW APIs.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local AltsData = {}
ns.DatatextAltsData = AltsData

-- Shared row comparator: gold desc, then key asc as a stable tiebreak.
-- Used by BuildRows and MergeLegacyGold so the two never drift.
local function RowLess(a, b)
    if a.money ~= b.money then return a.money > b.money end
    return a.key < b.key
end

--- characters: { key → record }. Returns rows sorted by gold desc:
--- { key, name, class, level, ilvl, money }.
function AltsData.BuildRows(characters)
    local rows = {}
    for key, rec in pairs(characters or {}) do
        local d = (rec and rec.details) or {}
        rows[#rows + 1] = {
            key = key,
            name = key:match("^(.-)%-") or key,
            class = d.class,
            level = d.level,
            ilvl = d.ilvl,
            money = d.money or 0,
        }
    end
    table.sort(rows, RowLess)
    return rows
end

--- Legacy goldData key ("Realm-Name", raw realm) → storage key
--- ("Name-NormalizedRealm") or nil. Split on the LAST dash: realms may
--- contain dashes, character names never do. Normalization matches
--- store.lua's fallback gsub("[%s%-']", "").
function AltsData.LegacyToStorageKey(goldKey)
    if type(goldKey) ~= "string" then return nil end
    local realm, name = goldKey:match("^(.+)%-([^%-]+)$")
    if not name then return nil end
    return name .. "-" .. realm:gsub("[%s%-']", "")
end

--- Merge legacy goldData entries (keys "Realm-Name", raw realm with spaces)
--- into storage rows (keys "Name-NormalizedRealm"). Storage wins on
--- conflict; legacy entries only fill characters the (post-reset) cache
--- hasn't seen yet. legacyEntry: number (old format) or { money, class }.
--- Returns rows in BuildRows shape (re-sorted gold desc).
---
--- Key parsing: goldData keys are `realm .. "-" .. name`. Blizzard realm
--- names CAN contain dashes ("Azjol-Nerub") but character names CANNOT, so
--- we split on the LAST dash: everything before it is the realm, everything
--- after is the name. Realm is then normalized EXACTLY like store.lua's
--- NormalizedRealm last-resort fallback — gsub("[%s%-']", "") — so a spaced
--- realm "Aerie Peak" → "AeriePeak" and the synth key "Bob-AeriePeak"
--- collides with the storage key for the same character.
function AltsData.MergeLegacyGold(rows, goldData)
    rows = rows or {}
    if type(goldData) ~= "table" then
        table.sort(rows, RowLess)
        return rows
    end

    -- Existing storage keys win; legacy fills only the gaps.
    local seen = {}
    for _, r in ipairs(rows) do seen[r.key] = true end

    for key, entry in pairs(goldData) do
        local synthKey = AltsData.LegacyToStorageKey(key)
        if synthKey then
            if not seen[synthKey] then
                local money, class
                if type(entry) == "number" then
                    money = entry           -- old format: just the copper amount
                elseif type(entry) == "table" then
                    money = entry.money or 0
                    class = entry.class
                else
                    money = 0
                end
                rows[#rows + 1] = {
                    key = synthKey,
                    name = synthKey:match("^(.-)%-") or synthKey,
                    class = class,
                    level = nil,
                    ilvl = nil,
                    money = money or 0,
                }
                seen[synthKey] = true
            end
        end
    end

    table.sort(rows, RowLess)
    return rows
end

--- Remove legacy goldData entries that map to storageKey (used when a
--- character is deleted from the cache — without this the read-only
--- legacy layer would resurrect the deleted character in the gold
--- tooltip). Returns the number of entries removed.
function AltsData.PurgeLegacyFor(goldData, storageKey)
    if type(goldData) ~= "table" or not storageKey then return 0 end
    local removed = 0
    for key in pairs(goldData) do
        if AltsData.LegacyToStorageKey(key) == storageKey then
            goldData[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

--- Total copper across rows.
function AltsData.Total(rows)
    local t = 0
    for _, r in ipairs(rows) do t = t + (r.money or 0) end
    return t
end

--- Bar text for a mode. FormatGold injected (datatext-local formatter).
function AltsData.BarText(mode, rows, formatGold)
    if mode == "count" then
        return string.format("Alts: %d", #rows)
    end
    return "Alts: " .. formatGold(AltsData.Total(rows))
end
