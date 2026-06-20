-- tests/unit/qui_logger_combatlog_test.lua
-- Run: lua tests/unit/qui_logger_combatlog_test.lua
local R = assert(loadfile("tests/replay/replay_combatlog.lua"))()

-- 1. basic line: timestamp split off, subevent extracted, quotes stripped
local rec = R.ParseLine([[6/18/2026 01:37:48.181-4  ZONE_CHANGE,2913,"Isle of Quel'Danas",220]])
assert(rec.ts == "6/18/2026 01:37:48.181-4", "ts wrong: " .. tostring(rec.ts))
assert(rec.sub == "ZONE_CHANGE", "sub wrong: " .. tostring(rec.sub))
assert(rec.fields[1] == "2913", "f1 wrong: " .. tostring(rec.fields[1]))
assert(rec.fields[2] == "Isle of Quel'Danas", "quotes must be stripped: " .. tostring(rec.fields[2]))
assert(rec.fields[3] == "220", "f3 wrong: " .. tostring(rec.fields[3]))
assert(#rec.fields == 3, "field count wrong: " .. #rec.fields)

-- 2. comma INSIDE quotes must not split the field
local q = R.ParseLine([[1/1/2026 00:00:00.000-0  SPELL_CAST,"Doe, John",0x1]])
assert(q.fields[1] == "Doe, John", "comma-in-quotes broke: " .. tostring(q.fields[1]))
assert(q.fields[2] == "0x1", "f2 wrong: " .. tostring(q.fields[2]))
assert(#q.fields == 2, "field count wrong: " .. #q.fields)

-- 3. nil literal + empty fields preserved (arity intact, no holes)
local e = R.ParseLine([[1/1/2026 00:00:00.000-0  X,0000000000000000,nil,,5]])
assert(e.fields[1] == "0000000000000000", "f1 wrong")
assert(e.fields[2] == "nil", "literal nil must stay a string: " .. tostring(e.fields[2]))
assert(e.fields[3] == "", "empty field must be empty string: [" .. tostring(e.fields[3]) .. "]")
assert(e.fields[4] == "5", "f4 wrong")
assert(#e.fields == 4, "field count wrong: " .. #e.fields)

-- 4. Parse(text): multi-line, skips blanks, keeps order
local text = table.concat({
    [[6/18/2026 01:37:48.180-4  COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.0.7,PROJECT_ID,1]],
    [[6/18/2026 01:37:48.181-4  ZONE_CHANGE,2913,"Isle of Quel'Danas",220]],
    "",
    [[6/18/2026 01:37:48.393-4  SPELL_CAST_SUCCESS,Vehicle-0,"Captain Garrick",0xa12,0x80000000,0000000000000000,nil,0x80000000,0x80000000,465,"Devotion Aura",0x2]],
}, "\n")
local list = R.Parse(text)
assert(#list == 3, "Parse must skip blank line, got: " .. #list)
assert(list[1].sub == "COMBAT_LOG_VERSION", "first sub wrong")
assert(list[3].sub == "SPELL_CAST_SUCCESS", "third sub wrong")
assert(list[3].fields[2] == "Captain Garrick", "third name wrong: " .. tostring(list[3].fields[2]))

-- 5. Dispatch: handler(sub, unpack(fields)) in order, arity preserved
local recs = {
    { ts = "t1", sub = "A", fields = { "1", "2" } },
    { ts = "t2", sub = "B", fields = { "x" } },
}
local seen = {}
R.Dispatch(recs, function(sub, ...)
    seen[#seen + 1] = { sub, select("#", ...), (...) }
end)
assert(seen[1][1] == "A" and seen[1][2] == 2 and seen[1][3] == "1", "dispatch 1 wrong")
assert(seen[2][1] == "B" and seen[2][2] == 1 and seen[2][3] == "x", "dispatch 2 wrong")

print("qui_logger_combatlog_test: OK")
