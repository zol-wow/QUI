-- tests/unit/groupframes_clickcast_roster_update_test.lua
-- Run: lua tests/unit/groupframes_clickcast_roster_update_test.lua
--
-- Regression: zoning into an instance (e.g. a follower dungeon) changes the
-- party roster. Secure group headers create/assign child unit buttons lazily as
-- the roster settles, often AFTER the one-shot PLAYER_ENTERING_WORLD catch-up.
-- Click-casting must be (re)applied to frames that appear on a roster change,
-- otherwise the new party frames have no bindings until the user /reloads.
-- The module must re-register frames on GROUP_ROSTER_UPDATE (out of combat
-- immediately; in combat deferred to PLAYER_REGEN_ENABLED).

local inCombat = false
local function noop() end

local SPELL_NAMES = { [774] = "Rejuvenation" }
local NAME_TO_ID  = { Rejuvenation = 774 }

local createdFrames = {}
local frameMT
local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType, name = name, parent = parent, template = template,
        attributes = {}, scripts = {}, hooks = {}, events = {},
    }
    frameMT = frameMT or {
        __index = function(_, key)
            if key == "SetAttribute" then
                return function(self, attr, value)
                    assert(not inCombat, "must not mutate secure attributes in combat")
                    self.attributes[attr] = value
                end
            elseif key == "GetAttribute" then
                return function(self, attr) return self.attributes[attr] end
            elseif key == "SetScript" then
                return function(self, s, h) self.scripts[s] = h end
            elseif key == "HookScript" then
                return function(self, s, h) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], h) end
            elseif key == "RegisterEvent" then
                return function(self, e) self.events[e] = true end
            elseif key == "UnregisterEvent" then
                return function(self, e) self.events[e] = nil end
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function(self) return NewFrame(key, nil, self, nil) end
            end
            return noop
        end,
    }
    setmetatable(frame, frameMT)
    table.insert(createdFrames, frame)
    return frame
end

function CreateFrame(frameType, name, parent, template)
    local f = NewFrame(frameType, name, parent, template)
    if name then _G[name] = f end
    return f
end

function InCombatLockdown() return inCombat end
function UnitClass() return "Druid", "DRUID" end
function UnitIsDeadOrGhost() return false end
function UnitIsConnected() return true end
function UnitIsPlayer() return true end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 102 end
SecureHandlerWrapScript = noop
GameTooltip = { GetOwner = function() return nil end, AddLine = noop, AddDoubleLine = noop, Show = noop }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- Debounce timers must run for the test; execute callbacks synchronously.
C_Timer = {
    After = function(_, fn) if fn then fn() end end,
    NewTimer = function(_, fn) if fn then fn() end return { Cancel = noop } end,
}

C_Spell = {
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    GetSpellIDForSpellIdentifier = function(name) return NAME_TO_ID[name] end,
    GetBaseSpell = function(id) return id end,
}
C_ClassTalents = nil

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k, vv in pairs(v) do t[k] = DeepCopy(vv) end; return t
end

local ns = {
    Helpers = {
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            return tbl, function(key) local s = tbl[key]; if not s then s = {}; tbl[key] = s end; return s end
        end,
        DeepCopy = DeepCopy,
    },
}

_G.QUI = {
    db = {
        char = {
            clickCast = {
                enabled = true, _migratedFromProfile = true, rootSpellMigrationDone = true,
                bindings = {
                    { button = "LeftButton", modifiers = "", actionType = "spell",
                      spell = "Rejuvenation", spellID = 774 },
                },
            },
        },
        profile = {},
    },
}

-- Header starts with one child (player, solo) — mirrors a lazily-populated
-- SecureGroupHeader before zoning into a group instance.
local child1 = NewFrame("Button", "QUI_TestUnit1", nil, "SecureUnitButtonTemplate")
local partyHeader = NewFrame("Frame", "QUI_TestPartyHeader", nil, "SecureGroupHeaderTemplate")
partyHeader.attributes["child1"] = child1
ns.QUI_GroupFrames = {
    headers = { party = partyHeader, raid = false, self = false },
    raidGroupHeaders = {},
}

assert(loadfile("modules/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast)

-- Find the module's event frame (the one that listens for roster/zone events).
local eventFrame
for _, f in ipairs(createdFrames) do
    if f.events["PLAYER_ENTERING_WORLD"] and f.scripts["OnEvent"] then eventFrame = f break end
end
assert(eventFrame, "clickcast module should create an event frame")
local function fire(event, ...) eventFrame.scripts["OnEvent"](eventFrame, event, ...) end

-- Initial state: solo, one frame registered.
GFCC:Initialize()
GFCC:RegisterAllFrames()
assert(child1.attributes["type1"] == "macro", "player frame should be bound initially")

-- Zone into a follower dungeon: the secure header creates a new follower button.
local child2 = NewFrame("Button", "QUI_TestUnit2", nil, "SecureUnitButtonTemplate")
partyHeader.attributes["child2"] = child2
assert(child2.attributes["type1"] == nil, "sanity: new follower frame is unbound before any roster handling")

-- The roster-change event fires (out of combat).
fire("GROUP_ROSTER_UPDATE")

-- The new follower frame must get click-cast applied without a /reload.
assert(child2.attributes["type1"] == "macro",
    "BUG: after GROUP_ROSTER_UPDATE the new follower frame should be click-cast bound without /reload")
assert(child2.attributes["macrotext1"] and child2.attributes["macrotext1"]:find("Rejuvenation", 1, true),
    "new follower frame should cast the configured spell")

-- And the in-combat case should defer, then apply when combat ends.
local child3 = NewFrame("Button", "QUI_TestUnit3", nil, "SecureUnitButtonTemplate")
partyHeader.attributes["child3"] = child3
inCombat = true
fire("GROUP_ROSTER_UPDATE")
assert(child3.attributes["type1"] == nil, "in combat, registration must be deferred (no secure writes)")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(child3.attributes["type1"] == "macro",
    "BUG: deferred roster registration should apply when combat ends")

print("OK: groupframes_clickcast_roster_update_test")
