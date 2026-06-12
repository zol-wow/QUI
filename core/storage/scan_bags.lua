---------------------------------------------------------------------------
-- Core storage: player bag scanner (bag IDs 0–5: backpack, bags 1–4,
-- reagent bag). Events mark bags dirty; bags.lua schedules Drain() on the
-- next frame. Slots whose item data isn't loaded yet trigger a re-mark via
-- ScanCommon.MakePendingHandler (success-gated; see scan_common.lua).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanBags = {}
Storage.ScanBags = ScanBags

local TRACKED = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }

local dirty = {}
local hasDirty = false

function ScanBags.MarkDirty(bagID)
    if not TRACKED[bagID] then return end
    dirty[bagID] = true
    hasDirty = true
end

function ScanBags.MarkAllDirty()
    for bagID in pairs(TRACKED) do dirty[bagID] = true end
    hasDirty = true
end

--- Re-read every dirty bag into the store; publishes one BagsChanged event.
--- Returns true when anything was written.
function ScanBags.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end -- transient: dirty marks preserved for the next drain
    -- Snapshot-swap BEFORE reading: ITEM_DATA_LOAD_RESULT is a synchronous
    -- event, so a client-cached item can deliver its load result (and re-mark
    -- this bag) inside ReadContainer. Re-marks must land in the fresh set,
    -- not be wiped by this drain's cleanup.
    local toScan = dirty
    dirty = {}
    hasDirty = false
    local changed = {}
    for bagID in pairs(toScan) do
        rec.bags[bagID] = Storage.ScanCommon.ReadContainer(bagID, Storage.ScanCommon.MakePendingHandler(bagID, ScanBags.MarkDirty))
        changed[#changed + 1] = bagID
    end
    if #changed > 0 then
        -- changed: unordered array of bagIDs (consumers must not assume order)
        Storage.Bus.Publish("BagsChanged", Storage.Store.GetCurrentCharacterKey(), changed)
        return true
    end
    return false
end
