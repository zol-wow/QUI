-- tests/unit/groupframes_clickcast_slow_cold_login_test.lua
-- Run: lua tests/unit/groupframes_clickcast_slow_cold_login_test.lua
--
-- SLOW cold login: the startup catch-up's bounded retry can be exhausted before
-- spec/loadout data lands (slow realm/disk/first login), leaving the secure
-- header at keycount 0 (keyboard click-cast dead) until /reload or a respec.
-- The companion cold_login_catchup_test only covers the FAST case (data lands
-- within the retry window). This file covers recovery AFTER the retry gives up,
-- via the two catch-alls:
--   1) PLAYER_TALENT_UPDATE / ACTIVE_PLAYER_SPECIALIZATION_CHANGED (proactive)
--   2) the on-hover deferred re-resolve (on demand, when the user reaches for the
--      keybind -- the frame is provably present at that point)
--   3) once resolved, neither catch-all churns (no redundant refresh)

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
function GetSpecializationInfo() return specReady and 102 or 0 end  -- 0 => spec data not ready
function RegisterStateDriver() end
function UnregisterStateDriver() end
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
-- NOTE: C_Timer.NewTimer callbacks are never fired here, so production code that
-- must be reachable from a unit test has to schedule via C_Timer.After.
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

_G.QUI = { db = { char = {}, profile = {} } }

-- perSpec bindings stored under spec 102, with NO shared cc.bindings fallback,
-- so the resolve is empty until GetSpecializationInfo() returns the spec.
local BASE_CLICKCAST = {
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
}

-- Reset all cross-load state and load the click-cast module fresh, returning the
-- module's event frame plus the party child frame and header. Each call is an
-- independent "session" (module upvalues reset because loadfile re-runs the chunk).
local function loadModule(initialSpecReady, clickCast)
    inCombat = false
    specReady = initialSpecReady
    createdFrames = {}
    afterQueue = {}
    _G.QUI_ClickCastHeader = nil
    _G.QUI_ClickCastCaster = nil
    _G.QUI.db.char.clickCast = DeepCopy(clickCast or BASE_CLICKCAST)

    local child = NewFrame("Button", "QUI_TestUnit1", nil, "SecureUnitButtonTemplate")
    local partyHeader = NewFrame("Frame", "QUI_TestPartyHeader", nil, "SecureGroupHeaderTemplate")
    partyHeader.attributes["child1"] = child
    ns.QUI_GroupFrames = {
        headers = { party = partyHeader, raid = false, self = false },
        raidGroupHeaders = {},
    }

    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
    assert(ns.QUI_GroupFrameClickCast, "clickcast module should expose its API")

    local eventFrame
    for _, f in ipairs(createdFrames) do
        if f.events and f.events["PLAYER_ENTERING_WORLD"] and f.scripts and f.scripts.OnEvent then
            eventFrame = f
            break
        end
    end
    assert(eventFrame, "could not find clickcast event frame")
    return eventFrame, child, partyHeader
end

-- Keyboard keys are PUBLISHED to the global caster (QUI_ClickCastCaster); a
-- mouseoverstate state driver binds them only while @mouseover exists. This
-- reports how many keys are published (resolved + applied), i.e. ready to bind.
local function casterKeyCount()
    local c = _G.QUI_ClickCastCaster
    return (c and c:GetAttribute("cc-keycount")) or 0
end

-- Run the caster's mouseoverstate state-driver snippet with newstate "on"/"off"
-- (simulates a unit coming under / leaving the cursor).
local function runCasterState(state)
    local c = _G.QUI_ClickCastCaster
    if not c then return end
    local snippet = c:GetAttribute("_onstate-mouseoverstate")
    if not snippet then return end
    local loader = loadstring or load
    assert(loader("local self, newstate = ...\n" .. snippet))(c, state)
end

local function drain(maxTicks)
    for _ = 1, maxTicks do
        if #afterQueue == 0 then break end
        flushAfter()
    end
