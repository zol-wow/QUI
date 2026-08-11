-- tests/unit/blizzard_mover_mail_drift_reassert_test.lua
-- Run: lua tests/unit/blizzard_mover_mail_drift_reassert_test.lua
-- luacheck: allow defined top (mock frame globals assigned at top level)
--
-- UIParentPanelManager re-anchors the left-area panel (MailFrame) with
-- ClearAllPoints + SetPoint("TOPLEFT", UIParent, ...) on EVERY
-- UpdateUIPanelPositions pass (UIParentPanelManager.lua:597-598), not just
-- on show. The secure-frame watcher only re-asserts the saved position on
-- the hidden->shown transition plus 5 OnUpdate ticks, so any later pass
-- snapped the mail frame back to the default slot with QUI blind to it
-- (no SetPoint hook allowed: taint). Panels flagged reassertOnDrift now
-- compare the live first anchor against the saved offset each tick while
-- shown and re-assert when the panel manager has re-stamped the frame.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function blockForId(source, id)
    local pattern = '{%s*id = "' .. id .. '".-defaultEnabled = true,%s*}'
    return source:match(pattern)
end

-- Registry entries: the mail cluster must opt into drift re-assert; the
-- world map must NOT (drift-fighting would snap back Blizzard's own
-- maximize flow, which re-anchors the shown map on purpose).
local frameRegistry = readFile("modules/qol/blizzard_mover_frames.lua")
local mailBlock = assert(blockForId(frameRegistry, "MailFrame"), "MailFrame registry entry should exist")
assert(mailBlock:find("reassertOnDrift = true", 1, true), "MailFrame must opt into drift re-assert")
local openMailBlock = assert(blockForId(frameRegistry, "OpenMailFrame"), "OpenMailFrame registry entry should exist")
assert(openMailBlock:find("reassertOnDrift = true", 1, true), "OpenMailFrame must opt into drift re-assert")
local mapBlock = assert(blockForId(frameRegistry, "WorldMapFrame"), "WorldMapFrame registry entry should exist")
assert(not mapBlock:find("reassertOnDrift", 1, true), "WorldMapFrame must keep transition-only re-assert")

---------------------------------------------------------------------------
-- Frame mock with real anchor-point state
---------------------------------------------------------------------------

local function noop() end

