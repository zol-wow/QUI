-- tests/replay/replay_combatlog.lua
-- Offline parser/replay for a client /combatlog dump (WoWCombatLog-*.txt).
-- Each line is "<datetime>  <CSV...>" where the first CSV field is the
-- combat-log subevent. This is the full-fidelity combat data that
-- COMBAT_LOG_EVENT_UNFILTERED no longer exposes to addons in 12.0 -- the
-- disk log is not addon-gated. Returns a Replay table.
local R = {}

-- Split a combat-log CSV row. Double-quotes delimit fields that may contain
-- commas (names); the quotes are delimiters, not data, so they are stripped.
-- Empty fields become "" (arity preserved, no nil holes). The literal token
-- `nil` stays the string "nil" -- the caller interprets it.
local function splitCSV(s)
    local fields = {}
    local buf = {}
    local inQuote = false
    for i = 1, #s do
        local c = s:sub(i, i)
        if inQuote then
            if c == '"' then
                inQuote = false
            else
                buf[#buf + 1] = c
            end
        elseif c == '"' then
            inQuote = true
        elseif c == ',' then
            fields[#fields + 1] = table.concat(buf)
            buf = {}
        else
            buf[#buf + 1] = c
        end
    end
    fields[#fields + 1] = table.concat(buf)
    return fields
end

-- Parse one line into { ts = <string>, sub = <subevent>, fields = {...} }.
-- Returns nil for a line without the "  " timestamp/payload separator.
function R.ParseLine(line)
    local ts, rest = line:match("^(.-)  (.+)$")
    if not rest then return nil end
    local all = splitCSV(rest)
    local sub = table.remove(all, 1)
    return { ts = ts, sub = sub, fields = all }
end

-- Parse a whole log body (multi-line string). Blank lines are skipped.
function R.Parse(text)
    local list = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            local rec = R.ParseLine(line)
            if rec then list[#list + 1] = rec end
        end
    end
    return list
end

function R.LoadCombatLog(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return R.Parse(text)
end

-- Dispatch each record as handler(subevent, unpack(fields)) in log order,
-- mirroring how a CLEU handler would receive the row.
function R.Dispatch(records, handler)
    for i = 1, #records do
        local r = records[i]
        handler(r.sub, unpack(r.fields))
    end
end

return R
