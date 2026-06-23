-- tests/unit/collections_journal_font_lock_test.lua
-- Run: lua tests/unit/collections_journal_font_lock_test.lua
--
-- Collection list rows are Blizzard-owned/pool-owned and reapply font objects
-- when mount/pet/heirloom entries are rebound. The Collections skin must lock
-- active and future row text, not only skin the parent frame once.

-- luacheck: globals _G hooksecurefunc

local callbacks = {}
local calls = {}
local scrollHooks = {}
local frameData = setmetatable({}, { __mode = "k" })
local tableHooks = {}

function hooksecurefunc(target, method, callback)
    assert(type(target) == "table", "collections test only expects table-method hooks")
    assert(type(method) == "string", "hook method must be named")
    assert(type(callback) == "function", "hook callback must be callable")
    local original = assert(target[method], "missing hooked method " .. method)
    tableHooks[target] = tableHooks[target] or {}
    tableHooks[target][method] = callback
    target[method] = function(self, ...)
        local results = { original(self, ...) }
        callback(self, ...)
        return unpack(results)
    end
end

local mountRow = { name = "mountRow" }
local petRow = { name = "petRow" }
local heirloomEntry = { name = "heirloomEntry" }
local heirloomHeader = { name = "heirloomHeader" }

_G.CollectionsJournal = { name = "CollectionsJournal" }
_G.MountJournal = {
    ScrollBox = {
        name = "MountJournalScrollBox",
        ForEachFrame = function(_, callback) callback(mountRow) end,
    },
}
_G.PetJournal = {
    ScrollBox = {
        name = "PetJournalScrollBox",
        ForEachFrame = function(_, callback) callback(petRow) end,
    },
}
_G.HeirloomsJournal = {
    heirloomEntryFrames = { heirloomEntry },
    heirloomHeaderFrames = { heirloomHeader },
    AcquireFrame = function(_, framePool, numInUse)
        return framePool and framePool[numInUse]
    end,
    RefreshView = function() end,
    UpdateButton = function() end,
}

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = {
                            skinCollections = true,
                        },
                    },
                },
            }
        end,
    },
    Registry = {
        Register = function() end,
    },
}

ns.SkinBase = {
    RefreshFrameBackdropColors = function() end,
    IsSkinned = function() return false end,
    SkinButtonFrameTemplate = function(frame)
        calls.buttonFrame = frame
    end,
    SkinTabGroup = function(tabs, owner)
        calls.tabs = { tabs = tabs, owner = owner }
    end,
    SkinFrameText = function(frame, opts)
        calls[frame] = opts or {}
    end,
    LockFrameTextObjects = function(frame, depth)
        calls["lock:" .. tostring(frame.name)] = depth
    end,
    ApplyButtonFontObjectsDeep = function(frame, depth)
        calls["btnfont:" .. tostring(frame.name)] = depth
    end,
    HookScrollBoxAcquired = function(scrollBox, callback)
        scrollHooks[scrollBox] = callback
    end,
    -- Mirror the real SkinBase.HookScrollBoxRowFonts (core/uikit.lua): a guarded
    -- per-row font lock that runs the recursive pass ONCE per row, plus the
    -- initial visible-row pass that HookScrollBoxAcquired performs internally.
    HookScrollBoxRowFonts = function(scrollBox, depth)
        if not scrollBox then return end
        local function lockRow(row)
            if not row or (frameData[row] and frameData[row].qListRowFonted) then return end
            ns.SkinBase.SkinFrameText(row, { recurse = true })
            ns.SkinBase.LockFrameTextObjects(row, depth or 3)
            ns.SkinBase.SetFrameData(row, "qListRowFonted", true)
        end
        scrollHooks[scrollBox] = lockRow
        if scrollBox.ForEachFrame then scrollBox.ForEachFrame(scrollBox, lockRow) end
    end,
    MarkSkinned = function(frame)
        calls.marked = frame
    end,
    SetFrameData = function(frame, key, value)
        frameData[frame] = frameData[frame] or {}
        frameData[frame][key] = value
    end,
    GetFrameData = function(frame, key)
        local data = frameData[frame]
        return data and data[key]
    end,
    OnAddOnLoaded = function(addon, callback)
        callbacks[addon] = callback
    end,
}