end

-- Fire a frame's insecure OnEnter HookScript(s) -- simulates the player hovering.
local function hover(frame)
    for _, h in ipairs(frame.hooks.OnEnter or {}) do h(frame) end
end

-- Assert key "F" hovercasts: the state driver binds it to the caster (with an
-- @mouseover macro) while a unit is under the cursor AND the cursor is over a
-- registered click-cast frame, and releases it otherwise so the action bar's
-- own keybind fires off-frame (including over nameplates / world units).
local function assertCasterBindsF()
    local c = assert(_G.QUI_ClickCastCaster, "caster button was never created")
    local mt = c:GetAttribute("macrotext-keyf")
    assert(mt and mt:find("@mouseover", 1, true), "caster macro for F missing @mouseover cast")
    local hoverFrame = c.frameRefs and c.frameRefs["cc-frame1"]
    assert(hoverFrame, "registered frames were never published to the caster's frame-hover gate")
    hoverFrame.underMouse = true
    runCasterState("on")
    local b = c.overrideBindings and c.overrideBindings.F
    assert(b and b.button == "keyf", "@mouseover did not bind F to the caster -- click-cast dead")
    runCasterState("off")
    assert(not (c.overrideBindings and c.overrideBindings.F),
        "off @mouseover the caster must release F so the action bar keybind fires")
    hoverFrame.underMouse = nil
end

