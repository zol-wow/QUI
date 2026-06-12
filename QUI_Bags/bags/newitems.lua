---------------------------------------------------------------------------
-- Bags: new-item tracking (the glow's decision layer).
--
-- Model: GUID-keyed SESSION store (module-local table, never saved).
-- Store values:
--   firstSeen epoch  — observed, glow-eligible until timeout or hover
--   0 (tombstone)    — seen; a known entry, so Record never resurrects it
--
-- Why session-local (in-game finding, first release candidate): the
-- original char-SV store deliberately let glows survive a reload, which
-- read as a bug in play — and worse, it made any mis-baseline PERMANENT:
-- one bad walk stamped every long-held item "new" and the store carried
-- that across reloads. A reload now always starts from a clean slate.
--
-- Priming window: activation (login or mid-session enable) baselines every
-- item currently in bags 0–5 to seen, then KEEPS re-baselining on every
-- BagsChanged for PRIMING_WINDOW_SEC, takes a final catch-up sweep, and
-- only then arms CheckSlot. The original single-shot walk raced the login
-- container-data waves: GUIDs unreadable at that one instant were missed,
-- and the next dress pass recorded the whole bag as new (blanket glow on
-- first enable). Container data arrives in bursts, so the baseline must
-- too. Items looted inside the window baseline to seen and never glow —
-- the window is short and the alternative readmits the race.
--
-- CheckSlot is INERT until the window closes (no recording, no glow): a
-- bag window opened before then renders LAST session's cached slots, and
-- recording those would stamp long-held items as new. OnDisable
-- (StopUI) wipes the store and drops the gate so a disable/enable
-- cycle re-runs the full window before tracking resumes.
--
-- GUID access (verified, ItemDocumentation.lua): C_Item.GetItemGUID(
-- itemLocation) → WOWGUID, non-nilable — invalid locations ERROR rather
-- than return nil, so every call sits behind C_Item.DoesItemExist(loc)
-- (→ bool) plus a pcall (transient bag churn between cache and live state).
--
-- Scope: BAG window, live mode only. Bank/guild/cached dressing never calls
-- CheckSlot — withdrawals glow when they land in bags, which is the point.
--
-- Pure core (Record/IsNew/MarkSeen/Baseline/SeenAll) takes store + now —
-- TDD'd in tests/unit/bags_newitems_test.lua.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local NewItems = {}
Bags.NewItems = NewItems

local SEEN = 0        -- tombstone value: known but not glow-eligible
local primed = false  -- true once the activation priming window has closed
local sessionStore = {} -- session store: [guid] = firstSeen epoch | SEEN
local windowToken     -- identity of the pending window close; nil = no window
local busHooked = false

local PRIMING_WINDOW_SEC = 5

---------------------------------------------------------------------------
-- Pure core (injectable store/now — no WoW surface)
---------------------------------------------------------------------------

--- First observation of a GUID records firstSeen; known GUIDs (including
--- seen tombstones) are left untouched. Returns true when recorded.
function NewItems.Record(store, guid, now)
    if not store or not guid or store[guid] ~= nil then return false end
    store[guid] = now
    return true
end

--- Glow-eligible: tracked, not a seen tombstone, and inside the timeout
--- window (strict — an entry exactly timeoutSec old has expired).
function NewItems.IsNew(store, guid, now, timeoutSec)
    local firstSeen = store and guid and store[guid]
    if not firstSeen or firstSeen == SEEN then return false end
    return (now - firstSeen) < timeoutSec
end

--- Tombstone a TRACKED entry (hover). Untracked GUIDs are ignored — only
--- Record/Baseline create entries, so the store stays bag-bounded.
function NewItems.MarkSeen(store, guid)
    if store and guid and store[guid] ~= nil then
        store[guid] = SEEN
    end
end

--- Priming walk: an untracked present item becomes seen (never glows); a
--- tracked entry is left untouched, so repeat sweeps inside the priming
--- window are idempotent.
function NewItems.Baseline(store, guid)
    if store and guid and store[guid] == nil then
        store[guid] = SEEN
    end
end

--- The "clear new" sweep: every tracked GUID tombstones at once (all glows
--- end). Entries stay — the store is session-local and bag-bounded.
function NewItems.SeenAll(store)
    if not store then return end
    for guid in pairs(store) do
        store[guid] = SEEN
    end
end

---------------------------------------------------------------------------
-- Wrapper layer (settings + session store + live GUID access)
---------------------------------------------------------------------------

local function GetGlowConfig()
    local s = GetSettings()
    return s and s.behavior and s.behavior.newItemGlow or nil
end

local function TimeoutSeconds(glow)
    return ((glow and glow.timeoutMinutes) or 30) * 60
end

--- Resolve a live slot's GUID behind the full guard chain. Returns nil
--- whenever the GUID can't be (or shouldn't be) read.
local function SlotGUID(bagID, slot)
    if not (ItemLocation and C_Item and C_Item.DoesItemExist and C_Item.GetItemGUID) then
        return nil
    end
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    local ok, guid = pcall(C_Item.GetItemGUID, loc)
    if ok then return guid end
    return nil
end

--- One baseline sweep over the live bags. Repeated freely inside the
--- priming window; Baseline never clobbers an existing entry.
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

-- Re-baseline on every scanner publish while the window is open — login
-- (and enable-time) container data lands in waves, and any wave can carry
-- GUIDs the previous sweep couldn't read yet.
local function OnBagsChangedPrePrime()
    if not primed then
        BaselineLiveBags()
    end
end

local function UnhookBus()
    if busHooked and Bags.Bus and Bags.Bus.Unsubscribe then
        Bags.Bus.Unsubscribe("BagsChanged", OnBagsChangedPrePrime)
        busHooked = false
    end
end

local function ClosePrimingWindow(token)
    if token ~= windowToken then return end -- superseded by disable/re-enable
    windowToken = nil
    BaselineLiveBags() -- final catch-up sweep
    primed = true
    UnhookBus()
end

--- Dress-time entry point (bag window, live mode, occupied slots only).
--- Records an unseen GUID as first-observed-now; returns the GUID when the
--- item is currently glow-eligible, nil otherwise.
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

--- Hover handler (item button OnEnter post-hook): the glow is done.
function NewItems.MarkSlotSeen(guid)
    NewItems.MarkSeen(sessionStore, guid)
end

--- Module activation (login or mid-session enable): wipe the session
--- store, open the priming window (baseline now + on every BagsChanged),
--- and arm tracking when it closes. Headless harnesses without C_Timer
--- close the window synchronously.
function NewItems.OnLogin()
    WipeStore()
    primed = false
    BaselineLiveBags()
    if Bags.Bus and Bags.Bus.Subscribe and not busHooked then
        Bags.Bus.Subscribe("BagsChanged", OnBagsChangedPrePrime)
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

--- Module disable (StopUI): wipe the session state and go inert
--- until a re-enable has re-run the full priming window.
function NewItems.OnDisable()
    primed = false
    windowToken = nil
    WipeStore()
    UnhookBus()
end

--- The user-facing "clear new" affordance (/quibags clearnew): tombstone
--- everything and re-dress the bag window so the glows drop immediately.
function NewItems.ClearAllNew()
    NewItems.SeenAll(sessionStore)
    if Bags.Bus then Bags.Bus.Publish("BagsChanged") end
end

--- Test-only: expose the session store so the headless suite can assert
--- the no-write guarantees (unprimed/disabled CheckSlot must stay inert).
function NewItems._SessionStore()
    return sessionStore
end
