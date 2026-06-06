-- tests/unit/groupframes_clickcast_keyboard_dynamic_apply_test.lua
-- Run: lua tests/unit/groupframes_clickcast_keyboard_dynamic_apply_test.lua
--
-- Keybound click-cast abilities use secure override bindings established by
-- the wrapped OnEnter snippet, not the mouse-button typeN attributes. Changing
-- a key binding out of combat must update the active override binding on the
-- currently-hovered frame immediately; otherwise the stale key remains active
-- until the frame gets a fresh secure enter cycle or the UI is reloaded.

local inCombat = false
local function noop() end

local SPELL_NAMES = { [774] = "Rejuvenation", [8936] = "Regrowth" }
local NAME_TO_ID  = { Rejuvenation = 774, Regrowth = 8936 }

local frameMT
local function RunSnippet(snippet, selfFrame, owner)
    local loader = loadstring or load
    local chunk, err = loader("local self, owner = ...\n" .. snippet)
    assert(chunk, err)
    return chunk(selfFrame, owner)
end

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
            elseif key == "IsVisible" then
                return function(self) return self.visible ~= false end
            elseif key == "IsUnderMouse" then
                return function(self) return self.underMouse == true end
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
                bindings = {
                    { key = "F", modifiers = "", actionType = "spell",
                      spell = "Rejuvenation", spellID = 774 },
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

GFCC:Initialize()
GFCC:RegisterAllFrames()

-- Keyboard keys are PUBLISHED to the global caster (its mouseoverstate driver
-- binds them on @mouseover), not bound per-frame.
local caster = assert(_G.QUI_ClickCastCaster, "caster button should exist for keyboard binding")
assert(caster:GetAttribute("cc-key1") == "F", "key F should be published to the caster")
assert(caster:GetAttribute("type-keyf") == "macro", "caster key virtual button should be configured")

inCombat = false
assert(GFCC:RemoveBinding(1))
assert(GFCC:AddBinding({ key = "G", modifiers = "", actionType = "spell",
    spell = "Regrowth", spellID = 8936 }))

assert(caster:GetAttribute("cc-key1") == "G",
    "BUG: caster should now publish the new G key after changing key bindings")
assert(caster:GetAttribute("type-keyf") == nil,
    "BUG: stale F virtual button should be cleared from the caster after rebind")
assert(caster:GetAttribute("type-keyg") == "macro", "new caster key virtual button should be configured")
assert(caster:GetAttribute("macrotext-keyg"):find("Regrowth", 1, true),
    "new caster key virtual button should cast Regrowth")
-- And the driver binds the current key (G) on @mouseover while the cursor is
-- over a registered frame (the frame-hover gate scopes keyboard click-cast to
-- click-cast frames; bare @mouseover -- nameplates/world -- must not bind).
child.underMouse = true
local loader = loadstring or load
assert(loader("local self, newstate = ...\n" .. caster:GetAttribute("_onstate-mouseoverstate")))(caster, "on")
assert(caster.overrideBindings.G and caster.overrideBindings.G.button == "keyg",
    "BUG: @mouseover should bind the new G key without /reload")
assert(not caster.overrideBindings.F, "BUG: stale F binding should be gone after rebind")

print("OK: groupframes_clickcast_keyboard_dynamic_apply_test")
