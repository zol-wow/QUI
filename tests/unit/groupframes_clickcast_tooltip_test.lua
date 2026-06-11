-- tests/unit/groupframes_clickcast_tooltip_test.lua
-- Run: lua tests/unit/groupframes_clickcast_tooltip_test.lua
--
-- The click-cast binding tooltip on group-frame hover must list ALL binding
-- kinds. After the global-caster rewrite, keyboard keys moved from
-- keyboardBindings (now scroll-wheel only) into globalKeyBindings; the tooltip
-- renderer must include them, and the "any bindings at all?" guard must not
-- early-return for a keyboard-only configuration.

local inCombat = false
local function noop() end

local SPELL_NAMES = { [774] = "Rejuvenation", [8936] = "Regrowth" }
local NAME_TO_ID  = { Rejuvenation = 774, Regrowth = 8936 }

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

-- Recording tooltip stub: GetOwner returns whatever frame the test "hovers"
-- so the hook takes its append-to-unit-tooltip branch.
local tooltipOwner = nil
local tooltipLines = {}
GameTooltip = {
    GetOwner = function() return tooltipOwner end,
    AddLine = function(_, text) table.insert(tooltipLines, { text = text }) end,
    AddDoubleLine = function(_, left, right) table.insert(tooltipLines, { left = left, right = right }) end,
    Show = noop,
}
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
                showTooltip = true,
                _migratedFromProfile = true,
                rootSpellMigrationDone = true,
                bindings = {
                    { key = "F", modifiers = "", actionType = "spell",
                      spell = "Rejuvenation", spellID = 774 },
                    { button = "LeftButton", modifiers = "shift", actionType = "spell",
                      spell = "Regrowth", spellID = 8936 },
                    { button = "ScrollUp", modifiers = "", actionType = "spell",
                      spell = "Regrowth", spellID = 8936 },
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

assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast)

GFCC:Initialize()
GFCC:RegisterAllFrames()

local function Hover(frame)
    tooltipOwner = frame
    tooltipLines = {}
    for _, hook in ipairs(frame.hooks.OnEnter or {}) do hook(frame) end
end

local function FindLine(left, right)
    for _, line in ipairs(tooltipLines) do
        if line.left == left and line.right == right then return true end
    end
    return false
end

-- Scenario 1: mixed bindings -- mouse, scroll wheel, AND keyboard key must all
-- be listed in the hover tooltip.
Hover(child)
assert(FindLine("Shift+Left Click", "Regrowth"),
    "mouse binding should appear in the tooltip")
assert(FindLine("Scroll Up", "Regrowth"),
    "scroll-wheel binding should appear in the tooltip")
assert(FindLine("F", "Rejuvenation"),
    "BUG: keyboard-key binding should appear in the tooltip (globalKeyBindings omitted)")

-- Scenario 2: keyboard-only configuration -- the tooltip must still render
-- (the early-return guard must count globalKeyBindings too).
assert(GFCC:RemoveBinding(3))
assert(GFCC:RemoveBinding(2))
Hover(child)
assert(#tooltipLines > 0,
    "BUG: keyboard-only config should still produce a tooltip (guard ignores globalKeyBindings)")
assert(FindLine("F", "Rejuvenation"),
    "keyboard-key binding should appear in the keyboard-only tooltip")

print("OK: groupframes_clickcast_tooltip_test")
