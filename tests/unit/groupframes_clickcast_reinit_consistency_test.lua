-- tests/unit/groupframes_clickcast_reinit_consistency_test.lua
-- Run: lua tests/unit/groupframes_clickcast_reinit_consistency_test.lua
--
-- A re-entrant Initialize() must not silently desync keyboard click-cast. The
-- bare re-resolve path updates only the secure header's key attributes; if the
-- resolve is transiently empty (spec/loadout data momentarily unavailable) it
-- would zero the header's keycount while frames stay keyboard-wrapped -- so on
-- hover the secure snippet binds nothing (keyboard dead) even though the frame
-- still carries its key virtual-button attributes (mouse-style state survives).
-- Re-entrant Initialize must instead rebuild header and frames together.

local inCombat = false
local function noop() end
local SPELL_NAMES = { [774] = "Rejuvenation" }
local NAME_TO_ID  = { Rejuvenation = 774 }
local specReady = true

local frameMT
local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType, name = name, parent = parent, template = template,
        attributes = {}, scripts = {}, hooks = {}, events = {}, secureWraps = {},
        overrideBindings = {}, frameRefs = {},
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
function GetSpecializationInfo() return specReady and 102 or nil end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function SecureHandlerWrapScript(frame, script, header, preBody)
    frame.secureWraps[script] = { header = header, preBody = preBody }
end
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
            return tbl, function(key) local s = tbl[key]; if not s then s = {}; tbl[key] = s end; return s end
        end,
        DeepCopy = DeepCopy,
    },
}

_G.QUI = {
    db = {
        char = {
            clickCast = {
                enabled = true,
                _migratedFromProfile = true,
                rootSpellMigrationDone = true,
                perSpec = true,
                specBindings = {
                    [102] = {
                        { key = "F", modifiers = "", actionType = "spell",
                          spell = "Rejuvenation", spellID = 774 },
                    },
                },
            },
        },
        profile = {},
    },
}

local child = NewFrame("Button", "QUI_TestUnit1", nil, "SecureUnitButtonTemplate")
local partyHeader = NewFrame("Frame", "QUI_TestPartyHeader", nil, "SecureGroupHeaderTemplate")
partyHeader.attributes["child1"] = child
ns.QUI_GroupFrames = {
    headers = { party = partyHeader, raid = false, self = false },
    raidGroupHeaders = {},
}

assert(loadfile("modules/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast)

-- Good setup while spec data is ready: keyboard click-cast is live.
specReady = true
GFCC:Initialize()
GFCC:RegisterAllFrames()
-- Keyboard key F is published once to the global caster button.
local caster = assert(_G.QUI_ClickCastCaster, "caster button should exist")
assert(caster:GetAttribute("cc-key1") == "F", "precondition: caster should publish key F")

-- A re-entrant Initialize() while spec data is momentarily unavailable must NOT
-- wipe the good caster key list -- a transient empty resolve keeps last-good and
-- lets the recovery re-resolve, rather than silently killing keyboard click-cast.
specReady = false
GFCC:Initialize()

assert(caster:GetAttribute("cc-key1") == "F",
    "BUG: re-entrant Initialize with spec data unavailable wiped the caster keyboard "
    .. "key list -- silent keyboard click-cast death")

print("OK: groupframes_clickcast_reinit_consistency_test")
