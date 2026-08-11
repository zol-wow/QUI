-- tests/unit/raidmarkers_leader_secure_contract_test.lua
-- Run: lua tests/unit/raidmarkers_leader_secure_contract_test.lua
--
-- Leader toolbar (plan 007) contract test for the raid markers bar:
--   * world-marker row uses the blessed secure worldmarker action with the
--     WORLD_RAID_MARKER_ORDER mapping; left = set, right = clear
--   * the clear-all button carries action="clear" and NO marker attribute
--     (nil marker = ClearRaidMarker(nil) = clear all flares)
--   * strip buttons (ready/roles/pull) are plain buttons, not secure
--   * no secure attribute writes, geometry, or EnableMouse in combat;
--     visibility is alpha-only and reconciles on PLAYER_REGEN_ENABLED
--   * leadership gating shows/hides the two new rows via the coalesced
--     watcher; preview mode bypasses the leadership gate
--   * strip clicks call the party APIs with permission hints

-- Star-first symbol → world marker index (star→yellow 5 … skull→white 8).
-- This is Blizzard's WORLD_RAID_MARKER_ORDER[9 - i]; the in-game bug report
-- that motivated it: shipping ORDER[i] placed every flare mirrored (button 1
-- placed button 8's flare).
local WORLD_MARKER_ORDER = { 5, 6, 3, 2, 7, 1, 4, 8 }

local markersDB = {
    enabled = true,
    growDirection = "RIGHT",
    iconSize = 36,
    spacing = 4,
    borderSize = 2,
    zoom = 0,
    worldMarkers = { enabled = true },
    leaderStrip = { enabled = true, pullSeconds = 12 },
    autoShowForLeader = true,
}

local inCombat = false
local isLeader = false
local isAssistant = false
local inRaid = false
local inGroup = false

local function noop() end

local createdFrames = {}

local function NewTexture(parent)
    return {
        parent = parent,
        SetAllPoints = noop,
        SetTexture = function(self, tex) self.texture = tex end,
        SetAtlas = function(self, atlas) self.atlas = atlas end,
        SetTexCoord = noop,
        SetColorTexture = noop,
        Show = noop,
        Hide = noop,
        ClearAllPoints = noop,
        SetPoint = noop,
    }
end

local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        attributes = {},
        scripts = {},
        events = {},
        registeredClicks = {},
        alpha = 1,
        shown = true,
        mouseEnabled = true,
    }
    frame.SetAttribute = function(self, attr, value)
        assert(not inCombat, "raid markers bar must not mutate secure attributes in combat")
        self.attributes[attr] = value
    end
    frame.GetAttribute = function(self, attr) return self.attributes[attr] end
    frame.RegisterForClicks = function(self, ...)
        self.registeredClicks = { ... }
    end
    frame.SetScript = function(self, script, handler) self.scripts[script] = handler end
    frame.GetScript = function(self, script) return self.scripts[script] end
    frame.RegisterEvent = function(self, event) self.events[event] = true end
    frame.RegisterForDrag = noop
    frame.SetMovable = noop
    frame.SetClampedToScreen = noop
    frame.SetFrameStrata = noop
    frame.SetSize = function(self)
        assert(not inCombat, "raid markers bar must not resize frames in combat")
    end
    frame.SetPoint = function(self)
        assert(not inCombat, "raid markers bar must not reposition frames in combat")
    end
    frame.ClearAllPoints = function(self)
        assert(not inCombat, "raid markers bar must not clear frame points in combat")
    end
    frame.EnableMouse = function(self, enabled)
        assert(not inCombat, "raid markers bar must defer EnableMouse in combat")
        self.mouseEnabled = enabled
    end
    frame.SetAlpha = function(self, a) self.alpha = a end
    frame.GetAlpha = function(self) return self.alpha end
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.IsShown = function(self) return self.shown end
    frame.CreateTexture = function(self) return NewTexture(self) end
    frame.GetCenter = function() return 0, 0 end
    frame.GetLeft = function() return 0 end
    frame.GetRight = function() return 0 end
    frame.GetTop = function() return 0 end
    frame.GetBottom = function() return 0 end
    frame.StartMoving = noop
    frame.StopMovingOrSizing = noop
    createdFrames[#createdFrames + 1] = frame
    return frame
end

_G.UIParent = NewFrame("Frame", "UIParent")
function _G.CreateFrame(frameType, name, parent, template)
    local frame = NewFrame(frameType, name, parent, template)
    if name then _G[name] = frame end
    return frame
end

function _G.InCombatLockdown() return inCombat end
function _G.IsInRaid() return inRaid end
function _G.IsInGroup() return inGroup end
function _G.UnitIsGroupLeader() return isLeader end
function _G.UnitIsGroupAssistant() return isAssistant end

local inInstance, instanceType = false, "none"
function _G.IsInInstance() return inInstance, instanceType end

local countdownCalls = {}
_G.C_PartyInfo = {
    DoReadyCheck = function()
        _G.C_PartyInfo._readyChecks = (_G.C_PartyInfo._readyChecks or 0) + 1
    end,
    DoCountdown = function(secs)
        countdownCalls[#countdownCalls + 1] = secs
        return _G.C_PartyInfo._countdownOK ~= false
    end,
}
local rolePolls = 0
function _G.InitiateRolePoll() rolePolls = rolePolls + 1 end

_G.GameTooltip = { SetOwner = noop, SetText = noop, AddLine = noop, Show = noop, Hide = noop }
_G.C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }

local printed = {}
local realPrint = print
print = function(msg) printed[#printed + 1] = tostring(msg) end

local ns = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Addon = {
        db = { profile = { frameAnchoring = {} } },
        Pixels = function(_, value) return value end,
        PixelRound = function(_, value) return value end,
    },
    Helpers = {
        CreateDBGetter = function(key)
            assert(key == "raidMarkersBar", "module should request the raidMarkersBar DB")
            return function() return markersDB end
        end,
        IsSecretValue = function() return false end,
    },
    Registry = { Register = noop },
}

assert(loadfile("QUI_ActionBars/actionbars/raidmarkers.lua"))("QUI_ActionBars", ns)
print = realPrint

local Bar = assert(ns.QUI_RaidMarkersBar, "module should export QUI_RaidMarkersBar")

-- ---------------------------------------------------------------------------
-- Secure attribute shape
-- ---------------------------------------------------------------------------
for i = 1, 8 do
    local btn = assert(Bar.worldRow[i], "world marker button should exist")
    assert(btn.template == "SecureActionButtonTemplate",
        "world marker buttons must be secure")
    assert(btn.attributes.type == "worldmarker" and btn.attributes.type1 == "worldmarker"
        and btn.attributes["*type1"] == "worldmarker" and btn.attributes.type2 == "worldmarker",
        "world marker buttons must use the blessed worldmarker action")
    assert(btn.attributes.marker == WORLD_MARKER_ORDER[i],
        "world marker " .. i .. " must map through WORLD_RAID_MARKER_ORDER")
    assert(btn.attributes.action1 == "set" and btn.attributes.action2 == "clear",
        "left-click places, right-click clears (Blizzard raid manager UX)")
end

local clearBtn = assert(Bar.worldRow[9], "clear-all flare button should exist")
assert(clearBtn.template == "SecureActionButtonTemplate", "clear-all must be secure")
assert(clearBtn.attributes.action == "clear", "clear-all uses action=clear")
assert(clearBtn.attributes.marker == nil,
    "clear-all must carry NO marker attribute (nil clears all world markers)")

assert(#Bar.stripRow == 3, "strip should have ready/roles/pull")
for i = 1, #Bar.stripRow do
    local btn = Bar.stripRow[i]
    assert(btn.template == nil, "strip buttons must NOT be secure templates")
    assert(btn.attributes.type == nil, "strip buttons carry no secure action")
end

-- ---------------------------------------------------------------------------
-- Leadership gating (world/strip rows hidden for non-leaders)
-- ---------------------------------------------------------------------------
local leaderWatch, leaderCoalesce
for _, frame in ipairs(createdFrames) do
    if frame.events.PARTY_LEADER_CHANGED then leaderWatch = frame end
    if frame.scripts.OnUpdate and not next(frame.events) then leaderCoalesce = frame end
end
assert(leaderWatch, "leadership watcher should register PARTY_LEADER_CHANGED")
assert(leaderCoalesce, "leadership recompute should be coalesced")

local function FireLeadershipChange()
    leaderWatch.scripts.OnEvent(leaderWatch, "PARTY_LEADER_CHANGED")
    leaderCoalesce.scripts.OnUpdate(leaderCoalesce)
end

Bar:Refresh()
assert(Bar.buttons[1].alpha == 1, "target markers show whenever the bar is enabled")
assert(Bar.worldRow[1].alpha == 0 and Bar.stripRow[1].alpha == 0,
    "leader rows hidden while not lead/assist")

inGroup = true
isLeader = true
FireLeadershipChange()
assert(Bar.worldRow[1].alpha == 1 and Bar.worldRow[9].alpha == 1 and Bar.stripRow[1].alpha == 1,
    "leader rows shown once player becomes group lead")

-- Raid assist counts as leaderish
isLeader = false
inRaid = true
isAssistant = true
FireLeadershipChange()
assert(Bar.worldRow[1].alpha == 1, "raid assist keeps leader rows visible")

-- autoShowForLeader=false pins rows on regardless of leadership
inRaid, isAssistant = false, false
FireLeadershipChange()
assert(Bar.worldRow[1].alpha == 0, "losing leadership hides the rows again")
markersDB.autoShowForLeader = false
Bar:Refresh()
assert(Bar.worldRow[1].alpha == 1, "autoShowForLeader=false pins the rows on")
markersDB.autoShowForLeader = true
Bar:Refresh()
assert(Bar.worldRow[1].alpha == 0, "gate re-applies when autoShowForLeader returns")

-- ---------------------------------------------------------------------------
-- Combat contract: leadership flips in combat are alpha-only + deferred
-- ---------------------------------------------------------------------------
inCombat = true
inGroup, isLeader = true, true
FireLeadershipChange()  -- stub asserts would throw on any secure write / geometry
assert(Bar.worldRow[1].alpha == 1, "in-combat leadership gain shows rows via alpha only")

isLeader = false
inGroup = false
FireLeadershipChange()
assert(Bar.worldRow[1].alpha == 0, "in-combat leadership loss hides rows via alpha only")

inCombat = false
local initFrame
for _, frame in ipairs(createdFrames) do
    if frame.events.PLAYER_REGEN_ENABLED then initFrame = frame end
end
assert(initFrame, "init frame should watch PLAYER_REGEN_ENABLED")
initFrame.scripts.OnEvent(initFrame, "PLAYER_REGEN_ENABLED")
assert(Bar.worldRow[1].alpha == 0 and Bar.buttons[1].alpha == 1,
    "post-combat reconcile settles row visibility")

-- ---------------------------------------------------------------------------
-- Strip behavior: permissions + pull seconds
-- ---------------------------------------------------------------------------
local ready, roles, pull = Bar.stripRow[1], Bar.stripRow[2], Bar.stripRow[3]

printed = {}
print = function(msg) printed[#printed + 1] = tostring(msg) end

roles.scripts.OnClick(roles, "LeftButton")
assert(rolePolls == 0 and #printed == 1, "role poll as non-leader prints a hint instead")

inGroup, isLeader = true, true
roles.scripts.OnClick(roles, "LeftButton")
assert(rolePolls == 1, "role poll fires for the group leader")

ready.scripts.OnClick(ready, "LeftButton")
assert(_G.C_PartyInfo._readyChecks == 1, "ready check fires for lead/assist")

pull.scripts.OnClick(pull, "LeftButton")
assert(countdownCalls[1] == 12, "pull uses the configured pullSeconds")
pull.scripts.OnClick(pull, "RightButton")
assert(countdownCalls[2] == 0, "right-click cancels the countdown")

_G.C_PartyInfo._countdownOK = false
printed = {}
pull.scripts.OnClick(pull, "LeftButton")
assert(#printed == 1, "failed countdown surfaces the permission hint")
_G.C_PartyInfo._countdownOK = true
print = realPrint

-- ---------------------------------------------------------------------------
-- Preview bypasses the leadership gate
-- ---------------------------------------------------------------------------
inGroup, isLeader = false, false
FireLeadershipChange()
Bar:ShowPreview()
assert(Bar.worldRow[1].alpha == 1 and Bar.stripRow[1].alpha == 1,
    "preview shows enabled leader rows regardless of leadership")
Bar:HidePreview()
assert(Bar.worldRow[1].alpha == 0, "leaving preview restores the leadership gate")

-- ---------------------------------------------------------------------------
-- Whole-bar instance gate (onlyInInstances)
-- ---------------------------------------------------------------------------
markersDB.onlyInInstances = true
inInstance, instanceType = false, "none"
Bar:Refresh()
assert(Bar.buttons[1].alpha == 0 and Bar.container.alpha == 0,
    "onlyInInstances hides the whole bar in the open world")

-- Entering a dungeon flips the gate through the coalesced watcher (PEW).
inInstance, instanceType = true, "party"
FireLeadershipChange()
assert(Bar.buttons[1].alpha == 1 and Bar.container.alpha == 1,
    "entering a dungeon shows the bar again")

-- Battlegrounds do not count as dungeon/raid content.
inInstance, instanceType = true, "pvp"
FireLeadershipChange()
assert(Bar.container.alpha == 0, "battlegrounds keep the instance-gated bar hidden")

-- Raids count.
inInstance, instanceType = true, "raid"
FireLeadershipChange()
assert(Bar.container.alpha == 1, "raid instances show the instance-gated bar")

-- Preview bypasses the instance gate so the bar can be positioned anywhere.
inInstance, instanceType = false, "none"
FireLeadershipChange()
assert(Bar.container.alpha == 0, "back outside: bar hidden again")
Bar:ShowPreview()
assert(Bar.container.alpha == 1 and Bar.buttons[1].alpha == 1,
    "preview shows the instance-gated bar in the open world")
Bar:HidePreview()
assert(Bar.container.alpha == 0, "leaving preview restores the instance gate")
markersDB.onlyInInstances = false
Bar:Refresh()
assert(Bar.container.alpha == 1, "clearing onlyInInstances restores the bar")

print("OK: raidmarkers_leader_secure_contract")
