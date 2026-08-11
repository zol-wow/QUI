-- tests/unit/groupframes_clickcast_clear_bounded_test.lua
-- Run: lua tests/unit/groupframes_clickcast_clear_bounded_test.lua
--
-- Repro probe for the "script ran too long" watchdog crash in RefreshBindings:
--   ...groupframes_clickcast.lua:1283: script ran too long
--   ...:1458: in function 'RefreshBindings'
--   ...:1283: in function <...:1256>   (ClearFrameClickCast)
--
-- ClearFrameClickCast blind-cleared the full 8 modifier x 5 button attribute
-- matrix (~360 SetAttribute(nil) calls) per frame regardless of how many buttons
-- were actually bound. On a full raid (~100+ registered frames) the synchronous
-- out-of-combat clear loop in RefreshBindings exceeds WoW's 10s watchdog.
--
-- This test registers many frames with only a couple of bindings, then disables
-- click-cast (RefreshBindings -> clear-all, no re-setup) and asserts the number
-- of secure SetAttribute(nil) clears stays proportional to the bindings actually
-- written -- NOT the full matrix.

local inCombat = false
local function noop() end

-- Global counter: every SetAttribute(attr, nil) is one secure clear write.
_G.__nilWrites = 0

local SPELL_NAMES = { [774] = "Rejuvenation", [8936] = "Regrowth" }
local NAME_TO_ID  = { Rejuvenation = 774, Regrowth = 8936 }

local frameMT
local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType, name = name, parent = parent, template = template,
        attributes = {}, scripts = {}, hooks = {}, events = {},
        secureWraps = {}, overrideBindings = {}, frameRefs = {},
    }
    frameMT = frameMT or {
        __index = function(_, key)
            if key == "SetAttribute" then
                return function(self, attr, value)
                    assert(not inCombat, "must not mutate secure attributes in combat")
                    if value == nil then _G.__nilWrites = _G.__nilWrites + 1 end
                    self.attributes[attr] = value
                end
            elseif key == "GetAttribute" then
                return function(self, attr) return self.attributes[attr] end
            elseif key == "GetName" then
                return function(self) return self.name end
            elseif key == "SetScript" then
                return function(self, s, h) self.scripts[s] = h end
            elseif key == "HookScript" then
                return function(self, s, h) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], h) end
            elseif key == "RegisterEvent" then
                return function(self, e) self.events[e] = true end
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function(self) return NewFrame(key, nil, self, nil) end
            elseif key == "EnableMouseWheel" then
                return function(self, enabled) self.mouseWheelEnabled = enabled end
            elseif key == "ClearBindings" then
                return function(self) self.overrideBindings = {} end
            elseif key == "SetBindingClick" then
                return function(self, priority, bindKey, target, button)
                    self.overrideBindings[bindKey] = { priority = priority, target = target, button = button }
                end
            elseif key == "SetFrameRef" then
                return function(self, label, ref) self.frameRefs[label] = ref end
            elseif key == "GetFrameRef" then
                return function(self, label) return self.frameRefs[label] end
            elseif key == "IsVisible" then
                return function(self) return self.visible ~= false end
            elseif key == "Execute" then
                return function(self, snippet)
                    local loader = loadstring or load
                    local chunk, err = loader("local self = ...\n" .. snippet)
                    assert(chunk, err)
                    return chunk(self)
                end
            end
            return noop
        end,
    }
    return setmetatable(frame, frameMT)
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
RegisterStateDriver = noop
RegisterAttributeDriver = noop
UnregisterStateDriver = noop
GameTooltip = { GetOwner = function() return nil end, AddLine = noop, AddDoubleLine = noop, Show = noop }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

C_Timer = { After = function() end, NewTimer = function() return { Cancel = noop } end }

C_Spell = {
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    GetSpellIDForSpellIdentifier = function(name) return NAME_TO_ID[name] end,
    GetBaseSpell = function(id) return id end,
}
C_ClassTalents = nil

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, vv in pairs(v) do t[k] = DeepCopy(vv) end
    return t
end

local ns = {
    Helpers = {
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key)
                local s = tbl[key]; if not s then s = {}; tbl[key] = s end; return s
            end
            return tbl, get
        end,
        DeepCopy = DeepCopy,
    },
}

-- Two bound buttons; everything else in the 8x5 matrix is unbound.
_G.QUI = {
    db = {
        char = {
            clickCast = {
                enabled = true,
                _migratedFromProfile = true,
                rootSpellMigrationDone = true,
                bindings = {
                    { button = "LeftButton",  modifiers = "", actionType = "spell",
                      spell = "Rejuvenation", spellID = 774 },
                    { button = "RightButton", modifiers = "", actionType = "spell",
                      spell = "Regrowth",     spellID = 8936 },
                },
            },
        },
        profile = {},
    },
}

-- 40-frame raid header: child1..child40 (RegisterHeaderChildren walks 1..40).
local FRAME_COUNT = 40
local raidHeader = NewFrame("Frame", "QUI_TestRaidHeader", nil, "SecureGroupHeaderTemplate")
for i = 1, FRAME_COUNT do
    raidHeader.attributes["child" .. i] =
        NewFrame("Button", "QUI_TestRaidUnit" .. i, nil, "SecureUnitButtonTemplate")
end
ns.QUI_GroupFrames = {
    headers = { party = false, raid = raidHeader, self = false },
    raidGroupHeaders = {},
}

assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast, "module should export QUI_GroupFrameClickCast")

GFCC:Initialize()
assert(GFCC:IsEnabled(), "click-cast should be enabled after Initialize")
GFCC:RegisterAllFrames()

-- Sanity: every child registered and got a working proxy with the bound buttons.
local sampleProxyName = raidHeader.attributes["child1"]:GetAttribute("clickcast-proxyname")
local sampleProxy = assert(_G[sampleProxyName], "child1 must have a proxy")
assert(sampleProxy.attributes["type1"] == "macro", "left-click bound")
assert(sampleProxy.attributes["type2"] == "macro", "right-click bound")

-- Now disable and refresh: RefreshBindings clears every registered frame and
-- returns early (no re-setup). Count only the clear-path secure writes.
_G.__nilWrites = 0
QUI.db.char.clickCast.enabled = false
inCombat = false
GFCC:RefreshBindings()

local nilWrites = _G.__nilWrites
local perFrame = nilWrites / FRAME_COUNT
print(string.format("clear nil-writes: %d total, %.1f per frame (%d frames)",
    nilWrites, perFrame, FRAME_COUNT))

-- Two bindings + frame routing teardown is a handful of attrs per frame. The
-- blind full-matrix sweep was ~360/frame. Anything near that order trips the
-- watchdog on a real raid, so cap well below it.
assert(perFrame < 50,
    string.format("BUG: ClearFrameClickCast sweeps the full attribute matrix "
    .. "(%.1f clears/frame); a full raid of these blows the 'script ran too "
    .. "long' watchdog. Clear only the attrs actually written.", perFrame))

print("OK: groupframes_clickcast_clear_bounded_test")
