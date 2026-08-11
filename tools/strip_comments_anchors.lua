-- tools/strip_comments_anchors.lua
--
-- A large part of the unit suite does not test a module by loading it: it slices
-- a REGION out of the source file using comment banners as delimiters and
-- loadstrings the slice (tests/unit/unitframes_power_coalesce_test.lua is the
-- archetype), or it asserts outright that a comment documenting some subtle
-- reason is still there. tests/helpers/load_cdm_consolidated_chunk.lua does the
-- same with the `-- Inlined from <file>` markers in the merged CDM chunk.
--
-- Those comments are load-bearing. This script harvests every string literal in
-- the test tree that looks like it addresses a comment, and writes them out as
-- the anchor list tools/strip_comments.lua honours. Anything a test can find is
-- therefore kept; everything else goes.
--
--   lua tools/strip_comments_anchors.lua <testfile> ... > tests/helpers/comment_anchors.lua

local function longBracketLevel(src, pos)
    if src:sub(pos, pos) ~= "[" then return nil end
    local j = pos + 1
    local level = 0
    while src:sub(j, j) == "=" do
        level = level + 1
        j = j + 1
    end
    if src:sub(j, j) == "[" then return level, j + 1 end
    return nil
end

-- Return every string literal in `src`, source text and all, skipping comments
-- so a commented-out example never contributes an anchor.
local function stringLiterals(src)
    local out, n, i = {}, #src, 1
    while i <= n do
        local c = src:sub(i, i)
        if c == "-" and src:sub(i + 1, i + 1) == "-" then
            local level, bodyStart = longBracketLevel(src, i + 2)
            if level then
                local _, closeEnd = src:find("]" .. string.rep("=", level) .. "]", bodyStart, true)
                i = (closeEnd or n) + 1
            else
                local nl = src:find("\n", i, true)
                i = (nl or n + 1)
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local ch = src:sub(j, j)
                if ch == "\\" then
                    j = j + 2
                elseif ch == c then
                    j = j + 1
                    break
                elseif ch == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            out[#out + 1] = src:sub(i, j - 1)
            i = j
        elseif c == "[" then
            local level, bodyStart = longBracketLevel(src, i)
            if level then
                local _, closeEnd = src:find("]" .. string.rep("=", level) .. "]", bodyStart, true)
                out[#out + 1] = src:sub(i, closeEnd or n)
                i = (closeEnd or n) + 1
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return out
end

-- Two ways in. A literal that names a comment outright (`--` written straight,
-- or `%-%-` as a pattern) qualifies at MIN_COMMENT_LENGTH. Everything else has
-- to clear the longer MIN_LENGTH, because plenty of assertions pin comment
-- PROSE without the dashes ever appearing in the literal —
-- `source:find("COMBAT GATE (load-bearing)")` is a comment assertion too.
--
-- Casting this wide is safe by construction: an anchor can only ever keep a
-- comment alive. It cannot reach code, so a literal that happens to match a
-- function name costs at most a retained comment mentioning that name.
local MIN_LENGTH = 12
local MIN_COMMENT_LENGTH = 8
local MIN_LITERAL = 4

-- An anchor counts as a pattern only when it contains a `%`, matching how the
-- tests use them (a pattern is written `%-%-`; plain text goes to find(.., true)).
local function isPattern(value)
    return value:find("%%") ~= nil
end

-- Longest run of plain characters in a pattern. `%-%-[^\n]*` — a tool's generic
-- "any comment" regex rather than a pin on particular text — reduces to nothing
-- here, which is exactly how it gets rejected. Left in, it matched all 871
-- comments in unitframes.lua and the strip became a no-op.
local function literalProbe(value)
    local best, cur = "", {}
    local i, n = 1, #value
    local function flush()
        local run = table.concat(cur)
        if #run > #best then best = run end
        cur = {}
    end
    while i <= n do
        local c = value:sub(i, i)
        if c == "%" then
            local nxt = value:sub(i + 1, i + 1)
            if nxt:match("%a") then flush() else cur[#cur + 1] = nxt end
            i = i + 2
        elseif c:match("[%^%$%*%+%-%?%.%(%)%[%]]") then
            flush()
            i = i + 1
        else
            cur[#cur + 1] = c
            i = i + 1
        end
    end
    flush()
    return best
end

local function isCommentAnchor(value)
    local namesAComment = value:find("--", 1, true) ~= nil
        or value:find("%%%-%%%-") ~= nil
    if #value < (namesAComment and MIN_COMMENT_LENGTH or MIN_LENGTH) then
        return false
    end
    local probe = isPattern(value) and literalProbe(value) or value
    return #probe >= MIN_LITERAL
end

local seen, anchors = {}, {}
for _, path in ipairs(arg or {}) do
    local fh = io.open(path, "rb")
    if fh then
        local src = fh:read("*a")
        fh:close()
        for _, literal in ipairs(stringLiterals(src)) do
            -- Let Lua itself decode the escapes, so `\n` in a test's pattern is
            -- a real newline here and multi-line anchors keep working.
            local ok, value = pcall(function()
                return assert((loadstring or load)("return " .. literal))()
            end)
            if ok and type(value) == "string" and isCommentAnchor(value) and not seen[value] then
                seen[value] = true
                anchors[#anchors + 1] = value
            end
        end
    end
end

table.sort(anchors)

io.write("-- AUTO-GENERATED by tools/strip_comments_anchors.lua — DO NOT EDIT.\n")
io.write("-- Comment text the unit suite anchors on; tools/strip_comments.lua keeps\n")
io.write("-- every comment these match. Regenerate via tools/strip_comments.sh.\n")
io.write("return {\n")
for _, a in ipairs(anchors) do
    io.write(string.format("    %q,\n", a))
end
io.write("}\n")
