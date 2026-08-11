-- luacheck: read globals CursorHasItem
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local SortExecutor = {}
Bags.SortExecutor = SortExecutor

local BATCH_SIZE = 5
local PASS_LIMIT = 8
local LOCK_PASS_LIMIT = 30
local FALLBACK_DELAY = 0.5

local PREFIX = Bags.OpsShared.PREFIX

local SCOPES = {
    bags = { first = 0, last = 5, events = { "BagsChanged" }, label = ns.L["bags"], fallback = 0.5 },
    characterBank = { first = 6, last = 11, events = { "BankChanged" }, label = ns.L["character bank"], fallback = 1.5 },
    warbandBank = { first = 12, last = 16, events = { "WarbandChanged" }, label = ns.L["warband bank"], fallback = 1.5 },
}

local state = nil

local function ResolveScope(which, opts)
    local scope = SCOPES[which]
    if not scope then return nil end

    local tabID = opts and opts.tabID
    if tabID == nil then return scope end
    if type(tabID) ~= "number" or tabID ~= math.floor(tabID)
        or tabID < scope.first or tabID > scope.last then
        return nil
    end

    return {
        first = tabID,
        last = tabID,
        events = scope.events,
        label = scope.label,
        fallback = scope.fallback,
    }
end

local function IsBagIgnored(bagID)
    if bagID == 0 then
        return C_Container.GetBackpackAutosortDisabled() and true or false
    end
    if bagID >= 1 and bagID <= 5 then
        return C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.DisableAutoSort) and true or false
    end
    return false
end

local ITEM_CLASS_CONTAINER = (Enum and Enum.ItemClass and Enum.ItemClass.Container) or 1

local REAGENT_BAG_ID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

local function BuildContainers(scope)
    local ItemInfo = Storage.ItemInfo
    local containers = {}
    for bagID = scope.first, scope.last do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        local slots = {}
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info then
                local entry = {
                    itemID = info.itemID,
                    count = info.stackCount,
                    quality = info.quality,
                }
                local derived = ItemInfo.GetDerived(info.itemID)
                if derived then
                    entry.sortClass = derived.classID
                    entry.sortSubClass = derived.subClassID
                end
                local family = C_Item.GetItemFamily(info.itemID)
                if family and family ~= 0 and derived
                    and derived.classID == ITEM_CLASS_CONTAINER then
                    family = 0
                end
                entry.itemFamily = family
                local ext = ItemInfo.GetExtended(info.itemID, info.hyperlink)
                if ext then
                    entry.name = ext.name
                    entry.ilvl = ext.ilvl
                    entry.expacID = ext.expacID
                    entry.maxStack = ext.maxStack
                    entry.isReagent = ext.isReagent
                end
                slots[slot] = entry
            end
        end
        local _, bagFamily = C_Container.GetContainerNumFreeSlots(bagID)
        containers[#containers + 1] = {
            bagID = bagID,
            size = size,
            slots = slots,
            ignored = IsBagIgnored(bagID),
            family = bagFamily or 0,
            reagent = (bagID == REAGENT_BAG_ID),
        }
    end
    return containers
end

SortExecutor.BuildContainers = BuildContainers

local function Finish(ok, reason)
    local run = state
    state = nil
    for _, ev in ipairs(run.scope.events) do
        Storage.Bus.Unsubscribe(ev, run.busHandler)
    end
    if ok then
        print(("%s " .. ns.L["Sorted %s: %d moves in %d passes."]):format(
            PREFIX, run.scope.label, run.moved, run.passes))
    elseif reason == "combat" then
        print(PREFIX .. " " .. ns.L["Sort aborted: entered combat."])
    elseif reason == "passes" then
        print(("%s " .. ns.L["Sort stopped before converging after %d moves (locked or restricted slots?)."]):format(
            PREFIX, run.moved))
    end
    if run.onDone then run.onDone(ok, reason) end
end

local function IsMoveBlocked(blocked, m)
    if blocked[m.fromBag .. ":" .. m.fromSlot] or blocked[m.toBag .. ":" .. m.toSlot] then
        return true
    end
    local fromInfo = C_Container.GetContainerItemInfo(m.fromBag, m.fromSlot)
    if not fromInfo or fromInfo.isLocked then return true end
    local toInfo = C_Container.GetContainerItemInfo(m.toBag, m.toSlot)
    if toInfo and toInfo.isLocked then return true end
    return false
end

local function RunPass()
    state.waitToken = nil
    state.passes = state.passes + 1

    local s = GetSettings()
    local behavior = s and s.behavior
    local plan = Bags.SortPlanner.Plan(BuildContainers(state.scope), {
        key = behavior and behavior.sortKey or nil,
        reverse = behavior and behavior.sortReverse or false,
        fillFromBottom = behavior and behavior.fillFromBottom or false,
    })
    if #plan == 0 then
        Finish(true)
        return
    end
    if state.lastPlanLen and #plan >= state.lastPlanLen then
        if state.sawLock then
            state.lockStalls = state.lockStalls + 1
            if state.lockStalls >= LOCK_PASS_LIMIT then
                Finish(false, "passes")
                return
            end
        else
            state.stalls = state.stalls + 1
            if state.stalls >= PASS_LIMIT then
                Finish(false, "passes")
                return
            end
        end
    else
        state.stalls = 0
        state.lockStalls = 0
    end
    state.lastPlanLen = #plan

    local blocked = {}
    local issued = 0
    state.sawLock = false
    for i = 1, #plan do
        if issued >= BATCH_SIZE then break end
        local m = plan[i]
        if IsMoveBlocked(blocked, m) then
            state.sawLock = true
            blocked[m.fromBag .. ":" .. m.fromSlot] = true
            blocked[m.toBag .. ":" .. m.toSlot] = true
        else
            ClearCursor()
            C_Container.PickupContainerItem(m.fromBag, m.fromSlot)
            C_Container.PickupContainerItem(m.toBag, m.toSlot)
            ClearCursor()
            issued = issued + 1
            state.moved = state.moved + 1
        end
    end
    state.lastIssued = issued

    local token = {}
    state.waitToken = token
    C_Timer.After(state.scope.fallback or FALLBACK_DELAY, function()
        if state and state.waitToken == token then RunPass() end
    end)
end

function SortExecutor.Start(which, onDone, opts)
    local scope = ResolveScope(which, opts)
    if not scope then return false, "which" end
    if state then return false, "running" end
    if Bags.OpsShared.OpsBusy() then
        return false, "busy"
    end
    if InCombatLockdown() then return false, "combat" end
    if CursorHasItem() then return false, "cursor" end

    state = {
        scope = scope,
        passes = 0,
        moved = 0,
        stalls = 0,
        lockStalls = 0,
        sawLock = false,
        lastIssued = 0,
        lastPlanLen = nil,
        onDone = onDone,
        waitToken = nil,
    }
    state.busHandler = function(eventName, a, b)
        local changed = (eventName == "WarbandChanged") and a or b
        if changed and #changed == 0 then
            if state and state.waitToken and state.lastIssued == 0 then RunPass() end
            return
        end
        if state and state.waitToken then RunPass() end
    end
    for _, ev in ipairs(scope.events) do
        Storage.Bus.Subscribe(ev, state.busHandler)
    end
    RunPass()
    return true
end

function SortExecutor.IsRunning()
    return state ~= nil
end

function SortExecutor.OnCombat()
    if not state then return end
    Finish(false, "combat")
end

function SortExecutor.Cancel()
    if not state then return end
    Finish(false, "cancel")
end
