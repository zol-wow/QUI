-- tests/unit/groupframes_clickcast_frame_scope_test.lua
-- Run: lua tests/unit/groupframes_clickcast_frame_scope_test.lua
--
-- Keyboard click-cast must only intercept keys while the cursor is over a
-- REGISTERED click-cast frame (group/unit frames). Binding is edge-driven: the
-- secure OnEnter wrap (which exists ONLY on registered frames) binds the key to
-- the caster, and OnLeave/OnHide release it. A nameplate or 3D world-unit hover
-- has no wrap, so it can never bind the key -- the action bar keeps it, by
-- construction. The header's [@mouseover,exists] attribute driver is a clear-ONLY
-- safety net (DANGLING_SNIPPET): on the false edge it releases a stale override
-- only when geometry (GetMousePosition) proves the cursor left the last-entered
-- frame, so a churning mouseover token can't strand the key.

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
            elseif key == "GetMousePosition" then
                -- Restricted HANDLE:GetMousePosition -- cursor normalized into the
                -- frame's own rect; nil when outside the bounds or the rect is
                -- unresolved. self.underMouse drives "inside".
                return function(self)
                    if self.underMouse == true then return 0.5, 0.5 end
                    return nil
                end
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
function RegisterAttributeDriver() end
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

assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast)

GFCC:Initialize()
GFCC:RegisterAllFrames()

local caster = assert(_G.QUI_ClickCastCaster, "caster button should exist for keyboard binding")
local header = assert(_G.QUI_ClickCastHeader, "binding header should exist")
local loader = loadstring or load

-- Run a frame's secure wrap pre-body (self = frame, owner = wrap header). The
-- wraps run in the header's managed environment, so currentHoverFrame is shared
-- with the dangling net below -- here, both share the test's global table.
local function runWrap(frame, script)
    local wrap = frame.secureWraps[script]
    assert(wrap, "frame should have a secure " .. script .. " wrap for keyboard click-cast")
    assert(loader("local self, owner = ...\n" .. wrap.preBody))(frame, wrap.header)
end

-- Run the header's clear-only dangling net (self = header, name/value). Fires
-- when [@mouseover,exists] drops to false.
local function runDangling()
    local snippet = assert(header:GetAttribute("_onattributechanged"),
        "header should carry the dangling _onattributechanged snippet")
    assert(loader("local self, name, value = ...\n" .. snippet))(header, "cc-hasunit", "false")
end

---------------------------------------------------------------------------
-- Setup invariants: the registered frame carries the secure OnEnter/OnLeave/
-- OnHide wraps (the bind/clear edges), and the header carries the clear-only
-- dangling net. There is NO caster-side frame-hover gate any more.
---------------------------------------------------------------------------
assert(child.secureWraps["OnEnter"] and child.secureWraps["OnLeave"],
    "BUG: registered frame missing the secure hover wraps that bind keyboard click-cast")
assert(header:GetAttribute("_onattributechanged"),
    "BUG: header missing the dangling safety-net snippet")

---------------------------------------------------------------------------
-- Scenario 1 (THE regression): @mouseover exists but the cursor is NOT over a
-- registered frame -- a nameplate or 3D world unit. Such a hover fires no
-- OnEnter on any registered frame, so nothing binds: the key stays on the
-- action bar by construction (no driver can arm it off-frame).
---------------------------------------------------------------------------
assert(not caster.overrideBindings.F,
    "BUG: a key was bound with nothing hovered -- only an OnEnter over a registered frame may bind")
print("OK: nameplate/world mouseover cannot bind keyboard click-cast (no wrap, no bind)")

---------------------------------------------------------------------------
-- Scenario 2: cursor over a registered, visible frame -> OnEnter binds the key.
---------------------------------------------------------------------------
child.underMouse = true
runWrap(child, "OnEnter")
local b = caster.overrideBindings.F
assert(b and b.button == "keyf",
    "BUG: hovering a registered frame must bind the click-cast key to the caster")
print("OK: registered-frame OnEnter binds keyboard click-cast")

---------------------------------------------------------------------------
-- Scenario 3a: a transient mouseover-token churn while the cursor is STILL over
-- the frame (the [@mouseover,exists] driver is mouseover-blind, re-sampled on a
-- 0.2s tick) must NOT release the key. The dangling net checks geometry and
-- keeps the binding -- this is what un-strands the key.
---------------------------------------------------------------------------
runDangling()                  -- child.underMouse still true (cursor inside)
assert(caster.overrideBindings.F and caster.overrideBindings.F.button == "keyf",
    "BUG: a false-edge while the cursor is still over the frame must keep the key (no stranding)")
print("OK: dangling net keeps the key while the cursor is still over the frame")

---------------------------------------------------------------------------
-- Scenario 3b: the false edge once the cursor has truly left the frame releases
-- the key so the action bar keybind fires again.
---------------------------------------------------------------------------
child.underMouse = false
runDangling()
assert(not caster.overrideBindings.F,
    "false edge with the cursor off the frame must release the key so the action bar keybind fires")
print("OK: dangling net releases the key once the cursor has left the frame")

---------------------------------------------------------------------------
-- Scenario 4: a hidden frame must not keep the key. Re-arm, hide the frame,
-- then run the dangling net: even though the cursor rect still reports inside,
-- IsVisible() == false forces the release.
---------------------------------------------------------------------------
child.underMouse = true
runWrap(child, "OnEnter")
assert(caster.overrideBindings.F, "precondition: re-hovering rebinds the key")
child.visible = false
runDangling()
assert(not caster.overrideBindings.F,
    "BUG: a hidden frame must release the key even with the cursor rect still inside")
child.visible = nil
print("OK: dangling net releases the key when the frame is hidden")

---------------------------------------------------------------------------
-- Scenario 5: direct nameplate->frame transition. No driver re-fires between
-- units, so the frame's secure OnEnter wrap is the sole mechanism that binds.
---------------------------------------------------------------------------
assert(not caster.overrideBindings.F, "precondition: key unbound after Scenario 4")
child.underMouse = true
runWrap(child, "OnEnter")         -- cursor slides onto the frame
assert(caster.overrideBindings.F and caster.overrideBindings.F.button == "keyf",
    "BUG: direct unit->frame transition must bind via the secure OnEnter wrap")
print("OK: secure OnEnter wrap binds instantly on direct unit->frame transitions")

---------------------------------------------------------------------------
-- Scenario 6: direct frame->nameplate transition. The frame's secure OnLeave
-- wrap must release the keys so the nameplate hover falls to the action bar.
---------------------------------------------------------------------------
child.underMouse = false
runWrap(child, "OnLeave")
assert(not caster.overrideBindings.F,
    "BUG: direct frame->unit transition must release the keys via the secure OnLeave wrap")
print("OK: secure OnLeave wrap releases instantly on direct frame->unit transitions")

print("OK: groupframes_clickcast_frame_scope_test")
