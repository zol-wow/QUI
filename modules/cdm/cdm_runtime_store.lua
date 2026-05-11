local ADDON_NAME, ns = ...
local Helpers = ns.Helpers or {}

---------------------------------------------------------------------------
-- CDM Runtime Store
--
-- One place to snapshot resolved runtime state for owned CDM entries. The
-- store intentionally keeps DurationObjects as values only; they are never
-- used as table keys or inspected by Lua.
---------------------------------------------------------------------------

local CDMRuntimeStore = {}
ns.CDMRuntimeStore = CDMRuntimeStore

local type = type
local tostring = tostring
local pairs = pairs
local wipe = wipe

local _stateByKey = {}
local _keyByFrame = setmetatable({}, { __mode = "k" })
local _stateByFrame = setmetatable({}, { __mode = "k" })
local _version = 0

local function ValueID(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function IsSecretValue(value)
    return Helpers.IsSecretValue and Helpers.IsSecretValue(value) or false
end

local function ValuesEqual(left, right)
    if IsSecretValue(left) or IsSecretValue(right) then
        return nil
    end
    return left == right
end

local function StateEquals(target, state, key)
    if not target then return false end
    if target.key ~= key then return false end
    state = type(state) == "table" and state or nil

    if state then
        for k, v in pairs(state) do
            if ValuesEqual(target[k], v) ~= true then
                return false
            end
        end
    end

    for k, v in pairs(target) do
        if k ~= "epoch" and k ~= "key" and k ~= "frame" and k ~= "frameKind" then
            if not state or ValuesEqual(state[k], v) ~= true then
                return false
            end
        end
    end

    return true
end

function CDMRuntimeStore.BuildEntryKey(entry, fallbackContainer)
    if not entry then return nil end
    local containerKey = entry.viewerType or fallbackContainer or "unknown"
    local entryType = entry.type or "spell"
    local entryID = entry.id or entry.spellID or entry.overrideSpellID or entry.name or "unknown"
    local instanceKey = entry._instanceKey or entry.position or entry.index or ""
    return containerKey .. ":" .. entryType .. ":" .. ValueID(entryID) .. ":" .. ValueID(instanceKey)
end

function CDMRuntimeStore.Version()
    return _version
end

function CDMRuntimeStore.SetState(key, state)
    if type(key) ~= "string" or key == "" then return nil end
    local target = _stateByKey[key]
    if StateEquals(target, state, key) then
        return target
    end
    if not target then
        target = {}
        _stateByKey[key] = target
    else
        local epoch = target.epoch or 0
        wipe(target)
        target.epoch = epoch
    end
    if type(state) == "table" then
        for k, v in pairs(state) do
            target[k] = v
        end
    end
    target.key = key
    target.epoch = (target.epoch or 0) + 1
    _version = _version + 1
    return target
end

function CDMRuntimeStore.SetIconState(icon, state)
    if not icon then return nil end
    local entry = icon._spellEntry
    local key = CDMRuntimeStore.BuildEntryKey(entry)
    if not key then return nil end
    local stored = CDMRuntimeStore.SetState(key, state)
    if stored then
        stored.frameKind = "icon"
        stored.frame = icon
        _keyByFrame[icon] = key
        _stateByFrame[icon] = stored
    end
    return stored
end

function CDMRuntimeStore.SetBarState(bar, state)
    if not bar then return nil end
    local entry = bar._spellEntry
    local key = CDMRuntimeStore.BuildEntryKey(entry, "trackedBar")
    if not key then return nil end
    local stored = CDMRuntimeStore.SetState(key, state)
    if stored then
        stored.frameKind = "bar"
        stored.frame = bar
        _keyByFrame[bar] = key
        _stateByFrame[bar] = stored
    end
    return stored
end

function CDMRuntimeStore.GetState(key)
    return key and _stateByKey[key] or nil
end

function CDMRuntimeStore.GetFrameState(frame)
    return frame and _stateByFrame[frame] or nil
end

function CDMRuntimeStore.ClearFrame(frame)
    if not frame then return end
    local key = _keyByFrame[frame]
    _keyByFrame[frame] = nil
    _stateByFrame[frame] = nil
    if key then
        _stateByKey[key] = nil
        _version = _version + 1
    end
end

function CDMRuntimeStore.ClearAll()
    wipe(_stateByKey)
    wipe(_keyByFrame)
    wipe(_stateByFrame)
    _version = _version + 1
end

function CDMRuntimeStore.GetStats()
    local count = 0
    for _ in pairs(_stateByKey) do
        count = count + 1
    end
    return {
        states = count,
        version = _version,
    }
end
