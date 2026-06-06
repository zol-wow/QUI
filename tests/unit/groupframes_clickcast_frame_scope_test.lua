-- tests/unit/groupframes_clickcast_frame_scope_test.lua
-- Run: lua tests/unit/groupframes_clickcast_frame_scope_test.lua
--
-- Keyboard click-cast must only intercept keys while the cursor is over a
-- REGISTERED click-cast frame (group/unit frames). The caster's mouseoverstate
-- driver fires on [@mouseover,exists], which is also true for nameplate and
-- 3D world-unit hover -- those must NOT bind the keys (the action bar keeps
-- them). The driver snippet therefore gates on "a registered frame is under
-- the cursor" via the caster's frame refs, and the secure OnEnter/OnLeave
-- wraps bind/clear the caster instantly for direct unit<->frame transitions
-- the driver never re-fires on (its state stays "on").

local inCombat = false
local function noop() end

local SPELL_NAMES = { [774] = "Rejuvenation" }
local NAME_TO_ID  = { Rejuvenation = 774 }

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

-- Keyboard-only config: no scroll-wheel or mouse bindings, so the hover wraps
-- must be installed for the keyboard path on its own.
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

local caster = assert(_G.QUI_ClickCastCaster, "caster button should exist for keyboard binding")
local loader = loadstring or load

-- Run the caster's mouseoverstate driver snippet with newstate "on"/"off"
-- (simulates a unit coming under / leaving the cursor).
local function runCasterState(state)
    local snippet = assert(caster:GetAttribute("_onstate-mouseoverstate"))
    assert(loader("local self, newstate = ...\n" .. snippet))(caster, state)
end

-- Run a frame's secure wrap pre-body (self = frame, owner = wrap header).
local function runWrap(frame, script)
    local wrap = frame.secureWraps[script]
    assert(wrap, "frame should have a secure " .. script .. " wrap for keyboard click-cast")
    assert(loader("local self, owner = ...\n" .. wrap.preBody))(frame, wrap.header)
end

---------------------------------------------------------------------------
-- Setup invariants: the registered frame is published to the caster so the
-- secure driver snippet can test "is the cursor over a click-cast frame".
---------------------------------------------------------------------------
assert((caster:GetAttribute("cc-framecount") or 0) >= 1,
    "BUG: registered frames were not published to the caster (frame-hover gate has nothing to check)")
local ref = caster.frameRefs["cc-frame1"]
assert(ref == child, "BUG: caster frame ref should point at the registered frame")

---------------------------------------------------------------------------
-- Scenario 1 (THE regression): @mouseover exists but the cursor is NOT over
-- any registered frame -- a nameplate or 3D world unit. Keys must NOT bind;
-- the action bar keeps them.
---------------------------------------------------------------------------
child.underMouse = false
runCasterState("on")
assert(not caster.overrideBindings.F,
    "BUG: nameplate/world @mouseover bound the click-cast key -- it must only bind over registered frames")
print("OK: nameplate/world mouseover does not bind keyboard click-cast")

---------------------------------------------------------------------------
-- Scenario 2: cursor over a registered, visible frame -> the key binds.
---------------------------------------------------------------------------
child.underMouse = true
runCasterState("on")
local b = caster.overrideBindings.F
assert(b and b.button == "keyf",
    "BUG: hovering a registered frame must bind the click-cast key to the caster")
print("OK: registered-frame mouseover binds keyboard click-cast")

---------------------------------------------------------------------------
-- Scenario 3: driver "off" (no mouseover unit) releases the key.
---------------------------------------------------------------------------
runCasterState("off")
assert(not caster.overrideBindings.F,
    "off @mouseover the caster must release the key so the action bar keybind fires")
print("OK: mouseover gone releases the key")

---------------------------------------------------------------------------
-- Scenario 4: a hidden frame under the cursor does not count (its rect can
-- linger where the cursor is while a nameplate has the actual mouseover).
---------------------------------------------------------------------------
child.underMouse = true
child.visible = false
runCasterState("on")
assert(not caster.overrideBindings.F,
    "BUG: a hidden frame's rect must not satisfy the frame-hover gate")
child.visible = nil
runCasterState("off")
print("OK: hidden frames do not satisfy the frame-hover gate")

---------------------------------------------------------------------------
-- Scenario 5: direct nameplate->frame transition. The driver state stays "on"
-- (no off tick between units) so it never re-fires; the frame's secure OnEnter
-- wrap must bind the caster keys instantly.
---------------------------------------------------------------------------
child.underMouse = false
runCasterState("on")              -- hovering the nameplate: no bind
assert(not caster.overrideBindings.F, "precondition: nameplate hover left keys unbound")
child.underMouse = true
runWrap(child, "OnEnter")         -- cursor slides onto the frame, driver silent
assert(caster.overrideBindings.F and caster.overrideBindings.F.button == "keyf",
    "BUG: direct unit->frame transition must bind via the secure OnEnter wrap (driver never re-fires)")
print("OK: secure OnEnter wrap binds instantly on direct unit->frame transitions")

---------------------------------------------------------------------------
-- Scenario 6: direct frame->nameplate transition. Driver still "on"; the
-- frame's secure OnLeave wrap must release the keys so the nameplate hover
-- falls through to the action bar.
---------------------------------------------------------------------------
child.underMouse = false
runWrap(child, "OnLeave")
assert(not caster.overrideBindings.F,
    "BUG: direct frame->unit transition must release the keys via the secure OnLeave wrap")
print("OK: secure OnLeave wrap releases instantly on direct frame->unit transitions")

print("OK: groupframes_clickcast_frame_scope_test")
