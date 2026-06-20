-- tests/unit/qui_logger_replay_test.lua
-- Run: lua tests/unit/qui_logger_replay_test.lua
local Replay = assert(loadfile("tests/replay/replay_session.lua"))()

local session = { started = "D", events = {
    { e = "PLAYER_LOGIN", a = {}, n = 0 },
    { e = "UNIT_AURA",    a = { "player", nil, 3 }, n = 3 },
} }

local seen = {}
Replay.Dispatch(session, function(event, ...)
    seen[#seen + 1] = { event, select("#", ...) }
end)

assert(seen[1][1] == "PLAYER_LOGIN" and seen[1][2] == 0, "first event wrong")
assert(seen[2][1] == "UNIT_AURA" and seen[2][2] == 3, "arity must survive replay")
print("qui_logger_replay_test: OK")
