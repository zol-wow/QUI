-- tests/unit/groupframes_clickcast_dynamic_apply_test.lua
-- Run: lua tests/unit/groupframes_clickcast_dynamic_apply_test.lua
--
-- Repro probe: changing a click-cast binding out of combat should re-apply to
-- already-registered frames immediately (the UI path is AddBinding/RemoveBinding
-- -> RefreshBindings). User reports the change only takes effect after /reload.
-- This test exercises the pure-Lua apply path with mocked frames to determine
-- whether RefreshBindings actually updates a live frame's secure attributes.

local inCombat = false
local function noop() end

-- ---- spell tables -------------------------------------------------------
local SPELL_NAMES = { [774] = "Rejuvenation", [8936] = "Regrowth" }
local NAME_TO_ID  = { Rejuvenation = 774, Regrowth = 8936 }

-- ---- frame mock ---------------------------------------------------------
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
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function(self) return NewFrame(key, nil, self, nil) end
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
function GetSpecializationInfo() return 102 end -- Balance specID (arbitrary)
SecureHandlerWrapScript = noop
RegisterStateDriver = noop
UnregisterStateDriver = noop
GameTooltip = { GetOwner = function() return nil end, AddLine = noop, AddDoubleLine = noop, Show = noop }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

C_Timer = { After = function() end, NewTimer = function() return { Cancel = noop } end }

C_Spell = {
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    GetSpellIDForSpellIdentifier = function(name) return NAME_TO_ID[name] end,
    GetBaseSpell = function(id) return id end,
}
C_ClassTalents = nil -- not perLoadout in this test

-- ---- ns / Helpers -------------------------------------------------------
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

-- ---- DB ----------------------------------------------------------------
_G.QUI = {
    db = {
        char = {
            clickCast = {
                enabled = true,
                _migratedFromProfile = true, -- skip migration
                rootSpellMigrationDone = true,
                bindings = {
                    { button = "LeftButton", modifiers = "", actionType = "spell",
                      spell = "Rejuvenation", spellID = 774 },
                },
            },
        },
        profile = {},
    },
}

-- ---- group frame headers mock ------------------------------------------
local child = NewFrame("Button", "QUI_TestUnit1", nil, "SecureUnitButtonTemplate")
local partyHeader = NewFrame("Frame", "QUI_TestPartyHeader", nil, "SecureGroupHeaderTemplate")
partyHeader.attributes["child1"] = child
ns.QUI_GroupFrames = {
    headers = { party = partyHeader, raid = false, self = false },
    raidGroupHeaders = {},
}

-- ---- load module --------------------------------------------------------
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast, "module should export QUI_GroupFrameClickCast")

-- ---- 1. initial apply ---------------------------------------------------
GFCC:Initialize()
assert(GFCC:IsEnabled(), "click-cast should be enabled after Initialize")
GFCC:RegisterAllFrames()

assert(child.attributes["type1"] == "macro",
    "after initial register, left-click should be a macro action")
assert(child.attributes["macrotext1"]:find("Rejuvenation", 1, true),
    "after initial register, left-click macro should cast Rejuvenation, got: "
    .. tostring(child.attributes["macrotext1"]))

-- ---- 2. change the binding out of combat via the real UI path -----------
-- The options UI changes "which click casts what" by removing the old binding
-- and adding the new one. Both call RefreshBindings() internally out of combat.
inCombat = false
assert(GFCC:RemoveBinding(1))
assert(GFCC:AddBinding({ button = "LeftButton", modifiers = "", actionType = "spell",
    spell = "Regrowth", spellID = 8936 }))

-- ---- 3. assert the live frame reflects the NEW binding ------------------
assert(child.attributes["type1"] == "macro",
    "after binding change, left-click should still be a macro action")
assert(child.attributes["macrotext1"]:find("Regrowth", 1, true),
    "BUG: after changing the binding out of combat, left-click macro should cast "
    .. "Regrowth without a /reload. Got: " .. tostring(child.attributes["macrotext1"]))
assert(not child.attributes["macrotext1"]:find("Rejuvenation", 1, true),
    "BUG: stale Rejuvenation macro should be gone after the binding change")

print("OK: groupframes_clickcast_dynamic_apply_test")
