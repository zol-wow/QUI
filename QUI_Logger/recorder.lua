-- QUI_Logger/recorder.lua
-- Dev-only event recorder. Pure funcs are unit-tested; live wiring runs
-- only when WoW globals exist (guarded), so this file loads under plain lua.
-- luacheck: globals QUI_LoggerDB SLASH_QLOG1
local addonName, ns = ...

local function shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function ns.SanitizeArg(v)
    local tv = type(v)
    if tv == "number" or tv == "string" or tv == "boolean" or tv == "nil" then
        return v
    end
    if tv == "table" then
        local ok, copy = pcall(shallowCopy, v)
        return ok and copy or "<unstorable-table>"
    end
    -- userdata / function / thread / secret values: never store the live ref.
    return "<" .. tv .. ">"
end

function ns.SanitizeArgs(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do
        local ok, s = pcall(ns.SanitizeArg, (select(i, ...)))
        out[i] = ok and s or "<unstorable>"
    end
    return out, n
end
function ns.BuildRecord(timeFn, event, ...)
    local args, n = ns.SanitizeArgs(...)
    return { t = timeFn(), e = event, a = args, n = n }
end
function ns.NewSession(dateStr)
    return { started = dateStr, events = {} }
end

function ns.InitDB(dbProvider)
    local db = dbProvider.get() or {}
    if type(db.sessions) ~= "table" then db.sessions = {} end
    local session = ns.NewSession(ns._dateFn and ns._dateFn() or "?")
    db.sessions[#db.sessions + 1] = session
    dbProvider.set(db)
    return session.events
end

function ns.ClearDB(db)
    if db then db.sessions = {} end
end

function ns.StatusString(db)
    local sessions = (db and db.sessions) or {}
    local events = 0
    for i = 1, #sessions do events = events + #sessions[i].events end
    return string.format("sessions=%d events=%d", #sessions, events)
end

-- Live wiring: only with WoW globals present.
if type(CreateFrame) == "function" then
    ns._dateFn = date
    local buffer = {}
    local sink = buffer            -- pre-SV: collect into local buffer
    local function record(event, ...)
        sink[#sink + 1] = ns.BuildRecord(GetTimePreciseSec, event, ...)
    end

    -- NOTE: COMBAT_LOG_EVENT_UNFILTERED is NOT capturable from an addon in 12.0
    -- (Midnight). CLEU was removed from the addon environment: Frame:RegisterEvent
    -- for it raises ADDON_ACTION_FORBIDDEN, the public CombatLogGetCurrentEventInfo
    -- is gone from the API docs, and combat data moved to the Blizzard-only
    -- COMBAT_LOG_EVENT_INTERNAL_UNFILTERED / C_CombatLogInternal plus the aggregate
    -- C_DamageMeter API. RegisterAllEvents also never delivered CLEU. For raw
    -- combat-log capture use the client's own /combatlog (writes
    -- WoWCombatLog-*.txt), which is not addon-gated.
    local frame = CreateFrame("Frame")
    frame:RegisterAllEvents()
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" and ... == addonName then
            local provider = {
                get = function() return QUI_LoggerDB end,
                set = function(v) QUI_LoggerDB = v end,
            }
            local liveSink = ns.InitDB(provider)
            for i = 1, #buffer do liveSink[#liveSink + 1] = buffer[i] end
            buffer = nil
            sink = liveSink
            return
        end
        record(event, ...)
    end)

    SLASH_QLOG1 = "/qlog"
    SlashCmdList["QLOG"] = function(msg)
        msg = (msg or ""):lower():gsub("%s+", "")
        if msg == "clear" then
            ns.ClearDB(QUI_LoggerDB)
            print("QUI_Logger: cleared")
        else
            print("QUI_Logger: " .. ns.StatusString(QUI_LoggerDB))
        end
    end
end
