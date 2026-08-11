-- Emitter for positional, packed generated payloads.
--
-- Records are emitted as arrays, not maps: the field names live once in a
-- schema header instead of once per record. Reading a row means indexing the
-- schema for the slot number.
--
-- Four rules that are easy to get wrong:
--
--   1. Arity is PINNED. A record whose optional tail fields are nil would
--      truncate the Lua array -- `#row` shrinks and every field past the gap
--      silently reads as nil -- so an absent field emits `false`, never a
--      hole. `false` is therefore RESERVED as the top-level absent marker:
--      M.rows raises if a record actually holds a literal `false`, because a
--      reader could not tell the two apart. Nested tables are emitted keyed,
--      so a `false` inside one is preserved normally.
--
--   2. Values that are tables must survive whole. A table value can carry an
--      array part, a hash part, or both (search_cache's `widgetDescriptor`
--      does), so `quote` emits both parts. Emitting only `1..#v` would turn
--      every descriptor into `{}` without any error.
--
--   3. The long-bracket delimiter is "]==]"; any value containing it would
--      close the string early. Callers must reject such values. Lua 5.1's
--      long-string lexer also rewrites a raw CR to LF, so a value containing
--      one would come back changed; M.rows rejects those too.
--
--   4. Output must be deterministic or the staleness gates thrash. Hash-part
--      keys are emitted in sorted order.
--
-- Underscore-prefixed keys are dropped at every level, matching the keyed
-- serializer this replaced: they are runtime-derived scoring fields that the
-- consumer recomputes after localizing.

local M = {}

local function is_dropped_key(key)
    return type(key) == "string" and key:sub(1, 1) == "_"
end

-- Total order over mixed-type keys so the hash part is deterministic.
local function key_less(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return ta < tb
    end
    if ta == "number" or ta == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

local quote

-- Emits both the array part (1..#v, positional) and the remaining keys
-- (sorted, `[key]=value`). Any key already covered by the array part is
-- skipped so it is not emitted twice.
local function quote_table(v)
    local parts = {}
    local n = #v
    for i = 1, n do
        parts[#parts + 1] = quote(v[i]) or "nil"
    end

    local rest = {}
    for key in pairs(v) do
        local in_array_part = type(key) == "number"
            and key % 1 == 0 and key >= 1 and key <= n
        if not in_array_part and not is_dropped_key(key) then
            rest[#rest + 1] = key
        end
    end
    table.sort(rest, key_less)

    for _, key in ipairs(rest) do
        local encoded_key = quote(key)
        local encoded_value = quote(v[key])
        -- A key or value of an unrepresentable type (function, userdata)
        -- is dropped, which is what the keyed serializer did as well: it
        -- emitted `["k"] = nil`, i.e. no entry.
        if encoded_key and encoded_value then
            parts[#parts + 1] = "[" .. encoded_key .. "]=" .. encoded_value
        end
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

-- Returns a Lua source expression for `v`, or nil when `v` has no
-- representation (nil itself, functions, userdata, threads).
quote = function(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then return quote_table(v) end
    return nil
end

M.quote = quote

-- Union of the keys present across `rows`, sorted. Only string keys are
-- allowed: the schema is emitted with `%q` and read back as field names.
function M.derive_schema(rows)
    local seen, schema = {}, {}
    for i = 1, #rows do
        for key in pairs(rows[i]) do
            if not is_dropped_key(key) then
                if type(key) ~= "string" then
                    error(("pack_emit.derive_schema: row %d has a non-string field key (%s %s)")
                        :format(i, type(key), tostring(key)), 0)
                end
                if not seen[key] then
                    seen[key] = true
                    schema[#schema + 1] = key
                end
            end
        end
    end
    table.sort(schema)
    return schema
end

-- rows: array of record tables. schema: array of field names, in slot order.
function M.rows(rows, schema)
    local out = {}
    for i = 1, #rows do
        local rec, slots = rows[i], {}
        for s = 1, #schema do
            local value = rec[schema[s]]
            if value == false then
                error(("pack_emit.rows: row %d field %q holds a literal false, which is "
                    .. "reserved as the absent marker; give the field a distinct "
                    .. "encoding before shipping it")
                    :format(i, schema[s]), 0)
            end
            slots[s] = quote(value) or "false"  -- pin arity, never emit a hole
        end
        out[i] = "{" .. table.concat(slots, ",") .. "}"
    end
    return "{" .. table.concat(out, ",\n") .. "}"
end

function M.schema(schema)
    local parts = {}
    for i = 1, #schema do parts[i] = string.format("%q", schema[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Rejects payload text that a long-bracket string cannot carry unchanged:
-- the closing delimiter (which would end the string early) and a raw CR
-- (which Lua 5.1's long-string lexer rewrites to LF).
function M.assert_long_bracket_safe(payload, delimiter)
    if payload:find(delimiter, 1, true) then
        error("pack_emit: payload contains the long-bracket delimiter "
            .. delimiter .. "; widen the delimiter", 0)
    end
    if payload:find("\r", 1, true) then
        error("pack_emit: payload contains a raw CR, which Lua's long-string "
            .. "lexer rewrites to LF; escape it before packing", 0)
    end
end

return M
