---------------------------------------------------------------------------
-- Alts roster: pure data helpers (no frames — unit-tested headlessly).
-- Formatting + row building/sorting for the roster tab.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Alts = ns.Alts or {}; ns.Alts = Alts

local RosterData = {}
Alts.RosterData = RosterData

--- Copper → "1,234g" (gold only; roster altitude doesn't need silver).
function RosterData.FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local s = tostring(gold)
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return formatted .. "g"
end

--- Seconds → "3d 5h" / "2h 30m" / "1m"; nil → em dash.
function RosterData.FormatPlayed(seconds)
    if not seconds then return "—" end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", math.max(m, 1))
end

--- Epoch → "now" / "2h ago" / "3d ago"; nil → em dash.
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
    return -math.huge -- unseen fields sort last in desc, first in asc
end

--- characters: { key → record } (Store shape). opts: { sortKey, sortDesc }.
--- Returns dense rows: { key, name, realm, details, record }.
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

--- Sum of details.money across all records (copper).
function RosterData.TotalGold(characters)
    local total = 0
    for _, rec in pairs(characters) do
        total = total + ((rec.details and rec.details.money) or 0)
    end
    return total
end

--- Absolute epoch → "2d 5h" countdown; past → "expired"; nil → em dash.
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
