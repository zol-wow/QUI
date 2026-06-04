-- tests/unit/groupframes_clickcast_slow_cold_login_test.lua
-- Run: lua tests/unit/groupframes_clickcast_slow_cold_login_test.lua
--
-- SLOW cold login: the startup catch-up's bounded retry can be exhausted before
-- spec/loadout data lands (slow realm/disk/first login), leaving the secure
-- header at keycount 0 (keyboard click-cast dead) until /reload or a respec.
-- The companion cold_login_catchup_test only covers the FAST case (data lands
-- within the first dozen attempts). This file covers the two gaps:
--   A) spec data lands AFTER the old 12-attempt cap -> retry tail must still catch it
--   B) spec data lands AFTER the whole retry ladder is exhausted -> the
--      PLAYER_TALENT_UPDATE / ACTIVE_PLAYER_SPECIALIZATION_CHANGED "data ready"
--      signal must re-resolve and bring keyboard binds alive
--   C) once resolved, those signals must NOT churn (no redundant refresh)

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
local function loadModule(initialSpecReady)
    inCombat = false
    specReady = initialSpecReady
    createdFrames = {}
    afterQueue = {}
    _G.QUI_ClickCastHeader = nil
    _G.QUI.db.char.clickCast = DeepCopy(BASE_CLICKCAST)

    local child = NewFrame("Button", "QUI_TestUnit1", nil, "SecureUnitButtonTemplate")
    local partyHeader = NewFrame("Frame", "QUI_TestPartyHeader", nil, "SecureGroupHeaderTemplate")
    partyHeader.attributes["child1"] = child
    ns.QUI_GroupFrames = {
        headers = { party = partyHeader, raid = false, self = false },
        raidGroupHeaders = {},
    }

    assert(loadfile("modules/groupframes/groupframes_clickcast.lua"))("QUI", ns)
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

local function keycount()
    local hdr = _G.QUI_ClickCastHeader
    return hdr and hdr:GetAttribute("clickcast-keycount") or nil
end

local function drain(maxTicks)
    for _ = 1, maxTicks do
        if #afterQueue == 0 then break end
        flushAfter()
    end
end

---------------------------------------------------------------------------
-- Scenario A: spec data lands AFTER the old 12-attempt cap.
-- The retry tail must keep going long enough to catch it.
---------------------------------------------------------------------------
do
    local eventFrame = loadModule(false)
    -- Cold login (isInitialLogin = true): PEW while spec data is NOT ready.
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD", true, false)

    -- Slow boot: spec stays unresolved well past the old 12-attempt cap.
    -- (Old code stops scheduling at attempt 12, so the queue empties early.)
    for _ = 1, 14 do
        if #afterQueue == 0 then break end
        flushAfter()
    end

    -- Spec data finally lands; drain whatever retries are still scheduled.
    specReady = true
    drain(30)

    assert(keycount() == 1,
        "BUG: header keycount = " .. tostring(keycount())
        .. " -- retry gave up before slow spec data landed (past the 12-attempt cap)")
    print("OK: slow-boot retry tail catches late spec data")
end

---------------------------------------------------------------------------
-- Scenario B: spec data lands ONLY AFTER the whole retry ladder is exhausted.
-- The PLAYER_TALENT_UPDATE data-ready signal must re-resolve and revive binds.
---------------------------------------------------------------------------
do
    local eventFrame = loadModule(false)
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD", true, false)

    -- Run the entire retry ladder to exhaustion with spec never becoming ready.
    drain(100)
    assert(#afterQueue == 0, "retry ladder should be exhausted (bounded)")
    assert(keycount() == 0, "precondition: keyboard still dead while spec unresolved")

    -- Much later the client populates spec/talent data and signals it.
    specReady = true
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_TALENT_UPDATE")
    assert(#afterQueue >= 1,
        "BUG: PLAYER_TALENT_UPDATE did not schedule a re-resolve after the retry gave up")
    flushAfter()

    assert(keycount() == 1,
        "BUG: header keycount = " .. tostring(keycount())
        .. " -- data-ready signal failed to revive keyboard click-cast")
    print("OK: PLAYER_TALENT_UPDATE revives keyboard binds after retry exhaustion")

    ---------------------------------------------------------------------------
    -- Scenario C: now that bindings are resolved, the data-ready signal must be
    -- a no-op (no redundant refresh churn on the frequent PLAYER_TALENT_UPDATE).
    ---------------------------------------------------------------------------
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_TALENT_UPDATE")
    assert(#afterQueue == 0,
        "BUG: resolved state still scheduled a redundant refresh on PLAYER_TALENT_UPDATE")
    print("OK: data-ready signal does not churn once resolved")
end

print("OK: groupframes_clickcast_slow_cold_login_test")
