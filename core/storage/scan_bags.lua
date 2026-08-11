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

function ScanBags.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    local toScan = dirty
    dirty = {}
    hasDirty = false
    local changed = {}
    for bagID in pairs(toScan) do
        rec.bags[bagID] = Storage.ScanCommon.ReadContainer(bagID, Storage.ScanCommon.MakePendingHandler(bagID, ScanBags.MarkDirty))
        changed[#changed + 1] = bagID
    end
    if #changed > 0 then
        Storage.Bus.Publish("BagsChanged", Storage.Store.GetCurrentCharacterKey(), changed)
        return true
    end
    return false
end
