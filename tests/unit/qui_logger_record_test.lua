-- tests/unit/qui_logger_record_test.lua
-- Run: lua tests/unit/qui_logger_record_test.lua
local ns = {}
assert(loadfile("QUI_Logger/recorder.lua"))("QUI_Logger", ns)

for _, fn in ipairs({"SanitizeArg","SanitizeArgs","BuildRecord","NewSession","InitDB","ClearDB","StatusString"}) do
    assert(type(ns[fn]) == "function", "recorder must define ns." .. fn)
end

-- non-CLEU: args come from varargs, clock injected
local rec = ns.BuildRecord(function() return 42 end, "PLAYER_LOGIN", "a", nil, 3)
assert(rec.t == 42 and rec.e == "PLAYER_LOGIN", "t/e wrong")
assert(rec.n == 3 and rec.a[1] == "a" and rec.a[3] == 3, "varargs payload wrong")
print("qui_logger_record_test: OK")
