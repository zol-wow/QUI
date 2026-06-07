local _, ns = ...
---------------------------------------------------------------------------
-- CDM Runtime Store
--
-- Compatibility facade over frame-owned runtime facts. Icons and bars are
-- the runtime store; this module does not keep a central key-indexed cache.
---------------------------------------------------------------------------

local CDMRuntimeStore = {}
ns.CDMRuntimeStore = CDMRuntimeStore

local type = type
local tostring = tostring
local pairs = pairs
local wipe = wipe

local _version = 0
local _compatState

local function EnsureFrameState(frame)
    if not frame then return nil end
    local state = frame._cdmRuntimeState
    if not state then
        state = {}
        frame._cdmRuntimeState = state
    end
    return state
end

local function ValueID(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function ResolveEntryKeyParts(entry, fallbackContainer)
    if not entry then return nil end
    local containerKey = entry.viewerType or fallbackContainer or "unknown"
    local entryType = entry.type or "spell"
    local entryID = entry.id or entry.spellID or entry.overrideSpellID or entry.name or "unknown"
    local instanceKey = entry._instanceKey or entry.position or entry.index or ""
    return containerKey, entryType, entryID, instanceKey
end

local function BuildEntryKeyFromParts(containerKey, entryType, entryID, instanceKey)
    return containerKey .. ":" .. entryType .. ":" .. ValueID(entryID) .. ":" .. ValueID(instanceKey)
end

local function GetFrameEntryKey(frame, fallbackContainer)
    if not frame then return nil end
    local containerKey, entryType, entryID, instanceKey = ResolveEntryKeyParts(frame._spellEntry, fallbackContainer)
    if not containerKey then return nil end
    return BuildEntryKeyFromParts(containerKey, entryType, entryID, instanceKey)
end

local function CopyStateInto(target, state)
    if type(state) == "table" then
        for k, v in pairs(state) do
            if k ~= "queryCache" then
                target[k] = v
            end
        end
    end
end

function CDMRuntimeStore.BuildEntryKey(entry, fallbackContainer)
    local containerKey, entryType, entryID, instanceKey = ResolveEntryKeyParts(entry, fallbackContainer)
    if not containerKey then return nil end
    return BuildEntryKeyFromParts(containerKey, entryType, entryID, instanceKey)
end

function CDMRuntimeStore.Version()
    return _version
end

function CDMRuntimeStore.EnsureFrameState(frame)
    return EnsureFrameState(frame)
end

function CDMRuntimeStore.SetState(key, state)
    if type(key) ~= "string" or key == "" then return nil end
    if not _compatState then
        _compatState = {}
    else
        local epoch = _compatState.epoch or 0
        wipe(_compatState)
        _compatState.epoch = epoch
    end
    CopyStateInto(_compatState, state)
    _compatState.key = key
    _compatState.epoch = (_compatState.epoch or 0) + 1
    _compatState.compatOnly = true
    _version = _version + 1
    return _compatState
end

local function SetFrameState(frame, state, fallbackContainer, frameKind)
    if not frame then return nil end
    local key = GetFrameEntryKey(frame, fallbackContainer)
    if not key then return nil end

    local target = EnsureFrameState(frame)
    local epoch = target.epoch or 0
    local queryCache = target.queryCache
    wipe(target)
    target.epoch = epoch
    if queryCache then
        target.queryCache = queryCache
    end
    CopyStateInto(target, state)
    target.key = key
    target.epoch = (target.epoch or 0) + 1
    target.frameKind = frameKind
    target.frame = frame
    _version = _version + 1
    return target
end

function CDMRuntimeStore.SetIconState(icon, state)
    return SetFrameState(icon, state, nil, "icon")
end

function CDMRuntimeStore.SetBarState(bar, state)
    return SetFrameState(bar, state, "trackedBar", "bar")
end

function CDMRuntimeStore.GetState(key)
    return nil
end

function CDMRuntimeStore.GetFrameState(frame)
    return frame and frame._cdmRuntimeState or nil
end

function CDMRuntimeStore.ClearFrame(frame)
    if not frame then return end
    frame._cdmRuntimeState = nil
    _version = _version + 1
end

function CDMRuntimeStore.ClearAll()
    if _compatState then
        wipe(_compatState)
        _compatState = nil
    end
    _version = _version + 1
end

function CDMRuntimeStore.GetStats()
    return {
        states = 0,
        centralStates = 0,
        compatState = _compatState and 1 or 0,
        version = _version,
    }
end
