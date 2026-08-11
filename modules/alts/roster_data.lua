local ADDON_NAME, ns = ...
local Alts = ns.Alts or {}; ns.Alts = Alts

local RosterData = {}
Alts.RosterData = RosterData

function RosterData.FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local s = tostring(gold)
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return formatted .. "g"
end

function RosterData.FormatPlayed(seconds)
    if not seconds then return "—" end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", math.max(m, 1))
end

function RosterData.FormatLastSeen(ts, now)
    if not ts then return "—" end
    local age = (now or time()) - ts
    if age < 3600 then return "now" end
    if age < 86400 then return string.format("%dh ago", math.floor(age / 3600)) end
    return string.format("%dd ago", math.floor(age / 86400))
end

local function SortValue(key, details, sortKey)
    if sortKey == "name" then return key:lower() end
    local v = details[sortKey]
    if type(v) == "number" then return v end
    return -math.huge
end

function RosterData.BuildRows(characters, opts)
    opts = opts or {}
    local sortKey = opts.sortKey or "name"
    local rows = {}
    for key, rec in pairs(characters) do
        local name, realm = key:match("^(.-)%-(.+)$")
        rows[#rows + 1] = {
            key = key,
            name = name or key,
            realm = realm or "",
            details = rec.details or {},
            record = rec,
        }
    end
    table.sort(rows, function(a, b)
        local av = SortValue(a.key, a.details, sortKey)
        local bv = SortValue(b.key, b.details, sortKey)
        if av == bv then return a.key < b.key end
        if opts.sortDesc then return av > bv end
        return av < bv
    end)
    return rows
end

function RosterData.TotalGold(characters)
    local total = 0
    for _, rec in pairs(characters) do
        total = total + ((rec.details and rec.details.money) or 0)
    end
    return total
end

function RosterData.FormatResetIn(resetAt, now)
    if not resetAt then return "—" end
    local left = resetAt - (now or time())
    if left <= 0 then return "expired" end
    local d = math.floor(left / 86400)
    local h = math.floor((left % 86400) / 3600)
    if d > 0 then return string.format("%dd %dh", d, h) end
    local m = math.floor((left % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", math.max(m, 1))
end
