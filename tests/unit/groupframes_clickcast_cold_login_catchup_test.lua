-- tests/unit/groupframes_clickcast_cold_login_catchup_test.lua
-- Run: lua tests/unit/groupframes_clickcast_cold_login_catchup_test.lua
--
-- Cold-login race: spec/loadout data arrives asynchronously AFTER
-- PLAYER_ENTERING_WORLD, so the first binding resolve comes up empty and the
-- secure header is left at keycount 0 (keyboard dead) while mouse attributes
-- still apply. A single fixed-delay catch-up loses this race and nothing re-runs
-- it. The startup catch-up must keep retrying until the active binding table
-- actually resolves -- the way an in-world /reload (spec data already cached)
-- gets it right on the first pass.

local inCombat = false
local function noop() end
local SPELL_NAMES = { [774] = "Rejuvenation" }
local NAME_TO_ID  = { Rejuvenation = 774 }
local specReady = false  -- cold login: spec data not ready yet

local frameMT
local createdFrames = {}
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
            elseif key == "UnregisterEvent" then
                return function(self, e) self.events[e] = nil end
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
    createdFrames[#createdFrames + 1] = f
    if name then _G[name] = f end
    return f
end

function InCombatLockdown() return inCombat end
function UnitClass() return "Druid", "DRUID" end
function UnitIsDeadOrGhost() return false end
function UnitIsConnected() return true end
function UnitIsPlayer() return true end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return specReady and 102 or nil end  -- nil => spec data not ready
function SecureHandlerWrapScript(frame, script, header, preBody)
    frame.secureWraps[script] = { header = header, preBody = preBody }
end
-- Native ping-binding migration stubs hit on PLAYER_ENTERING_WORLD.
function GetBindingKey() return nil end
function SetBinding() return true end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
GameTooltip = { GetOwner = function() return nil end, AddLine = noop, AddDoubleLine = noop, Show = noop }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- Controllable timer: C_Timer.After queues callbacks; flushAfter() runs the
-- batch currently queued (retries scheduled during the flush land in the next).
local afterQueue = {}
C_Timer = {
    After = function(_, fn) afterQueue[#afterQueue + 1] = fn end,
    NewTimer = function(_, fn) local t = { fn = fn }; function t:Cancel() self.cancelled = true end return t end,
}
local function flushAfter()
    local batch = afterQueue
    afterQueue = {}
    for _, fn in ipairs(batch) do fn() end
end

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

-- perSpec bindings stored under spec 102, with NO shared cc.bindings fallback,
-- so the resolve is empty until GetSpecializationInfo() returns the spec.
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
assert(ns.QUI_GroupFrameClickCast, "clickcast module should expose its API")

-- Locate the module's event frame (the one that listens for PLAYER_ENTERING_WORLD).
local eventFrame
for _, f in ipairs(createdFrames) do
    if f.events and f.events["PLAYER_ENTERING_WORLD"] and f.scripts and f.scripts.OnEvent then
        eventFrame = f
        break
    end
end
assert(eventFrame, "could not find clickcast event frame")

-- Cold login: PLAYER_ENTERING_WORLD fires while spec data is NOT ready.
specReady = false
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")

-- The catch-up fires while the spec is still unresolved -> empty resolve.
flushAfter()
local hdr = assert(_G.QUI_ClickCastHeader, "binding header should exist after the first catch-up")

-- Spec data lands a moment later; drain the remaining scheduled retries.
specReady = true
for _ = 1, 12 do
    if #afterQueue == 0 then break end
    flushAfter()
end

-- Keyboard click-cast must now be applied (header + frame in sync, hover binds).
assert(hdr:GetAttribute("clickcast-keycount") == 1,
    "BUG: header keycount = " .. tostring(hdr:GetAttribute("clickcast-keycount"))
    .. " -- startup catch-up did not re-resolve after spec data became ready")

local wrap = assert(child.secureWraps.OnEnter,
    "BUG: frame was never keyboard-wrapped after spec data became ready")
child.overrideBindings = {}
local loader = loadstring or load
assert(loader("local self, owner = ...\n" .. wrap.preBody))(child, wrap.header)
assert(wrap.header.overrideBindings.F and wrap.header.overrideBindings.F.button == "keyf",
    "BUG: hovering binds nothing -- keyboard click-cast still dead after cold login")

print("OK: groupframes_clickcast_cold_login_catchup_test")
