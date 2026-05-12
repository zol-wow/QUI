local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Scheduler
--
-- Central event bus and coalesced runtime update scheduler for the owned
-- engine. Existing modules keep their public APIs, but delegate bus/update
-- mechanics here so event cadence has a single owner.
---------------------------------------------------------------------------

local CDMScheduler = {}
ns.CDMScheduler = CDMScheduler

local type = type
local table_remove = table.remove

---------------------------------------------------------------------------
-- Event bus
---------------------------------------------------------------------------

local _subscribers = {}

function CDMScheduler.Publish(eventName, ...)
    local list = _subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end

    local snapshot = {}
    for i = 1, n do
        snapshot[i] = list[i]
    end

    for i = 1, n do
        xpcall(snapshot[i], geterrorhandler(), eventName, ...)
    end
end

function CDMScheduler.Subscribe(eventName, handler)
    if type(eventName) ~= "string" or type(handler) ~= "function" then return end
    local list = _subscribers[eventName]
    if not list then
        list = {}
        _subscribers[eventName] = list
    end
    list[#list + 1] = handler
end

function CDMScheduler.Unsubscribe(eventName, handler)
    local list = _subscribers[eventName]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table_remove(list, i)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Runtime update coalescing
---------------------------------------------------------------------------

local UPDATE_COOLDOWN = "cooldown"
local UPDATE_FULL = "full"

local _updateFrame = CreateFrame("Frame")
local _handler = nil
local _getDelay = nil
local _isEnabled = nil
local _onCancel = nil
local _pending = false
local _elapsed = 0
local _delay = 0.05
local _mode = UPDATE_COOLDOWN
local _trustIsOnGCD = false

local function CancelRuntimeUpdate()
    _updateFrame:SetScript("OnUpdate", nil)
    _pending = false
    _elapsed = 0
    _mode = UPDATE_COOLDOWN
    _trustIsOnGCD = false
    if _onCancel then
        _onCancel()
    end
end

local function RuntimeUpdateOnUpdate(self, elapsed)
    _elapsed = _elapsed + elapsed
    if _elapsed < _delay then return end

    local handler = _handler
    local mode = _mode
    local trustIsOnGCD = _trustIsOnGCD

    self:SetScript("OnUpdate", nil)
    _pending = false
    _elapsed = 0
    _mode = UPDATE_COOLDOWN
    _trustIsOnGCD = false

    if handler then
        handler(mode, trustIsOnGCD)
    end
end

function CDMScheduler.SetRuntimeUpdateHandler(config)
    if type(config) == "function" then
        _handler = config
        _getDelay = nil
        _isEnabled = nil
        _onCancel = nil
        return
    end

    if type(config) ~= "table" then return end
    _handler = config.run
    _getDelay = config.getDelay
    _isEnabled = config.isEnabled
    _onCancel = config.onCancel
end

function CDMScheduler.ScheduleRuntimeUpdate(fast, mode, trustIsOnGCD)
    if _isEnabled and not _isEnabled() then
        CancelRuntimeUpdate()
        return
    end

    mode = (mode == UPDATE_FULL) and UPDATE_FULL or UPDATE_COOLDOWN
    local delay = (_getDelay and _getDelay(fast, mode, trustIsOnGCD == true)) or 0.05

    if _pending then
        if mode == UPDATE_FULL then
            _mode = UPDATE_FULL
        end
        if trustIsOnGCD then
            _trustIsOnGCD = true
        end
        if delay < _delay then
            _delay = delay
        end
        return
    end

    _pending = true
    _elapsed = 0
    _delay = delay
    _mode = mode
    _trustIsOnGCD = trustIsOnGCD == true
    _updateFrame:SetScript("OnUpdate", RuntimeUpdateOnUpdate)
end

function CDMScheduler.CancelRuntimeUpdate()
    CancelRuntimeUpdate()
end

function CDMScheduler.IsRuntimeUpdatePending()
    return _pending
end

function CDMScheduler.GetStats()
    return {
        updatePending = _pending,
        updateMode = _mode,
        trustIsOnGCD = _trustIsOnGCD,
    }
end
