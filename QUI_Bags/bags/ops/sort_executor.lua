---------------------------------------------------------------------------
-- Bags ops: lock-aware paced sort executor.
--
-- Start(which[, onDone]) replays SortPlanner output against LIVE container
-- state in paced batches (BATCH_SIZE moves), then yields until the next
-- relevant bus event OR a fallback timer — whichever fires first — and
-- RE-PLANS from fresh live reads (the planner is cheap; re-planning
-- subsumes every deferred/retry concern). Convergence = an empty plan.
--
-- Refusals at Start: already running, InCombatLockdown(), CursorHasItem().
-- Aborts mid-run: OnCombat() (bags.lua routes PLAYER_REGEN_DISABLED here —
-- the moves aren't protected, the spec hard-blocks combat for UX + lock
-- churn), Cancel(), and a pass limit so a non-converging state (persistent
-- locks, deposit-restricted slots) can't spin forever.
--
-- Move mechanics: each move is ClearCursor → Pickup(from) → Pickup(to) →
-- ClearCursor. PickupContainerItem (ContainerDocumentation: containerIndex,
-- slotIndex) picks up on an empty cursor and places/swaps/merges when the
-- cursor holds an item; the trailing ClearCursor returns a merge remainder
-- to its source slot, matching the planner's partial-pour model. Both
-- endpoints' isLocked are checked live before issuing; a locked move is
-- deferred — and because the plan is a SEQUENCE (later from-locations can
-- depend on earlier swaps), a deferred move poisons both its slots so any
-- later move touching them defers too instead of picking up the wrong item.
---------------------------------------------------------------------------
-- luacheck: read globals CursorHasItem
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local SortExecutor = {}
Bags.SortExecutor = SortExecutor

local BATCH_SIZE = 5       -- moves issued per batch before yielding
-- Pass limit = consecutive STALLED passes (re-plan didn't shrink the move
-- list) before declaring non-convergence. A healthy pass strictly shrinks
-- the plan (every executed move fixes at least one target slot / merges at
-- least one partial stack), so counting stalls instead of total passes
-- keeps the safety valve while never aborting a legitimately long sort
-- (a full 120-slot scramble needs far more than 8 batches of 5).
local PASS_LIMIT = 8
-- Lock-wait cap: passes allowed to repeat without shrinking WHILE locked
-- endpoints are in play (server-latency tolerance — warband/account-bank
-- moves confirm slowly). 30 × 1.5s bank fallback ≈ 45s before giving up
-- on a never-clearing lock.
local LOCK_PASS_LIMIT = 30
local FALLBACK_DELAY = 0.5 -- seconds; re-plan even if no bus event arrives

-- Informational house print prefix (registry.lua uses red for errors;
-- main.lua/gui_shell.lua use this cyan for neutral user-facing messages).
local PREFIX = Bags.OpsShared.PREFIX

-- Scope: container ID range + the bus events that signal "the server
-- applied our moves" (scanners publish after their drain). Character bank
-- and warband bank tabs are separate scopes so they never sort together.
local SCOPES = {
    bags = { first = 0, last = 5, events = { "BagsChanged" }, label = "bags", fallback = 0.5 },
    characterBank = { first = 6, last = 11, events = { "BankChanged" }, label = "character bank", fallback = 1.5 },
    warbandBank = { first = 12, last = 16, events = { "WarbandChanged" }, label = "warband bank", fallback = 1.5 },
}

local state = nil -- nil = idle; one run at a time

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

---------------------------------------------------------------------------
-- Live state → planner input
---------------------------------------------------------------------------

local function IsBagIgnored(bagID)
    -- DisableAutoSort applicability (verified against FrameXML
    -- ContainerFrame.lua AddButtons_BagCleanup): the backpack does NOT use
    -- the bag-slot flag — it has the standalone GetBackpackAutosortDisabled
    -- API; held bags 1–5 use GetBagSlotFlag(bagID, DisableAutoSort).
    -- Blizzard's cleanup menu exposes the flag on bank-tab bagIDs too, but
    -- QUI's bank tabs don't surface that UI, so bank tabs are pinned to
    -- ignored=false (a bank sort always includes every tab).
    if bagID == 0 then
        return C_Container.GetBackpackAutosortDisabled() and true or false
    end
    if bagID >= 1 and bagID <= 5 then
        return C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.DisableAutoSort) and true or false
    end
    return false
end