local frameMeta = {}
frameMeta.__index = function(_, key)
    if key == "GetName" then
        return function(self) return self.name end
    elseif key == "IsForbidden" then
        return function() return false end
    elseif key == "IsProtected" then
        return function(self) return self.protected or false end
    elseif key == "SetPoint" then
        return function(self, point, rel, relPoint, x, y)
            self.points[#self.points + 1] = { point, rel, relPoint, x, y }
            self.setPointCount = self.setPointCount + 1
        end
    elseif key == "ClearAllPoints" then
        return function(self)
            for i = #self.points, 1, -1 do self.points[i] = nil end
        end
    elseif key == "GetPoint" then
        return function(self, i)
            local p = self.points[i or 1]
            if not p then return nil end
            return p[1], p[2], p[3], p[4], p[5]
        end
    elseif key == "GetNumPoints" then
        return function(self) return #self.points end
    elseif key == "GetWidth" or key == "GetHeight" then
        return function() return 300 end
    elseif key == "GetSize" then
        return function() return 300, 200 end
    elseif key == "GetScale" then
        return function() return 1 end
    elseif key == "GetFrameStrata" then
        return function() return "MEDIUM" end
    elseif key == "GetFrameLevel" then
        return function(self) return rawget(self, "frameLevel") or 1 end
    elseif key == "IsShown" then
        return function(self) return rawget(self, "shown") or false end
    elseif key == "IsMovable" or key == "IsClampedToScreen" or key == "IsMouseEnabled" or key == "IsMouseWheelEnabled" or key == "IsUserPlaced" then
        return function() return false end
    elseif key == "HookScript" then
        return function(self, script, handler)
            self.hookedScripts[script] = handler
        end
    elseif key == "SetScript" then
        return function(self, script, handler)
            self.scripts[script] = handler
        end
    elseif key == "RegisterEvent" then
        return noop
    elseif key == "SetShown" then
        return function(self, shown) self.shown = shown and true or false end
    elseif key == "Show" then
        return function(self) self.shown = true end
    elseif key == "Hide" then
        return function(self) self.shown = false end
    end
    return noop
end

local function newFrame(name, parent, protected)
    return setmetatable({
        name = name,
        parent = parent,
        protected = protected,
        points = {},
        setPointCount = 0,
        scripts = {},
        hookedScripts = {},
        secureHooks = {},
        children = {},
    }, frameMeta)
end

UIParent = newFrame("UIParent")
MailFrame = newFrame("MailFrame", UIParent, false)
SendMailFrame = newFrame("SendMailFrame", MailFrame, false)
MailFrameInset = newFrame("MailFrameInset", MailFrame, false)
WorldMapFrame = newFrame("WorldMapFrame", UIParent, false)

local watcherFrames = {}

function CreateFrame(_, name, parent)
    local frame = newFrame(name, parent, false)
    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    watcherFrames[#watcherFrames + 1] = frame
    return frame
end

function hooksecurefunc(target, method, handler)
    if type(target) == "table" then
        target.secureHooks[method] = handler
    end
end

local inCombat = false
function InCombatLockdown() return inCombat end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end

C_AddOns = {
    IsAddOnLoaded = function() return true end,
}

local SAVED = { point = "LEFT", x = 187.88, y = 134.08 }

local profile = {
    blizzardMover = {
        enabled = true,
        requireModifier = true,
        modifier = "SHIFT",
        scaleEnabled = false,
        positionPersistence = "reset",
        frames = {
            MailFrame = { enabled = true, point = SAVED.point, x = SAVED.x, y = SAVED.y },
            WorldMapFrame = { enabled = true, point = SAVED.point, x = SAVED.x, y = SAVED.y },
        },
    },
}

local ns = {
    Helpers = {
        GetProfile = function()
            return profile
        end,
    },
    SafeCall = function(_policy, fn, ...)
        return pcall(fn, ...)
    end,
    SafeCallMethod = function(_policy, obj, name, ...)
        return pcall(function(...) return obj[name](obj, ...) end, ...)
    end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}

assert(loadfile("modules/qol/blizzard_mover.lua"))("QUI", ns)
local mover = assert(ns.QUI_BlizzardMover, "Blizzard mover module should load")
mover.functions.InitDB()

mover.functions.RegisterFrame({
    id = "MailFrame",
    label = "Mail",
    group = "vendors",
    names = { "MailFrame" },
    addon = "Blizzard_MailFrame",
    useRootHandle = true,
    handles = { "SendMailFrame", "MailFrameInset" },
    defaultEnabled = true,
    secureFrame = true,
    reassertOnDrift = true,
})

mover.functions.RegisterFrame({
    id = "WorldMapFrame",
    label = "World Map",
    group = "world",
    names = { "WorldMapFrame" },
    defaultEnabled = true,
    secureFrame = true,
})

local function watcherFor(root)
    -- The secure-frame watcher is the only CreateFrame'd frame with an
    -- OnUpdate SetScript; match it to its root by creation order.
    local found = {}
    for _, f in ipairs(watcherFrames) do
        if f.scripts.OnUpdate then found[#found + 1] = f end
    end
    assert(#found == 2, "expected one watcher per secure-frame panel, got " .. #found)
    if root == MailFrame then return found[1] end
    return found[2]
end

local mailWatcher = watcherFor(MailFrame)
local mapWatcher = watcherFor(WorldMapFrame)

local function tick(watcher, n)
    for _ = 1, (n or 1) do
        watcher.scripts.OnUpdate(watcher)
    end
end

local function firstPoint(f)
    local p = f.points[1]
    assert(p, (f.name or "?") .. " should have an anchor point")
    return p[1], p[2], p[4], p[5]
end

local function assertAtSaved(f, label)
    local point, rel, x, y = firstPoint(f)
    assert(point == SAVED.point and rel == UIParent and x == SAVED.x and y == SAVED.y,
        label .. ": expected saved position, got " .. tostring(point) .. "," .. tostring(x) .. "," .. tostring(y))
end

local function blizzardRestamp(f)
    -- UpdateUIPanelPositions left-area branch (UIParentPanelManager.lua:597)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
end

---------------------------------------------------------------------------
-- 1. Show transition applies saved position (existing behavior)
---------------------------------------------------------------------------

MailFrame.shown = true
blizzardRestamp(MailFrame)
tick(mailWatcher)
assertAtSaved(MailFrame, "show transition")
tick(mailWatcher, 5) -- burn the transition re-assert burst

---------------------------------------------------------------------------
-- 2. Panel-manager re-stamp while shown is corrected on the next tick
---------------------------------------------------------------------------

blizzardRestamp(MailFrame)
tick(mailWatcher)
assertAtSaved(MailFrame, "drift re-assert")

---------------------------------------------------------------------------
-- 3. Convergence: no SetPoint churn when the frame already sits at the
--    saved position
---------------------------------------------------------------------------

local before = MailFrame.setPointCount
tick(mailWatcher, 3)
assert(MailFrame.setPointCount == before,
    "drift re-assert must not touch anchors when position matches (got " ..
    (MailFrame.setPointCount - before) .. " extra SetPoint calls)")

---------------------------------------------------------------------------
-- 4. Combat gate: no mutation attempt while in combat, corrected after
---------------------------------------------------------------------------

inCombat = true
blizzardRestamp(MailFrame)
before = MailFrame.setPointCount
tick(mailWatcher, 2)
assert(MailFrame.setPointCount == before, "drift re-assert must stay inert in combat")
inCombat = false
tick(mailWatcher)
assertAtSaved(MailFrame, "post-combat drift re-assert")

---------------------------------------------------------------------------
-- 5. Panels without reassertOnDrift keep transition-only behavior
---------------------------------------------------------------------------

WorldMapFrame.shown = true
blizzardRestamp(WorldMapFrame)
tick(mapWatcher)
assertAtSaved(WorldMapFrame, "map show transition")
tick(mapWatcher, 5)

blizzardRestamp(WorldMapFrame)
tick(mapWatcher, 3)
local point = WorldMapFrame.points[1][1]
assert(point == "TOPLEFT",
    "non-flagged secure panels must NOT drift-re-assert while shown (got " .. tostring(point) .. ")")

---------------------------------------------------------------------------
-- 6. Hide/re-show still re-asserts (watcher transition path unchanged)
---------------------------------------------------------------------------

WorldMapFrame.shown = false
tick(mapWatcher)
WorldMapFrame.shown = true
blizzardRestamp(WorldMapFrame)
tick(mapWatcher)
assertAtSaved(WorldMapFrame, "map re-show transition")

---------------------------------------------------------------------------
-- 7. "Until frame closes" mode: the dragged position is stored per-open,
--    drift-repaired while the frame stays shown, and expires on close
---------------------------------------------------------------------------

profile.blizzardMover.positionPersistence = "close"

MailFrame.shown = false
tick(mailWatcher) -- hide transition under close mode (restore + slot clear)
MailFrame.shown = true
blizzardRestamp(MailFrame)
tick(mailWatcher, 6)
local pointFreshOpen = MailFrame.points[1][1]
assert(pointFreshOpen == "TOPLEFT",
    "close mode: no stored offset on fresh open, frame must stay at the Blizzard slot")

-- Simulate a drag: live anchor moves, drag-end records the until-close slot
MailFrame:ClearAllPoints()
MailFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(MailFrame, "MailFrame")

blizzardRestamp(MailFrame)
tick(mailWatcher)
assertAtSaved(MailFrame, "close-mode drift re-assert")

local closeModeBefore = MailFrame.setPointCount
tick(mailWatcher, 3)
assert(MailFrame.setPointCount == closeModeBefore,
    "close-mode drift re-assert must not churn anchors at rest")

MailFrame.shown = false
tick(mailWatcher) -- close: until-close slot expires
MailFrame.shown = true
blizzardRestamp(MailFrame)
tick(mailWatcher, 6)
local pointReopen = MailFrame.points[1][1]
assert(pointReopen == "TOPLEFT",
    "close mode: stored offset must expire when the frame closes (got " .. tostring(pointReopen) .. ")")

---------------------------------------------------------------------------
-- 8. Multi-name panel (QuestFrame+GossipFrame shape): cluster liveness
--    comes from observed show/hide transitions, never from live IsShown
--    probes — the whole section runs with GossipFrame.IsShown unreadable
---------------------------------------------------------------------------

QuestFrame = newFrame("QuestFrame", UIParent, false)
GossipFrame = newFrame("GossipFrame", UIParent, false)

mover.functions.RegisterFrame({
    id = "QuestDialog",
    label = "Dialog",
    group = "world",
    names = { "QuestFrame", "GossipFrame" },
    defaultEnabled = true,
})

assert(QuestFrame.hookedScripts.OnShow, "non-secure mover roots should hook OnShow")
assert(GossipFrame.hookedScripts.OnHide, "non-secure mover roots should hook OnHide")

-- Decisions must never read IsShown live: keep it unreadable from here on
rawset(GossipFrame, "IsShown", function() error("secret-capable read on a tainted stack") end)

QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
GossipFrame.shown = true
GossipFrame.hookedScripts.OnShow(GossipFrame)

QuestFrame:ClearAllPoints()
QuestFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(QuestFrame, "QuestDialog")

local openPositions = mover.variables.openPositions
assert(openPositions.QuestDialog, "close mode: drag end should record the until-close slot")

GossipFrame.shown = false
GossipFrame.hookedScripts.OnHide(GossipFrame)
assert(openPositions.QuestDialog,
    "a hiding sibling must not erase the until-close slot while another cluster frame is open")

QuestFrame.shown = false
QuestFrame.hookedScripts.OnHide(QuestFrame)
assert(not openPositions.QuestDialog,
    "the until-close slot must clear once every frame of the panel has hidden")

---------------------------------------------------------------------------
-- 9. A sibling SHOWING while the slot's owner is still open (overlapping
--    StaticPopup shape) must not erase the cluster's position — even with
--    the owner's IsShown unreadable
---------------------------------------------------------------------------

rawset(GossipFrame, "IsShown", nil)
rawset(QuestFrame, "IsShown", function() error("owner visibility unreadable") end)

QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
QuestFrame:ClearAllPoints()
QuestFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(QuestFrame, "QuestDialog")
assert(openPositions.QuestDialog, "slot should be armed for the still-open-cluster check")

GossipFrame.shown = true
GossipFrame.hookedScripts.OnShow(GossipFrame)
assert(openPositions.QuestDialog,
    "a sibling's show must not erase a still-open cluster's position")

rawset(QuestFrame, "IsShown", nil)
GossipFrame.shown = false
GossipFrame.hookedScripts.OnHide(GossipFrame)
QuestFrame.shown = false
QuestFrame.hookedScripts.OnHide(QuestFrame)
assert(not openPositions.QuestDialog, "teardown: slot clears when the cluster fully hides")

---------------------------------------------------------------------------
-- 10. Leak backstop: a slot surviving a MISSED hide (no OnHide observed)
--     must not leak into the next open — the stale self entry in the
--     transition log does not count as an open sibling
---------------------------------------------------------------------------

QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
QuestFrame:ClearAllPoints()
QuestFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(QuestFrame, "QuestDialog")
assert(openPositions.QuestDialog, "slot should be armed for the leak check")

QuestFrame.shown = false -- hide happens but the OnHide signal is missed

QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
assert(not openPositions.QuestDialog,
    "a fresh open must not inherit the until-close position from a previous open")

---------------------------------------------------------------------------
-- 11. Missed SIBLING hide: the stale log entry is repaired at the next
--     observed transition (probe of logged frames only), so the slot
--     cannot leak across a real cluster close through a sibling
---------------------------------------------------------------------------

-- Variant A: sibling hide missed, owner hide observed -> slot clears
QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
GossipFrame.shown = true
GossipFrame.hookedScripts.OnShow(GossipFrame)
QuestFrame:ClearAllPoints()
QuestFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(QuestFrame, "QuestDialog")
assert(openPositions.QuestDialog, "slot should be armed for the missed-sibling-hide check")

GossipFrame.shown = false -- hide happens but the OnHide signal is missed
QuestFrame.shown = false
QuestFrame.hookedScripts.OnHide(QuestFrame)
assert(not openPositions.QuestDialog,
    "an observed hide must sweep the provably hidden stale sibling and clear the slot")

-- Variant B: BOTH hides missed -> the next fresh show sweeps and clears
QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
GossipFrame.shown = true
GossipFrame.hookedScripts.OnShow(GossipFrame)
QuestFrame:ClearAllPoints()
QuestFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(QuestFrame, "QuestDialog")

QuestFrame.shown = false
GossipFrame.shown = false -- both hides missed

QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
assert(not openPositions.QuestDialog,
    "a fresh open must sweep provably hidden stale siblings instead of treating them as open")

-- Variant C: stale sibling UNREADABLE at the decision point -> log wins
-- (undecidable), then the next readable transition repairs and clears
QuestFrame:ClearAllPoints()
QuestFrame:SetPoint(SAVED.point, UIParent, SAVED.point, SAVED.x, SAVED.y)
mover.functions.StoreFramePosition(QuestFrame, "QuestDialog")
GossipFrame.shown = true
GossipFrame.hookedScripts.OnShow(GossipFrame)
GossipFrame.shown = false -- hide missed...
rawset(GossipFrame, "IsShown", function() error("...and unreadable at the next show") end)

QuestFrame.shown = false
QuestFrame.hookedScripts.OnHide(QuestFrame)
QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
assert(openPositions.QuestDialog,
    "an unreadable logged sibling keeps the slot (undecidable: the log wins)")

rawset(GossipFrame, "IsShown", nil) -- readable again
QuestFrame.shown = false
QuestFrame.hookedScripts.OnHide(QuestFrame)
QuestFrame.shown = true
QuestFrame.hookedScripts.OnShow(QuestFrame)
assert(not openPositions.QuestDialog,
    "the next readable transition must repair the log and clear the leaked slot")

---------------------------------------------------------------------------
-- 12. Instrument-time seed probes IsShown safely (throw / secret answers
--     seed as hidden, no crash)
---------------------------------------------------------------------------

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == SECRET end

ThrowSeedFrame = newFrame("ThrowSeedFrame", UIParent, false)
rawset(ThrowSeedFrame, "IsShown", function() error("unreadable at instrument time") end)
mover.functions.RegisterFrame({
    id = "ThrowSeedPanel",
    label = "ThrowSeed",
    group = "world",
    names = { "ThrowSeedFrame" },
    defaultEnabled = true,
})

SecretSeedFrame = newFrame("SecretSeedFrame", UIParent, false)
rawset(SecretSeedFrame, "IsShown", function() return SECRET end)
mover.functions.RegisterFrame({
    id = "SecretSeedPanel",
    label = "SecretSeed",
    group = "world",
    names = { "SecretSeedFrame" },
    defaultEnabled = true,
})

local shownLog = mover.variables.openPanelShown
assert(not (shownLog.ThrowSeedPanel and next(shownLog.ThrowSeedPanel)),
    "a throwing IsShown must seed the transition log as hidden")
assert(not (shownLog.SecretSeedPanel and next(shownLog.SecretSeedPanel)),
    "a secret IsShown answer must seed the transition log as hidden")

print("OK: blizzard_mover_mail_drift_reassert_test")