assert(loadfile("QUI_Skinning/skinning/frames/journals.lua"))("QUI", ns)
assert(type(callbacks.Blizzard_Collections) == "function", "Collections load hook must be registered")

callbacks.Blizzard_Collections()

assert(calls.buttonFrame == _G.CollectionsJournal, "Collections Journal must still get frame chrome")
-- Static text face now comes from the global font-object override (font_system.lua
-- ApplyGlobalDefaultFont); SkinFrameText recurse and LockFrameTextObjects on the
-- parent frame are no longer called — interactive reverts on bare-root surfaces accepted.
assert(calls["lock:mountRow"] == 3, "visible mount rows must be locked")
assert(calls["lock:petRow"] == 3, "visible pet rows must be locked")
-- Heirloom frames: LockFrameTextObjects was removed from LockHeirloomFrame.
-- Static text now from global object override; interactive reverts on heirloom rows accepted.
-- New contract: the frame is marked qHeirloomTextLocked via SetFrameData.
assert(ns.SkinBase.GetFrameData(heirloomEntry, "qHeirloomTextLocked"),
    "visible heirloom entry frames must be marked as locked")
assert(ns.SkinBase.GetFrameData(heirloomHeader, "qHeirloomTextLocked"),
    "visible heirloom header frames must be marked as locked")
assert(scrollHooks[_G.MountJournal.ScrollBox], "MountJournal ScrollBox must lock acquired rows")
assert(scrollHooks[_G.PetJournal.ScrollBox], "PetJournal ScrollBox must lock acquired rows")
assert(tableHooks[_G.HeirloomsJournal] and tableHooks[_G.HeirloomsJournal].AcquireFrame,
    "HeirloomsJournal must hook AcquireFrame, not a nonexistent ScrollBox")
assert(tableHooks[_G.HeirloomsJournal] and tableHooks[_G.HeirloomsJournal].RefreshView,
    "HeirloomsJournal must re-check active pools on RefreshView")
assert(tableHooks[_G.HeirloomsJournal] and tableHooks[_G.HeirloomsJournal].UpdateButton,
    "HeirloomsJournal must relock entries after UpdateButton font-object resets")

-- A NEWLY acquired row gets the full recursive lock pass.
local newMountRow = { name = "newMountRow" }
scrollHooks[_G.MountJournal.ScrollBox](newMountRow)
assert(calls["lock:newMountRow"] == 3, "newly acquired mount rows must be locked")

-- A re-acquired row that was already fonted is skipped — the recursive pass
-- runs once per pooled row; the LockFontObject hooks installed on the first
-- pass re-assert the QUI face on later rebinds. Re-walking every acquire was
-- the open-window hitch this guard removes.
calls["lock:mountRow"] = nil
scrollHooks[_G.MountJournal.ScrollBox](mountRow)
assert(calls["lock:mountRow"] == nil, "already-fonted rows must NOT re-run the recursive lock pass")

local newHeirloomEntry = { name = "newHeirloomEntry" }
_G.HeirloomsJournal.heirloomEntryFrames[2] = newHeirloomEntry
_G.HeirloomsJournal:AcquireFrame(_G.HeirloomsJournal.heirloomEntryFrames, 2)
assert(ns.SkinBase.GetFrameData(newHeirloomEntry, "qHeirloomTextLocked"),
    "newly acquired heirloom entries must be marked as locked")

local newHeirloomHeader = { name = "newHeirloomHeader" }
_G.HeirloomsJournal.heirloomHeaderFrames[2] = newHeirloomHeader
_G.HeirloomsJournal:RefreshView()
assert(ns.SkinBase.GetFrameData(newHeirloomHeader, "qHeirloomTextLocked"),
    "refreshed heirloom header frames must be marked as locked")

local updatedHeirloomEntry = { name = "updatedHeirloomEntry" }
_G.HeirloomsJournal:UpdateButton(updatedHeirloomEntry)
assert(ns.SkinBase.GetFrameData(updatedHeirloomEntry, "qHeirloomTextLocked"),
    "UpdateButton must mark heirloom entry as locked")

print("OK: collections_journal_font_lock_test")
