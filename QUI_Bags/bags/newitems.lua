local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local NewItems = {}
Bags.NewItems = NewItems

local SEEN = 0
local primed = false
local sessionStore = {}
local windowToken
local busHooked = false

local PRIMING_WINDOW_SEC = 5

function NewItems.Record(store, guid, now)
    if not store or not guid or store[guid] ~= nil then return false end
    store[guid] = now
    return true
end

function NewItems.IsNew(store, guid, now, timeoutSec)
    local firstSeen = store and guid and store[guid]
    if not firstSeen or firstSeen == SEEN then return false end
    return (now - firstSeen) < timeoutSec
end

function NewItems.MarkSeen(store, guid)
    if store and guid and store[guid] ~= nil then
        store[guid] = SEEN
    end
end

function NewItems.Baseline(store, guid)
    if store and guid and store[guid] == nil then
        store[guid] = SEEN
    end
end

function NewItems.SeenAll(store)
    if not store then return end
    for guid in pairs(store) do
        store[guid] = SEEN
    end
end

local function GetGlowConfig()
    local s = GetSettings()
    return s and s.behavior and s.behavior.newItemGlow or nil
end

local function TimeoutSeconds(glow)
    return ((glow and glow.timeoutMinutes) or 30) * 60
end

local function SlotGUID(bagID, slot)
    if not (ItemLocation and C_Item and C_Item.DoesItemExist and C_Item.GetItemGUID) then
        return nil
    end
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    local ok, guid = ns.SafeCall("best-effort-style", C_Item.GetItemGUID, loc)
    if ok then return guid end
    return nil
end

local function BaselineLiveBags()
    if not (C_Container and C_Container.GetContainerNumSlots) then return end
    for bagID = 0, 5 do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, size do
            NewItems.Baseline(sessionStore, SlotGUID(bagID, slot))
        end
    end
end

local function WipeStore()
    for guid in pairs(sessionStore) do
        sessionStore[guid] = nil
    end
end

local function OnBagsChangedPrePrime()
    if not primed then
        BaselineLiveBags()
    end
end

local function UnhookBus()
    if busHooked and Storage.Bus and Storage.Bus.Unsubscribe then
        Storage.Bus.Unsubscribe("BagsChanged", OnBagsChangedPrePrime)
        busHooked = false
    end
end

local function ClosePrimingWindow(token)
    if token ~= windowToken then return end
    windowToken = nil
    BaselineLiveBags()
    primed = true
    UnhookBus()
end

function NewItems.CheckSlot(bagID, slot, entry)
    if not primed or not entry then return nil end
    local glow = GetGlowConfig()
    if not (glow and glow.enabled) then return nil end
    local guid = SlotGUID(bagID, slot)
    if not guid then return nil end
    local now = time()
    NewItems.Record(sessionStore, guid, now)
    if NewItems.IsNew(sessionStore, guid, now, TimeoutSeconds(glow)) then
        return guid
    end
    return nil
end

function NewItems.MarkSlotSeen(guid)
    NewItems.MarkSeen(sessionStore, guid)
end

function NewItems.OnLogin()
    WipeStore()
    primed = false
    BaselineLiveBags()
    if Storage.Bus and Storage.Bus.Subscribe and not busHooked then
        Storage.Bus.Subscribe("BagsChanged", OnBagsChangedPrePrime)
        busHooked = true
    end
    local token = {}
    windowToken = token
    if C_Timer and C_Timer.After then
        C_Timer.After(PRIMING_WINDOW_SEC, function()
            ClosePrimingWindow(token)
        end)
    else
        ClosePrimingWindow(token)
    end
end

function NewItems.OnDisable()
    primed = false
    windowToken = nil
    WipeStore()
    UnhookBus()
end

function NewItems.ClearAllNew()
    NewItems.SeenAll(sessionStore)
    if Storage.Bus then Storage.Bus.Publish("BagsChanged") end
end

function NewItems._SessionStore()
    return sessionStore
end
