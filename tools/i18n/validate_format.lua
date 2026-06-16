local M = {}

-- printf specifiers (NO space-flag — `% sign` / `100% for` in prose must NOT be
-- read as a conversion). Positional `%n$` is kept so `%1$s`/`%2$d` are detected.
local SPEC = "%%%d*%$?[%-%+#0]*%d*%.?%d*[diouxXeEfgGqscp]"

local function specs(s)
    local t = {}
    for tok in s:gmatch("%%%%") do t[#t+1] = "%%" end
    -- temporarily blank out %% so its percent signs aren't re-matched as specs
    for tok in (s:gsub("%%%%", "\2\2")):gmatch(SPEC) do t[#t+1] = tok end
    return t
end

local function escapes(s)
    local t = {}
    for _ in s:gmatch("|c%x%x%x%x%x%x%x%x") do t[#t+1] = "|c" end
    for _ in s:gmatch("|r") do t[#t+1] = "|r" end
    for _ in s:gmatch("|T.-|t") do t[#t+1] = "|T|t" end
    for _ in s:gmatch("|H.-|h") do t[#t+1] = "|H|h" end
    return t
end

local function multiset(list)
    local m = {}
    for _, v in ipairs(list) do m[v] = (m[v] or 0) + 1 end
    return m
end

-- Combined sorted signature (specifiers + escapes). Kept for equality checks.
function M.tokens(s)
    local t = {}
    for _, v in ipairs(specs(s)) do t[#t+1] = v end
    for _, v in ipairs(escapes(s)) do t[#t+1] = v end
    table.sort(t)
    return table.concat(t, "\1")
end

-- pairs_: { [enUSKey] = translatedValue } -> list of {key, reason} drifts.
-- Rule: a translation may DROP or REORDER format specifiers (Lua format ignores
-- surplus args; reorder is the whole point of positional %n$), but ADDING one
-- risks consuming a nil arg -> error. WoW color/texture escapes must match
-- EXACTLY — a dropped |r bleeds color into the rest of the UI.
function M.validate(pairs_)
    local drifts = {}
    for key, value in pairs(pairs_) do
        local ks, vs = multiset(specs(key)), multiset(specs(value))
        local ke, ve = multiset(escapes(key)), multiset(escapes(value))
        local bad = false
        for tok, n in pairs(vs) do
            if n > (ks[tok] or 0) then bad = true end   -- translation ADDED a specifier
        end
        for tok, n in pairs(ke) do
            if (ve[tok] or 0) ~= n then bad = true end   -- escape count changed
        end
        for tok, n in pairs(ve) do
            if (ke[tok] or 0) ~= n then bad = true end   -- escape added
        end
        if bad then
            drifts[#drifts+1] = { key = key, reason = "format/escape token drift" }
        end
    end
    return drifts
end

return M
