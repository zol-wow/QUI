-- tests/unit/groupframes_mrb_hotfix_rebuild_test.lua
-- 12.1 COOLDOWN_VIEWER_TABLE_HOTFIXED: a server-side hotfix re-shapes
-- C_CooldownViewer.GetGroupBuffItems, so the missing-raid-buff catalog must
-- subscribe and rebuild — otherwise results stay stale until /reload.
-- Run: lua tests/unit/groupframes_mrb_hotfix_rebuild_test.lua

_G.issecretvalue = function() return false end
_G.C_Timer = { After = function() end }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
_G.UnitClass = function() return "Mage", "MAGE" end

local registeredByFrame = {}
local handlerByFrame = {}
function CreateFrame()
    local f = {}
    registeredByFrame[f] = {}
    f.RegisterEvent = function(self, event)
        registeredByFrame[self][event] = true
    end
    f.RegisterUnitEvent = function(self, event)
        registeredByFrame[self][event] = true
    end
    f.SetScript = function(self, kind, fn)
        if kind == "OnEvent" then handlerByFrame[self] = fn end
    end
    return f
end

local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"))("QUI", ns)
local MRB = assert(ns.QUI_GroupFrameMissingRaidBuffs)

-- Find the snapshot event frame: the one that registered the hotfix event.
local snapshotFrame
for frame, events in pairs(registeredByFrame) do
    if events["COOLDOWN_VIEWER_TABLE_HOTFIXED"] then
        snapshotFrame = frame
        break
    end
end
assert(snapshotFrame,
    "COOLDOWN_VIEWER_TABLE_HOTFIXED must be registered on the snapshot event frame")
local handler = assert(handlerByFrame[snapshotFrame],
    "snapshot event frame must have an OnEvent handler")

local rebuilds = 0
MRB.RebuildRaidBuffs = function() rebuilds = rebuilds + 1 end
MRB.HasActiveElements = function() return false end -- RefreshAll no-op

handler(snapshotFrame, "COOLDOWN_VIEWER_TABLE_HOTFIXED")
assert(rebuilds == 1,
    "COOLDOWN_VIEWER_TABLE_HOTFIXED must rebuild the group buff catalog")

print("OK groupframes_mrb_hotfix_rebuild_test")
