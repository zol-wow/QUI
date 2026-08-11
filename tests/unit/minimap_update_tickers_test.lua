-- tests/unit/minimap_update_tickers_test.lua
-- Verifies modules/minimap/minimap.lua StartUpdateTickers: per-feature ticker
-- lifecycle (clock/coords timers exist only while showClock/showCoords are
-- on; stale handles are canceled on refresh) and the minute-aligned clock
-- chain (one-shot C_Timer.NewTimer re-armed each fire; delay recomputed from
-- date("%S")). Harness mirrors tests/unit/minimap_drawer_filter_test.lua.
-- Run: lua tests/unit/minimap_update_tickers_test.lua
-- luacheck: globals MicroMenuPositionEnum (harness stub for the Blizzard enum)

local function noop() end

local Frame = {}
Frame.__index = Frame
local createdFrames = {}

local function newFrame(name, objectType, parent)
    return setmetatable({
        name = name,
        objectType = objectType or "Frame",
        parent = parent,
        scripts = {},
        children = {},
    }, Frame)
end

function Frame:IsObjectType(objectType)
    return self.objectType == objectType or objectType == "Frame"
end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:GetChildren() return unpack(self.children) end
function Frame:HasScript(scriptName) return self.scripts[scriptName] ~= nil end
function Frame:GetScript(scriptName) return self.scripts[scriptName] end
function Frame:SetScript(scriptName, handler) self.scripts[scriptName] = handler end
function Frame:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function Frame:UnregisterEvent(event)
    if self.events then self.events[event] = nil end
end
function Frame:Hide() end
function Frame:Show() end
function Frame:GetPoint() end
function Frame:GetWidth() return self.width or 32 end
function Frame:GetHeight() return self.height or 32 end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetScale(scale) self.scale = scale end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetFrameStrata(strata) self.strata = strata end

UIParent = newFrame("UIParent")
Minimap = newFrame("Minimap", "Frame", UIParent)
MinimapCluster = newFrame("MinimapCluster", "Frame", UIParent)
MinimapBackdrop = newFrame("MinimapBackdrop", "Frame", UIParent)
MicroMenuPositionEnum = { BottomLeft = 1, BottomRight = 2, TopLeft = 3, TopRight = 4 }
MicroMenuContainer = newFrame("MicroMenuContainer", "Frame", UIParent)
MicroMenu = newFrame("MicroMenu", "Frame", MicroMenuContainer)
MicroMenu.isHorizontal = true
function MicroMenuContainer:GetPosition()
    return MicroMenuPositionEnum.BottomRight
end
QueueStatusButton = newFrame("QueueStatusButton", "Button", MicroMenu)
function QueueStatusButton:UpdatePosition() end

function CreateFrame(_, name, parent)
    local frame = newFrame(name, "Frame", parent or UIParent)
    createdFrames[#createdFrames + 1] = frame
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end

function InCombatLockdown() return false end
function issecurevariable() return false end
function hooksecurefunc() end
LibStub = function() return nil end

-- Recording C_Timer stub: every NewTimer/NewTicker handle logs its interval
-- and whether Cancel was called.
local timerLog = {}
local function record(kind, interval, cb)
    local h = { kind = kind, interval = interval, cb = cb, canceled = false }
    function h:Cancel() self.canceled = true end
    timerLog[#timerLog + 1] = h
    return h
end
C_Timer = {
    After = noop,
    NewTimer = function(seconds, callback) return record("timer", seconds, callback) end,
    NewTicker = function(seconds, callback) return record("ticker", seconds, callback) end,
}

-- Fixed second-of-minute so the minute-alignment delay is deterministic.
date = function(fmt)
    if fmt == "%S" then return "15" end
    return os.date(fmt)
end

-- Shared mutable settings table: the module caches this via GetSettings, so
-- mutating it between calls is visible without invalidation.
local minimapSettings = {
    enabled = true,
    showClock = false,
    showCoords = false,
    coordUpdateInterval = 3,
    buttonDrawer = { enabled = false },
    dungeonEye = { enabled = false },
}

local ns = {
    Addon = { db = { profile = { minimapButton = { hide = false } } } },
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    Helpers = {
        GetModuleDB = function() return minimapSettings end,
        CreateDBGetter = function() return function() return {} end end,
        SafeToNumber = function(value, fallback) return tonumber(value) or fallback end,
    },
}

assert(loadfile("modules/minimap/minimap.lua"))("QUI", ns)

local function findUpvalue(func, wanted, seen)
    seen = seen or {}
    if seen[func] then return nil end
    seen[func] = true
    local i = 1
    while true do
        local name, value = debug.getupvalue(func, i)
        if not name then return nil end
        if name == wanted then return value end
        if type(value) == "function" then
            local found = findUpvalue(value, wanted, seen)
            if found then return found end
        end
        i = i + 1
    end
end

local Minimap_Module = assert(ns.Addon.Minimap, "minimap module should be exported on QUICore")
local StartUpdateTickers = assert(findUpvalue(Minimap_Module.Refresh, "StartUpdateTickers"),
    "StartUpdateTickers should be reachable from Refresh")

local function liveHandles(kind)
    local live = {}
    for _, h in ipairs(timerLog) do
        if h.kind == kind and not h.canceled then live[#live + 1] = h end
    end
    return live
end

-- 1) Both features off → no clock timer, no coords ticker.
StartUpdateTickers()
assert(#liveHandles("timer") == 0, "no clock timer while showClock is off")
assert(#liveHandles("ticker") == 0, "no coords ticker while showCoords is off")

-- 2) Clock on → exactly one one-shot timer aligned to the next minute
--    (second-of-minute stubbed to 15 → delay 60.1 - 15 = 45.1); no 1s ticker.
minimapSettings.showClock = true
StartUpdateTickers()
local timers = liveHandles("timer")
assert(#timers == 1, "clock on: exactly one live one-shot timer, got " .. #timers)
assert(math.abs(timers[1].interval - 45.1) < 1e-9,
    "minute-aligned delay expected 45.1, got " .. tostring(timers[1].interval))
assert(#liveHandles("ticker") == 0, "clock must not create a repeating ticker")

-- 3) Firing the timer re-arms the chain with a freshly computed delay.
timers[1].canceled = true  -- a fired one-shot is spent; mark it so liveHandles skips it
timers[1].cb()
local rearmed = liveHandles("timer")
assert(#rearmed == 1, "clock chain re-arms after firing, got " .. #rearmed)
assert(math.abs(rearmed[1].interval - 45.1) < 1e-9,
    "re-armed delay recomputed from date(\"%S\"), got " .. tostring(rearmed[1].interval))

-- 4) Coords on → one ticker at coordUpdateInterval; restart cancels the old
--    clock timer and arms a fresh one.
minimapSettings.showCoords = true
local before = liveHandles("timer")[1]
StartUpdateTickers()
assert(before.canceled, "restart must cancel the previous clock timer")
local tickers = liveHandles("ticker")
assert(#tickers == 1, "coords on: exactly one live ticker, got " .. #tickers)
assert(tickers[1].interval == 3,
    "coords ticker uses coordUpdateInterval, got " .. tostring(tickers[1].interval))
assert(#liveHandles("timer") == 1, "clock timer re-armed on restart")

-- 5) Both off again → restart cancels everything and creates nothing new.
minimapSettings.showClock = false
minimapSettings.showCoords = false
StartUpdateTickers()
assert(#liveHandles("timer") == 0, "clock off: timer canceled and not re-created")
assert(#liveHandles("ticker") == 0, "coords off: ticker canceled and not re-created")

print("OK: minimap_update_tickers_test")