-- Items that ARE containers report the family of what they can HOLD from
-- GetItemFamily (long-standing API quirk) — zero those so a reagent pouch
-- sitting in the backpack never "fits" the reagent bag.
-- Enum.ItemClass.Container = 1 (ItemConstantsDocumentation.lua:207).
local ITEM_CLASS_CONTAINER = (Enum and Enum.ItemClass and Enum.ItemClass.Container) or 1

-- Universal reagent bag = BagIndex 5 (BagIndexConstantsDocumentation; mirrors
-- Blizzard's ContainerFrame_IsReagentBag bare id == 5 check).
local REAGENT_BAG_ID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

local function BuildContainers(scope)
    local ItemInfo = Bags.ItemInfo
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
                -- Family mask for specialty-bag assignment (nilable per
                -- ItemDocumentation; nil/0 = fits regular bags only, which
                -- is the safe answer while item data is still loading).
                local family = C_Item.GetItemFamily(info.itemID)
                if family and family ~= 0 and derived
                    and derived.classID == ITEM_CLASS_CONTAINER then
                    family = 0
                end
                entry.itemFamily = family
                -- Pending extended data (GetExtended → nil) leaves name/
                -- ilvl/expacID/maxStack nil; the planner sorts nils last.
                local ext = ItemInfo.GetExtended(info.itemID, info.hyperlink)
                if ext then
                    entry.name = ext.name
                    entry.ilvl = ext.ilvl
                    entry.expacID = ext.expacID
                    entry.maxStack = ext.maxStack
                    -- isCraftingReagent: reagent-bag eligibility. nil while item
                    -- data loads → not-reagent (conservative; re-plan corrects).
                    entry.isReagent = ext.isReagent
                end
                slots[slot] = entry
            end
        end
        -- bagFamily: GetContainerNumFreeSlots second return (nilable per
        -- ContainerDocumentation; nil → unrestricted). Non-zero marks an OLD
        -- profession bag (herb/enchant/…) for the planner's family-mask path.
        local _, bagFamily = C_Container.GetContainerNumFreeSlots(bagID)
        containers[#containers + 1] = {
            bagID = bagID,
            size = size,
            slots = slots,
            ignored = IsBagIgnored(bagID),
            family = bagFamily or 0,
            -- The universal reagent bag is bagID 5 and lives OUTSIDE the
            -- family-mask system (Blizzard's ContainerFrame_IsReagentBag is a
            -- bare id == 5 check; GetContainerNumFreeSlots/GetItemFamily don't
            -- reliably flag it). Mark it so the planner gates it on isReagent.
            reagent = (bagID == REAGENT_BAG_ID),
        }
    end
    return containers
end

-- Shared live-state reader: Transfers.FillReagentBag feeds the reagent-fill
-- planner with the same container shape the sort planner consumes.
SortExecutor.BuildContainers = BuildContainers

---------------------------------------------------------------------------
-- Run lifecycle
---------------------------------------------------------------------------

local function Finish(ok, reason)
    local run = state
    state = nil
    for _, ev in ipairs(run.scope.events) do
        Bags.Bus.Unsubscribe(ev, run.busHandler)
    end
    if ok then
        print(("%s Sorted %s: %d move%s in %d pass%s."):format(
            PREFIX, run.scope.label, run.moved, run.moved == 1 and "" or "s",
            run.passes, run.passes == 1 and "" or "es"))
    elseif reason == "combat" then
        print(PREFIX .. " Sort aborted: entered combat.")
    elseif reason == "passes" then
        print(("%s Sort stopped before converging after %d move%s (locked or restricted slots?)."):format(
            PREFIX, run.moved, run.moved == 1 and "" or "s"))
    end -- cancel: silent — user-initiated
    if run.onDone then run.onDone(ok, reason) end
end

local function IsMoveBlocked(blocked, m)
    if blocked[m.fromBag .. ":" .. m.fromSlot] or blocked[m.toBag .. ":" .. m.toSlot] then
        return true
    end
    -- Live lock checks on both endpoints. GetContainerItemInfo may return
    -- nothing (doc: MayReturnNothing) — an empty from-slot means the plan
    -- went stale under us, treat it as blocked; an empty to-slot is fine.
    local fromInfo = C_Container.GetContainerItemInfo(m.fromBag, m.fromSlot)
    if not fromInfo or fromInfo.isLocked then return true end
    local toInfo = C_Container.GetContainerItemInfo(m.toBag, m.toSlot)
    if toInfo and toInfo.isLocked then return true end
    return false
end

local function RunPass()
    state.waitToken = nil -- consume the wait; the rival trigger no-ops
    state.passes = state.passes + 1

    local s = GetSettings()
    local behavior = s and s.behavior
    local plan = Bags.SortPlanner.Plan(BuildContainers(state.scope), {
        key = behavior and behavior.sortKey or nil,
        reverse = behavior and behavior.sortReverse or false,
        fillFromBottom = behavior and behavior.fillFromBottom or false,
    })
    if #plan == 0 then
        Finish(true) -- converged: nothing left to move (deferred moves were
        return       -- subsumed by this re-plan, so empty really means done)
    end
    -- Non-convergence valve: the re-planned move list must shrink between
    -- passes. A non-shrinking pass right after one that hit LOCKED endpoints
    -- is just server latency (warband moves confirm slowly) — those wait on
    -- a separate, much larger cap instead of the stall valve. Only a
    -- lock-free non-shrinking pass (server rejecting/ignoring pickups)
    -- counts against PASS_LIMIT.
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

    local blocked = {} -- "bag:slot" → true (deferred-move poisoning)
    local issued = 0
    state.sawLock = false
    for i = 1, #plan do
        if issued >= BATCH_SIZE then break end
        local m = plan[i]
        if IsMoveBlocked(blocked, m) then
            -- Defer: not retried inside this pass — the next re-plan reads
            -- live state and re-derives whatever still needs to happen.
            state.sawLock = true
            blocked[m.fromBag .. ":" .. m.fromSlot] = true
            blocked[m.toBag .. ":" .. m.toSlot] = true
        else
            -- Cursor hygiene: never issue with a dirty cursor; never leave
            -- a merge remainder dangling (ClearCursor returns it home).
            ClearCursor()
            C_Container.PickupContainerItem(m.fromBag, m.fromSlot)
            C_Container.PickupContainerItem(m.toBag, m.toSlot)
            ClearCursor()
            issued = issued + 1
            state.moved = state.moved + 1
        end
    end
    state.lastIssued = issued

    -- Yield: continue on the next scope bus event OR the fallback timer,
    -- whichever fires first. The token guards the double trigger — and,
    -- being identity-compared, makes stale timers from earlier batches
    -- inert (they captured a different token). Bank scopes use a longer
    -- fallback (account-bank moves confirm slowly server-side).
    local token = {}
    state.waitToken = token
    C_Timer.After(state.scope.fallback or FALLBACK_DELAY, function()
        if state and state.waitToken == token then RunPass() end
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Start a sort run. which = "bags" (containers 0–5), "characterBank"
--- (tabs 6–11), or "warbandBank" (tabs 12–16). opts.tabID may restrict the
--- run to one container inside the selected scope. The CALLER gates on an
--- open bank session — the executor re-checks only combat. onDone(ok, reason)
--- fires once when the run ends: (true) converged,
--- (false, "combat"|"passes"|"cancel") aborted.
--- Returns true, or false + reason
--- ("running"|"busy"|"combat"|"cursor"|"which") when refused — refusals
--- never invoke onDone.
function SortExecutor.Start(which, onDone, opts)
    local scope = ResolveScope(which, opts)
    if not scope then return false, "which" end
    if state then return false, "running" end
    -- shared ops gate: cursor/slot ops must never overlap (wrong-item hazards)
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
    -- Synthetic re-dress pings carry {}; scanner publishes never do (they
    -- fire only after at least one container changed — see data/bus.lua).
    -- Argument shapes: BagsChanged/BankChanged → (eventName, charKey,
    -- changed); WarbandChanged → (eventName, changed).
    state.busHandler = function(eventName, a, b)
        local changed = (eventName == "WarbandChanged") and a or b
        if changed and #changed == 0 then
            -- Synthetic lock/cooldown re-dress ping (bags.lua publishes {}
            -- on ITEM_LOCK_CHANGED). Worth a re-plan only when the last
            -- pass was a pure lock-wait (issued nothing) — a lock-cleared
            -- edge is exactly the resume signal it's waiting for; passes
            -- that issued moves keep riding scanner publishes/fallback.
            if state and state.waitToken and state.lastIssued == 0 then RunPass() end
            return
        end
        if state and state.waitToken then RunPass() end
    end
    for _, ev in ipairs(scope.events) do
        Bags.Bus.Subscribe(ev, state.busHandler)
    end
    RunPass() -- may converge (and Finish) synchronously on a sorted bag
    return true
end

function SortExecutor.IsRunning()
    return state ~= nil
end

--- Combat abort — bags.lua routes PLAYER_REGEN_DISABLED here.
function SortExecutor.OnCombat()
    if not state then return end
    Finish(false, "combat")
end

--- User abort. Silent (no chat message); onDone(false, "cancel").
function SortExecutor.Cancel()
    if not state then return end
    Finish(false, "cancel")
end
