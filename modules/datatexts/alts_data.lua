local ADDON_NAME, ns = ...
local AltsData = {}
ns.DatatextAltsData = AltsData

local function RowLess(a, b)
    if a.money ~= b.money then return a.money > b.money end
    return a.key < b.key
end

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

function AltsData.LegacyToStorageKey(goldKey)
    if type(goldKey) ~= "string" then return nil end
    local realm, name = goldKey:match("^(.+)%-([^%-]+)$")
    if not name then return nil end
    return name .. "-" .. realm:gsub("[%s%-']", "")
end

function AltsData.MergeLegacyGold(rows, goldData)
    rows = rows or {}
    if type(goldData) ~= "table" then
        table.sort(rows, RowLess)
        return rows
    end

    local seen = {}
    for _, r in ipairs(rows) do seen[r.key] = true end

    for key, entry in pairs(goldData) do
        local synthKey = AltsData.LegacyToStorageKey(key)
        if synthKey then
            if not seen[synthKey] then
                local money, class
                if type(entry) == "number" then
                    money = entry
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

function AltsData.Total(rows)
    local t = 0
    for _, r in ipairs(rows) do t = t + (r.money or 0) end
    return t
end

function AltsData.BarText(mode, rows, formatGold)
    if mode == "count" then
        return string.format("Alts: %d", #rows)
    end
    return "Alts: " .. formatGold(AltsData.Total(rows))
end