---------------------------------------------------------------------------
-- Scenario 1: spec data lands AFTER the startup retry is exhausted, and the
-- client fires PLAYER_TALENT_UPDATE. The proactive data-ready handler must
-- re-resolve and (re)bind the key to the caster.
---------------------------------------------------------------------------
do
    local eventFrame = loadModule(false)
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")

    drain(100)  -- exhaust the bounded startup retry with spec never ready
    assert(#afterQueue == 0, "startup retry should be bounded/exhausted")
    assert(casterKeyCount() == 0, "precondition: keyboard still dead while spec unresolved")

    specReady = true
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_TALENT_UPDATE")
    assert(#afterQueue >= 1, "PLAYER_TALENT_UPDATE should schedule a re-resolve")
    flushAfter()

    assert(casterKeyCount() == 1, "caster keycount = " .. casterKeyCount()
        .. " -- data-ready signal failed to revive keyboard click-cast")
    assertCasterBindsF()
    print("OK: PLAYER_TALENT_UPDATE revives keyboard binds after retry exhaustion")
end

---------------------------------------------------------------------------
-- Scenario 2: spec data lands after the retry is exhausted and NO data-ready
-- event fires. When the user HOVERS a frame, the on-hover trigger must
-- re-resolve on demand and bind the key to the caster.
---------------------------------------------------------------------------
do
    local eventFrame, child = loadModule(false)
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")

    drain(100)
    assert(#afterQueue == 0, "startup retry should be bounded/exhausted")
    assert(casterKeyCount() == 0, "precondition: keyboard still dead while spec unresolved")
    assert(child.hooks.OnEnter and #child.hooks.OnEnter > 0,
        "precondition: insecure OnEnter hook installed during registration")

    specReady = true
    hover(child)
    assert(#afterQueue >= 1, "BUG: hovering a still-dead frame scheduled no recovery re-resolve")
    flushAfter()

    assert(casterKeyCount() == 1, "on-hover trigger failed to revive keyboard click-cast")
    assertCasterBindsF()
    print("OK: on-hover trigger revives keyboard binds on demand")

    -----------------------------------------------------------------------
    -- Scenario 3: now resolved -- neither a hover nor a data-ready event may
    -- schedule a redundant refresh.
    -----------------------------------------------------------------------
    hover(child)
    assert(#afterQueue == 0, "BUG: resolved state still scheduled a refresh on hover")
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_TALENT_UPDATE")
    assert(#afterQueue == 0, "BUG: resolved state still scheduled a refresh on PLAYER_TALENT_UPDATE")
    print("OK: recovery triggers do not churn once resolved")
end

---------------------------------------------------------------------------
-- Scenario 4: GetSpecializationInfo returns specId 0 while the active spec is
-- unresolved. A shared/legacy mouse binding present during that cold window must
-- NOT make the recovery guard treat startup as done -- the per-spec keyboard key
-- still has to bind once data lands.
---------------------------------------------------------------------------
do
    local clickCast = DeepCopy(BASE_CLICKCAST)
    clickCast.bindings = {
        { button = "LeftButton", modifiers = "", actionType = "spell",
          spell = "Rejuvenation", spellID = 774 },
    }

    local eventFrame, child = loadModule(false, clickCast)
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")

    drain(100)
    assert(#afterQueue == 0, "startup retry should be bounded/exhausted")
    assert(casterKeyCount() == 0,
        "precondition: shared mouse fallback must not count as keyboard readiness")

    specReady = true
    hover(child)
    assert(#afterQueue >= 1,
        "BUG: shared mouse fallback masked unresolved per-spec keyboard bindings")
    flushAfter()

    assert(casterKeyCount() == 1,
        "per-spec keyboard bindings were not revived after spec data arrived")
    assertCasterBindsF()
    print("OK: shared mouse fallback does not mask cold per-spec keyboard recovery")
end

---------------------------------------------------------------------------
-- Scenario 5: DURABLE recovery across a combat window. Spec data lands while
-- IN COMBAT and the player hovers to use the keybind mid-fight. The on-hover
-- re-resolve can't run in combat, but it must leave a pending request so
-- PLAYER_REGEN_ENABLED binds the caster the instant combat ends.
---------------------------------------------------------------------------
do
    local eventFrame, child = loadModule(false)
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")

    drain(100)
    assert(#afterQueue == 0, "startup retry should be bounded/exhausted")
    assert(casterKeyCount() == 0, "precondition: keyboard still dead while spec unresolved")

    inCombat = true
    specReady = true
    hover(child)
    assert(#afterQueue >= 1, "hovering a still-dead frame scheduled no recovery")
    flushAfter()  -- runs in combat: must not mutate secure attrs, must not drop

    assert(casterKeyCount() == 0, "precondition: secure rebuild cannot happen mid-combat")

    inCombat = false
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    flushAfter()

    assert(casterKeyCount() == 1, "caster keycount = " .. casterKeyCount()
        .. " -- combat-window recovery was dropped (needs /reload)")
    assertCasterBindsF()
    print("OK: combat-window recovery is durable (revives on PLAYER_REGEN_ENABLED)")
end

---------------------------------------------------------------------------
-- Scenario 6: state-driver hovercast — the action bar keeps its own keybind, and
-- click-cast only intercepts the key while a unit is under the cursor. So off a
-- frame the real action-bar ability fires (the caster has RELEASED the key); on a
-- frame the @mouseover cast fires. No /click chaining, no unconditional clause.
---------------------------------------------------------------------------
do
    local eventFrame = loadModule(true)  -- spec ready on login
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
    drain(100)

    assertCasterBindsF()  -- binds F on @mouseover, releases it off @mouseover

    local mt = _G.QUI_ClickCastCaster:GetAttribute("macrotext-keyf")
    assert(mt:find("@mouseover", 1, true), "caster macro should be an @mouseover cast")
    assert(not mt:find("/click", 1, true),
        "must not chain /click into the bar (nested protected action, combat-unsafe)")

    -- Off @mouseover, F must NOT be bound on the caster, so the action bar's own
    -- keybind for F is what fires.
    runCasterState("off")
    assert(not (_G.QUI_ClickCastCaster.overrideBindings or {}).F,
        "off @mouseover the caster must leave F free for the action bar keybind")
    print("OK: caster hovercasts on @mouseover, releases off it so the action bar keybind fires")
end

print("OK: groupframes_clickcast_slow_cold_login_test")
