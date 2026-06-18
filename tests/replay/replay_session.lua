-- tests/replay/replay_session.lua
-- Offline replay of a QUI_Logger capture. Returns a Replay table.
-- luacheck: globals QUI_LoggerDB
local Replay = {}

function Replay.LoadFile(path)
    local chunk = assert(loadfile(path))
    chunk()                       -- defines global QUI_LoggerDB
    return QUI_LoggerDB
end

function Replay.Dispatch(session, handler)
    local events = session.events
    for i = 1, #events do
        local rec = events[i]
        handler(rec.e, unpack(rec.a, 1, rec.n or #rec.a))
    end
end

function Replay.DispatchSession(db, index, handler)
    Replay.Dispatch(db.sessions[index], handler)
end

return Replay
